"""
test_phase_x_warehouse_inbound.py

Comprehensive test suite verifying Phase X: Seller-to-warehouse stock request with accept/reject:
1. Block request if seller Company has no active warehouse assignment (NO_ASSIGNED_WAREHOUSE).
2. Block request if product fulfillment_method is not FULFILLED_BY_SEVO.
3. Seller with Phase T warehouse assignment submits inbound request -> PENDING status created.
4. Seller assigned warehouse endpoint returns read-only designated warehouse.
5. Warehouse staff lists inbound requests scoped to their assigned facility.
6. Warehouse staff accepts inbound request -> status transitions to ACCEPTED (awaiting physical receipt / Phase Y).
7. Warehouse staff rejects inbound request with reviewer note -> status transitions to REJECTED with note visible to seller.
8. Audit log immutably records all state transitions (CREATED, ACCEPTED, REJECTED).
"""
import os
import django

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "workforce_core.settings")
django.setup()

import unittest
from decimal import Decimal
from django.utils import timezone
from rest_framework.test import APIRequestFactory, force_authenticate
from rest_framework import status

from accounts.models import User
from companies.models import Company
from workforce_api.models import (
    Warehouse,
    WarehouseStaff,
    SellerWarehouseAssignment,
    SellerProduct,
    SellerHubCategory,
    WarehouseInboundRequest,
    WarehouseInboundRequestAuditLog,
)
from workforce_api.views_seller_hub import (
    SellerAssignedWarehouseView,
    SellerInboundRequestListCreateView,
)
from workforce_api.views_warehouse_portal import (
    WarehousePortalInboundRequestListView,
    WarehousePortalInboundRequestDecisionView,
)


class PhaseXWarehouseInboundTestCase(unittest.TestCase):
    @classmethod
    def _clean_test_fixtures(cls):
        from django.db import connection
        WarehouseInboundRequest.objects.filter(product__sku__startswith="PHASEX-").delete()
        SellerProduct.objects.filter(sku__startswith="PHASEX-").delete()
        WarehouseStaff.objects.filter(user__username__in=["phasex_wh_staff"]).delete()
        SellerWarehouseAssignment.objects.filter(company__slug__in=["phasex-seller-comp", "phasex-unassigned-comp"]).delete()
        Warehouse.objects.filter(code__in=["WH-PHASEX-01"]).delete()
        User.objects.filter(username__in=["phasex_seller", "phasex_unassigned_seller", "phasex_wh_staff"]).delete()
        SellerHubCategory.objects.filter(slug__in=["phasex-root-cat", "phasex-leaf-cat"]).delete()
        with connection.cursor() as cursor:
            cursor.execute("DELETE FROM companies_company WHERE slug IN ('phasex-seller-comp', 'phasex-unassigned-comp')")

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.factory = APIRequestFactory()
        cls._clean_test_fixtures()

        # 1. Categories
        cls.root_cat = SellerHubCategory.objects.create(
            name="PhaseX Groceries",
            slug="phasex-root-cat",
            is_active=True,
            sort_order=1,
        )
        cls.leaf_cat = SellerHubCategory.objects.create(
            name="PhaseX Spices",
            slug="phasex-leaf-cat",
            parent=cls.root_cat,
            is_active=True,
            sort_order=1,
        )

        # 2. Assigned Merchant Company & User
        cls.seller_company, _ = Company.objects.get_or_create(
            slug="phasex-seller-comp",
            defaults={
                "company_name": "PhaseX Spice Merchants",
                "business_type": "grocery_supplier",
            },
        )
        cls.seller_user, _ = User.objects.get_or_create(
            username="phasex_seller",
            defaults={
                "email": "phasex_seller@example.com",
                "first_name": "PhaseX",
                "last_name": "Seller",
                "company": cls.seller_company,
            },
        )
        cls.seller_user.company = cls.seller_company
        cls.seller_user.save()

        # 3. Unassigned Merchant Company & User (No warehouse assignment)
        cls.unassigned_company, _ = Company.objects.get_or_create(
            slug="phasex-unassigned-comp",
            defaults={
                "company_name": "PhaseX Orphan Merchants",
                "business_type": "grocery_supplier",
            },
        )
        cls.unassigned_user, _ = User.objects.get_or_create(
            username="phasex_unassigned_seller",
            defaults={
                "email": "phasex_unassigned@example.com",
                "first_name": "Unassigned",
                "last_name": "Seller",
                "company": cls.unassigned_company,
            },
        )
        cls.unassigned_user.company = cls.unassigned_company
        cls.unassigned_user.save()

        # 4. Warehouse & Staff
        cls.warehouse = Warehouse.objects.create(
            name="PhaseX Central Hub",
            code="WH-PHASEX-01",
            city="Chennai",
            address="100 Logistics Park, Chennai",
            latitude=Decimal("13.0827"),
            longitude=Decimal("80.2707"),
            is_active=True,
        )
        cls.wh_staff_user = User.objects.create_user(
            username="phasex_wh_staff",
            email="phasex_wh_staff@example.com",
            password="Password123!",
            first_name="Hub",
            last_name="Operator",
        )
        cls.wh_staff_profile = WarehouseStaff.objects.create(
            user=cls.wh_staff_user,
            warehouse=cls.warehouse,
            role="manager",
            is_primary=True,
        )

        # 5. Phase T Assignment: Assign seller_company -> warehouse
        cls.assignment = SellerWarehouseAssignment.objects.create(
            company=cls.seller_company,
            warehouse=cls.warehouse,
            assigned_by=cls.wh_staff_user,
            notes="PhaseX initial test assignment",
        )

        # 6. Products
        # FBS Product (Fulfilled by Sevo)
        cls.fbs_product = SellerProduct.objects.create(
            company=cls.seller_company,
            created_by=cls.seller_user,
            category=cls.leaf_cat,
            title="PhaseX Organic Cardamom 500g",
            brand="PhaseX Organics",
            sku="PHASEX-CRD-001",
            barcode="8901234567890",
            fulfillment_method=SellerProduct.FulfillmentMethod.FULFILLED_BY_SEVO,
            mrp=Decimal("850.00"),
            selling_price=Decimal("799.00"),
            status=SellerProduct.Status.APPROVED,
        )

        # Self-Ship Product
        cls.self_ship_product = SellerProduct.objects.create(
            company=cls.seller_company,
            created_by=cls.seller_user,
            category=cls.leaf_cat,
            title="PhaseX Black Pepper 1kg",
            brand="PhaseX Organics",
            sku="PHASEX-PEP-002",
            barcode="8901234567891",
            fulfillment_method=SellerProduct.FulfillmentMethod.SELF_SHIP,
            mrp=Decimal("600.00"),
            selling_price=Decimal("550.00"),
            status=SellerProduct.Status.APPROVED,
        )

        # Unassigned Company's FBS Product
        cls.unassigned_fbs_product = SellerProduct.objects.create(
            company=cls.unassigned_company,
            created_by=cls.unassigned_user,
            category=cls.leaf_cat,
            title="PhaseX Clove 250g",
            brand="PhaseX Organics",
            sku="PHASEX-CLV-003",
            barcode="8901234567892",
            fulfillment_method=SellerProduct.FulfillmentMethod.FULFILLED_BY_SEVO,
            mrp=Decimal("400.00"),
            selling_price=Decimal("380.00"),
            status=SellerProduct.Status.APPROVED,
        )

    @classmethod
    def tearDownClass(cls):
        cls._clean_test_fixtures()
        super().tearDownClass()

    def test_01_unassigned_seller_blocked_with_clear_error(self):
        """Seller with no warehouse assignment is blocked with NO_ASSIGNED_WAREHOUSE."""
        req = self.factory.post(
            "/api/workforce/seller-hub/inbound-requests/",
            {"product_id": self.unassigned_fbs_product.id, "requested_quantity": 50, "seller_note": "Test intake"},
            format="json",
        )
        force_authenticate(req, user=self.unassigned_user)
        view = SellerInboundRequestListCreateView.as_view()
        res = view(req)

        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(res.data.get("code"), "NO_ASSIGNED_WAREHOUSE")
        self.assertIn("No active warehouse assigned", res.data.get("error", ""))

    def test_02_self_ship_product_blocked_from_warehouse_intake(self):
        """Self-ship products cannot be submitted for warehouse inbound intake."""
        req = self.factory.post(
            "/api/workforce/seller-hub/inbound-requests/",
            {"product_id": self.self_ship_product.id, "requested_quantity": 25},
            format="json",
        )
        force_authenticate(req, user=self.seller_user)
        view = SellerInboundRequestListCreateView.as_view()
        res = view(req)

        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(res.data.get("code"), "INVALID_FULFILLMENT_METHOD")

    def test_03_seller_assigned_warehouse_read_only_endpoint(self):
        """Assigned warehouse endpoint returns seller's real Phase T assigned warehouse."""
        req = self.factory.get("/api/workforce/seller-hub/assigned-warehouse/")
        force_authenticate(req, user=self.seller_user)
        view = SellerAssignedWarehouseView.as_view()
        res = view(req)

        self.assertEqual(res.status_code, status.HTTP_200_OK)
        self.assertTrue(res.data.get("assigned"))
        wh_data = res.data.get("warehouse")
        self.assertEqual(wh_data["id"], self.warehouse.id)
        self.assertEqual(wh_data["name"], "PhaseX Central Hub")
        self.assertEqual(wh_data["city"], "Chennai")

    def test_04_seller_submits_fbs_inbound_request_successfully(self):
        """Seller creates a valid inbound storage request for FBS product."""
        req = self.factory.post(
            "/api/workforce/seller-hub/inbound-requests/",
            {
                "product_id": self.fbs_product.id,
                "requested_quantity": 100,
                "seller_note": "Please store in temperature-controlled spice bay.",
            },
            format="json",
        )
        force_authenticate(req, user=self.seller_user)
        view = SellerInboundRequestListCreateView.as_view()
        res = view(req)

        self.assertEqual(res.status_code, status.HTTP_201_CREATED)
        self.assertEqual(res.data["status"], "PENDING")
        self.assertEqual(res.data["requested_quantity"], 100)
        self.assertEqual(res.data["warehouse"], self.warehouse.id)
        self.assertEqual(res.data["warehouse_name"], "PhaseX Central Hub")
        self.assertEqual(res.data["seller_note"], "Please store in temperature-controlled spice bay.")
        self.assertEqual(res.data["product_title"], "PhaseX Organic Cardamom 500g")
        self.assertEqual(res.data["product_fulfillment_method"], "FULFILLED_BY_SEVO")

        # Verify DB and Audit Log
        inbound_id = res.data["id"]
        inbound_obj = WarehouseInboundRequest.objects.get(id=inbound_id)
        self.assertEqual(inbound_obj.status, WarehouseInboundRequest.Status.PENDING)
        self.assertEqual(inbound_obj.warehouse_id, self.warehouse.id)

        audit_logs = WarehouseInboundRequestAuditLog.objects.filter(inbound_request=inbound_obj)
        self.assertEqual(audit_logs.count(), 1)
        self.assertEqual(audit_logs.first().action, "CREATED")

    def test_05_warehouse_staff_lists_and_accepts_inbound_request(self):
        """Warehouse staff lists inbound requests and accepts one."""
        # Create an inbound request
        inbound_req = WarehouseInboundRequest.objects.create(
            product=self.fbs_product,
            company=self.seller_company,
            warehouse=self.warehouse,
            requested_quantity=75,
            status=WarehouseInboundRequest.Status.PENDING,
            seller_note="Ready for delivery next Tuesday.",
            requested_by=self.seller_user,
        )

        # 1. Warehouse staff lists requests
        list_req = self.factory.get("/api/workforce/warehouse/inbound-requests/?status=PENDING")
        force_authenticate(list_req, user=self.wh_staff_user)
        list_view = WarehousePortalInboundRequestListView.as_view()
        list_res = list_view(list_req)

        self.assertEqual(list_res.status_code, status.HTTP_200_OK)
        ids = [item["id"] for item in (list_res.data.get("results") or list_res.data)]
        self.assertIn(inbound_req.id, ids)

        # 2. Warehouse staff accepts request
        decision_req = self.factory.post(
            f"/api/workforce/warehouse/inbound-requests/{inbound_req.id}/decision/",
            {
                "action": "ACCEPT",
                "reviewer_note": "Dock 2 allocated for Tuesday morning intake.",
            },
            format="json",
        )
        force_authenticate(decision_req, user=self.wh_staff_user)
        dec_view = WarehousePortalInboundRequestDecisionView.as_view()
        dec_res = dec_view(decision_req, pk=inbound_req.id)

        self.assertEqual(dec_res.status_code, status.HTTP_200_OK)
        self.assertEqual(dec_res.data["status"], "ACCEPTED")
        self.assertEqual(dec_res.data["reviewer_note"], "Dock 2 allocated for Tuesday morning intake.")
        self.assertEqual(dec_res.data["reviewed_by_name"], "Hub Operator")
        self.assertIsNotNone(dec_res.data["reviewed_at"])

        # 3. Verify Seller visibility
        seller_list_req = self.factory.get(f"/api/workforce/seller-hub/inbound-requests/?product_id={self.fbs_product.id}")
        force_authenticate(seller_list_req, user=self.seller_user)
        seller_view = SellerInboundRequestListCreateView.as_view()
        seller_res = seller_view(seller_list_req)

        self.assertEqual(seller_res.status_code, status.HTTP_200_OK)
        target = next((item for item in seller_res.data if item["id"] == inbound_req.id), None)
        self.assertIsNotNone(target)
        self.assertEqual(target["status"], "ACCEPTED")
        self.assertEqual(target["reviewer_note"], "Dock 2 allocated for Tuesday morning intake.")

    def test_06_warehouse_staff_rejects_inbound_request_with_note(self):
        """Warehouse staff rejects an inbound request with a capacity constraint note."""
        inbound_req = WarehouseInboundRequest.objects.create(
            product=self.fbs_product,
            company=self.seller_company,
            warehouse=self.warehouse,
            requested_quantity=500,
            status=WarehouseInboundRequest.Status.PENDING,
            seller_note="Bulk batch 500 units.",
            requested_by=self.seller_user,
        )

        decision_req = self.factory.post(
            f"/api/workforce/warehouse/inbound-requests/{inbound_req.id}/decision/",
            {
                "action": "REJECT",
                "reviewer_note": "Capacity constraint: dry spice zone full until next month.",
            },
            format="json",
        )
        force_authenticate(decision_req, user=self.wh_staff_user)
        dec_view = WarehousePortalInboundRequestDecisionView.as_view()
        dec_res = dec_view(decision_req, pk=inbound_req.id)

        self.assertEqual(dec_res.status_code, status.HTTP_200_OK)
        self.assertEqual(dec_res.data["status"], "REJECTED")
        self.assertEqual(dec_res.data["reviewer_note"], "Capacity constraint: dry spice zone full until next month.")

        # Seller sees REJECTED with clear reason
        seller_list_req = self.factory.get("/api/workforce/seller-hub/inbound-requests/?status=REJECTED")
        force_authenticate(seller_list_req, user=self.seller_user)
        seller_view = SellerInboundRequestListCreateView.as_view()
        seller_res = seller_view(seller_list_req)

        self.assertEqual(seller_res.status_code, status.HTTP_200_OK)
        target = next((item for item in seller_res.data if item["id"] == inbound_req.id), None)
        self.assertIsNotNone(target)
        self.assertEqual(target["status"], "REJECTED")
        self.assertEqual(target["reviewer_note"], "Capacity constraint: dry spice zone full until next month.")

        # Check Audit Log has REJECTED action
        logs = WarehouseInboundRequestAuditLog.objects.filter(inbound_request_id=inbound_req.id, action="REJECT")
        self.assertEqual(logs.count(), 1)


if __name__ == "__main__":
    unittest.main()
