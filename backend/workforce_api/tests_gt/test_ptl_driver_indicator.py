"""Light PTL: the driver job payload flags 'customer loads & unloads' (read-only, from fare_breakdown)."""
from decimal import Decimal
from types import SimpleNamespace

from django.test import SimpleTestCase

from workforce_api.serializers import WorkforceJobSerializer
from workforce_api.services.logistics_events import extract_ptl_job_details

PTL_FB = {"booking_mode": "ptl", "pricing_basis": "ptl_per_kg", "loading_responsibility": "customer",
          "declared_weight_kg": "300.00", "loading_unloading": "0.00", "total": "1200.00",
          "load_assist": False, "load_assist_execution": None}


def _job(fb, category="goods_transport_truck"):
    return SimpleNamespace(
        id=7, request_id="GT0007", service_category=category, service_title="Mini Truck",
        issue_title="Part load", description="20 cartons", status="accepted", priority="normal",
        customer_name="C", phone="9876543210", email="c@e.com", address="Hosur",
        latitude=Decimal("12.74"), longitude=Decimal("77.82"), total_amount=Decimal("1200.00"),
        payment_status="pending", payment_method="COD", payment=None, created_at=None, updated_at=None,
        started_at=None, otp_verified=False, otp_verified_at=None, preferred_date=None, preferred_time=None,
        drop_address="Bengaluru", drop_latitude=Decimal("12.93"), drop_longitude=Decimal("77.62"),
        drop_contact_name="", drop_contact_phone="", logistics_leg="ASSIGNED", logistics_leg_updated_at=None,
        request_kind="DIRECT", assigned_employee=None, assigned_employee_id=None,
        fare_breakdown=fb, cart_data=[],
    )


class PTLDriverIndicatorTests(SimpleTestCase):
    def test_ptl_job_flags_customer_loading_without_amounts(self):
        d = extract_ptl_job_details(_job(PTL_FB))
        self.assertEqual(d["loading_responsibility"], "customer")
        self.assertEqual(d["declared_weight_kg"], "300.00")
        self.assertTrue(d["is_ptl"])
        self.assertNotIn("total", d)

    def test_pricing_basis_alone_is_enough_and_spot_returns_none(self):
        self.assertIsNotNone(extract_ptl_job_details(_job({"pricing_basis": "ptl_per_kg"})))
        self.assertIsNone(extract_ptl_job_details(_job({"pricing_basis": "distance", "loading_unloading": "100"})))
        self.assertIsNone(extract_ptl_job_details(_job(None)))

    def test_serializer_exposes_ptl_details(self):
        data = WorkforceJobSerializer(_job(PTL_FB)).data
        self.assertEqual(data["ptl_details"]["loading_responsibility"], "customer")
        self.assertIsNone(WorkforceJobSerializer(_job({"pricing_basis": "distance"})).data["ptl_details"])
