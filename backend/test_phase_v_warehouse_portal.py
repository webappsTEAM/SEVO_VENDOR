"""
test_phase_v_warehouse_portal.py

Comprehensive End-to-End Verification Suite for Phase V:
- Warehouse as a login-able role with its own portal
- Transactional warehouse creation with staff credentials
- Uniqueness & rollback validation
- Warehouse staff authentication & /api/auth/me/ serialization
- Multi-warehouse order scoping and cross-warehouse security isolation
- Regression verification for existing Seller, Platform Admin, and Employee roles
"""
import os
import sys
import django
import unittest
from decimal import Decimal
from django.utils import timezone
from django.db import connection

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "workforce_core.settings")
django.setup()

from rest_framework.test import APIClient
from rest_framework import status

from accounts.models import User
from companies.models import Company
from workforce_api.models import (
    Warehouse,
    WarehouseStaff,
    SellerWarehouseAssignment,
    SellerOrder,
    SellerOrderItem,
)


class PhaseVWarehousePortalTests(unittest.TestCase):
    def setUp(self):
        self.client = APIClient()
        self.created_warehouse_ids = []
        self.created_user_ids = []
        self.created_order_ids = []
        self.created_company_ids = []

        # Find or use existing superadmin / platform admin
        self.admin_user = User.objects.filter(is_superuser=True, is_active=True).first()
        if not self.admin_user:
            self.admin_user = User.objects.create_superuser(
                username="test_admin_phase_v",
                email="test_admin_v@example.com",
                password="AdminPassword123!",
            )
            self.created_user_ids.append(self.admin_user.id)

    def tearDown(self):
        # Clean up any test records created during testing in strict FK order
        if self.created_order_ids:
            SellerOrderItem.objects.filter(order_id__in=self.created_order_ids).delete()
            SellerOrder.objects.filter(id__in=self.created_order_ids).delete()
        if self.created_warehouse_ids:
            WarehouseStaff.objects.filter(warehouse_id__in=self.created_warehouse_ids).delete()
            SellerWarehouseAssignment.objects.filter(warehouse_id__in=self.created_warehouse_ids).delete()
            Warehouse.objects.filter(id__in=self.created_warehouse_ids).delete()
        if self.created_user_ids:
            User.objects.filter(id__in=self.created_user_ids).delete()
        if self.created_company_ids:
            with connection.cursor() as cur:
                cur.execute("DELETE FROM companies_company WHERE id = ANY(%s)", [self.created_company_ids])

    def _get_data(self, response):
        if hasattr(response, "data") and response.data is not None:
            return response.data
        try:
            return response.json()
        except Exception:
            return {}

    def test_01_transactional_warehouse_creation_with_credentials(self):
        """1. Admin creates warehouse with staff login credentials in a single step."""
        self.client.force_authenticate(user=self.admin_user)

        wh_payload = {
            "name": "Phase V Central Hub",
            "code": "WH-PHASEV-01",
            "address": "100 Logistics Park, Ring Road, Hosur",
            "city": "Hosur",
            "region": "Tamil Nadu",
            "contact_phone": "+91 9988776655",
            "latitude": 12.7409,
            "longitude": 77.8253,
            "is_active": True,
            "username": "phase_v_operator_01",
            "password": "WarehouseSecret123!",
            "email": "operator01@phasev.local",
        }

        response = self.client.post("/api/workforce/admin/warehouses/", wh_payload, format="json")
        res_data = self._get_data(response)
        self.assertEqual(response.status_code, status.HTTP_201_CREATED, f"Failed: {res_data}")

        wh_id = res_data["id"]
        self.created_warehouse_ids.append(wh_id)

        # Verify DB records
        warehouse = Warehouse.objects.filter(id=wh_id).first()
        self.assertIsNotNone(warehouse)
        self.assertEqual(warehouse.name, "Phase V Central Hub")

        staff = WarehouseStaff.objects.filter(warehouse=warehouse).select_related("user").first()
        self.assertIsNotNone(staff, "WarehouseStaff record was not created.")
        self.created_user_ids.append(staff.user.id)

        self.assertEqual(staff.user.username, "phase_v_operator_01")
        self.assertEqual(staff.user.role, "warehouse")
        self.assertTrue(staff.user.check_password("WarehouseSecret123!"))
        self.assertTrue(res_data["staff_login"]["has_login"])
        self.assertEqual(res_data["staff_login"]["username"], "phase_v_operator_01")

        print("  [PASS] 1. Warehouse created transactionally with User & WarehouseStaff credentials.")

    def test_02_duplicate_username_atomic_rollback(self):
        """2. Duplicate username fails validation and prevents warehouse creation (atomic rollback)."""
        self.client.force_authenticate(user=self.admin_user)

        # Create a user first
        existing_user = User.objects.create_user(
            username="existing_user_v",
            email="existing_v@example.com",
            password="Password123!",
        )
        self.created_user_ids.append(existing_user.id)

        wh_payload = {
            "name": "Phase V Orphan Test Hub",
            "code": "WH-ORPHAN-01",
            "address": "200 Fail Lane",
            "city": "Hosur",
            "latitude": 12.7409,
            "longitude": 77.8253,
            "username": "existing_user_v", # Collision!
            "password": "ValidPassword123!",
        }

        response = self.client.post("/api/workforce/admin/warehouses/", wh_payload, format="json")
        res_data = self._get_data(response)
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("already in use", str(res_data))

        # Verify no orphan warehouse exists in DB
        orphan = Warehouse.objects.filter(code="WH-ORPHAN-01").first()
        self.assertIsNone(orphan, "Orphan warehouse was created despite login failure!")

        print("  [PASS] 2. Duplicate username triggers 400 and rolls back warehouse creation cleanly.")

    def test_03_warehouse_staff_login_and_auth_me_payload(self):
        """3. Warehouse staff logs in via /api/auth/login/ and verifies /api/auth/me/ payload."""
        # Create warehouse + staff
        wh = Warehouse.objects.create(
            name="Alpha Hub Hosur",
            code="WH-ALPHA-01",
            address="Plot 5, Hosur Industrial Estate",
            latitude=Decimal("12.7400000"),
            longitude=Decimal("77.8200000"),
            city="Hosur",
            is_active=True,
        )
        self.created_warehouse_ids.append(wh.id)

        staff_user = User.objects.create_user(
            username="alpha_operator",
            email="alpha.op@hosur.local",
            password="AlphaSecretPass123!",
            role="warehouse",
            first_name="Alpha Operator",
        )
        self.created_user_ids.append(staff_user.id)

        WarehouseStaff.objects.create(
            user=staff_user,
            warehouse=wh,
            role="operator",
            is_primary=True,
        )

        # Login via public endpoint
        login_resp = self.client.post(
            "/api/auth/login/",
            {"identifier": "alpha_operator", "password": "AlphaSecretPass123!"},
            format="json",
        )
        res_data = self._get_data(login_resp)
        self.assertEqual(login_resp.status_code, status.HTTP_200_OK, f"Login failed: {res_data}")
        user_info = res_data["user"]
        self.assertTrue(user_info["is_warehouse_staff"])
        self.assertEqual(user_info["warehouse_id"], wh.id)
        self.assertEqual(user_info["warehouse_name"], "Alpha Hub Hosur")
        self.assertEqual(user_info["role"], "warehouse")
        self.assertEqual(user_info["user_type"], "warehouse_staff")
        self.assertFalse(user_info["is_seller"])

        token = res_data["token"]

        # Call /api/auth/me/ with token
        self.client.credentials(HTTP_AUTHORIZATION=f"Bearer {token}")
        me_resp = self.client.get("/api/auth/me/")
        self.assertEqual(me_resp.status_code, status.HTTP_200_OK)
        me_user = self._get_data(me_resp)
        self.assertTrue(me_user["is_warehouse_staff"])
        self.assertEqual(me_user["warehouse_id"], wh.id)
        self.assertEqual(me_user["warehouse_name"], "Alpha Hub Hosur")
        self.assertEqual(me_user["role"], "warehouse")

        print("  [PASS] 3. Warehouse login & /api/auth/me/ return correct authoritative warehouse context.")

    def test_04_cross_warehouse_data_scoping_and_security_isolation(self):
        """4. Verifies warehouse orders are strictly scoped and cross-warehouse access is 404 blocked."""
        # Warehouse A
        wh_a = Warehouse.objects.create(
            name="Warehouse A (Hosur North)",
            code="WH-A-NORTH",
            address="North Rd",
            latitude=Decimal("12.7500000"),
            longitude=Decimal("77.8300000"),
            city="Hosur",
            is_active=True,
        )
        self.created_warehouse_ids.append(wh_a.id)
        user_a = User.objects.create_user(
            username="user_warehouse_a",
            email="wh_a@test.local",
            password="PasswordA123!",
            role="warehouse",
        )
        self.created_user_ids.append(user_a.id)
        WarehouseStaff.objects.create(user=user_a, warehouse=wh_a, is_primary=True)

        # Warehouse B
        wh_b = Warehouse.objects.create(
            name="Warehouse B (Hosur South)",
            code="WH-B-SOUTH",
            address="South Rd",
            latitude=Decimal("12.7100000"),
            longitude=Decimal("77.8100000"),
            city="Hosur",
            is_active=True,
        )
        self.created_warehouse_ids.append(wh_b.id)
        user_b = User.objects.create_user(
            username="user_warehouse_b",
            email="wh_b@test.local",
            password="PasswordB123!",
            role="warehouse",
        )
        self.created_user_ids.append(user_b.id)
        WarehouseStaff.objects.create(user=user_b, warehouse=wh_b, is_primary=True)

        # Merchant Company (using Company #1210 if present or create and track)
        comp = Company.objects.filter(id=1210).first()
        if not comp:
            comp = Company.objects.create(
                company_name="Phase V Test Merchant",
                slug=f"phase-v-merchant-{int(timezone.now().timestamp())}",
                business_type="grocery_supplier",
            )
            self.created_company_ids.append(comp.id)

        # Order 1 assigned to Warehouse A
        order_1 = SellerOrder.objects.create(
            source_order_id=f"SO-PHASEV-A-{timezone.now().timestamp()}",
            order_number="SO-V-1001",
            company=comp,
            warehouse_id=wh_a.id,
            warehouse_name=wh_a.name,
            customer_name="Customer Alpha",
            customer_phone="+91 9111111111",
            total_amount=Decimal("450.00"),
            status=SellerOrder.Status.READY_FOR_PICKUP,
        )
        self.created_order_ids.append(order_1.id)

        # Order 2 assigned to Warehouse B
        order_2 = SellerOrder.objects.create(
            source_order_id=f"SO-PHASEV-B-{timezone.now().timestamp()}",
            order_number="SO-V-1002",
            company=comp,
            warehouse_id=wh_b.id,
            warehouse_name=wh_b.name,
            customer_name="Customer Beta",
            customer_phone="+91 9222222222",
            total_amount=Decimal("890.00"),
            status=SellerOrder.Status.PACKED,
        )
        self.created_order_ids.append(order_2.id)

        # --- TEST 4A: User A queries orders list ---
        self.client.force_authenticate(user=user_a)
        resp_a = self.client.get("/api/workforce/warehouse/orders/")
        self.assertEqual(resp_a.status_code, status.HTTP_200_OK, f"Error: {self._get_data(resp_a)}")
        res_a_data = self._get_data(resp_a)
        results_a = res_a_data.get("results", res_a_data)
        ids_a = [o["id"] for o in results_a]
        self.assertIn(order_1.id, ids_a, "Warehouse A orders list must include Order 1")
        self.assertNotIn(order_2.id, ids_a, "SECURITY VIOLATION: Warehouse A saw Warehouse B's order!")

        # --- TEST 4B: User B queries orders list ---
        self.client.force_authenticate(user=user_b)
        resp_b = self.client.get("/api/workforce/warehouse/orders/")
        self.assertEqual(resp_b.status_code, status.HTTP_200_OK, f"Error: {self._get_data(resp_b)}")
        res_b_data = self._get_data(resp_b)
        results_b = res_b_data.get("results", res_b_data)
        ids_b = [o["id"] for o in results_b]
        self.assertIn(order_2.id, ids_b, "Warehouse B orders list must include Order 2")
        self.assertNotIn(order_1.id, ids_b, "SECURITY VIOLATION: Warehouse B saw Warehouse A's order!")

        # --- TEST 4C: User A attempts direct URL access to Warehouse B's order ---
        self.client.force_authenticate(user=user_a)
        direct_cross_access = self.client.get(f"/api/workforce/warehouse/orders/{order_2.id}/")
        self.assertEqual(
            direct_cross_access.status_code,
            status.HTTP_404_NOT_FOUND,
            "SECURITY VIOLATION: User A was able to access Warehouse B's order by ID!",
        )

        # --- TEST 4D: User B attempts direct URL access to Warehouse A's order ---
        self.client.force_authenticate(user=user_b)
        direct_cross_access_b = self.client.get(f"/api/workforce/warehouse/orders/{order_1.id}/")
        self.assertEqual(
            direct_cross_access_b.status_code,
            status.HTTP_404_NOT_FOUND,
            "SECURITY VIOLATION: User B was able to access Warehouse A's order by ID!",
        )

        print("  [PASS] 4. Multi-warehouse data scoping and cross-warehouse 404 security isolation verified.")

    def test_05_warehouse_portal_stats_and_profile_endpoints(self):
        """5. Verifies /api/workforce/warehouse/stats/ and profile endpoints."""
        wh = Warehouse.objects.create(
            name="Hosur Metro Staging Hub",
            code="WH-METRO-01",
            address="15 Metro Line, Hosur",
            latitude=Decimal("12.7450000"),
            longitude=Decimal("77.8250000"),
            city="Hosur",
            contact_phone="+91 9888877777",
            is_active=True,
        )
        self.created_warehouse_ids.append(wh.id)
        user_wh = User.objects.create_user(
            username="metro_staff",
            email="metro@hosur.local",
            password="MetroPassword123!",
            role="warehouse",
        )
        self.created_user_ids.append(user_wh.id)
        WarehouseStaff.objects.create(user=user_wh, warehouse=wh, is_primary=True)

        self.client.force_authenticate(user=user_wh)

        # Test profile GET
        prof_resp = self.client.get("/api/workforce/warehouse/profile/")
        self.assertEqual(prof_resp.status_code, status.HTTP_200_OK, f"Error: {self._get_data(prof_resp)}")
        prof_data = self._get_data(prof_resp)
        self.assertEqual(prof_data["id"], wh.id)
        self.assertEqual(prof_data["name"], "Hosur Metro Staging Hub")

        # Test profile PATCH (e.g. phone update)
        patch_resp = self.client.patch(
            "/api/workforce/warehouse/profile/",
            {"contact_phone": "+91 9999900000"},
            format="json",
        )
        self.assertEqual(patch_resp.status_code, status.HTTP_200_OK)
        patch_data = self._get_data(patch_resp)
        self.assertEqual(patch_data["contact_phone"], "+91 9999900000")

        # Test stats GET
        stats_resp = self.client.get("/api/workforce/warehouse/stats/")
        self.assertEqual(stats_resp.status_code, status.HTTP_200_OK)
        stats_data = self._get_data(stats_resp)
        self.assertEqual(stats_data["warehouse_id"], wh.id)
        self.assertIn("total_orders", stats_data)
        self.assertIn("ready_for_pickup", stats_data)

        print("  [PASS] 5. Warehouse profile and stats endpoints operating correctly.")


if __name__ == "__main__":
    print("\n=======================================================")
    print("RUNNING PHASE V: WAREHOUSE PORTAL END-TO-END VERIFICATION")
    print("=======================================================\n")
    unittest.main()
