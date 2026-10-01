"""Regression (E2E QA 2026-10-01), SSE /api/workforce/realtime/stream/:
1. Without Redis the stream never queried the event log, so a driver received NO offer events
   (GT offers live ~20-40s; the client poll is 30s). It must fall back to polling the log.
2. Company-scoped dispatch diagnostics (ranked candidate names/scores) were delivered to every
   driver; they are admin-radar only."""
import json
import time
from unittest.mock import patch

from django.test import Client
from rest_framework_simplejwt.tokens import AccessToken

from .test_realdb_gt_lifecycle import RealDbBase, Trip


def _read_events(response, want, timeout=8, after_first_chunk=None):
    """Collect SSE `workforce_event` payloads until `want(types)` is true or timeout."""
    got, buf, t0 = [], "", time.time()
    for i, chunk in enumerate(response.streaming_content):
        if i == 0 and after_first_chunk:
            after_first_chunk()
        buf += chunk.decode() if isinstance(chunk, bytes) else chunk
        while "\n\n" in buf:
            frame, buf = buf.split("\n\n", 1)
            if "event: workforce_event" in frame:
                data = [l[6:] for l in frame.splitlines() if l.startswith("data: ")]
                got.append(json.loads(data[0]))
        if want([e["event_type"] for e in got]) or time.time() - t0 > timeout:
            break
    response.close()
    return got


class RealtimeStreamTests(RealDbBase):
    def setUp(self):
        super().setUp()
        self.t = Trip(fare={"vehicle_class": "truck"}, tag="31")
        self.token = str(AccessToken.for_user(self.t.tech_user))

    def _log(self, event_type, user=None, payload=None):
        from workforce_api.models import WorkforceEventLog
        return WorkforceEventLog.objects.create(user=user, event_type=event_type, payload=payload or {})

    def test_driver_gets_own_offer_without_redis_and_not_dispatch_diagnostics(self):
        # last_event_id = newest existing row, so only events written AFTER the stream opens count:
        # delivery of those is what needs the (no-Redis) event-log polling fallback.
        last = self._log("DISPATCH_STARTED", None, {"job_id": 1}).id
        resp = Client().get("/api/workforce/realtime/stream/", {"token": self.token, "last_event_id": last})
        self.assertEqual(resp.status_code, 200)
        calls = {"n": 0}

        def fake_sleep(_seconds):
            # First idle second of the stream: the offer + a diagnostics row are written. Stop the
            # (otherwise endless) stream after a few idle seconds so a broken fallback fails fast.
            calls["n"] += 1
            if calls["n"] == 1:
                self._log("CANDIDATES_EVALUATED", None, {"eligible_candidates_snapshot": [{"employee_name": "other driver"}]})
                self._log("OFFER_CREATED", self.t.tech_user, {"job_id": self.t.sr.id})
            elif calls["n"] > 4:
                raise RuntimeError("stop idle stream")

        with patch("workforce_api.views.time.sleep", fake_sleep):
            events = _read_events(resp, lambda types: "OFFER_CREATED" in types)
        types = [e["event_type"] for e in events]
        self.assertIn("OFFER_CREATED", types)
        self.assertNotIn("CANDIDATES_EVALUATED", types)
        self.assertNotIn("DISPATCH_STARTED", types)
        self.assertNotIn("other driver", json.dumps(events))
