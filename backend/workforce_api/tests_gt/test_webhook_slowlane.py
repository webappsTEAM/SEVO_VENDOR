"""GT_WEBHOOK_SLOWLANE: an outbound customer webhook whose fast retries are exhausted is not stranded."""
import uuid
from datetime import timedelta
from io import StringIO
from unittest.mock import MagicMock, patch

from django.core.management import call_command
from django.test import TestCase
from django.utils import timezone

from workforce_api.models import WorkforceOutboundWebhook as W
from workforce_api.services import customer_webhook as cw


def _rec(attempts=10, last_h=2, created_h=3, status=W.Status.FAILED):
    now = timezone.now()
    r = W.objects.create(event_id=f"evt_{uuid.uuid4().hex}", event_type="employee_accepted", booking_id="GT-1", payload={},
                         status=status, attempts=attempts, last_attempt_at=now - timedelta(hours=last_h), last_error="HTTP 502")
    W.objects.filter(pk=r.pk).update(created_at=now - timedelta(hours=created_h))
    return r


OK = MagicMock(status_code=200, text="ok")


class SlowLaneTests(TestCase):
    @patch("workforce_api.services.customer_webhook.requests.post", return_value=OK)
    def test_exhausted_record_is_retried_and_delivered(self, post):
        r = _rec()
        res = cw.process_exhausted_outbound_webhooks()
        r.refresh_from_db()
        self.assertEqual(r.status, W.Status.DELIVERED); self.assertEqual(res["delivered"], 1); post.assert_called_once()

    @patch("workforce_api.services.customer_webhook.requests.post", return_value=OK)
    def test_not_retried_too_soon_too_old_or_too_many(self, post):
        _rec(last_h=0); _rec(created_h=100, last_h=50); _rec(attempts=10 + cw.SLOW_LANE_MAX_ATTEMPTS)
        res = cw.process_exhausted_outbound_webhooks()
        self.assertEqual(res["exhausted_found"], 0); post.assert_not_called()

    @patch("workforce_api.services.customer_webhook.requests.post", side_effect=Exception("down"))
    def test_failure_keeps_it_failed_and_bounded(self, post):
        r = _rec()
        cw.process_exhausted_outbound_webhooks()
        r.refresh_from_db()
        self.assertEqual(r.status, W.Status.FAILED); self.assertEqual(r.attempts, 11); self.assertIsNone(r.next_retry_at)

    def test_operator_command_requeues_failed(self):
        r = _rec(created_h=200)
        out = StringIO(); call_command("requeue_failed_customer_webhooks", "--dry-run", "--hours", "300", stdout=out)
        self.assertIn("1 failed", out.getvalue()); r.refresh_from_db(); self.assertEqual(r.status, W.Status.FAILED)
        call_command("requeue_failed_customer_webhooks", "--hours", "300", stdout=StringIO())
        r.refresh_from_db(); self.assertEqual((r.status, r.attempts), (W.Status.PENDING, 0)); self.assertIsNotNone(r.next_retry_at)
