"""
workforce_api/services/logistics_events.py

The driver-side half of the Goods & Transport lifecycle contract.

The Customer app consumes four logistics events -- `logistics.leg_changed`,
`trip.stop_arrived`, `trip.stop_completed` and a rich
`job.completion_proof_submitted`. This module is where the vendor side
emits them, and where the leg-progression rules live, so the views stay
thin (CLAUDE.md: business logic never in views).

Why events at all, when both apps share one database?
Leg and stop columns live on the shared ServiceRequest/TripStop tables, so
a customer polling their tracking endpoint would eventually see a change
written here regardless. The webhook adds the two things a shared column
cannot: an immediate WebSocket broadcast to a customer watching the map
right now, and the Customer app's own side effects (proof records,
recipient notification, fare reconciliation). Emission is fire-and-forget
via notify_customer_app(), so a webhook failure never blocks or undoes the
driver's action -- the shared row is still correct either way. That makes
the webhook an enhancement over the shared table, not a single point of
failure for it.

The driver-visible trip flow this supports:

    accept -> EN_ROUTE_PICKUP -> (arrive at pickup stop) -> LOADING
           -> EN_ROUTE_DROP -> (arrive at drop stop) -> UNLOADING
           -> proof of delivery -> DELIVERED
"""
import logging

from django.db import transaction
from django.utils import timezone

logger = logging.getLogger(__name__)

# Forward-only ordering for the trip. Index position is the rule: a leg may
# be repeated (idempotent) or skipped forward (a driver who never signals
# LOADING should not be blocked from signalling EN_ROUTE_DROP), but never
# moved backwards -- a trip that has reached DELIVERED cannot claim to be
# EN_ROUTE_PICKUP again, and accepting that would corrupt both the customer's
# tracking view and the leg audit trail.
LEG_SEQUENCE = [
    "EN_ROUTE_PICKUP",
    "LOADING",
    "EN_ROUTE_DROP",
    "UNLOADING",
    "DELIVERED",
]

PM_LEG_SEQUENCE = [
    "ASSIGNED",
    "TEAM_EN_ROUTE",
    "ARRIVED_PICKUP",
    "PACKING",
    "DISMANTLING",
    "LOADING",
    "IN_TRANSIT",
    "ARRIVED_DROP",
    "UNLOADING",
    "REASSEMBLY",
    "UNPACKING",
    "DELIVERED",
    "COMPLETED",
]

ALL_VALID_LEGS = set(LEG_SEQUENCE) | set(PM_LEG_SEQUENCE)


PM_SPECIFIC_LEGS = {
    "ASSIGNED", "TEAM_EN_ROUTE", "ARRIVED_PICKUP", "PACKING", "DISMANTLING",
    "IN_TRANSIT", "ARRIVED_DROP", "REASSEMBLY", "UNPACKING", "COMPLETED"
}

# Category aliases, kept in step with automatic_dispatch.normalize_service_category
# (inlined rather than imported to avoid a services import cycle).
GT_CATEGORY_ALIASES = {
    "goods_transport_truck", "truck", "mini_truck",
    "goods_transport_two_wheeler", "two_wheeler", "2_wheeler",
}
# Only the canonical slug: the vendor frontend (LogisticsLegController
# isPackersMoversJob) recognises P&M by this slug or by title, so pinning
# other aliases here could reject legs the UI legitimately sends.
PM_CATEGORY_ALIASES = {"packers_movers"}


def _normalise_category(service_category):
    return str(service_category or "").strip().lower().replace("-", "_").replace(" ", "_")


def get_sequence_for_job(service_category=None, current_leg=None, target_leg=None):
    """
    Determines whether to use standard goods transport sequence or relocation
    sequence.

    A booking whose category is a known goods-transport category is pinned to
    the GT sequence and a known Packers & Movers category to the P&M
    sequence. Previously any P&M-only leg in the request (e.g. IN_TRANSIT or
    COMPLETED) silently switched a GT truck booking onto the P&M sequence,
    letting a GT trip jump straight to P&M-only states the Customer app's GT
    tracking does not know about. The leg-based guess is kept only for
    blank/unknown categories.
    """
    cat = _normalise_category(service_category)
    if cat in GT_CATEGORY_ALIASES:
        return LEG_SEQUENCE
    if cat in PM_CATEGORY_ALIASES:
        return PM_LEG_SEQUENCE
    if current_leg in PM_SPECIFIC_LEGS or target_leg in PM_SPECIFIC_LEGS:
        return PM_LEG_SEQUENCE
    return LEG_SEQUENCE


def leg_rank(leg, sequence=None):
    """Position of `leg` in the trip, or -1 for a blank/unknown value."""
    seq = sequence or LEG_SEQUENCE
    try:
        return seq.index(leg)
    except ValueError:
        return -1


def can_advance_to(current_leg, target_leg, service_category=None):
    """
    (allowed, reason). Forward-only; repeats are allowed and handled as
    no-ops by the caller so a retried request stays idempotent.
    """
    seq = get_sequence_for_job(service_category, current_leg, target_leg)
    if target_leg not in ALL_VALID_LEGS or target_leg not in seq:
        return False, f"Invalid leg '{target_leg}'. Choose one of: {', '.join(seq)}"
    if not current_leg:
        return True, ""
    
    curr_rank = leg_rank(current_leg, seq)
    tgt_rank = leg_rank(target_leg, seq)
    if curr_rank != -1 and tgt_rank != -1 and tgt_rank < curr_rank:
        return False, (
            f"Cannot move the trip backwards from '{current_leg}' to '{target_leg}'."
        )
    return True, ""



# Legs that declare the goods handed over. The forward-only rule above still
# lets a driver skip optional middle legs (e.g. DISMANTLING), but nothing
# stopped these final legs being set while the job was only `accepted` --
# before the driver had even arrived or started the job. DELIVERED is what
# the Customer app's fare reconciliation and the waiting-charge window key
# off, so reaching it must at least require the job to have been started.
FINAL_LEGS = {"DELIVERED", "COMPLETED"}
FINAL_LEG_ALLOWED_STATUSES = {"in_progress", "on_hold", "proof_submitted", "follow_up_required"}


def final_leg_status_error(job_status, leg):
    """Return an error message when `leg` is a final leg the job's status
    does not yet permit, else ""."""
    leg = (leg or "").strip().upper()
    status = str(job_status or "").lower()
    if leg in FINAL_LEGS and status not in FINAL_LEG_ALLOWED_STATUSES:
        return (
            f"Cannot mark the trip '{leg}' while the job is '{status}'. "
            "Start the job at pickup first."
        )
    return ""


def initial_leg_for_category(service_category):
    """First leg set automatically when a logistics job is accepted: the GT
    trip starts EN_ROUTE_PICKUP; a Packers & Movers job starts ASSIGNED (its
    sequence has no EN_ROUTE_PICKUP, so setting that was silently rejected
    and P&M jobs previously started with a blank leg)."""
    seq = get_sequence_for_job(service_category)
    return seq[0] if seq is PM_LEG_SEQUENCE else "EN_ROUTE_PICKUP"


def set_logistics_leg(job, leg, actor=None):
    """
    Advance a job's logistics leg on the shared ServiceRequest row and tell
    the Customer app.

    Returns (changed, error). `changed` is False for an idempotent repeat of
    the leg the job is already on -- not an error, since the driver app may
    retry. `error` is a message when the move was rejected.

    Mirrors ServiceRequest.set_logistics_leg() in the Customer app: same
    append-only history shape ({"leg", "at", "by"}), same idempotency. The
    two implementations are separate because this app's ServiceRequest is an
    unmanaged mirror model without the Customer app's methods, which is the
    established pattern for every shared table here.
    """
    leg = (leg or "").strip().upper()

    if hasattr(job, "pk") and job.pk and hasattr(type(job), "objects"):
        with transaction.atomic():
            locked = type(job).objects.select_for_update().filter(pk=job.pk).first()
            target = locked if locked is not None else job

            allowed, reason = can_advance_to(target.logistics_leg, leg, service_category=target.service_category)
            if not allowed:
                return False, reason

            if target.logistics_leg == leg:
                job.logistics_leg = target.logistics_leg
                job.logistics_leg_updated_at = target.logistics_leg_updated_at
                job.logistics_leg_history = target.logistics_leg_history
                return False, ""

            now = timezone.now()
            history = list(target.logistics_leg_history or [])
            if not any(h.get("leg") == leg for h in history):
                history.append({
                    "leg": leg,
                    "at": now.isoformat(),
                    "by": getattr(actor, "id", None),
                })
            target.logistics_leg = leg
            target.logistics_leg_updated_at = now
            target.logistics_leg_history = history
            target.save(update_fields=[
                "logistics_leg", "logistics_leg_updated_at", "logistics_leg_history", "updated_at",
            ])
            job.logistics_leg = target.logistics_leg
            job.logistics_leg_updated_at = target.logistics_leg_updated_at
            job.logistics_leg_history = target.logistics_leg_history
    else:
        allowed, reason = can_advance_to(job.logistics_leg, leg, service_category=getattr(job, "service_category", None))
        if not allowed:
            return False, reason

        if job.logistics_leg == leg:
            return False, ""

        now = timezone.now()
        history = list(job.logistics_leg_history or [])
        if not any(h.get("leg") == leg for h in history):
            history.append({
                "leg": leg,
                "at": now.isoformat(),
                "by": getattr(actor, "id", None),
            })
        job.logistics_leg = leg
        job.logistics_leg_updated_at = now
        job.logistics_leg_history = history
        if hasattr(job, "save"):
            job.save(update_fields=[
                "logistics_leg", "logistics_leg_updated_at", "logistics_leg_history", "updated_at",
            ])

    emit_leg_changed(job, leg)
    return True, ""


def emit_leg_changed(job, leg):
    try:
        from workforce_api.services.customer_webhook import notify_customer_app
        notify_customer_app("logistics.leg_changed", job, leg=leg)
    except Exception as exc:
        logger.info("Could not emit logistics.leg_changed for job %s: %s", job.id, exc)


def emit_stop_progress(job, stop, completed):
    event = "trip.stop_completed" if completed else "trip.stop_arrived"
    try:
        from workforce_api.services.customer_webhook import notify_customer_app
        notify_customer_app(
            event, job,
            stop_id=stop.id,
            stop_sequence=stop.sequence,
            stop_type=stop.stop_type,
            completed=bool(completed),
        )
    except Exception as exc:
        logger.info("Could not emit %s for job %s: %s", event, job.id, exc)


def record_stop_progress(job, stop, completed, actor=None):
    """
    Mark a stop arrived (and optionally completed) on the shared table, then
    tell the Customer app.

    Idempotent in the way that matters: an existing timestamp is never
    rewritten, so a retried request cannot drag the trip timeline forward.
    A completion for a stop whose arrival was never reported still produces
    a coherent timeline rather than a half-filled row.
    """
    now = timezone.now()
    fields = []
    
    if hasattr(stop, "pk") and stop.pk and hasattr(type(stop), "objects"):
        with transaction.atomic():
            locked_stop = type(stop).objects.select_for_update().filter(pk=stop.pk).first()
            target = locked_stop if locked_stop is not None else stop
            if target.arrived_at is None:
                target.arrived_at = now
                fields.append("arrived_at")
            if completed and target.completed_at is None:
                target.completed_at = now
                fields.append("completed_at")
            if fields:
                target.save(update_fields=fields)
            stop.arrived_at = target.arrived_at
            stop.completed_at = target.completed_at
    else:
        if stop.arrived_at is None:
            stop.arrived_at = now
            fields.append("arrived_at")
        if completed and stop.completed_at is None:
            stop.completed_at = now
            fields.append("completed_at")
        if fields and hasattr(stop, "save"):
            stop.save(update_fields=fields)

    emit_stop_progress(job, stop, completed)
    return bool(fields)


def emit_completion_proof(job, *, notes="", photo_url="", signature_url="",
                          recipient_name="", recipient_phone="", stop=None,
                          otp_verified=False, technician_name="",
                          workforce_employee_id="", location=None):
    """
    The rich `job.completion_proof_submitted` payload.

    Previously this event carried only free-text remarks, and the Customer
    app could do nothing with it but append them to the booking description.
    It now carries the actual evidence, which is what the receiver turns
    into DeliveryProof rows.

    Image references are passed as URLs into this app's own media storage
    rather than re-uploading the bytes: the Customer app deliberately stores
    the reference it is given instead of pulling someone else's file into its
    media root from inside a webhook handler.
    """
    payload = {
        "notes": notes or "",
        "otp_verified": bool(otp_verified),
        "technician_name": technician_name or "",
        "workforce_employee_id": str(workforce_employee_id or ""),
    }
    if photo_url:
        payload["photo_url"] = photo_url
    if signature_url:
        payload["signature_url"] = signature_url
    if recipient_name:
        payload["recipient_name"] = recipient_name
    if recipient_phone:
        payload["recipient_phone"] = recipient_phone
    if stop is not None:
        payload["stop_id"] = stop.id
        payload["stop_sequence"] = stop.sequence
    if location:
        payload["location"] = location

    try:
        from workforce_api.services.customer_webhook import notify_customer_app
        notify_customer_app("job.completion_proof_submitted", job, **payload)
    except Exception as exc:
        logger.info("Could not emit job.completion_proof_submitted for job %s: %s", job.id, exc)


def absolute_media_url(request, file_field):
    """
    Build an absolute URL for an uploaded proof file, so the Customer app
    stores a reference it can actually resolve. Returns "" when there is no
    file -- callers omit the key entirely in that case.
    """
    try:
        if not file_field:
            return ""
        url = file_field.url
        if request is not None:
            return request.build_absolute_uri(url)
        return url
    except Exception:
        return ""
