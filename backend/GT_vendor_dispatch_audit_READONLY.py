"""SEVO GT -- VENDOR-SIDE dispatch/notification/assignment audit.  STRICTLY READ ONLY.

Run in the VENDOR backend (it reads the shared database):
    python manage.py shell < GT_vendor_dispatch_audit_READONLY.py  > vendor_audit_out.txt

Safety:
  * The DB session is forced read-only first (PostgreSQL itself rejects any write).
  * Only SELECTs and Django's read-only migration-graph inspection. Nothing is saved, sent, accepted,
    redispatched, migrated or restarted.
  * No names, e-mails, phones, tokens, passwords, addresses: columns with such names are dropped,
    address-like columns are shown as their length, coordinates are rounded to 2 decimals (~1 km).
    People appear only as numeric ids.
  * Rows are printed as rows (not counts). A missing table prints exactly: TABLE/RECORD NOT AVAILABLE
"""
import re
from django.db import connection

SINCE_UTC = "2026-09-30 18:30:00+00"      # = 2026-10-01 00:00 IST
FOCUS = (42, 43)
DROP = re.compile(r"(e?mail|phone|mobile|password|token|secret|otp|first_name|last_name|full_name|^name$|"
                  r"signature|photo|image|avatar|aadhaar|pan_|bank|account_number|ifsc|upi|key$|hash)", re.I)
ADDR = re.compile(r"(address|landmark|instructions|notes?|description|message)$", re.I)
GEO = re.compile(r"(lat|lng|lon)", re.I)


def hdr(t):
    print("\n" + "=" * 8, t, "=" * 8)


def run(sql, params=None, limit=None):
    with connection.cursor() as c:
        c.execute(sql, params or [])
        cols = [d[0] for d in c.description] if c.description else []
        rows = c.fetchmany(limit) if limit else c.fetchall()
    return cols, rows


def table_exists(t):
    return bool(run("SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name=%s", [t])[1])


def columns(t):
    return [r[0] for r in run("SELECT column_name FROM information_schema.columns WHERE table_schema='public' "
                              "AND table_name=%s ORDER BY ordinal_position", [t])[1]]


def clean(col, v):
    if v is None:
        return None
    if GEO.search(col) and isinstance(v, (float, int)) or (GEO.search(col) and str(v).replace('.', '', 1).replace('-', '', 1).isdigit()):
        try:
            return round(float(v), 2)
        except Exception:
            return "<geo>"
    if ADDR.search(col) and isinstance(v, str):
        return "<text len %d>" % len(v)
    s = str(v)
    return s if len(s) <= 160 else s[:160] + "..."


def dump(title, table, where="TRUE", params=None, order="1", limit=300, extra_drop=()):
    print("\n-- %s  [%s]" % (title, table))
    if not table_exists(table):
        print("   TABLE/RECORD NOT AVAILABLE")
        return []
    cols = [c for c in columns(table) if not DROP.search(c) and c not in extra_drop]
    try:
        cs, rows = run('SELECT %s FROM "%s" WHERE %s ORDER BY %s LIMIT %d'
                       % (", ".join('"%s"' % c for c in cols), table, where, order, limit), params)
    except Exception as e:
        connection.rollback()
        print("   could not read:", type(e).__name__, str(e)[:140])
        return []
    for r in rows:
        print("  ", {c: clean(c, v) for c, v in zip(cs, r)})
    if not rows:
        print("   (no rows)")
    return rows


# ------------------------------------------------------------------ 0
hdr("0. SESSION / DATABASE")
with connection.cursor() as c:
    c.execute("SET default_transaction_read_only = on")
    c.execute("SET statement_timeout = '45s'")
    c.execute("SHOW default_transaction_read_only")
    print("session read-only:", c.fetchone()[0])
    c.execute("SELECT current_database(), now()")
    print("database / server time:", c.fetchone())

print("window start (UTC):", SINCE_UTC, "(= 2026-10-01 00:00 IST)")

# ------------------------------------------------------------------ 1. GT jobs
hdr("1. ALL GT JOBS (ServiceRequest) CREATED IN WINDOW  -- a 'job' here is the ServiceRequest id")
SR = "service_requests_servicerequest"
sr_cols = columns(SR)
print("columns present:", [c for c in sr_cols if not DROP.search(c)])
GT_WHERE = "(service_category ILIKE 'goods_transport%%' OR service_category IN ('packers_movers','ptl','goods_transport')) " \
           "AND created_at >= %s"
gt_rows = dump("GT bookings/jobs", SR, GT_WHERE, [SINCE_UTC], "id")
gt_ids = sorted(set(int(r[sr_cols.index('id')]) if False else int(r[0]) for r in gt_rows)) if gt_rows else []
ids = sorted(set(gt_ids) | set(FOCUS))
print("\nGT job ids in window + focus ids:", ids)
print("(non-GT bookings in the same window are NOT dispatched by this audit; see customer audit)")

IDS = ids or [0]

# ------------------------------------------------------------------ 2. dispatch state, offers, lifecycle
hdr("2. DISPATCH STATE (one row per job)")
dump("workforce_dispatch_state", "workforce_dispatch_state", "job_id = ANY(%s)", [IDS], "job_id")

hdr("3. JOB OFFERS = dispatch waves / eligible vendors / vendor responses (one row per employee per wave)")
dump("workforce_job_offer", "workforce_job_offer", "job_id = ANY(%s)", [IDS], "job_id, wave_number, offered_at", 600)
print("\n-- summary per job/wave (derived from the rows above)")
if table_exists("workforce_job_offer"):
    for r in run("""SELECT job_id, wave_number, wave_id::text, count(*) AS offers, count(DISTINCT employee_id) AS employees,
                           min(offered_at) AS wave_created, max(expires_at) AS wave_expiry,
                           string_agg(DISTINCT status, ',') AS statuses
                    FROM workforce_job_offer WHERE job_id = ANY(%s) GROUP BY 1,2,3 ORDER BY 1,2""", [IDS])[1]:
        print("  ", r)

hdr("4. JOB LIFECYCLE EVENTS (accept / decline / assign / cancel / expire ...)")
dump("workforce_job_lifecycle_event", "workforce_job_lifecycle_event", "job_id = ANY(%s)", [IDS], "job_id, created_at", 600)

# ------------------------------------------------------------------ 5. notifications
hdr("5. NOTIFICATION EVIDENCE -- three different states")
print("State 1 = a DB row exists.  State 2 = a notification row was generated for the vendor.")
print("State 3 = delivered/received: only read_at (vendor opened it) or a push-delivery log can show that.")
if table_exists("workforce_notification"):
    dump("notification rows tied to these jobs (related_object_id)", "workforce_notification",
         "related_object_id = ANY(%s) OR (created_at >= %s AND notification_type ILIKE ANY(ARRAY['%%job%%','%%dispatch%%','%%offer%%','%%booking%%']))",
         [[str(i) for i in IDS], SINCE_UTC], "created_at", 400)
else:
    print("TABLE/RECORD NOT AVAILABLE: workforce_notification")
print("\n-- tables that could hold push-delivery evidence (names + row counts only; token columns never read)")
for t, in run("""SELECT table_name FROM information_schema.tables WHERE table_schema='public'
                 AND table_name ~* '(push|fcm|device|webpush|notification_log|delivery_log|outbound)' ORDER BY 1""")[1]:
    try:
        print("  ", t, "rows:", run('SELECT count(*) FROM "%s"' % t)[1][0][0], "| columns:", [c for c in columns(t) if not DROP.search(c)][:14])
    except Exception as e:
        connection.rollback()
        print("  ", t, "could not count")
print("   (if no FCM/push receipt table lists delivery status, delivery to a phone is UNKNOWN from the database)")

dump("outbound webhooks about these jobs", "workforce_outbound_webhook", "TRUE", None, "1 DESC", 40)

# ------------------------------------------------------------------ 6. events / task runs
hdr("6. WORKFORCE EVENT LOG rows mentioning these jobs (dispatch engine heartbeat/expiry events)")
if table_exists("workforce_event_log"):
    pat = "|".join(r'"job_id": ?%d\b' % i for i in IDS)
    dump("event_log", "workforce_event_log", "created_at >= %s AND payload::text ~ %s", [SINCE_UTC, pat], "created_at", 300, ("ip_address",))
    print("\n-- event types in window (counts, to see what the engine logs)")
    for r in run("SELECT event_type, count(*), min(created_at), max(created_at) FROM workforce_event_log WHERE created_at >= %s GROUP BY 1 ORDER BY 2 DESC LIMIT 40", [SINCE_UTC])[1]:
        print("  ", r)
else:
    print("TABLE/RECORD NOT AVAILABLE: workforce_event_log")

hdr("6b. CELERY TASK RESULTS in window (task name/status/time only; arguments never printed)")
if table_exists("django_celery_results_taskresult"):
    for r in run("""SELECT task_name, status, count(*), min(date_done), max(date_done) FROM django_celery_results_taskresult
                    WHERE date_done >= %s GROUP BY 1,2 ORDER BY 3 DESC LIMIT 40""", [SINCE_UTC])[1]:
        print("  ", r)
else:
    print("TABLE/RECORD NOT AVAILABLE: django_celery_results_taskresult (task history is not stored in the DB)")

# ------------------------------------------------------------------ 7. trip / tracking / payment / completion
hdr("7. TRIP / TRACKING / CHECKPOINT / PAYMENT / PROOF rows for these jobs")
dump("tracking sessions", "workforce_job_tracking_session", "job_id = ANY(%s)", [IDS], "job_id, started_at", 100,
     ("last_fix_lat", "last_fix_lon", "prev_latitude", "prev_longitude"))
if table_exists("workforce_job_location_point"):
    for r in run("SELECT job_id, count(*), min(captured_at), max(captured_at) FROM workforce_job_location_point WHERE job_id = ANY(%s) GROUP BY 1", [IDS])[1]:
        print("   location points:", r)
dump("logistics checkpoints", "workforce_logistics_checkpoint_verification", "job_id = ANY(%s)", [IDS], "job_id, 1", 100)
dump("job payments (vendor side)", "workforce_job_payment", "job_id = ANY(%s)", [IDS], "job_id", 50)
dump("post-service proof", "workforce_post_service_proof", "job_id = ANY(%s)", [IDS], "job_id", 50)
dump("reschedules", "workforce_job_reschedule", "job_id = ANY(%s)", [IDS], "job_id", 50)

hdr("7b. THE BOOKING ROWS THEMSELVES (customer-side fields, for cross-check)")
dump("jobs 42 / 43 full non-PII row", SR, "id = ANY(%s)", [list(FOCUS)], "id")
dump("customer-side payments for those bookings (if a payments table keys on the booking)", "service_requests_payment",
     "service_request_id = ANY(%s)", [list(FOCUS)], "1", 20)

# ------------------------------------------------------------------ 8. real vendor activity
hdr("8. REAL VENDOR / WORKFORCE ACTIVITY (numeric ids and operational flags only)")
try:
    from workforce_api.models import WorkforceJobOffer
    Emp = WorkforceJobOffer._meta.get_field("employee").related_model
    et = Emp._meta.db_table
    print("employee table:", et)
    eids = [r[0] for r in run("SELECT DISTINCT employee_id FROM workforce_job_offer WHERE job_id = ANY(%s)", [IDS])[1]]
    print("distinct employees that received an offer for these jobs:", eids)
    print("employees that ACCEPTED / DECLINED (from offer status):")
    for r in run("SELECT status, count(*), count(DISTINCT employee_id) FROM workforce_job_offer WHERE job_id = ANY(%s) GROUP BY 1", [IDS])[1]:
        print("  ", r)
    dump("those employee rows (non-PII columns only)", et, "id = ANY(%s)", [eids or [0]], "id", 100)
    ucol = next((c.column for c in Emp._meta.fields if c.is_relation and c.related_model._meta.db_table.endswith("user")), None)
    if ucol:
        print("\n-- login recency of the underlying user accounts (flags/timestamps only, no names)")
        ut = Emp._meta.get_field(ucol.replace("_id", "")).related_model._meta.db_table
        for r in run('SELECT u.id, u.is_staff, u.is_superuser, u.last_login, u.date_joined FROM "%s" u JOIN "%s" e ON e.%s = u.id WHERE e.id = ANY(%%s) ORDER BY 1' % (ut, et, ucol), [eids or [0]])[1]:
            print("  ", r)
except Exception as e:
    connection.rollback()
    print("employee linkage could not be read:", type(e).__name__, str(e)[:140])

print("\n-- ANY vendor-side lifecycle activity in the window on ANY job (is a real vendor using the system at all?)")
if table_exists("workforce_job_lifecycle_event"):
    for r in run("""SELECT event_type, count(*), count(DISTINCT employee_id), min(created_at), max(created_at)
                    FROM workforce_job_lifecycle_event WHERE created_at >= %s GROUP BY 1 ORDER BY 2 DESC""", [SINCE_UTC])[1]:
        print("  ", r)
print("\n-- vendor vehicles by class/active (eligibility context; counts only)")
if table_exists("workforce_vehicle"):
    vc = [c for c in columns("workforce_vehicle") if re.search(r"(class|type|active|status|approved|verified)", c, re.I)]
    print("   grouping columns:", vc)
    if vc:
        for r in run('SELECT %s, count(*) FROM workforce_vehicle GROUP BY %s ORDER BY count(*) DESC LIMIT 40'
                     % (", ".join('"%s"' % c for c in vc[:4]), ", ".join('"%s"' % c for c in vc[:4])))[1]:
            print("  ", r)

# ------------------------------------------------------------------ 9. migrations
hdr("9. VENDOR MIGRATION STATE (read-only graph inspection; nothing is applied)")
try:
    from django.db.migrations.executor import MigrationExecutor
    ex = MigrationExecutor(connection)
    conflicts = ex.loader.detect_conflicts()
    print("conflicting leaf nodes (must be empty):", conflicts or "none")
    plan = ex.migration_plan(ex.loader.graph.leaf_nodes())
    print("UNAPPLIED migrations (code has them, DB does not):", [f"{m.app_label}.{m.name}" for m, _ in plan] or "none")
    print("latest applied per app (vendor-relevant apps):")
    for r in run("""SELECT app, max(name), max(applied), count(*) FROM django_migrations
                    WHERE app IN ('workforce_api','accounts','service_requests','logistics','settings_hub','orders','customer_analytics')
                    GROUP BY 1 ORDER BY 1""")[1]:
        print("  ", r)
    print("django_migrations total:", run("SELECT count(*), min(applied), max(applied) FROM django_migrations")[1][0])
    print("applied in DB but missing from this code checkout (possible code/schema mismatch):")
    on_disk = set(ex.loader.disk_migrations.keys())
    applied = {(a, n) for a, n in run("SELECT app, name FROM django_migrations")[1]}
    print("  ", sorted(applied - on_disk)[:40] or "none")
except Exception as e:
    connection.rollback()
    print("migration inspection failed:", type(e).__name__, str(e)[:160])

print("\nAUDIT COMPLETE: nothing was written (session was read-only).")
