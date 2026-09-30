"""Checkpoint radius, delivery-OTP lifetime / attempts / requirement follow the Admin GTOperationsConfig."""
from types import SimpleNamespace
from unittest.mock import patch

from django.test import SimpleTestCase

from workforce_api.services import logistics_checkpoints as lc

SEAM = "workforce_api.services.logistics_checkpoints._ops_row"


class OpsConfigTests(SimpleTestCase):
    def test_defaults_without_a_row(self):
        with patch(SEAM, return_value=None):
            self.assertEqual((lc.checkpoint_radius_meters(), lc.delivery_otp_ttl_minutes(), lc.max_otp_attempts()), (250.0, 30, 5))
            self.assertTrue(lc.drop_otp_required(SimpleNamespace(customer_id=1)))

    def test_admin_values_apply(self):
        row = SimpleNamespace(checkpoint_radius_meters=100, delivery_otp_ttl_minutes=10, max_otp_attempts=3, delivery_otp_required=True)
        with patch(SEAM, return_value=row):
            self.assertEqual((lc.checkpoint_radius_meters(), lc.delivery_otp_ttl_minutes(), lc.max_otp_attempts()), (100.0, 10, 3))

    def test_admin_can_switch_otp_off_but_never_on_without_a_customer(self):
        off = SimpleNamespace(checkpoint_radius_meters=250, delivery_otp_ttl_minutes=30, max_otp_attempts=5, delivery_otp_required=False)
        with patch(SEAM, return_value=off):
            self.assertFalse(lc.drop_otp_required(SimpleNamespace(customer_id=1)))
        with patch(SEAM, return_value=None):
            self.assertFalse(lc.drop_otp_required(SimpleNamespace(customer_id=None)))

