"""
0014_performance_indexes.py

Adds composite database indexes on high-frequency query patterns identified
from the actual ORM filter/ordering operations in workforce_api/views.py.

Priority tables and patterns:
  - WorkforceNotification: (recipient_id, created_at) — notification list + unread count
  - WorkforceJobOffer:     (employee_id, status, expires_at) — active offer lookup
  - WorkforceJobOffer:     (job_id, employee_id) — per-job offer retrieval
  - WorkforceJobLifecycleEvent: (job_id, employee_id, event_type) — acceptance event lookup
  - WorkforceWorkExtension: (job_id,) — bulk extension fetch
  - JobPayment:            (job_id,) — bulk payment fetch
  - WorkforceEventLog:     (user_id, event_type) — event audit queries
  - WorkforceEmployeeCompliance: (employee_id, requirement_id) — compliance gate checks

Note: ServiceRequest (jobs) and Employee tables are managed=False (Supabase-owned).
      Their indexes must be created via Supabase SQL editor, not Django migrations.
      Those patterns are documented in a comment at the bottom of this file.
"""
from django.db import migrations

# ── Concurrent (non-locking) performance indexes, Postgres-only syntax ─────
# CREATE INDEX CONCURRENTLY cannot run inside a transaction (hence
# atomic = False below) and has no sqlite equivalent. manage.py test always
# runs against sqlite (workforce_core.settings IS_TESTING forces this for
# any 'test' invocation), so each of these is wrapped in a RunPython that
# no-ops on any non-Postgres connection -- these are pure secondary indexes
# with no ORM/model-state impact either way, so skipping them under sqlite
# changes nothing observable in tests. Production is Postgres-only per
# settings.py's DATABASES config, so the real index creation still runs
# there exactly as before.
_INDEXES = [
    (
        "idx_workforce_notification_recipient_created",
        """
        CREATE INDEX CONCURRENTLY IF NOT EXISTS
            idx_workforce_notification_recipient_created
        ON workforce_notification (recipient_id, created_at DESC);
        """,
    ),
    (
        "idx_workforcejoboffer_employee_status_expires",
        """
        CREATE INDEX CONCURRENTLY IF NOT EXISTS
            idx_workforcejoboffer_employee_status_expires
        ON workforce_job_offer (employee_id, status, expires_at)
        WHERE status = 'OFFERED';
        """,
    ),
    (
        "idx_workforcejoboffer_job_employee",
        """
        CREATE INDEX CONCURRENTLY IF NOT EXISTS
            idx_workforcejoboffer_job_employee
        ON workforce_job_offer (job_id, employee_id);
        """,
    ),
    (
        "idx_workforcejob_lifecycle_job_emp_type",
        """
        CREATE INDEX CONCURRENTLY IF NOT EXISTS
            idx_workforcejob_lifecycle_job_emp_type
        ON workforce_job_lifecycle_event (job_id, employee_id, event_type);
        """,
    ),
    (
        "idx_workforceworkextension_job_created",
        """
        CREATE INDEX CONCURRENTLY IF NOT EXISTS
            idx_workforceworkextension_job_created
        ON workforce_work_extension (job_id, created_at DESC);
        """,
    ),
    (
        "idx_jobpayment_job_id",
        """
        CREATE INDEX CONCURRENTLY IF NOT EXISTS
            idx_jobpayment_job_id
        ON workforce_job_payment (job_id);
        """,
    ),
    (
        "idx_workforce_compliance_emp_req",
        """
        CREATE INDEX CONCURRENTLY IF NOT EXISTS
            idx_workforce_compliance_emp_req
        ON workforce_employee_compliance (employee_id, requirement_id);
        """,
    ),
    (
        "idx_workforce_notification_recipient_unread",
        """
        CREATE INDEX CONCURRENTLY IF NOT EXISTS
            idx_workforce_notification_recipient_unread
        ON workforce_notification (recipient_id, is_read)
        WHERE is_read = FALSE;
        """,
    ),
]


def _make_forward(sql):
    def forward(apps, schema_editor):
        if schema_editor.connection.vendor != "postgresql":
            return
        schema_editor.execute(sql)

    return forward


def _make_reverse(index_name):
    def reverse(apps, schema_editor):
        if schema_editor.connection.vendor != "postgresql":
            return
        schema_editor.execute(f"DROP INDEX IF EXISTS {index_name};")

    return reverse


class Migration(migrations.Migration):

    atomic = False

    dependencies = [
        ("workforce_api", "0013_workforcejoboffer_wave_id_and_more"),
    ]

    operations = [
        migrations.RunPython(_make_forward(sql), _make_reverse(name), hints={"target_db": "default"})
        for name, sql in _INDEXES
    ]

    # ── Supabase-managed tables (managed=False) ────────────────────────────────
    # These tables are managed by the Supabase project, not Django.
    # The following indexes should be created via the Supabase SQL Editor:
    #
    # -- ServiceRequest (jobs): status filter + ordering
    # CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_sr_company_status_created
    #   ON service_requests_servicerequest (company_id, status, created_at DESC);
    #
    # -- ServiceRequest: assigned employee + status (dispatch queries)
    # CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_sr_assigned_employee_status
    #   ON service_requests_servicerequest (assigned_employee_id, status)
    #   WHERE status NOT IN ('completed', 'cancelled');
    #
    # -- Employee: company + is_active (fleet map, dispatch candidate queries)
    # CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_employee_company_active
    #   ON employees_employee (company_id, is_active)
    #   WHERE is_active = TRUE;
    #
    # -- Employee: is_online + company (fleet map filter)
    # CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_employee_company_online
    #   ON employees_employee (company_id, is_online);
