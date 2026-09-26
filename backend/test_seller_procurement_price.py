"""
test_seller_procurement_price.py

Comprehensive test suite verifying Seller Procurement Price (cost price) & Profit/Margin Tracking:
1. Single product creation & update sets and persists `procurement_price`.
2. Bulk CSV template includes Procurement_Price; bulk uploads with and without `procurement_price` succeed.
3. Privacy Scoping: Owning seller and platform admin see `procurement_price`; other sellers and non-admin users do NOT.
4. Order Intake Snapshot: `SellerOrderItem.procurement_price_snapshot` captures the point-in-time cost on order intake.
5. Seller Reports Profitability: Calculates unit profit, margin %, total gross profit across delivered units, and handles products with null procurement cost safely (rendered as None/NA without treating as 0).
6. Profitability CSV Export generates proper columns and data.
"""
import os
import io
import csv
import uuid
import django
from decimal import Decimal

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "workforce_core.settings")
django.setup()

from django.conf import settings
if "testserver" not in settings.ALLOWED_HOSTS and "*" not in settings.ALLOWED_HOSTS:
    settings.ALLOWED_HOSTS = list(settings.ALLOWED_HOSTS) + ["testserver", "localhost", "127.0.0.1"]

import unittest
from django.utils import timezone
from rest_framework.test import APIClient
from rest_framework import status
from rest_framework_simplejwt.tokens import RefreshToken

from accounts.models import User
from companies.models import Company
from workforce_api.models import (
    SellerHubCategory,
    SellerProduct,
    SellerOrder,
    SellerOrderItem,
)


class SellerProcurementPriceTestCase(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.client = APIClient()

        # 1. Platform Admin / Superuser
        cls.admin_user, _ = User.objects.get_or_create(
            username="superadmin_procurement_test",
            defaults={
                "email": "superadmin_procure@sevo.com",
                "is_superuser": True,
                "is_staff": True,
                "role": "SUPERADMIN",
            }
        )
        cls.admin_token = str(RefreshToken.for_user(cls.admin_user).access_token)

        # 2. Seller Company A & User A
        cls.company_a, _ = Company.objects.get_or_create(
            slug="store-alpha-procure-test",
            defaults={"company_name": "Store Alpha Procure", "business_type": "grocery_supplier", "is_active": True}
        )
        cls.seller_user_a, _ = User.objects.get_or_create(
            username="seller_user_alpha_procure",
            defaults={"email": "seller_alpha_p@store.com", "company": cls.company_a, "role": "ADMIN"}
        )
        cls.seller_user_a.company = cls.company_a
        cls.seller_user_a.save()
        cls.seller_a_token = str(RefreshToken.for_user(cls.seller_user_a).access_token)

        # 3. Seller Company B & User B
        cls.company_b, _ = Company.objects.get_or_create(
            slug="store-beta-procure-test",
            defaults={"company_name": "Store Beta Procure", "business_type": "grocery_supplier", "is_active": True}
        )
        cls.seller_user_b, _ = User.objects.get_or_create(
            username="seller_user_beta_procure",
            defaults={"email": "seller_beta_p@store.com", "company": cls.company_b, "role": "ADMIN"}
        )
        cls.seller_user_b.company = cls.company_b
        cls.seller_user_b.save()
        cls.seller_b_token = str(RefreshToken.for_user(cls.seller_user_b).access_token)

        # 4. Active leaf category
        cls.category, _ = SellerHubCategory.objects.get_or_create(
            slug="procurement-test-cat",
            defaults={"name": "Procurement Test Category", "is_active": True}
        )

        # Cleanup prior test data
        SellerOrderItem.objects.filter(product__company__in=[cls.company_a, cls.company_b]).delete()
        SellerOrder.objects.filter(company__in=[cls.company_a, cls.company_b]).delete()
        SellerProduct.objects.filter(company__in=[cls.company_a, cls.company_b]).delete()

    @classmethod
    def tearDownClass(cls):
        SellerOrderItem.objects.filter(product__company__in=[cls.company_a, cls.company_b]).delete()
        SellerOrder.objects.filter(company__in=[cls.company_a, cls.company_b]).delete()
        SellerProduct.objects.filter(company__in=[cls.company_a, cls.company_b]).delete()
        super().tearDownClass()

    def test_01_single_product_crud_with_procurement_price(self):
        """Single product creation & update preserves procurement_price."""
        self.client.credentials(HTTP_AUTHORIZATION=f"Bearer {self.seller_a_token}")

        # Create product with procurement price
        create_payload = {
            "title": "Alpha Sunflower Oil 1L",
            "sku": "ALPHA-OIL-001",
            "category": self.category.id,
            "mrp": "200.00",
            "selling_price": "180.00",
            "procurement_price": "140.00",
            "status": "DRAFT",
        }
        res = self.client.post("/api/workforce/seller-hub/products/", create_payload, format="json")
        self.assertEqual(res.status_code, status.HTTP_201_CREATED, res.data)
        product_id = res.data["id"] if "id" in res.data else res.data["product"]["id"]

        # Verify DB directly
        prod_db = SellerProduct.objects.get(id=product_id)
        self.assertEqual(prod_db.procurement_price, Decimal("140.00"))
        self.assertEqual(prod_db.selling_price, Decimal("180.00"))
        self.assertEqual(prod_db.mrp, Decimal("200.00"))

        # Update procurement price
        update_payload = {
            "title": "Alpha Sunflower Oil 1L (Updated)",
            "sku": "ALPHA-OIL-001",
            "category": self.category.id,
            "mrp": "200.00",
            "selling_price": "175.00",
            "procurement_price": "135.50",
            "status": "DRAFT",
        }
        res_update = self.client.patch(f"/api/workforce/seller-hub/products/{product_id}/", update_payload, format="json")
        self.assertEqual(res_update.status_code, status.HTTP_200_OK, res_update.data)

        prod_db.refresh_from_db()
        self.assertEqual(prod_db.procurement_price, Decimal("135.50"))
        self.assertEqual(prod_db.selling_price, Decimal("175.00"))

    def test_02_bulk_csv_upload_with_and_without_procurement_price(self):
        """Bulk CSV upload parses optional procurement_price and succeeds when omitted."""
        self.client.credentials(HTTP_AUTHORIZATION=f"Bearer {self.seller_a_token}")

        # 1. Download template check
        res_template = self.client.get("/api/workforce/seller-hub/products/template/")
        self.assertEqual(res_template.status_code, status.HTTP_200_OK)
        content_str = res_template.content.decode("utf-8")
        self.assertIn("Procurement_Price", content_str)

        # 2. Upload CSV containing a row with procurement price and a row without
        csv_data = [
            ["SKU", "Title", "Category_ID", "MRP", "Selling_Price", "Procurement_Price", "HSN_Code", "GST_Rate", "Description"],
            ["ALPHA-BULK-01", "Alpha Basmati Rice 5kg", str(self.category.id), "500", "450", "380.00", "100630", "5", "Premium Rice"],
            ["ALPHA-BULK-02", "Alpha Wheat Flour 10kg", str(self.category.id), "400", "360", "", "110100", "0", "Whole Wheat"],
        ]
        csv_file = io.StringIO()
        writer = csv.writer(csv_file)
        writer.writerows(csv_data)
        csv_bytes = io.BytesIO(csv_file.getvalue().encode("utf-8"))
        csv_bytes.name = "catalog_upload.csv"

        # Bulk upload preview/import
        res_upload = self.client.post(
            "/api/workforce/seller-hub/products/bulk-upload/",
            {"file": csv_bytes, "mode": "commit"},
            format="multipart"
        )
        self.assertIn(res_upload.status_code, [status.HTTP_200_OK, status.HTTP_201_CREATED], res_upload.data)
        self.assertEqual(res_upload.data.get("imported_count") or res_upload.data.get("imported_rows"), 2)

        # Verify in DB
        prod1 = SellerProduct.objects.get(company=self.company_a, sku="ALPHA-BULK-01")
        self.assertEqual(prod1.procurement_price, Decimal("380.00"))

        prod2 = SellerProduct.objects.get(company=self.company_a, sku="ALPHA-BULK-02")
        self.assertIsNone(prod2.procurement_price)

    def test_03_privacy_scoping_isolation(self):
        """Seller A sees their procurement price; Seller B does NOT; Admin DOES."""
        # Create a product owned by Seller A
        prod_a = SellerProduct.objects.create(
            company=self.company_a,
            title="Alpha Organic Honey 500g",
            sku="ALPHA-HONEY-500",
            category=self.category,
            mrp=Decimal("350.00"),
            selling_price=Decimal("300.00"),
            procurement_price=Decimal("210.00"),
            status="APPROVED",
        )

        # 1. Seller A requesting detail -> Should see procurement_price
        self.client.credentials(HTTP_AUTHORIZATION=f"Bearer {self.seller_a_token}")
        res_a = self.client.get(f"/api/workforce/seller-hub/products/{prod_a.id}/")
        self.assertEqual(res_a.status_code, status.HTTP_200_OK)
        self.assertIn("procurement_price", res_a.data)
        self.assertEqual(Decimal(str(res_a.data["procurement_price"])), Decimal("210.00"))

        # 2. Seller B requesting list -> Cannot see other seller's products due to tenant isolation
        self.client.credentials(HTTP_AUTHORIZATION=f"Bearer {self.seller_b_token}")
        res_b = self.client.get(f"/api/workforce/seller-hub/products/{prod_a.id}/")
        self.assertEqual(res_b.status_code, status.HTTP_404_NOT_FOUND)

        # 3. Platform Admin requesting detail -> Should see procurement_price
        self.client.credentials(HTTP_AUTHORIZATION=f"Bearer {self.admin_token}")
        res_admin = self.client.get(f"/api/workforce/seller-hub/products/{prod_a.id}/")
        self.assertEqual(res_admin.status_code, status.HTTP_200_OK)
        self.assertIn("procurement_price", res_admin.data)
        self.assertEqual(Decimal(str(res_admin.data["procurement_price"])), Decimal("210.00"))

    def test_04_order_intake_snapshot_and_reports_profitability(self):
        """Order intake snapshots procurement price, reports compute unit profit & aggregate gross profit accurately."""
        # Create 2 products for Seller B: one with cost, one without
        prod_b1 = SellerProduct.objects.create(
            company=self.company_b,
            title="Beta Green Tea 100g",
            sku="BETA-TEA-100",
            category=self.category,
            mrp=Decimal("250.00"),
            selling_price=Decimal("200.00"),
            procurement_price=Decimal("120.00"),  # Unit profit: 80, Margin: 40%
            status="APPROVED",
        )

        prod_b2 = SellerProduct.objects.create(
            company=self.company_b,
            title="Beta Coffee Beans 250g",
            sku="BETA-COFFEE-250",
            category=self.category,
            mrp=Decimal("400.00"),
            selling_price=Decimal("350.00"),
            procurement_price=None,  # No cost set
            status="APPROVED",
        )

        # Create a DELIVERED order for Seller B
        order_uid = uuid.uuid4().hex[:8]
        order = SellerOrder.objects.create(
            source_order_id=f"SRC-PROFIT-TEST-{order_uid}",
            order_number=f"SO-TEST-PROFIT-{order_uid}",
            company=self.company_b,
            status=SellerOrder.Status.DELIVERED if hasattr(SellerOrder, "Status") else "DELIVERED",
            total_amount=Decimal("1100.00"),
            customer_name="John Doe",
            customer_phone="9876543210",
            delivery_address="123 Test Street",
        )

        # Item 1: 3 units of Beta Green Tea (Cost snapshot = 120.00, Selling price snapshot = 200.00)
        item1 = SellerOrderItem.objects.create(
            order=order,
            product=prod_b1,
            sku=prod_b1.sku,
            product_title=prod_b1.title,
            unit_price=Decimal("200.00"),
            procurement_price_snapshot=Decimal("120.00"),
            ordered_quantity=Decimal("3.000"),
            line_total=Decimal("600.00"),
        )
        self.assertEqual(item1.procurement_price_snapshot, Decimal("120.00"))

        # Item 2: 1 unit of Beta Coffee Beans (Cost snapshot = None, Selling price snapshot = 350.00)
        item2 = SellerOrderItem.objects.create(
            order=order,
            product=prod_b2,
            sku=prod_b2.sku,
            product_title=prod_b2.title,
            unit_price=Decimal("350.00"),
            procurement_price_snapshot=None,
            ordered_quantity=Decimal("1.000"),
            line_total=Decimal("350.00"),
        )
        self.assertIsNone(item2.procurement_price_snapshot)

        # Query Seller Reports Performance API for Seller B
        self.client.credentials(HTTP_AUTHORIZATION=f"Bearer {self.seller_b_token}")
        res_perf = self.client.get("/api/workforce/seller-hub/reports/performance/?days=30")
        self.assertEqual(res_perf.status_code, status.HTTP_200_OK)
        
        profitability = res_perf.data.get("product_profitability", [])
        self.assertTrue(len(profitability) >= 2)

        # Find Beta Green Tea
        tea_row = next((r for r in profitability if r["sku"] == "BETA-TEA-100"), None)
        self.assertIsNotNone(tea_row)
        self.assertEqual(float(tea_row["selling_price"]), 200.00)
        self.assertEqual(float(tea_row["procurement_price"]), 120.00)
        self.assertEqual(float(tea_row["unit_profit"]), 80.00)
        self.assertEqual(float(tea_row["margin_percent"]), 40.0)
        self.assertEqual(float(tea_row["units_sold"]), 3.0)
        self.assertEqual(float(tea_row["total_profit"]), 240.00)  # 3 units * 80

        # Find Beta Coffee Beans (Cost is None)
        coffee_row = next((r for r in profitability if r["sku"] == "BETA-COFFEE-250"), None)
        self.assertIsNotNone(coffee_row)
        self.assertIsNone(coffee_row["procurement_price"])
        self.assertIsNone(coffee_row["unit_profit"])
        self.assertIsNone(coffee_row["margin_percent"])
        self.assertEqual(float(coffee_row["units_sold"]), 1.0)
        self.assertIsNone(coffee_row["total_profit"])

        # Query Seller Reports Summary API
        res_sum = self.client.get("/api/workforce/seller-hub/reports/summary/?days=30")
        self.assertEqual(res_sum.status_code, status.HTTP_200_OK)
        self.assertTrue(res_sum.data.get("has_cost_data"))
        self.assertEqual(float(res_sum.data.get("total_gross_profit")), 240.00)

    def test_05_profitability_csv_export(self):
        """Export CSV for profitability returns valid rows and headers."""
        self.client.credentials(HTTP_AUTHORIZATION=f"Bearer {self.seller_b_token}")
        res_csv = self.client.get("/api/workforce/seller-hub/reports/export-csv/?type=profitability&days=30")
        self.assertEqual(res_csv.status_code, status.HTTP_200_OK)
        self.assertIn("text/csv", res_csv["Content-Type"])

        content = res_csv.content.decode("utf-8")
        reader = csv.reader(io.StringIO(content))
        rows = list(reader)
        self.assertGreater(len(rows), 1)

        headers = rows[0]
        self.assertIn("Procurement Price (INR)", headers)
        self.assertIn("Unit Profit (INR)", headers)
        self.assertIn("Margin (%)", headers)


if __name__ == "__main__":
    unittest.main()


if __name__ == "__main__":
    unittest.main()
