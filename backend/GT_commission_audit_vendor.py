"""SEVO commission settings audit -- READ ONLY (no writes).

VENDOR backend:  python manage.py shell < GT_commission_audit_vendor.py
Prints the live commission settings, or says they are not set (then the code fallbacks apply).
"""
from workforce_api.models import WorkforceSystemSetting

keys = ["SEVO_PROVIDER_COMMISSION_RATE", "SEVO_PROVIDER_PROMO_RATE",
        "SEVO_INDIVIDUAL_COMMISSION_RATE", "SEVO_INDIVIDUAL_PROMO_RATE"]
for k in keys:
    row = WorkforceSystemSetting.objects.filter(key=k).first()
    print(k, "=", (row.value if row is not None else "NOT SET -> code fallback"))


from django.conf import settings
print("SEVO_PROMO_PERIOD_DAYS (env/settings) =", getattr(settings, "SEVO_PROMO_PERIOD_DAYS", "not set -> 90"))
print("code fallbacks: provider 0.10 / provider promo 0.00 / individual 0.18 / individual promo 0.08 / promo 90 days (not approved rates)")
