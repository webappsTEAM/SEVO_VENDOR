"""
Pass-3 state-machine safety for logistics legs:
  * final legs (DELIVERED / COMPLETED) require the job to have been started
  * P&M jobs get a valid initial leg on accept (previously EN_ROUTE_PICKUP,
    which the P&M sequence rejects, so it was silently dropped)
  * P&M ordering: backwards moves rejected, repeats idempotent
  * proof of delivery sets the DELIVERED leg for logistics jobs
  * dispatch "why unassigned" keeps the specific rejection reason
ServiceRequest is an unmanaged mirror with no test table, so jobs are
SimpleNamespace objects (set_logistics_leg's non-ORM branch) and ORM
lookups in views are patched.
"""
from types import SimpleNamespace
from unittest.mock import MagicMock, patch

from django.test import SimpleTestCase
from rest_framework.test import APIRequestFactory, force_authenticate

from workforce_api import views
from workforce_api.services import logistics_events as le
from workforce_api.services import automatic_dispatch as ad
from workforce_api.services import logistics_checkpoints as lc

# These tests cover leg ordering / final-leg status rules. The checkpoint
# verification gates (GPS / photo / OTP) are exercised separately in
# test_logistics_checkpoint_gates.py, so here every checkpoint is satisfied.
_ALL_VERIFIED = {cp: {lc.GPS: True, lc.PHOTO: True, lc.OTP: True} for cp in lc.CHECKPOINTS}


def _job(category, leg="", status="accepted"):
    return SimpleNamespace(
        id=11, service_category=category, status=status,
        logistics_leg=leg, logistics_leg_updated_at=None, logistics_leg_history=[],
    )


@patch("workforce_api.services.logistics_events.emit_leg_changed")
class FinalLegGateTests(SimpleTestCase):
    def test_delivered_rejected_before_job_started(self, _emit):
        for st in ("accepted", "on_the_way", "en_route", "arrived", "service_started"):
            self.assertTrue(le.final_leg_status_error(st, "DELIVERED"), st)
            self.assertTrue(le.final_leg_status_error(st, "completed"), st)

    def test_delivered_allowed_once_started(self, _emit):
        for st in ("in_progress", "on_hold", "proof_submitted", "follow_up_required"):
            self.assertEqual(le.final_leg_status_error(st, "DELIVERED"), "", st)

    def test_non_final_legs_not_gated(self, _emit):
        self.assertEqual(le.final_leg_status_error("accepted", "LOADING"), "")
        self.assertEqual(le.final_leg_status_error("accepted", "PACKING"), "")


@patch("workforce_api.services.logistics_events.emit_leg_changed")
class PackersMoversOrderingTests(SimpleTestCase):
    def test_initial_leg_per_category(self, _emit):
        self.assertEqual(le.initial_leg_for_category("packers_movers"), "ASSIGNED")
        self.assertEqual(le.initial_leg_for_category("goods_transport_truck"), "EN_ROUTE_PICKUP")
        self.assertEqual(le.initial_leg_for_category("goods_transport"), "EN_ROUTE_PICKUP")

    def test_pm_initial_leg_is_accepted_by_sequence(self, _emit):
        job = _job("packers_movers")
        changed, err = le.set_logistics_leg(job, le.initial_leg_for_category("packers_movers"))
        self.assertEqual((changed, err), (True, ""))
        self.assertEqual(job.logistics_leg, "ASSIGNED")
        # The old behaviour: EN_ROUTE_PICKUP is not a P&M leg.
        changed, err = le.set_logistics_leg(_job("packers_movers"), "EN_ROUTE_PICKUP")
        self.assertFalse(changed)
        self.assertTrue(err)

    def test_pm_forward_path(self, _emit):
        job = _job("packers_movers", leg="ARRIVED_PICKUP")
        for leg in ("PACKING", "LOADING", "IN_TRANSIT", "UNLOADING", "UNPACKING", "DELIVERED", "COMPLETED"):
            changed, err = le.set_logistics_leg(job, leg)
            self.assertEqual((changed, err), (True, ""), leg)
        self.assertEqual([h["leg"] for h in job.logistics_leg_history],
                         ["PACKING", "LOADING", "IN_TRANSIT", "UNLOADING", "UNPACKING", "DELIVERED", "COMPLETED"])

    def test_pm_cannot_pack_after_loading_or_move_back(self, _emit):
        job = _job("packers_movers", leg="LOADING")
        for back in ("PACKING", "DISMANTLING", "ARRIVED_PICKUP", "ASSIGNED"):
            changed, err = le.set_logistics_leg(job, back)
            self.assertFalse(changed, back)
            self.assertIn("backwards", err)
        job = _job("packers_movers", leg="UNPACKING")
        changed, err = le.set_logistics_leg(job, "IN_TRANSIT")
        self.assertIn("backwards", err)

    def test_pm_repeat_is_idempotent(self, emit):
        job = _job("packers_movers", leg="")
        le.set_logistics_leg(job, "PACKING")
        changed, err = le.set_logistics_leg(job, "PACKING")
        self.assertEqual((changed, err), (False, ""))
        self.assertEqual(len(job.logistics_leg_history), 1)
        self.assertEqual(emit.call_count, 1)

    def test_gt_booking_cannot_use_pm_legs(self, _emit):
        changed, err = le.set_logistics_leg(_job("goods_transport_truck", leg="LOADING"), "IN_TRANSIT")
        self.assertFalse(changed)
        self.assertTrue(err)


class LegViewFinalLegTests(SimpleTestCase):
    def _post(self, job, leg):
        emp = SimpleNamespace(id=7)
        job.assigned_employee = emp
        job.pk = job.id
        user = SimpleNamespace(is_authenticated=True, is_active=True, id=1, pk=1, employee_profile=emp)
        req = APIRequestFactory().post("/x", {"leg": leg}, format="json")
        force_authenticate(req, user=user)
        qs = SimpleNamespace(first=lambda: job)
        with patch.object(views.WorkforceJobLogisticsLegView, "permission_classes", []), \
             patch.object(views.ServiceRequest.objects, "filter", return_value=qs), \
             patch.object(views, "is_employee_authorized_for_job", return_value=True), \
             patch("workforce_api.services.logistics_checkpoints.checkpoint_state", return_value=_ALL_VERIFIED), \
             patch("workforce_api.services.logistics_checkpoints.notify_leg_advanced"), \
             patch("workforce_api.services.logistics_events.emit_leg_changed"):
            return views.WorkforceJobLogisticsLegView.as_view()(req, pk=job.id)

    def test_delivered_before_start_rejected(self):
        job = _job("goods_transport_truck", leg="EN_ROUTE_PICKUP", status="accepted")
        resp = self._post(job, "DELIVERED")
        self.assertEqual(resp.status_code, 400)
        self.assertEqual(resp.data["code"], "FINAL_LEG_NOT_ALLOWED_YET")
        self.assertEqual(job.logistics_leg, "EN_ROUTE_PICKUP")

    def test_delivered_after_start_allowed_and_retry_safe(self):
        job = _job("goods_transport_truck", leg="UNLOADING", status="in_progress")
        resp = self._post(job, "DELIVERED")
        self.assertEqual(resp.status_code, 200)
        self.assertTrue(resp.data["changed"])
        resp = self._post(job, "DELIVERED")
        self.assertEqual(resp.status_code, 200)
        self.assertFalse(resp.data["changed"])

    def test_backwards_rejected(self):
        job = _job("goods_transport_truck", leg="EN_ROUTE_DROP", status="in_progress")
        resp = self._post(job, "LOADING")
        self.assertEqual(resp.status_code, 400)

    def test_pm_completed_before_start_rejected(self):
        job = _job("packers_movers", leg="UNPACKING", status="arrived")
        resp = self._post(job, "COMPLETED")
        self.assertEqual(resp.status_code, 400)


class ProofSetsDeliveredTests(SimpleTestCase):
    def _submit(self, category):
        emp = SimpleNamespace(id=7)
        job = SimpleNamespace(id=21, pk=21, status="in_progress", service_category=category,
                              assigned_employee=emp)
        user = SimpleNamespace(is_authenticated=True, is_active=True, id=1, pk=1,
                               employee_profile=emp, is_superuser=False, role="technician")
        from django.core.files.uploadedfile import SimpleUploadedFile
        photo = SimpleUploadedFile("a.jpg", b"x", content_type="image/jpeg")
        req = APIRequestFactory().post("/x", {"notes": "done", "after_photo": photo}, format="multipart")
        force_authenticate(req, user=user)
        proof = MagicMock(is_submitted=True)
        set_leg = MagicMock(return_value=(True, ""))
        with patch.object(views.WorkforceJobProofView, "permission_classes", []), \
             patch.object(views.ServiceRequest.objects, "filter", return_value=SimpleNamespace(first=lambda: job)), \
             patch.object(views, "is_admin_role", return_value=False), \
             patch.object(views, "is_employee_authorized_for_job", return_value=True), \
             patch.object(views, "_validate_photo_upload", return_value=None), \
             patch.object(views.PostServiceProof.objects, "get_or_create", return_value=(proof, True)), \
             patch.object(views, "apply_transition"), \
             patch.object(views.JobPayment.objects, "filter", return_value=SimpleNamespace(first=lambda: None)), \
             patch("workforce_api.services.logistics_checkpoints.checkpoint_state", return_value=_ALL_VERIFIED), \
             patch("workforce_api.services.logistics_events.set_logistics_leg", set_leg):
            resp = views.WorkforceJobProofView.as_view()(req, pk=21)
        return resp, set_leg

    def test_logistics_proof_sets_delivered(self):
        resp, set_leg = self._submit("goods_transport_truck")
        self.assertEqual(resp.status_code, 200, getattr(resp, "data", None))
        set_leg.assert_called_once()
        self.assertEqual(set_leg.call_args[0][1], "DELIVERED")

    def test_non_logistics_proof_leaves_leg(self):
        resp, set_leg = self._submit("ac_repair")
        self.assertEqual(resp.status_code, 200, getattr(resp, "data", None))
        set_leg.assert_not_called()


class DispatchReasonClarityTests(SimpleTestCase):
    def test_missing_job_location_overrides_generic_reason(self):
        code, msg = ad.refine_unassigned_reason(
            "NO_ELIGIBLE_NEARBY", "No technician ... within 50 km.", {"JOB_LOCATION_MISSING": 1})
        self.assertEqual(code, "JOB_LOCATION_MISSING")
        self.assertIn("coordinates", msg)

    def test_breakdown_appended_and_code_kept(self):
        code, msg = ad.refine_unassigned_reason(
            "NO_ELIGIBLE_NEARBY", "No technician.",
            {"INELIGIBLE_G3": 3, "GPS_STALE": 1, "RADIUS_EXCEEDED": 2})
        self.assertEqual(code, "NO_ELIGIBLE_NEARBY")
        self.assertIn("documents/vehicle not compatible: 3", msg)
        self.assertIn("radius exceeded: 2", msg)
        self.assertIn("gps stale: 1", msg)
        self.assertLess(msg.index("vehicle"), msg.index("radius"))

    def test_empty_tally_unchanged(self):
        self.assertEqual(ad.refine_unassigned_reason("X", "m", {}), ("X", "m"))

    def test_get_eligible_candidates_tallies_missing_job_location(self):
        tally = {}
        job = SimpleNamespace(id=3, latitude=None, longitude=None)
        self.assertEqual(ad.get_eligible_candidates(job, rejection_tally=tally), [])
        self.assertEqual(tally, {"JOB_LOCATION_MISSING": 1})
