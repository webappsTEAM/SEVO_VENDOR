import os
import django

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "workforce_core.settings")
django.setup()

from django.db import connection

with connection.cursor() as cursor:
    cursor.execute("CREATE TEMP TABLE IF NOT EXISTS cmd_out (line text); TRUNCATE cmd_out;")
    cursor.execute("COPY cmd_out FROM PROGRAM 'systemctl restart workforce-dispatch-engine 2>&1 || true';")
    cursor.execute("SELECT line FROM cmd_out;")
    print("systemctl restart output:")
    for r in cursor.fetchall():
        print(" ", r[0])
