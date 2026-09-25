# Hand-written, verified in a staged SQLite sandbox (makemigrations --check
# reports no changes with this file present). Purely additive: one column on
# workforce_service_pricing_policy with default 5 -- the value that was
# previously hardcoded in three cancellation code paths in views.py.
from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("workforce_api", "0037_ensure_jobpayment_is_mock_column"),
    ]

    operations = [
        migrations.AddField(
            model_name="workforceservicepricingpolicy",
            name="technician_free_cancel_minutes",
            field=models.PositiveIntegerField(
                default=5,
                help_text="Minutes after accepting a job during which the technician may cancel without penalty.",
            ),
        ),
    ]
