"""
test_phase_aa_warehouse_picker.py

Phase AA regression suite - Seller Warehouse Picker + Current-Balance Display.

Covers:
  (a) A seller can submit a storage request to any active warehouse they choose,
      not just a single locked/assigned one.
  (b) A second request from the same seller to a *different* warehouse succeeds
      and does not clobber or reject based on the existing single assignment.
  (c) The current-balance figure returned for a warehouse+product combo matches
      the actual on_hand_qty stored in SellerInventory.
  (d) Eligible-warehouses list returns all active warehouses (inactive ones excluded).
  (e) Invalid / inactive warehouse_id in the request payload is rejected with a clear error.

Teardown removes all fixtures created by this suite; production data
(Warehouse #51 Hosur Hub, Company #1210) is never touched.
"""
import os
import django

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "workforce_core.settings")
django.setup()

import unittest
from decimal import Decimal
from rest_framework.test import APIRequestFactory, force_authenticate
from rest_framework import status as drf_status

from accounts.models import User
from companies.models import Company
from workforce_api.models import (
    Warehouse,
    SellerWarehouseAssignment,
    SellerHubCategory,
    SellerProduct,
    SellerInventory,
    WarehouseInboundRequest,
)
from workforce_api.views_seller_hub import (
    SellerEligibleWarehousesView,
    SellerInventoryBalanceView,
    SellerInboundRequestListCreateView,
)

SLUG_PREFIX = "phaseaa"


def _clean_fixtures():
    from django.db import connection
    WarehouseInboundRequest.objects.filter(product__sku__startswith="PHASEAA-").delete()
    SellerInventory.objects.filter(product__sku__startswith="PHASEAA-").delete()
    SellerProduct.objects.filter(sku__startswith="PHASEAA-").delete()
    SellerWarehouseAssignment.objects.filter(
        company__slug__in=[f"{SLUG_PREFIX}-comp-a", f"{SLUG_PREFIX}-comp-b"]
    ).delete()
    Warehouse.objects.filter(code__in=["WH-AA-01", "WH-AA-02", "WH-AA-INACTIVE"]).delete()
    User.objects.filter(username__in=[f"{SLUG_PREFIX}_seller_a", f"{SLUG_PREFIX}_seller_b"]).delete()
    SellerHubCategory.objects.filter(slug__in=[f"{SLUG_PREFIX}-root", f"{SLUG_PREFIX}-leaf"]).delete()
    with connection.cursor() as cur:
        cur.execute(
            "DELETE FROM companies_company WHERE slug IN (%s, %s)",
            [f"{SLUG_PREFIX}-comp-a", f"{SLUG_PREFIX}-comp-b"],
        )


class PhaseAAWarehousePickerTestCase(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.factory = APIRequestFactory()
        _clean_fixtures()

        cls.root_cat = SellerHubCategory.objects.create(
            name="PhaseAA Groceries", slug=f"{SLUG_PREFIX}-root", is_active=True, sort_order=1,
        )
        cls.leaf_cat = SellerHubCategory.objects.create(
            name="PhaseAA Spices", slug=f"{SLUG_PREFIX}-leaf",
            parent=cls.root_cat, is_active=True, sort_order=1,
        )

        cls.wh1 = Warehouse.objects.create(
            name="PhaseAA Hub North", code="WH-AA-01",
            address="1 Test St", latitude=Decimal("12.9716"), longitude=Decimal("77.5946"),
            city="Hosur", is_active=True,
        )
        cls.wh2 = Warehouse.objects.create(
            name="PhaseAA Hub South", code="WH-AA-02",
            address="2 Test St", latitude=Decimal("12.9000"), longitude=Decimal("77.6000"),
            city="Chennai", is_active=True,
        )
        cls.wh_inactive = Warehouse.objects.create(
            name="PhaseAA Inactive Hub", code="WH-AA-INACTIVE",
            address="3 Test St", latitude=Decimal("13.0000"), longitude=Decimal("77.0000"),
            city="Bangalore", is_active=False,
        )

        cls.seller_a_user = User.objects.create_user(
            username=f"{SLUG_PREFIX}_seller_a", password="testpass",
            email=f"{SLUG_PREFIX}a@test.com",
        )
        cls.company_a = Company.objects.create(
            company_name="PhaseAA Seller A Co", slug=f"{SLUG_PREFIX}-comp-a",
        )
        cls.seller_a_user.company = cls.company_a
        cls.seller_a_user.save()

        cls.assignment_a = SellerWarehouseAssignment.objects.create(
            company=cls.company_a, warehouse=cls.wh1,
        )

        cls.product_a = SellerProduct.objects.create(
            company=cls.company_a, category=cls.leaf_cat, title="PhaseAA Test Spice",
            sku="PHASEAA-SPICE-001", description="Test spice", unit="kg",
            selling_price=Decimal("99.00"), mrp=Decimal("120.00"),
            fulfillment_method=SellerProduct.FulfillmentMethod.FULFILLED_BY_SEVO,
            status=SellerProduct.Status.APPROVED,
        )
        cls.inventory_a = SellerInventory.objects.create(
            company=cls.company_a, product=cls.product_a, on_hand_qty=Decimal("120.000"),
        )

        cls.seller_b_user = User.objects.create_user(
            username=f"{SLUG_PREFIX}_seller_b", password="testpass",
            email=f"{SLUG_PREFIX}b@test.com",
        )
        cls.company_b = Company.objects.create(
            company_name="PhaseAA Seller B Co", slug=f"{SLUG_PREFIX}-comp-b",
        )
        cls.seller_b_user.company = cls.company_b
        cls.seller_b_user.save()

        cls.product_b = SellerProduct.objects.create(
            company=cls.company_b, category=cls.leaf_cat, title="PhaseAA Test Salt",
            sku="PHASEAA-SALT-001", description="Test salt", unit="kg",
            selling_price=Decimal("25.00"), mrp=Decimal("30.00"),
            fulfillment_method=SellerProduct.FulfillmentMethod.FULFILLED_BY_SEVO,
            status=SellerProduct.Status.APPROVED,
        )

    @classmethod
    def tearDownClass(cls):
        _clean_fixtures()
        super().tearDownClass()

    # (d) Eligible warehouses list
    def test_d_eligible_warehouses_active_only(self):
        req = self.factory.get("/seller-hub/warehouses/")
        force_authenticate(req, user=self.seller_a_user)
        resp = SellerEligibleWarehousesView.as_view()(req)
        self.assertEqual(resp.status_code, drf_status.HTTP_200_OK)
        ids = {wh["id"] for wh in resp.data["warehouses"]}
        self.assertIn(self.wh1.id, ids)
        self.assertIn(self.wh2.id, ids)
        self.assertNotIn(self.wh_inactive.id, ids)

    def test_d_seller_with_no_prior_assignment_gets_all_active_warehouses(self):
        """A seller with zero prior SellerWarehouseAssignment records still gets a non-empty eligible-warehouses list."""
        self.assertFalse(
            SellerWarehouseAssignment.objects.filter(company=self.company_b).exists()
        )
        req = self.factory.get("/seller-hub/warehouses/")
        force_authenticate(req, user=self.seller_b_user)
        resp = SellerEligibleWarehousesView.as_view()(req)
        self.assertEqual(resp.status_code, drf_status.HTTP_200_OK)
        self.assertGreater(resp.data["count"], 0)
        ids = {wh["id"] for wh in resp.data["warehouses"]}
        self.assertIn(self.wh1.id, ids)
        self.assertIn(self.wh2.id, ids)
        self.assertNotIn(self.wh_inactive.id, ids)

    # (c) Balance matches on_hand_qty
    def test_c_balance_matches_on_hand_qty(self):
        req = self.factory.get(
            "/seller-hub/inventory-balance/",
            {"product_id": self.product_a.id, "warehouse_id": self.wh1.id},
        )
        force_authenticate(req, user=self.seller_a_user)
        resp = SellerInventoryBalanceView.as_view()(req)
        self.assertEqual(resp.status_code, drf_status.HTTP_200_OK)
        self.assertEqual(float(resp.data["on_hand_qty"]), float(self.inventory_a.on_hand_qty))

    def test_c_balance_zero_no_inventory(self):
        req = self.factory.get(
            "/seller-hub/inventory-balance/",
            {"product_id": self.product_b.id, "warehouse_id": self.wh2.id},
        )
        force_authenticate(req, user=self.seller_b_user)
        resp = SellerInventoryBalanceView.as_view()(req)
        self.assertEqual(resp.status_code, drf_status.HTTP_200_OK)
        self.assertEqual(resp.data["on_hand_qty"], 0.0)
        self.assertFalse(resp.data["has_stock"])

    def test_c_balance_wrong_product_404(self):
        req = self.factory.get(
            "/seller-hub/inventory-balance/",
            {"product_id": self.product_b.id, "warehouse_id": self.wh1.id},
        )
        force_authenticate(req, user=self.seller_a_user)
        resp = SellerInventoryBalanceView.as_view()(req)
        self.assertEqual(resp.status_code, drf_status.HTTP_404_NOT_FOUND)

    # (a) Any active warehouse
    def test_a_submit_to_assigned_warehouse(self):
        req = self.factory.post(
            "/seller-hub/inbound-requests/",
            {"product_id": self.product_a.id, "requested_quantity": 50,
             "warehouse_id": self.wh1.id, "seller_note": "AA test wh1"},
            format="json",
        )
        force_authenticate(req, user=self.seller_a_user)
        resp = SellerInboundRequestListCreateView.as_view()(req)
        self.assertEqual(resp.status_code, drf_status.HTTP_201_CREATED, resp.data)
        self.assertEqual(resp.data["warehouse"], self.wh1.id)

    def test_a_submit_to_non_assigned_warehouse(self):
        req = self.factory.post(
            "/seller-hub/inbound-requests/",
            {"product_id": self.product_a.id, "requested_quantity": 30,
             "warehouse_id": self.wh2.id, "seller_note": "AA test wh2"},
            format="json",
        )
        force_authenticate(req, user=self.seller_a_user)
        resp = SellerInboundRequestListCreateView.as_view()(req)
        self.assertEqual(resp.status_code, drf_status.HTTP_201_CREATED, resp.data)
        self.assertEqual(resp.data["warehouse"], self.wh2.id)

    # (b) Two requests to different warehouses
    def test_b_two_different_warehouses_both_succeed(self):
        view = SellerInboundRequestListCreateView.as_view()

        req1 = self.factory.post(
            "/seller-hub/inbound-requests/",
            {"product_id": self.product_b.id, "requested_quantity": 20, "warehouse_id": self.wh1.id},
            format="json",
        )
        force_authenticate(req1, user=self.seller_b_user)
        resp1 = view(req1)
        self.assertEqual(resp1.status_code, drf_status.HTTP_201_CREATED, resp1.data)

        req2 = self.factory.post(
            "/seller-hub/inbound-requests/",
            {"product_id": self.product_b.id, "requested_quantity": 40, "warehouse_id": self.wh2.id},
            format="json",
        )
        force_authenticate(req2, user=self.seller_b_user)
        resp2 = view(req2)
        self.assertEqual(resp2.status_code, drf_status.HTTP_201_CREATED, resp2.data)

        wh_ids = set(
            WarehouseInboundRequest.objects.filter(
                company=self.company_b, product=self.product_b,
                status=WarehouseInboundRequest.Status.PENDING,
            ).values_list("warehouse_id", flat=True)
        )
        self.assertIn(self.wh1.id, wh_ids)
        self.assertIn(self.wh2.id, wh_ids)

    # (e) Validation
    def test_e_inactive_warehouse_rejected(self):
        req = self.factory.post(
            "/seller-hub/inbound-requests/",
            {"product_id": self.product_a.id, "requested_quantity": 10,
             "warehouse_id": self.wh_inactive.id},
            format="json",
        )
        force_authenticate(req, user=self.seller_a_user)
        resp = SellerInboundRequestListCreateView.as_view()(req)
        self.assertEqual(resp.status_code, drf_status.HTTP_400_BAD_REQUEST)
        self.assertEqual(resp.data.get("code"), "WAREHOUSE_NOT_FOUND")

    def test_e_no_warehouse_no_assignment_rejected(self):
        req = self.factory.post(
            "/seller-hub/inbound-requests/",
            {"product_id": self.product_b.id, "requested_quantity": 10},
            format="json",
        )
        force_authenticate(req, user=self.seller_b_user)
        resp = SellerInboundRequestListCreateView.as_view()(req)
        self.assertEqual(resp.status_code, drf_status.HTTP_400_BAD_REQUEST)
        self.assertIn(resp.data.get("code"), ["NO_WAREHOUSE_SELECTED", "NO_ASSIGNED_WAREHOUSE"])

    def test_e_no_warehouse_id_with_assignment_falls_back(self):
        """Phase T backward compat: omitting warehouse_id falls back to assigned warehouse."""
        req = self.factory.post(
            "/seller-hub/inbound-requests/",
            {"product_id": self.product_a.id, "requested_quantity": 5, "seller_note": "fallback"},
            format="json",
        )
        force_authenticate(req, user=self.seller_a_user)
        resp = SellerInboundRequestListCreateView.as_view()(req)
        self.assertEqual(resp.status_code, drf_status.HTTP_201_CREATED, resp.data)
        self.assertEqual(resp.data["warehouse"], self.wh1.id)


if __name__ == "__main__":
    unittest.main(verbosity=2)
