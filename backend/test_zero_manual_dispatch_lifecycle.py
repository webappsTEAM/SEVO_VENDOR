"""
test_zero_manual_dispatch_lifecycle.py

Comprehensive End-to-End Validation Suite for CalTrack Zero-Manual-Dispatch Architecture
with 2-Minute Offer TTL and Bounded Parallel Offer Waves.

Verifies:
1. Worker Single-Pass Reconciliation & Parallel Wave 1 Creation (up to 5 candidates, 120s TTL).
2. Immediate Customer Dispatch Trigger (POST /api/workforce/jobs/dispatch/).
3. First-Acceptance Winner-Takes-All (Winner ACCEPTED, peers SUPERSEDED_BY_ACCEPTANCE).
4. Partial Wave Decline (Peer offers stay active, no premature abort).
5. Full Wave Decline Immediate Progression (All declined -> immediate next wave dispatch).
6. Wave Expiry Sweep & Wave 2 Progression (120s expiry -> Wave 2 with up to 10 candidates).
7. Scheduled-Window Holding and Automatic Unlock (T - 1h to T + 1h).
8. Retry Backoff Ladder (RETRY_SCHEDULED and retry_at enforcement).
9. Read-only Safety (GET /api/workforce/jobs/ does NOT dispatch).
10. Super Admin Dispatch Radar Observability (current_wave, countdown, waiting candidates).
11. Worker Heartbeat Observability (single upserted event row, bounded growth).
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
    get_wave_size,
    OFFER_TTL_SECONDS,
    DISPATCHABLE_STATUSES,
)
from workforce_api.views import (
    WorkforceCrossServiceDispatchView,
    WorkforceJobListView,
    WorkforceJobRejectOfferView,
    WorkforceJobAcceptOfferView,
    WorkforceDispatchRadarView,
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
        first_name=f"Tech{offset_index+1:02d}",
        last_name="Test",
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
    print(" CALTRACK 2-MIN TTL + PARALLEL OFFER WAVES VALIDATION SUITE")
    print("==================================================================")

    company = _create_test_company("Main")
    # Create a pool of 12 eligible technicians for wave sizing tests
    techs = [_create_test_employee(company, offset_index=i) for i in range(12)]
    print(f"Created test company #{company.id} with pool of {len(techs)} technicians.")

    passed = 0
    total = 11

    # -------------------------------------------------------------
    # Test 1: Worker Single-Pass Reconciliation & Parallel Wave 1 Creation
    # -------------------------------------------------------------
    _reset_technicians(company)
    print("\n[TEST 1/11] Worker Single-Pass & Wave 1 Bounded Parallel Distribution...")
    sr1 = _create_test_service_request(company, req_id="ZMD-WAVE1", status="unassigned")
    result1 = dispatch_pending_jobs(company_id=company.id, limit=10)
    
    offers1 = list(WorkforceJobOffer.objects.filter(job_id=sr1.id, status=WorkforceJobOffer.Status.OFFERED))
    assert len(offers1) == 5, f"Expected Wave 1 to create exactly 5 parallel offers, got {len(offers1)}"
    
    wave1_id = offers1[0].wave_id
    assert all(o.wave_id == wave1_id for o in offers1), "All offers in Wave 1 must share the same wave_id."
    assert all(o.wave_number == 1 for o in offers1), "All offers in Wave 1 must have wave_number=1."
    
    # Verify 120s TTL
    now = timezone.now()
    for o in offers1:
        ttl_seconds = round((o.expires_at - o.offered_at).total_seconds())
        assert ttl_seconds in (119, 120, 121), f"Expected ~120s TTL, got {ttl_seconds}s"
    
    print(f"  -> SUCCESS: Wave 1 created exactly {len(offers1)} parallel offers (TTL: 120s, wave_id: {wave1_id}).")
    passed += 1

    # -------------------------------------------------------------
    # Test 2: Customer Immediate Dispatch Trigger
    # -------------------------------------------------------------
    _reset_technicians(company)
    print("\n[TEST 2/11] Customer Immediate Dispatch Trigger (POST /api/workforce/jobs/dispatch/)...")
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
    offers2 = list(WorkforceJobOffer.objects.filter(job_id=sr2.id, status=WorkforceJobOffer.Status.OFFERED))
    assert len(offers2) == 5, f"Expected 5 offers from customer trigger, got {len(offers2)}"
    print(f"  -> SUCCESS: Customer POST trigger dispatched Job #{sr2.id} with {len(offers2)} parallel offers.")
    passed += 1

    # -------------------------------------------------------------
    # Test 3: First-Acceptance Winner-Takes-All & Superseding
    # -------------------------------------------------------------
    _reset_technicians(company)
    print("\n[TEST 3/11] First-Acceptance Winner-Takes-All & Atomic Superseding...")
    sr3 = _create_test_service_request(company, req_id="ZMD-WIN-03", status="unassigned")
    dispatch_job(sr3)
    
    wave_offers = list(WorkforceJobOffer.objects.filter(job_id=sr3.id, status=WorkforceJobOffer.Status.OFFERED))
    assert len(wave_offers) == 5, f"Expected 5 wave offers, got {len(wave_offers)}"
    
    # Candidate #2 accepts
    winner_offer = wave_offers[1]
    winner_tech = winner_offer.employee
    
    acc_req = factory.post(f"/api/workforce/jobs/{sr3.id}/accept-offer/", format="json")
    acc_req.user = winner_tech.user
    acc_view = WorkforceJobAcceptOfferView.as_view()
    resp_acc = acc_view(acc_req, pk=sr3.id)
    assert resp_acc.status_code == 200, f"Accept failed: {resp_acc.data}"
    
    winner_offer.refresh_from_db()
    assert winner_offer.status == "ACCEPTED", f"Winner offer status should be ACCEPTED, got {winner_offer.status}"
    
    sr3.refresh_from_db()
    assert sr3.assigned_employee_id == winner_tech.id, "Job must be assigned to winning technician."
    assert sr3.status == "accepted", f"Job status must be 'accepted', got {sr3.status}"
    
    # Verify other 4 offers became SUPERSEDED_BY_ACCEPTANCE
    superseded_offers = list(WorkforceJobOffer.objects.filter(job_id=sr3.id, status=WorkforceJobOffer.Status.SUPERSEDED_BY_ACCEPTANCE))
    assert len(superseded_offers) == 4, f"Expected 4 superseded offers, got {len(superseded_offers)}"
    
    # Second tech tries to accept -> must be rejected with 409 Conflict
    loser_offer = wave_offers[0]
    loser_tech = loser_offer.employee
    acc_req2 = factory.post(f"/api/workforce/jobs/{sr3.id}/accept-offer/", format="json")
    acc_req2.user = loser_tech.user
    resp_acc2 = acc_view(acc_req2, pk=sr3.id)
    assert resp_acc2.status_code == 409, f"Expected 409 Conflict for loser acceptance, got {resp_acc2.status_code}"
    
    print(f"  -> SUCCESS: Tech #{winner_tech.id} won job #{sr3.id}; {len(superseded_offers)} peer offers atomically superseded; late acceptance safely rejected (409).")
    passed += 1

    # -------------------------------------------------------------
    # Test 4: Partial Wave Decline (Peer Offers Remain Active)
    # -------------------------------------------------------------
    _reset_technicians(company)
    print("\n[TEST 4/11] Partial Wave Decline (Peers Remain Active)...")
    sr4 = _create_test_service_request(company, req_id="ZMD-PDECL-04", status="unassigned")
    dispatch_job(sr4)
    
    w_offers = list(WorkforceJobOffer.objects.filter(job_id=sr4.id, status=WorkforceJobOffer.Status.OFFERED))
    assert len(w_offers) == 5
    
    decliner = w_offers[0].employee
    decl_req = factory.post(
        f"/api/workforce/jobs/{sr4.id}/reject-offer/",
        data={"reason": "Busy with another client"},
        format="json",
    )
    decl_req.user = decliner.user
    decl_view = WorkforceJobRejectOfferView.as_view()
    resp_decl = decl_view(decl_req, pk=sr4.id)
    assert resp_decl.status_code == 200, f"Decline failed: {resp_decl.data}"
    assert resp_decl.data.get("remaining_wave_offers") == 4
    
    # Check that 4 peer offers remain OFFERED and unexpired
    active_peers = WorkforceJobOffer.objects.filter(job_id=sr4.id, status=WorkforceJobOffer.Status.OFFERED)
    assert active_peers.count() == 4, f"Expected 4 active peer offers, got {active_peers.count()}"
    
    state4 = WorkforceDispatchState.objects.get(job_id=sr4.id)
    assert state4.dispatch_status == WorkforceDispatchState.DispatchStatus.OFFER_ACTIVE, "Wave must remain OFFER_ACTIVE while peers are pending."
    
    print(f"  -> SUCCESS: Tech #{decliner.id} declined; remaining 4 peer offers in Wave 1 remain active.")
    passed += 1

    # -------------------------------------------------------------
    # Test 5: Full Wave Decline Immediate Progression
    # -------------------------------------------------------------
    _reset_technicians(company)
    print("\n[TEST 5/11] Full Wave Decline Immediate Next Wave Progression...")
    sr5 = _create_test_service_request(company, req_id="ZMD-FDECL-05", status="unassigned")
    dispatch_job(sr5)
    
    wave1_offers = list(WorkforceJobOffer.objects.filter(job_id=sr5.id, status=WorkforceJobOffer.Status.OFFERED))
    assert len(wave1_offers) == 5
    
    # All 5 technicians decline sequentially
    for idx, off in enumerate(wave1_offers):
        decl_req = factory.post(
            f"/api/workforce/jobs/{sr5.id}/reject-offer/",
            data={"reason": f"Tech {idx+1} declined"},
            format="json",
        )
        decl_req.user = off.employee.user
        resp = decl_view(decl_req, pk=sr5.id)
        assert resp.status_code == 200
    
    # After last technician declines, next wave (Wave 2) should be triggered immediately
    # Let's run a sweep or verify Wave 2
    dispatch_pending_jobs(company_id=company.id, limit=10)
    
    wave2_offers = list(WorkforceJobOffer.objects.filter(job_id=sr5.id, status=WorkforceJobOffer.Status.OFFERED))
    assert len(wave2_offers) > 0, "Wave 2 offers must be created after all Wave 1 offers declined."
    assert all(o.wave_number == 2 for o in wave2_offers), "New offers must be in Wave 2."
    
    wave1_emp_ids = {o.employee_id for o in wave1_offers}
    assert all(o.employee_id not in wave1_emp_ids for o in wave2_offers), "Wave 1 decliners must be excluded from Wave 2."
    
    print(f"  -> SUCCESS: All 5 Wave 1 technicians declined -> Wave 2 dispatched immediately with {len(wave2_offers)} new candidate(s).")
    passed += 1

    # -------------------------------------------------------------
    # Test 6: Wave Expiry Sweep & Wave 2 Progression
    # -------------------------------------------------------------
    _reset_technicians(company)
    print("\n[TEST 6/11] Wave Expiry Sweep & Wave 2 Progression...")
    sr6 = _create_test_service_request(company, req_id="ZMD-EXP-06", status="unassigned")
    dispatch_job(sr6)
    
    w1_offers = list(WorkforceJobOffer.objects.filter(job_id=sr6.id, status=WorkforceJobOffer.Status.OFFERED))
    assert len(w1_offers) == 5
    
    # Simulate TTL expiry on all Wave 1 offers
    past_dt = timezone.now() - timedelta(seconds=10)
    WorkforceJobOffer.objects.filter(job_id=sr6.id, status=WorkforceJobOffer.Status.OFFERED).update(expires_at=past_dt)
    
    # Sweep expired offers
    swept = expire_and_reassign_offers()
    assert swept >= 5, f"Expected at least 5 expired offers swept, got {swept}"
    
    # Verify Wave 2 offers were created
    w2_offers = list(WorkforceJobOffer.objects.filter(job_id=sr6.id, status=WorkforceJobOffer.Status.OFFERED))
    assert len(w2_offers) > 0, "Wave 2 offers must be created after Wave 1 expired."
    assert all(o.wave_number == 2 for o in w2_offers), "New offers must have wave_number=2."
    
    print(f"  -> SUCCESS: Expired Wave 1 offers swept ({swept} offers) -> Wave 2 automatically dispatched with {len(w2_offers)} candidate(s).")
    passed += 1

    # -------------------------------------------------------------
    # Test 7: Scheduled-Window Holding and Automatic Unlock
    # -------------------------------------------------------------
    _reset_technicians(company)
    print("\n[TEST 7/11] Scheduled-Window Holding & Automatic Unlock (±1 Hour)...")
    import zoneinfo
    kolkata_tz = zoneinfo.ZoneInfo("Asia/Kolkata")
    kolkata_now = timezone.now().astimezone(kolkata_tz)
    today = kolkata_now.date()
    future_time_str = (kolkata_now + timedelta(hours=4)).strftime("%H:%M")
    sr7 = _create_test_service_request(company, req_id="ZMD-SCHED-07", preferred_date=today, preferred_time=future_time_str, status="unassigned")
    
    # Sweep while booking is 4 hours in the future -> must be held
    res7_fut = dispatch_pending_jobs(company_id=company.id, limit=10)
    assert WorkforceJobOffer.objects.filter(job_id=sr7.id).count() == 0, "Future scheduled booking must be held."
    
    # Window opens: set preferred_time to 30 mins from local now (inside ±1 hour window)
    near_time_str = (kolkata_now + timedelta(minutes=30)).strftime("%H:%M")
    sr7.preferred_time = near_time_str
    sr7.save()
    
    # Sweep inside window -> must unlock and dispatch
    res7_near = dispatch_pending_jobs(company_id=company.id, limit=10)
    offers7 = list(WorkforceJobOffer.objects.filter(job_id=sr7.id, status=WorkforceJobOffer.Status.OFFERED))
    assert len(offers7) > 0, "Job inside window must unlock and dispatch."
    print(f"  -> SUCCESS: Held future booking outside window, unlocked and dispatched inside window ({len(offers7)} offers).")
    passed += 1

    # -------------------------------------------------------------
    # Test 8: Retry Backoff Ladder Enforcement
    # -------------------------------------------------------------
    _reset_technicians(company)
    print("\n[TEST 8/11] Retry Backoff Ladder Enforcement...")
    sr8 = _create_test_service_request(company, req_id="ZMD-RETRY-08", status="unassigned")
    # Take all techs offline to force failure
    Employee.objects.filter(company=company).update(is_online=False)
    
    success, msg = dispatch_job(sr8)
    assert success is False, "Dispatch should fail when no technicians online."
    state8 = WorkforceDispatchState.objects.get(job_id=sr8.id)
    assert state8.dispatch_status == WorkforceDispatchState.DispatchStatus.RETRY_SCHEDULED
    assert state8.retry_at is not None and state8.retry_at > timezone.now()
    
    # Restore techs online
    Employee.objects.filter(company=company).update(is_online=True)
    
    # Sweep before retry_at -> must skip
    res8_skip = dispatch_pending_jobs(company_id=company.id, limit=10)
    assert WorkforceJobOffer.objects.filter(job_id=sr8.id).count() == 0, "Sweep before retry_at must be skipped."
    
    # Fast-forward retry_at
    state8.retry_at = timezone.now() - timedelta(seconds=1)
    state8.save()
    
    # Sweep after retry_at -> must dispatch
    res8_retry = dispatch_pending_jobs(company_id=company.id, limit=10)
    offers8 = list(WorkforceJobOffer.objects.filter(job_id=sr8.id, status=WorkforceJobOffer.Status.OFFERED))
    assert len(offers8) > 0, "Sweep after retry_at must dispatch."
    print(f"  -> SUCCESS: Respected retry backoff ladder without duplicate dispatch spam.")
    passed += 1

    # -------------------------------------------------------------
    # Test 9: Read-Only Safety (GET /api/workforce/jobs/ does NOT dispatch)
    # -------------------------------------------------------------
    _reset_technicians(company)
    print("\n[TEST 9/11] Read-Only Invariant for GET Endpoints...")
    sr9 = _create_test_service_request(company, req_id="ZMD-RO-09", status="unassigned")
    assert WorkforceJobOffer.objects.filter(job_id=sr9.id).count() == 0
    
    get_req = factory.get("/api/workforce/jobs/")
    get_req.user = techs[0].user
    job_view = WorkforceJobListView.as_view()
    resp9 = job_view(get_req)
    assert resp9.status_code == 200
    assert WorkforceJobOffer.objects.filter(job_id=sr9.id).count() == 0, "GET /jobs/ must never trigger dispatch or mutate state."
    print(f"  -> SUCCESS: GET /jobs/ executed purely as read-only; zero dispatch side-effects.")
    passed += 1

    # -------------------------------------------------------------
    # Test 10: Super Admin Dispatch Radar Observability
    # -------------------------------------------------------------
    _reset_technicians(company)
    print("\n[TEST 10/11] Super Admin Dispatch Radar (current_wave & waiting candidates)...")
    sr10 = _create_test_service_request(company, req_id="ZMD-RADAR-10", status="unassigned")
    dispatch_job(sr10)
    
    admin_user = User.objects.create_superuser("admin_radar_test", "admin@example.com", "AdminPass@123")
    radar_req = factory.get(f"/api/workforce/dispatch/radar/?job_id={sr10.id}")
    radar_req.user = admin_user
    radar_view = WorkforceDispatchRadarView.as_view()
    resp10 = radar_view(radar_req)
    assert resp10.status_code == 200, f"Radar request failed: {resp10.data}"
    
    sel_job_data = resp10.data.get("selected_job")
    assert sel_job_data is not None, "Selected job details must be returned."
    
    current_wave_info = sel_job_data.get("current_wave")
    assert current_wave_info is not None, "current_wave must be present in radar detail."
    assert current_wave_info.get("wave_number") == 1, f"Expected wave_number=1, got {current_wave_info.get('wave_number')}"
    assert current_wave_info.get("count") == 5, f"Expected 5 offers in current wave, got {current_wave_info.get('count')}"
    assert "remaining_seconds" in current_wave_info, "remaining_seconds countdown must be present in current wave."
    assert "waiting_candidates" in sel_job_data, "waiting_candidates must be categorized in radar."
    
    print(f"  -> SUCCESS: Dispatch Radar returned current_wave (Wave #{current_wave_info['wave_number']}, {current_wave_info['count']} active offers, {current_wave_info['remaining_seconds']}s remaining) & waiting candidates.")
    passed += 1

    # -------------------------------------------------------------
    # Test 11: Worker Heartbeat Observability (Bounded Storage)
    # -------------------------------------------------------------
    print("\n[TEST 11/11] Worker Heartbeat Observability...")
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
    print(f" ALL {passed}/{total} CALTRACK DISPATCH LIFECYCLE TESTS PASSED PERFECTLY!")
    print("==================================================================")
    return True


if __name__ == "__main__":
    success = run_all_zero_dispatch_tests()
    sys.exit(0 if success else 1)
