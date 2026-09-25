"""
backend/test_technician_ac_inspection_e2e.py

Comprehensive End-to-End Automated Test Suite for Technician-side AC Inspection,
Rate-Card Snapshot Selection, Customer Admin Review Gate, Customer Decision,
and Repair Lifecycle Execution against the shared PostgreSQL database.

Zero mock data. Direct DB persistence verification.
"""
from decimal import Decimal
import os
import sys
import uuid
from datetime import datetime, timezone, timedelta

if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8')
if hasattr(sys.stderr, 'reconfigure'):
    sys.stderr.reconfigure(encoding='utf-8')

# Django setup
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "workforce_core.settings")
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import django
django.setup()

from django.contrib.auth import get_user_model
from django.db import connection, transaction
from rest_framework.test import APIRequestFactory, force_authenticate

from accounts.models import User
from companies.models import Company
from employees.models import Employee
from service_requests.models import (
    ServiceRequest,
    Estimation,
    EstimationFee,
    Inspection,
    InspectionFinding,
    InspectionPhoto,
    EstimationQuotation,
    EstimationQuotationItem,
    CustomerInspection,
    CustomerInspectionRateSnapshot,
)
from service_requests.vendor_views import (
    VendorEstimationListView,
    VendorEstimationDetailView,
    VendorEstimationConfirmView,
    VendorEstimationAssignTechnicianView,
    VendorEstimationStartJourneyView,
    VendorEstimationArrivedView,
    VendorEstimationVerifyOtpView,
    VendorEstimationFindingsView,
    VendorEstimationInspectionCompleteView,
    VendorEstimationInspectionSaveView,
    VendorEstimationQuotationView,
    VendorEstimationQuotationSendView,
    VendorEstimationQuotationReviseView,
    VendorEstimationQuotationSubmitForReviewView,
    VendorEstimationAdminReviewView,
    VendorEstimationRepairProgressView,
    VendorEstimationFeeCollectView,
    VendorEstimationFeeWaiveView,
    VendorEstimationCustomerDecideView,
    VendorEstimationInvoiceView,
)

factory = APIRequestFactory()
TEST_RUN_ID = uuid.uuid4().hex[:6].upper()
PASSED_TESTS = []
FAILED_TESTS = []


def record_pass(name, details=""):
    print(f"  [PASS] {name} {details}")
    PASSED_TESTS.append(name)


def record_fail(name, error):
    import traceback
    print(f"  [FAIL] {name} -> {error}")
    traceback.print_exc()
    FAILED_TESTS.append((name, str(error)))


def run_e2e_suite():
    print(f"\n==========================================================================")
    print(f"TECHNICIAN AC INSPECTION & ESTIMATION WORKFLOW E2E TEST")
    print(f"Test Run ID: {TEST_RUN_ID}")
    print(f"==========================================================================\n")

    # -------------------------------------------------------------------------
    # Setup Tenant, Users, and Shared Data
    # -------------------------------------------------------------------------
    print("--- 1. Setup Company, Vendor, and Technician ---")
    try:
        company = Company.objects.first()
        if not company:
            company = Company.objects.create(name=f"E2E Test HVAC Corp {TEST_RUN_ID}")

        vendor_user, _ = User.objects.get_or_create(
            username=f"vendor_tech_{TEST_RUN_ID}",
            defaults={
                "email": f"vendor_tech_{TEST_RUN_ID}@example.com",
                "first_name": "Vendor",
                "last_name": "Admin",
                "company": company,
                "role": "admin",
                "is_staff": True,
            }
        )
        vendor_user.set_password("TestPass123!")
        vendor_user.company = company
        vendor_user.role = "admin"
        vendor_user.is_staff = True
        vendor_user.save()

        tech_user, _ = User.objects.get_or_create(
            username=f"tech_{TEST_RUN_ID}",
            defaults={
                "email": f"technician_{TEST_RUN_ID}@example.com",
                "first_name": "Ramesh",
                "last_name": "Kumar",
                "company": company,
                "role": "employee",
            }
        )
        tech_user.set_password("TestPass123!")
        tech_user.company = company
        tech_user.role = "employee"
        tech_user.save()

        employee, _ = Employee.objects.get_or_create(
            user=tech_user,
            defaults={"company": company, "phone": "+919876543210", "employee_id": f"EMP_{TEST_RUN_ID}"}
        )

        record_pass("Setup Tenant, Vendor & Technician", f"Vendor: {vendor_user.email}, Tech: {tech_user.email}")
    except Exception as e:
        record_fail("Setup Tenant, Vendor & Technician", e)
        return

    # =========================================================================
    # SCENARIO A: Full Inspection, Rate-Snapshot Selection, Admin Review Gate,
    # Customer Acceptance, and Multi-Stage Repair Execution to Completion
    # =========================================================================
    print("\n--- SCENARIO A: Complete AC Inspection -> Admin Review -> Customer Accept -> Repair Execution ---")

    # Step A1: Simulate Customer Application creating ServiceRequest + CustomerInspection + RateSnapshot in PostgreSQL
    print("\n[A1] Creating CustomerInspection and CustomerInspectionRateSnapshot in Shared DB")
    try:
        sr_a = ServiceRequest.objects.create(
            request_id=f"AC_SR_{TEST_RUN_ID}_A",
            job_type="ESTIMATION",
            request_kind="ESTIMATION",
            customer_name="Arun Sharma",
            phone="+919876543210",
            email="arun@example.com",
            service_category="HVAC & Air Conditioning",
            issue_title="Daikin 1.5 Ton Inverter AC Diagnostic",
            description="AC not cooling properly; outdoor fan vibrating",
            address="402 Palm Grove Apartments, Sector 15, Gurgaon",
            status="requested",
            company=company,
            start_otp="458921",
            total_amount=Decimal("199.00"),
            preferred_date=datetime.now(timezone.utc).date(),
            preferred_time="10:00 AM - 01:00 PM",
        )

        est_a = Estimation.objects.create(
            service_request=sr_a,
            ac_type="SPLIT",
            ac_brand="Daikin",
            ac_capacity="1.5_TON",
            ac_quantity=1,
            customer_symptom="AC not cooling properly; outdoor fan vibrating",
            customer_notes="Advise technician to bring gas charging manifold and capacitor.",
            status="REQUESTED",
        )

        fee_a = EstimationFee.objects.create(
            estimation=est_a,
            amount=Decimal("199.00"),
            currency="INR",
            status="PENDING",
        )

        customer_inspection = CustomerInspection.objects.create(
            service_request=sr_a,
            inspection_name_snapshot="AC Comprehensive Diagnostic & Inspection",
            diagnostic_fee_snapshot=Decimal("199.00"),
            currency="INR",
            quantity=1,
            status="BOOKED",
        )

        # Fetch real rate items from database if available
        from service_requests.models import ACInspectionRateItem
        real_items = list(ACInspectionRateItem.objects.filter(is_active=True)[:4])
        r1_id = real_items[0].id if len(real_items) > 0 else None
        r2_id = real_items[1].id if len(real_items) > 1 else None
        r3_id = real_items[2].id if len(real_items) > 2 else None
        r4_id = real_items[3].id if len(real_items) > 3 else None

        # Create rate card snapshots simulating the authorized rates captured at booking time
        snap1 = CustomerInspectionRateSnapshot.objects.create(
            customer_inspection=customer_inspection,
            rate_item_id=r1_id,
            category_name_snapshot="Gas Charging & Leakage Repair",
            item_name_snapshot="R32 Inverter Gas Top-up & Refill",
            description_snapshot="Up to 1kg R32 refrigerant with vacuuming",
            price_snapshot=Decimal("1850.00"),
            unit_snapshot="kg",
            service_type_snapshot="GAS",
            display_order=1,
        )
        snap2 = CustomerInspectionRateSnapshot.objects.create(
            customer_inspection=customer_inspection,
            rate_item_id=r2_id,
            category_name_snapshot="Electrical & PCB",
            item_name_snapshot="Dual Run Capacitor 45/5 uF Replacement",
            description_snapshot="Heavy-duty 450V AC capacitor",
            price_snapshot=Decimal("850.00"),
            unit_snapshot="piece",
            service_type_snapshot="PART",
            display_order=2,
        )
        snap3 = CustomerInspectionRateSnapshot.objects.create(
            customer_inspection=customer_inspection,
            rate_item_id=r3_id,
            category_name_snapshot="Electrical & PCB",
            item_name_snapshot="Inverter PCB Motherboard Repair",
            description_snapshot="Component-level repair of outdoor IPM PCB",
            price_snapshot=Decimal("2450.00"),
            unit_snapshot="unit",
            service_type_snapshot="PART",
            display_order=3,
        )
        snap4 = CustomerInspectionRateSnapshot.objects.create(
            customer_inspection=customer_inspection,
            rate_item_id=r4_id,
            category_name_snapshot="Servicing & Cleaning",
            item_name_snapshot="Deep Chemical Jet Foam Coil Wash",
            description_snapshot="Indoor evaporator and outdoor condenser jet wash",
            price_snapshot=Decimal("799.00"),
            unit_snapshot="service",
            service_type_snapshot="LABOR",
            display_order=4,
        )

        record_pass("Create CustomerInspection & Rate Snapshots", f"SR ID: {sr_a.id}, CustInspection ID: {customer_inspection.id}")
    except Exception as e:
        record_fail("Create CustomerInspection & Rate Snapshots", e)
        return

    # Step A2: Vendor / Technician accepts and starts journey
    print("\n[A2] Vendor Confirm and Technician Assignment")
    try:
        # Vendor confirms
        req = factory.post(f"/api/vendor/estimations/{sr_a.id}/confirm/", {})
        force_authenticate(req, user=vendor_user)
        res = VendorEstimationConfirmView.as_view()(req, pk=sr_a.id)
        assert res.status_code == 200, f"Expected 200, got {res.status_code}: {res.data}"

        # Assign technician
        req = factory.post(f"/api/vendor/estimations/{sr_a.id}/assign-technician/", {
            "technician_id": employee.id,
            "technician_name": "Ramesh Kumar",
            "technician_phone": "+919876543210"
        }, format="json")
        force_authenticate(req, user=vendor_user)
        res = VendorEstimationAssignTechnicianView.as_view()(req, pk=sr_a.id)
        assert res.status_code == 200, f"Expected 200, got {res.status_code}: {res.data}"

        # Technician starts journey
        req = factory.post(f"/api/vendor/estimations/{sr_a.id}/start-journey/", {})
        force_authenticate(req, user=tech_user)
        res = VendorEstimationStartJourneyView.as_view()(req, pk=sr_a.id)
        assert res.status_code == 200, f"Expected 200, got {res.status_code}: {res.data}"

        # Technician marks arrived
        req = factory.post(f"/api/vendor/estimations/{sr_a.id}/arrived/", {})
        force_authenticate(req, user=tech_user)
        res = VendorEstimationArrivedView.as_view()(req, pk=sr_a.id)
        assert res.status_code == 200, f"Expected 200, got {res.status_code}: {res.data}"

        # Technician verifies customer start OTP
        req = factory.post(f"/api/vendor/estimations/{sr_a.id}/verify-otp/", {"otp": "458921"}, format="json")
        force_authenticate(req, user=tech_user)
        res = VendorEstimationVerifyOtpView.as_view()(req, pk=sr_a.id)
        assert res.status_code == 200, f"Expected 200, got {res.status_code}: {res.data}"
        assert res.data["data"]["status"] == "INSPECTION_IN_PROGRESS", f"Expected INSPECTION_IN_PROGRESS, got {res.data['data']['status']}"

        record_pass("Technician Dispatch, Journey, Arrival & OTP Check-in", "Status advanced to INSPECTION_IN_PROGRESS")
    except Exception as e:
        record_fail("Technician Dispatch, Journey, Arrival & OTP Check-in", e)
        return

    # Step A3: Technician performs on-site inspection, records AC specs, multi-point checklist, and findings
    print("\n[A3] Technician Records Multi-Point Inspection Checklist & Defect Findings")
    try:
        inspection_data = {
            "ac_details": {
                "ac_brand": "Daikin",
                "ac_type": "Inverter Split AC",
                "ac_capacity": "1.5_TON",
                "gas_type": "R32",
                "unit_age": "3-5 Years",
                "model_number": "FTKM50TV16U",
                "checklist": {
                    "indoor_filter": "CHOKED",
                    "indoor_coil": "DIRTY",
                    "blower_fan": "NORMAL",
                    "outdoor_coil": "DUSTY",
                    "compressor_status": "RUNNING_NORMAL",
                    "service_valves": "OIL_TRACES",
                    "voltage_reading": "232V",
                    "capacitor_status": "WEAK",
                    "standing_pressure": "95 PSI (Low - Gas Leakage)",
                    "cooling_delta_t": "5°C (Poor cooling)",
                }
            },
            "diagnosis": "Refrigerant gas leak at outdoor flare nut union. Compressor run capacitor weak (28uF instead of 45uF). Evaporator coil heavily choked.",
            "notes": "Advised customer to perform leak brazing, gas recharge, capacitor replacement, and deep jet cleaning.",
            "findings": [
                {
                    "finding_type": "Gas Leakage",
                    "title": "R32 Refrigerant Gas Leakage at Service Flare Nut",
                    "severity": "HIGH",
                    "description": "Oil traces and standing pressure 95 PSI vs 140 PSI rated.",
                    "recommended_action": "Tighten flare nut, nitrogen leak test, vacuum, top up R32 gas (1kg).",
                    "quantity": 1,
                    "unit": "kg"
                },
                {
                    "finding_type": "Capacitor",
                    "title": "Dual Run Capacitor Weak (28uF vs 45uF)",
                    "severity": "HIGH",
                    "description": "Capacitor output dropped by 38%, causing compressor overheating.",
                    "recommended_action": "Replace with genuine 45/5 uF capacitor.",
                    "quantity": 1,
                    "unit": "piece"
                },
                {
                    "finding_type": "Coil Cleaning",
                    "title": "Evaporator & Condenser Coil Grime Choking",
                    "severity": "MEDIUM",
                    "description": "Airflow restricted by >40% due to dust sludge.",
                    "recommended_action": "Deep chemical foam jet wash.",
                    "quantity": 1,
                    "unit": "service"
                }
            ]
        }

        # Save inspection details
        req = factory.post(f"/api/vendor/estimations/{sr_a.id}/inspection/save/", inspection_data, format="json")
        force_authenticate(req, user=tech_user)
        res = VendorEstimationInspectionSaveView.as_view()(req, pk=sr_a.id)
        assert res.status_code == 200, f"Expected 200, got {res.status_code}: {res.data}"

        # Complete inspection
        req = factory.post(f"/api/vendor/estimations/{sr_a.id}/inspection/complete/", {
            "diagnosis_summary": inspection_data["diagnosis"],
            "notes": inspection_data["notes"]
        }, format="json")
        force_authenticate(req, user=tech_user)
        res = VendorEstimationInspectionCompleteView.as_view()(req, pk=sr_a.id)
        assert res.status_code == 200, f"Expected 200, got {res.status_code}: {res.data}"
        assert res.data["data"]["status"] == "INSPECTION_COMPLETED", f"Expected INSPECTION_COMPLETED, got {res.data['data']['status']}"

        record_pass("Technician Save Inspection Details & Complete Inspection", "AC details, checklist, and 3 findings saved")
    except Exception as e:
        record_fail("Technician Save Inspection Details & Complete Inspection", e)
        return

    # Step A4: Technician builds quotation selecting required items from rate-card snapshot
    print("\n[A4] Technician Quotation Builder with Rate-Card Snapshot Line Items")
    quote_id = None
    try:
        # Technician picks snap1 (Gas Refill ₹1850), snap2 (Capacitor ₹850), and snap4 (Jet Wash ₹799)
        quote_payload = {
            "valid_until": (datetime.now(timezone.utc) + timedelta(days=7)).strftime("%Y-%m-%d"),
            "tax_rate_percent": 18,
            "discount_amount": 100,
            "notes": "Includes 90 days warranty on replaced capacitor and gas top-up.",
            "items": [
                {
                    "rate_item_id": snap1.rate_item_id,
                    "category_name_snapshot": snap1.category_name_snapshot,
                    "item_name_snapshot": snap1.item_name_snapshot,
                    "title": snap1.item_name_snapshot,
                    "item_type": "GAS",
                    "quantity": 1,
                    "unit": snap1.unit_snapshot,
                    "unit_price": float(snap1.price_snapshot),
                },
                {
                    "rate_item_id": snap2.rate_item_id,
                    "category_name_snapshot": snap2.category_name_snapshot,
                    "item_name_snapshot": snap2.item_name_snapshot,
                    "title": snap2.item_name_snapshot,
                    "item_type": "PART",
                    "quantity": 1,
                    "unit": snap2.unit_snapshot,
                    "unit_price": float(snap2.price_snapshot),
                },
                {
                    "rate_item_id": snap4.rate_item_id,
                    "category_name_snapshot": snap4.category_name_snapshot,
                    "item_name_snapshot": snap4.item_name_snapshot,
                    "title": snap4.item_name_snapshot,
                    "item_type": "LABOR",
                    "quantity": 1,
                    "unit": snap4.unit_snapshot,
                    "unit_price": float(snap4.price_snapshot),
                }
            ]
        }

        req = factory.post(f"/api/vendor/estimations/{sr_a.id}/quotation/", quote_payload, format="json")
        force_authenticate(req, user=tech_user)
        res = VendorEstimationQuotationView.as_view()(req, pk=sr_a.id)
        assert res.status_code in [200, 201], f"Expected 200/201, got {res.status_code}: {res.data}"

        quote_data = res.data["data"]["latest_quotation"]
        quote_id = quote_data["id"]
        assert quote_data.get("items_count") == 3 or len(res.data["data"]["quotations"][0]["items"]) == 3, f"Expected 3 items"

        # Verify snapshot prices and math:
        # subtotal = 1850 + 850 + 799 = 3499
        # tax (18%) = 3499 * 0.18 = 629.82
        # discount = 100
        # total = 3499 + 629.82 - 100 = 4028.82
        subtotal_expected = Decimal("3499.00")
        tax_expected = Decimal("629.82")
        total_expected = Decimal("4028.82")

        assert Decimal(str(quote_data["subtotal"])) == subtotal_expected, f"Subtotal mismatch: {quote_data['subtotal']} vs {subtotal_expected}"
        assert Decimal(str(quote_data["tax_amount"])) == tax_expected, f"Tax mismatch: {quote_data['tax_amount']} vs {tax_expected}"
        assert Decimal(str(quote_data["total_amount"])) == total_expected, f"Total mismatch: {quote_data['total_amount']} vs {total_expected}"

        # Verify DB line items snapshot integrity
        db_items = EstimationQuotationItem.objects.filter(quotation_id=quote_id)
        assert db_items.count() == 3
        gas_item = db_items.filter(item_name_snapshot=snap1.item_name_snapshot).first()
        assert gas_item is not None
        assert gas_item.rate_item_id == snap1.rate_item_id
        assert gas_item.unit_price_snapshot == snap1.price_snapshot

        record_pass("Quotation Created with Rate-Card Snapshots", f"Quote #{quote_data['quote_ref']} Total: ₹{quote_data['total_amount']}")
    except Exception as e:
        record_fail("Quotation Created with Rate-Card Snapshots", e)
        return

    # Step A5: Technician submits quotation for Customer Admin Review
    print("\n[A5] Technician Submits Quotation for Customer Admin Review")
    try:
        req = factory.post(f"/api/vendor/estimations/{sr_a.id}/quotation/{quote_id}/submit/", {})
        force_authenticate(req, user=tech_user)
        res = VendorEstimationQuotationSubmitForReviewView.as_view()(req, pk=sr_a.id, quote_id=quote_id)
        assert res.status_code == 200, f"Expected 200, got {res.status_code}: {res.data}"

        quote_obj = EstimationQuotation.objects.get(id=quote_id)
        assert quote_obj.status == "SUBMITTED_FOR_ADMIN_REVIEW", f"Expected SUBMITTED_FOR_ADMIN_REVIEW, got {quote_obj.status}"

        record_pass("Submit for Admin Review", f"Status is {quote_obj.status}")
    except Exception as e:
        record_fail("Submit for Admin Review", e)
        return

    # Step A6: Admin Review Gate — Send Back with revision notes
    print("\n[A6] Customer Admin Reviews and Sends Back to Technician")
    try:
        req = factory.post(f"/api/vendor/estimations/{sr_a.id}/quotation/{quote_id}/admin-review/", {
            "action": "SEND_BACK",
            "admin_notes": "Please verify if 1kg gas is sufficient or if 1.5kg is required for dual-inverter split unit."
        }, format="json")
        force_authenticate(req, user=vendor_user)
        res = VendorEstimationAdminReviewView.as_view()(req, pk=sr_a.id, quote_id=quote_id)
        assert res.status_code == 200, f"Expected 200, got {res.status_code}: {res.data}"

        quote_obj = EstimationQuotation.objects.get(id=quote_id)
        assert quote_obj.status == "SENT_BACK_TO_TECHNICIAN", f"Expected SENT_BACK_TO_TECHNICIAN, got {quote_obj.status}"
        assert "1.5kg" in quote_obj.admin_notes

        record_pass("Admin Send-Back with Feedback", f"Notes: '{quote_obj.admin_notes}'")
    except Exception as e:
        record_fail("Admin Send-Back with Feedback", e)
        return

    # Step A7: Technician updates quotation and resubmits for Admin Review
    print("\n[A7] Technician Updates Line Items and Resubmits for Admin Review")
    try:
        # Update gas quantity to 1.5kg
        updated_payload = {
            "valid_until": (datetime.now(timezone.utc) + timedelta(days=7)).strftime("%Y-%m-%d"),
            "tax_rate_percent": 18,
            "discount_amount": 100,
            "notes": "Updated to 1.5kg R32 gas per Daikin dual-coil specs.",
            "items": [
                {
                    "rate_item_id": snap1.rate_item_id,
                    "category_name_snapshot": snap1.category_name_snapshot,
                    "item_name_snapshot": snap1.item_name_snapshot,
                    "title": snap1.item_name_snapshot,
                    "item_type": "GAS",
                    "quantity": 1.5,
                    "unit": snap1.unit_snapshot,
                    "unit_price": float(snap1.price_snapshot),
                },
                {
                    "rate_item_id": snap2.rate_item_id,
                    "category_name_snapshot": snap2.category_name_snapshot,
                    "item_name_snapshot": snap2.item_name_snapshot,
                    "title": snap2.item_name_snapshot,
                    "item_type": "PART",
                    "quantity": 1,
                    "unit": snap2.unit_snapshot,
                    "unit_price": float(snap2.price_snapshot),
                },
                {
                    "rate_item_id": snap4.rate_item_id,
                    "category_name_snapshot": snap4.category_name_snapshot,
                    "item_name_snapshot": snap4.item_name_snapshot,
                    "title": snap4.item_name_snapshot,
                    "item_type": "LABOR",
                    "quantity": 1,
                    "unit": snap4.unit_snapshot,
                    "unit_price": float(snap4.price_snapshot),
                }
            ]
        }

        # Save update
        req = factory.post(f"/api/vendor/estimations/{sr_a.id}/quotation/", updated_payload, format="json")
        force_authenticate(req, user=tech_user)
        res = VendorEstimationQuotationView.as_view()(req, pk=sr_a.id)
        assert res.status_code in [200, 201], f"Expected 200/201, got {res.status_code}: {res.data}"

        # Resubmit for review
        req = factory.post(f"/api/vendor/estimations/{sr_a.id}/quotation/{quote_id}/submit/", {})
        force_authenticate(req, user=tech_user)
        res = VendorEstimationQuotationSubmitForReviewView.as_view()(req, pk=sr_a.id, quote_id=quote_id)
        assert res.status_code == 200, f"Expected 200, got {res.status_code}: {res.data}"

        quote_obj = EstimationQuotation.objects.get(id=quote_id)
        assert quote_obj.status == "SUBMITTED_FOR_ADMIN_REVIEW"

        record_pass("Resubmit for Admin Review", "Quotation updated and resubmitted")
    except Exception as e:
        record_fail("Resubmit for Admin Review", e)
        return

    # Step A8: Customer Admin Approves Quotation (Releasing to Customer)
    print("\n[A8] Customer Admin Approves Quotation")
    try:
        req = factory.post(f"/api/vendor/estimations/{sr_a.id}/quotation/{quote_id}/admin-review/", {
            "action": "APPROVE",
            "admin_notes": "All rates verified against snapshot catalog. Approved for customer release."
        }, format="json")
        force_authenticate(req, user=vendor_user)
        res = VendorEstimationAdminReviewView.as_view()(req, pk=sr_a.id, quote_id=quote_id)
        assert res.status_code == 200, f"Expected 200, got {res.status_code}: {res.data}"

        quote_obj = EstimationQuotation.objects.get(id=quote_id)
        assert quote_obj.status in ["ADMIN_APPROVED", "SENT"], f"Expected ADMIN_APPROVED/SENT, got {quote_obj.status}"

        record_pass("Admin Approves Quotation", f"Quotation released to customer with status: {quote_obj.status}")
    except Exception as e:
        record_fail("Admin Approves Quotation", e)
        return

    # Step A9: Customer Accepts Quotation and Books Repair
    print("\n[A9] Customer Decision: Accept Quotation & Book Job")
    try:
        req = factory.post(f"/api/vendor/estimations/{sr_a.id}/customer-decide/", {
            "decision": "APPROVE",
            "scheduled_date": datetime.now(timezone.utc).strftime("%Y-%m-%d"),
            "scheduled_time": "10:00 AM - 01:00 PM"
        }, format="json")
        force_authenticate(req, user=tech_user)
        res = VendorEstimationCustomerDecideView.as_view()(req, pk=sr_a.id)
        assert res.status_code == 200, f"Expected 200, got {res.status_code}: {res.data}"

        quote_obj = EstimationQuotation.objects.get(id=quote_id)
        assert quote_obj.status == "APPROVED", f"Expected APPROVED, got {quote_obj.status}"

        # Verify fee is waived/credited towards the job
        fee_obj = EstimationFee.objects.filter(estimation__service_request=sr_a).first()
        assert fee_obj is not None
        assert fee_obj.status == "WAIVED", f"Expected fee WAIVED, got {fee_obj.status}"

        record_pass("Customer Accepts Quotation", "Quotation APPROVED, ₹199 diagnostic fee waived/credited")
    except Exception as e:
        record_fail("Customer Accepts Quotation", e)
        return

    # Step A10: Repair Progression Lifecycle (Start -> Complete -> Test -> Customer Confirmation -> COMPLETED)
    print("\n[A10] Multi-Stage Repair Execution to Completion")
    try:
        # Step 1: Start Repair
        req = factory.post(f"/api/vendor/estimations/{sr_a.id}/repair/progress/", {"stage": "START_REPAIR"}, format="json")
        force_authenticate(req, user=tech_user)
        res = VendorEstimationRepairProgressView.as_view()(req, pk=sr_a.id)
        assert res.status_code == 200, f"Expected 200, got {res.status_code}: {res.data}"
        assert res.data["data"]["status"] == "REPAIR_IN_PROGRESS"

        # Step 2: Complete Repair
        req = factory.post(f"/api/vendor/estimations/{sr_a.id}/repair/progress/", {
            "stage": "COMPLETE_REPAIR",
            "notes": "Flare nut brazed, 1.5kg R32 filled, 45uF capacitor installed, coils jet washed."
        }, format="json")
        force_authenticate(req, user=tech_user)
        res = VendorEstimationRepairProgressView.as_view()(req, pk=sr_a.id)
        assert res.status_code == 200, f"Expected 200, got {res.status_code}: {res.data}"
        assert res.data["data"]["status"] == "REPAIR_COMPLETED"

        # Step 3: Test AC & Cooling Performance
        req = factory.post(f"/api/vendor/estimations/{sr_a.id}/repair/progress/", {
            "stage": "TEST_AC",
            "notes": "AC tested for 20 mins. Grill temp 12°C, Room temp 24°C (Delta T = 12°C - Normal)."
        }, format="json")
        force_authenticate(req, user=tech_user)
        res = VendorEstimationRepairProgressView.as_view()(req, pk=sr_a.id)
        assert res.status_code == 200, f"Expected 200, got {res.status_code}: {res.data}"
        assert res.data["data"]["status"] == "TESTING_AC"

        # Step 4: Customer Confirmation / Sign-Off
        req = factory.post(f"/api/vendor/estimations/{sr_a.id}/repair/progress/", {
            "stage": "CUSTOMER_CONFIRM",
            "notes": "Customer inspected cooling and signed off."
        }, format="json")
        force_authenticate(req, user=tech_user)
        res = VendorEstimationRepairProgressView.as_view()(req, pk=sr_a.id)
        assert res.status_code == 200, f"Expected 200, got {res.status_code}: {res.data}"
        assert res.data["data"]["status"] == "COMPLETED"

        # Verify ServiceRequest final status
        sr_a.refresh_from_db()
        assert sr_a.status == "completed"

        # Verify Invoice generation
        req = factory.get(f"/api/vendor/estimations/{sr_a.id}/invoice/")
        force_authenticate(req, user=tech_user)
        res = VendorEstimationInvoiceView.as_view()(req, pk=sr_a.id)
        assert res.status_code == 200, f"Expected 200, got {res.status_code}: {res.data}"
        assert res.data["data"]["invoice_type"] == "JOB_INVOICE"

        record_pass("Repair Progression & Job Completion", f"Status: COMPLETED, Invoice: {res.data['data']['invoice_id']}")
    except Exception as e:
        record_fail("Repair Progression & Job Completion", e)
        return

    # =========================================================================
    # SCENARIO B: Customer Rejection / Inspection-Only Closure Path
    # Diagnostic fee of ₹199 collected, zero repair charges, tech blocked from repair
    # =========================================================================
    print("\n--- SCENARIO B: Customer Rejection -> Inspection-Only Closure (₹199 Diagnostic Fee) ---")

    try:
        # 1. Create booking with CustomerInspection + RateSnapshots
        sr_b = ServiceRequest.objects.create(
            request_id=f"AC_SR_{TEST_RUN_ID}_B",
            job_type="ESTIMATION",
            request_kind="ESTIMATION",
            customer_name="Deepak Verma",
            phone="+919811223344",
            email="deepak@example.com",
            service_category="HVAC & Air Conditioning",
            issue_title="Voltas 1 Ton Window AC Inspection",
            description="AC compressor cutting off repeatedly",
            address="Flat 201, Green View Apartments, Delhi",
            status="requested",
            company=company,
            start_otp="782194",
            total_amount=Decimal("199.00"),
            preferred_date=datetime.now(timezone.utc).date(),
            preferred_time="02:00 PM - 05:00 PM",
        )

        est_b = Estimation.objects.create(
            service_request=sr_b,
            ac_type="WINDOW",
            ac_brand="Voltas",
            ac_capacity="1_TON",
            ac_quantity=1,
            customer_symptom="AC compressor cutting off repeatedly",
            status="REQUESTED",
        )

        fee_b = EstimationFee.objects.create(
            estimation=est_b,
            amount=Decimal("199.00"),
            currency="INR",
            status="PENDING",
        )

        cust_insp_b = CustomerInspection.objects.create(
            service_request=sr_b,
            inspection_name_snapshot="AC Comprehensive Diagnostic & Inspection",
            diagnostic_fee_snapshot=Decimal("199.00"),
            currency="INR",
            quantity=1,
            status="BOOKED",
        )

        CustomerInspectionRateSnapshot.objects.create(
            customer_inspection=cust_insp_b,
            category_name_snapshot="Gas Charging",
            item_name_snapshot="R32 Gas Refill",
            description_snapshot="Standard R32 refrigerant refill",
            price_snapshot=Decimal("1850.00"),
            unit_snapshot="kg",
            service_type_snapshot="GAS",
            display_order=1,
        )

        # 2. Confirm, Assign, Arrive, Verify OTP
        req = factory.post(f"/api/vendor/estimations/{sr_b.id}/confirm/", {})
        force_authenticate(req, user=vendor_user)
        VendorEstimationConfirmView.as_view()(req, pk=sr_b.id)

        req = factory.post(f"/api/vendor/estimations/{sr_b.id}/assign-technician/", {
            "technician_id": employee.id,
            "technician_name": "Ramesh Kumar"
        }, format="json")
        force_authenticate(req, user=vendor_user)
        VendorEstimationAssignTechnicianView.as_view()(req, pk=sr_b.id)

        req = factory.post(f"/api/vendor/estimations/{sr_b.id}/verify-otp/", {"otp": "782194"}, format="json")
        force_authenticate(req, user=tech_user)
        VendorEstimationVerifyOtpView.as_view()(req, pk=sr_b.id)

        # 3. Complete Inspection
        req = factory.post(f"/api/vendor/estimations/{sr_b.id}/inspection/complete/", {
            "diagnosis_summary": "Compressor motor shorted; replacement required.",
            "notes": "Cost exceeds budget expectation."
        }, format="json")
        force_authenticate(req, user=tech_user)
        VendorEstimationInspectionCompleteView.as_view()(req, pk=sr_b.id)

        # 4. Create Quotation & Submit for Admin Review & Admin Approve
        req = factory.post(f"/api/vendor/estimations/{sr_b.id}/quotation/", {
            "valid_until": "2026-10-01",
            "items": [
                {"title": "Rotary Compressor Replacement", "item_type": "PART", "quantity": 1, "unit": "unit", "unit_price": 4500}
            ]
        }, format="json")
        force_authenticate(req, user=tech_user)
        res = VendorEstimationQuotationView.as_view()(req, pk=sr_b.id)
        assert res.status_code in [200, 201], f"Expected 200/201, got {res.status_code}: {res.data}"
        quote_b_id = res.data["data"]["latest_quotation"]["id"]

        req = factory.post(f"/api/vendor/estimations/{sr_b.id}/quotation/{quote_b_id}/submit/", {})
        force_authenticate(req, user=tech_user)
        VendorEstimationQuotationSubmitForReviewView.as_view()(req, pk=sr_b.id, quote_id=quote_b_id)

        req = factory.post(f"/api/vendor/estimations/{sr_b.id}/quotation/{quote_b_id}/admin-review/", {
            "action": "APPROVE"
        }, format="json")
        force_authenticate(req, user=vendor_user)
        VendorEstimationAdminReviewView.as_view()(req, pk=sr_b.id, quote_id=quote_b_id)

        # 5. Customer REJECTS quotation
        req = factory.post(f"/api/vendor/estimations/{sr_b.id}/customer-decide/", {
            "decision": "REJECT",
            "rejection_reason": "PRICE_TOO_HIGH",
            "rejection_note": "Customer decided to purchase a new AC unit instead of repairing.",
            "payment_method": "UPI"
        }, format="json")
        force_authenticate(req, user=tech_user)
        res = VendorEstimationCustomerDecideView.as_view()(req, pk=sr_b.id)
        assert res.status_code == 200, f"Expected 200, got {res.status_code}: {res.data}"

        # 6. Verify assertions for rejection path
        quote_b_obj = EstimationQuotation.objects.get(id=quote_b_id)
        assert quote_b_obj.status == "REJECTED", f"Expected quote REJECTED, got {quote_b_obj.status}"

        fee_b_obj = EstimationFee.objects.filter(estimation__service_request=sr_b).first()
        assert fee_b_obj is not None
        assert fee_b_obj.status == "COLLECTED", f"Expected fee COLLECTED, got {fee_b_obj.status}"
        assert fee_b_obj.amount == Decimal("199.00")

        # Verify technician CANNOT start repair on rejected estimation
        req = factory.post(f"/api/vendor/estimations/{sr_b.id}/repair/progress/", {"stage": "START_REPAIR"}, format="json")
        force_authenticate(req, user=tech_user)
        res = VendorEstimationRepairProgressView.as_view()(req, pk=sr_b.id)
        assert res.status_code == 400, f"Expected 400 when attempting repair on rejected quote, got {res.status_code}"

        # Verify diagnostic invoice
        req = factory.get(f"/api/vendor/estimations/{sr_b.id}/invoice/")
        force_authenticate(req, user=tech_user)
        res = VendorEstimationInvoiceView.as_view()(req, pk=sr_b.id)
        assert res.status_code == 200, f"Expected 200, got {res.status_code}: {res.data}"
        assert res.data["data"]["invoice_type"] == "INSPECTION_FEE_INVOICE"
        assert Decimal(str(res.data["data"]["total_amount"])) == Decimal("199.00")

        record_pass("Customer Rejection & Inspection-Only Closure", "Fee ₹199 collected, repair blocked, fee invoice generated")
    except Exception as e:
        record_fail("Customer Rejection & Inspection-Only Closure", e)
        return

    # =========================================================================
    # Summary of Test Execution
    # =========================================================================
    print(f"\n==========================================================================")
    print(f"TEST EXECUTION COMPLETE")
    print(f"Total Passed: {len(PASSED_TESTS)} | Total Failed: {len(FAILED_TESTS)}")
    print(f"==========================================================================\n")

    if FAILED_TESTS:
        print("FAILED TESTS:")
        for name, err in FAILED_TESTS:
            print(f"  ❌ {name}: {err}")
        sys.exit(1)
    else:
        print("🎉 ALL END-TO-END VERIFICATION TESTS PASSED PERFECTLY!")


if __name__ == "__main__":
    run_e2e_suite()
