"""Driver-facing waiting charge must follow the Customer GTWaitingChargePolicy
(single source of truth) with the same semantics as its charge_for()."""
from datetime import datetime, timedelta, timezone
from decimal import Decimal
from types import SimpleNamespace
from unittest.mock import patch

from django.test import SimpleTestCase

from workforce_api.services import waiting_charges as wc

SEAM = "workforce_api.services.waiting_charges.customer_policy_for"
T0 = datetime(2026, 1, 1, 10, 0, tzinfo=timezone.utc)


def _pol(**kw):
    d = dict(is_enabled=True, is_active=True, free_minutes_per_stop=10,
             rate_per_minute=Decimal("3.00"), max_charge_per_booking=None)
    d.update(kw)
    return SimpleNamespace(**d)


def _job(stops=None, category="goods_transport_truck"):
    hist = [
        {"leg": "LOADING", "at": T0.isoformat()},
        {"leg": "EN_ROUTE_DROP", "at": (T0 + timedelta(minutes=25)).isoformat()},
    ]
    ts = SimpleNamespace(all=lambda: stops or [])
    return SimpleNamespace(service_category=category, logistics_leg_history=hist, trip_stops=ts)


class SingleSourceTests(SimpleTestCase):
    def test_no_policy_is_zero(self):
        with patch(SEAM, return_value=None):
            r = wc.waiting_charge_for_booking(_job())
        self.assertFalse(r["enabled"]); self.assertEqual(r["amount"], Decimal("0.00"))

    def test_disabled_policy_is_zero(self):
        with patch(SEAM, return_value=_pol(is_enabled=False)):
            self.assertFalse(wc.waiting_charge_for_booking(_job())["enabled"])

    def test_history_fallback_uses_customer_free_minutes(self):
        with patch(SEAM, return_value=_pol()):
            r = wc.waiting_charge_for_booking(_job())
        self.assertEqual(r["billable_minutes"], 15)
        self.assertEqual(r["amount"], Decimal("45.00"))

    def test_cap_applies(self):
        with patch(SEAM, return_value=_pol(max_charge_per_booking=Decimal("20"))):
            self.assertEqual(wc.waiting_charge_for_booking(_job())["amount"], Decimal("20.00"))

    def test_trip_stops_take_precedence_floor_minutes(self):
        stop = SimpleNamespace(arrived_at=T0, completed_at=T0 + timedelta(minutes=30, seconds=59))
        with patch(SEAM, return_value=_pol()):
            r = wc.waiting_charge_for_booking(_job(stops=[stop]))
        self.assertEqual(r["billable_minutes"], 20)

    def test_pm_without_stops_never_uses_history(self):
        with patch(SEAM, return_value=_pol()):
            r = wc.waiting_charge_for_booking(_job(category="packers_movers"))
        self.assertEqual(r["amount"], Decimal("0.00"))
