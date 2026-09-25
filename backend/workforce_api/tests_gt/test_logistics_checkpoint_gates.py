"""
Checkpoint verification gates for logistics trips (pickup / drop GPS,
proof photos, delivery OTP) and the notifications each gate-pass fires.

ServiceRequest is an unmanaged mirror with no test table, so jobs are
SimpleNamespace objects; LogisticsCheckpointVerification is a managed model
and is exercised against the real test database.
"""
from types import SimpleNamespace
from unittest.mock import MagicMock, patch

from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import SimpleTestCase, TestCase, override_settings
from rest_framework.test import APIRequestFactory, force_authenticate

from workforce_api import views
from workforce_api.models import LogisticsCheckpointVerification
from workforce_api.services import logistics_checkpoints as lc

PICKUP_LAT, PICKUP_LON = 12.971600, 77.594600
DROP_LAT, DROP_LON = 13.035500, 77.597000


def _job(category="goods_transport_truck", leg="EN_ROUTE_PICKUP", status="in_progress", customer=True, jid=11):
    return SimpleNamespace(
        id=jid, pk=jid, service_category=category, status=status,
        logistics_leg=leg, logistics_leg_updated_at=None, logistics_leg_history=[],
        latitude=PICKUP_LAT, longitude=PICKUP_LON,
        drop_latitude=DROP_LAT, drop_longitude=DROP_LON,
        customer_id=5 if customer else None,
        customer=SimpleNamespace(id=5) if customer else None,
        company=None, company_id=None,
    )


def _state(**flags):
    st = {cp: {lc.GPS: False, lc.PHOTO: False, lc.OTP: False} for cp in lc.CHECKPOINTS}
    for key, val in flags.items():
        cp, req = key.split("_")
        st[cp.upper()][req] = val
    return st


class GateRuleTests(SimpleTestCase):
    def test_gt_requirements_per_leg(self):
        job = _job(leg="EN_ROUTE_PICKUP")
        self.assertEqual(lc.required_before(job, "EN_ROUTE_PICKUP"), [])
        self.assertEqual(lc.required_before(job, "LOADING"), [(lc.PICKUP, lc.GPS)])
        job.logistics_leg = "LOADING"
        self.assertEqual(lc.required_before(job, "EN_ROUTE_DROP"), [(lc.PICKUP, lc.PHOTO)])
        job.logistics_leg = "EN_ROUTE_DROP"
        self.assertEqual(lc.required_before(job, "UNLOADING"), [(lc.DROP, lc.GPS)])
        job.logistics_leg = "UNLOADING"
        self.assertEqual(lc.required_before(job, "DELIVERED"), [(lc.DROP, lc.PHOTO), (lc.DROP, lc.OTP)])

    def test_skip_ahead_cannot_jump_over_checkpoints(self):
        job = _job(leg="EN_ROUTE_PICKUP")
        self.assertEqual(len(lc.required_before(job, "DELIVERED")), 5)

    def test_gates_already_behind_current_leg_not_redemanded(self):
        # A job already at the drop when this shipped must not be stranded
        # demanding pickup evidence it can no longer produce.
        job = _job(leg="EN_ROUTE_DROP")
        self.assertNotIn((lc.PICKUP, lc.GPS), lc.required_before(job, "DELIVERED"))
        self.assertNotIn((lc.PICKUP, lc.PHOTO), lc.required_before(job, "DELIVERED"))

    def test_otp_only_when_customer_to_send_it_to(self):
        job = _job(leg="UNLOADING", customer=False)
        self.assertEqual(lc.required_before(job, "DELIVERED"), [(lc.DROP, lc.PHOTO)])

    @override_settings(LOGISTICS_DROP_OTP_REQUIRED=False)
    def test_otp_kill_switch(self):
        job = _job(leg="UNLOADING")
        self.assertEqual(lc.required_before(job, "DELIVERED"), [(lc.DROP, lc.PHOTO)])

    def test_pm_gates_on_arrival_legs(self):
        job = _job(category="packers_movers", leg="TEAM_EN_ROUTE")
        self.assertEqual(lc.required_before(job, "ARRIVED_PICKUP"), [(lc.PICKUP, lc.GPS)])
        job.logistics_leg = "LOADING"
        self.assertEqual(lc.required_before(job, "IN_TRANSIT"), [(lc.PICKUP, lc.PHOTO)])
        job.logistics_leg = "IN_TRANSIT"
        self.assertEqual(lc.required_before(job, "ARRIVED_DROP"), [(lc.DROP, lc.GPS)])
        job.logistics_leg = "UNPACKING"
        self.assertEqual(lc.required_before(job, "DELIVERED"), [(lc.DROP, lc.PHOTO), (lc.DROP, lc.OTP)])
        job.logistics_leg = "ARRIVED_PICKUP"
        # Ungated work legs between checkpoints are unaffected.
        self.assertEqual(lc.required_before(job, "PACKING"), [])
        self.assertEqual(lc.required_before(job, "LOADING"), [])

    def test_gate_error_lists_what_is_missing(self):
        job = _job(leg="EN_ROUTE_PICKUP")
        msg, missing = lc.checkpoint_gate_error(job, "LOADING", state=_state())
        self.assertIn("Pickup GPS", msg)
        self.assertEqual(missing[0]["checkpoint"], "PICKUP")
        msg, missing = lc.checkpoint_gate_error(job, "LOADING", state=_state(pickup_gps=True))
        self.assertEqual((msg, missing), ("", []))


class LegViewGateTests(SimpleTestCase):
    def _post(self, job, leg, state):
        emp = SimpleNamespace(id=7)
        job.assigned_employee = emp
        user = SimpleNamespace(is_authenticated=True, is_active=True, id=1, pk=1, employee_profile=emp)
        req = APIRequestFactory().post("/x", {"leg": leg}, format="json")
        force_authenticate(req, user=user)
        notify = MagicMock()
        with patch.object(views.WorkforceJobLogisticsLegView, "permission_classes", []), \
             patch.object(views.ServiceRequest.objects, "filter", return_value=SimpleNamespace(first=lambda: job)), \
             patch.object(views, "is_employee_authorized_for_job", return_value=True), \
             patch("workforce_api.services.logistics_checkpoints.checkpoint_state", return_value=state), \
             patch("workforce_api.services.logistics_checkpoints.notify_leg_advanced", notify), \
             patch("workforce_api.services.logistics_events.emit_leg_changed"):
            return views.WorkforceJobLogisticsLegView.as_view()(req, pk=job.id), notify

    def test_loading_blocked_without_pickup_gps(self):
        job = _job(leg="EN_ROUTE_PICKUP")
        resp, notify = self._post(job, "LOADING", _state())
        self.assertEqual(resp.status_code, 400)
        self.assertEqual(resp.data["code"], "CHECKPOINT_VERIFICATION_REQUIRED")
        self.assertEqual(resp.data["missing"][0]["requirement"], "gps")
        self.assertEqual(job.logistics_leg, "EN_ROUTE_PICKUP")
        notify.assert_not_called()

    def test_loading_allowed_after_pickup_gps_and_notifies(self):
        job = _job(leg="EN_ROUTE_PICKUP")
        resp, notify = self._post(job, "LOADING", _state(pickup_gps=True))
        self.assertEqual(resp.status_code, 200, resp.data)
        self.assertEqual(job.logistics_leg, "LOADING")
        notify.assert_called_once_with(job, "LOADING")

    def test_leave_pickup_needs_loading_photo(self):
        job = _job(leg="LOADING")
        resp, _ = self._post(job, "EN_ROUTE_DROP", _state(pickup_gps=True))
        self.assertEqual(resp.status_code, 400)
        resp, _ = self._post(job, "EN_ROUTE_DROP", _state(pickup_gps=True, pickup_photo=True))
        self.assertEqual(resp.status_code, 200)

    def test_unloading_needs_drop_gps(self):
        job = _job(leg="EN_ROUTE_DROP")
        resp, _ = self._post(job, "UNLOADING", _state(pickup_gps=True, pickup_photo=True))
        self.assertEqual(resp.status_code, 400)
        self.assertEqual(resp.data["missing"][0]["checkpoint"], "DROP")

    def test_delivered_needs_photo_and_otp(self):
        job = _job(leg="UNLOADING")
        resp, _ = self._post(job, "DELIVERED", _state(drop_gps=True, drop_photo=True))
        self.assertEqual(resp.status_code, 400)
        self.assertEqual([m["requirement"] for m in resp.data["missing"]], ["otp"])
        resp, _ = self._post(job, "DELIVERED", _state(drop_gps=True, drop_photo=True, drop_otp=True))
        self.assertEqual(resp.status_code, 200)

    def test_jump_to_delivered_from_pickup_blocked(self):
        job = _job(leg="EN_ROUTE_PICKUP")
        resp, _ = self._post(job, "DELIVERED", _state())
        self.assertEqual(resp.status_code, 400)
        self.assertEqual(len(resp.data["missing"]), 5)
        self.assertEqual(job.logistics_leg, "EN_ROUTE_PICKUP")

    def test_idempotent_repeat_not_regated_or_renotified(self):
        job = _job(leg="LOADING")
        resp, notify = self._post(job, "LOADING", _state())
        self.assertEqual(resp.status_code, 200)
        self.assertFalse(resp.data["changed"])
        notify.assert_not_called()


class ProofViewGateTests(SimpleTestCase):
    def _submit(self, state, leg="UNLOADING"):
        emp = SimpleNamespace(id=7)
        job = _job(leg=leg)
        job.assigned_employee = emp
        user = SimpleNamespace(is_authenticated=True, is_active=True, id=1, pk=1,
                               employee_profile=emp, is_superuser=False, role="technician")
        photo = SimpleUploadedFile("a.jpg", b"x", content_type="image/jpeg")
        req = APIRequestFactory().post("/x", {"notes": "done", "after_photo": photo}, format="multipart")
        force_authenticate(req, user=user)
        set_leg = MagicMock(return_value=(True, ""))
        with patch.object(views.WorkforceJobProofView, "permission_classes", []), \
             patch.object(views.ServiceRequest.objects, "filter", return_value=SimpleNamespace(first=lambda: job)), \
             patch.object(views, "is_admin_role", return_value=False), \
             patch.object(views, "is_employee_authorized_for_job", return_value=True), \
             patch.object(views, "_validate_photo_upload", return_value=None), \
             patch.object(views.PostServiceProof.objects, "get_or_create", return_value=(MagicMock(is_submitted=True), True)), \
             patch.object(views, "apply_transition"), \
             patch.object(views.JobPayment.objects, "filter", return_value=SimpleNamespace(first=lambda: None)), \
             patch("workforce_api.services.logistics_checkpoints.checkpoint_state", return_value=state), \
             patch("workforce_api.services.logistics_events.set_logistics_leg", set_leg):
            return views.WorkforceJobProofView.as_view()(req, pk=job.id), set_leg

    def test_proof_cannot_bypass_drop_checkpoint(self):
        resp, set_leg = self._submit(_state(), leg="EN_ROUTE_DROP")
        self.assertEqual(resp.status_code, 400)
        self.assertEqual(resp.data["code"], "CHECKPOINT_VERIFICATION_REQUIRED")
        set_leg.assert_not_called()

    def test_proof_photo_stands_in_for_unloading_photo(self):
        resp, set_leg = self._submit(_state(drop_gps=True, drop_otp=True))
        self.assertEqual(resp.status_code, 200, resp.data)
        set_leg.assert_called_once()


@patch("workforce_api.services.logistics_checkpoints.checkpoint_target",
       side_effect=lambda job, cp: (PICKUP_LAT, PICKUP_LON) if cp == "PICKUP" else (DROP_LAT, DROP_LON))
class CheckpointServiceTests(TestCase):
    """Real LogisticsCheckpointVerification rows; notification channels mocked."""

    @classmethod
    def setUpTestData(cls):
        # ServiceRequest is unmanaged (owned by the Customer app), so the test
        # database has no table for the checkpoint row's FK to point at. A
        # minimal stand-in keeps SQLite's FK check satisfied; it is rolled
        # back with the class transaction.
        from django.db import connection
        with connection.cursor() as cur:
            cur.execute("CREATE TABLE IF NOT EXISTS service_requests_servicerequest (id integer PRIMARY KEY)")
            cur.execute("INSERT OR IGNORE INTO service_requests_servicerequest (id) VALUES (11)")

    def setUp(self):
        self.create_notification = patch("workforce_api.views.create_notification").start()
        self.notify_admins = patch("workforce_api.views._notify_company_admins").start()
        self.webhook = patch("workforce_api.services.customer_webhook.notify_customer_app").start()
        self.addCleanup(patch.stopall)
        self.user = SimpleNamespace(is_superuser=False, is_staff=False)
        self.emp = None

    def _events(self):
        return [c.args[0] for c in self.webhook.call_args_list]

    def test_pickup_gps_outside_geofence_rejected_and_not_recorded(self, _t):
        job = _job()
        ok, data = lc.verify_checkpoint_gps(job, self.emp, self.user, "PICKUP", DROP_LAT, DROP_LON)
        self.assertFalse(ok)
        self.assertEqual(data["code"], "OUTSIDE_GEOFENCE")
        self.assertFalse(lc.checkpoint_state(job)["PICKUP"][lc.GPS])
        self.webhook.assert_not_called()

    def test_pickup_gps_inside_geofence_records_and_notifies_both(self, _t):
        job = _job()
        ok, data = lc.verify_checkpoint_gps(job, self.emp, self.user, "PICKUP", PICKUP_LAT + 0.001, PICKUP_LON)
        self.assertTrue(ok, data)
        self.assertLess(data["distance_m"], 250)
        state = lc.checkpoint_state(job)
        self.assertTrue(state["PICKUP"][lc.GPS])
        self.assertFalse(state["DROP"][lc.GPS])  # separate record per location
        self.create_notification.assert_called_once()
        self.assertEqual(self.create_notification.call_args.kwargs["recipient"], job.customer)
        self.notify_admins.assert_called_once()
        self.assertEqual(self.notify_admins.call_args.kwargs["dedup_key"], "job:11:PICKUP:gps_verified")
        self.assertIn("logistics.checkpoint_verified", self._events())
        # The leg gate now passes for LOADING.
        self.assertEqual(lc.checkpoint_gate_error(job, "LOADING")[0], "")

    def test_drop_gps_is_checked_against_drop_not_pickup(self, _t):
        job = _job(leg="EN_ROUTE_DROP")
        ok, _ = lc.verify_checkpoint_gps(job, self.emp, self.user, "DROP", PICKUP_LAT, PICKUP_LON)
        self.assertFalse(ok)
        ok, _ = lc.verify_checkpoint_gps(job, self.emp, self.user, "DROP", DROP_LAT, DROP_LON)
        self.assertTrue(ok)

    def test_geofence_override_allowed_but_flagged(self, _t):
        job = _job()
        ok, data = lc.verify_checkpoint_gps(job, None, self.user, "PICKUP", DROP_LAT, DROP_LON)
        self.assertFalse(ok)
        with patch.object(lc, "_is_override", return_value=True):
            ok, data = lc.verify_checkpoint_gps(job, None, self.user, "PICKUP", DROP_LAT, DROP_LON)
        self.assertTrue(ok)
        self.assertEqual(data["geofence_note"], "override")

    def test_photo_requires_gps_first_then_notifies(self, _t):
        job = _job(leg="LOADING")
        photo = SimpleUploadedFile("load.jpg", b"img", content_type="image/jpeg")
        ok, data = lc.record_checkpoint_photo(job, self.emp, "PICKUP", photo)
        self.assertFalse(ok)
        self.assertEqual(data["code"], "GPS_REQUIRED_FIRST")
        lc.verify_checkpoint_gps(job, self.emp, self.user, "PICKUP", PICKUP_LAT, PICKUP_LON)
        self.webhook.reset_mock()
        self.notify_admins.reset_mock()
        with patch("django.core.files.storage.FileSystemStorage._save", return_value="logistics_checkpoints/load.jpg"):
            ok, _ = lc.record_checkpoint_photo(job, self.emp, "PICKUP", photo)
        self.assertTrue(ok)
        self.assertTrue(lc.checkpoint_state(job)["PICKUP"][lc.PHOTO])
        self.assertEqual(self.notify_admins.call_args.kwargs["dedup_key"], "job:11:PICKUP:photo_submitted")
        self.assertIn("logistics.checkpoint_verified", self._events())

    def test_drop_gps_issues_delivery_otp_and_otp_verifies(self, _t):
        job = _job(leg="EN_ROUTE_DROP")
        ok, data = lc.verify_checkpoint_gps(job, self.emp, self.user, "DROP", DROP_LAT, DROP_LON)
        self.assertTrue(data["otp_issued"])
        self.assertIn("logistics.delivery_otp_issued", self._events())
        otp_notifs = [c for c in self.create_notification.call_args_list
                      if c.kwargs.get("notification_type") == "DELIVERY_OTP"]
        self.assertEqual(len(otp_notifs), 1)
        rec = LogisticsCheckpointVerification.objects.get(job_id=job.id, checkpoint="DROP")
        wrong = "000000" if rec.otp_code != "000000" else "111111"
        ok, data = lc.verify_delivery_otp(job, self.emp, wrong)
        self.assertFalse(ok)
        self.assertEqual(data["code"], "INVALID_OTP")
        self.assertFalse(lc.checkpoint_state(job)["DROP"][lc.OTP])
        self.notify_admins.reset_mock()
        ok, data = lc.verify_delivery_otp(job, self.emp, rec.otp_code)
        self.assertTrue(ok, data)
        self.assertTrue(lc.checkpoint_state(job)["DROP"][lc.OTP])
        self.assertEqual(self.notify_admins.call_args.kwargs["dedup_key"], "job:11:DROP:otp_verified")

    def test_otp_attempt_limit(self, _t):
        job = _job(leg="EN_ROUTE_DROP")
        lc.verify_checkpoint_gps(job, self.emp, self.user, "DROP", DROP_LAT, DROP_LON)
        rec = LogisticsCheckpointVerification.objects.get(job_id=job.id, checkpoint="DROP")
        wrong = "000000" if rec.otp_code != "000000" else "111111"
        for _ in range(5):
            lc.verify_delivery_otp(job, self.emp, wrong)
        ok, data = lc.verify_delivery_otp(job, self.emp, rec.otp_code)
        self.assertFalse(ok)
        self.assertEqual(data["code"], "MAX_OTP_ATTEMPTS_EXCEEDED")

    def test_repeat_gps_verify_does_not_renotify(self, _t):
        job = _job()
        lc.verify_checkpoint_gps(job, self.emp, self.user, "PICKUP", PICKUP_LAT, PICKUP_LON)
        lc.verify_checkpoint_gps(job, self.emp, self.user, "PICKUP", PICKUP_LAT, PICKUP_LON)
        self.assertEqual(self.notify_admins.call_count, 1)

    def test_leg_advance_notifies_customer_and_admin(self, _t):
        job = _job()
        lc.notify_leg_advanced(job, "LOADING")
        self.create_notification.assert_called_once()
        self.assertEqual(self.create_notification.call_args.kwargs["notification_type"], "LOGISTICS_LEG")
        self.notify_admins.assert_called_once()
        self.assertEqual(self.notify_admins.call_args.kwargs["dedup_key"], "job:11:leg:LOADING")

    def _call_checkpoint_view(self, job, data, method="post"):
        # id=None: no Employee row exists in the test DB for the FK.
        emp = SimpleNamespace(id=None)
        job.assigned_employee_id = None
        job.assigned_employee = emp
        user = SimpleNamespace(is_authenticated=True, is_active=True, id=1, pk=1,
                               employee_profile=emp, is_superuser=False, is_staff=False)
        factory = APIRequestFactory()
        req = factory.post("/x", data, format="json") if method == "post" else factory.get("/x")
        force_authenticate(req, user=user)
        with patch.object(views.WorkforceJobLogisticsCheckpointView, "permission_classes", []), \
             patch.object(views.WorkforceJobLogisticsCheckpointView, "throttle_classes", []), \
             patch.object(views.ServiceRequest.objects, "filter", return_value=SimpleNamespace(first=lambda: job)), \
             patch.object(views, "is_employee_authorized_for_job", return_value=True), \
             patch("workforce_api.services.logistics_checkpoints._get_record",
                   side_effect=lambda j, cp, e: LogisticsCheckpointVerification.objects.get_or_create(
                       job_id=j.id, checkpoint=cp)[0]):
            return views.WorkforceJobLogisticsCheckpointView.as_view()(req, pk=job.id)

    def test_checkpoint_endpoint_gps_then_gate_summary(self, _t):
        job = _job()
        resp = self._call_checkpoint_view(job, {"checkpoint": "PICKUP", "action": "gps",
                                                "lat": DROP_LAT, "lon": DROP_LON})
        self.assertEqual(resp.status_code, 403)
        resp = self._call_checkpoint_view(job, {}, method="get")
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(resp.data["gates"]["LOADING"][0]["requirement"], "gps")
        resp = self._call_checkpoint_view(job, {"checkpoint": "PICKUP", "action": "gps",
                                                "lat": PICKUP_LAT, "lon": PICKUP_LON})
        self.assertEqual(resp.status_code, 200, resp.data)
        self.assertTrue(resp.data["checkpoints"]["PICKUP"]["gps"])
        self.assertEqual(resp.data["gates"]["LOADING"], [])

    def test_checkpoint_endpoint_rejects_otp_on_pickup(self, _t):
        resp = self._call_checkpoint_view(_job(), {"checkpoint": "PICKUP", "action": "otp", "otp": "123456"})
        self.assertEqual(resp.status_code, 400)
