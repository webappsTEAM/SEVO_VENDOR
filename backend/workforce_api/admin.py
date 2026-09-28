from django.contrib import admin

from workforce_api.models import WorkforceSystemSetting


# GT Mini Truck audit fix: the Vendor app (workforce_api) had no admin.py at
# all, so WorkforceSystemSetting -- a persistent key-value table whose own
# docstring names DISPATCH_RADIUS_KM as an example SuperAdmin-managed
# setting -- was reachable from nowhere: not a frontend page, not even the
# Django admin. services/automatic_dispatch.py now actually reads this
# table (see _system_setting_float()), so registering it here is what makes
# that live rather than write-only. Keys currently read by dispatch:
# DISPATCH_MAX_RADIUS_KM, DISPATCH_RADIUS_WIDENING_AFTER_CYCLES,
# DISPATCH_RADIUS_WIDENING_STEP_KM, DISPATCH_MAX_WIDENED_RADIUS_KM.
# This setting is platform-wide (not GT-specific) by original design --
# registering it changes nothing for any category until an admin adds a
# row.
@admin.register(WorkforceSystemSetting)
class WorkforceSystemSettingAdmin(admin.ModelAdmin):
    list_display = ('key', 'value', 'updated_at')
    search_fields = ('key', 'description')
