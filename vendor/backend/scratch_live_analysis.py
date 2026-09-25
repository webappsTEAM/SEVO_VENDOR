import os
import django
from collections import defaultdict
from datetime import timedelta

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "workforce_core.settings")
django.setup()

from django.utils import timezone
from workforce_api.models import WorkforceEventLog, WorkforceDispatchState, WorkforceJobOffer
from service_requests.models import ServiceRequest

now = timezone.now()
print(f"Current server time: {now}")

# 1. Fetch latest 500 events
events_500 = list(WorkforceEventLog.objects.order_by("-id")[:500])
if not events_500:
    print("No events found in WorkforceEventLog.")
    exit(0)

newest_ev = events_500[0]
oldest_ev = events_500[-1]
time_span_s = (newest_ev.created_at - oldest_ev.created_at).total_seconds()
print(f"Sample span: Event #{oldest_ev.id} ({oldest_ev.created_at}) to #{newest_ev.id} ({newest_ev.created_at})")
print(f"Total time span for 500 events: {time_span_s:.2f} seconds ({time_span_s/60:.2f} minutes)")
print(f"Overall event rate: {len(events_500) / (time_span_s / 60):.2f} events/minute ({len(events_500) / time_span_s:.2f} events/sec)\n")

# Group by job_id and event_type
by_job = defaultdict(lambda: defaultdict(list))
dispatch_started_by_job = defaultdict(list)

for e in reversed(events_500):
    p = e.payload or {}
    jid = p.get("job_id")
    by_job[jid][e.event_type].append(e)
    if e.event_type == "DISPATCH_STARTED":
        dispatch_started_by_job[jid].append(e)

print(f"{'Job ID':<8} | {'Total Evs':<10} | {'STARTED':<8} | {'EVAL':<8} | {'UNASSIGN':<8} | {'Evs/min':<10} | {'STARTED/min':<12} | {'Avg Int (s)':<12}")
print("-" * 95)

for jid, type_dict in sorted(by_job.items(), key=lambda x: len(x[1].get("DISPATCH_STARTED", [])), reverse=True):
    total_for_job = sum(len(evs) for evs in type_dict.values())
    started_evs = type_dict.get("DISPATCH_STARTED", [])
    eval_evs = type_dict.get("CANDIDATES_EVALUATED", [])
    unassign_evs = type_dict.get("DISPATCH_UNASSIGNED_REASON", [])
    
    cnt_started = len(started_evs)
    cnt_eval = len(eval_evs)
    cnt_unassign = len(unassign_evs)
    
    evs_per_min = (total_for_job / (time_span_s / 60)) if time_span_s > 0 else 0
    started_per_min = (cnt_started / (time_span_s / 60)) if time_span_s > 0 else 0
    
    if cnt_started > 1:
        job_span = (started_evs[-1].created_at - started_evs[0].created_at).total_seconds()
        avg_int = job_span / (cnt_started - 1)
    else:
        avg_int = 0.0
        
    print(f"{str(jid):<8} | {total_for_job:<10} | {cnt_started:<8} | {cnt_eval:<8} | {cnt_unassign:<8} | {evs_per_min:<10.1f} | {started_per_min:<12.1f} | {avg_int:<12.2f}")
