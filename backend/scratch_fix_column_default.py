import os
import django
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "workforce_core.settings")
django.setup()

from django.db import connection

with connection.cursor() as cursor:
    cursor.execute("ALTER TABLE workforce_job_payment ALTER COLUMN is_mock SET DEFAULT FALSE;")
    cursor.execute("UPDATE workforce_job_payment SET is_mock = FALSE WHERE is_mock IS NULL;")
print("Successfully set column default for workforce_job_payment.is_mock!")
