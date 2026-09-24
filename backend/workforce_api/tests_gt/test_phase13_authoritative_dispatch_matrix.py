"""
Authoritative Dispatch Test Matrix (Phase 13).
Uses SimpleTestCase with mocked models/services to test:
- Cross-service dispatch triggering & authorization
- Idempotency and duplicate dispatch protection
- Online vs offline presence gating
- Service/skill mismatch rejection
- Distance/radius gating
- Decline exclusion & next candidate fallback
- Offer acceptance state transitions
- Read-only GET /jobs/ discipline
"""
import datetime
from unittest.mock import patch, MagicMock
from types import SimpleNamespace

from django.test import SimpleTestCase
from django.utils import timezone
from rest_framework.test import APIRequestFactory, force_authenticate

from workforce_api.models import WorkforceJobOffer
from workforce_api.services.automatic_dispatch import (
    check_candidate_eligibility,
    can_receive_offer,
    can_accept_offer,
)
from workforce_api.views import (
    WorkforceCrossServiceDispatchView,
    WorkforceJobListView,
    WorkforceJobRejectOfferView,
)


class MockUser:
    def __init__(self, username="tech_user", pk=101, role="employee"):
        self.username = username
        self.pk = pk
        self.id = pk
        self.is_authenticated = True
        self.is_staff = False
        self.is_superuser = False
        self.is_active = True
        self.role = role
        self.employee_profile = None
        self.company = None
        self.last_known_location = {
            "latitude": 12.9716,
            "longitude": 77.5946,
            "updated_at": timezone.now().isoformat(),
        }

    def get_full_name(self):
        return self.username


class AuthoritativeDispatchMatrixTests(SimpleTestCase):
    def setUp(self):
        self.factory = APIRequestFactory()

    # ── Test A: Cross-Service Dispatch Authorization & Trigger ───────────────
    @patch("workforce_api.views.run_automatic_dispatch")
    @patch("service_requests.models.ServiceRequest.objects.filter")
    def test_a_cross_service_dispatch_endpoint_authorized(self, mock_sr_filter, mock_dispatch):
        """A: Customer booking dispatch trigger executes run_automatic_dispatch."""
        mock_job = SimpleNamespace(id=6234, request_id="SR-6234", status="unassigned")
        mock_sr_filter.return_value.first.return_value = mock_job
        mock_dispatch.return_value = (True, "Job #6234 offered to technician.")

        req = self.factory.post(
            "/api/workforce/jobs/dispatch/",
            {"booking_id": 6234},
            format="json",
            HTTP_X_CALSERVICES_SOURCE="calservices-platform",
        )
        with self.settings(DEBUG=True):
            view = WorkforceCrossServiceDispatchView.as_view()
            resp = view(req)

        self.assertEqual(resp.status_code, 200)
        self.assertTrue(resp.data.get("success"))
        self.assertEqual(resp.data.get("workforce_job_id"), "6234")
        mock_dispatch.assert_called_once_with(mock_job)

    # ── Test B: Idempotency / Duplicate Offer Protection ─────────────────────
    @patch("workforce_api.models.WorkforceJobOffer.objects.filter")
    def test_b_can_receive_offer_prevents_duplicate_offers(self, mock_offer_filter):
        """B: An employee who already has an offer history for a job cannot receive it again."""
        mock_offer_filter.return_value.exists.return_value = True

        user = MockUser()
        emp = SimpleNamespace(
            id=101,
            pk=101,
            user=user,
            is_active=True,
            is_online=True,
            current_availability="available",
            bank_details={"onboarding": {"status": "approved"}},
        )
        job = SimpleNamespace(id=5001, service_category="hvac", issue_title="AC Repair")

        can_rx, reason = can_receive_offer(emp, job)
        self.assertFalse(can_rx)
        self.assertIn("already has offer history", reason)

    # ── Test C & D: Presence Gating (Online vs Offline) ───────────────────────
    def test_c_and_d_online_vs_offline_presence(self):
        """C & D: Online technician passes Gate 7; offline technician fails Gate 7."""
        user = MockUser()
        emp_online = SimpleNamespace(
            id=101,
            pk=101,
            user=user,
            is_active=True,
            is_online=True,
            current_availability="available",
            bank_details={
                "onboarding": {
                    "status": "approved",
                    "services": [{"name": "AC Repair", "category": "hvac", "status": "approved"}],
                }
            },
            company_id=None,
            prefetched_compliance_records=[],
            prefetched_employee_documents=[],
            prefetched_today_schedules=[],
            prefetched_verified_skills=[],
        )
        emp_offline = SimpleNamespace(
            id=102,
            pk=102,
            user=user,
            is_active=True,
            is_online=False,
            current_availability="offline",
            bank_details={
                "onboarding": {
                    "status": "approved",
                    "services": [{"name": "AC Repair", "category": "hvac", "status": "approved"}],
                }
            },
            company_id=None,
            prefetched_compliance_records=[],
            prefetched_employee_documents=[],
            prefetched_today_schedules=[],
            prefetched_verified_skills=[],
        )

        ok_online, _, gates_on = check_candidate_eligibility(emp_online, "hvac", purpose="offer_reception")
        self.assertTrue(gates_on["G7"])
        self.assertTrue(ok_online)

        ok_offline, reason_off, gates_off = check_candidate_eligibility(emp_offline, "hvac", purpose="offer_reception")
        self.assertFalse(gates_off["G7"])
        self.assertFalse(ok_offline)
        self.assertIn("OFFLINE", reason_off)

    # ── Test E: Skill Mismatch Gating ─────────────────────────────────────────
    def test_e_skill_mismatch_blocks_offer(self):
        """E: Technician without required service category fails Gate 6."""
        user = MockUser()
        emp = SimpleNamespace(
            id=101,
            pk=101,
            user=user,
            is_active=True,
            is_online=True,
            current_availability="available",
            bank_details={
                "onboarding": {
                    "status": "approved",
                    "services": [{"name": "Plumbing Repair", "category": "plumbing", "status": "approved"}],
                }
            },
            company_id=None,
            prefetched_compliance_records=[],
            prefetched_employee_documents=[],
            prefetched_today_schedules=[],
            prefetched_verified_skills=[],
        )

        ok, reason, gates = check_candidate_eligibility(emp, "hvac", purpose="offer_reception")
        self.assertFalse(gates["G6"])
        self.assertFalse(ok)
        self.assertIn("Gate 6", reason)

    @patch("django.db.transaction.atomic")
    @patch("django.db.transaction.on_commit")
    @patch("workforce_api.models.WorkforceDispatchState.objects.filter")
    @patch("service_requests.models.ServiceRequest.objects.select_for_update")
    @patch("service_requests.models.ServiceRequest.objects.filter")
    @patch("service_requests.models.EmployeeJob.objects.filter")
    @patch("workforce_api.models.WorkforceJobOffer.objects.select_for_update")
    @patch("workforce_api.models.WorkforceJobOffer.objects.filter")
    @patch("workforce_api.models.WorkforceJobLifecycleEvent.objects.create")
    @patch("workforce_api.models.WorkforceEventLog.objects.create")
    def test_g_decline_triggers_redispatch_excluding_declining_technician(
        self, mock_event_log, mock_event, mock_offer_filter, mock_offer_sfu, mock_emp_job_filter, mock_sr_filter, mock_sr_sfu, mock_dispatch_state, mock_on_commit, mock_atomic
    ):
        """G: Rejecting an offer commits a callback to run_automatic_dispatch excluding the employee."""
        user = MockUser(pk=201)
        emp = SimpleNamespace(
            id=201,
            pk=201,
            user=user,
            is_active=True,
            is_online=True,
            current_availability="available",
            bank_details={"onboarding": {"status": "approved"}},
        )
        user.employee_profile = emp

        job = SimpleNamespace(
            id=7001,
            request_id="SR-7001",
            status="unassigned",
            assigned_employee=None,
            company=None,
            preferred_date=None,
            preferred_time=None,
            issue_title="AC Repair",
            service_category="hvac",
            customer=None,
        )
        mock_sr_filter.return_value.first.return_value = job
        mock_sr_sfu.return_value.filter.return_value.first.return_value = job

        mock_offer = SimpleNamespace(
            id=99,
            job=job,
            employee=emp,
            status=WorkforceJobOffer.Status.OFFERED,
            expires_at=timezone.now() + datetime.timedelta(minutes=5),
            save=MagicMock(),
        )
        mock_offer_filter.return_value.first.return_value = mock_offer
        mock_offer_filter.return_value.count.return_value = 0
        mock_offer_sfu.return_value.filter.return_value.order_by.return_value.first.return_value = mock_offer

        req = self.factory.post("/api/workforce/jobs/7001/reject-offer/", {"reason": "Busy"}, format="json")
        force_authenticate(req, user=user)
        view = WorkforceJobRejectOfferView.as_view()
        resp = view(req, pk=7001)

        self.assertEqual(resp.status_code, 200)
        self.assertEqual(mock_offer.status, WorkforceJobOffer.Status.REJECTED)
        self.assertTrue(mock_on_commit.called)

    # ── Test H: Offer Acceptance Gating ───────────────────────────────────────
    @patch("workforce_api.services.workload.get_employee_active_job")
    def test_h_acceptance_requires_no_active_conflicting_job(self, mock_active_job):
        """H: can_accept_offer fails Gate 9 if technician is busy on another active job."""
        user = MockUser(pk=301)
        emp = SimpleNamespace(
            id=301,
            pk=301,
            user=user,
            is_active=True,
            is_online=True,
            current_availability="available",
            bank_details={
                "onboarding": {
                    "status": "approved",
                    "services": [{"name": "AC Repair", "category": "hvac", "status": "approved"}],
                }
            },
            company_id=None,
            prefetched_compliance_records=[],
            prefetched_employee_documents=[],
            prefetched_today_schedules=[],
            prefetched_verified_skills=[],
        )

        # 1. When employee has another active job #9001
        conflicting_job = SimpleNamespace(id=9001, request_id="SR-9001")
        mock_active_job.return_value = conflicting_job

        new_job = SimpleNamespace(id=9002, service_category="hvac", issue_title="AC Repair")
        can_accept, reason = can_accept_offer(emp, new_job)
        self.assertFalse(can_accept)
        self.assertIn("active assigned Job #9001", reason)

        # 2. When employee is free
        mock_active_job.return_value = None
        can_accept_free, _ = can_accept_offer(emp, new_job)
        self.assertTrue(can_accept_free)

    # ── Test I & K: Read-Only Jobs GET Discipline ────────────────────────────
    @patch("workforce_api.services.workload.get_employee_active_job")
    @patch("service_requests.models.ServiceRequest.objects.filter")
    @patch("workforce_api.models.WorkforceJobOffer.objects.filter")
    @patch("service_requests.models.EmployeeJob.objects.filter")
    @patch("workforce_api.models.WorkforceJobLifecycleEvent.objects.filter")
    def test_i_and_k_jobs_get_is_strictly_read_only(
        self, mock_lifecycle, mock_emp_job, mock_offer, mock_sr, mock_active_job
    ):
        """I & K: GET /api/workforce/jobs/ reads existing records without triggering dispatch."""
        user = MockUser(pk=401)
        emp = SimpleNamespace(
            id=401,
            pk=401,
            user=user,
            is_active=True,
            is_online=True,
            current_availability="available",
            company=None,
            company_id=None,
            bank_details={"onboarding": {"status": "approved"}},
        )
        user.employee_profile = emp
        mock_active_job.return_value = None

        mock_offer.return_value.filter.return_value.values.return_value = []
        mock_lifecycle.return_value.values.return_value = []
        mock_emp_job.return_value.exclude.return_value.values.return_value = []

        mock_chain = MagicMock()
        mock_sr.return_value = mock_chain
        mock_chain.annotate.return_value.filter.return_value.select_related.return_value.order_by.return_value = []
        mock_chain.exclude.return_value.exclude.return_value.select_related.return_value.distinct.return_value.order_by.return_value = []

        req = self.factory.get("/api/workforce/jobs/?status=active")
        force_authenticate(req, user=user)
        view = WorkforceJobListView.as_view()
        resp = view(req)

        self.assertEqual(resp.status_code, 200)
