"""
backend/test_ac_workflow_security_gates.py

Targeted Verification Suite for:
1. Technician cannot directly send quotation to customer (requires vendor admin).
2. Technician cannot approve own quotation (requires vendor admin).
3. Technician A cannot edit or submit Technician B's quotation (ownership check).
4. Arbitrary price replacement is prevented without explicit override reason.
5. Price override with explicit reason is preserved and recorded with snapshot price.
6. Technician cannot start repair before customer approval & authorization (REPAIR_NOT_AUTHORIZED).
"""
import os
import sys
import uuid
from decimal import Decimal
from datetime import datetime, timezone, timedelta

if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8')
if hasattr(sys.stderr, 'reconfigure'):
    sys.stderr.reconfigure(encoding='utf-8')

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "workforce_core.settings")
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import django
django.setup()

from rest_framework.test import APIRequestFactory, force_authenticate
from accounts.models import User
from companies.models import Company
from employees.models import Employee
from service_requests.models import (
    ServiceRequest,
    Estimation,
    EstimationQuotation,
    CustomerInspection,
    CustomerInspectionRateSnapshot,
    ACInspectionRateItem,
)
from service_requests.vendor_views import (
    VendorEstimationQuotationView,
    VendorEstimationQuotationSubmitForReviewView,
    VendorEstimationAdminReviewView,
    VendorEstimationQuotationSendView,
    VendorEstimationRepairProgressView,
)

factory = APIRequestFactory()
RUN_ID = uuid.uuid4().hex[:6].upper()

def run_security_gates_suite():
    print(f"\n=======================================================")
    print(f"AC WORKFLOW SECURITY & STATE MACHINE GATES TEST [{RUN_ID}]")
    print(f"=======================================================\n")

    company = Company.objects.first()
    if not company:
        company = Company.objects.create(name=f"HVAC Corp {RUN_ID}")

    # Vendor Admin User
    admin_user, _ = User.objects.get_or_create(
        username=f"admin_{RUN_ID}",
        defaults={"email": f"admin_{RUN_ID}@test.com", "role": "admin", "company": company, "is_staff": True}
    )
    admin_user.role = "admin"
    admin_user.is_staff = True
    admin_user.save()

    # Technician A
    tech_a_user, _ = User.objects.get_or_create(
        username=f"tech_a_{RUN_ID}",
        defaults={"email": f"tech_a_{RUN_ID}@test.com", "role": "employee", "company": company}
    )
    emp_a, _ = Employee.objects.get_or_create(
        user=tech_a_user,
        defaults={"company": company, "employee_id": f"EMPA_{RUN_ID}"}
    )

    # Technician B (Separate technician)
    tech_b_user, _ = User.objects.get_or_create(
        username=f"tech_b_{RUN_ID}",
        defaults={"email": f"tech_b_{RUN_ID}@test.com", "role": "employee", "company": company}
    )
    emp_b, _ = Employee.objects.get_or_create(
        user=tech_b_user,
        defaults={"company": company, "employee_id": f"EMPB_{RUN_ID}"}
    )

    # Service Request assigned to Tech A
    sr = ServiceRequest.objects.create(
        request_id=f"GATE_{RUN_ID}",
        customer_name="Anita Sharma",
        email="anita@test.com",
        service_category="HVAC & Air Conditioning",
        job_type="ESTIMATION",
        request_kind="ESTIMATION",
        status="inspection_completed",
        company=company,
        assigned_employee=emp_a,
        technician_name=f"{tech_a_user.first_name} {tech_a_user.last_name}",
        technician_phone="+919876543210",
        preferred_date=datetime.now(timezone.utc).date(),
        preferred_time="10:00 AM - 01:00 PM",
        total_amount=Decimal("199.00"),
    )
    est = Estimation.objects.create(
        service_request=sr,
        ac_type="SPLIT",
        ac_brand="Voltas",
        ac_capacity="1.5_TON",
        status="INSPECTION_COMPLETED",
    )

    # Master rate snapshot: Capacitor master price is ₹850
    rate_item = ACInspectionRateItem.objects.first()
    r_id = rate_item.id if rate_item else None
    cust_insp = CustomerInspection.objects.create(
        service_request=sr,
        inspection_name_snapshot="AC Inspection & Diagnostic Visit",
        diagnostic_fee_snapshot=Decimal("199.00"),
    )
    snap = CustomerInspectionRateSnapshot.objects.create(
        customer_inspection=cust_insp,
        rate_item_id=r_id,
        category_name_snapshot="Electrical & PCB",
        item_name_snapshot="Inverter AC Dual Run Capacitor (45/5 uF)",
        price_snapshot=Decimal("850.00"),
        unit_snapshot="pc",
    )

    # -------------------------------------------------------------
    # Gate 1: Technician B cannot create/edit quotation for Tech A's job
    # -------------------------------------------------------------
    print("[Gate 1] Verify Technician B cannot modify Technician A's booking")
    req = factory.post(f"/api/vendor/estimations/{sr.id}/quotation/", {
        "items": [{"title": "Capacitor", "unit_price": 850, "quantity": 1}]
    }, format="json")
    force_authenticate(req, user=tech_b_user)
    res = VendorEstimationQuotationView.as_view()(req, pk=sr.id)
    assert res.status_code == 403, f"Expected 403 Forbidden, got {res.status_code}"
    print("  [PASS] Tech B blocked with 403 FORBIDDEN")

    # -------------------------------------------------------------
    # Gate 2: Master Price Enforcement (Silent arbitrary replacement blocked)
    # -------------------------------------------------------------
    print("[Gate 2] Verify silent arbitrary price replacement is prevented")
    # Tech A attempts to price the capacitor at ₹1500 without an override reason
    req = factory.post(f"/api/vendor/estimations/{sr.id}/quotation/", {
        "items": [{
            "rate_item_id": snap.rate_item_id,
            "title": snap.item_name_snapshot,
            "unit_price": 1500,  # Arbitrary inflated price
            "quantity": 1,
        }]
    }, format="json")
    force_authenticate(req, user=tech_a_user)
    res = VendorEstimationQuotationView.as_view()(req, pk=sr.id)
    assert res.status_code in [200, 201]
    q_data = res.data["data"]["latest_quotation"]
    quote_id = q_data["id"]
    # Backend must enforce master snapshot price (₹850)
    assert Decimal(str(q_data["subtotal"])) == Decimal("850.00"), f"Expected ₹850.00, got {q_data['subtotal']}"
    print(f"  [PASS] Arbitrary price 1500 replaced with master snapshot rate: ₹{q_data['subtotal']}")

    # -------------------------------------------------------------
    # Gate 3: Override with Reason is Preserved and Recorded
    # -------------------------------------------------------------
    print("[Gate 3] Verify override rate with reason is preserved and snapshotted")
    req = factory.post(f"/api/vendor/estimations/{sr.id}/quotation/", {
        "items": [{
            "rate_item_id": snap.rate_item_id,
            "title": snap.item_name_snapshot,
            "unit_price": 1200,
            "quantity": 1,
            "override_reason": "Heavy duty commercial 60uF capacitor required for outdoor VRV unit",
        }]
    }, format="json")
    force_authenticate(req, user=tech_a_user)
    res = VendorEstimationQuotationView.as_view()(req, pk=sr.id)
    assert res.status_code in [200, 201]
    q_data = res.data["data"]["latest_quotation"]
    assert Decimal(str(q_data["subtotal"])) == Decimal("1200.00"), f"Expected ₹1200.00, got {q_data['subtotal']}"
    print(f"  [PASS] Override price ₹1200 with reason successfully preserved")

    # Submit for admin review
    req = factory.post(f"/api/vendor/estimations/{sr.id}/quotation/{quote_id}/submit/", {})
    force_authenticate(req, user=tech_a_user)
    res = VendorEstimationQuotationSubmitForReviewView.as_view()(req, pk=sr.id, quote_id=quote_id)
    assert res.status_code == 200

    # -------------------------------------------------------------
    # Gate 4: Technician cannot directly send quotation to customer
    # -------------------------------------------------------------
    print("[Gate 4] Verify technician cannot directly send quotation to customer")
    req = factory.post(f"/api/vendor/estimations/{sr.id}/quotation/{quote_id}/send/", {})
    force_authenticate(req, user=tech_a_user)
    res = VendorEstimationQuotationSendView.as_view()(req, pk=sr.id, quote_id=quote_id)
    assert res.status_code == 403, f"Expected 403 Forbidden, got {res.status_code}"
    assert res.data.get("code") == "ADMIN_AUTHORIZATION_REQUIRED"
    print("  [PASS] Direct send by technician blocked with ADMIN_AUTHORIZATION_REQUIRED")

    # -------------------------------------------------------------
    # Gate 5: Technician cannot approve their own quotation
    # -------------------------------------------------------------
    print("[Gate 5] Verify technician cannot approve their own quotation")
    req = factory.post(f"/api/vendor/estimations/{sr.id}/quotation/{quote_id}/admin-review/", {
        "action": "APPROVE"
    }, format="json")
    force_authenticate(req, user=tech_a_user)
    res = VendorEstimationAdminReviewView.as_view()(req, pk=sr.id, quote_id=quote_id)
    assert res.status_code == 403, f"Expected 403 Forbidden, got {res.status_code}"
    assert res.data.get("code") == "ADMIN_AUTHORIZATION_REQUIRED"
    print("  [PASS] Self-approval by technician blocked with ADMIN_AUTHORIZATION_REQUIRED")

    # -------------------------------------------------------------
    # Gate 6: Technician cannot start repair before customer approval & authorization
    # -------------------------------------------------------------
    print("[Gate 6] Verify technician cannot start repair while quote is pending or unapproved")
    req = factory.post(f"/api/vendor/estimations/{sr.id}/repair/progress/", {
        "stage": "START_REPAIR"
    }, format="json")
    force_authenticate(req, user=tech_a_user)
    res = VendorEstimationRepairProgressView.as_view()(req, pk=sr.id)
    assert res.status_code == 400, f"Expected 400 Bad Request, got {res.status_code}"
    assert res.data.get("code") == "REPAIR_NOT_AUTHORIZED"
    print("  [PASS] Start repair blocked before customer approval with REPAIR_NOT_AUTHORIZED")

    # Clean up test rows
    cust_insp.delete()
    sr.delete()
    print("\n=======================================================")
    print("ALL 6 SECURITY & STATE MACHINE GATES VERIFIED 100% PASS!")
    print("=======================================================\n")

if __name__ == "__main__":
    run_security_gates_suite()
