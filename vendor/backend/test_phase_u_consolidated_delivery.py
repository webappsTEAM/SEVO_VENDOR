#!/usr/bin/env python
"""
test_phase_u_consolidated_delivery.py
Permanent Phase U Regression Test Suite:
- Multi-vendor cart & consolidated per-warehouse delivery
- Same Warehouse (2 Sellers): Single delivery_group_id, group-wait state machine, single consolidated dispatch job
- Different Warehouses (2 Sellers): Multiple delivery_group_ids, independent dispatch jobs per warehouse
- Fulfillment propagation (Assigned, Handover, Delivered) across consolidated group orders
"""
import os
import sys
import uuid
from decimal import Decimal

# Initialize Django environment
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "workforce_core.settings")

import django
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
    SellerOrder,
    SellerOrderItem,
    SellerProduct,
    SellerHubCategory,
)
from workforce_api.views_seller_hub import (
    SellerOrderStatusTransitionView,
)

User = get_user_model()


class PhaseUConsolidatedDeliveryTestCase(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.factory = APIRequestFactory()
        cls.run_id = uuid.uuid4().hex[:8]

        # 1. Platform Admin User
        cls.admin_user, _ = User.objects.get_or_create(
            username=f"admin_u_{cls.run_id}",
            defaults={
                "email": f"admin_u_{cls.run_id}@sevo.com",
                "is_staff": True,
                "is_superuser": True,
                "role": "platform_admin",
            },
        )
        cls.admin_user.is_staff = True
        cls.admin_user.is_superuser = True
        cls.admin_user.save()

        # 2. Category
        cls.category, _ = SellerHubCategory.objects.get_or_create(
            slug=f"cat-u-{cls.run_id}",
            defaults={"name": "Phase U Groceries", "sort_order": 1, "is_active": True},
        )

        # 3. Warehouses
        # Warehouse 1: Central Bangalore Fulfillment Hub
        cls.wh_central, _ = Warehouse.objects.get_or_create(
            code=f"WH-U-CEN-{cls.run_id}",
            defaults={
                "name": f"PhaseU Central Hub {cls.run_id}",
                "address": "Koramangala 80ft Road, Bangalore",
                "latitude": Decimal("12.9350000"),
                "longitude": Decimal("77.6240000"),
                "city": "Bangalore",
                "region": "Karnataka",
                "contact_phone": "+919876543210",
                "is_active": True,
            },
        )

        # Warehouse 2: North Bangalore Fulfillment Hub
        cls.wh_north, _ = Warehouse.objects.get_or_create(
            code=f"WH-U-NOR-{cls.run_id}",
            defaults={
                "name": f"PhaseU North Hub {cls.run_id}",
                "address": "Hebbal Outer Ring Road, Bangalore",
                "latitude": Decimal("13.0358000"),
                "longitude": Decimal("77.5970000"),
                "city": "Bangalore",
                "region": "Karnataka",
                "contact_phone": "+919876543211",
                "is_active": True,
            },
        )

        # 4. Sellers
        # Seller A -> WH Central
        cls.seller_a_user, _ = User.objects.get_or_create(
            username=f"seller_a_{cls.run_id}",
            defaults={"email": f"seller_a_{cls.run_id}@merchant.com", "role": "vendor_admin"},
        )
        cls.company_a, _ = Company.objects.get_or_create(
            company_name=f"Seller A Organic {cls.run_id}",
            defaults={
                "slug": f"seller-a-{cls.run_id}",
                "business_type": "grocery_supplier",
                "address": "Store A Location",
                "latitude": Decimal("12.9300000"),
                "longitude": Decimal("77.6200000"),
                "is_active": True,
            },
        )
        Employee.objects.get_or_create(
            user=cls.seller_a_user,
            defaults={"company": cls.company_a, "employee_id": f"EMP-A-{cls.run_id}", "is_active": True},
        )
        SellerWarehouseAssignment.objects.get_or_create(
            company=cls.company_a,
            warehouse=cls.wh_central,
            defaults={"assigned_by": cls.admin_user, "notes": "Phase U Assignment WH Central"},
        )

        # Seller B -> WH Central (Same Warehouse as Seller A)
        cls.seller_b_user, _ = User.objects.get_or_create(
            username=f"seller_b_{cls.run_id}",
            defaults={"email": f"seller_b_{cls.run_id}@merchant.com", "role": "vendor_admin"},
        )
        cls.company_b, _ = Company.objects.get_or_create(
            company_name=f"Seller B Dairy {cls.run_id}",
            defaults={
                "slug": f"seller-b-{cls.run_id}",
                "business_type": "grocery_supplier",
                "address": "Store B Location",
                "latitude": Decimal("12.9320000"),
                "longitude": Decimal("77.6220000"),
                "is_active": True,
            },
        )
        Employee.objects.get_or_create(
            user=cls.seller_b_user,
            defaults={"company": cls.company_b, "employee_id": f"EMP-B-{cls.run_id}", "is_active": True},
        )
        SellerWarehouseAssignment.objects.get_or_create(
            company=cls.company_b,
            warehouse=cls.wh_central,
            defaults={"assigned_by": cls.admin_user, "notes": "Phase U Assignment WH Central"},
        )

        # Seller C -> WH North (Different Warehouse)
        cls.seller_c_user, _ = User.objects.get_or_create(
            username=f"seller_c_{cls.run_id}",
            defaults={"email": f"seller_c_{cls.run_id}@merchant.com", "role": "vendor_admin"},
        )
        cls.company_c, _ = Company.objects.get_or_create(
            company_name=f"Seller C Farms {cls.run_id}",
            defaults={
                "slug": f"seller-c-{cls.run_id}",
                "business_type": "grocery_supplier",
                "address": "Store C Location",
                "latitude": Decimal("13.0300000"),
                "longitude": Decimal("77.5900000"),
                "is_active": True,
            },
        )
        Employee.objects.get_or_create(
            user=cls.seller_c_user,
            defaults={"company": cls.company_c, "employee_id": f"EMP-C-{cls.run_id}", "is_active": True},
        )
        SellerWarehouseAssignment.objects.get_or_create(
            company=cls.company_c,
            warehouse=cls.wh_north,
            defaults={"assigned_by": cls.admin_user, "notes": "Phase U Assignment WH North"},
        )

        # Products
        cls.prod_a = SellerProduct.objects.create(
            company=cls.company_a,
            category=cls.category,
            title=f"Organic Rice {cls.run_id}",
            sku=f"SKU-A-{cls.run_id}",
            selling_price=Decimal("150.00"),
            mrp=Decimal("180.00"),
            status="APPROVED",
        )
        cls.prod_b = SellerProduct.objects.create(
            company=cls.company_b,
            category=cls.category,
            title=f"Fresh Milk {cls.run_id}",
            sku=f"SKU-B-{cls.run_id}",
            selling_price=Decimal("60.00"),
            mrp=Decimal("65.00"),
            status="APPROVED",
        )
        cls.prod_c = SellerProduct.objects.create(
            company=cls.company_c,
            category=cls.category,
            title=f"Green Apples {cls.run_id}",
            sku=f"SKU-C-{cls.run_id}",
            selling_price=Decimal("200.00"),
            mrp=Decimal("220.00"),
            status="APPROVED",
        )

    @classmethod
    def tearDownClass(cls):
        # Clean up test entities created in this test run
        try:
            SellerOrderItem.objects.filter(product__in=[cls.prod_a, cls.prod_b, cls.prod_c]).delete()
            SellerOrder.objects.filter(company__in=[cls.company_a, cls.company_b, cls.company_c]).delete()
            SellerProduct.objects.filter(id__in=[cls.prod_a.id, cls.prod_b.id, cls.prod_c.id]).delete()
            SellerWarehouseAssignment.objects.filter(company__in=[cls.company_a, cls.company_b, cls.company_c]).delete()
            Employee.objects.filter(company__in=[cls.company_a, cls.company_b, cls.company_c]).delete()
            cls.company_a.delete()
            cls.company_b.delete()
            cls.company_c.delete()
            cls.wh_central.delete()
            cls.wh_north.delete()
            cls.category.delete()
            cls.seller_a_user.delete()
            cls.seller_b_user.delete()
            cls.seller_c_user.delete()
            cls.admin_user.delete()
        except Exception:
            pass
        super().tearDownClass()

    def test_01_same_warehouse_consolidated_delivery_flow(self):
        """
        Scenario 1: Customer buys from Seller A and Seller B (both fulfilled from WH Central).
        - Both orders share delivery_group_id = 'DG-SAME-WH-...'
        - Seller A marks READY_FOR_PICKUP first -> No dispatch job yet (waits for Seller B).
        - Seller B marks READY_FOR_PICKUP -> Exactly 1 consolidated dispatch job created for WH Central.
        - Both orders reference the same dispatch job.
        """
        dg_id = f"DG-SAME-WH-{self.run_id}"

        # Create Order A (Seller A)
        order_a = SellerOrder.objects.create(
            company=self.company_a,
            order_number=f"SO-A-{self.run_id}",
            source_order_id=f"MKT-A-{self.run_id}",
            delivery_group_id=dg_id,
            warehouse_id=self.wh_central.id,
            warehouse_name=self.wh_central.name,
            status=SellerOrder.Status.ACCEPTED,
            total_amount=Decimal("150.00"),
            customer_name="Multi-Vendor Customer",
            customer_phone="+919900011122",
            delivery_address="Indiranagar 12th Main, Bangalore",
        )
        SellerOrderItem.objects.create(
            order=order_a,
            product=self.prod_a,
            product_title=self.prod_a.title,
            sku=self.prod_a.sku,
            ordered_quantity=Decimal("1.000"),
            fulfilled_quantity=Decimal("1.000"),
            unit_price=Decimal("150.00"),
            line_total=Decimal("150.00"),
        )

        # Create Order B (Seller B)
        order_b = SellerOrder.objects.create(
            company=self.company_b,
            order_number=f"SO-B-{self.run_id}",
            source_order_id=f"MKT-B-{self.run_id}",
            delivery_group_id=dg_id,
            warehouse_id=self.wh_central.id,
            warehouse_name=self.wh_central.name,
            status=SellerOrder.Status.ACCEPTED,
            total_amount=Decimal("60.00"),
            customer_name="Multi-Vendor Customer",
            customer_phone="+919900011122",
            delivery_address="Indiranagar 12th Main, Bangalore",
        )
        SellerOrderItem.objects.create(
            order=order_b,
            product=self.prod_b,
            product_title=self.prod_b.title,
            sku=self.prod_b.sku,
            ordered_quantity=Decimal("1.000"),
            fulfilled_quantity=Decimal("1.000"),
            unit_price=Decimal("60.00"),
            line_total=Decimal("60.00"),
        )

        # Step 1: Seller A packs and marks READY_FOR_PICKUP
        req = self.factory.post(f"/api/workforce/seller-hub/orders/{order_a.id}/transition/", {"action": "start_picking"}, format="json")
        force_authenticate(req, user=self.seller_a_user)
        SellerOrderStatusTransitionView.as_view()(req, pk=order_a.id)

        req = self.factory.post(f"/api/workforce/seller-hub/orders/{order_a.id}/transition/", {"action": "mark_packed"}, format="json")
        force_authenticate(req, user=self.seller_a_user)
        SellerOrderStatusTransitionView.as_view()(req, pk=order_a.id)

        req = self.factory.post(f"/api/workforce/seller-hub/orders/{order_a.id}/transition/", {"action": "mark_ready"}, format="json")
        force_authenticate(req, user=self.seller_a_user)
        resp_a = SellerOrderStatusTransitionView.as_view()(req, pk=order_a.id)
        self.assertEqual(resp_a.status_code, status.HTTP_200_OK)

        order_a.refresh_from_db()
        self.assertEqual(order_a.status, SellerOrder.Status.READY_FOR_PICKUP)
        # Group synchronization check: Sibling order B is still ACCEPTED, so dispatch job MUST NOT be created yet
        self.assertIsNone(order_a.dispatch_job, "Dispatch job must NOT be created while sibling seller order B is not ready")

        # Step 2: Seller B packs and marks READY_FOR_PICKUP
        req = self.factory.post(f"/api/workforce/seller-hub/orders/{order_b.id}/transition/", {"action": "start_picking"}, format="json")
        force_authenticate(req, user=self.seller_b_user)
        SellerOrderStatusTransitionView.as_view()(req, pk=order_b.id)

        req = self.factory.post(f"/api/workforce/seller-hub/orders/{order_b.id}/transition/", {"action": "mark_packed"}, format="json")
        force_authenticate(req, user=self.seller_b_user)
        SellerOrderStatusTransitionView.as_view()(req, pk=order_b.id)

        req = self.factory.post(f"/api/workforce/seller-hub/orders/{order_b.id}/transition/", {"action": "mark_ready"}, format="json")
        force_authenticate(req, user=self.seller_b_user)
        resp_b = SellerOrderStatusTransitionView.as_view()(req, pk=order_b.id)
        self.assertEqual(resp_b.status_code, status.HTTP_200_OK)

        order_a.refresh_from_db()
        order_b.refresh_from_db()

        self.assertEqual(order_b.status, SellerOrder.Status.READY_FOR_PICKUP)
        self.assertIsNotNone(order_b.dispatch_job, "Dispatch job MUST be created once all sibling orders are ready")
        self.assertIsNotNone(order_a.dispatch_job, "Order A MUST be linked to the newly created consolidated dispatch job")

        # Confirm BOTH orders point to the exact same consolidated dispatch job
        self.assertEqual(order_a.dispatch_job_id, order_b.dispatch_job_id, "Both orders MUST share the exact same Dispatch Job")

        # Confirm Dispatch Job pickup coordinates match WH Central (NOT store addresses)
        job = order_a.dispatch_job
        self.assertAlmostEqual(float(job.latitude), float(self.wh_central.latitude), places=4)
        self.assertAlmostEqual(float(job.longitude), float(self.wh_central.longitude), places=4)

        print(f"\n[PHASE U SAME-WAREHOUSE TEST PASSED]")
        print(f"  Delivery Group: {dg_id}")
        print(f"  Order A #{order_a.order_number} & Order B #{order_b.order_number}")
        print(f"  Consolidated Dispatch Job #{job.id} created at Warehouse: {self.wh_central.name}")

    def test_02_different_warehouses_independent_dispatch_flow(self):
        """
        Scenario 2: Customer buys from Seller A (WH Central) and Seller C (WH North).
        - Different delivery_group_ids (DG-WH-CEN-... and DG-WH-NOR-...)
        - Seller A transitions to READY_FOR_PICKUP -> Immediately creates Dispatch Job 1 for WH Central.
        - Seller C transitions to READY_FOR_PICKUP -> Immediately creates Dispatch Job 2 for WH North.
        - Two distinct dispatch jobs with distinct warehouse coordinates.
        """
        dg_cen = f"DG-WH-CEN-{self.run_id}"
        dg_nor = f"DG-WH-NOR-{self.run_id}"

        # Create Order A (Seller A -> WH Central)
        order_a = SellerOrder.objects.create(
            company=self.company_a,
            order_number=f"SO-A2-{self.run_id}",
            source_order_id=f"MKT-A2-{self.run_id}",
            delivery_group_id=dg_cen,
            warehouse_id=self.wh_central.id,
            warehouse_name=self.wh_central.name,
            status=SellerOrder.Status.PACKED,
            total_amount=Decimal("150.00"),
            customer_name="Multi-Warehouse Customer",
            customer_phone="+919900011122",
            delivery_address="Indiranagar 12th Main, Bangalore",
        )
        SellerOrderItem.objects.create(
            order=order_a,
            product=self.prod_a,
            product_title=self.prod_a.title,
            sku=self.prod_a.sku,
            ordered_quantity=Decimal("1.000"),
            fulfilled_quantity=Decimal("1.000"),
            unit_price=Decimal("150.00"),
            line_total=Decimal("150.00"),
        )

        # Create Order C (Seller C -> WH North)
        order_c = SellerOrder.objects.create(
            company=self.company_c,
            order_number=f"SO-C-{self.run_id}",
            source_order_id=f"MKT-C-{self.run_id}",
            delivery_group_id=dg_nor,
            warehouse_id=self.wh_north.id,
            warehouse_name=self.wh_north.name,
            status=SellerOrder.Status.PACKED,
            total_amount=Decimal("200.00"),
            customer_name="Multi-Warehouse Customer",
            customer_phone="+919900011122",
            delivery_address="Indiranagar 12th Main, Bangalore",
        )
        SellerOrderItem.objects.create(
            order=order_c,
            product=self.prod_c,
            product_title=self.prod_c.title,
            sku=self.prod_c.sku,
            ordered_quantity=Decimal("1.000"),
            fulfilled_quantity=Decimal("1.000"),
            unit_price=Decimal("200.00"),
            line_total=Decimal("200.00"),
        )

        # Transition Order A to READY_FOR_PICKUP
        req = self.factory.post(f"/api/workforce/seller-hub/orders/{order_a.id}/transition/", {"action": "mark_ready"}, format="json")
        force_authenticate(req, user=self.seller_a_user)
        resp_a = SellerOrderStatusTransitionView.as_view()(req, pk=order_a.id)
        self.assertEqual(resp_a.status_code, status.HTTP_200_OK)

        order_a.refresh_from_db()
        self.assertIsNotNone(order_a.dispatch_job, "Order A must immediately dispatch without waiting for WH North seller")
        job_cen = order_a.dispatch_job
        self.assertAlmostEqual(float(job_cen.latitude), float(self.wh_central.latitude), places=4)

        # Transition Order C to READY_FOR_PICKUP
        req = self.factory.post(f"/api/workforce/seller-hub/orders/{order_c.id}/transition/", {"action": "mark_ready"}, format="json")
        force_authenticate(req, user=self.seller_c_user)
        resp_c = SellerOrderStatusTransitionView.as_view()(req, pk=order_c.id)
        self.assertEqual(resp_c.status_code, status.HTTP_200_OK)

        order_c.refresh_from_db()
        self.assertIsNotNone(order_c.dispatch_job, "Order C must dispatch independently for WH North")
        job_nor = order_c.dispatch_job
        self.assertAlmostEqual(float(job_nor.latitude), float(self.wh_north.latitude), places=4)

        # Confirm the two jobs are separate and distinct
        self.assertNotEqual(job_cen.id, job_nor.id, "Different warehouses MUST produce separate dispatch jobs")
        self.assertNotEqual(job_cen.latitude, job_nor.latitude, "Different warehouse coordinates must be used")

        print(f"\n[PHASE U MULTI-WAREHOUSE TEST PASSED]")
        print(f"  Delivery Group 1: {dg_cen} -> Dispatch Job #{job_cen.id} ({self.wh_central.name})")
        print(f"  Delivery Group 2: {dg_nor} -> Dispatch Job #{job_nor.id} ({self.wh_north.name})")
        print(f"  Two independent delivery dispatches successfully created for separate warehouses!\n")


if __name__ == "__main__":
    unittest.main()
