"""
Unit tests for Packers & Movers relocation manifest extraction,
serializer fields, live tracking response, and trip progress cancellation locks.
"""
from decimal import Decimal
from types import SimpleNamespace
from unittest.mock import MagicMock, patch

from django.test import SimpleTestCase, TestCase, override_settings
from rest_framework.test import APIRequestFactory, force_authenticate

from service_requests.models import ServiceRequest
from workforce_api import models as wf_models
from workforce_api.serializers import WorkforceJobSerializer
from workforce_api.services.logistics_events import extract_pm_job_details
from workforce_api.views import (
    WorkforceJobLiveTrackingView,
    WorkforceJobTechnicianCancelView,
)


class PackersMoversManifestExtractionTests(SimpleTestCase):
    def test_extract_pm_job_details_from_fare_breakdown(self):
        job = SimpleNamespace(
            service_category="packers_movers",
            service_title="House Relocation",
            fare_breakdown={
                "total_cft": 350,
                "vehicle": {
                    "code": "TATA_ACE",
                    "name": "Tata Ace",
                    "crew_size": 3,
                },
                "inventory_summary": {
                    "total_items": 4,
                    "total_cft": 350,
                    "items": [
                        {"name": "Queen Bed", "quantity": 1, "is_fragile": False},
                        {"name": "Glass Coffee Table", "quantity": 1, "is_fragile": True},
                        {"name": "Carton Boxes", "quantity": 2, "is_fragile": False},
                    ],
                },
                "access": {
                    "pickup_floor": 2,
                    "pickup_has_lift": False,
                    "drop_floor": 1,
                    "drop_has_lift": True,
                },
                "pricing": {
                    "packing_label": "Premium",
                    "dismantling_required": True,
                    "unpacking_required": True,
                },
            },
            cart_data=[],
        )

        crew_size, items, relocation = extract_pm_job_details(job)
        self.assertEqual(crew_size, 3)
        self.assertEqual(len(items), 3)
        self.assertEqual(items[0]["name"], "Queen Bed")
        self.assertEqual(items[0]["quantity"], 1)
        self.assertEqual(items[1]["is_fragile"], True)
        self.assertEqual(relocation["pickup_floor"], 2)
        self.assertEqual(relocation["pickup_has_lift"], False)
        self.assertEqual(relocation["drop_floor"], 1)
        self.assertEqual(relocation["drop_has_lift"], True)
        self.assertEqual(relocation["packing_tier"], "Premium")
        self.assertTrue(relocation["dismantling_required"])
        self.assertTrue(relocation["unpacking_required"])
        self.assertEqual(relocation["vehicle_name"], "Tata Ace")
        self.assertEqual(relocation["volume_cft"], 350)

    def test_extract_pm_job_details_from_cart_data_fallback(self):
        job = SimpleNamespace(
            service_category="packers_movers",
            service_title="",
            issue_title="Packers & Movers - Relocation",
            fare_breakdown={},
            cart_data=[{
                "helpers_requested": 4,
                "package": "14ft Truck",
                "relocation_type": "Intercity",
                "pickup_floor": 3,
                "pickup_has_lift": True,
                "drop_floor": 0,
                "drop_has_lift": True,
                "packing_tier": "standard",
                "dismantling_required": False,
                "unpacking_required": False,
                "inventory": [
                    {"goods_item_id": 101, "name": "Dining Table", "quantity": 1},
                    {"goods_item_id": 102, "name": "Chairs", "quantity": 6},
                ],
            }],
        )

        crew_size, items, relocation = extract_pm_job_details(job)
        self.assertEqual(crew_size, 4)
        self.assertEqual(len(items), 2)
        self.assertEqual(items[0]["name"], "Dining Table")
        self.assertEqual(items[1]["quantity"], 6)
        self.assertEqual(relocation["pickup_floor"], 3)
        self.assertEqual(relocation["pickup_has_lift"], True)
        self.assertEqual(relocation["drop_floor"], 0)
        self.assertEqual(relocation["packing_tier"], "Standard")
        self.assertFalse(relocation["dismantling_required"])
        self.assertEqual(relocation["relocation_type"], "Intercity")
        self.assertEqual(relocation["vehicle_name"], "14ft Truck")

    def test_extract_pm_job_details_non_pm_returns_none(self):
        job = SimpleNamespace(
            service_category="goods_transport_truck",
            service_title="Truck Freight",
            issue_title="Transport Cargo",
            fare_breakdown={"crew_size": 2},
            cart_data=[],
        )
        crew_size, items, relocation = extract_pm_job_details(job)
        self.assertIsNone(crew_size)
        self.assertIsNone(items)
        self.assertIsNone(relocation)


class PackersMoversSerializerTests(SimpleTestCase):
    def test_serializer_exposes_pm_fields(self):
        job = SimpleNamespace(
            id=42,
            request_id="SR-PM-42",
            service_category="packers_movers",
            service_title="Packers & Movers Shifting",
            issue_title="House Move",
            description="2BHK relocation",
            status="accepted",
            priority="normal",
            customer_name="Anita",
            phone="9876543210",
            email="anita@example.com",
            address="12 MG Road",
            latitude=Decimal("12.970000"),
            longitude=Decimal("77.590000"),
            total_amount=Decimal("7500.00"),
            payment_status="pending",
            payment_method="COD",
            payment=None,
            created_at=None,
            updated_at=None,
            started_at=None,
            otp_verified=False,
            otp_verified_at=None,
            preferred_date=None,
            preferred_time=None,
            drop_address="45 Whitefield",
            drop_latitude=Decimal("12.980000"),
            drop_longitude=Decimal("77.750000"),
            drop_contact_name="Anita",
            drop_contact_phone="9876543210",
            logistics_leg="ARRIVED_PICKUP",
            logistics_leg_updated_at=None,
            request_kind="DIRECT",
            assigned_employee=None,
            assigned_employee_id=None,
            fare_breakdown={
                "vehicle": {"name": "Tata Ace", "crew_size": 2},
                "inventory_summary": {
                    "total_items": 1,
                    "items": [{"name": "Sofa", "quantity": 1}],
                },
                "access": {"pickup_floor": 1, "pickup_has_lift": True, "drop_floor": 2, "drop_has_lift": False},
                "pricing": {"packing_label": "Standard", "dismantling_required": False, "unpacking_required": False},
            },
            cart_data=[],
        )

        serializer = WorkforceJobSerializer(job)
        data = serializer.data

        self.assertIn("crew_size", data)
        self.assertEqual(data["crew_size"], 2)
        self.assertIn("inventory_items", data)
        self.assertEqual(len(data["inventory_items"]), 1)
        self.assertEqual(data["inventory_items"][0]["name"], "Sofa")
        self.assertIn("relocation_details", data)
        self.assertEqual(data["relocation_details"]["pickup_floor"], 1)
        self.assertEqual(data["relocation_details"]["drop_floor"], 2)
        self.assertEqual(data["relocation_details"]["drop_has_lift"], False)


@override_settings(WORKFORCE_WEBHOOK_SECRET="s3cret")
class PackersMoversLiveTrackingTests(SimpleTestCase):
    def test_live_tracking_includes_pm_manifest_and_relocation(self):
        job = SimpleNamespace(
            id=88,
            request_id="SR-PM-88",
            status="in_progress",
            service_category="packers_movers",
            latitude=Decimal("12.900000"),
            longitude=Decimal("77.600000"),
            address="Pickup Point",
            drop_latitude=Decimal("12.950000"),
            drop_longitude=Decimal("77.650000"),
            drop_address="Drop Point",
            assigned_employee=None,
            customer=None,
            customer_name="",
            phone="",
            company_id=None,
            pre_service_verification=None,
            fare_breakdown={
                "vehicle": {"crew_size": 3, "name": "Canter 14ft"},
                "inventory_summary": {
                    "items": [
                        {"name": "Wardrobe", "quantity": 2},
                        {"name": "Fridge", "quantity": 1},
                    ]
                },
                "access": {"pickup_floor": 0, "pickup_has_lift": True, "drop_floor": 4, "drop_has_lift": True},
                "pricing": {"packing_label": "Full Packing", "dismantling_required": True, "unpacking_required": True},
            },
            cart_data=[],
        )

        qs = MagicMock()
        qs.select_related.return_value.first.return_value = job
        req = APIRequestFactory().get("/api/workforce/jobs/88/live-tracking/", HTTP_AUTHORIZATION="Bearer s3cret")
        empty = MagicMock()
        empty.filter.return_value.first.return_value = None

        with patch.object(ServiceRequest.objects, "filter", return_value=qs), \
             patch.object(wf_models.JobTrackingSession, "objects", empty), \
             patch.object(wf_models.PreServiceVerification, "objects", empty):
            resp = WorkforceJobLiveTrackingView.as_view()(req, pk=88)

        self.assertEqual(resp.status_code, 200)
        self.assertEqual(resp.data["crew_size"], 3)
        self.assertEqual(len(resp.data["inventory_items"]), 2)
        self.assertIsNotNone(resp.data["relocation_details"])
        self.assertEqual(resp.data["relocation_details"]["drop_floor"], 4)
        self.assertTrue(resp.data["relocation_details"]["dismantling_required"])


class PackersMoversCancellationLockTests(TestCase):
    def test_cancel_locked_when_trip_in_physical_progress(self):
        emp = SimpleNamespace(id=10, pk=10, company_id=None)
        user = SimpleNamespace(is_authenticated=True, is_active=True, id=2, pk=2, employee_profile=emp)
        job = SimpleNamespace(
            pk=99,
            id=99,
            company_id=None,
            assigned_employee=emp,
            status="accepted",
            service_category="packers_movers",
            logistics_leg="LOADING",
            updated_at=None,
        )

        from django.utils import timezone
        emp_job = MagicMock()
        emp_job.status = "ACCEPTED"
        emp_job.accepted_date = timezone.now()

        sfu = MagicMock()
        sfu.filter.return_value.first.return_value = job
        req = APIRequestFactory().post("/api/workforce/jobs/99/cancel/", {"reason_code": "TOO_FAR"}, format="json")
        force_authenticate(req, user=user)

        with patch.object(WorkforceJobTechnicianCancelView, "permission_classes", []), \
             patch.object(ServiceRequest.objects, "filter", return_value=SimpleNamespace(first=lambda: job)), \
             patch.object(ServiceRequest.objects, "select_for_update", return_value=sfu), \
             patch("workforce_api.views.is_employee_authorized_for_job", return_value=True), \
             patch("service_requests.models.EmployeeJob.objects.filter", return_value=MagicMock(exists=lambda: True, first=lambda: emp_job)):
            resp = WorkforceJobTechnicianCancelView.as_view()(req, pk=99)

        self.assertEqual(resp.status_code, 409)
        self.assertEqual(resp.data["code"], "TRIP_PROGRESS_CANCELLATION_LOCKED")
