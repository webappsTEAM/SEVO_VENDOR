"""
test_admin_warehouse_assign_merchant.py

Comprehensive End-to-End Verification Suite for Admin Warehouse Merchant Assignment:
(a) Admin can assign a merchant to a warehouse and it appears in warehouseDetail.sellers
(b) Assigning the same merchant twice rejects and doesn't duplicate
(c) Admin can unassign a merchant and it disappears from the list
(d) Non-admin users receive 403 Forbidden on assign, unassign, and company lookup endpoints
(e) Companies lookup endpoint returns accurate assignment status
"""
import os
import sys
import uuid
import unittest
import django

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "workforce_core.settings")
django.setup()

from rest_framework.test import APIClient
from rest_framework import status
from django.db import connection

from accounts.models import User
from companies.models import Company
from workforce_api.models import (
    Warehouse,
    SellerWarehouseAssignment,
)


class AdminWarehouseAssignMerchantTests(unittest.TestCase):
    def setUp(self):
        self.client = APIClient()
        self.created_warehouse_ids = []
        self.created_company_ids = []
        self.created_user_ids = []

        # Find or create superadmin
        self.admin_user = User.objects.filter(is_superuser=True, is_active=True).first()
        if not self.admin_user:
            self.admin_user = User.objects.create_superuser(
                username=f"admin_asn_{uuid.uuid4().hex[:6]}",
                email=f"admin_asn_{uuid.uuid4().hex[:6]}@sevo.local",
                password="AdminPassword123!",
            )
            self.created_user_ids.append(self.admin_user.id)

        # Create non-admin user
        self.non_admin_user = User.objects.create_user(
            username=f"tech_asn_{uuid.uuid4().hex[:6]}",
            email=f"tech_asn_{uuid.uuid4().hex[:6]}@sevo.local",
            password="TechPassword123!",
            role="employee",
            is_staff=False,
            is_superuser=False,
        )
        self.created_user_ids.append(self.non_admin_user.id)

        # Create a test Warehouse
        token = uuid.uuid4().hex[:6]
        self.test_warehouse = Warehouse.objects.create(
            name=f"Test Facility {token}",
            code=f"WH-ASN-{token.upper()}",
            address=f"{token} Industrial Way, Hosur",
            city="Hosur",
            region="Tamil Nadu",
            contact_phone="+91 9876543210",
            latitude=12.7409,
            longitude=77.8253,
            is_active=True,
        )
        self.created_warehouse_ids.append(self.test_warehouse.id)

        # Create a test merchant Company
        self.test_company = Company.objects.create(
            company_name=f"Merchant Organic Store {token}",
            slug=f"merchant-organic-{token}",
            business_type="grocery_supplier",
            is_active=True,
        )
        self.created_company_ids.append(self.test_company.id)

    def tearDown(self):
        # Strict teardown of all test records
        if self.created_company_ids or self.created_warehouse_ids:
            SellerWarehouseAssignment.objects.filter(warehouse_id__in=self.created_warehouse_ids).delete()
            SellerWarehouseAssignment.objects.filter(company_id__in=self.created_company_ids).delete()
        if self.created_warehouse_ids:
            Warehouse.objects.filter(id__in=self.created_warehouse_ids).delete()
        if self.created_company_ids:
            with connection.cursor() as cur:
                cur.execute("DELETE FROM companies_company WHERE id = ANY(%s)", [self.created_company_ids])
        if self.created_user_ids:
            User.objects.filter(id__in=self.created_user_ids).delete()

    def test_01_admin_assign_merchant_to_warehouse_success(self):
        """(a) Admin can assign a merchant to a warehouse and it appears in warehouse detail sellers."""
        self.client.force_authenticate(user=self.admin_user)

        payload = {
            "company_id": self.test_company.id,
            "notes": "Primary regional hub assignment",
        }
        response = self.client.post(
            f"/api/workforce/admin/warehouses/{self.test_warehouse.id}/assign-merchant/",
            payload,
            format="json",
        )
        self.assertEqual(response.status_code, status.HTTP_200_OK, f"Assign failed: {response.data}")
        self.assertTrue(response.data.get("created"))
        self.assertEqual(response.data["assignment"]["company"], self.test_company.id)
        self.assertEqual(response.data["assignment"]["warehouse"], self.test_warehouse.id)

        # Verify it appears in warehouse detail GET
        detail_resp = self.client.get(f"/api/workforce/admin/warehouses/{self.test_warehouse.id}/")
        self.assertEqual(detail_resp.status_code, status.HTTP_200_OK)
        sellers = detail_resp.data.get("sellers", [])
        seller_company_ids = [s["company_id"] for s in sellers]
        self.assertIn(self.test_company.id, seller_company_ids, "Assigned company not found in warehouse detail sellers list")

    def test_02_assigning_same_merchant_twice_rejects_and_does_not_duplicate(self):
        """(b) Assigning the same merchant twice rejects with 400 and does not duplicate."""
        self.client.force_authenticate(user=self.admin_user)

        # First assignment
        SellerWarehouseAssignment.objects.create(
            company=self.test_company,
            warehouse=self.test_warehouse,
            assigned_by=self.admin_user,
            notes="Initial assignment",
        )

        # Attempt duplicate assignment
        payload = {"company_id": self.test_company.id, "notes": "Duplicate attempt"}
        response = self.client.post(
            f"/api/workforce/admin/warehouses/{self.test_warehouse.id}/assign-merchant/",
            payload,
            format="json",
        )
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(response.data.get("code"), "ALREADY_ASSIGNED")

        # Confirm count in DB is exactly 1
        count = SellerWarehouseAssignment.objects.filter(company=self.test_company, warehouse=self.test_warehouse).count()
        self.assertEqual(count, 1, "Duplicate SellerWarehouseAssignment created in DB")

    def test_03_admin_unassign_merchant_removes_from_warehouse_detail(self):
        """(c) Admin can unassign a merchant and it disappears from the warehouse list."""
        self.client.force_authenticate(user=self.admin_user)

        # Set up assignment
        SellerWarehouseAssignment.objects.create(
            company=self.test_company,
            warehouse=self.test_warehouse,
            assigned_by=self.admin_user,
            notes="To be removed",
        )

        # Unassign via DELETE endpoint
        response = self.client.delete(
            f"/api/workforce/admin/warehouses/{self.test_warehouse.id}/assign-merchant/{self.test_company.id}/"
        )
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertTrue(response.data.get("unassigned"))

        # Verify no longer in warehouse detail
        detail_resp = self.client.get(f"/api/workforce/admin/warehouses/{self.test_warehouse.id}/")
        self.assertEqual(detail_resp.status_code, status.HTTP_200_OK)
        sellers = detail_resp.data.get("sellers", [])
        seller_company_ids = [s["company_id"] for s in sellers]
        self.assertNotIn(self.test_company.id, seller_company_ids, "Company still found in warehouse sellers after unassign")

    def test_04_non_admin_user_forbidden(self):
        """(d) Non-admin user gets 403 Forbidden on assign, unassign, and company lookup."""
        self.client.force_authenticate(user=self.non_admin_user)

        # POST assign
        resp_assign = self.client.post(
            f"/api/workforce/admin/warehouses/{self.test_warehouse.id}/assign-merchant/",
            {"company_id": self.test_company.id},
            format="json",
        )
        self.assertEqual(resp_assign.status_code, status.HTTP_403_FORBIDDEN)

        # DELETE unassign
        resp_unassign = self.client.delete(
            f"/api/workforce/admin/warehouses/{self.test_warehouse.id}/assign-merchant/{self.test_company.id}/"
        )
        self.assertEqual(resp_unassign.status_code, status.HTTP_403_FORBIDDEN)

        # GET companies lookup
        resp_lookup = self.client.get("/api/workforce/admin/companies/")
        self.assertEqual(resp_lookup.status_code, status.HTTP_403_FORBIDDEN)

    def test_05_companies_lookup_endpoint(self):
        """(e) Companies lookup endpoint returns search results and assignment status."""
        self.client.force_authenticate(user=self.admin_user)

        # 1. Unassigned company lookup
        resp = self.client.get(f"/api/workforce/admin/companies/?search={self.test_company.slug}")
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertTrue(len(resp.data) >= 1)
        found = next((c for c in resp.data if c["id"] == self.test_company.id), None)
        self.assertIsNotNone(found)
        self.assertFalse(found["is_assigned"])

        # 2. Assign company and check updated lookup
        SellerWarehouseAssignment.objects.create(
            company=self.test_company,
            warehouse=self.test_warehouse,
            assigned_by=self.admin_user,
        )

        resp2 = self.client.get(f"/api/workforce/admin/companies/?search={self.test_company.slug}")
        self.assertEqual(resp2.status_code, status.HTTP_200_OK)
        found2 = next((c for c in resp2.data if c["id"] == self.test_company.id), None)
        self.assertIsNotNone(found2)
        self.assertTrue(found2["is_assigned"])
        self.assertEqual(found2["assigned_warehouse_id"], self.test_warehouse.id)
        self.assertEqual(found2["assigned_warehouse_name"], self.test_warehouse.name)


if __name__ == "__main__":
    print("\n" + "=" * 65)
    print("RUNNING ADMIN WAREHOUSE ASSIGN MERCHANT VERIFICATION SUITE")
    print("=" * 65)
    suite = unittest.TestLoader().loadTestsFromTestCase(AdminWarehouseAssignMerchantTests)
    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(suite)
    if result.wasSuccessful():
        print("\n  [PASS] All 5 Admin Warehouse Assign Merchant tests passed successfully!")
    else:
        print("\n  [FAIL] Some tests failed.")
        sys.exit(1)
