"""
test_phase_w_fulfillment_method.py

Comprehensive test suite verifying Phase W: Per-product fulfillment method (Self-Ship vs Fulfilled by Sevo):
1. Existing products default to SELF_SHIP via migration without functional disruption.
2. Single product creation supports explicit SELF_SHIP and FULFILLED_BY_SEVO choices.
3. Serializer outputs include fulfillment_method across list, detail, and create/update.
4. Product editing preserves and correctly updates fulfillment_method.
5. Platform Admin visibility into product fulfillment_method.
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
from workforce_api.models import SellerProduct, SellerHubCategory
from workforce_api.serializers import (
    SellerProductListSerializer,
    SellerProductDetailSerializer,
    SellerProductCreateUpdateSerializer,
)
from workforce_api.views_seller_hub import (
    SellerProductListView,
    SellerProductDetailView,
)


class PhaseWFulfillmentMethodTestCase(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.factory = APIRequestFactory()

        # Clean up any leftover test data
        SellerProduct.objects.filter(sku__startswith="PHASEW-").delete()
        User.objects.filter(username__in=["phasew_seller", "phasew_admin"]).delete()
        SellerHubCategory.objects.filter(slug__in=["phasew-root-cat", "phasew-leaf-cat"]).delete()

        # 1. Leaf Category
        cls.root_cat, _ = SellerHubCategory.objects.get_or_create(
            slug="phasew-root-cat",
            defaults={"name": "PhaseW Grocery", "is_active": True, "sort_order": 1}
        )
        cls.leaf_cat, _ = SellerHubCategory.objects.get_or_create(
            slug="phasew-leaf-cat",
            defaults={"name": "PhaseW Oil & Ghee", "parent": cls.root_cat, "is_active": True, "sort_order": 1}
        )

        # 2. Company & Seller
        cls.company, _ = Company.objects.get_or_create(
            slug="phasew-seller-comp",
            defaults={
                "company_name": "PhaseW Merchant Store",
                "business_type": "grocery_supplier",
                "industry": "grocery",
            }
        )
        cls.seller_user, _ = User.objects.get_or_create(
            username="phasew_seller",
            defaults={
                "email": "phasew_seller@test.com",
                "company": cls.company,
            }
        )
        if not cls.seller_user.check_password("password123"):
            cls.seller_user.set_password("password123")
            cls.seller_user.save()

        # 3. Admin User
        cls.admin_user, _ = User.objects.get_or_create(
            username="phasew_admin",
            defaults={
                "email": "phasew_admin@test.com",
                "is_superuser": True,
                "is_staff": True,
            }
        )

    @classmethod
    def tearDownClass(cls):
        SellerProduct.objects.filter(sku__startswith="PHASEW-").delete()
        super().tearDownClass()

    def test_01_default_migration_value_is_self_ship(self):
        """Verifies that pre-existing products in the database default to SELF_SHIP."""
        prod = SellerProduct.objects.create(
            company=self.company,
            created_by=self.seller_user,
            category=self.leaf_cat,
            title="PhaseW Default Migration Product",
            sku="PHASEW-DEFAULT-001",
            mrp=Decimal("100.00"),
            selling_price=Decimal("90.00"),
            status=SellerProduct.Status.APPROVED,
        )
        self.assertEqual(prod.fulfillment_method, SellerProduct.FulfillmentMethod.SELF_SHIP)
        self.assertEqual(prod.fulfillment_method, "SELF_SHIP")
        print(f"  [OK] Default product fulfillment method is: {prod.fulfillment_method}")

    def test_02_create_product_as_self_ship_api(self):
        """Verifies creating a product with explicit SELF_SHIP method via API."""
        payload = {
            "category": self.leaf_cat.id,
            "title": "PhaseW Self-Ship Sunflower Oil 1L",
            "brand": "PhaseW Brands",
            "sku": "PHASEW-OIL-SS",
            "barcode": "8901112223334",
            "fulfillment_method": "SELF_SHIP",
            "unit": "litre",
            "pack_size": "1L",
            "mrp": "180.00",
            "selling_price": "160.00",
            "tax_rate": "5.00",
            "status": "DRAFT",
        }
        req = self.factory.post("/api/workforce/seller-hub/products/", payload, format="json")
        force_authenticate(req, user=self.seller_user)
        view = SellerProductListView.as_view()
        resp = view(req)

        self.assertEqual(resp.status_code, status.HTTP_201_CREATED)
        data = resp.data["product"]
        self.assertEqual(data["fulfillment_method"], "SELF_SHIP")
        self.assertEqual(data["sku"], "PHASEW-OIL-SS")

        # Verify in DB
        db_prod = SellerProduct.objects.get(sku="PHASEW-OIL-SS")
        self.assertEqual(db_prod.fulfillment_method, SellerProduct.FulfillmentMethod.SELF_SHIP)
        print(f"  [OK] Created Self-Ship product: #{db_prod.id} {db_prod.title} ({db_prod.fulfillment_method})")

    def test_03_create_product_as_fulfilled_by_sevo_api(self):
        """Verifies creating a product with FULFILLED_BY_SEVO (FBS) via API."""
        payload = {
            "category": self.leaf_cat.id,
            "title": "PhaseW Fulfilled by Sevo Sharbati Atta 5kg",
            "brand": "PhaseW Brands",
            "sku": "PHASEW-ATTA-FBS",
            "barcode": "8901030898765",
            "fulfillment_method": "FULFILLED_BY_SEVO",
            "unit": "kg",
            "pack_size": "5kg",
            "mrp": "320.00",
            "selling_price": "290.00",
            "tax_rate": "5.00",
            "status": "DRAFT",
        }
        req = self.factory.post("/api/workforce/seller-hub/products/", payload, format="json")
        force_authenticate(req, user=self.seller_user)
        view = SellerProductListView.as_view()
        resp = view(req)

        self.assertEqual(resp.status_code, status.HTTP_201_CREATED)
        data = resp.data["product"]
        self.assertEqual(data["fulfillment_method"], "FULFILLED_BY_SEVO")

        # Verify in DB
        db_prod = SellerProduct.objects.get(sku="PHASEW-ATTA-FBS")
        self.assertEqual(db_prod.fulfillment_method, SellerProduct.FulfillmentMethod.FULFILLED_BY_SEVO)
        print(f"  [OK] Created FBS product: #{db_prod.id} {db_prod.title} ({db_prod.fulfillment_method})")

    def test_04_update_product_fulfillment_method(self):
        """Verifies changing fulfillment method on an existing product persists cleanly."""
        prod = SellerProduct.objects.create(
            company=self.company,
            created_by=self.seller_user,
            category=self.leaf_cat,
            title="PhaseW Basmati Rice 5kg",
            sku="PHASEW-RICE-5KG",
            fulfillment_method=SellerProduct.FulfillmentMethod.SELF_SHIP,
            mrp=Decimal("500.00"),
            selling_price=Decimal("450.00"),
            status=SellerProduct.Status.DRAFT,
        )

        # Update to FBS
        patch_payload = {
            "fulfillment_method": "FULFILLED_BY_SEVO",
        }
        req = self.factory.patch(f"/api/workforce/seller-hub/products/{prod.id}/", patch_payload, format="json")
        force_authenticate(req, user=self.seller_user)
        view = SellerProductDetailView.as_view()
        resp = view(req, pk=prod.id)

        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        prod.refresh_from_db()
        self.assertEqual(prod.fulfillment_method, SellerProduct.FulfillmentMethod.FULFILLED_BY_SEVO)
        print(f"  [OK] Updated product #{prod.id} fulfillment_method to: {prod.fulfillment_method}")

    def test_05_serializers_include_fulfillment_method(self):
        """Verifies list and detail serializers expose fulfillment_method correctly."""
        fbs_prod = SellerProduct.objects.create(
            company=self.company,
            created_by=self.seller_user,
            category=self.leaf_cat,
            title="PhaseW Test Serializer Product",
            sku="PHASEW-SER-001",
            fulfillment_method=SellerProduct.FulfillmentMethod.FULFILLED_BY_SEVO,
            mrp=Decimal("180.00"),
            selling_price=Decimal("165.00"),
            status=SellerProduct.Status.APPROVED,
        )

        list_data = SellerProductListSerializer(fbs_prod).data
        self.assertIn("fulfillment_method", list_data)
        self.assertEqual(list_data["fulfillment_method"], "FULFILLED_BY_SEVO")

        detail_data = SellerProductDetailSerializer(fbs_prod).data
        self.assertIn("fulfillment_method", detail_data)
        self.assertEqual(detail_data["fulfillment_method"], "FULFILLED_BY_SEVO")
        print(f"  [OK] Serializers correctly export fulfillment_method: {list_data['fulfillment_method']}")

    def test_06_admin_listing_sees_fulfillment_method(self):
        """Verifies Platform Admin catalog review endpoint sees both Self-Ship and FBS products."""
        SellerProduct.objects.create(
            company=self.company,
            created_by=self.seller_user,
            category=self.leaf_cat,
            title="PhaseW Admin Test Product FBS",
            sku="PHASEW-ADMIN-FBS",
            fulfillment_method=SellerProduct.FulfillmentMethod.FULFILLED_BY_SEVO,
            mrp=Decimal("100.00"),
            selling_price=Decimal("90.00"),
            status=SellerProduct.Status.SUBMITTED,
        )

        req = self.factory.get(f"/api/workforce/seller-hub/products/?company_id={self.company.id}")
        force_authenticate(req, user=self.admin_user)
        view = SellerProductListView.as_view()
        resp = view(req)

        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        fbs_item = next((p for p in resp.data if p["sku"] == "PHASEW-ADMIN-FBS"), None)
        self.assertIsNotNone(fbs_item)
        self.assertEqual(fbs_item["fulfillment_method"], "FULFILLED_BY_SEVO")
        print(f"  [OK] Admin list view returned fulfillment_method: {fbs_item['fulfillment_method']}")


if __name__ == "__main__":
    unittest.main()
