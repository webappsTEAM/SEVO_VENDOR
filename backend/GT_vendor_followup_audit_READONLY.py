"""SEVO GT -- VENDOR-SIDE FOLLOW-UP audit.  STRICTLY READ ONLY.

Run in the VENDOR backend, UNEDITED:
    python manage.py shell < GT_vendor_followup_audit_READONLY.py > vendor_followup_out.txt

Answers: (1) are there any vendors/vehicles at all, (2) which job did the Oct-1 acceptance belong to,
(3) why did GT jobs 42/43 get a 'DISPATCHED' flag but no dispatch state / offers -- by comparing EVERY booking.
Read-only session is forced first. No names/e-mails/phones/tokens/addresses are read; people are numeric ids.
Missing tables print exactly: TABLE/RECORD NOT AVAILABLE
"""
import re
from django.db import connection

DROP = re.compile(r"(e?mail|phone|mobile|password|token|secret|otp|first_name|last_name|full_name|^name$|"
                  r"signature|photo|image|avatar|aadhaar|pan_|bank|account_number|ifsc|upi|key$|hash|address|"
                  r"license|licence|rc_number|plate|registration)", re.I)


def hdr(t):
    print("\n" + "=" * 8, t, "=" * 8)


def run(sql, params=None, limit=None):
    with connection.cursor() as c:
        c.execute(sql, params or [])
        cols = [d[0] for d in c.description] if c.description else []
        rows = c.fetchmany(limit) if limit else c.fetchall()
    return cols, rows


def exists(t):
    return bool(run("SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name=%s", [t])[1])


def cols_of(t):
    return [r[0] for r in run("SELECT column_name FROM information_schema.columns WHERE table_schema='public' "
                              "AND table_name=%s ORDER BY ordinal_position", [t])[1]]


def show(sql, params=None, limit=300):
    try:
        cs, rows = run(sql, params, limit)
        for r in rows:
            print("  ", {c: (str(v) if v is not None else None) for c, v in zip(cs, r)})
        if not rows:
            print("   (no rows)")
        return rows
    except Exception as e:
        connection.rollback()
        print("   could not read:", type(e).__name__, str(e)[:150])
        return []


def dump(title, table, where="TRUE", params=None, order="1", limit=200):
    print("\n-- %s  [%s]" % (title, table))
    if not exists(table):
        print("   TABLE/RECORD NOT AVAILABLE")
        return
    keep = [c for c in cols_of(table) if not DROP.search(c)]
    show('SELECT %s FROM "%s" WHERE %s ORDER BY %s LIMIT %d' % (", ".join('"%s"' % c for c in keep), table, where, order, limit), params, limit)


hdr("0. SESSION")
with connection.cursor() as c:
    c.execute("SET default_transaction_read_only = on")
    c.execute("SET statement_timeout = '45s'")
    c.execute("SHOW default_transaction_read_only")
    print("session read-only:", c.fetchone()[0])
    c.execute("SELECT current_database(), now()")
    print(c.fetchone())

hdr("1. WHO CAN RECEIVE GT JOBS? employees, companies, vehicles (counts + non-PII flags)")
for t in ("employees_employee", "workforce_vehicle"):
    print("\n-- %s" % t)
    if not exists(t):
        print("   TABLE/RECORD NOT AVAILABLE")
        continue
    print("   total rows:", run('SELECT count(*) FROM "%s"' % t)[1][0][0])
    flags = [c for c in cols_of(t) if re.search(r"(^status$|is_active|active|approved|verified|vehicle_type|vehicle_class|^role$|employee_type|online|available|on_duty|company_id|vendor)", c, re.I) and not DROP.search(c)]
    print("   flag columns:", flags)
    if flags:
        g = ", ".join('"%s"' % c for c in flags[:5])
        show('SELECT %s, count(*) AS n FROM "%s" GROUP BY %s ORDER BY n DESC LIMIT 60' % (g, t, g))
dump("employees (non-PII columns)", "employees_employee", "TRUE", None, "1", 60)
dump("vehicles (non-PII columns)", "workforce_vehicle", "TRUE", None, "1", 60)
for t, in run("SELECT table_name FROM information_schema.tables WHERE table_schema='public' AND table_name ~* '(^|_)(company|vendor|provider)(_|$)' ORDER BY 1")[1]:
    try:
        print("\n-- %s rows:" % t, run('SELECT count(*) FROM "%s"' % t)[1][0][0])
    except Exception:
        connection.rollback()

hdr("2. THE OCT-1 'EMPLOYEE_JOB_ACCEPTED' EVENT: which job, which employee, what happened next")
dump("lifecycle events (ALL, any job)", "workforce_job_lifecycle_event", "TRUE", None, "created_at", 200)
show("""SELECT s.id, s.request_id, s.service_category, s.status, s.created_at, s.customer_id, s.dispatch_status,
               s.assigned_employee_id, s.vendor_id, s.accepted_at, s.started_at, s.completed_at, s.total_amount
        FROM service_requests_servicerequest s
        WHERE s.id IN (SELECT job_id FROM workforce_job_lifecycle_event)""")

hdr("3. EVERY BOOKING vs ITS DISPATCH RECORDS (why do 42/43 differ from the rest?)")
show("""SELECT s.id, s.service_category, s.status, s.dispatch_status, s.dispatch_attempts,
               left(coalesce(s.last_dispatch_error,''),60) AS last_dispatch_error,
               s.last_dispatched_at IS NOT NULL AS was_dispatched, s.workforce_job_id, s.assigned_employee_id, s.vendor_id, s.company_id,
               (SELECT count(*) FROM workforce_dispatch_state d WHERE d.job_id = s.id) AS dispatch_state_rows,
               (SELECT count(*) FROM workforce_job_offer o WHERE o.job_id = s.id) AS offers,
               (SELECT count(*) FROM workforce_notification n WHERE n.related_object_id = s.id::text) AS notifications,
               s.created_at
        FROM service_requests_servicerequest s ORDER BY s.id""", None, 200)
print("\n-- dispatch_status distribution (all bookings)")
show("SELECT service_category, dispatch_status, count(*) FROM service_requests_servicerequest GROUP BY 1,2 ORDER BY 1,2")

hdr("4. ALL DISPATCH STATE / OFFER ROWS THAT EXIST AT ALL (any job)")
dump("workforce_dispatch_state (ALL)", "workforce_dispatch_state", "TRUE", None, "job_id", 100)
if exists("workforce_job_offer"):
    show("SELECT count(*) AS offers_total, count(DISTINCT job_id) AS jobs, count(DISTINCT employee_id) AS employees, min(offered_at), max(offered_at) FROM workforce_job_offer")
    dump("most recent offers", "workforce_job_offer", "TRUE", None, "offered_at DESC", 30)

hdr("5. DISPATCH / GT SETTINGS THAT GOVERN ELIGIBILITY (non-secret keys only)")
for t, in run("SELECT table_name FROM information_schema.tables WHERE table_schema='public' AND table_name ~* '(system_setting|dispatch_config|dispatch_setting|workforce_setting)' ORDER BY 1")[1]:
    ks = [c for c in cols_of(t)]
    kc = next((c for c in ks if c in ("key", "name", "setting_key")), None)
    vc = next((c for c in ks if c in ("value", "setting_value")), None)
    print("\n-- %s columns: %s" % (t, ks))
    if kc and vc:
        show('SELECT "%s" AS k, left("%s"::text,80) AS v FROM "%s" WHERE "%s" ~* %%s AND "%s" !~* %%s ORDER BY 1' % (kc, vc, t, kc, kc),
             ["(dispatch|wave|radius|offer|expir|gt_|goods|logistics|eligib|vehicle)", "(secret|token|password|key_|_key|razorpay|smtp|api)"], 80)
    else:
        print("   (no key/value columns recognised; table left unread)")

print("\nAUDIT COMPLETE: nothing was written (session was read-only).")
