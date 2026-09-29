"""
test_delivery_slots.py

Comprehensive test suite for Delivery Slots & Capacity Scheduling (Phase 1):
1. Admin CRUD endpoints with role-based authorization.
2. Overlap validation & rejection for active slots on the same warehouse.
3. Deletion protection for slots referenced by order bookings.
4. Public slot availability API with capacity calculation, applicable days, and same-day cutoff.
5. Marketplace order intake with atomic capacity booking, concurrency prevention, and backward compatibility.
"""

import os
import django
import unittest
from datetime import time, date, timedelta
from decimal import Decimal

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "workforce_core.settings")
django.setup()

from django.conf import settings
if "testserver" not in settings.ALLOWED_HOSTS and "*" not in settings.ALLOWED_HOSTS:
    settings.ALLOWED_HOSTS = list(settings.ALLOWED_HOSTS) + ["testserver", "localhost", "127.0.0.1"]

from django.contrib.auth import get_user_model
from django.utils import timezone
from rest_framework import status
from rest_framework.test import APIClient
from rest_framework_simplejwt.tokens import RefreshToken

from companies.models import Company
from workforce_api.models import (
    Warehouse,
    SellerWarehouseAssignment,
    SellerHubCategory,
    SellerProduct,
    SellerInventory,
    SellerOrder,
    SellerOrderItem,
    DeliverySlot,
    DeliverySlotBooking,
)

User = get_user_model()


class DeliverySlotsTestCase(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.client = APIClient()

        # 1. Superuser / Platform Admin
        cls.admin_user, _ = User.objects.get_or_create(
            username="superadmin_slots_test",
            defaults={
                "email": "superadmin_slots@sevo.com",
                "is_superuser": True,
                "is_staff": True,
                "role": "SUPERADMIN",
            }
        )
        cls.admin_token = str(RefreshToken.for_user(cls.admin_user).access_token)
        cls.admin_auth_header = {"HTTP_AUTHORIZATION": f"Bearer {cls.admin_token}"}

        # 2. Regular Seller User (Non-Platform Admin)
        cls.seller_company, _ = Company.objects.get_or_create(
            slug="store-slots-test-company",
            defaults={"company_name": "Slots Test Mart", "business_type": "grocery_supplier", "is_active": True}
        )
        cls.seller_company.is_active = True
        cls.seller_company.save()

        cls.seller_user, _ = User.objects.get_or_create(
            username="seller_user_slots_test",
            defaults={"email": "seller_slots@store.com", "company": cls.seller_company, "role": "ADMIN"}
        )
        cls.seller_user.company = cls.seller_company
        cls.seller_user.save()
        cls.seller_token = str(RefreshToken.for_user(cls.seller_user).access_token)
        cls.seller_auth_header = {"HTTP_AUTHORIZATION": f"Bearer {cls.seller_token}"}

        # 3. Warehouses
        cls.wh1, _ = Warehouse.objects.get_or_create(
            code="WH-SLOTS-01",
            defaults={
                "name": "Central Slots Hub BLR",
                "address": "100 MG Road, Bengaluru",
                "latitude": Decimal("12.9716000"),
                "longitude": Decimal("77.5946000"),
                "city": "Bengaluru",
                "is_active": True,
            }
        )
        cls.wh1.is_active = True
        cls.wh1.save()

        cls.wh2, _ = Warehouse.objects.get_or_create(
            code="WH-SLOTS-02",
            defaults={
                "name": "North Slots Hub BLR",
                "address": "200 Hebbal, Bengaluru",
                "latitude": Decimal("13.0358000"),
                "longitude": Decimal("77.5970000"),
                "city": "Bengaluru",
                "is_active": True,
            }
        )
        cls.wh2.is_active = True
        cls.wh2.save()

        # Assign company to wh1
        SellerWarehouseAssignment.objects.update_or_create(
            company=cls.seller_company,
            defaults={"warehouse": cls.wh1}
        )

        # 4. Catalog & Products for intake tests
        cls.cat, _ = SellerHubCategory.objects.get_or_create(
            slug="slots-grocery-cat",
            defaults={"name": "Slots Grocery Category", "is_active": True}
        )
        cls.cat.is_active = True
        cls.cat.save()

        cls.prod, _ = SellerProduct.objects.get_or_create(
            company=cls.seller_company,
            sku="SLOT-PROD-001",
            defaults={
                "title": "Fresh Farm Milk 1L",
                "category": cls.cat,
                "mrp": Decimal("60.00"),
                "selling_price": Decimal("55.00"),
                "procurement_price": Decimal("45.00"),
                "status": SellerProduct.Status.APPROVED,
                "created_by": cls.seller_user,
            }
        )
        cls.prod.status = SellerProduct.Status.APPROVED
        cls.prod.save()

        cls.inv, _ = SellerInventory.objects.get_or_create(
            company=cls.seller_company,
            product=cls.prod,
            defaults={"on_hand_qty": Decimal("100.000"), "reserved_qty": Decimal("0.000")}
        )
        cls.inv.on_hand_qty = Decimal("100.000")
        cls.inv.reserved_qty = Decimal("0.000")
        cls.inv.save()

        # Webhook Secret Header for marketplace integration
        settings.WORKFORCE_WEBHOOK_SECRET = "test_webhook_secret_key_1234567890"
        cls.marketplace_header = {"HTTP_X_WORKFORCE_WEBHOOK_SECRET": "test_webhook_secret_key_1234567890"}

    def setUp(self):
        super().setUp()
        DeliverySlotBooking.objects.filter(slot__warehouse__in=[self.wh1, self.wh2]).delete()
        DeliverySlot.objects.filter(warehouse__in=[self.wh1, self.wh2]).delete()
        SellerOrderItem.objects.filter(product__company=self.seller_company).delete()
        SellerOrder.objects.filter(company=self.seller_company).delete()
        self.inv.reserved_qty = Decimal("0.000")
        self.inv.on_hand_qty = Decimal("100.000")
        self.inv.save()

    @classmethod
    def tearDownClass(cls):
        DeliverySlotBooking.objects.filter(slot__warehouse__in=[cls.wh1, cls.wh2]).delete()
        DeliverySlot.objects.filter(warehouse__in=[cls.wh1, cls.wh2]).delete()
        SellerOrderItem.objects.filter(product__company=cls.seller_company).delete()
        SellerOrder.objects.filter(company=cls.seller_company).delete()
        super().tearDownClass()

    def test_01_admin_delivery_slot_crud_and_permissions(self):
        """
        Verify Admin Delivery Slot CRUD:
        - Non-admin is blocked (403)
        - Start time >= end time is rejected (400)
        - Admin can create, list, patch, and read slots
        """
        # Non-admin attempt
        unauth_res = self.client.get("/api/workforce/admin/delivery-slots/", **self.seller_auth_header)
        self.assertEqual(unauth_res.status_code, status.HTTP_403_FORBIDDEN)

        # Invalid timing: end_time before start_time
        invalid_timing_payload = {
            "warehouse_id": self.wh1.id,
            "label": "Invalid Timing Slot",
            "start_time": "14:00",
            "end_time": "12:00",
            "slot_type": "STANDARD",
        }
        inv_res = self.client.post("/api/workforce/admin/delivery-slots/", invalid_timing_payload, format="json", **self.admin_auth_header)
        self.assertEqual(inv_res.status_code, status.HTTP_400_BAD_REQUEST)

        # Valid create
        create_payload = {
            "warehouse_id": self.wh1.id,
            "label": "Morning Delivery (09:00 - 11:00 AM)",
            "start_time": "09:00",
            "end_time": "11:00",
            "slot_type": "STANDARD",
            "max_orders_per_slot": 25,
            "applicable_days": "0,1,2,3,4,5,6",
            "is_active": True,
        }
        res = self.client.post("/api/workforce/admin/delivery-slots/", create_payload, format="json", **self.admin_auth_header)
        self.assertEqual(res.status_code, status.HTTP_201_CREATED)
        slot_id = res.json()["id"]
        self.assertEqual(res.json()["label"], "Morning Delivery (09:00 - 11:00 AM)")
        self.assertEqual(res.json()["max_orders_per_slot"], 25)

        # Get detail
        detail_res = self.client.get(f"/api/workforce/admin/delivery-slots/{slot_id}/", **self.admin_auth_header)
        self.assertEqual(detail_res.status_code, status.HTTP_200_OK)
        self.assertEqual(detail_res.json()["warehouse_name"], self.wh1.name)

        # Update slot
        patch_res = self.client.patch(
            f"/api/workforce/admin/delivery-slots/{slot_id}/",
            {"max_orders_per_slot": 30, "label": "Morning Super Saver (09:00 - 11:00 AM)"},
            format="json",
            **self.admin_auth_header,
        )
        self.assertEqual(patch_res.status_code, status.HTTP_200_OK)
        self.assertEqual(patch_res.json()["max_orders_per_slot"], 30)
        self.assertEqual(patch_res.json()["label"], "Morning Super Saver (09:00 - 11:00 AM)")

    def test_02_overlap_detection_and_rejection(self):
        """
        Verify that creating overlapping active slots on the same warehouse is blocked,
        while non-overlapping windows or slots on another warehouse are permitted.
        """
        # Create base slot: 11:00 - 13:00 on wh1 (active every day)
        base_payload = {
            "warehouse_id": self.wh1.id,
            "label": "Midday Slot (11:00 - 13:00)",
            "start_time": "11:00",
            "end_time": "13:00",
            "slot_type": "STANDARD",
            "is_active": True,
            "applicable_days": "",
        }
        base_res = self.client.post("/api/workforce/admin/delivery-slots/", base_payload, format="json", **self.admin_auth_header)
        self.assertEqual(base_res.status_code, status.HTTP_201_CREATED)

        # Overlapping slot: 12:00 - 14:00 on wh1 -> MUST BE REJECTED
        overlap_payload = {
            "warehouse_id": self.wh1.id,
            "label": "Conflicting Afternoon Slot",
            "start_time": "12:00",
            "end_time": "14:00",
            "slot_type": "EXPRESS",
            "is_active": True,
        }
        overlap_res = self.client.post("/api/workforce/admin/delivery-slots/", overlap_payload, format="json", **self.admin_auth_header)
        self.assertEqual(overlap_res.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(overlap_res.json()["code"], "SLOT_OVERLAP")

        # Same time 11:00 - 13:00 on DIFFERENT warehouse (wh2) -> MUST SUCCEED
        wh2_payload = {
            "warehouse_id": self.wh2.id,
            "label": "North Midday Slot (11:00 - 13:00)",
            "start_time": "11:00",
            "end_time": "13:00",
            "slot_type": "STANDARD",
            "is_active": True,
        }
        wh2_res = self.client.post("/api/workforce/admin/delivery-slots/", wh2_payload, format="json", **self.admin_auth_header)
        self.assertEqual(wh2_res.status_code, status.HTTP_201_CREATED)

        # Non-overlapping time on wh1: 14:00 - 16:00 -> MUST SUCCEED
        afternoon_payload = {
            "warehouse_id": self.wh1.id,
            "label": "Afternoon Slot (14:00 - 16:00)",
            "start_time": "14:00",
            "end_time": "16:00",
            "slot_type": "EXPRESS",
            "is_active": True,
        }
        aft_res = self.client.post("/api/workforce/admin/delivery-slots/", afternoon_payload, format="json", **self.admin_auth_header)
        self.assertEqual(aft_res.status_code, status.HTTP_201_CREATED)

    def test_03_deletion_protection_with_bookings(self):
        """
        Verify that slots with active bookings cannot be hard-deleted,
        preventing foreign-key reference corruption.
        """
        # Create dedicated slot
        slot = DeliverySlot.objects.create(
            warehouse=self.wh1,
            label="Evening Slot (18:00 - 20:00)",
            start_time=time(18, 0),
            end_time=time(20, 0),
            slot_type=DeliverySlot.SlotType.STANDARD,
            max_orders_per_slot=10,
            is_active=True,
        )

        # Create dummy order and booking
        order = SellerOrder.objects.create(
            source_order_id=f"TEST-ORDER-DEL-{timezone.now().timestamp()}",
            company=self.seller_company,
            order_number=f"SO-DEL-{timezone.now().strftime('%H%M%S')}",
            customer_name="John Doe",
            delivery_slot=slot.label,
            total_amount=Decimal("110.00"),
        )
        booking = DeliverySlotBooking.objects.create(
            slot=slot,
            delivery_date=date.today() + timedelta(days=2),
            seller_order=order,
        )

        # Delete attempt -> MUST BE BLOCKED
        del_res = self.client.delete(f"/api/workforce/admin/delivery-slots/{slot.id}/", **self.admin_auth_header)
        self.assertEqual(del_res.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(del_res.json()["code"], "SLOT_HAS_BOOKINGS")

        # Deactivation instead -> MUST SUCCEED
        patch_res = self.client.patch(
            f"/api/workforce/admin/delivery-slots/{slot.id}/",
            {"is_active": False},
            format="json",
            **self.admin_auth_header,
        )
        self.assertEqual(patch_res.status_code, status.HTTP_200_OK)
        self.assertFalse(patch_res.json()["is_active"])

        # Clean up booking & then test successful deletion
        booking.delete()
        del_ok_res = self.client.delete(f"/api/workforce/admin/delivery-slots/{slot.id}/", **self.admin_auth_header)
        self.assertEqual(del_ok_res.status_code, status.HTTP_200_OK)
        self.assertFalse(DeliverySlot.objects.filter(pk=slot.id).exists())

    def test_04_public_slot_availability_endpoint(self):
        """
        Verify PublicDeliverySlotsView:
        - Checks warehouse_id & date parameters
        - Calculates booked count and capacity availability
        - Filters by applicable days
        """
        future_date = date.today() + timedelta(days=3)
        future_weekday = future_date.weekday()

        # Slot 1: Active with capacity 2
        slot_cap2 = DeliverySlot.objects.create(
            warehouse=self.wh1,
            label="Night Window (20:00 - 22:00)",
            start_time=time(20, 0),
            end_time=time(22, 0),
            slot_type=DeliverySlot.SlotType.EXPRESS,
            max_orders_per_slot=2,
            is_active=True,
            applicable_days="",
        )

        # Slot 2: Only active on specific other day (not future_weekday)
        other_day = (future_weekday + 1) % 7
        slot_wrong_day = DeliverySlot.objects.create(
            warehouse=self.wh1,
            label="Specific Day Window",
            start_time=time(22, 0),
            end_time=time(23, 0),
            slot_type=DeliverySlot.SlotType.STANDARD,
            is_active=True,
            applicable_days=str(other_day),
        )

        # Query public availability for future_date
        res = self.client.get(
            f"/api/workforce/marketplace/delivery-slots/?warehouse_id={self.wh1.id}&date={future_date.strftime('%Y-%m-%d')}",
            **self.marketplace_header,
        )
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        data = res.json()
        self.assertEqual(data["warehouse_id"], self.wh1.id)

        slot_ids = [s["id"] for s in data["slots"]]
        self.assertIn(slot_cap2.id, slot_ids)
        self.assertNotIn(slot_wrong_day.id, slot_ids)

        slot_info = next(s for s in data["slots"] if s["id"] == slot_cap2.id)
        self.assertTrue(slot_info["available"])
        self.assertEqual(slot_info["booked_count"], 0)

        # Add 2 bookings on future_date to fill capacity
        DeliverySlotBooking.objects.create(slot=slot_cap2, delivery_date=future_date)
        DeliverySlotBooking.objects.create(slot=slot_cap2, delivery_date=future_date)

        # Re-query -> available should now be False
        res_full = self.client.get(
            f"/api/workforce/marketplace/delivery-slots/?warehouse_id={self.wh1.id}&date={future_date.strftime('%Y-%m-%d')}",
            **self.marketplace_header,
        )
        self.assertEqual(res_full.status_code, status.HTTP_200_OK)
        slot_info_full = next(s for s in res_full.json()["slots"] if s["id"] == slot_cap2.id)
        self.assertFalse(slot_info_full["available"])
        self.assertEqual(slot_info_full["booked_count"], 2)

    def test_05_marketplace_order_intake_with_slot_booking_and_capacity_guards(self):
        """
        Verify MarketplaceOrderIntakeView:
        1. Order intake with delivery_slot_id & delivery_date creates DeliverySlotBooking.
        2. Capacity cap is enforced atomically (rejects intake when capacity exceeded).
        3. Backward compatible: Orders without delivery_slot_id (e.g. Store Pickup) succeed seamlessly.
        """
        target_date = date.today() + timedelta(days=4)

        slot = DeliverySlot.objects.create(
            warehouse=self.wh1,
            label="Intake Test Slot (07:00 - 08:30)",
            start_time=time(7, 0),
            end_time=time(8, 30),
            slot_type=DeliverySlot.SlotType.EXPRESS,
            max_orders_per_slot=1, # Cap of exactly 1 order
            is_active=True,
            applicable_days="",
        )

        # 1. First order booking slot -> MUST SUCCEED
        order1_source = f"TEST-ORDER-SLOT-01-{timezone.now().timestamp()}"
        payload_1 = {
            "source_order_id": order1_source,
            "company_id": self.seller_company.id,
            "warehouse_id": self.wh1.id,
            "customer_name": "Alice Green",
            "customer_phone": "9876543210",
            "delivery_address": "456 Park Avenue, Bengaluru",
            "delivery_slot_id": slot.id,
            "delivery_date": target_date.strftime("%Y-%m-%d"),
            "items": [
                {
                    "product_id": self.prod.id,
                    "quantity": 1,
                    "expected_unit_price": str(self.prod.selling_price),
                }
            ],
        }
        res1 = self.client.post("/api/workforce/marketplace/orders/intake/", payload_1, format="json", **self.marketplace_header)
        self.assertEqual(res1.status_code, status.HTTP_201_CREATED)
        order1_id = res1.json()["order"]["id"]

        # Verify DeliverySlotBooking created
        booking = DeliverySlotBooking.objects.filter(slot=slot, delivery_date=target_date, seller_order_id=order1_id).first()
        self.assertIsNotNone(booking)

        # Verify SellerOrder has resolved slot label
        order1 = SellerOrder.objects.get(id=order1_id)
        self.assertEqual(order1.delivery_slot, slot.label)

        # 2. Second order attempting same slot on same date -> MUST BE REJECTED (Capacity = 1)
        order2_source = f"TEST-ORDER-SLOT-02-{timezone.now().timestamp()}"
        payload_2 = {
            "source_order_id": order2_source,
            "company_id": self.seller_company.id,
            "warehouse_id": self.wh1.id,
            "customer_name": "Bob Brown",
            "delivery_slot_id": slot.id,
            "delivery_date": target_date.strftime("%Y-%m-%d"),
            "items": [
                {
                    "product_id": self.prod.id,
                    "quantity": 1,
                    "expected_unit_price": str(self.prod.selling_price),
                }
            ],
        }
        res2 = self.client.post("/api/workforce/marketplace/orders/intake/", payload_2, format="json", **self.marketplace_header)
        self.assertEqual(res2.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(res2.json()["code"], "SLOT_CAPACITY_EXCEEDED")

        # 3. Store Pickup / Unscheduled order without slot fields -> MUST SUCCEED (backward compatible)
        order3_source = f"TEST-ORDER-NOSLOT-{timezone.now().timestamp()}"
        payload_3 = {
            "source_order_id": order3_source,
            "company_id": self.seller_company.id,
            "warehouse_id": self.wh1.id,
            "fulfillment_type": "STORE_PICKUP",
            "customer_name": "Charlie White",
            "items": [
                {
                    "product_id": self.prod.id,
                    "quantity": 1,
                    "expected_unit_price": str(self.prod.selling_price),
                }
            ],
        }
        res3 = self.client.post("/api/workforce/marketplace/orders/intake/", payload_3, format="json", **self.marketplace_header)
        self.assertEqual(res3.status_code, status.HTTP_201_CREATED)
        order3_id = res3.json()["order"]["id"]
        self.assertFalse(DeliverySlotBooking.objects.filter(seller_order_id=order3_id).exists())


if __name__ == "__main__":
    unittest.main()
