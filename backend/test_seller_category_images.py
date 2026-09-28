"""
test_seller_category_images.py

Comprehensive test suite verifying Seller Hub Category Images:
(a) Creating a category with an uploaded image sets image_url and it is returned by category APIs.
(b) Creating a category with a pasted URL works identically and returns in category APIs.
(c) A category with no image returns empty image_url and icon is intact for fallback.
(d) An invalid URL is rejected with a clear 400 validation error without a 500 error.
(e) Image upload endpoint returns a valid image_url for category image usage.
(f) Hierarchy tree, active lists, and catalog endpoints return image_url consistently.
"""
import os
import io
import django
import unittest
from PIL import Image

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "workforce_core.settings")
django.setup()

from django.conf import settings
if "testserver" not in settings.ALLOWED_HOSTS and "*" not in settings.ALLOWED_HOSTS:
    settings.ALLOWED_HOSTS = list(settings.ALLOWED_HOSTS) + ["testserver", "localhost", "127.0.0.1"]

from django.core.files.uploadedfile import SimpleUploadedFile
from rest_framework.test import APIClient
from rest_framework import status
from rest_framework_simplejwt.tokens import RefreshToken

from accounts.models import User
from workforce_api.models import SellerHubCategory


def generate_test_image_file(name="category_test.png"):
    img = Image.new("RGB", (64, 64), color=(73, 109, 137))
    byte_arr = io.BytesIO()
    img.save(byte_arr, format="PNG")
    byte_arr.seek(0)
    return SimpleUploadedFile(name, byte_arr.read(), content_type="image/png")


class SellerCategoryImagesTestCase(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.client = APIClient()

        # Platform Admin / Superuser
        cls.admin_user, _ = User.objects.get_or_create(
            username="superadmin_cat_img_test",
            defaults={
                "email": "superadmin_cat_img@sevo.com",
                "is_superuser": True,
                "is_staff": True,
                "role": "SUPERADMIN",
            }
        )
        if not cls.admin_user.is_superuser:
            cls.admin_user.is_superuser = True
            cls.admin_user.save()

        cls.admin_token = str(RefreshToken.for_user(cls.admin_user).access_token)
        cls.auth_headers = {"HTTP_AUTHORIZATION": f"Bearer {cls.admin_token}"}

    def setUp(self):
        # Clean up test records
        SellerHubCategory.objects.filter(slug__startswith="test-img-").delete()

    def tearDown(self):
        SellerHubCategory.objects.filter(slug__startswith="test-img-").delete()

    def test_01_upload_image_endpoint(self):
        """Test image upload endpoint returns a valid image_url for category/product storage"""
        test_file = generate_test_image_file("fresh_produce.png")
        upload_res = self.client.post(
            "/api/workforce/seller-hub/products/upload-image/",
            {"image": test_file},
            format="multipart",
            **self.auth_headers
        )
        self.assertEqual(upload_res.status_code, status.HTTP_201_CREATED, f"Upload failed: {upload_res.data}")
        uploaded_url = upload_res.data.get("image_url")
        self.assertTrue(uploaded_url, "Upload response did not return 'image_url'")
        self.assertTrue(
            uploaded_url.startswith("http://") or uploaded_url.startswith("https://") or uploaded_url.startswith("/media/"),
            f"Unexpected URL structure: {uploaded_url}"
        )
        print(f"\n[Test 1] Passed: Upload endpoint returned {uploaded_url}")

    def test_02_create_category_with_uploaded_image(self):
        """Test category creation with uploaded image URL sets image_url and returns in API"""
        test_file = generate_test_image_file("fruits.png")
        upload_res = self.client.post(
            "/api/workforce/seller-hub/products/upload-image/",
            {"image": test_file},
            format="multipart",
            **self.auth_headers
        )
        uploaded_url = upload_res.data.get("image_url")

        create_payload = {
            "name": "Fresh Fruits & Vegetables",
            "slug": "test-img-fruits-veg",
            "description": "Farm fresh fruits and green vegetables",
            "icon": "Carrot",
            "image_url": uploaded_url,
            "is_active": True,
            "sort_order": 1,
        }
        res = self.client.post(
            "/api/workforce/seller-hub/categories/",
            create_payload,
            format="json",
            **self.auth_headers
        )
        self.assertEqual(res.status_code, status.HTTP_201_CREATED, f"Creation failed: {res.data}")
        cat_data = res.data.get("category", {})
        self.assertEqual(cat_data.get("image_url"), uploaded_url)
        self.assertEqual(cat_data.get("icon"), "Carrot")

        # Verify DB persistence
        db_cat = SellerHubCategory.objects.get(slug="test-img-fruits-veg")
        self.assertEqual(db_cat.image_url, uploaded_url)
        self.assertEqual(db_cat.icon, "Carrot")
        print(f"\n[Test 2] Passed: Category created with uploaded image_url={uploaded_url}")

    def test_03_create_category_with_pasted_url(self):
        """Test category creation with pasted external web URL"""
        pasted_url = "https://images.unsplash.com/photo-1542838132-92c53300491e?auto=format&fit=crop&w=400&q=80"
        create_payload = {
            "name": "Organic Groceries",
            "slug": "test-img-organic-groceries",
            "description": "Certified organic pantry essentials",
            "icon": "Package",
            "image_url": pasted_url,
            "is_active": True,
            "sort_order": 2,
        }
        res = self.client.post(
            "/api/workforce/seller-hub/categories/",
            create_payload,
            format="json",
            **self.auth_headers
        )
        self.assertEqual(res.status_code, status.HTTP_201_CREATED, f"Creation failed: {res.data}")
        cat_data = res.data.get("category", {})
        self.assertEqual(cat_data.get("image_url"), pasted_url)
        self.assertEqual(cat_data.get("icon"), "Package")

        db_cat = SellerHubCategory.objects.get(slug="test-img-organic-groceries")
        self.assertEqual(db_cat.image_url, pasted_url)
        print(f"\n[Test 3] Passed: Category created with pasted URL={pasted_url}")

    def test_04_category_no_image_fallback_icon(self):
        """Test category with no image returns empty image_url and keeps icon for fallback"""
        create_payload = {
            "name": "Household Essentials",
            "slug": "test-img-household",
            "description": "Everyday home care supplies",
            "icon": "Sparkles",
            "image_url": "",
            "is_active": True,
            "sort_order": 3,
        }
        res = self.client.post(
            "/api/workforce/seller-hub/categories/",
            create_payload,
            format="json",
            **self.auth_headers
        )
        self.assertEqual(res.status_code, status.HTTP_201_CREATED, f"Creation failed: {res.data}")
        cat_data = res.data.get("category", {})
        self.assertEqual(cat_data.get("image_url"), "")
        self.assertEqual(cat_data.get("icon"), "Sparkles")
        print("\n[Test 4] Passed: Category with no image returns empty image_url and icon='Sparkles'")

    def test_05_invalid_url_rejected_without_500(self):
        """Test invalid URL formats are rejected with 400 validation error, not 500"""
        invalid_payloads = [
            {"name": "Bad URL 1", "slug": "test-img-bad-1", "image_url": "javascript:alert(1)"},
            {"name": "Bad URL 2", "slug": "test-img-bad-2", "image_url": "not-a-valid-link"},
            {"name": "Bad URL 3", "slug": "test-img-bad-3", "image_url": "ftp://files.example.com/img.jpg"},
            {"name": "Bad URL 4", "slug": "test-img-bad-4", "image_url": "https://example.com/" + ("x" * 1050)},
        ]

        for payload in invalid_payloads:
            res = self.client.post(
                "/api/workforce/seller-hub/categories/",
                payload,
                format="json",
                **self.auth_headers
            )
            self.assertEqual(
                res.status_code,
                status.HTTP_400_BAD_REQUEST,
                f"Expected 400 for payload {payload}, got {res.status_code}: {res.data}"
            )
            self.assertIn("details", res.data)
            self.assertIn("image_url", res.data["details"])
        print("\n[Test 5] Passed: All invalid URLs safely returned 400 Validation Errors (no 500s)")

    def test_06_get_endpoints_return_image_url(self):
        """Test that list, detail, tree, and active endpoints return image_url consistently"""
        pasted_url = "https://images.unsplash.com/photo-1542838132-92c53300491e"
        cat = SellerHubCategory.objects.create(
            name="Category with Photo",
            slug="test-img-photo-cat",
            icon="Carrot",
            image_url=pasted_url,
            is_active=True,
            sort_order=10,
        )

        # 1. Admin List
        list_res = self.client.get("/api/workforce/seller-hub/categories/", **self.auth_headers)
        self.assertEqual(list_res.status_code, status.HTTP_200_OK)
        found = next((c for c in list_res.data if c["id"] == cat.id), None)
        self.assertIsNotNone(found)
        self.assertEqual(found.get("image_url"), pasted_url)

        # 2. Admin Detail
        det_res = self.client.get(f"/api/workforce/seller-hub/categories/{cat.id}/", **self.auth_headers)
        self.assertEqual(det_res.status_code, status.HTTP_200_OK)
        self.assertEqual(det_res.data.get("image_url"), pasted_url)

        # 3. Hierarchy Tree
        tree_res = self.client.get("/api/workforce/seller-hub/categories/tree/", **self.auth_headers)
        self.assertEqual(tree_res.status_code, status.HTTP_200_OK)
        tree_found = next((c for c in tree_res.data if c["id"] == cat.id), None)
        self.assertIsNotNone(tree_found)
        self.assertEqual(tree_found.get("image_url"), pasted_url)

        # 4. Active Catalog Categories (Customer Storefront)
        active_res = self.client.get("/api/workforce/seller-hub/categories/active/", **self.auth_headers)
        self.assertEqual(active_res.status_code, status.HTTP_200_OK)
        active_found = next((c for c in active_res.data if c["id"] == cat.id), None)
        self.assertIsNotNone(active_found)
        self.assertEqual(active_found.get("image_url"), pasted_url)
        print("\n[Test 6] Passed: All 4 GET endpoints return image_url accurately")

    def test_07_patch_and_update_image_url(self):
        """Test updating category image_url via PATCH"""
        cat = SellerHubCategory.objects.create(
            name="Updatable Category",
            slug="test-img-update-cat",
            icon="Store",
            image_url="",
            is_active=True,
        )

        new_img = "https://images.unsplash.com/photo-1584308666744-24d5c474f2ae"
        patch_res = self.client.patch(
            f"/api/workforce/seller-hub/categories/{cat.id}/",
            {"image_url": new_img},
            format="json",
            **self.auth_headers
        )
        self.assertEqual(patch_res.status_code, status.HTTP_200_OK, f"PATCH failed: {patch_res.data}")
        self.assertEqual(patch_res.data.get("category", {}).get("image_url"), new_img)

        cat.refresh_from_db()
        self.assertEqual(cat.image_url, new_img)
        print("\n[Test 7] Passed: PATCH updated image_url successfully")


if __name__ == "__main__":
    unittest.main()
