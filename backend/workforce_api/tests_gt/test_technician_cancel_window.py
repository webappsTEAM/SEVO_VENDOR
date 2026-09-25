"""
Admin-configurable technician no-penalty cancellation window
(WorkforceServicePricingPolicy.technician_free_cancel_minutes, default 5).

ServiceRequest / EmployeeJob are unmanaged mirrors with no test tables, so
the view test patches their managers; the policy lookup is patched too.
"""
from datetime import timedelta
from types import SimpleNamespace
from unittest.mock import MagicMock, patch

from django.test import SimpleTestCase, TestCase
from django.utils import timezone
from rest_framework.test import APIRequestFactory, force_authenticate

from workforce_api import views
from workforce_api.invoice_views import _apply_policy_fields, _serialize_policy
from workforce_api.models import WorkforceServicePricingPolicy
from workforce_api.services import pricing_policy
from workforce_api.services.pricing_policy import technician_cancel_window_minutes


class CancelWindowHelperTests(SimpleTestCase):
    def test_default_when_no_policy(self):
        with patch.object(pricing_policy, "policy_for", return_value=None):
            self.assertEqual(technician_cancel_window_minutes("goods_transport_truck"), 5)

    def test_configured_value_used(self):
        pol = SimpleNamespace(technician_free_cancel_minutes=12)
        with patch.object(pricing_policy, "policy_for", return_value=pol):
            self.assertEqual(technician_cancel_window_minutes("packers_movers"), 12)

    def test_zero_is_respected(self):
        pol = SimpleNamespace(technician_free_cancel_minutes=0)
        with patch.object(pricing_policy, "policy_for", return_value=pol):
            self.assertEqual(technician_cancel_window_minutes("x"), 0)

    def test_lookup_failure_falls_back_to_default(self):
        with patch.object(pricing_policy, "policy_for", side_effect=RuntimeError("db down")):
            self.assertEqual(technician_cancel_window_minutes("x"), 5)

    def test_no_hardcoded_five_minute_window_left_in_views(self):
        import inspect
        src = inspect.getsource(views)
        self.assertNotIn("timedelta(minutes=5)", src)


class CancelWindowPolicyApiTests(SimpleTestCase):
    def test_model_default_is_five(self):
        # Unsaved: accounts_user (FK target of updated_by) is unmanaged here.
        p = WorkforceServicePricingPolicy(service_category="goods_transport_truck")
        self.assertEqual(p.technician_free_cancel_minutes, 5)
        self.assertEqual(_serialize_policy(p)["technician_free_cancel_minutes"], 5)

    def test_admin_can_set_and_reset(self):
        p = WorkforceServicePricingPolicy(service_category="packers_movers")
        self.assertIsNone(_apply_policy_fields(p, {"technician_free_cancel_minutes": "15"}))
        self.assertEqual(p.technician_free_cancel_minutes, 15)
        self.assertIsNone(_apply_policy_fields(p, {"technician_free_cancel_minutes": ""}))
        self.assertEqual(p.technician_free_cancel_minutes, 5)

    def test_validation(self):
        p = WorkforceServicePricingPolicy(service_category="packers_movers")
        self.assertIn("between", _apply_policy_fields(p, {"technician_free_cancel_minutes": -1}))
        self.assertIn("between", _apply_policy_fields(p, {"technician_free_cancel_minutes": 5000}))
        self.assertIn("whole number", _apply_policy_fields(p, {"technician_free_cancel_minutes": "abc"}))


class _Stop(Exception):
    pass


class TechnicianCancelViewWindowTests(TestCase):
    def _post(self, accepted_minutes_ago, window):
        emp = SimpleNamespace(id=7, pk=7, company_id=None)
        user = SimpleNamespace(is_authenticated=True, is_active=True, id=1, pk=1, employee_profile=emp)
        job = SimpleNamespace(
            pk=5, id=5, company_id=None, assigned_employee=emp, status="accepted",
            service_category="goods_transport_truck", updated_at=timezone.now(),
        )
        emp_job = MagicMock()
        emp_job.status = "ACCEPTED"
        emp_job.accepted_date = timezone.now() - timedelta(minutes=accepted_minutes_ago)
        emp_job.save.side_effect = _Stop()  # halt right after the window check passes

        sfu = MagicMock()
        sfu.filter.return_value.first.return_value = job
        req = APIRequestFactory().post("/x", {"reason_code": "TOO_FAR"}, format="json")
        force_authenticate(req, user=user)
        policy = None if window is None else SimpleNamespace(technician_free_cancel_minutes=window)
        from service_requests.models import EmployeeJob
        with patch.object(views.WorkforceJobTechnicianCancelView, "permission_classes", []), \
             patch.object(views.ServiceRequest.objects, "select_for_update", return_value=sfu), \
             patch.object(EmployeeJob.objects, "filter", return_value=MagicMock(first=lambda: emp_job)), \
             patch.object(pricing_policy, "policy_for", return_value=policy):
            try:
                return views.WorkforceJobTechnicianCancelView.as_view()(req, pk=5)
            except _Stop:
                return "PASSED_WINDOW_CHECK"

    def test_default_window_rejects_after_five_minutes(self):
        resp = self._post(accepted_minutes_ago=6, window=None)
        self.assertEqual(resp.status_code, 409)
        self.assertEqual(resp.data["code"], "CANCELLATION_WINDOW_EXPIRED")
        self.assertIn("5 minutes", resp.data["error"])

    def test_default_window_allows_within_five_minutes(self):
        self.assertEqual(self._post(accepted_minutes_ago=4, window=None), "PASSED_WINDOW_CHECK")

    def test_admin_shortened_window_rejects(self):
        resp = self._post(accepted_minutes_ago=4, window=3)
        self.assertEqual(resp.status_code, 409)
        self.assertIn("3 minutes", resp.data["error"])

    def test_admin_widened_window_allows(self):
        self.assertEqual(self._post(accepted_minutes_ago=8, window=10), "PASSED_WINDOW_CHECK")
