import os
import django

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "workforce_core.settings")
django.setup()

from django.utils import timezone
from service_requests.models import ServiceRequest
from workforce_api.services.automatic_dispatch import DISPATCHABLE_STATUSES

today = timezone.localdate()
now = timezone.now()

today_dispatchable = ServiceRequest.objects.filter(
    status__in=DISPATCHABLE_STATUSES,
    assigned_employee__isnull=True,
    latitude__isnull=False,
    longitude__isnull=False,
).filter(
    preferred_date=today
)

print(f"Total dispatchable jobs for today ({today}): {today_dispatchable.count()}")
for j in today_dispatchable:
    print(f"Job #{j.id}: status={j.status}, issue={j.issue_title}, category={j.service_category}, created_at={j.created_at}")
