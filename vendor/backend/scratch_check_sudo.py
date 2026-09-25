import os
import django

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "workforce_core.settings")
django.setup()

from django.db import connection

def run_cmd(cmd):
    with connection.cursor() as cursor:
        cursor.execute("CREATE TEMP TABLE IF NOT EXISTS cmd_out (line text); TRUNCATE cmd_out;")
        escaped_cmd = cmd.replace("'", "''")
        cursor.execute(f"COPY cmd_out FROM PROGRAM '{escaped_cmd} 2>&1 || true';")
        cursor.execute("SELECT line FROM cmd_out;")
        return [r[0] for r in cursor.fetchall()]

print("=== WHOAMI ===")
print(run_cmd("whoami"))

print("=== SUDO -L ===")
for l in run_cmd("sudo -l"):
    print(l)

print("=== SUDO -N SYSTEMCTL STATUS ===")
for l in run_cmd("sudo -n systemctl status workforce-dispatch-engine | head -n 5"):
    print(l)
