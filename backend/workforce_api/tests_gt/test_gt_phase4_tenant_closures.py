"""
GT audit Update 17 -- the Phase 4 Vendor tenant-isolation closures.

Four separate holes, all in workforce_api/views.py, all found by sweeping
every GT endpoint rather than by a report:

  1. WorkforceJobLogisticsLegView.get had NO ownership check at all. POST
     on the same endpoint required assignment AND tenancy; the read
     required neither, so any approved technician from any company could
     walk numeric ids and read any trip's current leg and full leg history.

  2. WorkforceJobRejectOfferView required tenancy and nothing else. Every
     platform job (company_id None or 1) passes tenancy for every solo and
     platform technician, so any of them could decline a job they had never
     been offered -- fabricating a REJECTED offer row and re-running
     automatic dispatch on a live booking.

  3. WorkforceJobMessagesView checked assignment but not tenancy, unlike
     the leg and stop endpoints beside it, on a thread carrying
     customer-written content.

  4. WorkforceJobAcceptOfferView ran the eligibility engine (and with it
     the Gate 3 purchased-vehicle-compatibility check) only when there was
     no offer. Vetting at dispatch time does not survive an insurance
     lapse or a vehicle being deactivated before acceptance.

Source-level, for the same reason as the sibling files here: ServiceRequest
is an unmanaged mirror of a table the Customer app owns, so there is no
local schema to build fixtures against, and no test runner has been
reachable in this environment.
"""
import re

from django.test import SimpleTestCase

SOURCE = "workforce_api/views.py"


def _class_body(name):
    src = open(SOURCE, encoding="utf-8", errors="replace").read()
    lines = src.splitlines()
    start = next(i for i, l in enumerate(lines) if re.match(rf"class {name}\(", l))
    end = next(
        (i for i, l in enumerate(lines) if i > start and re.match(r"class \w+\(", l)),
        len(lines),
    )
    return "\n".join(lines[start:end])


def _method_body(class_name, method_name):
    body = _class_body(class_name)
    lines = body.splitlines()
    start = next(i for i, l in enumerate(lines) if re.match(rf"\s+def {method_name}\(", l))
    indent = len(lines[start]) - len(lines[start].lstrip())
    end = next(
        (
            i
            for i, l in enumerate(lines)
            if i > start
            and l.strip()
            and (len(l) - len(l.lstrip())) <= indent
        ),
        len(lines),
    )
    return "\n".join(lines[start:end])


class LogisticsLegReadIsOwnershipCheckedTests(SimpleTestCase):
    def test_get_requires_the_job_to_be_assigned_to_the_caller(self):
        self.assertIn(
            "assigned_employee != emp",
            _method_body("WorkforceJobLogisticsLegView", "get"),
            "the leg READ is open to any approved technician again",
        )

    def test_get_requires_tenancy(self):
        get_body = _method_body("WorkforceJobLogisticsLegView", "get")
        self.assertIn("is_employee_authorized_for_job", get_body)
        self.assertIn("CROSS_TENANT_FORBIDDEN", get_body)

    def test_read_and_write_are_held_to_the_same_standard(self):
        get_body = _method_body("WorkforceJobLogisticsLegView", "get")
        post_body = _method_body("WorkforceJobLogisticsLegView", "post")
        for guard in ("assigned_employee != emp", "is_employee_authorized_for_job"):
            self.assertIn(guard, get_body, f"GET is missing {guard}")
            self.assertIn(guard, post_body, f"POST is missing {guard}")


class RejectOfferRequiresAnActualOfferTests(SimpleTestCase):
    def test_declining_requires_an_offer_or_an_assignment(self):
        body = _class_body("WorkforceJobRejectOfferView")
        self.assertIn("WorkforceJobOffer.objects.filter(job=job, employee=emp).exists()", body)
        self.assertIn("job.assigned_employee != emp", body)

    def test_the_refusal_is_anti_enumerating(self):
        # Must be indistinguishable from "no such job", not a 403 that
        # confirms the job exists.
        body = _class_body("WorkforceJobRejectOfferView")
        guard = body.split("has_offer =", 1)[1].split("reason =", 1)[0]
        self.assertIn("HTTP_404_NOT_FOUND", guard)
        self.assertNotIn("HTTP_403_FORBIDDEN", guard)

    def test_the_guard_runs_before_any_dispatch_side_effect(self):
        body = _class_body("WorkforceJobRejectOfferView")
        self.assertLess(
            body.index("has_offer ="),
            body.index("run_automatic_dispatch"),
            "a caller with no offer can still trigger re-dispatch",
        )

    def test_tenancy_is_still_checked_too(self):
        body = _class_body("WorkforceJobRejectOfferView")
        self.assertIn("is_employee_authorized_for_job", body)


class JobMessagesTenancyTests(SimpleTestCase):
    def test_both_verbs_check_assignment_and_tenancy(self):
        for verb in ("get", "post"):
            body = _method_body("WorkforceJobMessagesView", verb)
            self.assertIn("assigned_employee != emp", body, verb)
            self.assertIn("is_employee_authorized_for_job", body, verb)
            self.assertIn("CROSS_TENANT_FORBIDDEN", body, verb)


class AcceptanceEnforcesCompatibilityTests(SimpleTestCase):
    """
    Acceptance runs the eligibility engine -- and so Gate 3's purchased-
    vehicle-class check -- on the path that has no vetted offer behind it.

    KNOWN RESIDUAL, deliberately left and recorded here rather than
    silently closed: when an offer DOES exist, the engine is not re-run, so
    acceptance stands on the vetting done at dispatch time. Between those
    two moments a vehicle's insurance/permit/PUC can lapse or the only
    class-compatible vehicle can be deactivated.

    Re-running the whole engine at acceptance was tried and reverted: it is
    a TEN-gate engine, so it would also reject acceptances for reasons
    unrelated to vehicle compatibility (an unsettled cash float, say) on
    offers the platform itself issued -- a wider behaviour change than the
    compatibility rule calls for, and it broke
    test_production_blocking_regressions.JobAcceptTenantGuardTests.
    Narrowing it to the compatibility dimension alone would mean a second
    copy of Gate 3, which the audit forbids. Whether that window matters
    enough to widen acceptance is a business decision, not a code one.
    """

    def test_acceptance_forwards_the_job_to_the_gate(self):
        # Without job=, Gate 3's purchased-vehicle-class check is a no-op
        # (see test_gt_vehicle_tier_compatibility.py).
        body = _class_body("WorkforceJobAcceptOfferView")
        self.assertIn("check_technician_eligibility(emp_obj, job_obj.service_category, job=job_obj)", body)
        self.assertIn("INELIGIBLE_TECHNICIAN", body)

    def test_acceptance_still_requires_an_offer_or_assignment(self):
        body = _class_body("WorkforceJobAcceptOfferView")
        self.assertIn("NO_ACTIVE_OFFER", body)

    def test_acceptance_still_checks_tenancy_under_the_row_lock(self):
        body = _class_body("WorkforceJobAcceptOfferView")
        self.assertIn("select_for_update", body)
        self.assertEqual(
            body.count("is_employee_authorized_for_job"),
            2,
            "tenancy must be checked both before and under the lock",
        )


class BareGoodsTransportSlugIsClassCheckedTests(SimpleTestCase):
    """
    Update 16. "goods_transport" is in LOGISTICS_SERVICE_CATEGORIES but has
    no coarse allowed_types branch -- the slug does not say truck or
    two-wheeler, so one cannot be written. That left it with no vehicle-type
    check of any kind. The purchased tier's class is the only authority that
    knows, so the fine-grained check has to cover it.
    """

    def test_the_fine_grained_gate_covers_the_bare_slug(self):
        src = open(
            "workforce_api/services/automatic_dispatch.py", encoding="utf-8", errors="replace"
        ).read()
        gate = src.split("fb = getattr(job,", 1)[1]
        for slug in ("goods_transport_truck", "goods_transport_two_wheeler", "goods_transport"):
            self.assertIn(f'"{slug}"', gate, f"{slug} is not class-checked")

    def test_the_coarse_check_is_still_there(self):
        src = open(
            "workforce_api/services/automatic_dispatch.py", encoding="utf-8", errors="replace"
        ).read()
        self.assertIn("allowed_types", src, "the coarse filter was replaced rather than layered")


class EstimationClaimDerivesOwnershipFromTheActorTests(SimpleTestCase):
    """
    Update 17. VendorEstimationConfirmView took vendor_id from the request
    BODY, so a claimer could attribute a lead to another company, or park it
    under a key nobody holds -- _may_access_estimation compares against the
    actor's own key, so a bogus value locks everyone out of that lead for
    good.
    """

    ESTIMATION_SOURCE = "service_requests/vendor_views.py"

    def _confirm_body(self):
        src = open(self.ESTIMATION_SOURCE, encoding="utf-8", errors="replace").read()
        lines = src.splitlines()
        start = next(
            i for i, l in enumerate(lines)
            if re.match(r"class VendorEstimationConfirmView\(", l)
        )
        end = next(
            (i for i, l in enumerate(lines) if i > start and re.match(r"class \w+\(", l)),
            len(lines),
        )
        return "\n".join(lines[start:end])

    def test_vendor_id_is_derived_from_the_authenticated_actor(self):
        body = self._confirm_body()
        self.assertIn("vendor_id = _actor_vendor_key(request)", body)

    def test_a_body_supplied_vendor_id_is_superuser_only(self):
        body = self._confirm_body()
        self.assertIn("is_platform_admin", body)
        override = body.split("is_platform_admin =", 1)[1].split("else:", 1)[0]
        self.assertIn("is_superuser", override)
        self.assertIn('request.data.get("vendor_id")', override)

    def test_the_claim_key_matches_what_the_ownership_gate_reads_back(self):
        # If these two ever diverge, an actor cannot recognise the lead they
        # themselves just claimed.
        src = open(self.ESTIMATION_SOURCE, encoding="utf-8", errors="replace").read()
        self.assertIn("return sr.vendor_id == _actor_vendor_key(request)", src)
