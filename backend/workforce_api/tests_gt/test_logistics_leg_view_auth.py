"""
Object-level authorization + waiting-charge exposure on
GET /api/workforce/jobs/<pk>/logistics-leg/ (WorkforceJobLogisticsLegView).
ServiceRequest is an unmanaged mirror with no test table, so the ORM
lookup and the policy lookup are patched.
"""
from decimal import Decimal
from types import SimpleNamespace
from unittest.mock import patch

from django.test import SimpleTestCase
from rest_framework.test import APIRequestFactory, force_authenticate

from workforce_api import views


def _job(assigned_id):
    return SimpleNamespace(
        pk=5, id=5, assigned_employee_id=assigned_id,
        service_category="goods_transport_truck",
        logistics_leg="DELIVERED", logistics_leg_updated_at=None,
        logistics_leg_history=[
            {"leg": "LOADING", "at": "2026-01-01T10:00:00+00:00"},
            {"leg": "EN_ROUTE_DROP", "at": "2026-01-01T10:40:00+00:00"},
            {"leg": "UNLOADING", "at": "2026-01-01T11:30:00+00:00"},
            {"leg": "DELIVERED", "at": "2026-01-01T11:45:00+00:00"},
        ],
    )


class LegViewAuthTests(SimpleTestCase):
    def _get(self, job, emp_id):
        user = SimpleNamespace(
            is_authenticated=True, is_active=True, id=1, pk=1,
            employee_profile=SimpleNamespace(id=emp_id),
        )
        req = APIRequestFactory().get("/x")
        force_authenticate(req, user=user)
        qs = SimpleNamespace(first=lambda: job)
        policy = SimpleNamespace(
            waiting_free_loading_minutes=30, waiting_free_unloading_minutes=None,
            waiting_charge_per_minute=Decimal("2.00"), waiting_charge_cap=None,
        )
        with patch.object(views.WorkforceJobLogisticsLegView, "permission_classes", []), \
             patch.object(views.ServiceRequest.objects, "filter", return_value=qs), \
             patch("workforce_api.services.pricing_policy.policy_for", return_value=policy):
            return views.WorkforceJobLogisticsLegView.as_view()(req, pk=5)

    def test_other_technician_is_forbidden(self):
        resp = self._get(_job(assigned_id=99), emp_id=7)
        self.assertEqual(resp.status_code, 403)
        self.assertNotIn("logistics_leg_history", resp.data)

    def test_assigned_technician_gets_history_and_waiting_charge(self):
        resp = self._get(_job(assigned_id=7), emp_id=7)
        self.assertEqual(resp.status_code, 200)
        wc = resp.data["waiting_charge"]
        self.assertTrue(wc["enabled"])
        self.assertEqual(wc["loading_minutes"], 40)
        self.assertEqual(wc["billable_minutes"], 10)
        self.assertEqual(wc["amount"], "20.00")
