"""
set_wallet_status() referenced WALLET_SUSPENDED / WALLET_LOCKED / WALLET_CLOSED
without importing them, so every admin wallet-status change (which controls
whether a driver's Goods & Transport earnings can be withdrawn) raised NameError.
"""
from django.test import SimpleTestCase

from vendor_wallet.services import wallet_service


class WalletStatusNamesTests(SimpleTestCase):
    def test_invalid_status_is_a_clean_value_error(self):
        with self.assertRaises(ValueError):
            wallet_service.set_wallet_status(object(), "NOT_A_STATUS")

    def test_all_statuses_are_resolvable(self):
        for name in ("WALLET_ACTIVE", "WALLET_SUSPENDED", "WALLET_LOCKED", "WALLET_CLOSED"):
            self.assertTrue(hasattr(wallet_service, name), name)
