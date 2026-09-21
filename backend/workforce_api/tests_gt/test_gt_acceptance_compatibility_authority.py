"""
GT audit Update 18 -- the acceptance compatibility authority.

Decision recorded in the final closure pass: offer acceptance must enforce
the purchased-vehicle requirement, but it must NOT re-run the full ten-gate
dispatch engine. That engine carries unrelated operational gates (cash float
ceiling, workload) which would refuse an offer the platform itself issued --
an earlier attempt to re-run it broke
test_production_blocking_regressions.JobAcceptTenantGuardTests for exactly
that reason.

So the logistics half of Gate 3 was lifted into ONE function,
check_purchased_vehicle_compatibility(), which both callers share:

  * check_candidate_eligibility() calls it as part of the full sweep, and
  * WorkforceJobAcceptOfferView calls it on its own, on every acceptance.

There is no second copy of the rules. These tests assert that -- that the
authority exists, that it is what Gate 3 now uses, that acceptance calls it
unconditionally, and that it decides the cases it is supposed to decide.
"""
import re
from decimal import Decimal
from types import SimpleNamespace
from unittest.mock import patch

from django.test import SimpleTestCase

import workforce_api.services.automatic_dispatch as ad


def _vehicle(vehicle_type, capacity_kg=None, documents_current=True):
    return SimpleNamespace(
        vehicle_type=vehicle_type,
        capacity_kg=capacity_kg,
        is_active=True,
        is_document_current=lambda: documents_current,
    )


def _job(fare_breakdown):
    return SimpleNamespace(fare_breakdown=fare_breakdown)


_EMP = SimpleNamespace(id=1, company_id=None)


def _compat(service_name, vehicles, job=None, emp=_EMP):
    with patch("workforce_api.models.Vehicle.objects.filter", return_value=vehicles):
        return ad.check_purchased_vehicle_compatibility(emp, service_name, job)


class TheAuthorityDecidesCompatibilityTests(SimpleTestCase):
    def test_a_matching_class_is_compatible(self):
        ok, reason = _compat(
            "goods_transport_truck", [_vehicle("truck")], _job({"vehicle_class": "truck"})
        )
        self.assertTrue(ok, reason)
        self.assertEqual(reason, "")

    def test_a_bigger_vehicle_satisfies_a_smaller_purchase(self):
        ok, reason = _compat(
            "goods_transport_truck", [_vehicle("truck")], _job({"vehicle_class": "three_wheeler"})
        )
        self.assertTrue(ok, reason)

    def test_a_smaller_vehicle_never_satisfies_a_bigger_purchase(self):
        ok, reason = _compat(
            "goods_transport_truck",
            [_vehicle("three_wheeler")],
            _job({"vehicle_class": "truck"}),
        )
        self.assertFalse(ok)
        self.assertIn("class-compatible", reason)

    def test_an_unrecognised_purchased_class_fails_closed(self):
        ok, reason = _compat(
            "goods_transport_truck", [_vehicle("truck")], _job({"vehicle_class": "spaceship"})
        )
        self.assertFalse(ok)
        self.assertIn("not recognized", reason)

    def test_insufficient_relocation_payload_is_refused(self):
        ok, reason = _compat(
            "packers_movers",
            [_vehicle("truck", capacity_kg=Decimal("500"))],
            _job({"vehicle": {"payload_kg": "1200"}}),
        )
        self.assertFalse(ok)
        self.assertIn("payload", reason)

    def test_sufficient_relocation_payload_is_accepted(self):
        ok, reason = _compat(
            "packers_movers",
            [_vehicle("truck", capacity_kg=Decimal("1500"))],
            _job({"vehicle": {"payload_kg": "1200"}}),
        )
        self.assertTrue(ok, reason)

    def test_no_active_vehicle_is_refused(self):
        ok, reason = _compat("goods_transport_truck", [], _job({"vehicle_class": "truck"}))
        self.assertFalse(ok)
        self.assertIn("No active vehicle", reason)

    def test_expired_vehicle_documents_are_refused(self):
        ok, reason = _compat(
            "goods_transport_truck",
            [_vehicle("truck", documents_current=False)],
            _job({"vehicle_class": "truck"}),
        )
        self.assertFalse(ok)
        self.assertIn("expired", reason.lower())

    def test_a_booking_with_no_snapshot_falls_back_to_the_coarse_check(self):
        # Legacy bookings predate the snapshot; they must not be stranded.
        ok, reason = _compat("goods_transport_truck", [_vehicle("mini_truck")], job=None)
        self.assertTrue(ok, reason)

    def test_the_coarse_check_still_refuses_an_obviously_wrong_vehicle(self):
        ok, reason = _compat("goods_transport_two_wheeler", [_vehicle("truck")], job=None)
        self.assertFalse(ok)

    def test_non_logistics_categories_short_circuit_without_touching_the_database(self):
        # No Vehicle mock at all: if this reached the ORM it would raise in a
        # SimpleTestCase, which is the point -- acceptance of a plumbing job
        # must not pay for a vehicle query.
        for category in ("plumbing", "hvac", "electrical", "", None):
            ok, reason = ad.check_purchased_vehicle_compatibility(_EMP, category, None)
            self.assertTrue(ok, category)
            self.assertEqual(reason, "")


class ThereIsExactlyOneCopyOfTheRulesTests(SimpleTestCase):
    SOURCE = "workforce_api/services/automatic_dispatch.py"
    VIEWS = "workforce_api/views.py"

    def _source(self, path):
        return open(path, encoding="utf-8", errors="replace").read()

    def test_gate_3_delegates_rather_than_duplicating(self):
        src = self._source(self.SOURCE)
        engine = src.split("def check_candidate_eligibility(", 1)[1]
        self.assertIn("check_purchased_vehicle_compatibility(", engine)
        # The rank tables must be read in exactly one place -- the authority.
        self.assertNotIn("_TIER_VEHICLE_CLASS_RANK.get", engine)
        self.assertNotIn("_EMPLOYEE_VEHICLE_TYPE_RANK.get", engine)

    def test_acceptance_calls_the_same_authority(self):
        src = self._source(self.VIEWS)
        lines = src.splitlines()
        start = next(i for i, l in enumerate(lines) if re.match(r"class WorkforceJobAcceptOfferView\(", l))
        end = next(i for i, l in enumerate(lines) if i > start and re.match(r"class \w+\(", l))
        body = "\n".join(lines[start:end])
        self.assertIn("check_purchased_vehicle_compatibility(", body)
        self.assertIn("INCOMPATIBLE_VEHICLE", body)

    def test_acceptance_checks_compatibility_before_it_assigns(self):
        src = self._source(self.VIEWS)
        lines = src.splitlines()
        start = next(i for i, l in enumerate(lines) if re.match(r"class WorkforceJobAcceptOfferView\(", l))
        end = next(i for i, l in enumerate(lines) if i > start and re.match(r"class \w+\(", l))
        body = "\n".join(lines[start:end])
        self.assertLess(
            body.index("check_purchased_vehicle_compatibility("),
            body.index("job_obj.assigned_employee = emp_obj"),
            "a technician is assigned before compatibility is known",
        )

    def test_acceptance_is_not_conditional_on_a_missing_offer(self):
        src = self._source(self.VIEWS)
        lines = src.splitlines()
        start = next(i for i, l in enumerate(lines) if re.match(r"class WorkforceJobAcceptOfferView\(", l))
        end = next(i for i, l in enumerate(lines) if i > start and re.match(r"class \w+\(", l))
        body = "\n".join(lines[start:end])
        self.assertLess(
            body.index("check_purchased_vehicle_compatibility("),
            body.index("if not offer:"),
            "compatibility is only checked when there is no offer",
        )

    def test_the_full_engine_still_guards_the_unvetted_path(self):
        src = self._source(self.VIEWS)
        lines = src.splitlines()
        start = next(i for i, l in enumerate(lines) if re.match(r"class WorkforceJobAcceptOfferView\(", l))
        end = next(i for i, l in enumerate(lines) if i > start and re.match(r"class \w+\(", l))
        body = "\n".join(lines[start:end])
        after = body.split("if not offer:", 1)[1]
        self.assertIn("check_technician_eligibility(", after)
        self.assertIn("INELIGIBLE_TECHNICIAN", after)


class ReassignmentCannotBypassTheAuthorityTests(SimpleTestCase):
    """
    Reassignment has no assignment path of its own: an expired offer is
    swept by expire_and_reassign_offers(), which re-dispatches through
    dispatch_next_candidate() -- the gated engine -- producing a new offer
    that a technician must then accept. Acceptance is the ONLY place in this
    backend that assigns a technician to a job, and it is compatibility-
    checked above. These assertions pin that shape so a future direct-
    assignment shortcut cannot appear unnoticed.
    """

    SOURCE = "workforce_api/services/automatic_dispatch.py"
    VIEWS = "workforce_api/views.py"

    def test_reassignment_redispatches_through_the_engine(self):
        src = open(self.SOURCE, encoding="utf-8", errors="replace").read()
        body = src.split("def expire_and_reassign_offers(", 1)[1].split("\ndef ", 1)[0]
        self.assertIn("dispatch_next_candidate(", body)
        self.assertNotIn("assigned_employee =", body)

    def test_acceptance_is_the_only_place_a_technician_is_assigned(self):
        src = open(self.VIEWS, encoding="utf-8", errors="replace").read()
        assignments = [
            l.strip()
            for l in src.splitlines()
            if re.search(r"\.assigned_employee\s*=\s*(?!=)(?!None\b)\S", l)
        ]
        self.assertEqual(
            assignments,
            ["job_obj.assigned_employee = emp_obj"],
            f"a new non-acceptance assignment path appeared: {assignments}",
        )
