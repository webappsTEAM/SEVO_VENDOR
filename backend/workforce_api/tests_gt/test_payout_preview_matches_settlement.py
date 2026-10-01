"""Driver-app EST. PAYOUT must use the settlement rules (commission, insurance
exclusion, toll reimbursement), not show the gross fare."""
from decimal import Decimal
from types import SimpleNamespace
from unittest.mock import MagicMock, patch
from django.test import TestCase as SimpleTestCase
from workforce_api.services import commission as cm


def _job(total, cat="goods_transport_truck", insured=False, premium=None, extras=None, emp=True):
    return SimpleNamespace(id=9, pk=9, service_category=cat, total_amount=Decimal(total), insurance_opted_in=insured,
                           insurance_premium=None if premium is None else Decimal(premium),
                           assigned_employee=SimpleNamespace(id=1, company_id=None, company=None) if emp else None,
                           extra_charges=extras or [])


def _preview(job, rate="0.18"):
    rel = MagicMock(); rel.objects.filter.return_value.exists.return_value = False
    wa = MagicMock(); wa.objects.filter.return_value.first.return_value = None
    with patch("workforce_api.models.VendorTechnicianRelationship", rel), patch("workforce_api.models.WalletAccount", wa), \
         patch.object(cm, "commission_rate_for", return_value=Decimal(rate)):
        return cm.preview_job_payout(job)


class PayoutPreviewTests(SimpleTestCase):
    def test_net_of_commission_not_gross(self):
        p = _preview(_job("584.00"), rate="0.10")
        self.assertEqual(p["estimated_payout"], "525.60")      # old UI showed 584.00

    def test_insurance_excluded_and_toll_reimbursed(self):
        p = _preview(_job("689.00", insured=True, premium="20.00", extras=[{"status": "APPLIED", "amount": "85.00"}]), rate="0.10")
        # fare 689-20-85 = 584 -> 525.60 net + 85 toll
        self.assertEqual(p["estimated_payout"], "610.60")

    def test_non_logistics_and_unassigned_return_none(self):
        self.assertIsNone(_preview(_job("500", cat="ac_repair")))
        self.assertIsNone(_preview(_job("500", emp=False)))


class SettlementAtomicTests(SimpleTestCase):
    def test_settle_is_atomic_and_helper_is_not_wrapped(self):
        # Regression: @transaction.atomic used to decorate a duplicate
        # _extra_charges_total() instead of settle_completed_job(), so the
        # JOB_CREDIT and COMMISSION entries could commit separately.
        self.assertTrue(hasattr(cm.settle_completed_job, "__wrapped__"))
        self.assertFalse(hasattr(cm._extra_charges_total, "__wrapped__"))
