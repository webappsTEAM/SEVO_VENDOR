from django.core.cache import cache
from django.test import TestCase
from workforce_api.models import WorkforceSystemSetting
from workforce_api.services.automatic_dispatch import get_wave_size


class WaveSizeConfigurableTests(TestCase):
    def setUp(self):
        cache.clear()

    def test_defaults_without_setting(self):
        self.assertEqual((get_wave_size(1), get_wave_size(2), get_wave_size(3), get_wave_size(4)), (5, 10, 20, 20))

    def test_system_setting_overrides_and_bad_value_falls_back(self):
        WorkforceSystemSetting.objects.create(key="DISPATCH_INITIAL_WAVE_SIZE", value="3")
        cache.clear()
        self.assertEqual(get_wave_size(1), 3)
        WorkforceSystemSetting.objects.filter(key="DISPATCH_INITIAL_WAVE_SIZE").update(value="0")
        cache.clear()
        self.assertEqual(get_wave_size(1), 5)
