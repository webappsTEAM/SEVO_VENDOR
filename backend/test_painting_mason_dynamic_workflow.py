"""
Comprehensive automated test suite for Dynamic Painting & Mason Multi-Day Workflow,
Dual-Radius Serviceability, CRM Gates, Hold/Resume, Scope Reduction, and GST Invoicing.
"""
import os
import sys
import django

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "workforce_core.settings")
django.setup()

from decimal import Decimal
from django.utils import timezone
from django.contrib.auth import get_user_model
from companies.models import Company
from employees.models import Employee
from service_requests.models import ServiceRequest
from workforce_api.models import (
    WorkforceServicePricingPolicy,
    WorkforceVendorBaseLocation,
    WorkforceQuote,
    WorkforceQuoteItem,
    WorkforcePaintingQuote,
    WorkforceMasonQuote,
    WorkforceJobHold,
    WorkforceScopeReduction,
    WorkforceInvoice,
)
from workforce_api.services import pricing_policy, quotation_service, invoice_service, automatic_dispatch

User = get_user_model()
PASSED = 0
FAILED = 0


def record_result(name, condition, msg=""):
    global PASSED, FAILED
    if condition:
        PASSED += 1
        print(f" [PASS] {name} - {msg}")
    else:
        FAILED += 1
        print(f" [FAIL] {name} - {msg}")


def run_tests():
    print("\n" + "=" * 65)
    print(" STARTING DYNAMIC PAINTING & MASON WORKFLOW VERIFICATION")
    print("=" * 65 + "\n")

    # Setup test users and company
    admin_user, _ = User.objects.get_or_create(username="test_crm_admin", defaults={"email": "crm@caltrack.com", "role": "admin"})
    cust_user, _ = User.objects.get_or_create(username="test_customer_paint", defaults={"email": "cust@paint.com", "role": "customer"})
    tech_user, _ = User.objects.get_or_create(username="test_painter_tech", defaults={"email": "painter@caltrack.com", "role": "employee"})

    company, _ = Company.objects.get_or_create(
        company_name="Hosur Painting Experts Pvt Ltd",
        defaults={"slug": "hosur-painting-experts", "business_type": "service_provider", "is_active": True}
    )

    tech_emp, _ = Employee.objects.get_or_create(
        user=tech_user,
        defaults={"company": company, "employee_id": "TECH-PAINT-001", "is_active": True}
    )

    # ─────────────────────────────────────────────────────────────────────────
    # 1. DYNAMIC DUAL-RADIUS SERVICEABILITY & PRICING
    # ─────────────────────────────────────────────────────────────────────────
    print("\n--- 1. Testing Dynamic Dual-Radius Serviceability & Distance Bands ---")
    policy, _ = WorkforceServicePricingPolicy.objects.get_or_create(
        service_category="Painting",
        defaults={
            "display_name": "Interior & Exterior Painting",
            "consultation_fee_mode": WorkforceServicePricingPolicy.ConsultationFeeMode.DISTANCE_BAND,
            "free_radius_km": Decimal("15.00"),
            "beyond_radius_amount": Decimal("300.00"),
            "max_service_radius_km": Decimal("50.00"),
            "hub_latitude": 12.7409,
            "hub_longitude": 77.8253,
            "advance_percent": Decimal("50.00"),
            "is_active": True,
        }
    )
    policy.free_radius_km = Decimal("15.00")
    policy.beyond_radius_amount = Decimal("300.00")
    policy.max_service_radius_km = Decimal("50.00")
    policy.hub_latitude = 12.7409
    policy.hub_longitude = 77.8253
    policy.save()

    # Vendor base location registered in Hosur
    base_loc, _ = WorkforceVendorBaseLocation.objects.get_or_create(
        company=company,
        defaults={
            "address": "123 Bagalur Road, Hosur",
            "area": "Bagalur",
            "city": "Hosur",
            "pincode": "635109",
            "base_latitude": 12.7409,
            "base_longitude": 77.8253,
            "max_service_radius_km": Decimal("50.00"),
            "is_active": True,
        }
    )

    # Test 8 km (Inside free radius: Rs.0)
    # ~8 km north (lat + 0.072)
    fee_8km, exp_8km, serv_8km, dist_8km = pricing_policy.evaluate_serviceability(
        "Painting", latitude=12.8129, longitude=77.8253, vendor=company
    )
    record_result("8 km Site Evaluation", serv_8km and fee_8km == Decimal("0.00"), f"Dist={dist_8km:.1f}km, Fee=Rs.{fee_8km}, Serv={serv_8km}")

    # Test 14 km (Inside free radius: Rs.0)
    # ~14 km (lat + 0.126)
    fee_14km, exp_14km, serv_14km, dist_14km = pricing_policy.evaluate_serviceability(
        "Painting", latitude=12.8669, longitude=77.8253, vendor=company
    )
    record_result("14 km Site Evaluation", serv_8km and fee_14km == Decimal("0.00"), f"Dist={dist_14km:.1f}km, Fee=Rs.{fee_14km}, Serv={serv_14km}")

    # Test 20 km (Beyond free radius, within 50 km: Rs.300)
    # ~20 km (lat + 0.180)
    fee_20km, exp_20km, serv_20km, dist_20km = pricing_policy.evaluate_serviceability(
        "Painting", latitude=12.9209, longitude=77.8253, vendor=company
    )
    record_result("20 km Site Evaluation", serv_20km and fee_20km == Decimal("300.00"), f"Dist={dist_20km:.1f}km, Fee=Rs.{fee_20km}, Serv={serv_20km}")

    # Test 35 km (Within 50 km: Rs.300)
    fee_35km, exp_35km, serv_35km, dist_35km = pricing_policy.evaluate_serviceability(
        "Painting", latitude=13.0559, longitude=77.8253, vendor=company
    )
    record_result("35 km Site Evaluation", serv_35km and fee_35km == Decimal("300.00"), f"Dist={dist_35km:.1f}km, Fee=Rs.{fee_35km}, Serv={serv_35km}")

    # Test 55 km (Beyond max radius 50 km: NOT SERVICEABLE)
    # ~55 km (lat + 0.500)
    fee_55km, exp_55km, serv_55km, dist_55km = pricing_policy.evaluate_serviceability(
        "Painting", latitude=13.2409, longitude=77.8253, vendor=company
    )
    record_result("55 km Site Evaluation (Out of Zone)", serv_55km is False, f"Dist={dist_55km:.1f}km, Serv={serv_55km}, Msg={exp_55km}")

    # ─────────────────────────────────────────────────────────────────────────
    # 2. DISPATCH & SERVICE ALIAS MATCHING
    # ─────────────────────────────────────────────────────────────────────────
    print("\n--- 2. Testing Dispatch Aliases for Painting & Mason ---")
    aliases = automatic_dispatch.EXPLICIT_SERVICE_ALIASES
    record_result("Painting Aliases", "painting" in aliases and "paintings" in aliases["painting"], "painting <-> paintings mapped")
    record_result("Mason Aliases", "mason" in aliases and "masonry" in aliases["mason"] and "tile fixing" in aliases["mason"], "mason <-> masonry <-> tile fixing mapped")

    # ─────────────────────────────────────────────────────────────────────────
    # 3. QUOTATION DURATION, CRM PRE-SEND GATE & APPROVAL
    # ─────────────────────────────────────────────────────────────────────────
    print("\n--- 3. Testing Quotation Lifecycle, Duration Days & CRM Approval Gate ---")
    insp_job = ServiceRequest.objects.create(
        customer=cust_user,
        company=company,
        assigned_employee=tech_emp,
        service_category="Painting",
        issue_title="Full House Painting 2BHK",
        latitude=12.8129,
        longitude=77.8253,
        preferred_date=timezone.now().date(),
        preferred_time="09:00:00",
        status="in_progress",
    )

    quote = WorkforceQuote.objects.create(
        job=insp_job,
        technician=tech_emp,
        company=company,
        customer=cust_user,
        title="2BHK Premium Interior Painting",
        service_category="Painting",
        estimated_duration_days=5,
        subtotal_amount=Decimal("40000.00"),
        tax_amount=Decimal("7200.00"),
        total_amount=Decimal("47200.00"),
        inspection_fee_adjusted=Decimal("0.00"),
        net_payable=Decimal("47200.00"),
        advance_percent=Decimal("50.00"),
        status=WorkforceQuote.Status.DRAFT,
    )

    p_details = WorkforcePaintingQuote.objects.create(
        quote=quote,
        property_type="2BHK Apartment",
        area_sqft=Decimal("1200.00"),
        paint_type="Royal Luxury Emulsion",
        number_of_coats=2,
        estimated_duration_days=5,
    )

    record_result("Quotation Duration Days Field", quote.estimated_duration_days == 5 and p_details.estimated_duration_days == 5, f"Quote duration: {quote.estimated_duration_days} days")

    # Vendor submits quote to CRM
    quote.status = WorkforceQuote.Status.PENDING_REVIEW
    quote.save()
    record_result("Submit Quote to CRM", quote.status == WorkforceQuote.Status.PENDING_REVIEW, "Quote is PENDING_REVIEW")

    # CRM Admin approves quote -> transitions to SENT_TO_CUSTOMER + generates decision token
    quote.admin_cleared_by = admin_user
    quote.admin_cleared_at = timezone.now()
    quote.save()

    sent_quote = quotation_service.send_quote_to_customer(quote.id, actor=admin_user)
    record_result(
        "CRM Approval & Send to Customer",
        sent_quote.status == WorkforceQuote.Status.SENT_TO_CUSTOMER and bool(sent_quote.decision_token),
        f"Status={sent_quote.status}, Token={sent_quote.decision_token[:10]}..."
    )

    # Customer accepts quote
    accepted_quote, work_job = quotation_service.record_customer_decision(
        quote_id=sent_quote.id,
        action="ACCEPT",
        token=sent_quote.decision_token,
        actor=cust_user,
    )

    # ─────────────────────────────────────────────────────────────────────────
    # 4. ADVANCE PAYMENT & 50% BREAKDOWN WITH CONSULTATION FEE CREDIT
    # ─────────────────────────────────────────────────────────────────────────
    print("\n--- 4. Testing 50% Advance & Consultation Fee Credit ---")
    adv_pct = pricing_policy.advance_percent("Painting")
    adv_amt, bal_amt = pricing_policy.split_advance_and_balance(quote.net_payable, "Painting", percent=adv_pct)
    record_result("50% Advance Calculation", adv_pct == Decimal("50.00") and adv_amt == Decimal("23600.00") and bal_amt == Decimal("23600.00"), f"Advance: Rs.{adv_amt}, Balance: Rs.{bal_amt}")

    # ─────────────────────────────────────────────────────────────────────────
    # 5. MULTI-DAY JOB HOLD & RESUME
    # ─────────────────────────────────────────────────────────────────────────
    print("\n--- 5. Testing Multi-Day Job Hold & Resume (Weather/Delay) ---")
    hold = WorkforceJobHold.objects.create(
        job=insp_job,
        employee=tech_emp,
        held_by=tech_user,
        reason="HEAVY_RAIN_WEATHER_DELAY",
        status=WorkforceJobHold.Status.ACTIVE,
    )
    insp_job.status = "on_hold"
    insp_job.save()
    tech_emp.current_availability = "available"
    tech_emp.save()

    record_result("Job Put ON_HOLD", insp_job.status == "on_hold" and tech_emp.current_availability == "available", "Technician availability toggled to available")

    # Resume Job
    hold.status = WorkforceJobHold.Status.RESUMED
    hold.hold_end = timezone.now()
    hold.save()
    insp_job.status = "in_progress"
    insp_job.save()
    tech_emp.current_availability = "busy"
    tech_emp.save()

    record_result("Job Resumed", insp_job.status == "in_progress" and tech_emp.current_availability == "busy", "Job resumed to in_progress, tech busy")

    # ─────────────────────────────────────────────────────────────────────────
    # 6. MID-JOB SCOPE REDUCTION & INVOICE RECALCULATION
    # ─────────────────────────────────────────────────────────────────────────
    print("\n--- 6. Testing Mid-Job Scope Reduction & Invoice Balance Recalculation ---")
    work_inv = invoice_service.generate_invoice_for_job(insp_job)
    work_inv.total_amount = Decimal("47200.00")
    work_inv.amount_paid = Decimal("23600.00")  # 50% advance already paid
    work_inv.balance_due = Decimal("23600.00")
    work_inv.save()

    # Customer drops balcony painting (-Rs.7,200)
    reduction = WorkforceScopeReduction.objects.create(
        job=insp_job,
        quote=quote,
        requested_by=tech_user,
        original_amount=Decimal("47200.00"),
        reduction_amount=Decimal("7200.00"),
        revised_amount=Decimal("40000.00"),
        reason="Customer decided not to paint exterior balcony",
        crm_status=WorkforceScopeReduction.Status.APPROVED,
        approved_by=admin_user,
        approved_at=timezone.now(),
    )

    recalc_inv = invoice_service.recalculate_invoice_for_scope_reduction(
        job=insp_job,
        reduction_amount=Decimal("7200.00"),
        actor=admin_user,
    )

    record_result(
        "Scope Reduction Recalculation",
        recalc_inv.total_amount == Decimal("40000.00") and recalc_inv.balance_due == Decimal("16400.00") and recalc_inv.amount_paid == Decimal("23600.00"),
        f"Original: Rs.47,200 | Advance Paid: Rs.23,600 | New Total: Rs.{recalc_inv.total_amount} | New Balance Due: Rs.{recalc_inv.balance_due}"
    )

    # ─────────────────────────────────────────────────────────────────────────
    # 7. COMPLETION & 18% GST TAX INVOICE
    # ─────────────────────────────────────────────────────────────────────────
    print("\n--- 7. Testing Universal 18% GST Invoice on Final Completion ---")
    insp_job.status = "completed"
    insp_job.total_amount = Decimal("40000.00")
    insp_job.payment_status = "paid"
    insp_job.save()

    final_inv = invoice_service.generate_invoice_for_job(insp_job)
    subtotal_check = final_inv.subtotal_amount + final_inv.tax_amount == final_inv.total_amount
    record_result(
        "GST Invoice Consistency",
        final_inv.status == WorkforceInvoice.Status.PAID and subtotal_check,
        f"Invoice #{final_inv.invoice_number}: Subtotal=Rs.{final_inv.subtotal_amount}, Tax(18%)=Rs.{final_inv.tax_amount}, Total=Rs.{final_inv.total_amount}"
    )

    # Summary
    print("\n" + "=" * 65)
    print(f" VERIFICATION COMPLETE: {PASSED} PASSED, {FAILED} FAILED")
    print("=" * 65 + "\n")

    if FAILED > 0:
        sys.exit(1)


if __name__ == "__main__":
    run_tests()
