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

print("=== PERMISSIONS OF SYSTEMD SERVICE ===")
for l in run_cmd("ls -la /etc/systemd/system/workforce-dispatch-engine.service"):
    print(l)

print("=== PERMISSIONS OF VENDOR DIR ===")
for l in run_cmd("ls -ld /var/www/calservices/current-vendor/backend"):
    print(l)

print("=== SUDO GROUP USERS ===")
for l in run_cmd("grep -E 'sudo|wheel|deployer|postgres' /etc/group"):
    print(l)
