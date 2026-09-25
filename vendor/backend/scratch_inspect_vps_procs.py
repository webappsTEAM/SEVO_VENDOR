import os
import sys
import django

sys.stdout.reconfigure(encoding='utf-8')
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

print("=== 3. SYSTEMCTL STATUS WORKFORCE-DISPATCH-ENGINE ===")
for l in run_cmd("systemctl status workforce-dispatch-engine"):
    print(l)

print("\n=== 4. SYSTEMCTL CAT WORKFORCE-DISPATCH-ENGINE ===")
for l in run_cmd("systemctl cat workforce-dispatch-engine"):
    print(l)

print("\n=== 5. CHECK PROC FOR PID 1743241 ===")
print("EXE:", run_cmd("ls -la /proc/1743241/exe"))
print("CWD:", run_cmd("ls -la /proc/1743241/cwd"))
print("CMDLINE:", run_cmd("tr '\\0' ' ' < /proc/1743241/cmdline"))

print("\n=== 6. DEPLOYED PATHS & SYMLINKS ON VPS ===")
for l in run_cmd("ls -la /var/www/calservices/"):
    print(l)

for l in run_cmd("ls -la /var/www/calservices/current-vendor/"):
    print(l)

print("\n=== 7. HASH OF automatic_dispatch.py IN RUNNING DIRECTORY ===")
for l in run_cmd("md5sum /var/www/calservices/current-vendor/backend/workforce_api/services/automatic_dispatch.py"):
    print(l)

print("\n=== 8. CHECK IF OTHER VENDOR DIRECTORIES EXIST ===")
for l in run_cmd("find /var/www/calservices -name automatic_dispatch.py"):
    print(l)

