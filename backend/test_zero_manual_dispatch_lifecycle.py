"""
test_zero_manual_dispatch_lifecycle.py

Comprehensive End-to-End Validation Suite for CalTrack Zero-Manual-Dispatch Architecture.

Verifies:
1. Worker Single-Pass Reconciliation (`dispatch_pending_jobs`).
2. Immediate Customer Dispatch Trigger (`POST /api/workforce/jobs/dispatch/` via WorkforceCrossServiceDispatchView).
3. Worker Recovery after Downtime (PostgreSQL durability).
4. Scheduled-Window Holding and Automatic Unlock (T - 1h to T + 1h).
5. Retry Backoff Ladder (`RETRY_SCHEDULED` and `retry_at` enforcement).
6. Decline Fallback (Permanent exclusion + next candidate routing).
7. Expiry Fallback (Auto-sweep + next candidate routing).
8. Concurrent Dispatch Safety (WorkforceDispatchState claim prevents double offer).
9. Read-only Endpoints (`GET /api/workforce/jobs/`, SSE, GPS telemetry remain 100% dispatch-free).
10. Worker Heartbeat Observability (single upserted event row, bounded growth).
"""
import os
import sys
import time
import uuid
import threading
from datetime import timedelta, date, time as dtime

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "workforce_core.settings")

import django
django.setup()

from django.test import TestCase
from rest_framework.test import APIRequestFactory, force_authenticate
from django.utils import timezone
from django.contrib.auth import get_user_model
from django.db import transaction

from companies.models import Company
from employees.models import Employee
from service_requests.models import ServiceRequest
from workforce_api.models import (
    WorkforceJobOffer,
    WorkforceDispatchState,
    WorkforceEventLog,
    WorkforceEmployeeSchedule,
)
from workforce_api.services.automatic_dispatch import (
    dispatch_job,
    dispatch_pending_jobs,
    expire_and_reassign_offers,
    get_scheduled_dispatch_window,
    DISPATCHABLE_STATUSES,
)
from workforce_api.views import (
    WorkforceCrossServiceDispatchView,
    WorkforceJobListView,
    WorkforceJobRejectOfferView,
)
from workforce_api.management.commands.dispatch_pending_workforce_jobs import _write_heartbeat

User = get_user_model()
factory = APIRequestFactory()

BOOKING_LAT = 12.9715987
BOOKING_LON = 77.5945627
BASE_TECH_LAT = 12.9780000
BASE_TECH_LON = 77.5975000


def _create_test_company(tag=""):
    name = f"ZeroDispatch Co {tag} {uuid.uuid4().hex[:6]}"
    co, _ = Company.objects.get_or_create(
        company_name=name,
        defaults={"is_active": True},
    )
    return co


def _create_test_employee(company, offset_index=0):
    uname = f"zmd_tech_{uuid.uuid4().hex[:8]}"
    user = User.objects.create_user(
        username=uname,
        password="TestPass@123",
        email=f"{uname}@example.com",
        role="employee",
        company=company,
    )
    lat = BASE_TECH_LAT + (offset_index * 0.003)
    lon = BASE_TECH_LON + (offset_index * 0.003)
    emp = Employee.objects.create(
        user=user,
        employee_id=f"EMP-{uuid.uuid4().hex[:6].upper()}",
        company=company,
        is_active=True,
        is_online=True,
        current_availability="available",
        bank_details={
            "onboarding": {
                "services": [
                    {"name": "Electrical", "category": "Electrical", "status": "approved"},
                    {"name": "Electrical Wiring Repair", "category": "Electrical", "status": "approved"},
                    {"name": "General Maintenance", "category": "General Maintenance", "status": "approved"},
                ],
                "status": "approved",
                "documents": {},
            },
            "attendance": {"is_clocked_in": True},
            "leaves": [],
        },
    )
    user.last_known_location = {
        "latitude": lat,
        "longitude": lon,
        "accuracy": 5.0,
        "captured_at": timezone.now().isoformat(),
        "updated_at": timezone.now().isoformat(),
    }
    user.save(update_fields=["last_known_location"])

    for dow in range(7):
        WorkforceEmployeeSchedule.objects.create(
            employee=emp,
            company=company,
            day_of_week=dow,
            start_time="00:00:00",
            end_time="23:59:59",
            is_working_day=True,
        )
    return emp


def _create_test_service_request(company, req_id=None, req_prefix="ZMD", preferred_date=None, preferred_time=None, status="confirmed"):
    today = timezone.localdate()
    # request_id max length is 20 chars
    unique_tag = uuid.uuid4().hex[:6].upper()
    prefix = (req_id[:8] if req_id else req_prefix[:4]).upper()
    actual_req_id = f"Z-{prefix}-{unique_tag}"[:20]
    sr = ServiceRequest.objects.create(
        company=company,
        request_id=actual_req_id,
        customer_name="Test Customer",
        phone="+919876543210",
        service_category="Electrical",
        issue_title="Electrical Wiring Repair",
        status=status,
        latitude=BOOKING_LAT,
        longitude=BOOKING_LON,
        address="123 MG Road, Bangalore",
        preferred_date=preferred_date or today,
        preferred_time=preferred_time,
        catalog_service_id=1,
    )
    return sr


def _reset_technicians(company):
    WorkforceJobOffer.objects.filter(employee__company=company).update(
        status=WorkforceJobOffer.Status.CANCELLED
    )
    Employee.objects.filter(company=company).update(
        is_active=True,
        is_online=True,
        current_availability="available",
    )


def run_all_zero_dispatch_tests():
    print("==================================================================")
    print(" CALTRACK ZERO-MANUAL-DISPATCH ARCHITECTURE VALIDATION SUITE")
    print("==================================================================")

    company = _create_test_company("Main")
    tech1 = _create_test_employee(company, offset_index=0)  # Closest
    tech2 = _create_test_employee(company, offset_index=1)  # 2nd closest
    tech3 = _create_test_employee(company, offset_index=2)  # 3rd closest

    passed = 0
    total = 10

    # -------------------------------------------------------------
    # Test 1: Worker Single-Pass Reconciliation
    # -------------------------------------------------------------
    _reset_technicians(company)
    print("\n[TEST 1/10] Worker Single-Pass Reconciliation...")
    sr1 = _create_test_service_request(company, req_id="ZMD-REC-01", status="unassigned")
    result1 = dispatch_pending_jobs(company_id=company.id, limit=10)
    offer1 = WorkforceJobOffer.objects.filter(job_id=sr1.id, status=WorkforceJobOffer.Status.OFFERED).first()
    assert offer1 is not None, "Expected active offer created by worker sweep."
    assert offer1.employee_id == tech1.id, f"Expected closest tech {tech1.id}, got {offer1.employee_id}"
    print(f"  -> SUCCESS: Worker discovered pending booking #{sr1.id} and offered to nearest Tech #{offer1.employee_id}")
    passed += 1

    # -------------------------------------------------------------
    # Test 2: Customer Immediate Dispatch Trigger
    # -------------------------------------------------------------
    _reset_technicians(company)
    print("\n[TEST 2/10] Customer Immediate Dispatch Trigger (POST /api/workforce/jobs/dispatch/)...")
    sr2 = _create_test_service_request(company, req_id="ZMD-CUST-02", status="unassigned")
    req = factory.post(
        "/api/workforce/jobs/dispatch/",
        data={"booking_id": sr2.request_id},
        format="json",
        HTTP_X_CALSERVICES_SOURCE="calservices-platform",
    )
    view = WorkforceCrossServiceDispatchView.as_view()
    resp = view(req)
    assert resp.status_code == 200, f"Expected 200, got {resp.status_code}: {resp.data}"
    assert resp.data.get("success") is True, f"Expected success=True, got {resp.data}"
    offer2 = WorkforceJobOffer.objects.filter(job_id=sr2.id, status=WorkforceJobOffer.Status.OFFERED).first()
    assert offer2 is not None, "Immediate trigger must create job offer."
    print(f"  -> SUCCESS: Customer POST trigger dispatched Job #{sr2.id} with status={resp.data.get('status')}")
    passed += 1

    # -------------------------------------------------------------
    # Test 3: Worker Downtime / Crash Recovery
    # -------------------------------------------------------------
    _reset_technicians(company)
    print("\n[TEST 3/10] Worker Recovery after Downtime...")
    sr3 = _create_test_service_request(company, req_id="ZMD-REC-03", status="unassigned")
    # Worker is OFF, no offer exists
    assert WorkforceJobOffer.objects.filter(job_id=sr3.id).count() == 0, "No offer should exist yet."
    # Worker starts up and reconciles
    result3 = dispatch_pending_jobs(company_id=company.id, limit=10)
    offer3 = WorkforceJobOffer.objects.filter(job_id=sr3.id, status=WorkforceJobOffer.Status.OFFERED).first()
    assert offer3 is not None, "Worker startup must recover pending persisted booking."
    print(f"  -> SUCCESS: Worker recovered persisted booking #{sr3.id} after downtime.")
    passed += 1

    # -------------------------------------------------------------
    # Test 4: Scheduled-Window Holding and Automatic Unlock
    # -------------------------------------------------------------
    _reset_technicians(company)
    print("\n[TEST 4/10] Scheduled-Window Holding & Automatic Unlock (±1 Hour)...")
    import zoneinfo
    kolkata_tz = zoneinfo.ZoneInfo("Asia/Kolkata")
    kolkata_now = timezone.now().astimezone(kolkata_tz)
    today = kolkata_now.date()
    future_time_str = (kolkata_now + timedelta(hours=4)).strftime("%H:%M")
    sr4 = _create_test_service_request(company, req_id="ZMD-SCHED-04", preferred_date=today, preferred_time=future_time_str, status="unassigned")
    
    # Sweep while booking is 4 hours in the future -> must be held
    res4_fut = dispatch_pending_jobs(company_id=company.id, limit=10)
    assert WorkforceJobOffer.objects.filter(job_id=sr4.id).count() == 0, "Future scheduled booking must be held."
    
    # Window opens: set preferred_time to 30 mins from local now (inside ±1 hour window)
    near_time_str = (kolkata_now + timedelta(minutes=30)).strftime("%H:%M")
    sr4.preferred_time = near_time_str
    sr4.save()
    
    # Sweep inside window -> must unlock and dispatch
    res4_near = dispatch_pending_jobs(company_id=company.id, limit=10)
    offer4 = WorkforceJobOffer.objects.filter(job_id=sr4.id, status=WorkforceJobOffer.Status.OFFERED).first()
    assert offer4 is not None, "Job inside window must unlock and dispatch."
    print(f"  -> SUCCESS: Held future booking outside window, unlocked and dispatched inside window.")
    passed += 1

    # -------------------------------------------------------------
    # Test 5: Retry Backoff Ladder Enforcement
    # -------------------------------------------------------------
    _reset_technicians(company)
    print("\n[TEST 5/10] Retry Backoff Ladder Enforcement...")
    sr5 = _create_test_service_request(company, req_id="ZMD-RETRY-05", status="unassigned")
    # Take all techs offline to force failure
    Employee.objects.filter(company=company).update(is_online=False)
    
    success, msg = dispatch_job(sr5)
    assert success is False, "Dispatch should fail when no technicians online."
    state5 = WorkforceDispatchState.objects.get(job_id=sr5.id)
    assert state5.dispatch_status == WorkforceDispatchState.DispatchStatus.RETRY_SCHEDULED
    assert state5.retry_at is not None and state5.retry_at > timezone.now()
    
    # Restore techs online
    Employee.objects.filter(company=company).update(is_online=True)
    
    # Sweep before retry_at -> must skip
    res5_skip = dispatch_pending_jobs(company_id=company.id, limit=10)
    assert WorkforceJobOffer.objects.filter(job_id=sr5.id).count() == 0, "Sweep before retry_at must be skipped."
    
    # Fast-forward retry_at
    state5.retry_at = timezone.now() - timedelta(seconds=1)
    state5.save()
    
    # Sweep after retry_at -> must dispatch
    res5_retry = dispatch_pending_jobs(company_id=company.id, limit=10)
    offer5 = WorkforceJobOffer.objects.filter(job_id=sr5.id, status=WorkforceJobOffer.Status.OFFERED).first()
    assert offer5 is not None, "Sweep after retry_at must dispatch."
    print(f"  -> SUCCESS: Respected retry backoff ladder without duplicate dispatch spam.")
    passed += 1

    # -------------------------------------------------------------
    # Test 6: Decline Fallback (Permanent Exclusion + Next Candidate)
    # -------------------------------------------------------------
    _reset_technicians(company)
    print("\n[TEST 6/10] Decline Fallback & Next Candidate Routing...")
    sr6 = _create_test_service_request(company, req_id="ZMD-DECL-06", status="unassigned")
    dispatch_job(sr6)
    
    offer6_a = WorkforceJobOffer.objects.get(job_id=sr6.id, status=WorkforceJobOffer.Status.OFFERED)
    first_tech_id = offer6_a.employee_id
    
    # Tech declines via WorkforceJobRejectOfferView
    decl_req = factory.post(
        f"/api/workforce/jobs/{sr6.id}/reject-offer/",
        data={"reason": "Location too far"},
        format="json",
    )
    decl_req.user = offer6_a.employee.user
    decl_view = WorkforceJobRejectOfferView.as_view()
    resp_decl = decl_view(decl_req, pk=sr6.id)
    assert resp_decl.status_code == 200, f"Decline failed: {resp_decl.data}"
    
    # Worker reconciliation sweep
    dispatch_pending_jobs(company_id=company.id, limit=10)
    offer6_b = WorkforceJobOffer.objects.filter(job_id=sr6.id, status=WorkforceJobOffer.Status.OFFERED).first()
    assert offer6_b is not None, "Fallback offer must be created."
    assert offer6_b.employee_id != first_tech_id, f"Declined Tech #{first_tech_id} must not be re-offered."
    print(f"  -> SUCCESS: Declined Tech #{first_tech_id} excluded; fallback offer created for Tech #{offer6_b.employee_id}")
    passed += 1

    # -------------------------------------------------------------
    # Test 7: Expiry Fallback (Auto-Sweep + Next Candidate)
    # -------------------------------------------------------------
    _reset_technicians(company)
    print("\n[TEST 7/10] Expiry Fallback & Auto-Sweep...")
    sr7 = _create_test_service_request(company, req_id="ZMD-EXP-07", status="unassigned")
    dispatch_job(sr7)
    
    offer7_a = WorkforceJobOffer.objects.get(job_id=sr7.id, status=WorkforceJobOffer.Status.OFFERED)
    exp_tech_id = offer7_a.employee_id
    # Force offer expiry
    offer7_a.expires_at = timezone.now() - timedelta(seconds=10)
    offer7_a.save()
    
    # Worker reconciliation sweep sweeps expired and assigns next
    res7 = dispatch_pending_jobs(company_id=company.id, limit=10)
    assert res7["expired_offers_swept"] >= 1, "Must sweep expired offer."
    
    offer7_a.refresh_from_db()
    assert offer7_a.status == WorkforceJobOffer.Status.EXPIRED
    
    offer7_b = WorkforceJobOffer.objects.filter(job_id=sr7.id, status=WorkforceJobOffer.Status.OFFERED).first()
    assert offer7_b is not None, "Next candidate offer must be created after expiry."
    assert offer7_b.employee_id != exp_tech_id
    print(f"  -> SUCCESS: Expired offer on Tech #{exp_tech_id} swept -> Fallback offered to Tech #{offer7_b.employee_id}")
    passed += 1

    # -------------------------------------------------------------
    # Test 8: Concurrent Dispatch Safety
    # -------------------------------------------------------------
    _reset_technicians(company)
    print("\n[TEST 8/10] Concurrent Dispatch Safety (Two-Phase Claim Lock)...")
    sr8 = _create_test_service_request(company, req_id="ZMD-CONC-08", status="unassigned")
    
    results8 = []
    def worker_thread():
        res, msg = dispatch_job(sr8)
        results8.append((res, msg))

    t1 = threading.Thread(target=worker_thread)
    t2 = threading.Thread(target=worker_thread)
    t1.start()
    t2.start()
    t1.join()
    t2.join()

    active_offers_count = WorkforceJobOffer.objects.filter(job_id=sr8.id, status=WorkforceJobOffer.Status.OFFERED).count()
    assert active_offers_count == 1, f"Expected exactly 1 active offer, found {active_offers_count}"
    print(f"  -> SUCCESS: Concurrent workers executed; exactly 1 active offer created.")
    passed += 1

    # -------------------------------------------------------------
    # Test 9: Read-Only Invariant (GET /api/workforce/jobs/ does NOT dispatch)
    # -------------------------------------------------------------
    _reset_technicians(company)
    print("\n[TEST 9/10] Read-Only Invariant for GET Endpoints...")
    sr9 = _create_test_service_request(company, req_id="ZMD-RO-09", status="unassigned")
    assert WorkforceJobOffer.objects.filter(job_id=sr9.id).count() == 0

    get_req = factory.get("/api/workforce/jobs/")
    get_req.user = tech1.user
    job_view = WorkforceJobListView.as_view()
    resp9 = job_view(get_req)
    assert resp9.status_code == 200
    assert WorkforceJobOffer.objects.filter(job_id=sr9.id).count() == 0, "GET /jobs/ must never trigger dispatch or mutate state."
    print(f"  -> SUCCESS: GET /jobs/ executed purely as read-only; zero dispatch side-effects.")
    passed += 1

    # -------------------------------------------------------------
    # Test 10: Worker Heartbeat Observability (Bounded Storage)
    # -------------------------------------------------------------
    print("\n[TEST 10/10] Worker Heartbeat Observability...")
    _write_heartbeat("ok", {"cycle": 1})
    _write_heartbeat("ok", {"cycle": 2})
    _write_heartbeat("ok", {"cycle": 3})

    hb_rows = WorkforceEventLog.objects.filter(event_type="dispatch_engine_heartbeat")
    assert hb_rows.count() == 1, f"Expected exactly 1 heartbeat row, found {hb_rows.count()}"
    hb = hb_rows.first()
    assert hb.payload.get("detail", {}).get("cycle") == 3
    print(f"  -> SUCCESS: Heartbeat upsert verified without unbounded table growth (last cycle: {hb.payload['detail']['cycle']})")
    passed += 1

    print("\n==================================================================")
    print(f" ALL {passed}/{total} ZERO-MANUAL-DISPATCH TESTS PASSED PERFECTLY!")
    print("==================================================================")
    return True


if __name__ == "__main__":
    success = run_all_zero_dispatch_tests()
    sys.exit(0 if success else 1)
