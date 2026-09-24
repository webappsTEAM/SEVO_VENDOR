import os
import django

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "workforce_core.settings")
django.setup()

from workforce_api.models import WorkforceEventLog, WorkforceJobOffer
from service_requests.models import ServiceRequest

for jid in [5995, 5994, 5969, 5952, 5951, 5937, 5936]:
    sr = ServiceRequest.objects.filter(id=jid).first()
    ev_cnt = WorkforceEventLog.objects.filter(payload__job_id=jid).count()
    offers = list(WorkforceJobOffer.objects.filter(job_id=jid).values("id", "status", "expires_at"))
    print(f"Job #{jid}: status={sr.status if sr else 'N/A'}, ev_cnt={ev_cnt}, offers={offers}")
