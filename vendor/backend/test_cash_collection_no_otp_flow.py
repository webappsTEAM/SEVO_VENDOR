import os
import sys
import json
from decimal import Decimal

import django
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "workforce_core.settings")
django.setup()

from django.test import TestCase
from django.utils import timezone
from django.contrib.auth import get_user_model
from rest_framework.test import APIRequestFactory, force_authenticate

User = get_user_model()

from employees.models import Employee
from companies.models import Company
from service_requests.models import ServiceRequest
from workforce_api.models import (
    PostServiceProof,
    JobPayment,
    PaymentCollectionEvent,
)
from workforce_api.views import WorkforceJobCashCollectView, WorkforceJobPaymentVerifyOTPView


import uuid

class CashCollectionNoOtpTests(TestCase):
    def setUp(self):
        self.factory = APIRequestFactory()
        self.company = Company.objects.filter(is_active=True).first() or Company.objects.create(company_name="Test Company", is_active=True)
        unique_id = uuid.uuid4().hex[:8]
        self.user = User.objects.create_user(
            username=f"tech_cash_{unique_id}",
            email=f"tech_cash_{unique_id}@example.com",
            password="password123",
            role="employee",
        )
        self.emp = Employee.objects.create(
            user=self.user,
            company=self.company,
            employee_id=f"EMP-{unique_id[:6].upper()}",
            phone=f"98{unique_id[:8]}",
            bank_details={"onboarding": {"status": "approved"}},
        )
        self.job = ServiceRequest.objects.create(
            company=self.company,
            assigned_employee=self.emp,
            status="proof_submitted",
            total_amount=Decimal("999.00"),
            payment_method="cash",
            payment_status="pending",
            preferred_date=timezone.localdate(),
            preferred_time="10:00 AM",
            service_category="Appliances",
            issue_title="AC Repair",
        )
        # Create after-service proof
        self.proof = PostServiceProof.objects.create(
            job=self.job,
            employee=self.emp,
            after_presence_photo="proofs/after_presence.jpg",
            is_submitted=True,
        )

    def test_cash_collection_records_cash_pending_and_otp_verification_completes_job(self):
        """Technician reports cash; transitions to CASH_PENDING; OTP verification transitions to PAID and completes job."""
        from django.contrib.auth.hashers import make_password

        # Step 1: Cash Collection
        req = self.factory.post(
            f"/workforce/jobs/{self.job.id}/payment/collect/",
            {"amount_received": "1000.00"},
            format="json",
        )
        force_authenticate(req, user=self.user)
        view = WorkforceJobCashCollectView.as_view()
        resp = view(req, pk=self.job.id)

        self.assertEqual(resp.status_code, 200)
        self.assertEqual(resp.data["payment_status"], "CASH_PENDING")
        self.assertEqual(resp.data["amount_due"], "999.00")
        self.assertEqual(resp.data["amount_received"], "1000.00")
        self.assertEqual(resp.data["change_returned"], "1.00")

        # Verify database record in CASH_PENDING state
        pmt = JobPayment.objects.get(job=self.job)
        self.assertEqual(pmt.payment_status, JobPayment.PaymentStatus.CASH_PENDING)
        self.assertIsNotNone(pmt.payment_confirmation_otp_hash)

        # Verify audit events
        events = list(PaymentCollectionEvent.objects.filter(job_payment=pmt).values_list("event_type", flat=True))
        self.assertIn("CASH_REPORTED", events)

        # Step 2: Set deterministic OTP and verify via WorkforceJobPaymentVerifyOTPView
        pmt.payment_confirmation_otp_hash = make_password("654321")
        pmt.save(update_fields=["payment_confirmation_otp_hash"])

        req_otp = self.factory.post(
            f"/workforce/jobs/{self.job.id}/payment/verify-otp/",
            {"otp": "654321"},
            format="json",
        )
        force_authenticate(req_otp, user=self.user)
        view_otp = WorkforceJobPaymentVerifyOTPView.as_view()
        resp_otp = view_otp(req_otp, pk=self.job.id)

        self.assertEqual(resp_otp.status_code, 200)
        self.assertEqual(resp_otp.data["payment_status"], "PAID")

        # Verify job is completed
        self.job.refresh_from_db()
        self.assertEqual(self.job.status, "completed")
        self.assertEqual(self.job.payment_status, "paid")

        # Verify final audit events
        events_final = list(PaymentCollectionEvent.objects.filter(job_payment=pmt).values_list("event_type", flat=True))
        self.assertIn("PAYMENT_PAID", events_final)

    def test_cash_collection_insufficient_amount_rejected(self):
        """Technician cannot collect less than authoritative amount due."""
        req = self.factory.post(
            f"/workforce/jobs/{self.job.id}/payment/collect/",
            {"amount_received": "500.00"},
            format="json",
        )
        force_authenticate(req, user=self.user)
        view = WorkforceJobCashCollectView.as_view()
        resp = view(req, pk=self.job.id)

        self.assertEqual(resp.status_code, 400)
        self.assertIn("cannot be less than authoritative amount due", resp.data["error"])

    def test_wrong_payment_confirmation_otp_rejected(self):
        """Submitting an invalid 6-digit OTP is rejected with 400."""
        from django.contrib.auth.hashers import make_password

        # Report cash first
        req = self.factory.post(
            f"/workforce/jobs/{self.job.id}/payment/collect/",
            {"amount_received": "1000.00"},
            format="json",
        )
        force_authenticate(req, user=self.user)
        WorkforceJobCashCollectView.as_view()(req, pk=self.job.id)

        # Submit wrong OTP
        req_wrong = self.factory.post(
            f"/workforce/jobs/{self.job.id}/payment/verify-otp/",
            {"otp": "000000"},
            format="json",
        )
        force_authenticate(req_wrong, user=self.user)
        resp_wrong = WorkforceJobPaymentVerifyOTPView.as_view()(req_wrong, pk=self.job.id)

        self.assertEqual(resp_wrong.status_code, 400)
        self.assertIn("Invalid payment confirmation OTP", resp_wrong.data["error"])


if __name__ == "__main__":
    import unittest
    suite = unittest.TestLoader().loadTestsFromTestCase(CashCollectionNoOtpTests)
    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(suite)
    if not result.wasSuccessful():
        sys.exit(1)
    print("\nALL CASH COLLECTION NO-OTP TESTS PASSED PERFECTLY!")
