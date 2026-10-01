from decimal import Decimal
from django.core.cache import cache
from django.test import TestCase
from workforce_api.models import WorkforceSystemSetting
from workforce_api.services import commission as c


class CommissionRateLiveTests(TestCase):
    def setUp(self):
        cache.clear()

    def test_default_when_no_setting(self):
        self.assertEqual(c._live_rate("SEVO_INDIVIDUAL_COMMISSION_RATE", c.INDIVIDUAL_STANDARD_RATE), c.INDIVIDUAL_STANDARD_RATE)

    def test_setting_overrides_and_invalid_values_ignored(self):
        WorkforceSystemSetting.objects.create(key="SEVO_INDIVIDUAL_COMMISSION_RATE", value="0.12")
        self.assertEqual(c._live_rate("SEVO_INDIVIDUAL_COMMISSION_RATE", Decimal("0.18")), Decimal("0.12"))
        for bad in ("1.5", "-0.1", "abc", "NaN", ""):
            cache.clear()
            WorkforceSystemSetting.objects.filter(key="SEVO_INDIVIDUAL_COMMISSION_RATE").update(value=bad)
            self.assertEqual(c._live_rate("SEVO_INDIVIDUAL_COMMISSION_RATE", Decimal("0.18")), Decimal("0.18"), bad)
