"""
record_cash_settlement (services/cash_reconciliation.py) must derive the
expected total and the set of reconciled payments from ONE locked snapshot,
and must never re-claim a payment already reconciled by another settlement.
JobPayment's FK targets (ServiceRequest, Employee) are unmanaged mirrors
with no test tables, so the ORM managers are patched.
"""
from decimal import Decimal
from types import SimpleNamespace
from unittest.mock import MagicMock, patch

from django.test import TestCase

from workforce_api.services import cash_reconciliation as cr


def _pay(i, received=None, paid=None):
    return SimpleNamespace(id=i, amount_received=received, amount_paid=paid)


class CashSettlementConsistencyTests(TestCase):
    def _run(self, payments, deposited):
        locked_qs = MagicMock()
        locked_qs.filter.return_value.order_by.return_value = payments
        update_qs = MagicMock()
        settlement = SimpleNamespace(id=42)
        with patch.object(cr.JobPayment.objects, "select_for_update", return_value=locked_qs) as sfu, \
             patch.object(cr.JobPayment.objects, "filter", return_value=update_qs) as flt, \
             patch.object(cr.CashSettlement.objects, "create", return_value=settlement) as create:
            result = cr.record_cash_settlement(
                employee="emp", company="co", deposited_amount=deposited, recorded_by=None)
        return result, sfu, flt, update_qs, create

    def test_rows_are_locked_and_totals_come_from_the_same_snapshot(self):
        payments = [_pay(1, received=Decimal("100.00")), _pay(2, paid=Decimal("50.50")),
                    _pay(3, received=None, paid=None)]
        result, sfu, flt, update_qs, create = self._run(payments, "140")
        sfu.assert_called_once()
        kwargs = create.call_args.kwargs
        self.assertEqual(kwargs["expected_amount"], Decimal("150.50"))
        self.assertEqual(kwargs["discrepancy"], Decimal("-10.50"))
        # Only ONE read of outstanding payments; the only plain filter() is the update.
        flt.assert_called_once()
        self.assertEqual(flt.call_args.kwargs, {"id__in": [1, 2, 3], "reconciled": False})
        self.assertEqual(update_qs.update.call_args.kwargs["reconciled_in"].id, 42)
        self.assertEqual(result.id, 42)

    def test_nothing_outstanding_records_zero_expected(self):
        _, _, flt, _, create = self._run([], "0")
        self.assertEqual(create.call_args.kwargs["expected_amount"], Decimal("0.00"))
        self.assertEqual(flt.call_args.kwargs["id__in"], [])

    def test_negative_deposit_rejected(self):
        with self.assertRaises(ValueError):
            cr.record_cash_settlement("emp", "co", "-1", None)
