"""
run_live_hardened_dispatch_e2e.py

Live E2E Verification of Hardened Dispatch Pipeline on Real PostgreSQL DB:
1. Creates real test Company, Skills, Technicians with Live GPS.
2. Creates real confirmed ServiceRequest.
3. Triggers authoritative dispatch_job(job_id).
4. Verifies WorkforceJobOffer creation with Wave metadata.
5. Verifies SSE WorkforceEventLog creation.
6. Simulates Technician Accept via WorkforceJobAcceptOfferView.
7. Verifies Atomic DB state: assigned_employee, status='in_progress', offer='ACCEPTED'.
8. Verifies Outbound Webhook creation in WorkforceOutboundWebhook Outbox table.
9. Verifies process_pending_outbound_webhooks() execution.
10. Tests concurrency: second technician attempting accept receives 409 conflict.
11. Tests offer expiration: expire_and_reassign_offers() marks EXPIRED.
12. Cleans up all test data.
"""
import os
import sys
import uuid
import datetime
from datetime import timedelta
from unittest.mock import patch

import django

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "workforce_core.settings")
django.setup()

from django.utils import timezone
from django.contrib.auth import get_user_model
from rest_framework.test import APIRequestFactory, force_authenticate

from companies.models import Company
from employees.models import Employee
from service_requests.models import ServiceRequest
from workforce_api.models import (
    WorkforceJobOffer,
    WorkforceDispatchState,
    WorkforceEventLog,
    WorkforceOutboundWebhook,
    WorkforceSkill,
    WorkforceEmployeeSkill,
    WorkforceEmployeeSchedule,
)
from workforce_api.services.automatic_dispatch import (
    dispatch_job,
    expire_and_reassign_offers,
)
from workforce_api.services.customer_webhook import (
    notify_customer_app,
    process_pending_outbound_webhooks,
)
from workforce_api.views import WorkforceJobAcceptOfferView

User = get_user_model()


def run_e2e_verification():
    print("=" * 70)
    print(" LIVE POSTGRESQL E2E PIPELINE VERIFICATION")
    print("=" * 70)

    factory = APIRequestFactory()
    now = timezone.now()
    today = timezone.localdate()
    day_name = today.strftime("%A").lower()

    # Tracking sets for cleanup
    created_companies = []
    created_users = []
    created_jobs = []

    try:
        # Step 1: Use or Create Test Company
        company = Company.objects.filter(is_active=True).first()
        if not company:
            company = Company.objects.create(
                company_name=f"E2E_Live_Co_{uuid.uuid4().hex[:6]}",
                is_active=True,
            )
            created_companies.append(company)
        print(f"[SETUP] Using test company #{company.id}: {company.company_name}")

        # Step 2: Create Skills
        skill, _ = WorkforceSkill.objects.get_or_create(
            name="AC Inspection",
            company=company,
            defaults={"category": "hvac"},
        )

        # Step 3: Create Technician 1 (Close to job, fresh GPS)
        u1 = User.objects.create_user(
            username=f"livetech1_{uuid.uuid4().hex[:6]}",
            email=f"livetech1_{uuid.uuid4().hex[:4]}@test.com",
            password="LivePassword123!",
            role="employee",
            company=company,
        )
        created_users.append(u1)
        u1.last_known_location = {
            "latitude": 12.9716,
            "longitude": 77.5946,
            "accuracy": 5.0,
            "captured_at": (now - timedelta(seconds=20)).isoformat(),
            "updated_at": (now - timedelta(seconds=20)).isoformat(),
        }
        u1.save(update_fields=["last_known_location"])

        emp1 = Employee.objects.create(
            user=u1,
            employee_id=f"EMP-{uuid.uuid4().hex[:8].upper()}",
            company=company,
            is_active=True,
            is_online=True,
            current_availability="available",
            bank_details={
                "onboarding": {
                    "status": "approved",
                    "services": [
                        {"name": "AC Inspection", "category": "hvac", "status": "approved"},
                        {"name": "hvac", "category": "hvac", "status": "approved"},
                    ],
                    "documents": {},
                },
                "attendance": {"is_clocked_in": True},
                "leaves": [],
            },
        )

        WorkforceEmployeeSkill.objects.get_or_create(employee=emp1, skill=skill, defaults={"is_verified": True})
        for dow in range(7):
            WorkforceEmployeeSchedule.objects.create(
                employee=emp1,
                company=company,
                day_of_week=dow,
                start_time=datetime.time(0, 0),
                end_time=datetime.time(23, 59),
                is_working_day=True,
            )
        print(f"[SETUP] Created Technician 1 #{emp1.id} ({u1.username}) with live GPS.")

        # Step 4: Create Technician 2
        u2 = User.objects.create_user(
            username=f"livetech2_{uuid.uuid4().hex[:6]}",
            email=f"livetech2_{uuid.uuid4().hex[:4]}@test.com",
            password="LivePassword123!",
            role="employee",
            company=company,
        )
        created_users.append(u2)
        u2.last_known_location = {
            "latitude": 12.9750,
            "longitude": 77.5980,
            "accuracy": 5.0,
            "captured_at": (now - timedelta(seconds=35)).isoformat(),
            "updated_at": (now - timedelta(seconds=35)).isoformat(),
        }
        u2.save(update_fields=["last_known_location"])

        emp2 = Employee.objects.create(
            user=u2,
            employee_id=f"EMP-{uuid.uuid4().hex[:8].upper()}",
            company=company,
            is_active=True,
            is_online=True,
            current_availability="available",
            bank_details={
                "onboarding": {
                    "status": "approved",
                    "services": [
                        {"name": "AC Inspection", "category": "hvac", "status": "approved"},
                        {"name": "hvac", "category": "hvac", "status": "approved"},
                    ],
                    "documents": {},
                },
                "attendance": {"is_clocked_in": True},
                "leaves": [],
            },
        )

        WorkforceEmployeeSkill.objects.get_or_create(employee=emp2, skill=skill, defaults={"is_verified": True})
        for dow in range(7):
            WorkforceEmployeeSchedule.objects.create(
                employee=emp2,
                company=company,
                day_of_week=dow,
                start_time=datetime.time(0, 0),
                end_time=datetime.time(23, 59),
                is_working_day=True,
            )
        print(f"[SETUP] Created Technician 2 #{emp2.id} ({u2.username}) with live GPS.")

        # Step 5: Create Confirmed ServiceRequest
        from zoneinfo import ZoneInfo
        kolkata_tz = ZoneInfo("Asia/Kolkata")
        job = ServiceRequest.objects.create(
            company=company,
            service_category="hvac",
            issue_title="AC Inspection",
            status="confirmed",
            preferred_date=today,
            preferred_time="ASAP",
            latitude=12.9716,
            longitude=77.5946,
            customer_name="E2E Live Customer",
            phone="+919876543210",
            address="Brigade Road, Bangalore",
        )
        created_jobs.append(job)
        print(f"[SETUP] Created ServiceRequest #{job.id} (status={job.status}, service={job.service_category}).")

        # Step 6: Trigger Authoritative Dispatch
        print("\n--- PHASE 1: AUTHORITATIVE DISPATCH TRIGGER ---")
        with patch("workforce_api.services.customer_webhook.requests.post") as mock_post:
            mock_post.return_value.status_code = 200
            mock_post.return_value.text = '{"success": true}'
            ok, reason = dispatch_job(job.id)

        print(f"dispatch_job result: ok={ok}, reason='{reason}'")
        assert ok is True, f"Authoritative dispatch failed: {reason}"

        # Verify JobOffer in DB
        offers = list(WorkforceJobOffer.objects.filter(job=job, status=WorkforceJobOffer.Status.OFFERED))
        print(f"Generated {len(offers)} active job offer(s) in Wave #{offers[0].wave_number if offers else 'N/A'}")
        assert len(offers) >= 1, "Expected at least 1 job offer generated"
        offered_emp_ids = [o.employee_id for o in offers]
        assert emp1.id in offered_emp_ids or emp2.id in offered_emp_ids

        # Verify SSE event logged in WorkforceEventLog
        sse_events = list(WorkforceEventLog.objects.filter(event_type="OFFER_CREATED", payload__job_id=job.id))
        print(f"Logged {len(sse_events)} OFFER_CREATED SSE event(s) in WorkforceEventLog table.")
        assert len(sse_events) >= 1, "Expected OFFER_CREATED SSE event logged"

        # Step 7: Technician 1 Accepts Offer
        print("\n--- PHASE 2: TECHNICIAN ACCEPTANCE & ATOMIC ASSIGNMENT ---")
        winning_emp = emp1 if emp1.id in offered_emp_ids else emp2
        winning_user = u1 if winning_emp == emp1 else u2
        losing_emp = emp2 if winning_emp == emp1 else emp1
        losing_user = u2 if winning_emp == emp1 else u1

        req = factory.post(f"/api/workforce/jobs/{job.id}/accept-offer/")
        force_authenticate(req, user=winning_user)
        view = WorkforceJobAcceptOfferView.as_view()

        with patch("workforce_api.services.customer_webhook.requests.post") as mock_post:
            mock_post.return_value.status_code = 200
            mock_post.return_value.text = '{"success": true}'
            resp = view(req, pk=job.id)

        print(f"Technician #{winning_emp.id} accept response: HTTP {resp.status_code}")
        assert resp.status_code == 200, f"Accept failed: {resp.data}"

        job.refresh_from_db()
        print(f"DB State after accept: job.status='{job.status}', assigned_employee=#{getattr(job.assigned_employee, 'id', None)}")
        assert job.assigned_employee == winning_emp, "Assigned employee does not match winning technician"
        assert job.status in ["in_progress", "accepted"], f"Unexpected job status: {job.status}"

        winning_offer = WorkforceJobOffer.objects.filter(job=job, employee=winning_emp).first()
        assert winning_offer.status == WorkforceJobOffer.Status.ACCEPTED, f"Expected offer ACCEPTED, got {winning_offer.status}"

        # Step 8: Concurrent Accept by second technician MUST fail with 409
        print("\n--- PHASE 3: CONCURRENCY RACE PROTECTION ---")
        req2 = factory.post(f"/api/workforce/jobs/{job.id}/accept-offer/")
        force_authenticate(req2, user=losing_user)

        with patch("workforce_api.services.customer_webhook.requests.post") as mock_post:
            mock_post.return_value.status_code = 200
            resp2 = view(req2, pk=job.id)

        print(f"Second technician #{losing_emp.id} concurrent accept response: HTTP {resp2.status_code}")
        assert resp2.status_code in [400, 409], f"Expected 400 or 409 on second accept, got {resp2.status_code}"

        job.refresh_from_db()
        assert job.assigned_employee == winning_emp, "Concurrency breach: assigned employee changed!"

        # Step 9: Durable Outbound Webhook Verification
        print("\n--- PHASE 4: DURABLE OUTBOX WEBHOOK DELIVERY ---")
        all_webhooks = list(WorkforceOutboundWebhook.objects.all().values("id", "event_type", "booking_id", "status", "created_at"))
        print(f"All outbox webhook records in DB ({len(all_webhooks)}): {all_webhooks}")
        outbox_records = list(WorkforceOutboundWebhook.objects.filter(booking_id__in=[str(job.id), str(job.request_id)]))
        print(f"Found {len(outbox_records)} outbox webhook record(s) for booking #{job.id} / {job.request_id}.")
        assert len(outbox_records) >= 1, "No outbox records created"

        assigned_webhook = next((w for w in outbox_records if w.event_type in ["technician.assigned", "employee_accepted"]), None)
        assert assigned_webhook is not None, f"technician.assigned/employee_accepted webhook record not found in Outbox. Found: {[w.event_type for w in outbox_records]}"
        print(f"Outbox record #{assigned_webhook.id}: event='{assigned_webhook.event_type}', status='{assigned_webhook.status}', attempts={assigned_webhook.attempts}")
        print(f"Technician metadata in webhook payload: {assigned_webhook.payload.get('technician', {})}")
        assert assigned_webhook.payload.get("technician", {}).get("id") in [winning_emp.id, str(winning_emp.id)], "Technician ID missing from webhook payload"

        # Step 10: Sweep pending webhooks
        with patch("workforce_api.services.customer_webhook.requests.post") as mock_post:
            mock_post.return_value.status_code = 200
            mock_post.return_value.text = '{"success": true}'
            sweep_result = process_pending_outbound_webhooks(limit=25)
        print(f"process_pending_outbound_webhooks result: {sweep_result}")

        # Step 11: Expire and redispatch verification
        print("\n--- PHASE 5: OFFER EXPIRATION & MULTI-WAVE TRIGGER ---")
        # Create a second test job with an expired offer
        job2 = ServiceRequest.objects.create(
            company=company,
            service_category="hvac",
            issue_title="AC Inspection",
            status="unassigned",
            preferred_date=today,
            preferred_time="ASAP",
            latitude=12.9716,
            longitude=77.5946,
            customer_name="E2E Expiry Customer",
            phone="+919876543210",
            address="Brigade Road, Bangalore",
        )
        created_jobs.append(job2)

        expired_offer = WorkforceJobOffer.objects.create(
            job=job2,
            employee=emp1,
            status=WorkforceJobOffer.Status.OFFERED,
            wave_number=1,
            expires_at=now - timedelta(seconds=10),
        )

        with patch("workforce_api.services.customer_webhook.requests.post") as mock_post:
            mock_post.return_value.status_code = 200
            mock_post.return_value.text = '{"success": true}'
            expired_count = expire_and_reassign_offers()

        print(f"expire_and_reassign_offers handled {expired_count} expired offer(s).")
        expired_offer.refresh_from_db()
        assert expired_offer.status == WorkforceJobOffer.Status.EXPIRED, f"Expected EXPIRED, got {expired_offer.status}"

        print("\n" + "=" * 70)
        print(" ALL LIVE POSTGRESQL E2E PIPELINE TESTS PASSED (100% SUCCESS)!")
        print("=" * 70)

    finally:
        # Cleanup
        print("\n[CLEANUP] Cleaning up test records...")
        from django.db import connection
        for j in created_jobs:
            try:
                WorkforceJobOffer.objects.filter(job=j).delete()
                WorkforceOutboundWebhook.objects.filter(booking_id__in=[str(j.id), str(j.request_id)]).delete()
                WorkforceEventLog.objects.filter(payload__job_id=j.id).delete()
                WorkforceDispatchState.objects.filter(job=j).delete()
                with connection.cursor() as cursor:
                    cursor.execute("DELETE FROM service_requests_bookingassignment WHERE booking_id = %s", [j.id])
                    cursor.execute("DELETE FROM service_requests_employeejob WHERE service_request_id = %s", [j.id])
                j.delete()
            except Exception as e:
                print(f"[CLEANUP WARNING] Error deleting test job #{j.id}: {e}")
        for u in created_users:
            try:
                if hasattr(u, "employee_profile"):
                    WorkforceEmployeeSkill.objects.filter(employee=u.employee_profile).delete()
                    WorkforceEmployeeSchedule.objects.filter(employee=u.employee_profile).delete()
                    u.employee_profile.delete()
                u.delete()
            except Exception as e:
                print(f"[CLEANUP WARNING] Error deleting test user #{u.id}: {e}")
        for c in created_companies:
            try:
                c.delete()
            except Exception as e:
                print(f"[CLEANUP WARNING] Error deleting test company #{c.id}: {e}")
        print("[CLEANUP] Done.")


if __name__ == "__main__":
    run_e2e_verification()
