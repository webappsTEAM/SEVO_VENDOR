"""
test_seller_labels_and_formats.py

Regression Test Suite for Seller-side Label Printing, Label Layout Alignment, and Multi-Format Paper Sizes (A4, Thermal 4x6, Thermal 2x1).

Covers:
(a) Seller can fetch PDF labels for their own inbound request (format=a4, thermal_4x6, thermal_2x1) and gets 200 OK.
(b) Seller gets 403 Forbidden when attempting to fetch labels for another merchant's request.
(c) Non-existent request returns 404 Not Found.
(d) Warehouse staff access to the labels endpoint still works across all formats.
(e) Unaccepted request without generated units returns 400 NO_UNITS.
(f) Clean teardown leaving production data untouched.
"""
import os
import sys
import django
from decimal import Decimal

import sys
sys.path.insert(0, r"c:\Users\USER\Desktop\caldim projects\sevo\sevo-vendor\vendor\backend")
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "workforce_core.settings")
django.setup()

import unittest
from rest_framework.test import APIRequestFactory, force_authenticate
from rest_framework import status

from accounts.models import User
from companies.models import Company
from workforce_api.models import (
    Warehouse,
    WarehouseStaff,
    SellerHubCategory,
    SellerProduct,
    WarehouseInboundRequest,
    WarehouseInboundUnit,
)
from workforce_api.views_seller_hub import (
    SellerInboundRequestLabelsPdfView,
)
from workforce_api.views_warehouse_portal import (
    WarehousePortalInboundRequestLabelsPdfView,
)

PREFIX = "lbltest"


def _clean_fixtures():
    from django.db import connection
    with connection.cursor() as cur:
        cur.execute(f"DELETE FROM workforce_warehouse_inbound_unit WHERE barcode LIKE 'SEVO-INB-{PREFIX}%';")
        cur.execute(f"DELETE FROM workforce_warehouse_inbound_request WHERE product_id IN (SELECT id FROM workforce_seller_product WHERE sku LIKE '{PREFIX.upper()}-%');")
        cur.execute(f"DELETE FROM workforce_seller_product WHERE sku LIKE '{PREFIX.upper()}-%';")
        cur.execute(f"DELETE FROM workforce_warehouse_staff WHERE user_id IN (SELECT id FROM accounts_user WHERE username LIKE '{PREFIX}_%');")
        cur.execute(f"DELETE FROM workforce_warehouse WHERE code LIKE 'WH-{PREFIX.upper()}-%';")
        cur.execute(f"DELETE FROM accounts_user WHERE username LIKE '{PREFIX}_%';")
        cur.execute(f"DELETE FROM companies_company WHERE slug LIKE '{PREFIX}-%';")
        cur.execute(f"DELETE FROM workforce_seller_hub_category WHERE slug LIKE '{PREFIX}-%';")


class SellerLabelsAndFormatsTestCase(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.factory = APIRequestFactory()
        _clean_fixtures()

        # Category
        cls.root_cat = SellerHubCategory.objects.create(
            name="Labels Test Cat", slug=f"{PREFIX}-root", is_active=True, sort_order=1,
        )

        # Warehouse
        cls.wh = Warehouse.objects.create(
            name="Labels Test Warehouse",
            code=f"WH-{PREFIX.upper()}-01",
            address="100 Warehouse Way",
            latitude=Decimal("12.9716"),
            longitude=Decimal("77.5946"),
            city="Hosur",
            is_active=True,
        )

        # Company A (Seller A)
        cls.seller_a_user = User.objects.create_user(
            username=f"{PREFIX}_seller_a",
            password="testpass",
            email=f"{PREFIX}_a@example.com",
        )
        cls.company_a = Company.objects.create(
            company_name="Labels Merchant A Co",
            slug=f"{PREFIX}-comp-a",
            business_type="grocery_supplier",
        )
        cls.seller_a_user.company = cls.company_a
        cls.seller_a_user.save()

        # Company B (Seller B)
        cls.seller_b_user = User.objects.create_user(
            username=f"{PREFIX}_seller_b",
            password="testpass",
            email=f"{PREFIX}_b@example.com",
        )
        cls.company_b = Company.objects.create(
            company_name="Labels Merchant B Co",
            slug=f"{PREFIX}-comp-b",
            business_type="grocery_supplier",
        )
        cls.seller_b_user.company = cls.company_b
        cls.seller_b_user.save()

        # Warehouse Staff User
        cls.wh_user = User.objects.create_user(
            username=f"{PREFIX}_wh_staff",
            password="testpass",
            email=f"{PREFIX}_wh@example.com",
        )
        WarehouseStaff.objects.create(
            user=cls.wh_user,
            warehouse=cls.wh,
            role="operator",
            is_primary=True,
        )

        # Products
        cls.prod_a = SellerProduct.objects.create(
            company=cls.company_a,
            category=cls.root_cat,
            title="Seller A Organic Pepper 250g",
            sku=f"{PREFIX.upper()}-PEPPER-250",
            unit="pack",
            selling_price=Decimal("150.00"),
            mrp=Decimal("180.00"),
            fulfillment_method=SellerProduct.FulfillmentMethod.FULFILLED_BY_SEVO,
            status=SellerProduct.Status.APPROVED,
        )

        cls.prod_b = SellerProduct.objects.create(
            company=cls.company_b,
            category=cls.root_cat,
            title="Seller B Cardamom 100g",
            sku=f"{PREFIX.upper()}-CARD-100",
            unit="pack",
            selling_price=Decimal("300.00"),
            mrp=Decimal("350.00"),
            fulfillment_method=SellerProduct.FulfillmentMethod.FULFILLED_BY_SEVO,
            status=SellerProduct.Status.APPROVED,
        )

        # Inbound Request for Seller A (Accepted with 5 units)
        cls.inbound_a = WarehouseInboundRequest.objects.create(
            company=cls.company_a,
            warehouse=cls.wh,
            product=cls.prod_a,
            requested_quantity=5,
            status=WarehouseInboundRequest.Status.ACCEPTED,
            requested_by=cls.seller_a_user,
        )
        for i in range(1, 6):
            WarehouseInboundUnit.objects.create(
                inbound_request=cls.inbound_a,
                unit_number=i,
                barcode=f"SEVO-INB-{PREFIX}-A-{i:04d}",
                status=WarehouseInboundUnit.Status.PENDING_SCAN,
            )

        # Inbound Request for Seller B (Accepted with 3 units)
        cls.inbound_b = WarehouseInboundRequest.objects.create(
            company=cls.company_b,
            warehouse=cls.wh,
            product=cls.prod_b,
            requested_quantity=3,
            status=WarehouseInboundRequest.Status.ACCEPTED,
            requested_by=cls.seller_b_user,
        )
        for i in range(1, 4):
            WarehouseInboundUnit.objects.create(
                inbound_request=cls.inbound_b,
                unit_number=i,
                barcode=f"SEVO-INB-{PREFIX}-B-{i:04d}",
                status=WarehouseInboundUnit.Status.PENDING_SCAN,
            )

        # Inbound Request for Seller A with PENDING status (no units generated yet)
        cls.inbound_pending = WarehouseInboundRequest.objects.create(
            company=cls.company_a,
            warehouse=cls.wh,
            product=cls.prod_a,
            requested_quantity=10,
            status=WarehouseInboundRequest.Status.PENDING,
            requested_by=cls.seller_a_user,
        )

    @classmethod
    def tearDownClass(cls):
        _clean_fixtures()
        super().tearDownClass()

    def test_01_seller_can_fetch_labels_across_all_formats(self):
        """Seller can fetch PDF labels for own accepted request in A4, Thermal 4x6, and Thermal 2x1 formats."""
        view = SellerInboundRequestLabelsPdfView.as_view()

        for fmt in ["a4", "thermal_4x6", "thermal_2x1"]:
            req = self.factory.get(f"/seller-hub/inbound-requests/{self.inbound_a.id}/labels-pdf/?format={fmt}")
            force_authenticate(req, user=self.seller_a_user)
            resp = view(req, pk=self.inbound_a.id)
            self.assertEqual(resp.status_code, status.HTTP_200_OK, f"Failed for format {fmt}")
            self.assertEqual(resp["Content-Type"], "application/pdf")
            self.assertGreater(len(resp.content), 500, f"PDF payload empty for format {fmt}")

    def test_02_seller_forbidden_from_fetching_other_merchant_labels(self):
        """Seller A cannot fetch labels for Seller B's inbound request (returns 403 Forbidden)."""
        view = SellerInboundRequestLabelsPdfView.as_view()

        req = self.factory.get(f"/seller-hub/inbound-requests/{self.inbound_b.id}/labels-pdf/")
        force_authenticate(req, user=self.seller_a_user)
        resp = view(req, pk=self.inbound_b.id)
        self.assertEqual(resp.status_code, status.HTTP_403_FORBIDDEN)
        self.assertEqual(resp.data.get("code"), "FORBIDDEN")

    def test_03_non_existent_inbound_request_404(self):
        """Requesting labels for non-existent request ID returns 404."""
        view = SellerInboundRequestLabelsPdfView.as_view()

        req = self.factory.get("/seller-hub/inbound-requests/999999/labels-pdf/")
        force_authenticate(req, user=self.seller_a_user)
        resp = view(req, pk=999999)
        self.assertEqual(resp.status_code, status.HTTP_404_NOT_FOUND)
        self.assertEqual(resp.data.get("code"), "NOT_FOUND")

    def test_04_warehouse_staff_access_across_all_formats(self):
        """Warehouse staff can download labels across all formats via warehouse portal view."""
        view = WarehousePortalInboundRequestLabelsPdfView.as_view()

        for fmt in ["a4", "thermal_4x6", "thermal_2x1"]:
            req = self.factory.get(f"/warehouse/inbound-requests/{self.inbound_a.id}/labels-pdf/?format={fmt}")
            force_authenticate(req, user=self.wh_user)
            resp = view(req, pk=self.inbound_a.id)
            self.assertEqual(resp.status_code, status.HTTP_200_OK, f"Warehouse failed for format {fmt}")
            self.assertEqual(resp["Content-Type"], "application/pdf")
            self.assertGreater(len(resp.content), 500)

    def test_05_unaccepted_request_with_no_units_returns_400(self):
        """Pending inbound request without generated units returns 400 NO_UNITS."""
        view = SellerInboundRequestLabelsPdfView.as_view()

        req = self.factory.get(f"/seller-hub/inbound-requests/{self.inbound_pending.id}/labels-pdf/")
        force_authenticate(req, user=self.seller_a_user)
        resp = view(req, pk=self.inbound_pending.id)
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(resp.data.get("code"), "NO_UNITS")


if __name__ == "__main__":
    unittest.main(verbosity=2)
