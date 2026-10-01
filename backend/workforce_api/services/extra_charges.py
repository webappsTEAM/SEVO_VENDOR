"""
Driver-side toll / parking receipt. The Customer GTExtraChargePolicy (mirrored) is the only source
of truth for what is accepted; the Customer app re-validates and bills. Mirrors
service_requests/services/extra_charges.py on the Customer app.
"""
import re
import uuid
from decimal import Decimal, InvalidOperation, ROUND_HALF_UP

from django.utils import timezone

TYPES = {"TOLL": "Toll", "PARKING": "Parking"}
CENT = Decimal("0.01")


def _amount(v):
    try:
        d = Decimal(str(v)).quantize(CENT, rounding=ROUND_HALF_UP)
    except (InvalidOperation, ValueError, TypeError):
        return None
    # Decimal("NaN") quantizes without error and then raises on comparison; reject non-finite values.
    if not d.is_finite():
        return None
    return d if d > 0 else None


_CHARGE_ID_RE = re.compile(r"^[A-Za-z0-9_\-]{1,64}$")


def clean_charge_id(value):
    """Client-supplied idempotency key: a short token, otherwise the server mints one."""
    if isinstance(value, str) and _CHARGE_ID_RE.match(value.strip()):
        return value.strip()
    return uuid.uuid4().hex[:12]


def charge_already_reported(job, charge_id):
    """True when this driver-side receipt id was already reported for the job (retry / double-tap)."""
    from workforce_api.models import WorkforceEventLog
    return any(
        (e.payload or {}).get("job_id") == job.id
        for e in WorkforceEventLog.objects.filter(event_type="LOGISTICS_EXTRA_CHARGE", payload__charge_id=charge_id)
    )


def applied_total(job):
    items = getattr(job, "extra_charges", None)
    total = Decimal("0.00")
    for e in (items if isinstance(items, list) else []):
        if isinstance(e, dict) and e.get("status") == "APPLIED":
            total += Decimal(str(e.get("amount") or 0))
    return total


def policy_for(job):
    try:
        from service_requests.models import get_gt_extra_charge_policy
        return get_gt_extra_charge_policy(getattr(job, "service_category", ""))
    except Exception:
        return None


def charge_error(policy, kind, amount, current_total=Decimal("0.00")):
    if policy is None:
        return "Toll and parking pass-through is not enabled."
    if kind not in TYPES:
        return f"Unknown charge type. Choose one of: {', '.join(TYPES)}"
    if (kind == "TOLL" and not policy.allow_toll) or (kind == "PARKING" and not policy.allow_parking):
        return f"{TYPES[kind]} charges are not accepted."
    amt = _amount(amount)
    if amt is None:
        return "Enter the receipt amount."
    if policy.max_amount_per_item is not None and amt > policy.max_amount_per_item:
        return f"A single receipt cannot exceed {policy.max_amount_per_item}."
    if policy.max_total_per_booking is not None and current_total + amt > policy.max_total_per_booking:
        return f"Total pass-through for a booking cannot exceed {policy.max_total_per_booking}."
    return None


def report_extra_charge(job, emp, kind, amount, note="", receipt="", charge_id=None, receipt_photo_url=""):
    from workforce_api.models import WorkforceEventLog
    from workforce_api.services.customer_webhook import notify_customer_app

    charge_id = clean_charge_id(charge_id)
    if charge_already_reported(job, charge_id):
        return charge_id
    amt = str(_amount(amount))
    reported_at = timezone.now().isoformat()
    WorkforceEventLog.objects.create(
        user=getattr(emp, "user", None), event_type="LOGISTICS_EXTRA_CHARGE",
        payload={"job_id": job.id, "employee_id": emp.id, "charge_type": kind, "amount": amt,
                 "charge_id": charge_id, "receipt": receipt[:500], "receipt_photo_url": receipt_photo_url[:500],
                 "reported_at": reported_at},
    )
    notify_customer_app(
        "logistics.extra_charge", job, charge_type=kind, amount=amt, note=note[:200],
        receipt=receipt[:500], receipt_photo_url=receipt_photo_url[:500], charge_id=charge_id, reported_at=reported_at,
    )
    return charge_id
