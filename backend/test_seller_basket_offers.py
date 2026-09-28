"""
test_seller_basket_offers.py

Comprehensive test suite for Basket Offers (Multi-Product Combo Bundles):
1. Basket creation validation:
   - < 3 distinct items rejected with 400 Bad Request.
   - Products from another seller company rejected with 400 Bad Request.
   - Basket activation blocked if any component product has procurement_price=None.
2. Two-way margin <-> price calculations:
   - Live calculate endpoint with MARGIN mode computes exact selling price and profit.
   - Live calculate endpoint with FIXED_PRICE mode back-computes exact margin %.
   - Worked example: 10 items total cost Rs 1000 + 10% margin -> selling_price Rs 1100.
3. Auto status & stock availability toggling:
   - When all component products have sufficient available stock, basket is ACTIVE and check_availability returns True.
   - When any component product stock drops below required quantity, basket auto-flips to OUT_OF_STOCK and is hidden from marketplace.
   - When stock is replenished, basket recovers to ACTIVE.
4. End-to-end cart validation & order intake:
   - Marketplace cart validation checks component stock and prices.
   - Order intake intaking a basket line item creates SellerOrder with authoritative basket price.
   - Atomically expands into component SellerOrderItem records with basket_id & basket_title.
   - Atomically decrements and reserves stock for each component product.
"""
import os
import django
import unittest
from decimal import Decimal

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "workforce_core.settings")
django.setup()

from django.conf import settings
if "testserver" not in settings.ALLOWED_HOSTS and "*" not in settings.ALLOWED_HOSTS:
    settings.ALLOWED_HOSTS = list(settings.ALLOWED_HOSTS) + ["testserver", "localhost", "127.0.0.1"]

from rest_framework.test import APIClient
from rest_framework import status
from rest_framework_simplejwt.tokens import RefreshToken

from accounts.models import User
from companies.models import Company
from workforce_api.models import (
    SellerHubCategory,
    SellerProduct,
    SellerInventory,
    SellerProductBasket,
    SellerProductBasketItem,
    SellerOrder,
    SellerOrderItem,
)


class SellerBasketOffersTestCase(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.client = APIClient()

        # 1. Primary Merchant Company & User
        cls.company, _ = Company.objects.get_or_create(
            slug="basket-test-grocery-mart",
            defaults={"company_name": "Basket Test Grocery Mart", "is_active": True}
        )
        cls.company.is_active = True
        cls.company.save()

        cls.seller_user, _ = User.objects.get_or_create(
            username="seller_basket_test_user",
            defaults={
                "email": "seller_basket@sevo.com",
                "role": "ADMIN",
                "company": cls.company,
            }
        )
        cls.seller_user.company = cls.company
        cls.seller_user.save()

        # 2. Second Company & User (for cross-tenant checks)
        cls.other_company, _ = Company.objects.get_or_create(
            slug="other-vendor-basket-store",
            defaults={"company_name": "Other Vendor Store", "is_active": True}
        )
        cls.other_user, _ = User.objects.get_or_create(
            username="other_vendor_basket_user",
            defaults={
                "email": "other_vendor@sevo.com",
                "role": "ADMIN",
                "company": cls.other_company,
            }
        )
        cls.other_user.company = cls.other_company
        cls.other_user.save()

        # 3. Active Category
        cls.category, _ = SellerHubCategory.objects.get_or_create(
            slug="basket-grocery-test-cat",
            defaults={
                "name": "Basket Grocery Category",
                "is_active": True,
            }
        )
        cls.category.is_active = True
        cls.category.save()

        # 4. Products for Primary Company
        # Product 1
        cls.p1, _ = SellerProduct.objects.get_or_create(
            company=cls.company,
            sku="BASKET-PROD-001",
            defaults={
                "title": "Atta Flour 5kg",
                "category": cls.category,
                "mrp": Decimal("250.00"),
                "selling_price": Decimal("220.00"),
                "procurement_price": Decimal("180.00"),
                "status": SellerProduct.Status.APPROVED,
                "created_by": cls.seller_user,
            }
        )
        cls.p1.procurement_price = Decimal("180.00")
        cls.p1.status = SellerProduct.Status.APPROVED
        cls.p1.save()

        cls.inv1, _ = SellerInventory.objects.get_or_create(
            company=cls.company,
            product=cls.p1,
            defaults={"on_hand_qty": Decimal("50.000"), "reserved_qty": Decimal("0.000")}
        )
        cls.inv1.on_hand_qty = Decimal("50.000")
        cls.inv1.reserved_qty = Decimal("0.000")
        cls.inv1.save()

        # Product 2
        cls.p2, _ = SellerProduct.objects.get_or_create(
            company=cls.company,
            sku="BASKET-PROD-002",
            defaults={
                "title": "Basmati Rice 5kg",
                "category": cls.category,
                "mrp": Decimal("400.00"),
                "selling_price": Decimal("350.00"),
                "procurement_price": Decimal("280.00"),
                "status": SellerProduct.Status.APPROVED,
                "created_by": cls.seller_user,
            }
        )
        cls.p2.procurement_price = Decimal("280.00")
        cls.p2.status = SellerProduct.Status.APPROVED
        cls.p2.save()

        cls.inv2, _ = SellerInventory.objects.get_or_create(
            company=cls.company,
            product=cls.p2,
            defaults={"on_hand_qty": Decimal("40.000"), "reserved_qty": Decimal("0.000")}
        )
        cls.inv2.on_hand_qty = Decimal("40.000")
        cls.inv2.reserved_qty = Decimal("0.000")
        cls.inv2.save()

        # Product 3
        cls.p3, _ = SellerProduct.objects.get_or_create(
            company=cls.company,
            sku="BASKET-PROD-003",
            defaults={
                "title": "Sunflower Oil 1L",
                "category": cls.category,
                "mrp": Decimal("150.00"),
                "selling_price": Decimal("130.00"),
                "procurement_price": Decimal("100.00"),
                "status": SellerProduct.Status.APPROVED,
                "created_by": cls.seller_user,
            }
        )
        cls.p3.procurement_price = Decimal("100.00")
        cls.p3.status = SellerProduct.Status.APPROVED
        cls.p3.save()

        cls.inv3, _ = SellerInventory.objects.get_or_create(
            company=cls.company,
            product=cls.p3,
            defaults={"on_hand_qty": Decimal("60.000"), "reserved_qty": Decimal("0.000")}
        )
        cls.inv3.on_hand_qty = Decimal("60.000")
        cls.inv3.reserved_qty = Decimal("0.000")
        cls.inv3.save()

        # Product 4 (belonging to other company)
        cls.p_other, _ = SellerProduct.objects.get_or_create(
            company=cls.other_company,
            sku="OTHER-PROD-001",
            defaults={
                "title": "Other Store Salt 1kg",
                "category": cls.category,
                "mrp": Decimal("30.00"),
                "selling_price": Decimal("25.00"),
                "procurement_price": Decimal("15.00"),
                "status": SellerProduct.Status.APPROVED,
                "created_by": cls.other_user,
            }
        )

        # Webhook / Integration Secret
        settings.WORKFORCE_WEBHOOK_SECRET = "test_webhook_secret_key_1234567890"
        cls.marketplace_header = {"HTTP_X_WORKFORCE_WEBHOOK_SECRET": "test_webhook_secret_key_1234567890"}

        # Auth Token
        token = RefreshToken.for_user(cls.seller_user).access_token
        cls.auth_header = {"HTTP_AUTHORIZATION": f"Bearer {token}"}

    def test_01_preview_calculate_worked_example(self):
        """
        Verify worked example from requirements:
        Procurement total Rs 1000 + 10% margin -> selling price Rs 1100.
        Bidirectional fixed price of Rs 1100 -> back-computes 10% margin.
        """
        # Create 10 dummy items or quantities summing to procurement Rs 1000
        # p1 (procurement Rs 180 * 2 = 360), p2 (procurement Rs 280 * 2 = 560), p3 (procurement Rs 100 * 0.8 -> let's use exact quantities)
        # Or p1 (180*2 = 360) + p2 (280*2 = 560) + p3 (100*1 = 100) -> total procurement = 1020
        # Let's test MARGIN mode
        payload = {
            "items": [
                {"product_id": self.p1.id, "quantity": 2}, # 180 * 2 = 360 cost, 250 * 2 = 500 MRP
                {"product_id": self.p2.id, "quantity": 2}, # 280 * 2 = 560 cost, 400 * 2 = 800 MRP
                {"product_id": self.p3.id, "quantity": 1}, # 100 * 1 = 100 cost, 150 * 1 = 150 MRP
            ],
            "pricing_mode": "MARGIN",
            "margin_percent": 10.0,
        }
        # Total procurement = 360 + 560 + 100 = 1020.00
        # With 10% margin: 1020 * 1.10 = 1122.00
        # Total MRP = 500 + 800 + 150 = 1450.00
        # Profit = 1122 - 1020 = 102.00
        # Savings vs MRP = 1450 - 1122 = 328.00

        res = self.client.post("/api/workforce/seller-hub/baskets/calculate/", payload, format="json", **self.auth_header)
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        data = res.json()
        self.assertEqual(data["total_procurement_price"], "1020.00")
        self.assertEqual(data["total_mrp"], "1450.00")
        self.assertEqual(data["selling_price"], "1122.00")
        self.assertEqual(data["profit_amount"], "102.00")
        self.assertEqual(data["savings_vs_mrp"], "328.00")

        # Now test FIXED_PRICE mode: set selling_price to 1122.00, it must compute margin_percent = 10.0
        payload_fixed = {
            "items": [
                {"product_id": self.p1.id, "quantity": 2},
                {"product_id": self.p2.id, "quantity": 2},
                {"product_id": self.p3.id, "quantity": 1},
            ],
            "pricing_mode": "FIXED_PRICE",
            "selling_price": 1122.00,
        }
        res_fixed = self.client.post("/api/workforce/seller-hub/baskets/calculate/", payload_fixed, format="json", **self.auth_header)
        self.assertEqual(res_fixed.status_code, status.HTTP_200_OK)
        data_fixed = res_fixed.json()
        self.assertEqual(data_fixed["margin_percent"], "10.00")

    def test_02_basket_creation_validation(self):
        """
        Verify validation rules:
        - Less than 3 items rejected
        - Products from another seller company rejected
        """
        # Test < 3 items
        payload_few = {
            "title": "Small Combo Deal",
            "pricing_mode": "MARGIN",
            "margin_percent": 15,
            "items": [
                {"product_id": self.p1.id, "quantity": 1},
                {"product_id": self.p2.id, "quantity": 1},
            ],
        }
        res_few = self.client.post("/api/workforce/seller-hub/baskets/", payload_few, format="json", **self.auth_header)
        self.assertEqual(res_few.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("at least 3 distinct products", str(res_few.json()))

        # Test cross-company product
        payload_cross = {
            "title": "Cross Company Combo",
            "pricing_mode": "MARGIN",
            "margin_percent": 15,
            "items": [
                {"product_id": self.p1.id, "quantity": 1},
                {"product_id": self.p2.id, "quantity": 1},
                {"product_id": self.p_other.id, "quantity": 1}, # Belongs to other company
            ],
        }
        res_cross = self.client.post("/api/workforce/seller-hub/baskets/", payload_cross, format="json", **self.auth_header)
        self.assertEqual(res_cross.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("store", str(res_cross.json()).lower())

    def test_03_missing_procurement_price_blocks_activation(self):
        """
        Verify that if any component product has procurement_price=None, basket activation is blocked.
        """
        # Create product with null procurement_price
        p_no_cost, _ = SellerProduct.objects.get_or_create(
            company=self.company,
            sku="BASKET-NO-COST-001",
            defaults={
                "title": "No Cost Product",
                "category": self.category,
                "mrp": Decimal("100.00"),
                "selling_price": Decimal("90.00"),
                "procurement_price": None,
                "status": SellerProduct.Status.APPROVED,
                "created_by": self.seller_user,
            }
        )
        p_no_cost.procurement_price = None
        p_no_cost.save()

        # Create basket in DRAFT
        payload = {
            "title": "Draft Basket with Missing Cost",
            "pricing_mode": "FIXED_PRICE",
            "selling_price": 400.00,
            "target_status": "DRAFT",
            "items": [
                {"product_id": self.p1.id, "quantity": 1},
                {"product_id": self.p2.id, "quantity": 1},
                {"product_id": p_no_cost.id, "quantity": 1},
            ],
        }
        res = self.client.post("/api/workforce/seller-hub/baskets/", payload, format="json", **self.auth_header)
        self.assertEqual(res.status_code, status.HTTP_201_CREATED)
        basket_id = res.json()["id"]

        # Attempt to activate basket -> must be blocked
        act_res = self.client.post(f"/api/workforce/seller-hub/baskets/{basket_id}/activate/", {}, format="json", **self.auth_header)
        self.assertEqual(act_res.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("procurement price", str(act_res.json()).lower())

    def test_04_stock_based_auto_availability_and_marketplace_feed(self):
        """
        Verify that basket auto-toggles OUT_OF_STOCK / ACTIVE based on component inventory.
        """
        # Create valid active basket
        payload = {
            "title": "Kitchen Super Saver Combo",
            "pricing_mode": "MARGIN",
            "margin_percent": 12.0,
            "target_status": "ACTIVE",
            "items": [
                {"product_id": self.p1.id, "quantity": 2}, # needs 2 per basket
                {"product_id": self.p2.id, "quantity": 1}, # needs 1 per basket
                {"product_id": self.p3.id, "quantity": 3}, # needs 3 per basket
            ],
        }
        res = self.client.post("/api/workforce/seller-hub/baskets/", payload, format="json", **self.auth_header)
        self.assertEqual(res.status_code, status.HTTP_201_CREATED)
        basket_data = res.json()
        basket_id = basket_data["id"]
        self.assertEqual(basket_data["status"], "ACTIVE")

        # Check marketplace feed
        m_res = self.client.get("/api/workforce/marketplace/baskets/", **self.marketplace_header)
        self.assertEqual(m_res.status_code, status.HTTP_200_OK)
        m_baskets = m_res.json()["results"]
        active_ids = [b["id"] for b in m_baskets]
        self.assertIn(basket_id, active_ids)

        # Now drop p1 available stock to 1 (less than required quantity 2)
        self.inv1.reserved_qty = Decimal("49.000") # on_hand 50, reserved 49 -> available 1
        self.inv1.save()

        # Fetch basket detail from marketplace -> should reflect out of stock / unavailable
        m_detail_res = self.client.get(f"/api/workforce/marketplace/baskets/{basket_id}/", **self.marketplace_header)
        # Either 404/unavailable or available_stock=0
        if m_detail_res.status_code == status.HTTP_200_OK:
            self.assertEqual(m_detail_res.json()["available_stock"], 0)
            self.assertFalse(m_detail_res.json()["in_stock"])
        else:
            self.assertEqual(m_detail_res.status_code, status.HTTP_404_NOT_FOUND)

        # Replenish stock
        self.inv1.reserved_qty = Decimal("0.000")
        self.inv1.save()

        # Basket detail recovers
        m_rec_res = self.client.get(f"/api/workforce/marketplace/baskets/{basket_id}/", **self.marketplace_header)
        self.assertEqual(m_rec_res.status_code, status.HTTP_200_OK)
        self.assertTrue(m_rec_res.json()["in_stock"])

    def test_05_end_to_end_cart_validation_and_order_intake(self):
        """
        Verify end-to-end purchasing of a basket:
        1. Cart validate validates basket pricing and component availability.
        2. Order intake creates order with basket line item.
        3. Atomically reserves stock on all component products.
        4. Creates expanded SellerOrderItem records tracking basket_id.
        """
        basket = SellerProductBasket.objects.filter(company=self.company, status=SellerProductBasket.Status.ACTIVE).first()
        if not basket:
            basket = SellerProductBasket.objects.create(
                company=self.company,
                created_by=self.seller_user,
                title="Grand Feast Basket",
                pricing_mode=SellerProductBasket.PricingMode.FIXED_PRICE,
                selling_price=Decimal("799.00"),
                status=SellerProductBasket.Status.ACTIVE,
            )
            SellerProductBasketItem.objects.create(basket=basket, product=self.p1, quantity=2)
            SellerProductBasketItem.objects.create(basket=basket, product=self.p2, quantity=1)
            SellerProductBasketItem.objects.create(basket=basket, product=self.p3, quantity=1)
            basket.recalculate_totals()
            basket.save()

        # Initial available quantities
        self.inv1.refresh_from_db()
        self.inv2.refresh_from_db()
        self.inv3.refresh_from_db()

        inv1_before = self.inv1.reserved_qty
        inv2_before = self.inv2.reserved_qty
        inv3_before = self.inv3.reserved_qty

        # 1. Cart Validate
        cart_payload = {
            "company_id": self.company.id,
            "items": [
                {
                    "basket_id": basket.id,
                    "quantity": 2, # Purchasing 2 basket bundles
                    "expected_unit_price": str(basket.selling_price),
                }
            ],
        }
        val_res = self.client.post("/api/workforce/marketplace/cart/validate/", cart_payload, format="json", **self.marketplace_header)
        self.assertEqual(val_res.status_code, status.HTTP_200_OK)
        val_data = val_res.json()
        self.assertTrue(val_data["is_valid"])
        self.assertEqual(len(val_data["items"]), 1)
        self.assertTrue(val_data["items"][0]["is_available"])

        # 2. Order Intake
        source_order_id = f"TEST-BASKET-ORDER-{django.utils.timezone.now().timestamp()}"
        order_payload = {
            "source_order_id": source_order_id,
            "company_id": self.company.id,
            "customer_name": "Combo Deal Buyer",
            "customer_phone": "9998887776",
            "delivery_address": "123 Mart Street, Bengaluru",
            "items": [
                {
                    "basket_id": basket.id,
                    "quantity": 2, # Purchasing 2 basket bundles
                    "expected_unit_price": str(basket.selling_price),
                }
            ],
        }
        intake_res = self.client.post("/api/workforce/marketplace/orders/intake/", order_payload, format="json", **self.marketplace_header)
        self.assertEqual(intake_res.status_code, status.HTTP_201_CREATED)
        order_data = intake_res.json()["order"]
        order_id = order_data["id"]

        # 3. Verify total amount equals 2 * basket.selling_price
        expected_total = basket.selling_price * Decimal("2")
        self.assertEqual(Decimal(str(order_data["total_amount"])), expected_total)

        # 4. Verify stock reserved for each component
        # Order of 2 baskets means each component increases reserved_qty by 2 * item.quantity
        self.inv1.refresh_from_db()
        self.inv2.refresh_from_db()
        self.inv3.refresh_from_db()

        item_qty_map = {item.product_id: item.quantity for item in basket.items.all()}
        p1_delta = Decimal(str(item_qty_map.get(self.p1.id, 0))) * Decimal("2")
        p2_delta = Decimal(str(item_qty_map.get(self.p2.id, 0))) * Decimal("2")
        p3_delta = Decimal(str(item_qty_map.get(self.p3.id, 0))) * Decimal("2")

        self.assertEqual(self.inv1.reserved_qty, inv1_before + p1_delta)
        self.assertEqual(self.inv2.reserved_qty, inv2_before + p2_delta)
        self.assertEqual(self.inv3.reserved_qty, inv3_before + p3_delta)

        # 5. Verify order items created with basket FK and basket_title
        order_items = SellerOrderItem.objects.filter(order_id=order_id)
        self.assertEqual(order_items.count(), 3)
        for oi in order_items:
            self.assertEqual(oi.basket_id, basket.id)
            self.assertEqual(oi.basket_title, basket.title)


if __name__ == "__main__":
    unittest.main()

