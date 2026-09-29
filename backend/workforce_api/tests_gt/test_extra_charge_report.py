"""Driver toll/parking report: mirrored Admin policy gates it; receipt required; event emitted."""
from decimal import Decimal
from types import SimpleNamespace
from unittest.mock import patch

from django.test import SimpleTestCase
from rest_framework.test import APIRequestFactory, force_authenticate

from workforce_api import views
from workforce_api.services.extra_charges import charge_error

POL = SimpleNamespace(allow_toll=True, allow_parking=False, max_amount_per_item=Decimal("100"), max_total_per_booking=Decimal("150"))


def _job(status="in_progress", assigned_id=7, extras=None):
    return SimpleNamespace(pk=5, id=5, assigned_employee_id=assigned_id, service_category="goods_transport_truck",
                           logistics_leg="EN_ROUTE_DROP", status=status, extra_charges=extras or [])


class RuleTests(SimpleTestCase):
    def test_policy_gates(self):
        self.assertIn("not enabled", charge_error(None, "TOLL", "10"))
        self.assertIsNone(charge_error(POL, "TOLL", "85"))
        self.assertIn("not accepted", charge_error(POL, "PARKING", "10"))
        self.assertIn("cannot exceed", charge_error(POL, "TOLL", "101"))
        self.assertIn("Total", charge_error(POL, "TOLL", "90", Decimal("80")))
        self.assertIn("amount", charge_error(POL, "TOLL", "abc"))


class ViewTests(SimpleTestCase):
    def _post(self, job, body, pol=POL, emp_id=7):
        user = SimpleNamespace(is_authenticated=True, is_active=True, id=1, pk=1,
                               employee_profile=SimpleNamespace(id=emp_id, company_id=None, user=None))
        req = APIRequestFactory().post("/x", body, format="json")
        force_authenticate(req, user=user)
        qs = SimpleNamespace(first=lambda: job)
        with patch.object(views.WorkforceJobLogisticsExtraChargeView, "permission_classes", []), \
             patch.object(views.ServiceRequest.objects, "filter", return_value=qs), \
             patch.object(views, "is_employee_authorized_for_job", return_value=True), \
             patch("workforce_api.services.extra_charges.policy_for", return_value=pol), \
             patch("workforce_api.models.WorkforceEventLog.objects.create") as log, \
             patch("workforce_api.services.customer_webhook.notify_customer_app") as hook:
            resp = views.WorkforceJobLogisticsExtraChargeView.as_view()(req, pk=5)
            return resp, log, hook

    def test_valid_report_notifies_customer_app(self):
        resp, log, hook = self._post(_job(), {"charge_type": "toll", "amount": "85", "receipt": "r1.jpg"})
        self.assertEqual(resp.status_code, 200, resp.data)
        args, kw = hook.call_args
        self.assertEqual(args[0], "logistics.extra_charge")
        self.assertEqual((kw["charge_type"], kw["amount"]), ("TOLL", "85.00"))

    def test_receipt_required(self):
        resp, log, hook = self._post(_job(), {"charge_type": "TOLL", "amount": "85"})
        self.assertEqual(resp.status_code, 400); hook.assert_not_called()

    def test_disabled_policy_rejected(self):
        resp, log, hook = self._post(_job(), {"charge_type": "TOLL", "amount": "85", "receipt": "x"}, pol=None)
        self.assertEqual(resp.status_code, 400); hook.assert_not_called()

    def test_running_total_cap_uses_applied_entries(self):
        job = _job(extras=[{"status": "APPLIED", "amount": "80"}])
        resp, log, hook = self._post(job, {"charge_type": "TOLL", "amount": "90", "receipt": "x"})
        self.assertEqual(resp.status_code, 400)

    def test_other_technician_forbidden_and_terminal_rejected(self):
        self.assertEqual(self._post(_job(assigned_id=99), {"charge_type": "TOLL", "amount": "5", "receipt": "x"})[0].status_code, 403)
        self.assertEqual(self._post(_job(status="completed"), {"charge_type": "TOLL", "amount": "5", "receipt": "x"})[0].status_code, 400)


class ReceiptPhotoTests(ViewTests):
    def _photo(self):
        import io
        from PIL import Image
        from django.core.files.uploadedfile import SimpleUploadedFile
        buf = io.BytesIO(); Image.new("RGB", (120, 120), "white").save(buf, "PNG")
        return SimpleUploadedFile("r.png", buf.getvalue(), content_type="image/png")

    def _post_mp(self, job, body, pol):
        user = SimpleNamespace(is_authenticated=True, is_active=True, id=1, pk=1,
                               employee_profile=SimpleNamespace(id=7, company_id=None, user=None))
        req = APIRequestFactory().post("/x", body, format="multipart")
        force_authenticate(req, user=user)
        qs = SimpleNamespace(first=lambda: job)
        with patch.object(views.WorkforceJobLogisticsExtraChargeView, "permission_classes", []), \
             patch.object(views.ServiceRequest.objects, "filter", return_value=qs), \
             patch.object(views, "is_employee_authorized_for_job", return_value=True), \
             patch("workforce_api.services.extra_charges.policy_for", return_value=pol), \
             patch("django.core.files.storage.default_storage.save", return_value="logistics_receipts/5_r.png"), \
             patch("django.core.files.storage.default_storage.url", return_value="/media/logistics_receipts/5_r.png"), \
             patch("workforce_api.models.WorkforceEventLog.objects.create"), \
             patch("workforce_api.services.customer_webhook.notify_customer_app") as hook:
            return views.WorkforceJobLogisticsExtraChargeView.as_view()(req, pk=5), hook

    def test_photo_is_stored_and_url_sent_to_customer_app(self):
        resp, hook = self._post_mp(_job(), {"charge_type": "TOLL", "amount": "40", "receipt_photo": self._photo()}, POL)
        self.assertEqual(resp.status_code, 200, resp.data)
        self.assertEqual(hook.call_args.kwargs["receipt_photo_url"], "/media/logistics_receipts/5_r.png")

    def test_policy_can_require_photo(self):
        pol = SimpleNamespace(**{**POL.__dict__, "require_receipt_photo": True})
        resp, hook = self._post_mp(_job(), {"charge_type": "TOLL", "amount": "40", "receipt": "ref-1"}, pol)
        self.assertEqual(resp.status_code, 400); hook.assert_not_called()

    def test_non_image_rejected(self):
        from django.core.files.uploadedfile import SimpleUploadedFile
        bad = SimpleUploadedFile("r.html", b"<script>", content_type="text/html")
        resp, hook = self._post_mp(_job(), {"charge_type": "TOLL", "amount": "40", "receipt_photo": bad}, POL)
        self.assertEqual(resp.status_code, 400); hook.assert_not_called()
