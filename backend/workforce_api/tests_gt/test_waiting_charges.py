"""
Pure unit tests for services/waiting_charges.compute_waiting_charge.
No DB access (SimpleTestCase); policy is a stand-in object.
Run in a staged SQLite sandbox replica (not on the target machine).
Run: python manage.py test workforce_api.tests_gt.test_waiting_charges
"""
from decimal import Decimal
from types import SimpleNamespace

from django.test import SimpleTestCase

from workforce_api.services.waiting_charges import compute_waiting_charge


def _policy(**kw):
    base = dict(
        waiting_free_loading_minutes=None,
        waiting_free_unloading_minutes=None,
        waiting_charge_per_minute=Decimal("0"),
        waiting_charge_cap=None,
    )
    base.update(kw)
    return SimpleNamespace(**base)


HISTORY = [
    {"leg": "EN_ROUTE_PICKUP", "at": "2026-09-24T10:00:00+00:00"},
    {"leg": "LOADING", "at": "2026-09-24T10:20:00+00:00"},
    {"leg": "EN_ROUTE_DROP", "at": "2026-09-24T11:05:00+00:00"},  # 45 min loading
    {"leg": "UNLOADING", "at": "2026-09-24T12:00:00+00:00"},
    {"leg": "DELIVERED", "at": "2026-09-24T12:30:30+00:00"},  # 30.5 -> 31 min
]


class WaitingChargeTests(SimpleTestCase):
    def test_no_policy_is_zero(self):
        r = compute_waiting_charge(HISTORY, None)
        self.assertEqual(r["amount"], Decimal("0.00"))
        self.assertFalse(r["enabled"])
        self.assertEqual(r["loading_minutes"], 45)
        self.assertEqual(r["unloading_minutes"], 31)

    def test_zero_rate_disabled(self):
        r = compute_waiting_charge(HISTORY, _policy(waiting_free_loading_minutes=10))
        self.assertEqual(r["amount"], Decimal("0.00"))
        self.assertFalse(r["enabled"])

    def test_charges_beyond_free_window(self):
        p = _policy(waiting_free_loading_minutes=30, waiting_free_unloading_minutes=30,
                    waiting_charge_per_minute=Decimal("2.50"))
        r = compute_waiting_charge(HISTORY, p)
        self.assertEqual(r["billable_minutes"], 15 + 1)
        self.assertEqual(r["amount"], Decimal("40.00"))

    def test_only_loading_configured(self):
        p = _policy(waiting_free_loading_minutes=30, waiting_charge_per_minute=Decimal("1"))
        self.assertEqual(compute_waiting_charge(HISTORY, p)["amount"], Decimal("15.00"))

    def test_cap_applies(self):
        p = _policy(waiting_free_loading_minutes=0, waiting_free_unloading_minutes=0,
                    waiting_charge_per_minute=Decimal("10"), waiting_charge_cap=Decimal("100"))
        self.assertEqual(compute_waiting_charge(HISTORY, p)["amount"], Decimal("100.00"))

    def test_incomplete_or_bad_history(self):
        p = _policy(waiting_free_loading_minutes=0, waiting_charge_per_minute=Decimal("1"))
        self.assertEqual(compute_waiting_charge([{"leg": "LOADING", "at": "bad"}], p)["amount"],
                         Decimal("0.00"))
        self.assertEqual(compute_waiting_charge(None, p)["amount"], Decimal("0.00"))

    def test_pm_legs(self):
        hist = [{"leg": "ARRIVED_PICKUP", "at": "2026-09-24T10:00:00Z"},
                {"leg": "PACKING", "at": "2026-09-24T10:10:00Z"},
                {"leg": "IN_TRANSIT", "at": "2026-09-24T12:00:00Z"}]
        r = compute_waiting_charge(hist, _policy(waiting_free_loading_minutes=90,
                                                 waiting_charge_per_minute=Decimal("1")))
        self.assertEqual(r["loading_minutes"], 120)
        self.assertEqual(r["amount"], Decimal("30.00"))

    def test_pm_full_sequence_measures_whole_pickup_and_drop_phases(self):
        # Documents CURRENT behaviour for Packers & Movers: the "loading"
        # dwell spans ARRIVED_PICKUP -> IN_TRANSIT and therefore includes
        # PACKING/DISMANTLING labour; "unloading" spans ARRIVED_DROP ->
        # DELIVERED and includes REASSEMBLY/UNPACKING. Whether P&M labour
        # time should ever count as billable waiting is a business decision
        # (flagged in the report); a P&M policy with waiting charges is off
        # unless an admin configures one.
        hist = [
            {"leg": "ASSIGNED", "at": "2026-09-24T08:00:00Z"},
            {"leg": "TEAM_EN_ROUTE", "at": "2026-09-24T08:10:00Z"},
            {"leg": "ARRIVED_PICKUP", "at": "2026-09-24T09:00:00Z"},
            {"leg": "PACKING", "at": "2026-09-24T09:05:00Z"},
            {"leg": "DISMANTLING", "at": "2026-09-24T10:00:00Z"},
            {"leg": "LOADING", "at": "2026-09-24T10:30:00Z"},
            {"leg": "IN_TRANSIT", "at": "2026-09-24T11:00:00Z"},
            {"leg": "ARRIVED_DROP", "at": "2026-09-24T12:00:00Z"},
            {"leg": "UNLOADING", "at": "2026-09-24T12:05:00Z"},
            {"leg": "REASSEMBLY", "at": "2026-09-24T12:35:00Z"},
            {"leg": "UNPACKING", "at": "2026-09-24T13:00:00Z"},
            {"leg": "DELIVERED", "at": "2026-09-24T13:30:00Z"},
            {"leg": "COMPLETED", "at": "2026-09-24T13:40:00Z"},
        ]
        r = compute_waiting_charge(hist, None)
        self.assertEqual(r["loading_minutes"], 120)
        self.assertEqual(r["unloading_minutes"], 90)  # ends at DELIVERED, not COMPLETED

    def test_pm_skipped_arrival_falls_back_to_loading_leg(self):
        hist = [{"leg": "LOADING", "at": "2026-09-24T10:00:00Z"},
                {"leg": "IN_TRANSIT", "at": "2026-09-24T10:25:00Z"},
                {"leg": "UNLOADING", "at": "2026-09-24T11:00:00Z"},
                {"leg": "COMPLETED", "at": "2026-09-24T11:20:00Z"}]
        r = compute_waiting_charge(hist, None)
        self.assertEqual(r["loading_minutes"], 25)
        self.assertEqual(r["unloading_minutes"], 20)
