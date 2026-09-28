"""
test_surgical_admin_corrections.py

Targeted verification tests for CalTrack Admin Surgical Correction Pass.
Covers:
1. Admin Cancellation (Cross-tenant rejection, state machine enforcement, event logging).
2. Dispatch Security & Engine Convergence.
3. Skills Tenant Isolation (cross-tenant rejected, global allowed).
4. Leave ID Concurrency & Non-collision.
5. Platform Admin Authorization Consistency.
"""

import os
import sys
import django

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "workforce_core.settings")
django.setup()

from rest_framework.test import APIRequestFactory, force_authenticate
from django.contrib.auth import get_user_model
from django.utils import timezone
from rest_framework import status

from companies.models import Company
from employees.models import Employee
from service_requests.models import ServiceRequest
from workforce_api.models import WorkforceSkill, WorkforceEmployeeSkill, WorkforceJobLifecycleEvent
from workforce_api.views import (
    WorkforceJobAdminCancelView,
    WorkforceAutoDispatchTriggerView,
    WorkforceSkillManageView,
    WorkforceEmployeeSkillAssignView,
    WorkforceLeaveListView,
    PlatformVendorsListView,
    PlatformWorkforceListView,
)
from accounts.platform import is_platform_company, PLATFORM_COMPANY_ID, is_platform_admin_user

User = get_user_model()
factory = APIRequestFactory()


def run_tests():
    print("=" * 70)
    print("RUNNING TARGETED TESTS: CALTRACK ADMIN SURGICAL CORRECTIONS")
    print("=" * 70)

    passed = 0
    failed = 0

    def assert_true(cond, msg):
        nonlocal passed, failed
        if cond:
            passed += 1
            print(f"  [PASS] {msg}")
        else:
            failed += 1
            print(f"  [FAIL] {msg}")

    # Setup test entities
    platform_company, _ = Company.objects.get_or_create(
        id=PLATFORM_COMPANY_ID,
        defaults={"company_name": "CalServices Platform", "slug": "calservices"}
    )
    tenant_a, _ = Company.objects.get_or_create(
        company_name="Tenant Company Alpha",
        defaults={"slug": "tenant-alpha"}
    )
    tenant_b, _ = Company.objects.get_or_create(
        company_name="Tenant Company Beta",
        defaults={"slug": "tenant-beta"}
    )

    admin_a, _ = User.objects.get_or_create(
        username="admin_tenant_alpha",
        defaults={"email": "admin_a@alpha.test", "role": "admin", "company": tenant_a}
    )
    admin_a.role = "admin"
    admin_a.company = tenant_a
    admin_a.is_superuser = False
    admin_a.save()

    admin_b, _ = User.objects.get_or_create(
        username="admin_tenant_beta",
        defaults={"email": "admin_b@beta.test", "role": "admin", "company": tenant_b}
    )
    admin_b.role = "admin"
    admin_b.company = tenant_b
    admin_b.is_superuser = False
    admin_b.save()

    platform_admin, _ = User.objects.get_or_create(
        username="platform_admin_user",
        defaults={"email": "platform_admin@calservices.test", "role": "admin", "company": platform_company}
    )
    platform_admin.role = "admin"
    platform_admin.company = platform_company
    platform_admin.is_superuser = False
    platform_admin.save()

    emp_user_a, _ = User.objects.get_or_create(
        username="tech_alpha_1",
        defaults={"email": "tech_a1@alpha.test", "role": "employee", "company": tenant_a}
    )
    emp_a, _ = Employee.objects.get_or_create(
        user=emp_user_a,
        defaults={"company": tenant_a, "employee_id": "EMP-ALPHA-01", "is_active": True}
    )

    print("\n--- 1. Testing Admin Job Cancellation ---")
    # Create a job under tenant_a in cancellable state 'draft'
    job_a = ServiceRequest.objects.create(
        company=tenant_a,
        status="draft",
        preferred_date=timezone.now().date(),
        issue_title="AC Inspection",
        service_category="HVAC",
        address="123 Test St",
    )

    # 1.1 Cross-tenant cancellation: Admin B attempts to cancel Job A
    cancel_view = WorkforceJobAdminCancelView.as_view()
    req_cross = factory.post(f"/api/workforce/jobs/{job_a.id}/admin-cancel/", {"reason": "Malicious cross-tenant attempt"}, format="json")
    force_authenticate(req_cross, user=admin_b)
    res_cross = cancel_view(req_cross, pk=job_a.id)
    assert_true(
        res_cross.status_code == status.HTTP_403_FORBIDDEN and res_cross.data.get("code") == "CROSS_TENANT_FORBIDDEN",
        f"Cross-tenant cancellation rejected with 403 CROSS_TENANT_FORBIDDEN (got {res_cross.status_code}, data: {res_cross.data})"
    )

    # 1.2 State machine enforcement: Set job to 'completed' and try to cancel
    job_a.status = "completed"
    job_a.save()
    req_invalid_state = factory.post(f"/api/workforce/jobs/{job_a.id}/admin-cancel/", {"reason": "Illegal transition"}, format="json")
    force_authenticate(req_invalid_state, user=admin_a)
    res_invalid_state = cancel_view(req_invalid_state, pk=job_a.id)
    job_a.refresh_from_db()
    assert_true(
        res_invalid_state.status_code == status.HTTP_400_BAD_REQUEST and res_invalid_state.data.get("code") == "INVALID_STATE_TRANSITION",
        f"Invalid transition from 'completed' rejected with 400 INVALID_STATE_TRANSITION (got {res_invalid_state.status_code}, data: {res_invalid_state.data})"
    )
    assert_true(
        job_a.status == "completed",
        f"Job state preserved as 'completed', direct DB mutation fallback removed (status: {job_a.status})"
    )

    # 1.3 Authorized cancellation: Valid cancellable state
    job_a.status = "new_request"
    job_a.save()
    req_valid_cancel = factory.post(f"/api/workforce/jobs/{job_a.id}/admin-cancel/", {"reason": "Customer cancelled via phone"}, format="json")
    force_authenticate(req_valid_cancel, user=admin_a)
    res_valid_cancel = cancel_view(req_valid_cancel, pk=job_a.id)
    job_a.refresh_from_db()
    assert_true(
        res_valid_cancel.status_code == status.HTTP_200_OK and job_a.status == "cancelled",
        f"Authorized cancellation transitioned job to 'cancelled' (status: {job_a.status})"
    )

    # Verify lifecycle event
    lc_ev = WorkforceJobLifecycleEvent.objects.filter(job=job_a, event_type=WorkforceJobLifecycleEvent.EventType.EMPLOYEE_JOB_CANCELLED).first()
    assert_true(
        lc_ev is not None and lc_ev.actor_user == admin_a and lc_ev.reason_text == "Customer cancelled via phone",
        "WorkforceJobLifecycleEvent recorded with correct actor_user and reason_text"
    )

    print("\n--- 2. Testing Dispatch Tenant Security ---")
    job_b = ServiceRequest.objects.create(
        company=tenant_b,
        status="new_request",
        preferred_date=timezone.now().date(),
        issue_title="Plumbing Repair",
        service_category="Plumbing",
        address="456 Test Ave",
    )
    auto_disp_view = WorkforceAutoDispatchTriggerView.as_view()
    req_disp_cross = factory.post(f"/api/workforce/dispatch/auto-dispatch/{job_b.id}/")
    force_authenticate(req_disp_cross, user=admin_a)
    res_disp_cross = auto_disp_view(req_disp_cross, pk=job_b.id)
    assert_true(
        res_disp_cross.status_code == status.HTTP_403_FORBIDDEN and res_disp_cross.data.get("code") == "CROSS_TENANT_FORBIDDEN",
        f"Cross-tenant dispatch trigger rejected with 403 CROSS_TENANT_FORBIDDEN (got {res_disp_cross.status_code}, data: {res_disp_cross.data})"
    )

    print("\n--- 3. Testing Admin Skills Tenant Isolation ---")
    # Skill owned by tenant B
    skill_b, _ = WorkforceSkill.objects.get_or_create(
        company=tenant_b,
        code="SKILL-BETA-EXCLUSIVE",
        defaults={"name": "Beta Exclusive Skill", "category": "General"}
    )
    # Global / platform skill owned by platform_company
    skill_global, _ = WorkforceSkill.objects.get_or_create(
        company=platform_company,
        code="SKILL-GLOBAL-COMMON",
        defaults={"name": "Global Common Skill", "category": "General"}
    )

    skill_assign_view = WorkforceEmployeeSkillAssignView.as_view()

    # 3.1 Tenant A admin attempts to assign Tenant B's private skill to Employee A
    req_assign_cross = factory.post(
        f"/api/workforce/skills/employee/{emp_a.id}/",
        {"skill_id": skill_b.id, "proficiency_level": "intermediate"},
        format="json"
    )
    force_authenticate(req_assign_cross, user=admin_a)
    res_assign_cross = skill_assign_view(req_assign_cross, emp_id=emp_a.id)
    assert_true(
        res_assign_cross.status_code == status.HTTP_403_FORBIDDEN and res_assign_cross.data.get("code") == "CROSS_TENANT_SKILL_FORBIDDEN",
        f"Cross-tenant skill assignment rejected with 403 CROSS_TENANT_SKILL_FORBIDDEN (got {res_assign_cross.status_code}, data: {res_assign_cross.data})"
    )

    # 3.2 Tenant A admin assigns global/platform skill to Employee A
    req_assign_global = factory.post(
        f"/api/workforce/skills/employee/{emp_a.id}/",
        {"skill_id": skill_global.id, "proficiency_level": "expert"},
        format="json"
    )
    force_authenticate(req_assign_global, user=admin_a)
    res_assign_global = skill_assign_view(req_assign_global, emp_id=emp_a.id)
    assert_true(
        res_assign_global.status_code in (status.HTTP_200_OK, status.HTTP_201_CREATED),
        f"Global/platform skill assignment allowed (status: {res_assign_global.status_code})"
    )

    print("\n--- 4. Testing Leave ID Generation Correctness ---")
    leave_list_view = WorkforceLeaveListView.as_view()
    # Reset leave details
    emp_a.bank_details = {"leaves": [{"id": 1, "reason": "Sick"}, {"id": 3, "reason": "Casual"}]}
    emp_a.save()

    req_leave = factory.post(
        "/api/workforce/leaves/",
        {"start_date": "2026-10-01", "end_date": "2026-10-02", "leave_type": "CASUAL", "reason": "Family function"},
        format="json"
    )
    force_authenticate(req_leave, user=emp_user_a)
    res_leave = leave_list_view(req_leave)
    created_id = res_leave.data.get("leave", {}).get("id")
    # With IDs 1 and 3 present, old len(leaves)+1 would be 2+1=3 (COLLISION with id 3!).
    # Correct logic max(existing_ids)+1 gives 4.
    assert_true(
        res_leave.status_code == status.HTTP_201_CREATED and created_id == 4,
        f"Leave ID safely generated as max(existing_ids) + 1 = 4, preventing collision (got ID: {created_id})"
    )

    print("\n--- 5. Testing Platform Admin Consistency ---")
    platform_vendors_view = PlatformVendorsListView.as_view()
    platform_workforce_view = PlatformWorkforceListView.as_view()

    # 5.1 Non-superuser platform admin (role=admin, company=calservices) allowed
    req_plat_v = factory.get("/api/workforce/platform/vendors/")
    force_authenticate(req_plat_v, user=platform_admin)
    res_plat_v = platform_vendors_view(req_plat_v)
    assert_true(
        res_plat_v.status_code == status.HTTP_200_OK,
        f"Platform admin authorized for PlatformVendorsListView (got {res_plat_v.status_code})"
    )

    req_plat_w = factory.get("/api/workforce/platform/workforce/")
    force_authenticate(req_plat_w, user=platform_admin)
    res_plat_w = platform_workforce_view(req_plat_w)
    assert_true(
        res_plat_w.status_code == status.HTTP_200_OK,
        f"Platform admin authorized for PlatformWorkforceListView (got {res_plat_w.status_code})"
    )

    # 5.2 Regular tenant admin rejected
    req_tenant_v = factory.get("/api/workforce/platform/vendors/")
    force_authenticate(req_tenant_v, user=admin_a)
    res_tenant_v = platform_vendors_view(req_tenant_v)
    assert_true(
        res_tenant_v.status_code == status.HTTP_403_FORBIDDEN,
        f"Regular tenant admin rejected from PlatformVendorsListView with 403 (got {res_tenant_v.status_code})"
    )
    # Cleanup test entities
    print("\nCleaning up test entities...")
    job_a.delete()
    job_b.delete()
    WorkforceEmployeeSkill.objects.filter(employee=emp_a).delete()
    skill_b.delete()
    skill_global.delete()
    emp_a.delete()
    emp_user_a.delete()
    admin_a.delete()
    admin_b.delete()
    platform_admin.delete()
    print("Cleanup completed.")

    print("\n" + "=" * 70)
    print(f"TEST RESULTS: {passed} PASSED, {failed} FAILED")
    print("=" * 70)
    return {"passed": passed, "failed": failed}


if __name__ == "__main__":
    results = run_tests()
    if results["failed"] > 0:
        sys.exit(1)
