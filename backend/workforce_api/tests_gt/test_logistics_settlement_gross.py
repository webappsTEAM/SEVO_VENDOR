"""Logistics earnings follow the FINAL reconciled fare (not the stale prepaid JobPayment amount),
and never include the insurance premium."""
from decimal import Decimal
from types import SimpleNamespace
from unittest.mock import MagicMock, patch

from django.test import TestCase

from workforce_api.services import commission as cm


def _job(total, cat="goods_transport_truck", insured=False, premium=None, extras=None):
    return SimpleNamespace(id=9, service_category=cat, total_amount=Decimal(total), insurance_opted_in=insured,
                           insurance_premium=None if premium is None else Decimal(premium),
                           assigned_employee=None, issue_title="t", request_id="GT1", extra_charges=extras or [])


class SettlementGrossTests(TestCase):
    def _gross(self, job, due="530.00"):
        return self._created(job, due)[0]["gross_job_amount"]

    def _created(self, job, due="530.00"):
        payment = SimpleNamespace(id=5, amount_due=Decimal(due), amount_paid=Decimal(due), payment_method="ONLINE")
        wallet = SimpleNamespace(id=1)
        created = []
        ledger = MagicMock()
        ledger.objects.filter.return_value.first.return_value = None
        ledger.objects.create.side_effect = lambda **kw: created.append(kw) or SimpleNamespace(**kw)
        ledger.EntryType.JOB_CREDIT = "JOB_CREDIT"; ledger.EntryType.COMMISSION_DEBIT = "COMMISSION_DEBIT"
        ledger.EntryType.COD_COMMISSION_PAYABLE = "COD"; ledger.Status.HELD = "HELD"; ledger.Status.RELEASED = "RELEASED"
        jp = MagicMock(); jp.objects.filter.return_value.first.return_value = payment
        jp.PaymentMethod.CASH_ON_SERVICE = "CASH"
        with patch("workforce_api.models.WalletLedgerEntry", ledger), patch("workforce_api.models.JobPayment", jp), \
             patch.object(cm, "resolve_payee_wallet", return_value=(wallet, "TECH")), \
             patch.object(cm, "commission_rate_for", return_value=Decimal("0.10")), \
             patch.object(cm, "is_in_promo_period", return_value=False):
            try:
                cm.settle_completed_job(job)
            except Exception as exc:
                if not created:
                    raise      # only the vendor_wallet mirror AFTER the ledger writes may fail here
        return created

    def test_uses_final_fare_not_stale_payment_row(self):
        self.assertEqual(self._gross(_job("584.00")), Decimal("584.00"))       # fare rose 530 -> 584

    def test_insurance_premium_is_not_commissionable(self):
        self.assertEqual(self._gross(_job("604.00", insured=True, premium="20.00")), Decimal("584.00"))

    def test_non_logistics_unchanged(self):
        self.assertEqual(self._gross(_job("999.00", cat="ac_repair"), due="450.00"), Decimal("450.00"))

    def test_toll_is_reimbursed_in_full_and_not_commissioned(self):
        job = _job("669.00", extras=[{"status": "APPLIED", "amount": "85.00"}, {"status": "REJECTED", "amount": "999"}])
        created = self._created(job, due="584.00")
        self.assertEqual(created[0]["gross_job_amount"], Decimal("584.00"))
        # 584 - 10% commission = 525.60 net, plus the 85.00 toll refunded untouched.
        self.assertEqual(created[0]["signed_amount"], Decimal("610.60"))
        self.assertEqual(created[1]["signed_amount"], Decimal("-58.40"))
