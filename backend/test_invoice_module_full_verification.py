"""
Comprehensive test script to verify that the Invoice Module is fully working across:
1. Quote-to-Invoice generation with multi-day 50% milestone terms
2. Itemized GST breakdowns & line item replication
3. Advance payment recording & idempotency
4. Downward scope reduction invoice recalculation
5. Final balance settlement & status transition (ISSUED -> PARTIALLY_PAID -> PAID)
6. Direct job completion invoice generation (fixed-price jobs)
7. Invoice serialization, view payload & PDF data readiness
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
    WorkforceQuote,
    WorkforceQuoteItem,
    WorkforceInvoice,
    WorkforceInvoiceItem,
    WorkforceInvoicePayment,
    WorkforceScopeReduction,
    JobPayment,
)
from workforce_api.services import invoice_service, quotation_service
from workforce_api.invoice_views import _serialize_invoice

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


def test_invoice_module():
    print("\n" + "=" * 65)
    print(" STARTING INVOICE MODULE FULL VERIFICATION")
    print("=" * 65 + "\n")

    # 1. Setup entities
    admin_user, _ = User.objects.get_or_create(username="inv_test_admin", defaults={"email": "admin@invtest.com", "role": "admin"})
    cust_user, _ = User.objects.get_or_create(username="inv_test_cust", defaults={"email": "cust@invtest.com", "role": "customer"})
    tech_user, _ = User.objects.get_or_create(username="inv_test_tech", defaults={"email": "tech@invtest.com", "role": "employee"})

    company, _ = Company.objects.get_or_create(
        company_name="Apex Contracts Ltd",
        defaults={"slug": "apex-contracts", "business_type": "service_provider", "is_active": True}
    )
    employee, _ = Employee.objects.get_or_create(
        user=tech_user,
        defaults={"company": company, "employee_id": "INV-TECH-001", "is_active": True}
    )

    # 2. Create Service Request & Multi-Item Commercial Quote
    job = ServiceRequest.objects.create(
        customer=cust_user,
        customer_name="Venkatesh Rao",
        phone="9876543210",
        email="venkatesh@example.com",
        address="Flat 402, Green Glen Layout, Bellandur, Bangalore",
        service_category="painting",
        issue_title="Full Apartment Exterior & Interior Painting",
        total_amount=Decimal("0.00"),
        status="in_progress",
        assigned_employee=employee,
        company=company,
        payment_method="CASH",
        preferred_date=timezone.now().date(),
        preferred_time="10:00 AM",
    )

    q_num = f"PQ-INV-{int(timezone.now().timestamp())}"
    quote = WorkforceQuote.objects.create(
        quote_number=q_num,
        quote_version=1,
        job=job,
        technician=employee,
        company=company,
        customer=cust_user,
        title="Full Apartment Painting Quotation",
        service_category="painting",
        service_name="Full Painting",
        subtotal_amount=Decimal("40000.00"),
        tax_amount=Decimal("7200.00"),
        total_amount=Decimal("47200.00"),
        net_payable=Decimal("47200.00"),
        advance_percent=Decimal("50.00"),
        estimated_duration_days=4,
        status=WorkforceQuote.Status.ADMIN_APPROVED,
    )

    # Line Items: Material & Labour with GST
    item1 = WorkforceQuoteItem.objects.create(
        quote=quote,
        section="MATERIAL",
        name="Royal Luxury Emulsion Paint (50 Litres)",
        quantity=Decimal("50.00"),
        unit="litres",
        unit_price=Decimal("500.00"),
        discount_amount=Decimal("0.00"),
        tax_rate=Decimal("18.00"),
        total_amount=Decimal("25000.00"),
        sort_order=1,
    )
    item2 = WorkforceQuoteItem.objects.create(
        quote=quote,
        section="LABOUR",
        name="Surface Preparation, Primer & Double Coat Application",
        quantity=Decimal("1500.00"),
        unit="sqft",
        unit_price=Decimal("10.00"),
        discount_amount=Decimal("0.00"),
        tax_rate=Decimal("18.00"),
        total_amount=Decimal("15000.00"),
        sort_order=2,
    )

    print("--- 1. Testing Quote-to-Invoice Generation ---")
    invoice = invoice_service.generate_invoice_for_quote(quote, actor=admin_user)
    
    record_result(
        "Invoice Creation",
        invoice is not None and invoice.invoice_number.startswith("INV-"),
        f"Invoice #{invoice.invoice_number} created with total Rs.{invoice.total_amount}"
    )
    record_result(
        "50% Advance & Balance Split",
        invoice.advance_amount == Decimal("23600.00") and invoice.balance_amount == Decimal("23600.00"),
        f"Advance: Rs.{invoice.advance_amount}, Balance: Rs.{invoice.balance_amount}"
    )
    record_result(
        "Initial Balance Due",
        invoice.balance_due == Decimal("47200.00") and invoice.status == WorkforceInvoice.Status.ISSUED,
        f"Status={invoice.status}, Balance Due=Rs.{invoice.balance_due}"
    )
    record_result(
        "Line Items Replication",
        invoice.items.count() == 2,
        f"Items copied: {invoice.items.count()} items"
    )

    # Idempotency test: Re-calling generate_invoice_for_quote returns existing invoice
    invoice_retry = invoice_service.generate_invoice_for_quote(quote, actor=admin_user)
    record_result(
        "Invoice Creation Idempotency",
        invoice_retry.id == invoice.id and WorkforceInvoice.objects.filter(quote=quote).count() == 1,
        "Re-generating for same quote safely returns existing invoice without duplicating."
    )

    print("\n--- 2. Testing Advance Payment Recording & Idempotency ---")
    # Pay 50% advance (Rs. 23,600.00)
    inv1, pmt1, created1 = invoice_service.record_invoice_payment(
        invoice,
        amount=Decimal("23600.00"),
        method="ONLINE",
        reference="PAY_REF_ADVANCE_9999",
        notes="Customer paid 50% advance via UPI",
        actor=admin_user,
    )
    invoice.refresh_from_db()

    record_result(
        "50% Advance Payment Receipt",
        pmt1 is not None and created1 and invoice.amount_paid == Decimal("23600.00"),
        f"Amount Paid: Rs.{invoice.amount_paid}, Balance Due: Rs.{invoice.balance_due}"
    )
    record_result(
        "Partially Paid Status",
        invoice.status == WorkforceInvoice.Status.PARTIALLY_PAID and invoice.balance_due == Decimal("23600.00"),
        f"Status transitioned to: {invoice.status}"
    )

    # Replay same payment reference (Idempotency test)
    inv_dup, pmt_duplicate, created_dup = invoice_service.record_invoice_payment(
        invoice,
        amount=Decimal("23600.00"),
        method="ONLINE",
        reference="PAY_REF_ADVANCE_9999",
        actor=admin_user,
    )
    invoice.refresh_from_db()
    record_result(
        "Payment Idempotency",
        not created_dup and pmt_duplicate.id == pmt1.id and invoice.amount_paid == Decimal("23600.00"),
        "Duplicate payment reference gracefully returned without double-crediting balance."
    )

    print("\n--- 3. Testing Mid-Job Scope Reduction Invoice Recalculation ---")
    # Suppose customer removes a room -> reduction of Rs. 7,200.00 (Total becomes Rs. 40,000.00)
    reduction = WorkforceScopeReduction.objects.create(
        job=job,
        quote=quote,
        requested_by=tech_user,
        original_amount=Decimal("47200.00"),
        reduction_amount=Decimal("7200.00"),
        revised_amount=Decimal("40000.00"),
        reason="Client excluded terrace and guest bedroom from painting scope",
        crm_status=WorkforceScopeReduction.Status.APPROVED,
        approved_by=admin_user,
        approved_at=timezone.now(),
    )

    updated_inv = invoice_service.recalculate_invoice_for_scope_reduction(
        job=job,
        reduction_amount=Decimal("7200.00"),
        actor=admin_user,
    )
    updated_inv.refresh_from_db()

    record_result(
        "Scope Reduction Recalculation",
        updated_inv.total_amount == Decimal("40000.00"),
        f"New Invoice Total: Rs.{updated_inv.total_amount} (reduced from Rs.47,200.00)"
    )
    record_result(
        "Balance Due Adjusted Accurately",
        updated_inv.balance_due == Decimal("16400.00") and updated_inv.amount_paid == Decimal("23600.00"),
        f"Advance paid (Rs.23,600) preserved | New Remaining Balance Due: Rs.{updated_inv.balance_due}"
    )

    print("\n--- 4. Testing Final Balance Payment & Full Settlement ---")
    # Pay remaining balance of Rs. 16,400.00
    inv2, pmt2, created2 = invoice_service.record_invoice_payment(
        updated_inv,
        amount=Decimal("16400.00"),
        method="CASH",
        reference="CASH_OTP_SETTLE_1234",
        notes="Cash OTP payment collected by technician upon completion",
        actor=employee.user,
    )
    updated_inv.refresh_from_db()

    record_result(
        "Final Balance Paid",
        pmt2 is not None and created2 and updated_inv.amount_paid == Decimal("40000.00"),
        f"Total Paid: Rs.{updated_inv.amount_paid}, Balance Due: Rs.{updated_inv.balance_due}"
    )
    record_result(
        "Invoice Fully Settled (PAID)",
        updated_inv.status == WorkforceInvoice.Status.PAID and updated_inv.balance_due == Decimal("0.00"),
        f"Invoice #{updated_inv.invoice_number} is now {updated_inv.status}"
    )

    print("\n--- 5. Testing Direct Fixed-Price Job Invoice Generation ---")
    # Standard Plumbing / Electrical direct job
    direct_job = ServiceRequest.objects.create(
        customer=cust_user,
        customer_name="Priya Sharma",
        phone="9876543211",
        email="priya@example.com",
        address="Indiranagar 100ft Road, Bangalore",
        service_category="plumbing",
        issue_title="Tap Replacement & Pipe Leak Fix",
        total_amount=Decimal("1180.00"),
        status="completed",
        assigned_employee=employee,
        company=company,
        payment_method="ONLINE",
        preferred_date=timezone.now().date(),
        preferred_time="11:00 AM",
    )

    direct_inv = invoice_service.generate_invoice_for_job(direct_job, actor=admin_user)
    record_result(
        "Direct Job Invoice Creation",
        direct_inv is not None and direct_inv.total_amount == Decimal("1180.00"),
        f"Invoice #{direct_inv.invoice_number} generated for direct job with total Rs.{direct_inv.total_amount}"
    )
    record_result(
        "Direct Job 18% GST Itemization",
        direct_inv.subtotal_amount == Decimal("1000.00") and direct_inv.tax_amount == Decimal("180.00"),
        f"Subtotal: Rs.{direct_inv.subtotal_amount}, GST(18%): Rs.{direct_inv.tax_amount}"
    )

    print("\n--- 6. Testing Invoice Serialization & UI API Payload ---")
    serialized = _serialize_invoice(updated_inv, full=True)
    
    record_result(
        "Serialized Invoice Fields",
        all(k in serialized for k in ["invoice_number", "total_amount", "amount_paid", "balance_due", "status", "payments", "items"]),
        f"Invoice #{serialized['invoice_number']} serialized with {len(serialized['payments'])} payments and {len(serialized['items'])} line items"
    )
    record_result(
        "Customer Bill-To Attribution",
        serialized.get("bill_to_name") == "Venkatesh Rao" and serialized.get("service_category") == "painting",
        f"Bill To: {serialized.get('bill_to_name')} | Service: {serialized.get('service_category')}"
    )

    print("\n" + "=" * 65)
    print(f" VERIFICATION COMPLETE: {PASSED} PASSED, {FAILED} FAILED")
    print("=" * 65 + "\n")

    return FAILED == 0


if __name__ == "__main__":
    success = test_invoice_module()
    sys.exit(0 if success else 1)
