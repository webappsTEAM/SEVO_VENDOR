"""Synchronize Django migration state with established shared schema.

The listed fields/tables predate this migration history.  Applying database
operations would either target a non-existent legacy table or mutate fields
that already exist, so only Django's historical state is updated.
"""
from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [("workforce_api", "0045_merge_20260925_1157")]

    operations = [
        migrations.SeparateDatabaseAndState(
            database_operations=[],
            state_operations=[
                migrations.RemoveField(model_name="vendorstore", name="gst_number"),
                migrations.RemoveField(model_name="vendorstore", name="onboarding"),
                migrations.AddField(
                    model_name="walletledgerentry",
                    name="is_mock",
                    field=models.BooleanField(default=False),
                ),
                migrations.AlterField(
                    model_name="workforcequote",
                    name="estimated_duration_days",
                    field=models.IntegerField(blank=True, default=1, null=True),
                ),
            ],
        ),
    ]
