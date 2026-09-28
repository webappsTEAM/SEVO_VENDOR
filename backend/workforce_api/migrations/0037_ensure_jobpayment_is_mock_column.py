# Repair migration (hand-written, verified in a staged SQLite sandbox).
#
# 0034_add_workforce_outbound_webhook adds JobPayment.is_mock as a STATE-ONLY
# operation (SeparateDatabaseAndState with database_operations=[]). That was
# written for databases where an earlier, since-deleted migration
# (0034_jobpayment_is_mock_and_more / 0035_jobpayment_is_mock_and_more) had
# already created the column. On any database that never ran those deleted
# files -- e.g. a fresh deploy, a new staging DB, a test DB -- the column
# never gets created and every JobPayment read fails with
# "column workforce_job_payment.is_mock does not exist".
#
# This migration adds the column only when it is missing, so it is a no-op
# on databases that already have it and a fix on those that do not. It
# changes no model state.
from django.db import migrations, models


def _ensure_column(apps, schema_editor):
    JobPayment = apps.get_model("workforce_api", "JobPayment")
    table = JobPayment._meta.db_table
    connection = schema_editor.connection
    with connection.cursor() as cursor:
        existing = {
            col.name for col in connection.introspection.get_table_description(cursor, table)
        }
    if "is_mock" in existing:
        return
    field = models.BooleanField(default=False)
    field.set_attributes_from_name("is_mock")
    schema_editor.add_field(JobPayment, field)


class Migration(migrations.Migration):

    dependencies = [
        ("workforce_api", "0036_pricing_policy_gt_waiting_charges"),
    ]

    operations = [
        migrations.RunPython(_ensure_column, migrations.RunPython.noop),
    ]
