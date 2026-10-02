"""
Forensic QA probes (2026-09-30): adversarial vendor API inputs on the real mirrored DB.
Non-object JSON bodies, hostile extra-charge amounts / charge ids, OTP replay/brute force,
cross-vendor (IDOR) access, mass assignment, accept/reject replay.
"""
from decimal import Decimal
from types import SimpleNamespace
from unittest.mock import patch

from rest_framework.test import APIClient

from .test_realdb_gt_lifecycle import RealDbBase, Trip

POL = SimpleNamespace(allow_toll=True, allow_parking=True, max_amount_per_item=Decimal("500"),
                      max_total_per_booking=Decimal("1000"), require_receipt_photo=False)


class _ThrottleIsolated(RealDbBase):
    """workforce_otp throttle state lives in the process cache; do not leak it across tests."""

    def setUp(self):
        super().setUp()
        from django.core.cache import cache
        cache.clear()
        self.addCleanup(cache.clear)


class NonObjectBodyTests(_ThrottleIsolated):
    """A JSON array / scalar body must be a 400, never an unhandled 500."""

    def test_non_object_json_bodies_never_5xx(self):
        t = Trip(fare={"vehicle_class": "truck"}, tag="40")
        self.assertTrue(t.dispatch()[0]); t.start_job()
        for tail in ("logistics-leg/", "logistics-checkpoint/", "logistics-exception/",
                     "logistics-extra-charge/", "stops/", "verify-otp/"):
            for body in ([], [1, 2], "x", 5, None):
                r = t.api.post(t.url(tail), body, format="json")
                self.assertLess(r.status_code, 500, (tail, body, r.status_code))


class ExtraChargeHostileTests(_ThrottleIsolated):
    def _t(self, tag):
        t = Trip(fare={"vehicle_class": "truck"}, tag=tag)
        self.assertTrue(t.dispatch()[0]); t.start_job()
        return t

    def _post(self, t, body):
        with patch("workforce_api.services.extra_charges.policy_for", return_value=POL):
            return t.api.post(t.url("logistics-extra-charge/"), body, format="json")

    def test_hostile_amounts_rejected(self):
        t = self._t("41")
        for amt in ("-5", "0", "0.001", "NaN", "Infinity", "-Infinity", "1e400", "1e30", "99999999999999999999999", "abc",
                    "", None, [5], {"a": 1}, "5,00"):
            r = self._post(t, {"charge_type": "TOLL", "amount": amt, "receipt": "r"})
            self.assertEqual(r.status_code, 400, (amt, r.status_code, getattr(r, "data", None)))
        self.assertEqual(t.events().count("logistics.extra_charge"), 0)

    def test_boundary_amounts(self):
        t = self._t("42")
        self.assertEqual(self._post(t, {"charge_type": "TOLL", "amount": "500", "receipt": "r"}).status_code, 200)
        self.assertEqual(self._post(t, {"charge_type": "TOLL", "amount": "500.01", "receipt": "r"}).status_code, 400)
        self.assertEqual(self._post(t, {"charge_type": "TOLL", "amount": "0.01", "receipt": "r"}).status_code, 200)

    def test_hostile_charge_id_and_note_never_5xx(self):
        t = self._t("43")
        for cid in ([1], {"a": 1}, "x" * 5000, "", None, 12, "<script>"):
            r = self._post(t, {"charge_type": "TOLL", "amount": "10", "receipt": "r", "charge_id": cid})
            self.assertLess(r.status_code, 500, (cid, r.status_code))

    def test_client_charge_id_is_bounded(self):
        t = self._t("44")
        r = self._post(t, {"charge_type": "TOLL", "amount": "10", "receipt": "r", "charge_id": "x" * 5000})
        self.assertEqual(r.status_code, 200)
        cid = r.data["charge_id"]
        self.assertLessEqual(len(cid), 64)

    def test_replayed_charge_id_is_not_duplicated(self):
        t = self._t("45")
        for _ in range(2):
            self.assertEqual(self._post(t, {"charge_type": "TOLL", "amount": "10", "receipt": "r", "charge_id": "abc123"}).status_code, 200)
        self.assertEqual(t.events().count("logistics.extra_charge"), 1)

    def test_other_driver_and_anonymous_refused(self):
        t = self._t("46")
        other = Trip(fare={"vehicle_class": "truck"}, tag="47")
        with patch("workforce_api.services.extra_charges.policy_for", return_value=POL):
            r = other.api.post(t.url("logistics-extra-charge/"), {"charge_type": "TOLL", "amount": "10", "receipt": "r"}, format="json")
            self.assertEqual(r.status_code, 403)
            r = APIClient().post(t.url("logistics-extra-charge/"), {"charge_type": "TOLL", "amount": "10", "receipt": "r"}, format="json")
            self.assertIn(r.status_code, (401, 403))


class OtpAndStateProbeTests(_ThrottleIsolated):
    def _to_drop_otp(self, tag):
        t = Trip(fare={"vehicle_class": "truck"}, tag=tag)
        self.assertTrue(t.dispatch()[0]); t.start_job()
        self.ok(t.gps("PICKUP")); self.ok(t.leg("LOADING")); self.ok(t.checkpoint("PICKUP", "photo"))
        self.ok(t.leg("EN_ROUTE_DROP")); self.ok(t.gps("DROP")); self.ok(t.leg("UNLOADING"))
        return t

    def test_delivery_otp_lockout_and_replay(self):
        t = self._to_drop_otp("50")
        real = t.delivery_otp()
        wrong = "000000" if real != "000000" else "111111"
        for _ in range(5):
            self.assertEqual(t.checkpoint("DROP", "otp", otp=wrong).status_code, 400)
        r = t.checkpoint("DROP", "otp", otp=real)       # correct code after lockout must still be refused
        self.assertEqual((r.status_code, r.data["code"]), (400, "MAX_OTP_ATTEMPTS_EXCEEDED"))

    def test_expired_delivery_otp_refused(self):
        from datetime import timedelta
        from django.utils import timezone
        from workforce_api.models import LogisticsCheckpointVerification as L
        t = self._to_drop_otp("51")
        L.objects.filter(job_id=t.sr.id, checkpoint="DROP").update(otp_expires_at=timezone.now() - timedelta(minutes=1))
        r = t.checkpoint("DROP", "otp", otp=t.delivery_otp())
        self.assertEqual(r.data["code"], "OTP_EXPIRED")

    def test_delivery_otp_of_other_job_or_driver_refused(self):
        t = self._to_drop_otp("52")
        other = Trip(fare={"vehicle_class": "truck"}, tag="53")
        r = other.api.post(t.url("logistics-checkpoint/"), {"checkpoint": "DROP", "action": "otp", "otp": t.delivery_otp()}, format="json")
        self.assertEqual(r.status_code, 403)

    def test_mass_assignment_ignored_and_terminal_leg_refused(self):
        t = self._to_drop_otp("54")
        r = t.api.post(t.url("logistics-leg/"), {"leg": "UNLOADING", "status": "completed", "total_amount": "1",
                                                 "payment_status": "paid"}, format="json")
        self.assertLess(r.status_code, 500)
        s = t.refresh()
        self.assertEqual((s.status, s.total_amount, s.payment_status), ("in_progress", Decimal("500.00"), "pending"))

    def test_accept_replay_and_second_driver(self):
        t = Trip(fare={"vehicle_class": "truck"}, tag="55")
        self.assertTrue(t.dispatch()[0])
        self.assertEqual(t.accept().status_code, 200)
        self.assertLess(t.accept().status_code, 500)
        other = Trip(fare={"vehicle_class": "truck"}, tag="56")
        r = other.api.post(t.url("accept-offer/"))
        self.assertIn(r.status_code, (400, 403, 404, 409))
        r = other.api.post(t.url("reject-offer/"))
        self.assertLess(r.status_code, 500)
        self.assertEqual(t.refresh().assigned_employee_id, t.emp.id)


class CheckpointRadiusLabelTests(RealDbBase):
    def test_gate_labels_and_radius_follow_admin_config(self):
        from workforce_api.services import logistics_checkpoints as lc
        with patch.object(lc, "checkpoint_radius_meters", return_value=400.0), \
                patch.object(lc, "max_otp_attempts", return_value=3):
            self.assertIn("within 400m", lc.REQUIREMENT_LABELS[(lc.PICKUP, lc.GPS)])
            self.assertNotIn("250", lc.REQUIREMENT_LABELS[(lc.DROP, lc.GPS)])
            self.assertEqual(lc._missing_item(lc.PICKUP, lc.GPS)["radius_m"], 400)
            self.assertNotIn("radius_m", lc._missing_item(lc.DROP, lc.OTP))
