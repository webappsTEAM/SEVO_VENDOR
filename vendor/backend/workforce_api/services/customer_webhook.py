"""
workforce_api/services/customer_webhook.py

Durable Outbox Delivery Service for Customer App Webhooks:
Guarantees at-least-once delivery for critical lifecycle state changes:
- employee_accepted
- employee_on_the_way
- employee_arrived
- service_started
- service_completed
- technician.cancelled
- technician.searching
- payment.collected
- technician.location_updated

Matches Customer app's expected payload shape:
  `event`, `event_id`, `sequence`, `payload.booking_id`, `payload.workforce_job_id`, `payload.company_id`
"""
import logging
import threading
import time
import uuid
from datetime import timedelta

import requests
from django.conf import settings
from django.utils import timezone

logger = logging.getLogger("workforce_api.customer_webhook")

_WEBHOOK_TIMEOUT_SECONDS = 4
MAX_WEBHOOK_ATTEMPTS = 10
WEBHOOK_RETRY_BACKOFF_SECONDS = [5, 15, 60, 180, 300, 600, 900, 1800]


def _compute_next_retry_at(attempt: int):
    idx = min(max(0, attempt - 1), len(WEBHOOK_RETRY_BACKOFF_SECONDS) - 1)
    delay_s = WEBHOOK_RETRY_BACKOFF_SECONDS[idx]
    return timezone.now() + timedelta(seconds=delay_s)


def send_outbound_webhook_record(webhook_record) -> bool:
    """
    Attempts HTTP delivery of a specific WorkforceOutboundWebhook record.
    Updates the record's status, attempts, last_attempt_at, next_retry_at, and last_error.
    Returns True if delivery succeeded, False otherwise.
    """
    from workforce_api.models import WorkforceOutboundWebhook

    if getattr(webhook_record, "status", None) == WorkforceOutboundWebhook.Status.DELIVERED:
        return True

    # Stable event_id check
    ev_id = getattr(webhook_record, "event_id", None)
    if not ev_id:
        ev_id = f"evt_{uuid.uuid4().hex}"
        webhook_record.event_id = ev_id
        webhook_record.save(update_fields=["event_id"])

    url = f"{settings.CUSTOMER_APP_BASE_URL}/api/workforce-integration/webhook/"
    body = {
        "event": getattr(webhook_record, "event_type", ""),
        "event_id": str(ev_id),
        "sequence": getattr(webhook_record, "sequence", 1),
        "payload": {"booking_id": getattr(webhook_record, "booking_id", ""), **(getattr(webhook_record, "payload", {}) or {})},
    }

    now = timezone.now()
    webhook_record.last_attempt_at = now
    webhook_record.attempts += 1

    try:
        response = requests.post(
            url,
            json=body,
            headers={
                "Content-Type": "application/json",
                "X-Workforce-Webhook-Secret": settings.WORKFORCE_WEBHOOK_SECRET,
            },
            timeout=_WEBHOOK_TIMEOUT_SECONDS,
        )

        if 200 <= response.status_code < 300:
            webhook_record.status = WorkforceOutboundWebhook.Status.DELIVERED
            webhook_record.next_retry_at = None
            webhook_record.last_error = ""
            webhook_record.save(update_fields=["status", "attempts", "last_attempt_at", "next_retry_at", "last_error", "updated_at"])
            logger.info(
                f"[CUSTOMER_WEBHOOK_DELIVERED] Event '{webhook_record.event_type}' for booking {webhook_record.booking_id} (attempt {webhook_record.attempts})."
            )
            return True
        else:
            err_msg = f"HTTP {response.status_code}: {response.text[:300]}"
            logger.warning(
                f"[CUSTOMER_WEBHOOK_REJECTED] Event '{webhook_record.event_type}' for booking {webhook_record.booking_id}: {err_msg}"
            )
            webhook_record.last_error = err_msg
            if webhook_record.attempts < MAX_WEBHOOK_ATTEMPTS:
                webhook_record.status = WorkforceOutboundWebhook.Status.FAILED
                webhook_record.next_retry_at = _compute_next_retry_at(webhook_record.attempts)
            else:
                webhook_record.status = WorkforceOutboundWebhook.Status.FAILED
                webhook_record.next_retry_at = None
            webhook_record.save(update_fields=["status", "attempts", "last_attempt_at", "next_retry_at", "last_error", "updated_at"])
            return False

    except Exception as exc:
        err_msg = str(exc)[:500]
        logger.warning(
            f"[CUSTOMER_WEBHOOK_ERR] Event '{webhook_record.event_type}' for booking {webhook_record.booking_id} failed: {err_msg}"
        )
        webhook_record.last_error = err_msg
        if webhook_record.attempts < MAX_WEBHOOK_ATTEMPTS:
            webhook_record.status = WorkforceOutboundWebhook.Status.FAILED
            webhook_record.next_retry_at = _compute_next_retry_at(webhook_record.attempts)
        else:
            webhook_record.status = WorkforceOutboundWebhook.Status.FAILED
            webhook_record.next_retry_at = None
        webhook_record.save(update_fields=["status", "attempts", "last_attempt_at", "next_retry_at", "last_error", "updated_at"])
        return False


def _post_webhook_async(webhook_id: int):
    """Worker thread target to attempt immediate delivery."""
    try:
        from workforce_api.models import WorkforceOutboundWebhook
        from django.db import connection
        try:
            record = WorkforceOutboundWebhook.objects.filter(pk=webhook_id).first()
            if record and record.status != WorkforceOutboundWebhook.Status.DELIVERED:
                send_outbound_webhook_record(record)
        finally:
            connection.close()
    except Exception as exc:
        logger.debug(f"[CUSTOMER_WEBHOOK_THREAD_ERR] {exc}")


def notify_customer_app(event_type: str, service_request, **extra_payload) -> str:
    """
    Durable entrypoint to notify Customer app of a lifecycle event.
    1. Persists event in WorkforceOutboundWebhook outbox table.
    2. Dispatches immediate delivery in background.
    3. If delivery fails or times out, the background reconciliation worker retries it with backoff.
    """
    try:
        from workforce_api.models import WorkforceOutboundWebhook

        booking_id = getattr(service_request, "request_id", None) or str(getattr(service_request, "id", ""))
        if not booking_id:
            return ""

        sequence = int(time.time() * 1000) % 2_147_483_647
        event_id = f"evt_{uuid.uuid4().hex}"

        payload = dict(extra_payload)
        payload.setdefault("workforce_job_id", str(getattr(service_request, "id", "")))
        payload.setdefault("company_id", str(getattr(service_request, "company_id", "") or ""))

        webhook_record = WorkforceOutboundWebhook.objects.create(
            event_id=event_id,
            event_type=event_type,
            booking_id=booking_id,
            payload=payload,
            sequence=sequence,
            status=WorkforceOutboundWebhook.Status.PENDING,
            next_retry_at=timezone.now(),
        )

        from django.db import transaction

        def _deliver():
            thread = threading.Thread(
                target=_post_webhook_async,
                args=(webhook_record.id,),
                daemon=True,
            )
            thread.start()

        transaction.on_commit(_deliver)
        return event_id

    except Exception as exc:
        logger.warning(f"[NOTIFY_CUSTOMER_FAIL] Could not enqueue durable webhook for '{event_type}': {exc}")
        return ""


def process_pending_outbound_webhooks(limit: int = 25) -> dict:
    """
    Reconciliation worker task: sweeps pending and failed outbound webhooks due for retry.
    Called in the dispatch worker loop.
    """
    from workforce_api.models import WorkforceOutboundWebhook
    now = timezone.now()

    pending_qs = WorkforceOutboundWebhook.objects.filter(
        status__in=[WorkforceOutboundWebhook.Status.PENDING, WorkforceOutboundWebhook.Status.FAILED],
        next_retry_at__lte=now,
        attempts__lt=MAX_WEBHOOK_ATTEMPTS,
    ).order_by("next_retry_at", "id")[:limit]

    records = list(pending_qs)
    delivered_count = 0
    failed_count = 0

    for rec in records:
        if send_outbound_webhook_record(rec):
            delivered_count += 1
        else:
            failed_count += 1

    return {
        "pending_found": len(records),
        "delivered": delivered_count,
        "failed_or_scheduled_retry": failed_count,
    }
