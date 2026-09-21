"""
GT audit Update 14 / Phase 2 & Phase 3 regression tests: purchased
ServiceTier vehicle-class/capacity compatibility, enforced at the point a
technician is matched to a Goods & Transport or Packers & Movers job.

Background (see automatic_dispatch.py's own comments at the Gate 3 fine-
grained block, and CUS/backend/service_requests/services/logistics_pricing.py
's LogisticsFareBreakdown): the ORIGINAL Gate 3 only checked a coarse
service-category-to-vehicle-type mapping ("some kind of truck for
goods_transport_truck"), which meant a three_wheeler and a heavy_truck were
equally eligible for the same "truck" tier booking regardless of what the
customer actually purchased. This file's fix adds a second, finer check that
reads the ACTUAL purchased requirement from the booking's own quote-time
snapshot (ServiceRequest.fare_breakdown -- a JSON field the Customer app
already populates at quote time and that Vendor's unmanaged ServiceRequest
mirror now also exposes) and fails closed when a candidate's vehicle doesn't
meet it.

Follows this package's own established SimpleTestCase + mocked-queryset +
SimpleNamespace convention (see test_gt_category_and_state_improvements.py)
rather than building real DB fixtures, because check_candidate_eligibility
reads Vehicle/WorkforceRequiredDocument via the ORM but the specific
objects returned are controlled here by mocking .objects.filter directly --
no schema/migration dependency either way.

IMPORTANT, same caveat as every other test file added during this audit:
these were written by reading the exact source of the fixed file and
reasoning through each branch, then verified by direct execution of this
module's own eligibility function against the scenarios below in a plain
Python process (not the Django test runner -- device_bash has been
unavailable for this entire session). Do NOT describe these as "passing"
under Django's test runner until `python manage.py test workforce_api.tests_gt`
has actually been executed.
"""
from decimal import Decimal
from types import SimpleNamespace
from unittest.mock import patch

from django.test import SimpleTestCase

from workforce_api.services import automatic_dispatch as ad


def _vehicle(v_type, capacity_kg=None, is_active=True, doc_current=True):
    return SimpleNamespace(
        vehicle_type=v_type,
        capacity_kg=capacity_kg,
        is_active=is_active,
        is_document_current=lambda: doc_current,
    )


def _employee(emp_id=1, company_id=None, approved_services=None):
    approved_services = approved_services or [
        "goods_transport_two_wheeler",
        "goods_transport_truck",
        "packers_movers",
    ]
    return SimpleNamespace(
        id=emp_id,
        company_id=company_id,
        is_active=True,
        is_online=True,
        current_availability="available",
        user=SimpleNamespace(is_active=True),
        bank_details={"onboarding": {
            "status": "approved",
            "documents": {},
            "services": [{"status": "approved", "name": s, "category": s} for s in approved_services],
        }},
        prefetched_invalid_compliance=[],
        prefetched_today_schedules=[],
        prefetched_verified_skills=[],
    )


class _EmptyQuerySet(list):
    """Gate 4 calls .exists() on its queryset, so a bare [] is not a
    sufficient stand-in."""

    def exists(self):
        return False


_EMPTY_QS = _EmptyQuerySet()


def _job(fare_breakdown):
    """A stub job -- check_candidate_eligibility only ever reads
    `job.fare_breakdown` via getattr(), so a real ServiceRequest instance
    is unnecessary here (and, being an unmanaged mirror model, awkward to
    construct as a DB fixture in this app anyway)."""
    return SimpleNamespace(fare_breakdown=fare_breakdown)


class _BaseGate3Test(SimpleTestCase):
    """Shared scaffolding: mocks out every DB read check_candidate_eligibility
    makes, so only the vehicle-compatibility logic under test executes.

    GT audit Update 17 fix: this previously patched only the workload
    lookup and Vehicle.objects.filter, which is enough ONLY for a
    company_id=None employee that is rejected at Gate 3. Two other reads
    escaped and hit the database, which a SimpleTestCase forbids outright:

      * Gate 3 queries WorkforceRequiredDocument, and Gate 4
        WorkforceComplianceRequirement, for any employee that HAS
        a company_id -- so both CompanyIsolationRemainsIntactTests cases,
        which deliberately use company_id=100, errored rather than
        asserting anything; and
      * Gate 10 (cash float ceiling) is reached by any candidate that
        passes Gate 3, and fails CLOSED when it cannot read -- which is why
        the one test expecting eligibility with job=None reported a cash
        float failure instead of the coarse-check pass it was written for.

    All three failed under the test runner while the underlying
    implementation was correct: a fixture gap, not an implementation bug.
    """

    def _patches(self, vehicles):
        return (
            patch("workforce_api.services.workload.get_employee_active_job", return_value=None),
            patch("workforce_api.models.Vehicle.objects.filter", return_value=vehicles),
            patch("workforce_api.models.WorkforceRequiredDocument.objects.filter", return_value=[]),
            patch(
                    "workforce_api.models.WorkforceComplianceRequirement.objects.filter",
                    return_value=_EMPTY_QS,
                ),
            patch(
                "workforce_api.services.cash_reconciliation.compute_outstanding_cash",
                return_value=(Decimal("0"), None),
            ),
        )

    def _check(self, emp, service_name, vehicles, job=None):
        from contextlib import ExitStack

        with ExitStack() as stack:
            for p in self._patches(vehicles):
                stack.enter_context(p)
            return ad.check_candidate_eligibility(emp, service_name, job=job)


class CompatibleVehicleIsEligibleTests(_BaseGate3Test):
    """Scenario 1: a compatible vehicle for the purchased tier is eligible."""

    def test_truck_tier_purchase_with_matching_truck_vehicle_is_eligible(self):
        emp = _employee(1)
        job = _job({"vehicle_class": "truck"})
        ok, reason, gates = self._check(emp, "goods_transport_truck", [_vehicle("truck")], job=job)
        self.assertTrue(ok, reason)
        self.assertTrue(gates.get("G3"))

    def test_two_wheeler_tier_purchase_with_matching_two_wheeler_vehicle_is_eligible(self):
        emp = _employee(2)
        job = _job({"vehicle_class": "two_wheeler"})
        ok, reason, gates = self._check(emp, "goods_transport_two_wheeler", [_vehicle("two_wheeler")], job=job)
        self.assertTrue(ok, reason)
        self.assertTrue(gates.get("G3"))

    def test_a_bigger_vehicle_than_purchased_is_still_eligible(self):
        # A heavy_truck candidate can still serve a "pickup"-tier booking --
        # the rule is "at least as capable", not "exactly matching".
        emp = _employee(3)
        job = _job({"vehicle_class": "pickup"})
        ok, reason, gates = self._check(emp, "goods_transport_truck", [_vehicle("truck")], job=job)
        self.assertTrue(ok, reason)

    def test_packers_movers_with_sufficient_payload_is_eligible(self):
        emp = _employee(4)
        job = _job({"vehicle": {"payload_kg": 800}})
        ok, reason, gates = self._check(
            emp, "packers_movers", [_vehicle("truck", capacity_kg=1000)], job=job
        )
        self.assertTrue(ok, reason)
        self.assertTrue(gates.get("G3"))


class IncompatibleVehicleClassIsRejectedTests(_BaseGate3Test):
    """Scenario 2: an incompatible/too-small vehicle class is rejected even
    though it passes the old coarse category check."""

    def test_three_wheeler_cannot_serve_a_purchased_heavy_truck_tier(self):
        # Both "three_wheeler" and "heavy_truck" fall under the coarse
        # "goods_transport_truck" allowed_types set (three_wheeler is
        # explicitly listed), which is exactly the gap Update 14 closes.
        emp = _employee(5)
        job = _job({"vehicle_class": "heavy_truck"})
        ok, reason, gates = self._check(emp, "goods_transport_truck", [_vehicle("three_wheeler")], job=job)
        self.assertFalse(ok)
        self.assertFalse(gates.get("G3"))
        self.assertIn("class-compatible", reason)

    def test_pickup_cannot_serve_a_purchased_heavy_truck_tier(self):
        emp = _employee(6)
        job = _job({"vehicle_class": "heavy_truck"})
        ok, reason, gates = self._check(emp, "goods_transport_truck", [_vehicle("pickup")], job=job)
        self.assertFalse(ok)
        self.assertFalse(gates.get("G3"))


class InsufficientCapacityIsRejectedTests(_BaseGate3Test):
    """Scenario 3: Packers & Movers payload_kg requirement enforced."""

    def test_insufficient_payload_capacity_is_rejected(self):
        emp = _employee(7)
        job = _job({"vehicle": {"payload_kg": 1500}})
        ok, reason, gates = self._check(
            emp, "packers_movers", [_vehicle("truck", capacity_kg=1000)], job=job
        )
        self.assertFalse(ok)
        self.assertFalse(gates.get("G3"))
        self.assertIn("payload", reason)

    def test_vehicle_with_no_recorded_capacity_cannot_satisfy_a_stated_requirement(self):
        # capacity_kg=None (never recorded) must not be treated as "unlimited".
        emp = _employee(8)
        job = _job({"vehicle": {"payload_kg": 500}})
        ok, reason, gates = self._check(
            emp, "packers_movers", [_vehicle("truck", capacity_kg=None)], job=job
        )
        self.assertFalse(ok)
        self.assertFalse(gates.get("G3"))


class MissingOrInvalidClassificationIsRejectedTests(_BaseGate3Test):
    """Scenario 4: a present-but-unrecognized snapshot value fails closed
    rather than silently allowing the candidate through."""

    def test_unrecognized_purchased_vehicle_class_string_is_rejected(self):
        emp = _employee(9)
        job = _job({"vehicle_class": "spaceship"})
        ok, reason, gates = self._check(emp, "goods_transport_truck", [_vehicle("truck")], job=job)
        self.assertFalse(ok)
        self.assertFalse(gates.get("G3"))
        self.assertIn("not recognized", reason)

    def test_unrecognized_purchased_payload_value_is_rejected(self):
        emp = _employee(10)
        job = _job({"vehicle": {"payload_kg": "not-a-number"}})
        ok, reason, gates = self._check(
            emp, "packers_movers", [_vehicle("truck", capacity_kg=1000)], job=job
        )
        self.assertFalse(ok)
        self.assertFalse(gates.get("G3"))
        self.assertIn("could not be determined", reason)

    def test_candidate_with_no_classified_vehicle_type_cannot_satisfy_any_requirement(self):
        # An "other"/unclassified vehicle_type has no rank in
        # _EMPLOYEE_VEHICLE_TYPE_RANK -- must fail closed, not be skipped.
        emp = _employee(11)
        job = _job({"vehicle_class": "two_wheeler"})
        ok, reason, gates = self._check(emp, "goods_transport_two_wheeler", [_vehicle("other")], job=job)
        self.assertFalse(ok)
        self.assertFalse(gates.get("G3"))


class ExistingValidGtDispatchStillEligibleTests(_BaseGate3Test):
    """Scenario 5: bookings placed before this fix shipped (no
    fare_breakdown snapshot at all, or job=None from a caller that hasn't
    been updated) must not be retroactively stranded -- the fine-grained
    check is skipped and the pre-existing coarse category check is the
    only one applied, exactly as it behaved before Update 14."""

    def test_no_job_argument_at_all_falls_back_to_coarse_check_only(self):
        emp = _employee(12)
        ok, reason, gates = self._check(emp, "goods_transport_truck", [_vehicle("mini_truck")], job=None)
        self.assertTrue(ok, reason)

    def test_job_with_no_fare_breakdown_snapshot_falls_back_to_coarse_check_only(self):
        emp = _employee(13)
        job = SimpleNamespace()  # no fare_breakdown attribute at all
        ok, reason, gates = self._check(emp, "goods_transport_truck", [_vehicle("truck")], job=job)
        self.assertTrue(ok, reason)

    def test_job_with_empty_fare_breakdown_falls_back_to_coarse_check_only(self):
        emp = _employee(14)
        job = _job({})
        ok, reason, gates = self._check(emp, "goods_transport_two_wheeler", [_vehicle("two_wheeler")], job=job)
        self.assertTrue(ok, reason)


class CompanyIsolationRemainsIntactTests(_BaseGate3Test):
    """Scenario 6: the fine-grained check reads only the candidate's OWN
    vehicles (Vehicle.objects.filter(employee=emp, ...)) -- it must never
    let one company's fleet make another company's candidate eligible."""

    def test_vehicle_lookup_is_scoped_to_the_candidate_employee_only(self):
        emp_a = _employee(15, company_id=100)
        job = _job({"vehicle_class": "truck"})
        from contextlib import ExitStack

        with ExitStack() as stack:
            stack.enter_context(
                patch("workforce_api.services.workload.get_employee_active_job", return_value=None)
            )
            stack.enter_context(
                patch("workforce_api.models.WorkforceRequiredDocument.objects.filter", return_value=[])
            )
            stack.enter_context(
                patch(
                    "workforce_api.models.WorkforceComplianceRequirement.objects.filter",
                    return_value=_EMPTY_QS,
                )
            )
            stack.enter_context(
                patch(
                    "workforce_api.services.cash_reconciliation.compute_outstanding_cash",
                    return_value=(Decimal("0"), None),
                )
            )
            with patch("workforce_api.models.Vehicle.objects.filter", return_value=[_vehicle("truck")]) as mock_filter:
                ad.check_candidate_eligibility(emp_a, "goods_transport_truck", job=job)
                # Every call must filter by this exact employee -- never a
                # bare, unscoped query that could pull another company's
                # vehicles into the eligibility decision.
                for call in mock_filter.call_args_list:
                    _, kwargs = call
                    self.assertEqual(kwargs.get("employee"), emp_a)

    def test_a_companys_own_incompatible_fleet_is_not_rescued_by_another_companys_vehicles(self):
        # Regression guard: even though this test only ever supplies emp_a's
        # own (incompatible) vehicle to the mock, assert explicitly that the
        # rejection reason is the class-compatibility one, not some other
        # gate -- i.e. nothing implicitly widened the candidate pool.
        emp_a = _employee(16, company_id=100)
        job = _job({"vehicle_class": "heavy_truck"})
        ok, reason, gates = self._check(emp_a, "goods_transport_truck", [_vehicle("three_wheeler")], job=job)
        self.assertFalse(ok)
        self.assertIn("class-compatible", reason)


class ManualAcceptanceForwardsJobToTheSameGateTests(SimpleTestCase):
    """GT audit Phase 3 regression: workforce_api/views.py's
    check_technician_eligibility() wrapper -- the function the manual
    offer-acceptance endpoint calls -- used to drop the `job` argument
    entirely, so a manually-accepting technician's vehicle was never
    checked against the purchased tier snapshot even though automatic
    dispatch (which always passed job=job_obj directly to
    check_candidate_eligibility) was already protected. This proves the
    wrapper now forwards `job` through unchanged."""

    def test_wrapper_forwards_job_to_check_candidate_eligibility(self):
        from workforce_api import views

        sentinel_job = _job({"vehicle_class": "truck"})
        with patch("workforce_api.services.automatic_dispatch.check_candidate_eligibility") as mock_check:
            mock_check.return_value = (True, "ok", {})
            views.check_technician_eligibility(SimpleNamespace(), "goods_transport_truck", job=sentinel_job)
            mock_check.assert_called_once_with(
                mock_check.call_args[0][0], "goods_transport_truck", job=sentinel_job
            )

    def test_wrapper_still_works_when_job_is_omitted(self):
        # Backward compatible for the two pre-existing call sites
        # (test_gt_c02_and_x11.py, test_gt_category_and_state_improvements.py)
        # that call this without a job argument at all.
        from workforce_api import views

        with patch("workforce_api.services.automatic_dispatch.check_candidate_eligibility") as mock_check:
            mock_check.return_value = (True, "ok", {})
            views.check_technician_eligibility(SimpleNamespace(), "goods_transport_truck")
            mock_check.assert_called_once_with(
                mock_check.call_args[0][0], "goods_transport_truck", job=None
            )

    def test_a_manually_accepted_incompatible_vehicle_is_rejected_end_to_end(self):
        # Exercises the REAL check_candidate_eligibility (not mocked) through
        # the wrapper, exactly as the manual-acceptance endpoint in views.py
        # now calls it: check_technician_eligibility(emp, category, job=job_obj).
        from workforce_api import views

        emp = _employee(17)
        job = _job({"vehicle_class": "heavy_truck"})
        with patch("workforce_api.services.workload.get_employee_active_job", return_value=None):
            with patch("workforce_api.models.Vehicle.objects.filter", return_value=[_vehicle("three_wheeler")]):
                ok, reason, gates = views.check_technician_eligibility(
                    emp, "goods_transport_truck", job=job
                )
        self.assertFalse(ok)
        self.assertIn("class-compatible", reason)
