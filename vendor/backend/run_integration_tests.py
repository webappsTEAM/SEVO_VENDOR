#!/usr/bin/env python
"""
run_integration_tests.py

Disposable Integration-Test Database Bootstrap & Test Runner for Workforce Backend.
Adheres strictly to AGENTS.md rules:
- No production database contamination or fake data injection.
- Preserves schema ownership: Customer migrations apply first to instantiate
  shared-schema tables (accounts_user, service_requests_servicerequest, etc.).
- Workforce migrations apply second to instantiate workforce tables and foreign keys.
- Completely clean, isolated execution on an empty disposable database.
- Drops the disposable database upon completion (or on interruption).
"""
import sys
import os
import uuid
import subprocess
import argparse

# Ensure current directory is on python path
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
if BASE_DIR not in sys.path:
    sys.path.insert(0, BASE_DIR)

import django
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "workforce_core.settings")
django.setup()

from django.conf import settings
from django.db import connections


def run_command_in_env(cmd, cwd, env_vars=None):
    merged_env = os.environ.copy()
    if env_vars:
        merged_env.update(env_vars)
    res = subprocess.run(cmd, cwd=cwd, env=merged_env, capture_output=True, text=True)
    if res.returncode != 0:
        print(f"Command failed with code {res.returncode}: {' '.join(cmd)}")
        print("STDOUT:", res.stdout)
        print("STDERR:", res.stderr)
        raise RuntimeError(f"Command execution failure: {' '.join(cmd)}")
    return res.stdout


def main():
    parser = argparse.ArgumentParser(description="Run Workforce integration tests on a disposable database.")
    parser.add_argument("tests", nargs="*", default=["test_cash_collection_no_otp_flow", "test_workforce_authorization_security"])
    parser.add_argument("--db-name", default=f"test_wf_disp_{uuid.uuid4().hex[:8]}", help="Disposable database name")
    parser.add_argument("--customer-path", default=None, help="Path to Customer backend directory")
    args = parser.parse_args()

    disposable_db = args.db_name
    print(f"\n========================================================")
    print(f"=== WORKFORCE INTEGRATION TEST BOOTSTRAP ===")
    print(f"=== Disposable Test Database: {disposable_db}")
    print(f"========================================================\n")

    # Resolve DB connection params
    db_conf = settings.DATABASES["default"]
    db_user = db_conf.get("USER", "calservices_user")
    db_pass = db_conf.get("PASSWORD", "")
    db_host = db_conf.get("HOST", "127.0.0.1")
    db_port = str(db_conf.get("PORT", "5432"))

    # Resolve Customer backend path
    customer_backend = args.customer_path
    if not customer_backend:
        if os.path.exists("/var/www/sevo/backend"):
            customer_backend = "/var/www/sevo/backend"
        else:
            local_cand = os.path.abspath(os.path.join(BASE_DIR, "..", "..", "Customer", "backend"))
            if os.path.exists(local_cand):
                customer_backend = local_cand

    if not customer_backend or not os.path.exists(customer_backend):
        print(f"FATAL: Customer backend directory not found at {customer_backend}")
        sys.exit(1)

    print(f"[1/5] Creating empty disposable PostgreSQL database '{disposable_db}'...")
    import psycopg2
    from psycopg2.extensions import ISOLATION_LEVEL_AUTOCOMMIT

    conn = psycopg2.connect(
        dbname="postgres",
        user=db_user,
        password=db_pass,
        host=db_host,
        port=db_port,
    )
    conn.set_isolation_level(ISOLATION_LEVEL_AUTOCOMMIT)
    cursor = conn.cursor()
    cursor.execute(f"DROP DATABASE IF EXISTS {disposable_db};")
    cursor.execute(f"CREATE DATABASE {disposable_db} OWNER {db_user};")
    cursor.close()
    conn.close()
    print(f"      Created database '{disposable_db}' successfully.")

    exit_code = 1
    try:
        print(f"\n[2/5] Applying Customer-owned shared-schema migrations into '{disposable_db}'...")
        # Runner script for Customer migrations
        cust_script = f"""
import sys
sys.path.insert(0, '{customer_backend}')
import os
import django
os.environ['DJANGO_SETTINGS_MODULE'] = 'quicktims.settings'
django.setup()
from django.db import connections
connections.databases['default']['NAME'] = '{disposable_db}'
connections.close_all()
from django.core.management import call_command
call_command('migrate', interactive=False)
"""
        cust_py = sys.executable
        if os.path.exists(os.path.join(customer_backend, ".venv", "bin", "python")):
            cust_py = os.path.join(customer_backend, ".venv", "bin", "python")

        res_cust = subprocess.run([cust_py, "-c", cust_script], cwd=customer_backend, capture_output=True, text=True)
        if res_cust.returncode != 0:
            print("Customer migrations failed:")
            print(res_cust.stderr or res_cust.stdout)
            raise RuntimeError("Customer migration failure")
        print("      Customer migrations applied cleanly.")

        print(f"\n[3/5] Applying Workforce migrations into '{disposable_db}'...")
        wf_script = f"""
import sys
sys.path.insert(0, '{BASE_DIR}')
import os
import django
os.environ['DJANGO_SETTINGS_MODULE'] = 'workforce_core.settings'
django.setup()
from django.db import connections
connections.databases['default']['NAME'] = '{disposable_db}'
connections.close_all()
from django.core.management import call_command
call_command('migrate', interactive=False)
"""
        res_wf = subprocess.run([sys.executable, "-c", wf_script], cwd=BASE_DIR, capture_output=True, text=True)
        if res_wf.returncode != 0:
            print("Workforce migrations failed:")
            print(res_wf.stderr or res_wf.stdout)
            raise RuntimeError("Workforce migration failure")
        print("      Workforce migrations applied cleanly.")

        print(f"\n[4/5] Executing test suite against '{disposable_db}': {args.tests}...")
        test_script = f"""
import sys
sys.path.insert(0, '{BASE_DIR}')
import os
import django
from django.conf import settings
os.environ['DJANGO_SETTINGS_MODULE'] = 'workforce_core.settings'
django.setup()

if 'TEST' not in settings.DATABASES['default']:
    settings.DATABASES['default']['TEST'] = {{}}
settings.DATABASES['default']['TEST']['NAME'] = '{disposable_db}'
settings.DATABASES['default']['TEST']['MIRROR'] = None

from django.core.management import call_command
labels = {repr(args.tests)}
call_command('test', *labels, '--keepdb', '--noinput')
"""
        res_test = subprocess.run([sys.executable, "-c", test_script], cwd=BASE_DIR, capture_output=True, text=True)
        print("------------------- TEST OUTPUT -------------------")
        print(res_test.stdout)
        print(res_test.stderr)
        print("---------------------------------------------------")
        exit_code = res_test.returncode

    finally:
        print(f"\n[5/5] Tearing down and dropping disposable test database '{disposable_db}'...")
        try:
            conn = psycopg2.connect(
                dbname="postgres",
                user=db_user,
                password=db_pass,
                host=db_host,
                port=db_port,
            )
            conn.set_isolation_level(ISOLATION_LEVEL_AUTOCOMMIT)
            cursor = conn.cursor()
            # Terminate any remaining connections to the test DB
            cursor.execute(f"""
                SELECT pg_terminate_backend(pg_stat_activity.pid)
                FROM pg_stat_activity
                WHERE pg_stat_activity.datname = '{disposable_db}'
                  AND pid <> pg_backend_pid();
            """)
            cursor.execute(f"DROP DATABASE IF EXISTS {disposable_db};")
            cursor.close()
            conn.close()
            print(f"      Dropped '{disposable_db}' successfully. Zero test data preserved.")
        except Exception as e:
            print(f"      Warning: could not drop test DB '{disposable_db}': {e}")

    if exit_code == 0:
        print("\n>>> ALL WORKFORCE INTEGRATION & SECURITY TESTS PASSED CLEANLY! <<<\n")
    else:
        print(f"\n>>> TEST SUITE FAILED WITH EXIT CODE {exit_code} <<<\n")
    sys.exit(exit_code)


if __name__ == "__main__":
    main()
