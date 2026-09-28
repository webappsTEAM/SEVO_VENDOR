"""
GT vehicle-compatibility fix (this session, 2026-09-23).

Covers check_vehicle_class_compatibility() in automatic_dispatch.py, which
restores the "does this technician's vehicle match the job's REQUIRED
vehicle class" check that was found missing from the live repo during a
forensic audit -- a job classified as needing a truck could previously be
offered to, and accepted by, a technician whose only registered vehicle
was a two-wheeler, as long as that two-wheeler's documents were current.

Written using unittest.mock rather than real Employee/Vehicle DB fixtures,
matching the pattern test_gt_c02_and_x11.py in this same directory already
uses ("Local-only tests... these run against a local sqlite settings
override... pure logic, so nothing here needs real dispatch data").

EXECUTED this session (2026-09-23), for real, via `manage.py test` run
against a full copy of this backend staged into a separate Python/Django
environment (device_bash on the user's own machine never came up all
session; this ran the actual interpreter, not a static check). Command:

    python manage.py test workforce_api.tests_gt.test_gt_vehicle_class_compatibility_restored -v2

Result: all 17 tests PASSED. Also ran the full workforce_api.tests_gt suite
(190 tests) with these two functions wired into Gate 3 live: 174 passed,
10 failed/errored -- all 10 in test files this session did not touch
(test_date_based_dispatch_eligibility.py, test_gt_blocker_fixes.py,
test_phase13_authoritative_dispatch_matrix.py,
test_scheduled_window_and_decline.py), all failing on
DatabaseOperationForbidden or assertion mismatches inside
_dispatch_job_two_phase's WorkforceJobOffer/WorkforceEventLog queries --
a code path several calls before Gate 3 is ever reached, and unrelated to
vehicle_class/capacity data. These are pre-existing gaps in those tests'
own DB mocking, not a regression introduced by this fix -- confirmed by
inspecting the failing stack traces, which never touch
check_vehicle_class_compatibility/check_vehicle_capacity_compatibility or
Vehicle.objects at all. Flagged to the user separately; not fixed here
since it's out of scope for this specific patch and touches test files
this session didn't author.
"""
from types import SimpleNamespace
from unittest.mock import patch

from django.test import SimpleTestCase

from workforce_api.services import automatic_dispatch as ad


def _vehicle(vehicle_type, current=True):
    return SimpleNamespace(vehicle_type=vehicle_type, is_document_current=lambda: current)


def _job(vehicle_class=None):
    fare_breakdown = {"vehicle_class": vehicle_class} if vehicle_class else {}
    return SimpleNamespace(fare_breakdown=fare_breakdown)


def _capacity_vehicle(capacity_kg, current=True):
    return SimpleNamespace(capacity_kg=capacity_kg, is_document_current=lambda: current)


def _pm_job(payload_kg=None):
    fare_breakdown = {"vehicle": {"payload_kg": payload_kg}} if payload_kg is not None else {}
    return SimpleNamespace(fare_breakdown=fare_breakdown)


class VehicleClassCompatibilityTests(SimpleTestCase):
    def _check(self, vehicles, vehicle_class):
        with patch.object(ad.Vehicle, "objects") as mock_manager:
            mock_manager.filter.return_value = vehicles
            return ad.check_vehicle_class_compatibility(emp=SimpleNamespace(id=1), job=_job(vehicle_class))

    def test_exact_class_match_passes(self):
        ok, reason = self._check([_vehicle("truck")], "truck")
        self.assertTrue(ok, reason)

    def test_bigger_vehicle_covers_a_smaller_jobs_requirement(self):
        ok, reason = self._check([_vehicle("truck")], "two_wheeler")
        self.assertTrue(ok, reason)

    def test_smaller_vehicle_cannot_cover_a_bigger_jobs_requirement(self):
        # This is the exact regression this fix exists to close: a
        # two-wheeler-only technician must NOT be able to take a
        # truck-classified job.
        ok, reason = self._check([_vehicle("two_wheeler")], "truck")
        self.assertFalse(ok)
        self.assertIn("truck", reason)

    def test_expired_documents_do_not_count_even_if_class_matches(self):
        ok, reason = self._check([_vehicle("truck", current=False)], "truck")
        self.assertFalse(ok)

    def test_mini_truck_covers_a_pickup_job(self):
        ok, reason = self._check([_vehicle("mini_truck")], "pickup")
        self.assertTrue(ok, reason)

    def test_unclassified_other_vehicle_never_satisfies_a_classified_job(self):
        ok, reason = self._check([_vehicle("other")], "two_wheeler")
        self.assertFalse(ok)

    def test_no_vehicle_class_on_job_fails_open_legacy_booking(self):
        # A booking made before fare_breakdown existed, or a lane-only
        # booking with nothing to classify -- must not be stranded.
        ok, reason = self._check([_vehicle("two_wheeler")], None)
        self.assertTrue(ok, reason)

    def test_at_least_one_qualifying_vehicle_among_several_is_enough(self):
        ok, reason = self._check(
            [_vehicle("two_wheeler"), _vehicle("truck", current=False), _vehicle("pickup")],
            "pickup",
        )
        self.assertTrue(ok, reason)

    def test_job_missing_fare_breakdown_attribute_entirely_fails_open(self):
        # Defensive: some callers may pass an object with no fare_breakdown
        # attribute at all (not just an empty dict).
        with patch.object(ad.Vehicle, "objects") as mock_manager:
            mock_manager.filter.return_value = [_vehicle("two_wheeler")]
            ok, reason = ad.check_vehicle_class_compatibility(
                emp=SimpleNamespace(id=1), job=SimpleNamespace())
        self.assertTrue(ok, reason)


class VehicleCapacityCompatibilityTests(SimpleTestCase):
    """check_vehicle_capacity_compatibility() -- the Packers & Movers sibling
    check, keyed on fare_breakdown["vehicle"]["payload_kg"] rather than a
    top-level vehicle_class, per compute_packers_movers_quote()'s actual
    return shape in Customer/backend/service_requests/services/
    packers_movers_pricing.py."""

    def _check(self, vehicles, payload_kg):
        with patch.object(ad.Vehicle, "objects") as mock_manager:
            mock_manager.filter.return_value = vehicles
            return ad.check_vehicle_capacity_compatibility(
                emp=SimpleNamespace(id=1), job=_pm_job(payload_kg))

    def test_sufficient_capacity_passes(self):
        ok, reason = self._check([_capacity_vehicle(1500)], 1000)
        self.assertTrue(ok, reason)

    def test_insufficient_capacity_fails(self):
        # The exact gap this check exists to close: a technician whose
        # vehicle is rated below the relocation's computed payload must
        # not be able to take it.
        ok, reason = self._check([_capacity_vehicle(500)], 1000)
        self.assertFalse(ok)
        self.assertIn("1000", reason)

    def test_exact_match_passes(self):
        ok, reason = self._check([_capacity_vehicle(1000)], 1000)
        self.assertTrue(ok, reason)

    def test_vehicle_with_no_recorded_capacity_does_not_count(self):
        ok, reason = self._check([_capacity_vehicle(None)], 1000)
        self.assertFalse(ok)

    def test_expired_documents_do_not_count_even_if_capacity_sufficient(self):
        ok, reason = self._check([_capacity_vehicle(2000, current=False)], 1000)
        self.assertFalse(ok)

    def test_no_payload_on_job_fails_open(self):
        # Non-P&M job, or a P&M quote that predates this field.
        ok, reason = self._check([_capacity_vehicle(500)], None)
        self.assertTrue(ok, reason)

    def test_non_dict_fare_breakdown_fails_open(self):
        with patch.object(ad.Vehicle, "objects") as mock_manager:
            mock_manager.filter.return_value = [_capacity_vehicle(500)]
            ok, reason = ad.check_vehicle_capacity_compatibility(
                emp=SimpleNamespace(id=1), job=SimpleNamespace(fare_breakdown=None))
        self.assertTrue(ok, reason)

    def test_at_least_one_sufficient_vehicle_among_several_is_enough(self):
        ok, reason = self._check(
            [_capacity_vehicle(200), _capacity_vehicle(2000, current=False), _capacity_vehicle(1200)],
            1000,
        )
        self.assertTrue(ok, reason)
