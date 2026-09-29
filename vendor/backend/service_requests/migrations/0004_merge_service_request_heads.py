"""Merge parallel historical service-request migration heads.

Both prior merge migrations have identical parents and no operations.  This
node preserves migration history while providing one unambiguous leaf for
deployment; it intentionally performs no schema or data change.
"""
from django.db import migrations


class Migration(migrations.Migration):
    dependencies = [
        ("service_requests", "0003_merge_20260923_1507"),
        ("service_requests", "0003_merge_service_requests"),
    ]

    operations = []
