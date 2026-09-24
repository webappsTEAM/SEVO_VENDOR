import os
import django

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "workforce_core.settings")
django.setup()

from workforce_api.models import WorkforceEventLog, WorkforceDispatchState, WorkforceJobOffer
from service_requests.models import ServiceRequest

events = list(WorkforceEventLog.objects.filter(event_type="DISPATCH_STARTED").order_by("-id")[:20])

print(f"Top 20 Newest DISPATCH_STARTED Events:")
for e in events:
    p = e.payload or {}
    jid = p.get("job_id")
    st = WorkforceDispatchState.objects.filter(job_id=jid).first() if jid else None
    sr = ServiceRequest.objects.filter(id=jid).first() if jid else None
    
    act_cnt = WorkforceJobOffer.objects.filter(job_id=jid, status=WorkforceJobOffer.Status.OFFERED).count()
    exp_cnt = WorkforceJobOffer.objects.filter(job_id=jid, status=WorkforceJobOffer.Status.EXPIRED).count()
    acc_cnt = WorkforceJobOffer.objects.filter(job_id=jid, status=WorkforceJobOffer.Status.ACCEPTED).count()
    
    st_dict = {
        "dispatch_status": st.dispatch_status if st else "NO_RECORD",
        "attempt_count": st.attempt_count if st else None,
        "retry_at": str(st.retry_at) if st and st.retry_at else None,
        "locked_at": str(st.locked_at) if st and st.locked_at else None,
    }
    
    print(f"\nEvent #{e.id} | created_at={e.created_at} | job_id={jid}")
    print(f"  payload: {e.payload}")
    print(f"  ServiceRequest: status={sr.status if sr else 'N/A'}, pref_date={sr.preferred_date if sr else 'N/A'}, assigned_emp={sr.assigned_employee_id if sr else 'N/A'}")
    print(f"  WorkforceDispatchState: {st_dict}")
    print(f"  Offers: active(OFFERED)={act_cnt}, expired={exp_cnt}, accepted={acc_cnt}")
