"""
GT waiting (detention) charge computation.

Pure, read-only: derives loading/unloading dwell time from the append-only
ServiceRequest.logistics_leg_history ({"leg", "at", "by"} entries written by
services/logistics_events.py) and prices it with the admin-configured
WorkforceServicePricingPolicy waiting_* fields. Nothing here writes to the
booking, the fare, JobPayment or the wallet -- wiring the result into billing
is a separate, test-gated step (see the GT ownership report).

Every value is configuration: with no policy, a null free window, or a zero
per-minute rate, the charge is zero.
"""
import math
from datetime import datetime
from decimal import Decimal, ROUND_HALF_UP

ZERO = Decimal("0.00")
CENT = Decimal("0.01")

# Leg names come from ServiceRequest.LogisticsLeg (GT legs + P&M legs).
LOADING_START = ("ARRIVED_PICKUP", "LOADING")
LOADING_END = ("EN_ROUTE_DROP", "IN_TRANSIT")
UNLOADING_START = ("ARRIVED_DROP", "UNLOADING")
UNLOADING_END = ("DELIVERED", "COMPLETED")


def _parse(ts):
    if isinstance(ts, datetime):
        return ts
    if not ts:
        return None
    try:
        return datetime.fromisoformat(str(ts).replace("Z", "+00:00"))
    except ValueError:
        return None


def _first_at(history, legs):
    """Earliest timestamp among history entries whose leg is in `legs`."""
    found = [
        _parse(h.get("at"))
        for h in (history or [])
        if isinstance(h, dict) and h.get("leg") in legs
    ]
    found = [t for t in found if t is not None]
    return min(found) if found else None


def _dwell_minutes(history, start_legs, end_legs):
    start = _first_at(history, start_legs)
    end = _first_at(history, end_legs)
    if start is None or end is None or end <= start:
        return 0
    return math.ceil((end - start).total_seconds() / 60)


def compute_waiting_charge(history, policy):
    """
    history: ServiceRequest.logistics_leg_history (list of dicts).
    policy: a WorkforceServicePricingPolicy (or any object with the waiting_*
            attributes), or None.

    Returns a dict breakdown; "amount" is a Decimal (0.00 when disabled).
    """
    loading = _dwell_minutes(history, LOADING_START, LOADING_END)
    unloading = _dwell_minutes(history, UNLOADING_START, UNLOADING_END)
    result = {
        "loading_minutes": loading,
        "unloading_minutes": unloading,
        "billable_minutes": 0,
        "rate_per_minute": ZERO,
        "cap": None,
        "amount": ZERO,
        "enabled": False,
    }
    if policy is None:
        return result

    rate = Decimal(str(getattr(policy, "waiting_charge_per_minute", 0) or 0))
    free_load = getattr(policy, "waiting_free_loading_minutes", None)
    free_unload = getattr(policy, "waiting_free_unloading_minutes", None)
    cap = getattr(policy, "waiting_charge_cap", None)
    if rate <= 0 or (free_load is None and free_unload is None):
        return result

    billable = 0
    if free_load is not None:
        billable += max(0, loading - int(free_load))
    if free_unload is not None:
        billable += max(0, unloading - int(free_unload))

    amount = (rate * billable).quantize(CENT, rounding=ROUND_HALF_UP)
    if cap is not None:
        amount = min(amount, Decimal(str(cap)).quantize(CENT))
    result.update(
        billable_minutes=billable,
        rate_per_minute=rate,
        cap=Decimal(str(cap)) if cap is not None else None,
        amount=amount,
        enabled=True,
    )
    return result


def customer_policy_for(category):
    """The Customer app's GTWaitingChargePolicy for `category` (category row
    first, then the platform-wide blank row), or None. Never raises."""
    try:
        from service_requests.models import GTWaitingChargePolicy

        cat = str(category or "").strip().lower()
        qs = GTWaitingChargePolicy.objects.filter(is_active=True)
        return (
            qs.filter(service_category__iexact=cat).first()
            or qs.filter(service_category="").first()
        )
    except Exception:
        return None


_HISTORY_CATEGORIES = ("goods_transport_truck", "goods_transport_two_wheeler")


def waiting_charge_for_booking(booking):
    """
    Waiting charge shown to the driver. Single source of truth is the
    Customer GTWaitingChargePolicy (free_minutes_per_stop, rate_per_minute,
    max_charge_per_booking, is_enabled) -- identical semantics to its
    charge_for(): per-TripStop dwell when stops exist, otherwise the
    leg-history loading/unloading windows for the distance-priced GT
    categories. Disabled / missing policy => enabled False, amount 0.
    """
    category = str(getattr(booking, "service_category", "") or "").strip().lower()
    history = getattr(booking, "logistics_leg_history", None) or []
    loading = _dwell_minutes(history, LOADING_START, LOADING_END)
    unloading = _dwell_minutes(history, UNLOADING_START, UNLOADING_END)
    result = {
        "loading_minutes": loading,
        "unloading_minutes": unloading,
        "billable_minutes": 0,
        "rate_per_minute": ZERO,
        "cap": None,
        "amount": ZERO,
        "enabled": False,
    }
    policy = customer_policy_for(category)
    if policy is None or not policy.is_enabled or not policy.is_active:
        return result
    rate = Decimal(str(policy.rate_per_minute or 0))
    free = int(policy.free_minutes_per_stop or 0)

    stops = []
    try:
        stops = list(booking.trip_stops.all())
    except Exception:
        stops = []
    billable = 0
    if stops:
        for stop in stops:
            if not stop.arrived_at or not stop.completed_at:
                continue
            secs = (stop.completed_at - stop.arrived_at).total_seconds()
            if secs <= 0:
                continue
            billable += max(0, int(secs // 60) - free)
    elif category in _HISTORY_CATEGORIES:
        billable = max(0, loading - free) + max(0, unloading - free)

    amount = (rate * billable).quantize(CENT, rounding=ROUND_HALF_UP)
    cap = policy.max_charge_per_booking
    if cap is not None:
        amount = min(amount, Decimal(str(cap)).quantize(CENT))
    result.update(
        billable_minutes=billable,
        rate_per_minute=rate,
        cap=Decimal(str(cap)) if cap is not None else None,
        amount=amount,
        enabled=True,
    )
    return result
