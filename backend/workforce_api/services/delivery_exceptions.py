"""
Driver-side report of a trip exception (customer unreachable, receiver unavailable, ...).

Mirrors service_requests/services/delivery_exception.py on the Customer app -- the codes must
match, because the Customer app ignores unknown types. Reporting never cancels or reprices the
trip: Porter publishes no automatic fee for these cases, so the decision stays with support.
"""
import logging

from django.utils import timezone

logger = logging.getLogger(__name__)

EXCEPTION_TYPES = {
    "CUSTOMER_UNREACHABLE_AT_PICKUP": ("Customer not reachable at pickup", ("EN_ROUTE_PICKUP", "LOADING", "")),
    "PICKUP_ADDRESS_ISSUE": ("Pickup address could not be found", ("EN_ROUTE_PICKUP", "")),
    "RECEIVER_UNAVAILABLE": ("Receiver not available at drop", ("EN_ROUTE_DROP", "UNLOADING")),
    "RECEIVER_REFUSED": ("Receiver refused the delivery", ("EN_ROUTE_DROP", "UNLOADING")),
    "DROP_ADDRESS_ISSUE": ("Drop address could not be found", ("EN_ROUTE_DROP", "UNLOADING")),
}


def exception_error(code, leg, notes):
    if code not in EXCEPTION_TYPES:
        return f"Unknown exception type. Choose one of: {', '.join(EXCEPTION_TYPES)}"
    if leg not in EXCEPTION_TYPES[code][1]:
        return f"'{code}' cannot be reported while the trip is at stage '{leg or 'not started'}'."
    if len((notes or "").strip()) < 5:
        return "Please add a short note describing what happened."
    return None


def report_delivery_exception(job, emp, code, notes, actor=None):
    """Audit-log the report and tell the Customer app. Returns the reported_at ISO string."""
    from workforce_api.models import WorkforceEventLog
    from workforce_api.services.customer_webhook import notify_customer_app

    leg = str(job.logistics_leg or "").strip().upper()
    reported_at = timezone.now().isoformat()
    WorkforceEventLog.objects.create(
        user=getattr(emp, "user", None),
        event_type="LOGISTICS_DELIVERY_EXCEPTION",
        payload={"job_id": job.id, "employee_id": emp.id, "exception_type": code, "leg": leg,
                 "notes": notes.strip()[:500], "reported_at": reported_at},
    )
    notify_customer_app(
        "logistics.delivery_exception", job,
        exception_type=code, notes=notes.strip()[:500], leg=leg, reported_at=reported_at,
    )
    return reported_at
