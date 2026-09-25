"""
Django Management Command: dispatch_pending_workforce_jobs

Authoritative Cross-Application Background Dispatch Worker:
1. Sweeps and falls back on expired job offers.
2. Discovers pending dispatchable customer jobs directly from the PostgreSQL database.
3. Evaluates technician live GPS proximity, readiness, and 10 eligibility gates.
4. Creates exclusive job offers for nearest qualified technicians.
5. Emits realtime SSE events (OFFER_CREATED) for technician UI updates.

Usage:
  Single pass:
    python manage.py dispatch_pending_workforce_jobs --once

  Continuous background reconciliation loop (5s interval):
    python manage.py dispatch_pending_workforce_jobs --loop --interval 5
"""
import logging
import signal
import sys
import time
from django.core.management.base import BaseCommand
from django.utils import timezone
from workforce_api.services.automatic_dispatch import dispatch_pending_jobs, expire_and_reassign_offers
from workforce_api.services.customer_webhook import process_pending_outbound_webhooks

logger = logging.getLogger("workforce.dispatch.worker")


def _write_heartbeat(status: str, detail: dict = None) -> None:
    """
    Records worker health in a single WorkforceEventLog row (event_type='dispatch_engine_heartbeat').
    This is lightweight and idempotent, providing health-check observability without database bloating.
    """
    try:
        from workforce_api.models import WorkforceEventLog
        row, _ = WorkforceEventLog.objects.get_or_create(
            event_type="dispatch_engine_heartbeat",
            user=None,
            defaults={"payload": {}},
        )
        row.payload = {
            "last_heartbeat": timezone.now().isoformat(),
            "status": status,
            "detail": detail or {},
        }
        row.save(update_fields=["payload"])
    except Exception as e:
        # Heartbeat is best-effort observability, never let it break dispatch.
        logger.debug(f"[DISPATCH_HEARTBEAT_ERR] {e}")


class Command(BaseCommand):
    help = "Reconciles pending cross-application customer service requests and executes authoritative automatic dispatch."

    def add_arguments(self, parser):
        parser.add_argument(
            "--once",
            action="store_true",
            help="Run reconciliation once and exit immediately.",
        )
        parser.add_argument(
            "--loop",
            action="store_true",
            help="Run continuous reconciliation loop in the background.",
        )
        parser.add_argument(
            "--interval",
            type=int,
            default=5,
            help="Interval in seconds between reconciliation cycles (default: 5s).",
        )
        parser.add_argument(
            "--limit",
            type=int,
            default=50,
            help="Maximum pending jobs to evaluate per reconciliation cycle (default: 50).",
        )

    def handle(self, *args, **options):
        run_once = options.get("once")
        run_loop = options.get("loop")
        interval = max(1, options.get("interval") or 5)
        limit = max(1, options.get("limit") or 50)

        self.stdout.write(self.style.SUCCESS(
            f"[DISPATCH ENGINE] Initializing Authoritative Dispatch Worker (interval: {interval}s, limit: {limit})..."
        ))

        if run_once or not run_loop:
            # Single pass reconciliation
            webhook_res = process_pending_outbound_webhooks(limit=25)
            result = dispatch_pending_jobs(limit=limit)
            _write_heartbeat("ok", {
                "mode": "single_pass",
                "pending_jobs_found": result.get("pending_jobs_found", 0),
                "dispatched_count": result.get("dispatched_count", 0),
                "expired_offers_swept": result.get("expired_offers_swept", 0),
                "webhooks_delivered": webhook_res.get("delivered", 0),
            })
            self.stdout.write(
                self.style.SUCCESS(
                    f"[DISPATCH ENGINE] Completed single pass: {result['pending_jobs_found']} pending found, "
                    f"{result['dispatched_count']} offered, {result['unassigned_count']} unassigned, "
                    f"{result['expired_offers_swept']} expired offers swept, "
                    f"{webhook_res.get('delivered', 0)} webhooks delivered."
                )
            )
            for detail in result.get("details", []):
                self.stdout.write(f"  - Job #{detail['job_id']}: {detail['message']}")
            return

        # Continuous reconciliation loop
        shutdown_requested = False

        def handle_shutdown(sig, frame):
            nonlocal shutdown_requested
            shutdown_requested = True
            self.stdout.write(self.style.WARNING(f"\n[DISPATCH ENGINE] Signal {sig} received. Initiating graceful shutdown..."))

        try:
            signal.signal(signal.SIGINT, handle_shutdown)
            if hasattr(signal, "SIGTERM"):
                signal.signal(signal.SIGTERM, handle_shutdown)
        except Exception:
            pass

        self.stdout.write(self.style.SUCCESS(
            f"[DISPATCH ENGINE] Running in continuous daemon mode. Supervisor active (PID: {sys.argv}). Press Ctrl+C to stop."
        ))

        cycle = 0
        last_heartbeat_time = 0.0
        heartbeat_interval = 30.0  # Throttle idle heartbeats to every 30s
        last_status = "ok"

        # Initial heartbeat
        _write_heartbeat("ok", {"status": "started", "interval": interval})
        last_heartbeat_time = time.time()

        while not shutdown_requested:
            cycle += 1
            cycle_start = time.time()
            try:
                # 1. Sweep pending/retrying customer webhook notifications
                webhook_res = process_pending_outbound_webhooks(limit=25)
                # 2. Dispatch pending jobs and sweep expired offers
                result = dispatch_pending_jobs(limit=limit)
                pending_found = result.get("pending_jobs_found", 0)
                dispatched_count = result.get("dispatched_count", 0)
                expired_swept = result.get("expired_offers_swept", 0)
                unassigned_count = result.get("unassigned_count", 0)
                webhooks_delivered = webhook_res.get("delivered", 0)

                now_ts = time.time()
                activity = (pending_found > 0 or expired_swept > 0 or webhooks_delivered > 0)

                if activity:
                    self.stdout.write(
                        f"[DISPATCH cycle={cycle}] Swept {expired_swept} expired, "
                        f"Evaluated {pending_found} pending -> {dispatched_count} offered, {unassigned_count} unassigned, "
                        f"{webhooks_delivered} webhooks delivered."
                    )
                    for detail in result.get("details", []):
                        self.stdout.write(f"  * Job #{detail.get('job_id')}: {detail.get('message')}")

                # Update heartbeat if activity occurred, or if status changed, or every 30s
                if activity or last_status != "ok" or (now_ts - last_heartbeat_time >= heartbeat_interval):
                    _write_heartbeat("ok", {
                        "cycle": cycle,
                        "pending_jobs_found": pending_found,
                        "dispatched_count": dispatched_count,
                        "expired_offers_swept": expired_swept,
                        "webhooks_delivered": webhooks_delivered,
                    })
                    last_heartbeat_time = now_ts
                    last_status = "ok"

            except Exception as exc:
                self.stderr.write(self.style.ERROR(f"[DISPATCH ERROR cycle={cycle}] {type(exc).__name__}: {exc}"))
                logger.error(f"[DISPATCH_CYCLE_ERROR] cycle={cycle}: {exc}", exc_info=True)
                _write_heartbeat("error", {"cycle": cycle, "error": str(exc), "error_type": type(exc).__name__})
                last_status = "error"
                last_heartbeat_time = time.time()

            # Bounded sleep respecting shutdown signal
            elapsed = time.time() - cycle_start
            sleep_remaining = max(0.1, interval - elapsed)
            sleep_chunks = int(sleep_remaining / 0.5)
            for _ in range(sleep_chunks):
                if shutdown_requested:
                    break
                time.sleep(0.5)
            if not shutdown_requested and (sleep_remaining % 0.5) > 0:
                time.sleep(sleep_remaining % 0.5)

        self.stdout.write(self.style.SUCCESS("[DISPATCH ENGINE] Dispatch worker shut down cleanly."))
        _write_heartbeat("stopped", {"status": "clean_shutdown", "final_cycle": cycle})
        sys.exit(0)
