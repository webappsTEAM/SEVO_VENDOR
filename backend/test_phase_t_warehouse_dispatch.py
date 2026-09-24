#!/usr/bin/env python
"""
test_phase_t_warehouse_dispatch.py
Comprehensive verification test suite for Phase T:
- Real Warehouse Model & CRUD
- Seller Company to Warehouse Assignment Mapping
- Automatic Dispatch & Retry Dispatch using Warehouse coordinates instead of Seller company coordinates
- Distance computation from Warehouse coordinates
- WAREHOUSE_ASSIGNMENT_REQUIRED blocking for unassigned sellers
"""
import os
import sys
import django
from decimal import Decimal

# Initialize Django environment
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "workforce_core.settings")
django.setup()

import unittest
from django.utils import timezone
from django.contrib.auth import get_user_model
from rest_framework.test import APIRequestFactory, force_authenticate
from rest_framework import status

from companies.models import Company
from employees.models import Employee
from service_requests.models import ServiceRequest
from workforce_api.models import (
    Warehouse,
    SellerWarehouseAssignment,
    get_seller_assigned_warehouse,
    SellerOrder,
    SellerOrderItem,
    SellerProduct,
    SellerHubCategory,
)
from workforce_api.views_seller_hub import (
    AdminWarehouseListCreateView,
    AdminWarehouseDetailView,
    AdminSellerWarehouseAssignView,
    AdminSellerApprovalListView,
    SellerOrderStatusTransitionView,
    SellerOrderRetryDispatchView,
    SellerOrderAvailableRidersView,
)
from workforce_api.services.automatic_dispatch import (
    get_available_riders_summary,
    haversine_distance,
)

User = get_user_model()


class PhaseTWarehouseDispatchTestCase(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.factory = APIRequestFactory()

        # 1. Platform Admin User
        cls.admin_user, _ = User.objects.get_or_create(
            username="phaset_platform_admin",
            defaults={
                "email": "phaset_admin@sevo.com",
                "is_staff": True,
                "is_superuser": True,
                "role": "platform_admin",
            },
        )
        cls.admin_user.is_staff = True
        cls.admin_user.is_superuser = True
        cls.admin_user.role = "platform_admin"
        cls.admin_user.save()

        # 2. Regular Seller User
        cls.seller_user, _ = User.objects.get_or_create(
            username="phaset_seller_user",
            defaults={"email": "phaset_seller@merchant.com", "is_staff": False, "role": "vendor_admin"},
        )
        cls.seller_user.role = "vendor_admin"
        cls.seller_user.save()

        # 3. Seller Company with distinct store location (e.g. Koramangala: 12.9279000, 77.6271000)
        cls.company_seller, _ = Company.objects.get_or_create(
            company_name="PhaseT Organic Mart",
            defaults={
                "slug": "phaset-organic-mart",
                "business_type": "grocery_supplier",
                "address": "80ft Road, Koramangala 4th Block, Bangalore",
                "latitude": Decimal("12.9279000"),
                "longitude": Decimal("77.6271000"),
                "is_active": True,
            },
        )
        cls.company_seller.latitude = Decimal("12.9279000")
        cls.company_seller.longitude = Decimal("77.6271000")
        cls.company_seller.save()

        # Associate seller_user with company_seller via Employee or user profile if applicable
        cls.seller_emp, _ = Employee.objects.get_or_create(
            user=cls.seller_user,
            defaults={"company": cls.company_seller, "employee_id": "EMP-SELLER-T", "is_active": True},
        )
        cls.seller_emp.company = cls.company_seller
        cls.seller_emp.save()

        # 4. Unassigned Seller Company
        cls.unassigned_company, _ = Company.objects.get_or_create(
            company_name="PhaseT Unassigned Store",
            defaults={
                "slug": "phaset-unassigned-store",
                "business_type": "grocery_supplier",
                "address": "Indiranagar 100ft Road",
                "latitude": Decimal("12.9784000"),
                "longitude": Decimal("77.6408000"),
                "is_active": True,
            },
        )

        cls.unassigned_user, _ = User.objects.get_or_create(
            username="phaset_unassigned_user",
            defaults={"email": "unassigned@merchant.com", "role": "vendor_admin"},
        )
        cls.unassigned_emp, _ = Employee.objects.get_or_create(
            user=cls.unassigned_user,
            defaults={"company": cls.unassigned_company, "employee_id": "EMP-UNASSIGNED-T", "is_active": True},
        )
        cls.unassigned_emp.company = cls.unassigned_company
        cls.unassigned_emp.save()

        # 5. Clean prior test assignments and warehouses
        SellerWarehouseAssignment.objects.filter(company__in=[cls.company_seller, cls.unassigned_company]).delete()
        Warehouse.objects.filter(name__startswith="PhaseT").delete()

    def test_01_create_warehouse_and_admin_crud(self):
        """Platform Admin can create, view, edit, and deactivate warehouse facilities."""
        # 1. Create Central Warehouse
        req = self.factory.post(
            "/api/workforce/admin/warehouses/",
            {
                "name": "PhaseT Central Bangalore Warehouse",
                "code": "WH-BLR-PHASE-T",
                "address": "Electronic City Phase 1, Bangalore",
                "latitude": 12.8399,
                "longitude": 77.6770,
                "city": "Bangalore",
                "region": "Karnataka",
                "contact_phone": "+91 80 1234 5678",
                "is_active": True,
            },
            format="json",
        )
        force_authenticate(req, user=self.admin_user)
        resp = AdminWarehouseListCreateView.as_view()(req)
        self.assertEqual(resp.status_code, status.HTTP_201_CREATED, resp.data)
        wh_id = resp.data["id"]

        # 2. Get list of warehouses
        req_list = self.factory.get("/api/workforce/admin/warehouses/")
        force_authenticate(req_list, user=self.admin_user)
        resp_list = AdminWarehouseListCreateView.as_view()(req_list)
        self.assertEqual(resp_list.status_code, status.HTTP_200_OK)
        found = any(w["id"] == wh_id for w in resp_list.data)
        self.assertTrue(found, "Created warehouse must appear in admin list")

        # 3. Patch warehouse coordinates
        req_patch = self.factory.patch(
            f"/api/workforce/admin/warehouses/{wh_id}/",
            {"latitude": 12.8400, "longitude": 77.6780},
            format="json",
        )
        force_authenticate(req_patch, user=self.admin_user)
        resp_patch = AdminWarehouseDetailView.as_view()(req_patch, pk=wh_id)
        self.assertEqual(resp_patch.status_code, status.HTTP_200_OK)
        self.assertAlmostEqual(float(resp_patch.data["latitude"]), 12.8400, places=4)

        # 4. Non-admin user is rejected
        req_unauth = self.factory.post(
            "/api/workforce/admin/warehouses/",
            {"name": "Hacker Warehouse", "address": "X", "latitude": 0, "longitude": 0},
            format="json",
        )
        force_authenticate(req_unauth, user=self.seller_user)
        resp_unauth = AdminWarehouseListCreateView.as_view()(req_unauth)
        self.assertEqual(resp_unauth.status_code, status.HTTP_403_FORBIDDEN)

    def test_02_assign_seller_to_warehouse(self):
        """Platform Admin can map a seller company to a warehouse facility."""
        # Create dedicated test warehouse in North Bangalore (Yelahanka: 13.1007, 77.5963)
        warehouse, _ = Warehouse.objects.get_or_create(
            name="PhaseT North Bangalore Hub",
            defaults={
                "code": "WH-BLR-NORTH",
                "address": "Yelahanka Logistics Park, Bangalore",
                "latitude": Decimal("13.1007000"),
                "longitude": Decimal("77.5963000"),
                "city": "Bangalore",
                "region": "Karnataka",
                "is_active": True,
            },
        )

        # Assign seller company to this warehouse via admin API
        req_assign = self.factory.post(
            f"/api/workforce/admin/sellers/{self.company_seller.id}/warehouse/",
            {"warehouse_id": warehouse.id, "notes": "Primary FMCG North Zone Hub"},
            format="json",
        )
        force_authenticate(req_assign, user=self.admin_user)
        resp_assign = AdminSellerWarehouseAssignView.as_view()(req_assign, seller_id=self.company_seller.id)
        self.assertEqual(resp_assign.status_code, status.HTTP_200_OK, resp_assign.data)
        self.assertTrue(resp_assign.data["assignment"]["warehouse"] == warehouse.id)

        # Helper resolution test
        resolved_wh = get_seller_assigned_warehouse(self.company_seller.id)
        self.assertIsNotNone(resolved_wh)
        self.assertEqual(resolved_wh.id, warehouse.id)
        self.assertEqual(resolved_wh.name, "PhaseT North Bangalore Hub")

        # Admin seller list includes warehouse info
        req_sellers = self.factory.get(f"/api/workforce/admin/seller-hub/approval/sellers/?search={self.company_seller.company_name}")
        force_authenticate(req_sellers, user=self.admin_user)
        resp_sellers = AdminSellerApprovalListView.as_view()(req_sellers)
        self.assertEqual(resp_sellers.status_code, status.HTTP_200_OK)
        results = resp_sellers.data.get("results", [])
        seller_item = next((s for s in results if s["id"] == self.company_seller.id), None)
        self.assertIsNotNone(seller_item)
        self.assertEqual(seller_item["warehouse_id"], warehouse.id)
        self.assertEqual(seller_item["warehouse_name"], "PhaseT North Bangalore Hub")

    def test_03_unassigned_seller_order_dispatch_blocked(self):
        """Sellers with NO assigned warehouse are blocked with WAREHOUSE_ASSIGNMENT_REQUIRED."""
        # Ensure unassigned_company has NO assignment
        SellerWarehouseAssignment.objects.filter(company=self.unassigned_company).delete()

        # Create Order in PACKED status
        order = SellerOrder.objects.create(
            company=self.unassigned_company,
            source_order_id=f"TEST-PHASE-T-UNASSIGNED-{timezone.now().timestamp()}",
            order_number=f"SO-TEST-UNA-{int(timezone.now().timestamp()) % 10000}",
            customer_name="Customer Unassigned",
            customer_phone="9988776655",
            delivery_address="Indiranagar, Bangalore",
            total_amount=Decimal("450.00"),
            status=SellerOrder.Status.PACKED,
        )

        # 1. Attempt transition to READY_FOR_PICKUP
        req_trans = self.factory.post(
            f"/api/workforce/seller-hub/orders/{order.id}/transition/",
            {"action": "mark_ready"},
            format="json",
        )
        force_authenticate(req_trans, user=self.unassigned_user)
        resp_trans = SellerOrderStatusTransitionView.as_view()(req_trans, pk=order.id)
        self.assertEqual(resp_trans.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(resp_trans.data.get("code"), "WAREHOUSE_ASSIGNMENT_REQUIRED")
        self.assertIn("assigned to an active warehouse", resp_trans.data.get("error", ""))

        # 2. Attempt retry-dispatch (order in READY_FOR_PICKUP state)
        order.status = SellerOrder.Status.READY_FOR_PICKUP
        order.save(update_fields=["status"])

        req_retry = self.factory.post(
            f"/api/workforce/seller-hub/orders/{order.id}/retry-dispatch/",
            {},
            format="json",
        )
        force_authenticate(req_retry, user=self.unassigned_user)
        resp_retry = SellerOrderRetryDispatchView.as_view()(req_retry, pk=order.id)
        self.assertEqual(resp_retry.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(resp_retry.data.get("code"), "WAREHOUSE_ASSIGNMENT_REQUIRED")

        # 3. Attempt available-riders diagnostics
        req_diag = self.factory.get(f"/api/workforce/seller-hub/orders/{order.id}/available-riders/")
        force_authenticate(req_diag, user=self.unassigned_user)
        resp_diag = SellerOrderAvailableRidersView.as_view()(req_diag, pk=order.id)
        self.assertEqual(resp_diag.status_code, status.HTTP_200_OK)
        self.assertEqual(resp_diag.data.get("code"), "WAREHOUSE_ASSIGNMENT_REQUIRED")
        self.assertTrue(resp_diag.data.get("warehouse_missing"))

    def test_04_assigned_seller_order_uses_warehouse_coordinates(self):
        """Assigned seller orders use the Warehouse coordinates (NOT Company.latitude/longitude)."""
        # Warehouse in Whitefield (12.9698, 77.7499)
        wh_whitefield, _ = Warehouse.objects.get_or_create(
            name="PhaseT Whitefield Fulfillment Center",
            defaults={
                "code": "WH-BLR-WTF",
                "address": "ITPB Main Road, Whitefield, Bangalore",
                "latitude": Decimal("12.9698000"),
                "longitude": Decimal("77.7499000"),
                "city": "Bangalore",
                "region": "Karnataka",
                "is_active": True,
            },
        )
        # Assign company_seller to Whitefield warehouse
        SellerWarehouseAssignment.objects.update_or_create(
            company=self.company_seller,
            defaults={"warehouse": wh_whitefield, "assigned_by": self.admin_user},
        )

        # Confirm Company.latitude is in Koramangala (12.9279, 77.6271), NOT Whitefield (12.9698, 77.7499)
        self.company_seller.refresh_from_db()
        self.assertAlmostEqual(float(self.company_seller.latitude), 12.9279, places=3)
        self.assertAlmostEqual(float(self.company_seller.longitude), 77.6271, places=3)

        # Create Order in PACKED status
        order = SellerOrder.objects.create(
            company=self.company_seller,
            source_order_id=f"TEST-PHASE-T-WH-{timezone.now().timestamp()}",
            order_number=f"SO-TEST-WH-{int(timezone.now().timestamp()) % 10000}",
            customer_name="Rahul Customer",
            customer_phone="9876543210",
            delivery_address="Kundalahalli Gate, Bangalore",
            total_amount=Decimal("899.00"),
            status=SellerOrder.Status.PACKED,
        )

        # Transition to READY_FOR_PICKUP
        req_trans = self.factory.post(
            f"/api/workforce/seller-hub/orders/{order.id}/transition/",
            {"action": "mark_ready"},
            format="json",
        )
        force_authenticate(req_trans, user=self.seller_user)
        resp_trans = SellerOrderStatusTransitionView.as_view()(req_trans, pk=order.id)
        self.assertEqual(resp_trans.status_code, status.HTTP_200_OK, resp_trans.data)

        order.refresh_from_db()
        self.assertEqual(order.status, SellerOrder.Status.READY_FOR_PICKUP)
        self.assertIsNotNone(order.dispatch_job)

        # Concrete pickup coordinates verification:
        dispatch_job = order.dispatch_job
        self.assertAlmostEqual(float(dispatch_job.latitude), 12.9698000, places=4,
                               msg="Dispatch Job latitude MUST match assigned Warehouse (Whitefield), NOT Seller Company")
        self.assertAlmostEqual(float(dispatch_job.longitude), 77.7499000, places=4,
                               msg="Dispatch Job longitude MUST match assigned Warehouse (Whitefield), NOT Seller Company")
        self.assertIn("Whitefield", dispatch_job.address)

        # Distance calculation verification:
        # Distance from Whitefield WH (12.9698, 77.7499) to a test rider in Whitefield (12.9700, 77.7500)
        dist_m = haversine_distance(12.9698, 77.7499, 12.9700, 77.7500)
        self.assertLess(dist_m, 100.0, "Test Whitefield rider is within 100m of Whitefield Warehouse")

        # Test distance from Koramangala store (12.9279, 77.6271) to Whitefield WH is ~14 km
        dist_store_to_wh_km = haversine_distance(12.9279, 77.6271, 12.9698, 77.7499) / 1000.0
        self.assertGreater(dist_store_to_wh_km, 10.0, "Distance between seller store and warehouse should be >10 km")

        print(f"\n[PHASE T VERIFICATION SUCCESS]")
        print(f"  Seller Store Address: {self.company_seller.address} ({self.company_seller.latitude}, {self.company_seller.longitude})")
        print(f"  Assigned Warehouse:   {wh_whitefield.name} ({wh_whitefield.latitude}, {wh_whitefield.longitude})")
        print(f"  Dispatch Job Coords:  Lat={dispatch_job.latitude}, Lon={dispatch_job.longitude} (Address: {dispatch_job.address})")
        print(f"  Pickup origin verified coming from WAREHOUSE, not seller store!\n")


if __name__ == "__main__":
    unittest.main()
