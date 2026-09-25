# Hand-written, then checked in a staged sandbox replica (SQLite):
# `makemigrations --check --dry-run` reports "No changes detected" with this
# file in place, so it matches models.py. Purely additive: four new columns
# on the managed workforce_service_pricing_policy table, all nullable or
# defaulted, so it is safe on a populated table and changes no existing
# behaviour. (Not yet applied against the real Postgres database.)
from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("workforce_api", "0035_walletledgerentry_is_mock_and_more"),
    ]

    operations = [
        migrations.AddField(
            model_name="workforceservicepricingpolicy",
            name="waiting_free_loading_minutes",
            field=models.PositiveIntegerField(
                blank=True, null=True,
                help_text="GT: free minutes for loading at pickup. Blank disables loading waiting charges.",
            ),
        ),
        migrations.AddField(
            model_name="workforceservicepricingpolicy",
            name="waiting_free_unloading_minutes",
            field=models.PositiveIntegerField(
                blank=True, null=True,
                help_text="GT: free minutes for unloading at drop. Blank disables unloading waiting charges.",
            ),
        ),
        migrations.AddField(
            model_name="workforceservicepricingpolicy",
            name="waiting_charge_per_minute",
            field=models.DecimalField(
                decimal_places=2, default=0.0, max_digits=8,
                help_text="GT: amount charged per minute beyond the free window. 0 disables.",
            ),
        ),
        migrations.AddField(
            model_name="workforceservicepricingpolicy",
            name="waiting_charge_cap",
            field=models.DecimalField(
                blank=True, decimal_places=2, max_digits=10, null=True,
                help_text="GT: maximum waiting charge per booking. Blank means no cap.",
            ),
        ),
    ]
