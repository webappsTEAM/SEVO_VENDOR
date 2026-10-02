"""Regression (E2E QA 2026-10-01): the driver live-update stream took the full access JWT (valid hours) in the
URL query string, where proxies and access logs record it. A 60 s single-use ticket must authorise the stream
instead, must not be usable as an API credential, and must not be replayable."""
from unittest.mock import patch

from django.core.cache import cache
from django.test import Client, override_settings
from rest_framework.test import APIClient
from rest_framework_simplejwt.tokens import AccessToken

from workforce_api.services.stream_ticket import issue_stream_ticket, redeem_stream_ticket
from .test_realdb_gt_lifecycle import RealDbBase, Trip

URL = "/api/workforce/realtime/stream/"


def _open(client, **params):
    with patch("workforce_api.views.time.sleep", side_effect=RuntimeError("stop")):
        resp = client.get(URL, params)
        if resp.status_code == 200:
            resp.close()
        return resp


class RealtimeStreamTicketTests(RealDbBase):
    def setUp(self):
        super().setUp()
        cache.clear()
        self.t = Trip(fare={"vehicle_class": "truck"}, tag="32")
        self.jwt = str(AccessToken.for_user(self.t.tech_user))

    def _ticket(self):
        api = APIClient(); api.credentials(HTTP_AUTHORIZATION="Bearer " + self.jwt)
        r = api.post("/api/workforce/realtime/stream-ticket/")
        self.assertEqual(r.status_code, 200, r.content)
        return r.json()["ticket"]

    def test_ticket_requires_authentication(self):
        self.assertIn(APIClient().post("/api/workforce/realtime/stream-ticket/").status_code, (401, 403))

    def test_ticket_opens_the_stream_once(self):
        ticket = self._ticket()
        self.assertEqual(_open(Client(), ticket=ticket).status_code, 200)
        self.assertEqual(_open(Client(), ticket=ticket).status_code, 401)  # replay refused

    def test_garbage_and_expired_tickets_refused(self):
        self.assertEqual(_open(Client(), ticket="not-a-ticket").status_code, 401)
        self.assertIsNone(redeem_stream_ticket(issue_stream_ticket(self.t.tech_user.id), ttl=-1))

    def test_ticket_is_not_an_api_credential_and_jwt_is_not_a_ticket(self):
        ticket = self._ticket()
        api = APIClient(); api.credentials(HTTP_AUTHORIZATION="Bearer " + ticket)
        self.assertEqual(api.get("/api/workforce/jobs/").status_code, 401)
        self.assertEqual(_open(Client(), ticket=self.jwt).status_code, 401)

    def test_query_string_jwt_can_be_switched_off(self):
        self.assertEqual(_open(Client(), token=self.jwt).status_code, 200)  # legacy still works by default
        with override_settings(REALTIME_ALLOW_QUERY_TOKEN=False):
            self.assertEqual(_open(Client(), token=self.jwt).status_code, 401)
            api_header = Client(HTTP_AUTHORIZATION="Bearer " + self.jwt)
            self.assertEqual(_open(api_header).status_code, 200)
