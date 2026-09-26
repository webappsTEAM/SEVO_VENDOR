"""
Server-to-server auth (IsInternalWorkforceCaller) must fail closed and never
crash on hostile input.
"""
import os
from unittest.mock import patch

from django.test import SimpleTestCase, override_settings
from django.test.client import RequestFactory

from workforce_api.permissions import IsInternalWorkforceCaller


class InternalCallerFailClosedTests(SimpleTestCase):
    def setUp(self):
        self.rf = RequestFactory()
        self.perm = IsInternalWorkforceCaller()

    def _req(self, token):
        return self.rf.get("/api/workforce/jobs/1/live-tracking/", HTTP_AUTHORIZATION=f"Bearer {token}")

    def test_well_known_default_key_is_refused_when_no_key_is_configured(self):
        env = {k: v for k, v in os.environ.items() if k != "WORKFORCE_API_KEY"}
        with patch.dict(os.environ, env, clear=True), \
                override_settings(WORKFORCE_WEBHOOK_SECRET="real-secret", WORKFORCE_API_KEY="", DEBUG=False):
            self.assertFalse(self.perm.has_permission(self._req("wf_integration_key_default"), None))
            self.assertTrue(self.perm.has_permission(self._req("real-secret"), None))

    def test_configured_api_key_still_works(self):
        with override_settings(WORKFORCE_WEBHOOK_SECRET="s", WORKFORCE_API_KEY="prod-key-123", DEBUG=False):
            self.assertTrue(self.perm.has_permission(self._req("prod-key-123"), None))

    def test_non_ascii_credentials_are_denied_not_a_server_error(self):
        with override_settings(WORKFORCE_WEBHOOK_SECRET="s", WORKFORCE_API_KEY="k", DEBUG=False):
            self.assertFalse(self.perm.has_permission(self._req("sécret"), None))
