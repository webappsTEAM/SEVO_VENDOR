"""
WorkforceJobLiveTrackingView exposes pickup/drop points (additive fields
is_logistics / pickup_location / drop_location) so the technician and the
customer can render pickup, drop and live vehicle position together.
Pickup/drop are populated ONLY for LOGISTICS_SERVICE_CATEGORIES jobs.

ServiceRequest is an unmanaged mirror with no test table, so its manager is
patched; the view is called as an internal (webhook-secret) caller.
"""
from decimal import Decimal
from types import SimpleNamespace
from unittest.mock import MagicMock, patch

from django.test import SimpleTestCase, override_settings
from rest_framework.test import APIRequestFactory

from service_requests.models import ServiceRequest
from workforce_api import models as wf_models
from workforce_api.views import WorkforceJobLiveTrackingView


def _job(category, status="completed", with_tech=False):
    tech = None
    if with_tech:
        tech = SimpleNamespace(
            id=7, user=SimpleNamespace(get_full_name=lambda: "Ravi", username="ravi", last_known_location=None),
            phone="999", title="Driver", profile_photo=None, rating=None,
        )
    return SimpleNamespace(
        id=11, request_id="SR-11", status=status, service_category=category,
        latitude=Decimal("12.900000"), longitude=Decimal("77.600000"), address="Pickup St",
        drop_latitude=Decimal("12.950000"), drop_longitude=Decimal("77.650000"), drop_address="Drop Rd",
        assigned_employee=tech, customer=None, customer_name="", phone="", company_id=None,
        pre_service_verification=None,
    )


@override_settings(WORKFORCE_WEBHOOK_SECRET="s3cret")
class LiveTrackingRoutePointsTests(SimpleTestCase):
    def _get(self, job):
        qs = MagicMock()
        qs.select_related.return_value.first.return_value = job
        req = APIRequestFactory().get("/api/workforce/jobs/11/live-tracking/", HTTP_AUTHORIZATION="Bearer s3cret")
        empty = MagicMock()
        empty.filter.return_value.first.return_value = None
        with patch.object(ServiceRequest.objects, "filter", return_value=qs), \
             patch.object(wf_models.JobTrackingSession, "objects", empty), \
             patch.object(wf_models.PreServiceVerification, "objects", empty):
            return WorkforceJobLiveTrackingView.as_view()(req, pk=11)

    def test_logistics_job_exposes_pickup_and_drop(self):
        res = self._get(_job("goods_transport_truck", status="in_progress", with_tech=True))
        self.assertEqual(res.status_code, 200)
        self.assertTrue(res.data["is_logistics"])
        self.assertEqual(res.data["pickup_location"], {"latitude": 12.9, "longitude": 77.6, "address": "Pickup St"})
        self.assertEqual(res.data["drop_location"], {"latitude": 12.95, "longitude": 77.65, "address": "Drop Rd"})
        # existing contract untouched
        self.assertEqual(res.data["customer_location"]["latitude"], 12.9)
        self.assertIn("assigned_technician", res.data)

    def test_packers_movers_is_logistics(self):
        res = self._get(_job("packers_movers"))
        self.assertTrue(res.data["is_logistics"])
        self.assertEqual(res.data["drop_location"]["address"], "Drop Rd")

    def test_non_logistics_job_has_no_pickup_drop(self):
        res = self._get(_job("ac_repair", status="in_progress", with_tech=True))
        self.assertEqual(res.status_code, 200)
        self.assertFalse(res.data["is_logistics"])
        self.assertIsNone(res.data["pickup_location"])
        self.assertIsNone(res.data["drop_location"])

    def test_missing_drop_coordinates_are_null(self):
        job = _job("goods_transport_two_wheeler")
        job.drop_latitude = None
        job.drop_longitude = None
        res = self._get(job)
        self.assertIsNone(res.data["drop_location"]["latitude"])
        self.assertEqual(res.data["drop_location"]["address"], "Drop Rd")
