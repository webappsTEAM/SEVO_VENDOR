"""
workforce_api/services/logistics_checkpoints.py

Verification gates for the two physical checkpoints of a logistics trip:
the PICKUP (goods loaded) and the DROP (goods handed over).

Before this, WorkforceJobLogisticsLegView let a driver click from
"To Pickup" straight through to "Delivered" with nothing but a button
press. The job-START gate (PreServiceVerification: GPS <= 250m, customer
start OTP, presence selfie) only protects the start of the job; nothing
proved the vehicle ever reached either end of the trip.

The same three kinds of evidence are now required at the checkpoints,
recorded per location in LogisticsCheckpointVerification (never in the
job-start record):

  Goods Transport (EN_ROUTE_PICKUP > LOADING > EN_ROUTE_DROP > UNLOADING > DELIVERED)
    LOADING        needs  pickup GPS
    EN_ROUTE_DROP  needs  pickup proof photo (goods loaded)
    UNLOADING      needs  drop GPS
    DELIVERED      needs  drop proof photo + delivery OTP

  Packers & Movers (explicit ARRIVED_* legs, so the GPS check sits on them)
    ARRIVED_PICKUP needs  pickup GPS
    IN_TRANSIT     needs  pickup proof photo
    ARRIVED_DROP   needs  drop GPS
    DELIVERED      needs  drop proof photo + delivery OTP

Gates are cumulative by leg rank, so the forward "skip ahead" the leg
sequence allows can never jump over a checkpoint.

No OTP at pickup: the customer's Work Start OTP is already verified at the
booking address before the job can start, and that address is the pickup
for a logistics booking -- a second pickup OTP would be redundant.
"""
import logging
import secrets
from datetime import timedelta

from django.conf import settings
from django.db import transaction
from django.utils import timezone

from workforce_api.services.logistics_events import (
    LEG_SEQUENCE,
    PM_LEG_SEQUENCE,
    get_sequence_for_job,
    leg_rank,
)

logger = logging.getLogger(__name__)

CHECKPOINT_RADIUS_METERS = 250.0
DELIVERY_OTP_TTL_MINUTES = 30
MAX_OTP_ATTEMPTS = 5

PICKUP = "PICKUP"
DROP = "DROP"
CHECKPOINTS = (PICKUP, DROP)

GPS = "gps"
PHOTO = "photo"
OTP = "otp"

# (first leg that needs it, checkpoint, requirement)
GT_GATES = [
    ("LOADING", PICKUP, GPS),
    ("EN_ROUTE_DROP", PICKUP, PHOTO),
    ("UNLOADING", DROP, GPS),
    ("DELIVERED", DROP, PHOTO),
    ("DELIVERED", DROP, OTP),
]
PM_GATES = [
    ("ARRIVED_PICKUP", PICKUP, GPS),
    ("IN_TRANSIT", PICKUP, PHOTO),
    ("ARRIVED_DROP", DROP, GPS),
    ("DELIVERED", DROP, PHOTO),
    ("DELIVERED", DROP, OTP),
]

REQUIREMENT_LABELS = {
    (PICKUP, GPS): "Pickup GPS check-in (within 250m of pickup)",
    (PICKUP, PHOTO): "Loading proof photo at pickup",
    (DROP, GPS): "Drop GPS check-in (within 250m of drop)",
    (DROP, PHOTO): "Unloading proof photo at drop",
    (DROP, OTP): "Customer delivery OTP",
}


def drop_otp_required(job):
    """Delivery OTP is only enforceable when there is a customer to send it
    to (same channel as the Work Start OTP). Settings kill-switch:
    LOGISTICS_DROP_OTP_REQUIRED = False."""
    if not getattr(settings, "LOGISTICS_DROP_OTP_REQUIRED", True):
        return False
    return bool(getattr(job, "customer_id", None))


def gates_for_job(job):
    seq = get_sequence_for_job(getattr(job, "service_category", None), getattr(job, "logistics_leg", None))
    return seq, (PM_GATES if seq is PM_LEG_SEQUENCE else GT_GATES)


def required_before(job, target_leg):
    """[(checkpoint, requirement)] that must be satisfied to move from the
    job's current leg to `target_leg`.

    Only gates lying between the two are checked (current < gate <= target):
    a gate the trip has already moved past was either enforced at the time
    or predates this feature (a job in flight at deploy), and re-demanding
    pickup evidence from a driver already at the drop would strand the job.
    """
    seq, gates = gates_for_job(job)
    tgt = leg_rank((target_leg or "").strip().upper(), seq)
    if tgt < 0:
        return []
    cur = leg_rank((getattr(job, "logistics_leg", None) or "").strip().upper(), seq)
    out = []
    for gate_leg, cp, req in gates:
        if req == OTP and not drop_otp_required(job):
            continue
        g = leg_rank(gate_leg, seq)
        if cur < g <= tgt:
            out.append((cp, req))
    return out


def _load_records(job):
    from workforce_api.models import LogisticsCheckpointVerification
    return {r.checkpoint: r for r in LogisticsCheckpointVerification.objects.filter(job_id=job.id)}


def checkpoint_state(job, records=None):
    """{"PICKUP": {"gps": bool, "photo": bool, "otp": bool, ...}, "DROP": {...}}"""
    if records is None:
        records = _load_records(job)
    state = {}
    for cp in CHECKPOINTS:
        r = records.get(cp)
        state[cp] = {
            GPS: bool(r and r.geofence_passed),
            PHOTO: bool(r and r.proof_photo),
            OTP: bool(r and r.otp_verified),
            "gps_verified_at": r.gps_verified_at.isoformat() if r and r.gps_verified_at else None,
            "photo_uploaded_at": r.photo_uploaded_at.isoformat() if r and r.photo_uploaded_at else None,
            "otp_verified_at": r.otp_verified_at.isoformat() if r and r.otp_verified_at else None,
            "otp_issued": bool(r and r.otp_code),
            "distance_m": round(r.distance_m, 1) if r and r.distance_m is not None else None,
            "geofence_note": (r.geofence_note if r else ""),
        }
    return state


def missing_for_leg(job, target_leg, state=None):
    req = required_before(job, target_leg)
    if not req:
        return []
    if state is None:
        state = checkpoint_state(job)
    return [(cp, r) for cp, r in req if not state[cp][r]]


def checkpoint_gate_error(job, target_leg, state=None):
    """(message, missing) -- message is "" when the leg may be set."""
    missing = missing_for_leg(job, target_leg, state=state)
    if not missing:
        return "", []
    labels = [REQUIREMENT_LABELS[m] for m in missing]
    return (
        f"Cannot advance to '{target_leg}' yet. Still required: " + "; ".join(labels) + ".",
        [{"checkpoint": cp, "requirement": r, "label": REQUIREMENT_LABELS[(cp, r)]} for cp, r in missing],
    )


def gate_summary(job, state=None):
    """Per-leg list of still-missing requirements, for the driver UI."""
    if state is None:
        state = checkpoint_state(job)
    seq, _ = gates_for_job(job)
    return {
        leg: [{"checkpoint": cp, "requirement": r, "label": REQUIREMENT_LABELS[(cp, r)]}
              for cp, r in missing_for_leg(job, leg, state=state)]
        for leg in seq
    }


def checkpoint_target(job, checkpoint):
    """(lat, lon) of the checkpoint: the trip's PICKUP/DROP stop when one
    has coordinates, else the booking's address / drop coordinates."""
    try:
        from service_requests.models import TripStop
        qs = TripStop.objects.filter(booking_id=job.id, stop_type=checkpoint,
                                     latitude__isnull=False, longitude__isnull=False)
        stop = (qs.order_by("sequence").first() if checkpoint == PICKUP
                else qs.order_by("-sequence").first())
        if stop is not None:
            return float(stop.latitude), float(stop.longitude)
    except Exception as exc:  # table may be absent in some environments
        logger.debug("TripStop lookup failed for job %s: %s", getattr(job, "id", None), exc)
    if checkpoint == PICKUP:
        lat, lon = getattr(job, "latitude", None), getattr(job, "longitude", None)
    else:
        lat, lon = getattr(job, "drop_latitude", None), getattr(job, "drop_longitude", None)
    if lat is None or lon is None:
        return None, None
    return float(lat), float(lon)


def _get_record(job, checkpoint, emp):
    from workforce_api.models import LogisticsCheckpointVerification
    rec, _ = LogisticsCheckpointVerification.objects.get_or_create(
        job_id=job.id, checkpoint=checkpoint, defaults={"employee": emp},
    )
    return rec


def _is_override(emp, user):
    return bool(
        getattr(emp, "allow_all_locations", False)
        or not getattr(getattr(emp, "company", None), "geofence_enabled", True)
        or getattr(user, "is_superuser", False)
        or getattr(user, "is_staff", False)
    )


def verify_checkpoint_gps(job, emp, user, checkpoint, lat, lon):
    """Returns (ok, data). Same 250m rule and override flags as job-start
    arrival (WorkforceJobArriveView)."""
    from time_tracking.geo import haversine_distance

    target_lat, target_lon = checkpoint_target(job, checkpoint)
    override = _is_override(emp, user)
    note = ""
    distance = None
    if target_lat is not None:
        distance = haversine_distance(float(lat), float(lon), target_lat, target_lon)
        if distance > CHECKPOINT_RADIUS_METERS and not override:
            return False, {
                "error": (f"{checkpoint.title()} check-in failed: you are {int(distance)}m away from the "
                          f"{checkpoint.lower()} location. You must be within {int(CHECKPOINT_RADIUS_METERS)}m."),
                "code": "OUTSIDE_GEOFENCE",
                "geofence_passed": False,
                "details": {"distance_m": round(distance, 1), "threshold_m": CHECKPOINT_RADIUS_METERS},
            }
        if distance > CHECKPOINT_RADIUS_METERS:
            note = "override"
    else:
        # The booking carries no coordinates for this point, so a geofence
        # cannot be evaluated. The GPS fix is still recorded and admins are
        # told explicitly (see notify message) rather than silently passing.
        note = "no_target_coordinates"

    rec = _get_record(job, checkpoint, emp)
    already = rec.geofence_passed
    now = timezone.now()
    if emp is not None:
        rec.employee_id = getattr(emp, "id", None)
    rec.geofence_passed = True
    rec.gps_lat, rec.gps_lon = float(lat), float(lon)
    rec.target_lat, rec.target_lon = target_lat, target_lon
    rec.distance_m = distance
    rec.geofence_note = note
    if not rec.gps_verified_at:
        rec.gps_verified_at = now
    rec.save()

    otp_issued = False
    if checkpoint == DROP and drop_otp_required(job) and not rec.otp_verified:
        otp_issued = issue_delivery_otp(job, rec, force=False)

    if not already:
        extra = ""
        if note == "no_target_coordinates":
            extra = " (booking has no coordinates for this point -- geofence not evaluated)"
        elif note == "override":
            extra = f" (geofence override, {int(distance)}m away)"
        notify_checkpoint_event(
            job, checkpoint, "gps_verified",
            title=f"{checkpoint.title()} location verified",
            message=f"Driver GPS verified at the {checkpoint.lower()} location for job #{job.id}{extra}.",
            extra={"distance_m": round(distance, 1) if distance is not None else None,
                   "geofence_note": note},
        )
    return True, {
        "geofence_passed": True,
        "checkpoint": checkpoint,
        "distance_m": round(distance, 1) if distance is not None else None,
        "geofence_note": note,
        "otp_issued": otp_issued,
    }


def record_checkpoint_photo(job, emp, checkpoint, photo_file):
    rec = _get_record(job, checkpoint, emp)
    if not rec.geofence_passed:
        return False, {"error": f"Verify GPS at the {checkpoint.lower()} location before uploading the proof photo.",
                       "code": "GPS_REQUIRED_FIRST"}
    rec.proof_photo = photo_file
    rec.photo_uploaded_at = timezone.now()
    if emp is not None:
        rec.employee_id = getattr(emp, "id", None)
    rec.save()
    what = "Loading" if checkpoint == PICKUP else "Unloading"
    # P&M/GT damage-evidence audit fix: the DROP-side photo already reaches
    # the customer app as a real DeliveryProof.PHOTO row (via the separate
    # job.completion_proof_submitted webhook WorkforceJobProofView fires),
    # giving customers an "after" proof of what arrived. The PICKUP-side
    # ("before") photo was captured here and stored on
    # LogisticsCheckpointVerification, but this event's webhook payload
    # never actually included the photo itself -- only a text notice -- so
    # it could never become a DeliveryProof row on the customer side, and a
    # damage dispute had no "before" evidence to compare against. Including
    # photo_url here lets the customer-side webhook handler record it the
    # same way completion_proof_submitted already does, using the exact
    # same DeliveryProof.ProofType.PHOTO the customer app already knows how
    # to display -- no new field or model, just carrying data that was
    # already being captured through to where it was always meant to land.
    photo_url = ""
    try:
        photo_url = rec.proof_photo.url if rec.proof_photo else ""
    except Exception:
        photo_url = ""
    notify_checkpoint_event(
        job, checkpoint, "photo_submitted",
        title=f"{what} proof photo submitted",
        message=f"Driver submitted the {what.lower()} proof photo at the {checkpoint.lower()} for job #{job.id}.",
        extra={"photo_url": photo_url} if photo_url else None,
    )
    return True, {"checkpoint": checkpoint, "photo": True}


def issue_delivery_otp(job, rec=None, force=True):
    """Generate a delivery OTP and send it to the customer. With force=False
    an existing unexpired code is kept. Returns True when a code was sent."""
    from workforce_api.models import LogisticsCheckpointVerification  # noqa: F401
    if rec is None:
        rec = _get_record(job, DROP, None)
    now = timezone.now()
    if not force and rec.otp_code and rec.otp_expires_at and rec.otp_expires_at >= now:
        return False
    code = f"{secrets.randbelow(900000) + 100000}"
    rec.otp_code = code
    rec.otp_generated_at = now
    rec.otp_expires_at = now + timedelta(minutes=DELIVERY_OTP_TTL_MINUTES)
    rec.otp_attempts = 0
    rec.otp_verified = False
    rec.otp_verified_at = None
    rec.save()
    customer = getattr(job, "customer", None)
    if customer is not None:
        try:
            from workforce_api.views import create_notification
            create_notification(
                recipient=customer,
                title="Goods Arrived — Delivery OTP",
                message=(f"Your goods for job #{job.id} have reached the drop location. "
                         f"Share delivery OTP {code} with the driver only after you receive them."),
                notification_type="DELIVERY_OTP",
                company=getattr(job, "company", None),
                related_object_id=str(job.id),
            )
        except Exception as exc:
            logger.warning("Could not notify customer of delivery OTP for job %s: %s", job.id, exc)
    try:
        from workforce_api.services.customer_webhook import notify_customer_app
        notify_customer_app("logistics.delivery_otp_issued", job, otp_code=code,
                            expires_at=rec.otp_expires_at.isoformat())
    except Exception as exc:
        logger.info("Could not emit logistics.delivery_otp_issued for job %s: %s", job.id, exc)
    return True


def verify_delivery_otp(job, emp, otp_input):
    """
    GT audit fix: this used to read `rec` unlocked, then read-check-write
    `otp_attempts` with no transaction around it. Two concurrent verify
    requests for the same job (an attacker script, or a doubled network
    retry) could each load the row at otp_attempts=4, each pass the <5
    gate, and each independently `save(update_fields=["otp_attempts"])` --
    a lost-update race where the stored counter converges to 5 regardless
    of how many real guesses were made in that window, letting more than
    MAX_OTP_ATTEMPTS real guesses through before the counter catches up.
    select_for_update() inside transaction.atomic() serializes concurrent
    verify attempts for the same checkpoint row, closing the race.
    """
    from workforce_api.models import LogisticsCheckpointVerification

    with transaction.atomic():
        rec = _get_record(job, DROP, emp)
        rec = LogisticsCheckpointVerification.objects.select_for_update().get(pk=rec.pk)

        if rec.otp_verified:
            return True, {"otp_verified": True, "message": "Delivery OTP already verified."}
        if not rec.geofence_passed:
            return False, {"error": "Verify GPS at the drop location first.", "code": "GPS_REQUIRED_FIRST"}
        if not rec.otp_code:
            return False, {"error": "No delivery OTP issued yet. Use 'Resend OTP'.", "code": "OTP_NOT_ISSUED"}
        if rec.otp_attempts >= MAX_OTP_ATTEMPTS:
            return False, {"error": "Maximum delivery OTP attempts exceeded (5/5). Use 'Resend OTP' for a fresh code.",
                           "code": "MAX_OTP_ATTEMPTS_EXCEEDED"}
        now = timezone.now()
        if rec.otp_expires_at and now > rec.otp_expires_at:
            return False, {"error": "Delivery OTP has expired. Use 'Resend OTP' for a fresh code.", "code": "OTP_EXPIRED"}
        if not secrets.compare_digest(str(rec.otp_code), str(otp_input or "").strip()):
            rec.otp_attempts += 1
            rec.save(update_fields=["otp_attempts", "updated_at"])
            remaining = max(0, MAX_OTP_ATTEMPTS - rec.otp_attempts)
            return False, {"error": f"Invalid delivery OTP. {remaining} attempt(s) remaining.",
                           "code": "INVALID_OTP", "attempts_remaining": remaining}
        rec.otp_verified = True
        rec.otp_verified_at = now
        rec.otp_attempts = 0
        rec.save()

    notify_checkpoint_event(
        job, DROP, "otp_verified",
        title="Delivery OTP verified",
        message=f"Customer delivery OTP verified at the drop location for job #{job.id}.",
    )
    return True, {"otp_verified": True, "message": "Delivery OTP verified."}


def notify_checkpoint_event(job, checkpoint, event, title, message, extra=None):
    """Customer + admin visibility for a checkpoint gate passing. Reuses the
    existing channels: WorkforceNotification via create_notification (the
    customer, as for the Work Start OTP), _notify_company_admins (deduped per
    job/checkpoint/event) and the durable customer-app webhook outbox."""
    try:
        from workforce_api.views import _notify_company_admins, create_notification
        customer = getattr(job, "customer", None)
        if customer is not None:
            create_notification(
                recipient=customer, title=title, message=message,
                notification_type="LOGISTICS_CHECKPOINT",
                company=getattr(job, "company", None),
                related_object_id=str(job.id),
            )
        _notify_company_admins(
            job, title, message, "LOGISTICS_CHECKPOINT_ADMIN",
            dedup_key=f"job:{job.id}:{checkpoint}:{event}",
        )
    except Exception as exc:
        logger.warning("Could not create checkpoint notifications for job %s: %s", job.id, exc)
    try:
        from workforce_api.services.customer_webhook import notify_customer_app
        notify_customer_app("logistics.checkpoint_verified", job,
                            checkpoint=checkpoint, verification=event, message=message,
                            **(extra or {}))
    except Exception as exc:
        logger.info("Could not emit logistics.checkpoint_verified for job %s: %s", job.id, exc)


def notify_leg_advanced(job, leg):
    """Customer + admin notification for a stage change (the webhook for
    the customer app is already emitted by set_logistics_leg)."""
    try:
        from workforce_api.views import _notify_company_admins, create_notification
        from service_requests.models import ServiceRequest
        try:
            label = ServiceRequest.LogisticsLeg(leg).label
        except Exception:
            label = leg
        msg = f"Job #{job.id} trip stage is now: {label}."
        customer = getattr(job, "customer", None)
        if customer is not None:
            create_notification(
                recipient=customer, title="Trip update", message=msg,
                notification_type="LOGISTICS_LEG",
                company=getattr(job, "company", None),
                related_object_id=str(job.id),
            )
        _notify_company_admins(job, "Trip stage advanced", msg, "LOGISTICS_LEG_ADMIN",
                               dedup_key=f"job:{job.id}:leg:{leg}")
    except Exception as exc:
        logger.warning("Could not create leg notifications for job %s: %s", job.id, exc)
