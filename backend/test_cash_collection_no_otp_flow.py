import os
import sys
import json
from decimal import Decimal

import django
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "workforce_core.settings")
django.setup()

from unittest import TestCase
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
    WalletLedgerEntry,
)
from vendor_wallet.models import EmployeeWallet, EmployeeWalletTransaction
from workforce_api.views import WorkforceJobCashCollectView, WorkforceJobPaymentVerifyOTPView
from workforce_api.services.commission import settle_completed_job
from django.contrib.auth.hashers import check_password

import uuid

class CashCollectionLifecycleTests(TestCase):
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

    def test_complete_cash_collection_otp_and_wallet_lifecycle(self):
        from unittest.mock import patch
        # Step 1: Technician reports cash collection with mocked deterministic OTP
        with patch("secrets.randbelow", return_value=123456):
            req1 = self.factory.post(
                f"/workforce/jobs/{self.job.id}/payment/collect/",
                {"amount_received": "1000.00"},
                format="json",
            )
            force_authenticate(req1, user=self.user)
            view_collect = WorkforceJobCashCollectView.as_view()
            resp1 = view_collect(req1, pk=self.job.id)

        self.assertEqual(resp1.status_code, 200)
        self.assertEqual(resp1.data["payment_status"], "CASH_PENDING")
        self.assertEqual(resp1.data["amount_due"], "999.00")
        self.assertEqual(resp1.data["amount_received"], "1000.00")
        self.assertEqual(resp1.data["change_returned"], "1.00")

        # Verify database record after cash collection
        pmt = JobPayment.objects.get(job=self.job)
        self.assertEqual(pmt.payment_status, JobPayment.PaymentStatus.CASH_PENDING)
        self.assertEqual(pmt.amount_paid, Decimal("0.00"))
        self.assertEqual(pmt.amount_received, Decimal("1000.00"))
        self.assertEqual(pmt.change_returned, Decimal("1.00"))
        self.assertIsNotNone(pmt.payment_confirmation_otp_hash)

        # Verify job remains proof_submitted and payment_status is cash_pending
        self.job.refresh_from_db()
        self.assertEqual(self.job.status, "proof_submitted")
        self.assertEqual(self.job.payment_status, "cash_pending")

        # Verify no premature wallet credit
        self.assertFalse(WalletLedgerEntry.objects.filter(job=self.job).exists())

        # Step 2: Valid OTP is deterministic (123456 + 100000 = 223456)
        valid_otp = "223456"
        self.assertTrue(check_password(valid_otp, pmt.payment_confirmation_otp_hash))

        # Step 3: Technician verifies OTP
        req2 = self.factory.post(
            f"/workforce/jobs/{self.job.id}/payment/verify-otp/",
            {"otp": valid_otp},
            format="json",
        )
        force_authenticate(req2, user=self.user)
        view_verify = WorkforceJobPaymentVerifyOTPView.as_view()
        resp2 = view_verify(req2, pk=self.job.id)

        self.assertEqual(resp2.status_code, 200)
        self.assertEqual(resp2.data["payment_status"], "PAID")
        self.assertEqual(resp2.data["job_status"], "completed")

        # Verify database state after OTP verification
        pmt.refresh_from_db()
        self.assertEqual(pmt.payment_status, JobPayment.PaymentStatus.PAID)
        self.assertEqual(pmt.amount_paid, Decimal("999.00"))
        self.assertEqual(pmt.amount_received, Decimal("1000.00"))
        self.assertEqual(pmt.change_returned, Decimal("1.00"))

        self.job.refresh_from_db()
        self.assertEqual(self.job.status, "completed")
        self.assertEqual(self.job.payment_status, "paid")

        # Step 4: Verify Wallet Settlement was executed exactly once
        ledger_entries = list(WalletLedgerEntry.objects.filter(job=self.job))
        credit_entries = [e for e in ledger_entries if e.entry_type == WalletLedgerEntry.EntryType.JOB_CREDIT]
        self.assertEqual(len(credit_entries), 1)

        emp_wallet = EmployeeWallet.objects.filter(employee=self.emp).first()
        self.assertIsNotNone(emp_wallet)
        self.assertGreater(emp_wallet.pending_balance, Decimal("0.00"))

        emp_txns = list(EmployeeWalletTransaction.objects.filter(wallet=emp_wallet, reference_id=str(pmt.id)))
        self.assertEqual(len(emp_txns), 1)

        # Step 5: Verify Idempotency - repeated OTP verify returns 200 without duplicate credit
        req3 = self.factory.post(
            f"/workforce/jobs/{self.job.id}/payment/verify-otp/",
            {"otp": valid_otp},
            format="json",
        )
        force_authenticate(req3, user=self.user)
        resp3 = view_verify(req3, pk=self.job.id)
        self.assertEqual(resp3.status_code, 200)
        self.assertEqual(resp3.data["payment_status"], "PAID")

        # Verify no duplicate wallet transactions or entries
        self.assertEqual(WalletLedgerEntry.objects.filter(job=self.job, entry_type=WalletLedgerEntry.EntryType.JOB_CREDIT).count(), 1)
        self.assertEqual(EmployeeWalletTransaction.objects.filter(wallet=emp_wallet, reference_id=str(pmt.id)).count(), 1)


if __name__ == "__main__":
    import unittest
    suite = unittest.TestLoader().loadTestsFromTestCase(CashCollectionLifecycleTests)
    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(suite)
    if not result.wasSuccessful():
        sys.exit(1)
    print("\nALL CASH COLLECTION LIFECYCLE TESTS PASSED PERFECTLY!")
