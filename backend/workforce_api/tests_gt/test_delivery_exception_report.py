"""Driver-reported trip exceptions: validation by trip stage, authorization, event emission."""
from types import SimpleNamespace
from unittest.mock import patch

from django.test import SimpleTestCase
from rest_framework.test import APIRequestFactory, force_authenticate

from workforce_api import views
from workforce_api.services.delivery_exceptions import exception_error


def _job(leg, status="in_progress", assigned_id=7):
    return SimpleNamespace(pk=5, id=5, assigned_employee_id=assigned_id, service_category="goods_transport_truck",
                           logistics_leg=leg, status=status)


class RulesTests(SimpleTestCase):
    def test_types_are_tied_to_the_trip_stage(self):
        self.assertIsNone(exception_error("RECEIVER_UNAVAILABLE", "UNLOADING", "phone switched off"))
        self.assertIn("cannot be reported", exception_error("RECEIVER_UNAVAILABLE", "EN_ROUTE_PICKUP", "phone switched off"))
        self.assertIsNone(exception_error("CUSTOMER_UNREACHABLE_AT_PICKUP", "EN_ROUTE_PICKUP", "not answering"))
        self.assertIn("cannot be reported", exception_error("CUSTOMER_UNREACHABLE_AT_PICKUP", "DELIVERED", "not answering"))

    def test_unknown_type_and_missing_note(self):
        self.assertIn("Unknown", exception_error("NOPE", "UNLOADING", "abcdef"))
        self.assertIn("note", exception_error("RECEIVER_UNAVAILABLE", "UNLOADING", "  "))


class ViewTests(SimpleTestCase):
    def _post(self, job, body, emp_id=7):
        user = SimpleNamespace(is_authenticated=True, is_active=True, id=1, pk=1,
                               employee_profile=SimpleNamespace(id=emp_id, company_id=None, user=None))
        req = APIRequestFactory().post("/x", body, format="json")
        force_authenticate(req, user=user)
        qs = SimpleNamespace(first=lambda: job)
        with patch.object(views.WorkforceJobLogisticsExceptionView, "permission_classes", []), \
             patch.object(views.ServiceRequest.objects, "filter", return_value=qs), \
             patch.object(views, "is_employee_authorized_for_job", return_value=True), \
             patch("workforce_api.models.WorkforceEventLog.objects.create") as log, \
             patch("workforce_api.services.customer_webhook.notify_customer_app") as hook:
            resp = views.WorkforceJobLogisticsExceptionView.as_view()(req, pk=5)
            return resp, log, hook

    def test_valid_report_logs_and_notifies_customer_app(self):
        resp, log, hook = self._post(_job("UNLOADING"), {"exception_type": "RECEIVER_UNAVAILABLE", "notes": "Gate locked, phone off"})
        self.assertEqual(resp.status_code, 200, resp.data)
        log.assert_called_once()
        args, kw = hook.call_args
        self.assertEqual(args[0], "logistics.delivery_exception")
        self.assertEqual(kw["exception_type"], "RECEIVER_UNAVAILABLE")
        self.assertEqual(kw["leg"], "UNLOADING")

    def test_wrong_stage_rejected_and_nothing_sent(self):
        resp, log, hook = self._post(_job("EN_ROUTE_PICKUP"), {"exception_type": "RECEIVER_UNAVAILABLE", "notes": "Gate locked"})
        self.assertEqual(resp.status_code, 400)
        hook.assert_not_called()

    def test_other_technician_forbidden(self):
        resp, log, hook = self._post(_job("UNLOADING", assigned_id=99), {"exception_type": "RECEIVER_UNAVAILABLE", "notes": "Gate locked"})
        self.assertEqual(resp.status_code, 403)
        hook.assert_not_called()

    def test_terminal_job_rejected(self):
        resp, log, hook = self._post(_job("UNLOADING", status="completed"), {"exception_type": "RECEIVER_UNAVAILABLE", "notes": "Gate locked"})
        self.assertEqual(resp.status_code, 400)
