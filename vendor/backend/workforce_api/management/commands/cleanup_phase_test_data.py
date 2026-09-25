"""
workforce_api/management/commands/cleanup_phase_test_data.py

Django management command to safely inventory and clean up test/demo data
created during development verification (Phases N through U).

Features:
- --dry-run (default): Lists every single record identified for cleanup without deleting.
- --execute: Performs actual cascade deletion in strict foreign-key dependency order.
- Explicitly isolates test records matching known phase test patterns and hex slugs.
- Preserves all real user accounts, real companies (e.g. SEVO Platform, Grocery Test1),
  real products, and manual user orders.
"""

import re
from django.core.management.base import BaseCommand
from django.db import connection, transaction
from django.db.models import Q

from companies.models import Company
from accounts.models import User
from employees.models import Employee
from service_requests.models import ServiceRequest
from workforce_api.models import (
    Warehouse,
    SellerWarehouseAssignment,
    SellerProduct,
    SellerProductImage,
    SellerProductAuditLog,
    SellerInventory,
    SellerInventoryBatch,
    SellerInventoryMovement,
    SellerOrder,
    SellerOrderItem,
    SellerOrderAuditLog,
    SellerOrderStatusOutbox,
    SellerReturn,
    SellerReturnItem,
    SellerReturnAuditLog,
    SellerClaim,
    SellerClaimAuditLog,
    WorkforceJobOffer,
)


class Command(BaseCommand):
    help = "Clean up test/demo fixtures created during Phase N-U verification scripts."

    def add_arguments(self, parser):
        parser.add_argument(
            "--execute",
            action="store_true",
            default=False,
            help="Perform actual deletion. If omitted, runs in safe --dry-run mode.",
        )
        parser.add_argument(
            "--dry-run",
            action="store_true",
            default=True,
            help="Dry run mode (default). Only reports records that would be deleted.",
        )

    def handle(self, *args, **options):
        is_execute = options.get("execute", False)
        is_dry_run = not is_execute

        mode_str = "EXECUTION (PERMANENT DELETION)" if is_execute else "DRY-RUN (REPORT ONLY)"
        self.stdout.write(self.style.WARNING(f"\n{'='*75}\nPHASE TEST DATA CLEANUP: {mode_str}\n{'='*75}"))

        # ── 1. IDENTIFY TEST COMPANIES ───────────────────────────────────────
        test_company_patterns = [
            r"^phaset-",
            r"^company-[ab]-",
            r"^north-farms-",
            r"^south-orchards-",
            r"^seller-[ab]-",
            r"^diag-",
            r"^superstore-",
            r"^supermart-",
            r"^quickmart-",
            r"^fresh-grocery-",
        ]
        test_company_name_patterns = [
            r"Diagnostics Supermarket",
            r"Fresh Grocery Superstore",
            r"Super Mart Q",
            r"QuickMart Grocery",
            r"PhaseT Organic Mart",
            r"PhaseT Metro Supermarket",
            r"Green Valley Organic",
            r"Sunrise Dairy & Veg",
            r"North Farms",
            r"South Orchards",
        ]

        all_companies = Company.objects.all()
        target_companies = []
        ambiguous_companies = []

        for c in all_companies:
            slug = c.slug or ""
            name = c.company_name or ""

            # Check for definite test company
            is_test = False
            for pat in test_company_patterns:
                if re.search(pat, slug, re.I):
                    is_test = True
                    break
            if not is_test:
                for pat in test_company_name_patterns:
                    if re.search(pat, name, re.I):
                        is_test = True
                        break

            if is_test:
                # Exclude real platform companies
                if c.id in [1, 1210, 1808]:
                    ambiguous_companies.append(c)
                else:
                    target_companies.append(c)
            elif re.search(r"test", name, re.I) or re.search(r"test", slug, re.I):
                if c.id != 1210:  # Grocery Test1 is user onboarding
                    ambiguous_companies.append(c)

        target_company_ids = [c.id for c in target_companies]

        # ── 2. IDENTIFY TEST WAREHOUSES ───────────────────────────────────────
        target_warehouses = Warehouse.objects.filter(
            Q(code__startswith="WH-E2E-")
            | Q(code__startswith="WH-BLR-")
            | Q(code__startswith="WH-Q-")
            | Q(code__startswith="WH-R-")
            | Q(code__startswith="WH-TEST-")
            | Q(code__startswith="WH-NORTH-")
            | Q(code__startswith="WH-SOUTH-")
            | Q(name__icontains="PhaseT")
            | Q(name__icontains="Hosur Central Hub")
            | Q(name__icontains="E2E Fulfillment Hub")
        )
        target_warehouse_ids = list(target_warehouses.values_list("id", flat=True))

        # ── 3. IDENTIFY SELLER WAREHOUSE ASSIGNMENTS ──────────────────────────
        target_assignments = SellerWarehouseAssignment.objects.filter(
            Q(company_id__in=target_company_ids) | Q(warehouse_id__in=target_warehouse_ids)
        )
        target_assignment_ids = list(target_assignments.values_list("id", flat=True))

        # ── 4. IDENTIFY SELLER PRODUCTS & INVENTORY ───────────────────────────
        target_products = SellerProduct.objects.filter(company_id__in=target_company_ids)
        target_product_ids = list(target_products.values_list("id", flat=True))

        target_inventory = SellerInventory.objects.filter(
            Q(company_id__in=target_company_ids) | Q(product_id__in=target_product_ids)
        )
        target_inventory_ids = list(target_inventory.values_list("id", flat=True))

        target_inv_batches = SellerInventoryBatch.objects.filter(
            inventory_id__in=target_inventory_ids
        )
        target_inv_movements = SellerInventoryMovement.objects.filter(
            inventory_id__in=target_inventory_ids
        )
        target_prod_images = SellerProductImage.objects.filter(product_id__in=target_product_ids)
        target_prod_audits = SellerProductAuditLog.objects.filter(product_id__in=target_product_ids)

        # ── 5. IDENTIFY SELLER ORDERS & ITEMS ─────────────────────────────────
        target_orders = SellerOrder.objects.filter(
            Q(company_id__in=target_company_ids)
            | Q(warehouse_id__in=target_warehouse_ids)
            | Q(order_number__startswith="SO-A-")
            | Q(order_number__startswith="SO-B-")
            | Q(order_number__startswith="SO-PT-")
            | Q(order_number__startswith="SO-WH1-")
            | Q(order_number__startswith="SO-WH2-")
            | Q(order_number__startswith="SO-ORD-")
            | Q(source_order_id__startswith="MKT-AUTO-")
            | Q(source_order_id__startswith="MKT-TEST-")
            | Q(source_order_id__startswith="MKT-PT-")
            | Q(source_order_id__startswith="MKT-ORD-")
        )
        target_order_ids = list(target_orders.values_list("id", flat=True))

        target_order_items = SellerOrderItem.objects.filter(
            Q(order_id__in=target_order_ids) | Q(product_id__in=target_product_ids)
        )
        target_order_audits = SellerOrderAuditLog.objects.filter(order_id__in=target_order_ids)
        target_order_outboxes = SellerOrderStatusOutbox.objects.filter(order_id__in=target_order_ids)

        # ── 6. IDENTIFY DISPATCH SERVICE REQUESTS ─────────────────────────────
        linked_dispatch_job_ids = list(
            target_orders.exclude(dispatch_job_id__isnull=True).values_list("dispatch_job_id", flat=True)
        )
        target_service_requests = ServiceRequest.objects.filter(
            Q(id__in=linked_dispatch_job_ids)
            | Q(company_id__in=target_company_ids)
            | Q(issue_title__startswith="Consolidated Delivery")
        )
        target_sr_ids = list(target_service_requests.values_list("id", flat=True))
        target_job_offers = WorkforceJobOffer.objects.filter(job_id__in=target_sr_ids)

        # ── 7. IDENTIFY RETURNS & CLAIMS ──────────────────────────────────────
        target_returns = SellerReturn.objects.filter(
            Q(company_id__in=target_company_ids) | Q(order_id__in=target_order_ids)
        )
        target_return_ids = list(target_returns.values_list("id", flat=True))
        target_return_items = SellerReturnItem.objects.filter(return_case_id__in=target_return_ids)
        target_return_audits = SellerReturnAuditLog.objects.filter(return_case_id__in=target_return_ids)

        target_claims = SellerClaim.objects.filter(
            Q(company_id__in=target_company_ids) | Q(order_id__in=target_order_ids)
        )
        target_claim_ids = list(target_claims.values_list("id", flat=True))
        target_claim_audits = SellerClaimAuditLog.objects.filter(claim_id__in=target_claim_ids)

        # ── 8. IDENTIFY TEST USERS & EMPLOYEES ────────────────────────────────
        target_users = User.objects.filter(
            Q(company_id__in=target_company_ids)
            | Q(email__startswith="merchant_")
            | Q(email__startswith="rider_")
            | Q(email__startswith="rider2_")
            | Q(email__startswith="admin_q_")
            | Q(email__startswith="tech_cash_")
            | Q(email="tech@invtest.com")
        ).exclude(id__in=[1])  # Never touch superuser/admin 1
        target_user_ids = list(target_users.values_list("id", flat=True))

        target_employees = Employee.objects.filter(
            Q(company_id__in=target_company_ids) | Q(user_id__in=target_user_ids)
        )
        target_employee_ids = list(target_employees.values_list("id", flat=True))

        # ── REPORT SUMMARY ───────────────────────────────────────────────────
        self.stdout.write(self.style.HTTP_INFO("\n1. TARGET COMPANIES FOR REMOVAL:"))
        for c in target_companies:
            self.stdout.write(f"   - Company #{c.id}: '{c.company_name}' (slug: '{c.slug}')")
        self.stdout.write(f"   Total: {len(target_companies)} companies\n")

        self.stdout.write(self.style.HTTP_INFO("2. TARGET WAREHOUSES FOR REMOVAL:"))
        for w in target_warehouses:
            self.stdout.write(f"   - Warehouse #{w.id}: '{w.name}' (code: '{w.code}', city: '{w.city}')")
        self.stdout.write(f"   Total: {target_warehouses.count()} warehouses\n")

        self.stdout.write(self.style.HTTP_INFO("3. TARGET SELLER ORDERS & ITEMS:"))
        self.stdout.write(f"   - Seller Orders: {target_orders.count()} records")
        self.stdout.write(f"   - Seller Order Items: {target_order_items.count()} records")
        self.stdout.write(f"   - Seller Order Audit Logs: {target_order_audits.count()} records")
        self.stdout.write(f"   - Seller Order Outboxes: {target_order_outboxes.count()} records\n")

        self.stdout.write(self.style.HTTP_INFO("4. TARGET DISPATCH JOBS / SERVICE REQUESTS:"))
        for sr in target_service_requests:
            self.stdout.write(f"   - SR #{sr.id}: '{sr.issue_title}' (status: '{sr.status}')")
        self.stdout.write(f"   Total: {target_service_requests.count()} service requests")
        self.stdout.write(f"   - Job Offers: {target_job_offers.count()} records\n")

        self.stdout.write(self.style.HTTP_INFO("5. TARGET PRODUCTS & INVENTORY:"))
        self.stdout.write(f"   - Products: {target_products.count()} records")
        self.stdout.write(f"   - Inventory: {target_inventory.count()} records")
        self.stdout.write(f"   - Inventory Batches: {target_inv_batches.count()} records")
        self.stdout.write(f"   - Inventory Movements: {target_inv_movements.count()} records")
        self.stdout.write(f"   - Product Images: {target_prod_images.count()} records")
        self.stdout.write(f"   - Product Audits: {target_prod_audits.count()} records\n")

        self.stdout.write(self.style.HTTP_INFO("6. TARGET RETURNS & CLAIMS:"))
        self.stdout.write(f"   - Returns: {target_returns.count()} records")
        self.stdout.write(f"   - Return Items: {target_return_items.count()} records")
        self.stdout.write(f"   - Return Audits: {target_return_audits.count()} records")
        self.stdout.write(f"   - Claims: {target_claims.count()} records")
        self.stdout.write(f"   - Claim Audits: {target_claim_audits.count()} records\n")

        self.stdout.write(self.style.HTTP_INFO("7. TARGET USERS & EMPLOYEES:"))
        self.stdout.write(f"   - Test Users: {target_users.count()} accounts")
        self.stdout.write(f"   - Test Employees: {target_employees.count()} profiles\n")

        if ambiguous_companies:
            self.stdout.write(self.style.WARNING("\n[!] PRESERVED / AMBIGUOUS COMPANIES (NOT MARKED FOR DELETION):"))
            for ac in ambiguous_companies:
                self.stdout.write(f"   - Company #{ac.id}: '{ac.company_name}' (slug: '{ac.slug}')")

        # ── EXECUTION PHASE ──────────────────────────────────────────────────
        if is_execute:
            self.stdout.write(self.style.WARNING("\n[!] Starting atomic database deletion..."))
            with transaction.atomic():
                with connection.cursor() as cur:
                    # 1. Orders & Associated Child Records
                    if target_order_ids:
                        cur.execute("DELETE FROM workforce_seller_order_audit_log WHERE order_id = ANY(%s);", [target_order_ids])
                        cur.execute("DELETE FROM workforce_seller_order_status_outbox WHERE order_id = ANY(%s);", [target_order_ids])
                        cur.execute("DELETE FROM workforce_seller_order_item WHERE order_id = ANY(%s);", [target_order_ids])

                    if target_return_ids:
                        cur.execute("DELETE FROM workforce_seller_return_audit_log WHERE return_case_id = ANY(%s);", [target_return_ids])
                        cur.execute("DELETE FROM workforce_seller_return_item WHERE return_case_id = ANY(%s);", [target_return_ids])
                        cur.execute("DELETE FROM workforce_seller_return WHERE id = ANY(%s);", [target_return_ids])

                    if target_claim_ids:
                        cur.execute("DELETE FROM workforce_seller_claim_audit_log WHERE claim_id = ANY(%s);", [target_claim_ids])
                        cur.execute("DELETE FROM workforce_seller_claim WHERE id = ANY(%s);", [target_claim_ids])

                    if target_order_ids:
                        cur.execute("DELETE FROM workforce_seller_order WHERE id = ANY(%s);", [target_order_ids])

                    # 2. Service Requests & Child Operations
                    if target_sr_ids:
                        cur.execute("DELETE FROM workforce_job_offer WHERE job_id = ANY(%s);", [target_sr_ids])
                        cur.execute("DELETE FROM workforce_dispatch_state WHERE job_id = ANY(%s);", [target_sr_ids])
                        cur.execute("DELETE FROM workforce_job_location_point WHERE job_id = ANY(%s);", [target_sr_ids])
                        cur.execute("DELETE FROM workforce_job_tracking_session WHERE job_id = ANY(%s);", [target_sr_ids])
                        cur.execute("DELETE FROM workforce_job_lifecycle_event WHERE job_id = ANY(%s);", [target_sr_ids])
                        cur.execute("DELETE FROM customer_analytics_bookingstatusevent WHERE service_request_id = ANY(%s);", [target_sr_ids])
                        cur.execute("DELETE FROM orders_orderitem WHERE service_request_id = ANY(%s);", [target_sr_ids])
                        cur.execute("DELETE FROM service_requests_bookingassignment WHERE booking_id = ANY(%s);", [target_sr_ids])
                        cur.execute("DELETE FROM service_requests_customerinspection WHERE service_request_id = ANY(%s);", [target_sr_ids])
                        cur.execute("DELETE FROM service_requests_employeejob WHERE service_request_id = ANY(%s);", [target_sr_ids])
                        cur.execute("DELETE FROM service_requests_estimation WHERE service_request_id = ANY(%s);", [target_sr_ids])
                        cur.execute("DELETE FROM service_requests_servicerequest WHERE id = ANY(%s);", [target_sr_ids])

                    # 3. Inventory & Products
                    if target_inventory_ids:
                        cur.execute("DELETE FROM workforce_seller_inventory_movement WHERE inventory_id = ANY(%s);", [target_inventory_ids])
                        cur.execute("DELETE FROM workforce_seller_inventory_batch WHERE inventory_id = ANY(%s);", [target_inventory_ids])
                        cur.execute("DELETE FROM workforce_seller_inventory WHERE id = ANY(%s);", [target_inventory_ids])

                    if target_product_ids:
                        cur.execute("DELETE FROM workforce_seller_product_image WHERE product_id = ANY(%s);", [target_product_ids])
                        cur.execute("DELETE FROM workforce_seller_product_audit_log WHERE product_id = ANY(%s);", [target_product_ids])
                        cur.execute("DELETE FROM workforce_seller_product WHERE id = ANY(%s);", [target_product_ids])

                    # 4. Warehouses & Assignments
                    if target_company_ids or target_warehouse_ids:
                        cur.execute(
                            "DELETE FROM workforce_seller_warehouse_assignment WHERE company_id = ANY(%s) OR warehouse_id = ANY(%s);",
                            [target_company_ids, target_warehouse_ids],
                        )

                    if target_warehouse_ids:
                        cur.execute("DELETE FROM workforce_warehouse WHERE id = ANY(%s);", [target_warehouse_ids])

                    # 5. Employees
                    if target_employee_ids:
                        cur.execute("DELETE FROM workforce_job_offer WHERE employee_id = ANY(%s);", [target_employee_ids])
                        cur.execute("DELETE FROM workforce_cash_settlement WHERE employee_id = ANY(%s);", [target_employee_ids])
                        cur.execute("DELETE FROM workforce_job_payment WHERE employee_id = ANY(%s) OR cash_collected_by_id = ANY(%s);", [target_employee_ids, target_employee_ids])
                        cur.execute("DELETE FROM workforce_payment_collection_event WHERE employee_id = ANY(%s);", [target_employee_ids])
                        cur.execute("DELETE FROM workforce_work_extension WHERE technician_id = ANY(%s) OR specialist_technician_id = ANY(%s);", [target_employee_ids, target_employee_ids])
                        cur.execute("DELETE FROM workforce_wallet_ledger_entry WHERE worker_performed_id = ANY(%s);", [target_employee_ids])
                        cur.execute("UPDATE workforce_quote SET technician_id = NULL WHERE technician_id = ANY(%s);", [target_employee_ids])
                        cur.execute("UPDATE workforce_invoice SET technician_id = NULL WHERE technician_id = ANY(%s);", [target_employee_ids])
                        cur.execute("UPDATE workforce_seller_order SET handling_technician_id = NULL WHERE handling_technician_id = ANY(%s);", [target_employee_ids])
                        cur.execute("DELETE FROM workforce_job_hold WHERE employee_id = ANY(%s);", [target_employee_ids])
                        cur.execute("DELETE FROM workforce_job_lifecycle_event WHERE employee_id = ANY(%s);", [target_employee_ids])
                        cur.execute("DELETE FROM workforce_job_location_point WHERE employee_id = ANY(%s);", [target_employee_ids])
                        cur.execute("DELETE FROM workforce_job_tracking_session WHERE employee_id = ANY(%s);", [target_employee_ids])
                        cur.execute("DELETE FROM workforce_post_service_proof WHERE employee_id = ANY(%s);", [target_employee_ids])
                        cur.execute("DELETE FROM workforce_pre_service_verification WHERE employee_id = ANY(%s);", [target_employee_ids])
                        cur.execute("DELETE FROM workforce_payslip WHERE employee_id = ANY(%s);", [target_employee_ids])
                        cur.execute("DELETE FROM workforce_employee_schedule WHERE employee_id = ANY(%s);", [target_employee_ids])
                        cur.execute("DELETE FROM workforce_employee_skill WHERE employee_id = ANY(%s);", [target_employee_ids])
                        cur.execute("DELETE FROM workforce_employee_compliance WHERE employee_id = ANY(%s);", [target_employee_ids])
                        cur.execute("DELETE FROM workforce_employee_document WHERE employee_id = ANY(%s);", [target_employee_ids])
                        cur.execute("DELETE FROM workforce_employee_saved_location WHERE employee_id = ANY(%s);", [target_employee_ids])
                        cur.execute("DELETE FROM workforce_employee_service WHERE employee_id = ANY(%s);", [target_employee_ids])
                        cur.execute("DELETE FROM workforce_scorecard WHERE employee_id = ANY(%s);", [target_employee_ids])
                        cur.execute("DELETE FROM workforce_social_security_registration WHERE employee_id = ANY(%s);", [target_employee_ids])
                        cur.execute("DELETE FROM workforce_vendor_base_location WHERE employee_id = ANY(%s);", [target_employee_ids])
                        cur.execute("DELETE FROM workforce_vendor_technician_relationship WHERE technician_id = ANY(%s);", [target_employee_ids])
                        # Wallet dependencies
                        cur.execute("SELECT id FROM workforce_wallet_account WHERE employee_id = ANY(%s);", [target_employee_ids])
                        emp_wallet_acct_ids = [r[0] for r in cur.fetchall()]
                        if emp_wallet_acct_ids:
                            cur.execute("DELETE FROM workforce_withdrawal_request WHERE wallet_id = ANY(%s);", [emp_wallet_acct_ids])
                            cur.execute("DELETE FROM workforce_wallet_ledger_entry WHERE wallet_id = ANY(%s);", [emp_wallet_acct_ids])
                        cur.execute("DELETE FROM workforce_wallet_account WHERE employee_id = ANY(%s);", [target_employee_ids])

                        cur.execute("SELECT id FROM employee_wallet WHERE employee_id = ANY(%s);", [target_employee_ids])
                        emp_wallet_ids = [r[0] for r in cur.fetchall()]
                        if emp_wallet_ids:
                            cur.execute("DELETE FROM employee_wallet_transaction WHERE wallet_id = ANY(%s);", [emp_wallet_ids])
                            cur.execute("DELETE FROM employee_wallet_withdrawal WHERE wallet_id = ANY(%s);", [emp_wallet_ids])
                        cur.execute("DELETE FROM employee_wallet_withdrawal WHERE employee_id = ANY(%s);", [target_employee_ids])
                        cur.execute("DELETE FROM employee_wallet WHERE employee_id = ANY(%s);", [target_employee_ids])
                        cur.execute("DELETE FROM service_requests_refundrequest WHERE assigned_employee_id = ANY(%s);", [target_employee_ids])
                        cur.execute("DELETE FROM service_requests_employeejob WHERE employee_id = ANY(%s);", [target_employee_ids])
                        cur.execute("DELETE FROM time_tracking_timelog WHERE employee_id = ANY(%s);", [target_employee_ids])
                        cur.execute("DELETE FROM time_tracking_employeelocation WHERE employee_id = ANY(%s);", [target_employee_ids])
                        cur.execute("DELETE FROM live_locations_employeelocation WHERE employee_id = ANY(%s);", [target_employee_ids])
                        cur.execute("DELETE FROM leaves_leaverequest WHERE employee_id = ANY(%s);", [target_employee_ids])
                        cur.execute("DELETE FROM employees_presencelog WHERE employee_id = ANY(%s);", [target_employee_ids])
                        cur.execute("DELETE FROM employee_payout_account WHERE employee_id = ANY(%s);", [target_employee_ids])
                        cur.execute("DELETE FROM employee_commission_config WHERE employee_id = ANY(%s);", [target_employee_ids])
                        cur.execute("DELETE FROM compliance_auditlog WHERE employee_id = ANY(%s);", [target_employee_ids])
                        cur.execute("DELETE FROM scheduling_shift WHERE employee_id = ANY(%s);", [target_employee_ids])
                        cur.execute("DELETE FROM payroll_payrollgeneration WHERE employee_id = ANY(%s);", [target_employee_ids])
                        cur.execute("DELETE FROM employees_employee WHERE id = ANY(%s);", [target_employee_ids])

                    # 6. Users
                    if target_user_ids:
                        cur.execute("DELETE FROM workforce_notification WHERE recipient_id = ANY(%s);", [target_user_ids])
                        cur.execute("DELETE FROM workforce_scope_reduction WHERE requested_by_id = ANY(%s) OR approved_by_id = ANY(%s);", [target_user_ids, target_user_ids])
                        cur.execute("DELETE FROM workforce_cash_settlement WHERE recorded_by_id = ANY(%s);", [target_user_ids])
                        cur.execute("DELETE FROM workforce_job_hold WHERE held_by_id = ANY(%s);", [target_user_ids])
                        cur.execute("DELETE FROM workforce_invoice_payment WHERE recorded_by_id = ANY(%s);", [target_user_ids])
                        cur.execute("DELETE FROM workforce_seller_catalog_upload_batch WHERE uploaded_by_id = ANY(%s);", [target_user_ids])
                        cur.execute("DELETE FROM workforce_vendor_relieving_request WHERE sevo_approved_by_id = ANY(%s) OR vendor_approved_by_id = ANY(%s);", [target_user_ids, target_user_ids])
                        cur.execute("DELETE FROM workforce_vendor_technician_relationship WHERE created_by_id = ANY(%s);", [target_user_ids])
                        cur.execute("DELETE FROM workforce_provider_join_request WHERE decided_by_id = ANY(%s);", [target_user_ids])
                        cur.execute("DELETE FROM token_blacklist_outstandingtoken WHERE user_id = ANY(%s);", [target_user_ids])
                        cur.execute("DELETE FROM ai_assistant_conversation WHERE user_id = ANY(%s);", [target_user_ids])
                        cur.execute("DELETE FROM accounts_user WHERE id = ANY(%s);", [target_user_ids])

                    # 7. Companies and Company-Level Dependencies
                    if target_company_ids:
                        # Notifications
                        cur.execute("DELETE FROM workforce_notification WHERE company_id = ANY(%s);", [target_company_ids])

                        # Invoices & Invoice Children for target companies
                        cur.execute("SELECT id FROM workforce_invoice WHERE company_id = ANY(%s);", [target_company_ids])
                        comp_inv_ids = [r[0] for r in cur.fetchall()]
                        if comp_inv_ids:
                            cur.execute("DELETE FROM workforce_invoice_item WHERE invoice_id = ANY(%s);", [comp_inv_ids])
                            cur.execute("DELETE FROM workforce_invoice_payment WHERE invoice_id = ANY(%s);", [comp_inv_ids])
                            cur.execute("DELETE FROM workforce_invoice WHERE id = ANY(%s);", [comp_inv_ids])
                        cur.execute("DELETE FROM workforce_supplemental_invoice WHERE company_id = ANY(%s);", [target_company_ids])
                        cur.execute("DELETE FROM workforce_work_extension WHERE company_id = ANY(%s);", [target_company_ids])

                        # Quotes & Quote Children for target companies
                        cur.execute("SELECT id FROM workforce_quote WHERE company_id = ANY(%s);", [target_company_ids])
                        comp_quote_ids = [r[0] for r in cur.fetchall()]
                        if comp_quote_ids:
                            cur.execute("DELETE FROM workforce_scope_reduction WHERE quote_id = ANY(%s);", [comp_quote_ids])
                            cur.execute("DELETE FROM workforce_quote_item WHERE quote_id = ANY(%s);", [comp_quote_ids])
                            cur.execute("DELETE FROM workforce_quote_measurement WHERE quote_id = ANY(%s);", [comp_quote_ids])
                            cur.execute("DELETE FROM workforce_quote_photo WHERE quote_id = ANY(%s);", [comp_quote_ids])
                            cur.execute("DELETE FROM workforce_mason_quote WHERE quote_id = ANY(%s);", [comp_quote_ids])
                            cur.execute("DELETE FROM workforce_painting_quote WHERE quote_id = ANY(%s);", [comp_quote_ids])
                            cur.execute("DELETE FROM workforce_quote WHERE id = ANY(%s);", [comp_quote_ids])

                        # Other company associations
                        cur.execute("DELETE FROM workforce_seller_catalog_upload_batch WHERE company_id = ANY(%s);", [target_company_ids])
                        cur.execute("SELECT id FROM workforce_wallet_account WHERE company_id = ANY(%s);", [target_company_ids])
                        comp_wallet_ids = [r[0] for r in cur.fetchall()]
                        if comp_wallet_ids:
                            cur.execute("DELETE FROM workforce_withdrawal_request WHERE wallet_id = ANY(%s);", [comp_wallet_ids])
                            cur.execute("DELETE FROM workforce_wallet_ledger_entry WHERE wallet_id = ANY(%s);", [comp_wallet_ids])
                            cur.execute("DELETE FROM workforce_wallet_account WHERE id = ANY(%s);", [comp_wallet_ids])
                        cur.execute("DELETE FROM workforce_vendor_store WHERE company_id = ANY(%s);", [target_company_ids])
                        cur.execute("DELETE FROM workforce_vendor_criteria WHERE vendor_id = ANY(%s);", [target_company_ids])
                        cur.execute("DELETE FROM workforce_vendor_deal WHERE company_id = ANY(%s);", [target_company_ids])
                        cur.execute("DELETE FROM workforce_vendor_coupon WHERE company_id = ANY(%s);", [target_company_ids])
                        cur.execute("DELETE FROM workforce_vendor_invitation WHERE vendor_id = ANY(%s);", [target_company_ids])
                        cur.execute("DELETE FROM workforce_vendor_relieving_request WHERE vendor_id = ANY(%s);", [target_company_ids])
                        cur.execute("DELETE FROM workforce_vendor_technician_relationship WHERE vendor_id = ANY(%s);", [target_company_ids])
                        cur.execute("DELETE FROM workforce_provider_join_request WHERE provider_id = ANY(%s);", [target_company_ids])
                        cur.execute("DELETE FROM workforce_skill WHERE company_id = ANY(%s);", [target_company_ids])
                        cur.execute("DELETE FROM workforce_required_document WHERE company_id = ANY(%s);", [target_company_ids])
                        cur.execute("DELETE FROM workforce_pay_period WHERE company_id = ANY(%s);", [target_company_ids])
                        cur.execute("DELETE FROM workforce_vehicle WHERE company_id = ANY(%s);", [target_company_ids])
                        cur.execute("DELETE FROM workforce_vendor_base_location WHERE company_id = ANY(%s);", [target_company_ids])
                        cur.execute("DELETE FROM workforce_commission_rule WHERE company_id = ANY(%s);", [target_company_ids])
                        cur.execute("DELETE FROM workforce_compliance_requirement WHERE company_id = ANY(%s);", [target_company_ids])
                        cur.execute("DELETE FROM workforce_financial_ledger_entry WHERE company_id = ANY(%s);", [target_company_ids])
                        cur.execute("DELETE FROM workforce_inventory_item WHERE company_id = ANY(%s);", [target_company_ids])
                        cur.execute("DELETE FROM workforce_job_lifecycle_event WHERE company_id = ANY(%s);", [target_company_ids])
                        cur.execute("DELETE FROM workforce_job_payment WHERE company_id = ANY(%s);", [target_company_ids])
                        cur.execute("DELETE FROM workforce_job_tracking_session WHERE company_id = ANY(%s);", [target_company_ids])
                        cur.execute("DELETE FROM service_requests_workforcewebhookevent WHERE company_id = ANY(%s);", [target_company_ids])
                        cur.execute("DELETE FROM customer_analytics_customeridentity WHERE company_id = ANY(%s);", [target_company_ids])
                        cur.execute("DELETE FROM customer_analytics_customerloginevent WHERE company_id = ANY(%s);", [target_company_ids])
                        cur.execute("DELETE FROM customer_analytics_bookingstatusevent WHERE company_id = ANY(%s);", [target_company_ids])
                        cur.execute("DELETE FROM customer_users WHERE company_id = ANY(%s);", [target_company_ids])
                        cur.execute("DELETE FROM trial_management_trialplan WHERE company_id = ANY(%s);", [target_company_ids])
                        cur.execute("DELETE FROM mileage_mileagepolicy WHERE company_id = ANY(%s);", [target_company_ids])
                        cur.execute("DELETE FROM companies_company WHERE id = ANY(%s);", [target_company_ids])

            self.stdout.write(self.style.SUCCESS(f"\n[CLEANUP COMPLETE] Successfully deleted test records across all models."))
        else:
            self.stdout.write(self.style.SUCCESS(f"\n[DRY-RUN COMPLETE] No database records were modified or deleted."))
            self.stdout.write(self.style.SUCCESS(f"Pass `--execute` to perform permanent deletion."))

