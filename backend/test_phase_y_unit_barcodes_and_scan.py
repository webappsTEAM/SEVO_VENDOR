"""
test_phase_y_unit_barcodes_and_scan.py

Comprehensive End-to-End Test Suite for Phase Y:
Unique per-unit barcode generation + physical scan-in verification (sevo-vendor).

Test Coverage:
1. Unit Barcode Generation: Accepting an inbound request for N units generates N unique WarehouseInboundUnit records immediately.
2. Printable Labels PDF: Download endpoint generates a vector Code128 PDF label sheet.
3. Unit Barcode Query: Units list endpoint returns serialized unit details and pending scan statuses.
4. Scan-In Progression: Sequential barcode scanning updates unit status to RECEIVED and calculates live progress.
5. Duplicate Scan Rejection: Re-scanning an already-received barcode is rejected with DUPLICATE_SCAN.
6. Wrong-Request Barcode Rejection: Scanning a unit barcode generated for a different request is rejected with WRONG_REQUEST_BARCODE.
7. Invalid Barcode Rejection: Scanning an arbitrary non-existent barcode is rejected with INVALID_BARCODE.
8. Completion Trigger: Product batch / SellerInventory is ONLY credited and goes live when all N units are confirmed received (not at N-1).
9. Self-Cleaning: Completely purges all test fixtures upon completion.
"""
import os
import sys
import django
from decimal import Decimal

# Setup django environment
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "workforce_core.settings")
django.setup()

from django.test import TestCase
from rest_framework.test import APIRequestFactory, force_authenticate
from rest_framework import status

from accounts.models import User
from companies.models import Company
from workforce_api.models import (
    Warehouse,
    WarehouseStaff,
    SellerHubCategory,
    SellerProduct,
    SellerInventory,
    SellerInventoryMovement,
    SellerWarehouseAssignment,
    WarehouseInboundRequest,
    WarehouseInboundRequestAuditLog,
    WarehouseInboundUnit,
)
from workforce_api.views_seller_hub import (
    SellerInboundRequestListCreateView,
)
from workforce_api.views_warehouse_portal import (
    WarehousePortalInboundRequestDecisionView,
    WarehousePortalInboundRequestScanUnitView,
    WarehousePortalInboundRequestLabelsPdfView,
    WarehousePortalInboundRequestUnitsListView,
)


class PhaseYWarehouseInboundScanTestCase(TestCase):
    """
    Self-cleaning integration test suite for Phase Y per-unit barcode generation & scan-in.
    """

    @classmethod
    def _clean_test_fixtures(cls):
        """Purges any test entities with phasey- or PHASEY- prefixes."""
        from django.db import connection
        with connection.cursor() as cursor:
            cursor.execute("DELETE FROM workforce_warehouse_inbound_unit WHERE barcode LIKE 'SEVO-INB-%' AND inbound_request_id IN (SELECT id FROM workforce_warehouse_inbound_request WHERE product_id IN (SELECT id FROM workforce_seller_product WHERE sku LIKE 'PHASEY-%'));")
            cursor.execute("DELETE FROM workforce_warehouse_inbound_request_audit_log WHERE inbound_request_id IN (SELECT id FROM workforce_warehouse_inbound_request WHERE product_id IN (SELECT id FROM workforce_seller_product WHERE sku LIKE 'PHASEY-%'));")
            cursor.execute("DELETE FROM workforce_warehouse_inbound_request WHERE product_id IN (SELECT id FROM workforce_seller_product WHERE sku LIKE 'PHASEY-%');")
            cursor.execute("DELETE FROM workforce_seller_inventory_movement WHERE inventory_id IN (SELECT id FROM workforce_seller_inventory WHERE product_id IN (SELECT id FROM workforce_seller_product WHERE sku LIKE 'PHASEY-%'));")
            cursor.execute("DELETE FROM workforce_seller_inventory WHERE product_id IN (SELECT id FROM workforce_seller_product WHERE sku LIKE 'PHASEY-%');")
            cursor.execute("DELETE FROM workforce_seller_product WHERE sku LIKE 'PHASEY-%';")
            cursor.execute("DELETE FROM workforce_warehouse_staff WHERE user_id IN (SELECT id FROM accounts_user WHERE username LIKE 'phasey_%');")
            cursor.execute("DELETE FROM workforce_seller_warehouse_assignment WHERE company_id IN (SELECT id FROM companies_company WHERE slug LIKE 'phasey-%');")
            cursor.execute("DELETE FROM workforce_warehouse WHERE code LIKE 'WH-PHASEY-%';")
            cursor.execute("DELETE FROM accounts_user WHERE username LIKE 'phasey_%';")
            cursor.execute("DELETE FROM companies_company WHERE slug LIKE 'phasey-%';")

    @classmethod
    def setUpTestData(cls):
        cls._clean_test_fixtures()

        # 1. Categories
        cls.root_cat, _ = SellerHubCategory.objects.get_or_create(
            name="PhaseY Groceries Root",
            slug="phasey-root-cat",
            defaults={"is_active": True, "sort_order": 1},
        )
        cls.category, _ = SellerHubCategory.objects.get_or_create(
            name="PhaseY Rice & Staples",
            slug="phasey-staples",
            parent=cls.root_cat,
            defaults={"is_active": True, "sort_order": 1},
        )

        # 2. Seller Company & User
        cls.seller_company, _ = Company.objects.get_or_create(
            slug="phasey-merchant-comp",
            defaults={
                "company_name": "PhaseY Organic Farm Supplies",
                "business_type": "grocery_supplier",
            },
        )
        cls.seller_user, _ = User.objects.get_or_create(
            username="phasey_seller_user",
            defaults={
                "email": "seller.phasey@example.com",
                "first_name": "PhaseY",
                "last_name": "Seller",
                "company": cls.seller_company,
            },
        )
        cls.seller_user.company = cls.seller_company
        cls.seller_user.save()

        # 3. Warehouse & Warehouse Staff
        cls.warehouse, _ = Warehouse.objects.get_or_create(
            code="WH-PHASEY-BLR",
            defaults={
                "name": "PhaseY Whitefield Central Fulfillment Hub",
                "address": "ITPB Campus Road, Whitefield, Bangalore",
                "latitude": Decimal("12.9698000"),
                "longitude": Decimal("77.7499000"),
                "city": "Bangalore",
                "region": "Karnataka",
                "is_active": True,
            },
        )
        cls.wh_user, _ = User.objects.get_or_create(
            username="phasey_wh_staff",
            defaults={
                "email": "whstaff.phasey@example.com",
                "first_name": "PhaseY",
                "last_name": "Operator",
            },
        )
        cls.wh_staff, _ = WarehouseStaff.objects.get_or_create(
            user=cls.wh_user,
            defaults={
                "warehouse": cls.warehouse,
                "role": "supervisor",
                "is_primary": True,
            },
        )

        # 4. Phase T Assignment
        cls.assignment, _ = SellerWarehouseAssignment.objects.get_or_create(
            company=cls.seller_company,
            warehouse=cls.warehouse,
            defaults={
                "assigned_by": cls.wh_user,
                "notes": "PhaseY initial test warehouse assignment",
            },
        )

        # 5. FBS Seller Product
        cls.product, _ = SellerProduct.objects.get_or_create(
            sku="PHASEY-RICE-001",
            defaults={
                "company": cls.seller_company,
                "created_by": cls.seller_user,
                "category": cls.category,
                "title": "PhaseY Premium Basmati Rice 5kg",
                "barcode": "8901234567890",
                "fulfillment_method": SellerProduct.FulfillmentMethod.FULFILLED_BY_SEVO,
                "unit": "pack",
                "pack_size": "5kg",
                "mrp": Decimal("500.00"),
                "selling_price": Decimal("450.00"),
                "status": SellerProduct.Status.APPROVED,
            },
        )

    @classmethod
    def tearDownClass(cls):
        cls._clean_test_fixtures()
        super().tearDownClass()

    def setUp(self):
        self.factory = APIRequestFactory()

    def tearDown(self):
        # Clean request fixtures between tests
        WarehouseInboundUnit.objects.filter(barcode__startswith="SEVO-INB-").delete()
        WarehouseInboundRequestAuditLog.objects.filter(inbound_request__product__sku__startswith="PHASEY-").delete()
        WarehouseInboundRequest.objects.filter(product__sku__startswith="PHASEY-").delete()
        SellerInventoryMovement.objects.filter(inventory__product__sku__startswith="PHASEY-").delete()
        SellerInventory.objects.filter(product__sku__startswith="PHASEY-").delete()

    def test_01_accept_inbound_generates_unique_unit_barcodes(self):
        """Accepting an inbound request for 5 units creates exactly 5 unique WarehouseInboundUnit records."""
        # Create Inbound Request for 5 units
        inbound_req = WarehouseInboundRequest.objects.create(
            product=self.product,
            company=self.seller_company,
            warehouse=self.warehouse,
            requested_quantity=5,
            status=WarehouseInboundRequest.Status.PENDING,
            seller_note="Please handle with care",
            requested_by=self.seller_user,
        )

        self.assertEqual(inbound_req.units.count(), 0)

        # Warehouse staff accepts request
        req = self.factory.post(
            f"/api/workforce/warehouse/inbound-requests/{inbound_req.id}/decision/",
            {"action": "ACCEPT", "reviewer_note": "Approved for Bay 3 intake."},
            format="json",
        )
        force_authenticate(req, user=self.wh_user)
        resp = WarehousePortalInboundRequestDecisionView.as_view()(req, pk=inbound_req.id)

        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        inbound_req.refresh_from_db()
        self.assertEqual(inbound_req.status, WarehouseInboundRequest.Status.ACCEPTED)

        # Verify 5 units generated
        units = list(inbound_req.units.all().order_by("unit_number"))
        self.assertEqual(len(units), 5)

        # Verify barcodes are distinct and start with SEVO-INB-
        barcodes = [u.barcode for u in units]
        self.assertEqual(len(set(barcodes)), 5)
        for i, u in enumerate(units, start=1):
            self.assertEqual(u.unit_number, i)
            self.assertTrue(u.barcode.startswith(f"SEVO-INB-{inbound_req.id:04d}-{i:03d}-"))
            self.assertEqual(u.status, WarehouseInboundUnit.Status.PENDING_SCAN)
            self.assertIsNone(u.scanned_at)

    def test_02_printable_label_sheet_pdf(self):
        """Warehouse staff can download a scannable Code128 vector label sheet PDF."""
        inbound_req = WarehouseInboundRequest.objects.create(
            product=self.product,
            company=self.seller_company,
            warehouse=self.warehouse,
            requested_quantity=3,
            status=WarehouseInboundRequest.Status.PENDING,
            requested_by=self.seller_user,
        )

        # Accept to generate units
        req_dec = self.factory.post(
            f"/api/workforce/warehouse/inbound-requests/{inbound_req.id}/decision/",
            {"action": "ACCEPT"},
            format="json",
        )
        force_authenticate(req_dec, user=self.wh_user)
        WarehousePortalInboundRequestDecisionView.as_view()(req_dec, pk=inbound_req.id)

        # Request PDF labels
        req_pdf = self.factory.get(f"/api/workforce/warehouse/inbound-requests/{inbound_req.id}/labels-pdf/")
        force_authenticate(req_pdf, user=self.wh_user)
        resp_pdf = WarehousePortalInboundRequestLabelsPdfView.as_view()(req_pdf, pk=inbound_req.id)

        self.assertEqual(resp_pdf.status_code, status.HTTP_200_OK)
        self.assertEqual(resp_pdf["Content-Type"], "application/pdf")
        # PDF signature check
        self.assertTrue(resp_pdf.content.startswith(b"%PDF"))

    def test_03_units_list_endpoint(self):
        """Warehouse staff can query unit list and scan statuses."""
        inbound_req = WarehouseInboundRequest.objects.create(
            product=self.product,
            company=self.seller_company,
            warehouse=self.warehouse,
            requested_quantity=4,
            status=WarehouseInboundRequest.Status.PENDING,
            requested_by=self.seller_user,
        )

        # Accept
        req_dec = self.factory.post(
            f"/api/workforce/warehouse/inbound-requests/{inbound_req.id}/decision/",
            {"action": "ACCEPT"},
            format="json",
        )
        force_authenticate(req_dec, user=self.wh_user)
        WarehousePortalInboundRequestDecisionView.as_view()(req_dec, pk=inbound_req.id)

        # Query units
        req_units = self.factory.get(f"/api/workforce/warehouse/inbound-requests/{inbound_req.id}/units/")
        force_authenticate(req_units, user=self.wh_user)
        resp_units = WarehousePortalInboundRequestUnitsListView.as_view()(req_units, pk=inbound_req.id)

        self.assertEqual(resp_units.status_code, status.HTTP_200_OK)
        self.assertEqual(len(resp_units.data.get("units", [])), 4)

    def test_04_scan_in_full_workflow_and_validations(self):
        """
        Complete E2E Scan Verification:
        - Scans units 1-4: progress updates correctly, stock NOT live.
        - Duplicate scan rejected with DUPLICATE_SCAN.
        - Wrong-request barcode rejected with WRONG_REQUEST_BARCODE.
        - Invalid barcode rejected with INVALID_BARCODE.
        - Unit 5 scan: completion trigger fires, SellerInventory credited, status flipped to COMPLETED.
        """
        # Create Request 1 (5 units)
        inbound_req_1 = WarehouseInboundRequest.objects.create(
            product=self.product,
            company=self.seller_company,
            warehouse=self.warehouse,
            requested_quantity=5,
            status=WarehouseInboundRequest.Status.PENDING,
            requested_by=self.seller_user,
        )
        # Create Request 2 (Product 2, 2 units)
        product_2 = SellerProduct.objects.create(
            company=self.seller_company,
            created_by=self.seller_user,
            category=self.category,
            title="PhaseY Sunflower Oil 1L",
            sku="PHASEY-OIL-002",
            fulfillment_method=SellerProduct.FulfillmentMethod.FULFILLED_BY_SEVO,
            mrp=Decimal("180.00"),
            selling_price=Decimal("160.00"),
            status=SellerProduct.Status.APPROVED,
        )
        inbound_req_2 = WarehouseInboundRequest.objects.create(
            product=product_2,
            company=self.seller_company,
            warehouse=self.warehouse,
            requested_quantity=2,
            status=WarehouseInboundRequest.Status.PENDING,
            requested_by=self.seller_user,
        )

        # Accept both requests to generate barcodes
        for inb in [inbound_req_1, inbound_req_2]:
            req = self.factory.post(
                f"/api/workforce/warehouse/inbound-requests/{inb.id}/decision/",
                {"action": "ACCEPT"},
                format="json",
            )
            force_authenticate(req, user=self.wh_user)
            WarehousePortalInboundRequestDecisionView.as_view()(req, pk=inb.id)

        units_1 = list(inbound_req_1.units.all().order_by("unit_number"))
        units_2 = list(inbound_req_2.units.all().order_by("unit_number"))
        self.assertEqual(len(units_1), 5)
        self.assertEqual(len(units_2), 2)

        # 1. Scan Unit 1
        req_scan1 = self.factory.post(
            f"/api/workforce/warehouse/inbound-requests/{inbound_req_1.id}/scan-unit/",
            {"barcode": units_1[0].barcode},
            format="json",
        )
        force_authenticate(req_scan1, user=self.wh_user)
        resp_scan1 = WarehousePortalInboundRequestScanUnitView.as_view()(req_scan1, pk=inbound_req_1.id)

        self.assertEqual(resp_scan1.status_code, status.HTTP_200_OK)
        self.assertEqual(resp_scan1.data.get("received_units_count"), 1)
        self.assertEqual(resp_scan1.data.get("total_units_count"), 5)
        self.assertFalse(resp_scan1.data.get("is_complete"))

        # Confirm unit 1 in DB
        units_1[0].refresh_from_db()
        self.assertEqual(units_1[0].status, WarehouseInboundUnit.Status.RECEIVED)
        self.assertEqual(units_1[0].scanned_by, self.wh_user)
        self.assertIsNotNone(units_1[0].scanned_at)

        # Confirm inventory is NOT live yet (0 on hand)
        inv = SellerInventory.objects.filter(product=self.product).first()
        on_hand = inv.on_hand_qty if inv else Decimal("0.000")
        self.assertEqual(on_hand, Decimal("0.000"))

        # 2. Duplicate Scan Rejection (Scan Unit 1 again)
        req_dup = self.factory.post(
            f"/api/workforce/warehouse/inbound-requests/{inbound_req_1.id}/scan-unit/",
            {"barcode": units_1[0].barcode},
            format="json",
        )
        force_authenticate(req_dup, user=self.wh_user)
        resp_dup = WarehousePortalInboundRequestScanUnitView.as_view()(req_dup, pk=inbound_req_1.id)

        self.assertEqual(resp_dup.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(resp_dup.data.get("code"), "DUPLICATE_SCAN")

        # 3. Wrong Request Barcode Rejection (Scan Unit from Request 2 into Request 1)
        req_wrong = self.factory.post(
            f"/api/workforce/warehouse/inbound-requests/{inbound_req_1.id}/scan-unit/",
            {"barcode": units_2[0].barcode},
            format="json",
        )
        force_authenticate(req_wrong, user=self.wh_user)
        resp_wrong = WarehousePortalInboundRequestScanUnitView.as_view()(req_wrong, pk=inbound_req_1.id)

        self.assertEqual(resp_wrong.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(resp_wrong.data.get("code"), "WRONG_REQUEST_BARCODE")
        self.assertEqual(resp_wrong.data.get("actual_request_id"), inbound_req_2.id)

        # 4. Invalid Non-Existent Barcode Rejection
        req_invalid = self.factory.post(
            f"/api/workforce/warehouse/inbound-requests/{inbound_req_1.id}/scan-unit/",
            {"barcode": "RANDOM-GARBAGE-BARCODE-999"},
            format="json",
        )
        force_authenticate(req_invalid, user=self.wh_user)
        resp_invalid = WarehousePortalInboundRequestScanUnitView.as_view()(req_invalid, pk=inbound_req_1.id)

        self.assertEqual(resp_invalid.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(resp_invalid.data.get("code"), "INVALID_BARCODE")

        # 5. Scan Units 2, 3, 4 (Progress to 4/5)
        for i in range(1, 4):
            req_scan = self.factory.post(
                f"/api/workforce/warehouse/inbound-requests/{inbound_req_1.id}/scan-unit/",
                {"barcode": units_1[i].barcode},
                format="json",
            )
            force_authenticate(req_scan, user=self.wh_user)
            resp_scan = WarehousePortalInboundRequestScanUnitView.as_view()(req_scan, pk=inbound_req_1.id)
            self.assertEqual(resp_scan.status_code, status.HTTP_200_OK)
            self.assertEqual(resp_scan.data.get("received_units_count"), i + 1)
            self.assertFalse(resp_scan.data.get("is_complete"))

        # At 4 of 5 scanned: verify request is still ACCEPTED and inventory still 0
        inbound_req_1.refresh_from_db()
        self.assertEqual(inbound_req_1.status, WarehouseInboundRequest.Status.ACCEPTED)
        inv = SellerInventory.objects.filter(product=self.product).first()
        on_hand = inv.on_hand_qty if inv else Decimal("0.000")
        self.assertEqual(on_hand, Decimal("0.000"))

        # 6. Scan 5th and Final Unit (Completion Trigger)
        req_scan5 = self.factory.post(
            f"/api/workforce/warehouse/inbound-requests/{inbound_req_1.id}/scan-unit/",
            {"barcode": units_1[4].barcode},
            format="json",
        )
        force_authenticate(req_scan5, user=self.wh_user)
        resp_scan5 = WarehousePortalInboundRequestScanUnitView.as_view()(req_scan5, pk=inbound_req_1.id)

        self.assertEqual(resp_scan5.status_code, status.HTTP_200_OK)
        self.assertEqual(resp_scan5.data.get("received_units_count"), 5)
        self.assertEqual(resp_scan5.data.get("total_units_count"), 5)
        self.assertTrue(resp_scan5.data.get("is_complete"))
        self.assertEqual(resp_scan5.data.get("request_status"), WarehouseInboundRequest.Status.COMPLETED)

        # Verify DB state:
        inbound_req_1.refresh_from_db()
        self.assertEqual(inbound_req_1.status, WarehouseInboundRequest.Status.COMPLETED)

        # Verify SellerInventory is now credited with exactly 5.000 on hand units
        inv = SellerInventory.objects.get(product=self.product)
        self.assertEqual(inv.on_hand_qty, Decimal("5.000"))
        self.assertEqual(inv.available_qty, Decimal("5.000"))
        self.assertEqual(inv.stock_status, SellerInventory.StockStatus.LOW_STOCK)

        # Verify SellerInventoryMovement recorded
        movements = SellerInventoryMovement.objects.filter(inventory=inv)
        self.assertEqual(movements.count(), 1)
        m = movements.first()
        self.assertEqual(m.movement_type, SellerInventoryMovement.MovementType.STOCK_IN)
        self.assertEqual(m.quantity_change, Decimal("5.000"))
        self.assertEqual(m.balance_after, Decimal("5.000"))

        # Verify Audit Log recorded
        logs = WarehouseInboundRequestAuditLog.objects.filter(inbound_request=inbound_req_1, action="RECEIVE_COMPLETE")
        self.assertEqual(logs.count(), 1)

    def test_05_unapproved_product_blocked_from_inbound_and_scan_gates(self):
        """
        Admin Approval vs Physical Stock Independence Gate Verification:
        1. Products with status != APPROVED (e.g. DRAFT, SUBMITTED, UNDER_REVIEW) cannot submit FBS inbound requests (HTTP 400 PRODUCT_NOT_APPROVED).
        2. Warehouse staff cannot ACCEPT an inbound request for an unapproved product (HTTP 400 PRODUCT_NOT_APPROVED).
        3. Scanning physical units never modifies or bypasses SellerProduct.status.
        """
        # Create an unapproved (DRAFT) FBS product
        draft_product = SellerProduct.objects.create(
            company=self.seller_company,
            created_by=self.seller_user,
            category=self.category,
            title="PhaseY Unapproved Spices 100g",
            sku="PHASEY-UNAPPROVED-003",
            fulfillment_method=SellerProduct.FulfillmentMethod.FULFILLED_BY_SEVO,
            mrp=Decimal("90.00"),
            selling_price=Decimal("80.00"),
            status=SellerProduct.Status.DRAFT,
        )

        # 1. Attempt to submit an inbound storage request for the unapproved product -> MUST BE BLOCKED
        req_submit = self.factory.post(
            "/api/workforce/seller/inbound-requests/",
            {
                "product_id": draft_product.id,
                "requested_quantity": 10,
                "seller_note": "Trying to stock unapproved item",
            },
            format="json",
        )
        force_authenticate(req_submit, user=self.seller_user)
        resp_submit = SellerInboundRequestListCreateView.as_view()(req_submit)

        self.assertEqual(resp_submit.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(resp_submit.data.get("code"), "PRODUCT_NOT_APPROVED")
        self.assertIn("admin-approved", resp_submit.data.get("error", ""))

        # 2. Defense-in-depth test: If a request somehow existed in PENDING for an unapproved product, warehouse cannot ACCEPT it
        legacy_unapproved_req = WarehouseInboundRequest.objects.create(
            product=draft_product,
            company=self.seller_company,
            warehouse=self.warehouse,
            requested_quantity=5,
            status=WarehouseInboundRequest.Status.PENDING,
            requested_by=self.seller_user,
        )

        req_accept = self.factory.post(
            f"/api/workforce/warehouse/inbound-requests/{legacy_unapproved_req.id}/decision/",
            {"action": "ACCEPT"},
            format="json",
        )
        force_authenticate(req_accept, user=self.wh_user)
        resp_accept = WarehousePortalInboundRequestDecisionView.as_view()(req_accept, pk=legacy_unapproved_req.id)

        self.assertEqual(resp_accept.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(resp_accept.data.get("code"), "PRODUCT_NOT_APPROVED")
        self.assertIn("not admin-approved", resp_accept.data.get("error", ""))

        # Verify request status remained PENDING and no units were generated
        legacy_unapproved_req.refresh_from_db()
        self.assertEqual(legacy_unapproved_req.status, WarehouseInboundRequest.Status.PENDING)
        self.assertEqual(legacy_unapproved_req.units.count(), 0)

        # 3. Verify product status is still strictly DRAFT
        draft_product.refresh_from_db()
        self.assertEqual(draft_product.status, SellerProduct.Status.DRAFT)


if __name__ == "__main__":
    import unittest
    suite = unittest.TestLoader().loadTestsFromTestCase(PhaseYWarehouseInboundScanTestCase)
    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(suite)
    sys.exit(not result.wasSuccessful())
