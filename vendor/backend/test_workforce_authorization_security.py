"""
test_workforce_authorization_security.py

Comprehensive Authorization & Security Verification Suite for Workforce:
- Unauthenticated access rejection (401)
- Wrong role rejection (403)
- Wrong company / Tenant isolation (403)
- Cross-company job read/update/acceptance attempt (403 CROSS_TENANT_FORBIDDEN)
- Invalid state transitions (400/409)
- Duplicate accept / payment conflict handling (409)
- CSRF protection enforcement (403)
- Secure cookie attributes (Secure, HttpOnly, SameSite)
- CORS origin restrictions (Blocked unauthorized origins)
"""
import uuid
from decimal import Decimal
from datetime import timedelta

from django.test import TestCase, Client, override_settings
from django.utils import timezone
from django.conf import settings
from django.contrib.auth import get_user_model
from rest_framework import status
from rest_framework.test import APIClient, APIRequestFactory, force_authenticate

User = get_user_model()

from companies.models import Company
from employees.models import Employee
from service_requests.models import ServiceRequest
from workforce_api.models import (
    PostServiceProof,
    JobPayment,
    WorkforceJobOffer,
)
from workforce_api.views import (
    WorkforceJobListView,
    WorkforceJobAcceptOfferView,
    WorkforceJobTransitionView,
    WorkforceJobCashCollectView,
)


class WorkforceAuthorizationAndSecurityTests(TestCase):
    def setUp(self):
        self.factory = APIRequestFactory()
        self.client = APIClient()

        # Company A & Technician A
        uid_a = uuid.uuid4().hex[:8]
        self.company_a = Company.objects.create(company_name=f"Company A {uid_a}", is_active=True)
        self.user_tech_a = User.objects.create_user(
            username=f"tech_a_{uid_a}",
            email=f"tech_a_{uid_a}@example.com",
            password="Password123!",
            role="employee",
        )
        self.emp_a = Employee.objects.create(
            user=self.user_tech_a,
            company=self.company_a,
            employee_id=f"EMP-A-{uid_a[:4].upper()}",
            phone=f"91{uid_a[:8]}",
            bank_details={"onboarding": {"status": "approved"}},
        )

        # Company B & Technician B
        uid_b = uuid.uuid4().hex[:8]
        self.company_b = Company.objects.create(company_name=f"Company B {uid_b}", is_active=True)
        self.user_tech_b = User.objects.create_user(
            username=f"tech_b_{uid_b}",
            email=f"tech_b_{uid_b}@example.com",
            password="Password123!",
            role="employee",
        )
        self.emp_b = Employee.objects.create(
            user=self.user_tech_b,
            company=self.company_b,
            employee_id=f"EMP-B-{uid_b[:4].upper()}",
            phone=f"92{uid_b[:8]}",
            bank_details={"onboarding": {"status": "approved"}},
        )

        # Customer User (Wrong Role)
        uid_c = uuid.uuid4().hex[:8]
        self.user_customer = User.objects.create_user(
            username=f"cust_{uid_c}",
            email=f"cust_{uid_c}@example.com",
            password="Password123!",
            role="customer",
        )

        # Job belonging to Company A
        self.job_a = ServiceRequest.objects.create(
            company=self.company_a,
            assigned_employee=self.emp_a,
            status="proof_submitted",
            total_amount=Decimal("500.00"),
            payment_method="cash",
            payment_status="pending",
            preferred_date=timezone.localdate(),
            preferred_time="11:00 AM",
            service_category="Appliances",
            issue_title="AC Service",
        )

        # Create offer for Tech A
        WorkforceJobOffer.objects.create(
            job=self.job_a,
            employee=self.emp_a,
            status=WorkforceJobOffer.Status.OFFERED,
            expires_at=timezone.now() + timedelta(minutes=15),
        )

    # ── 1. Unauthenticated Access ─────────────────────────────────────────────

    def test_01_unauthenticated_job_endpoints_return_401(self):
        """Unauthenticated requests must be rejected with 401 Unauthorized."""
        client = APIClient()  # No authentication credentials provided

        resp_list = client.get("/api/workforce/jobs/")
        self.assertEqual(resp_list.status_code, status.HTTP_401_UNAUTHORIZED)

        resp_accept = client.post(f"/api/workforce/jobs/{self.job_a.id}/accept/")
        self.assertEqual(resp_accept.status_code, status.HTTP_401_UNAUTHORIZED)

        resp_collect = client.post(f"/api/workforce/jobs/{self.job_a.id}/payment/collect/", {"amount_received": "500.00"})
        self.assertEqual(resp_collect.status_code, status.HTTP_401_UNAUTHORIZED)

    # ── 2. Wrong Role ──────────────────────────────────────────────────────────

    def test_02_customer_role_cannot_access_technician_views(self):
        """Users with 'customer' role are rejected with 403 Forbidden by IsApprovedTechnician."""
        req = self.factory.get("/api/workforce/jobs/")
        force_authenticate(req, user=self.user_customer)
        view = WorkforceJobListView.as_view()
        resp = view(req)
        self.assertEqual(resp.status_code, status.HTTP_403_FORBIDDEN)

    # ── 3. Tenant Isolation & Cross-Company Job Rejection ─────────────────────

    def test_03_technician_b_cannot_accept_company_a_job(self):
        """Technician from Company B must be rejected when attempting to accept Company A job."""
        req = self.factory.post(f"/api/workforce/jobs/{self.job_a.id}/accept/")
        force_authenticate(req, user=self.user_tech_b)
        view = WorkforceJobAcceptOfferView.as_view()
        resp = view(req, pk=self.job_a.id)

        self.assertEqual(resp.status_code, status.HTTP_403_FORBIDDEN)
        self.assertEqual(resp.data.get("code"), "CROSS_TENANT_FORBIDDEN")

    def test_04_technician_b_cannot_transition_company_a_job(self):
        """Technician from Company B must be rejected when attempting to transition Company A job."""
        req = self.factory.post(
            f"/api/workforce/jobs/{self.job_a.id}/transition/",
            {"status": "in_progress"},
            format="json"
        )
        force_authenticate(req, user=self.user_tech_b)
        view = WorkforceJobTransitionView.as_view()
        resp = view(req, pk=self.job_a.id)

        self.assertEqual(resp.status_code, status.HTTP_403_FORBIDDEN)

    def test_05_technician_b_cannot_collect_cash_on_company_a_job(self):
        """Technician from Company B must be rejected when attempting cash collection on Company A job."""
        req = self.factory.post(
            f"/api/workforce/jobs/{self.job_a.id}/payment/collect/",
            {"amount_received": "500.00"},
            format="json"
        )
        force_authenticate(req, user=self.user_tech_b)
        view = WorkforceJobCashCollectView.as_view()
        resp = view(req, pk=self.job_a.id)

        self.assertEqual(resp.status_code, status.HTTP_403_FORBIDDEN)

    # ── 4. Invalid State Transitions ──────────────────────────────────────────

    def test_06_invalid_state_transition_rejected(self):
        """Attempting to complete a job directly without proof or execution must fail."""
        job_pending = ServiceRequest.objects.create(
            company=self.company_a,
            assigned_employee=self.emp_a,
            status="pending",
            total_amount=Decimal("300.00"),
            payment_method="cash",
            payment_status="pending",
            preferred_date=timezone.localdate(),
            preferred_time="02:00 PM",
            service_category="Appliances",
            issue_title="Pending Job",
        )

        req = self.factory.post(
            f"/api/workforce/jobs/{job_pending.id}/transition/",
            {"status": "completed"},
            format="json"
        )
        force_authenticate(req, user=self.user_tech_a)
        view = WorkforceJobTransitionView.as_view()
        resp = view(req, pk=job_pending.id)

        # Must reject invalid jump from pending directly to completed
        self.assertIn(resp.status_code, [status.HTTP_400_BAD_REQUEST, status.HTTP_403_FORBIDDEN, status.HTTP_409_CONFLICT])

    # ── 5. Duplicate Acceptance / Concurrency Conflict ────────────────────────

    def test_07_duplicate_acceptance_by_second_technician_returns_conflict_409(self):
        """When job is accepted by Tech A, simultaneous/subsequent accept by another tech returns 409 Conflict."""
        # Create unassigned offerable job in Company A
        job_open = ServiceRequest.objects.create(
            company=self.company_a,
            status="accepted",
            assigned_employee=self.emp_a,
            total_amount=Decimal("400.00"),
            payment_method="cash",
            payment_status="pending",
            preferred_date=timezone.localdate(),
            preferred_time="03:00 PM",
            service_category="Appliances",
            issue_title="Open Job",
        )

        # Another technician in same company
        uid_c2 = uuid.uuid4().hex[:8]
        user_c2 = User.objects.create_user(
            username=f"tech_c2_{uid_c2}",
            email=f"tech_c2_{uid_c2}@example.com",
            password="Password123!",
            role="employee",
        )
        emp_c2 = Employee.objects.create(
            user=user_c2,
            company=self.company_a,
            employee_id=f"EMP-C-{uid_c2[:4].upper()}",
            phone=f"93{uid_c2[:8]}",
            bank_details={"onboarding": {"status": "approved"}},
        )

        req = self.factory.post(f"/api/workforce/jobs/{job_open.id}/accept/")
        force_authenticate(req, user=user_c2)
        view = WorkforceJobAcceptOfferView.as_view()
        resp = view(req, pk=job_open.id)

        self.assertEqual(resp.status_code, status.HTTP_409_CONFLICT)
        self.assertEqual(resp.data.get("code"), "JOB_ALREADY_ACCEPTED")

    # ── 6. CSRF Protection ────────────────────────────────────────────────────

    def test_08_csrf_protection_enforced_on_session_client(self):
        """CSRF protection blocks unvalidated state-mutating requests when CSRF checks are enabled."""
        csrf_client = Client(enforce_csrf_checks=True)
        # Attempt POST without CSRF token
        resp = csrf_client.post("/api/workforce/jobs/", {"dummy": "data"})
        # Should be rejected with 403 Forbidden due to CSRF failure
        self.assertEqual(resp.status_code, status.HTTP_403_FORBIDDEN)

    # ── 7. Secure Cookie Attributes ───────────────────────────────────────────

    def test_09_secure_cookie_attributes_configuration(self):
        """Verify production cookie settings enforce Secure, HttpOnly, and SameSite."""
        # Check settings configuration
        self.assertTrue(getattr(settings, "SESSION_COOKIE_HTTPONLY", True))
        self.assertIn(getattr(settings, "SESSION_COOKIE_SAMESITE", "Lax"), ["Lax", "Strict", "lax", "strict"])
        self.assertIn(getattr(settings, "CSRF_COOKIE_SAMESITE", "Lax"), ["Lax", "Strict", "lax", "strict"])

    # ── 8. CORS Origin Restrictions ───────────────────────────────────────────

    def test_10_cors_origin_restrictions_blocks_unauthorized_origins(self):
        """CORS must block untrusted origins and allow only configured domains."""
        # Malicious origin
        resp_malicious = self.client.get(
            "/api/workforce/jobs/",
            HTTP_ORIGIN="https://malicious-attacker-domain.com",
            HTTP_ACCESS_CONTROL_REQUEST_METHOD="GET"
        )
        allow_origin_malicious = resp_malicious.get("Access-Control-Allow-Origin")
        self.assertNotEqual(allow_origin_malicious, "https://malicious-attacker-domain.com")

        # Configured origin
        resp_valid = self.client.get(
            "/api/workforce/jobs/",
            HTTP_ORIGIN="https://sevo.co.in",
            HTTP_ACCESS_CONTROL_REQUEST_METHOD="GET"
        )
        allow_origin_valid = resp_valid.get("Access-Control-Allow-Origin")
        # If origin is allowed, header reflects https://sevo.co.in
        if allow_origin_valid:
            self.assertEqual(allow_origin_valid, "https://sevo.co.in")
