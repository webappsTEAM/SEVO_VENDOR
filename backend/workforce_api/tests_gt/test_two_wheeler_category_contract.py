"""Regression coverage for the canonical two-wheeler delivery contract."""

from django.test import SimpleTestCase

from workforce_api.services.automatic_dispatch import (
    LOGISTICS_SERVICE_CATEGORIES,
    canonical_service_match,
    normalize_service_category,
)


class TwoWheelerCategoryContractTests(SimpleTestCase):
    def test_legacy_seller_hub_category_normalizes_to_shared_contract(self):
        self.assertEqual(
            normalize_service_category("two_wheeler_delivery"),
            "goods_transport_two_wheeler",
        )
        self.assertIn("goods_transport_two_wheeler", LOGISTICS_SERVICE_CATEGORIES)

    def test_legacy_technician_authorization_matches_canonical_booking(self):
        is_match, _, _ = canonical_service_match(
            "goods_transport_two_wheeler",
            ["two_wheeler_delivery"],
            [],
        )
        self.assertTrue(is_match)
