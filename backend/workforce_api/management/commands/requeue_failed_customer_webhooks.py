"""Operator tool: put FAILED (retries exhausted) customer webhooks back in the delivery queue.
Safe to re-run: the customer app deduplicates on event_id and validates sequence.
  python manage.py requeue_failed_customer_webhooks --dry-run
  python manage.py requeue_failed_customer_webhooks --hours 168 [--booking SR-123]
"""
from datetime import timedelta

from django.core.management.base import BaseCommand
from django.utils import timezone

from workforce_api.models import WorkforceOutboundWebhook


class Command(BaseCommand):
    help = "Re-queue FAILED customer webhooks (retries exhausted) so the dispatch sweep delivers them again."

    def add_arguments(self, parser):
        parser.add_argument("--hours", type=int, default=168, help="only records created within this many hours (default 168)")
        parser.add_argument("--booking", default="", help="restrict to one booking id")
        parser.add_argument("--dry-run", action="store_true")

    def handle(self, *args, **opts):
        qs = WorkforceOutboundWebhook.objects.filter(
            status=WorkforceOutboundWebhook.Status.FAILED,
            created_at__gte=timezone.now() - timedelta(hours=opts["hours"]),
        )
        if opts["booking"]:
            qs = qs.filter(booking_id=opts["booking"])
        n = qs.count()
        if opts["dry_run"]:
            self.stdout.write(f"[dry-run] {n} failed webhook(s) would be re-queued")
            return
        ids = list(qs.values_list("id", flat=True))
        WorkforceOutboundWebhook.objects.filter(id__in=ids).update(
            status=WorkforceOutboundWebhook.Status.PENDING, attempts=0, next_retry_at=timezone.now(), last_error="")
        self.stdout.write(f"re-queued {len(ids)} webhook(s)")
