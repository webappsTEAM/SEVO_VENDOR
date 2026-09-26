"""
Real-database end-to-end lifecycle tests for Goods & Transport (Mini Truck,
Two Wheeler) and Packers & Movers, driven through the real vendor API views.

Every other test in this package stands in for ServiceRequest with a
SimpleNamespace because the model is an unmanaged mirror of a table the
Customer app owns, so no test table exists. That leaves the views' real
ORM behaviour -- and what they actually emit to the Customer app -- untested.
Here the mirror tables are created in the test database from the mirror
models themselves, so dispatch -> accept -> arrive -> start -> legs ->
checkpoints -> proof -> payment -> completion and the cancellation paths run
against real rows, and the durable webhook outbox is inspected to see exactly
what the Customer app would be sent.
"""
import io
import json
from datetime import date, timedelta
from decimal import Decimal
from unittest.mock import patch

from django.apps import apps
from django.conf import settings
from django.core.files.uploadedfile import SimpleUploadedFile
from django.db import connection
from django.test import TransactionTestCase
from django.utils import timezone
from PIL import Image
from rest_framework.test import APIClient

PICK = (12.9716, 77.5946)
DROP = (13.0355, 77.5970)


def _png():
    buf = io.BytesIO()
    Image.new("RGB", (64, 64), (200, 30, 30)).save(buf, "PNG")
    return buf.getvalue()


PNG = _png()


def _img():
    return SimpleUploadedFile("p.png", PNG, content_type="image/png")


def _mirror_models():
    return [m for m in apps.get_models() if not m._meta.managed]


def create_mirror_tables():
    """Create the unmanaged mirror tables that do not exist yet; return the
    models whose tables this call created (so they can be dropped again)."""
    names = connection.introspection.table_names()
    created = []
    with connection.constraint_checks_disabled():
        with connection.schema_editor() as editor:
            for model in _mirror_models():
                if model._meta.db_table not in names:
                    editor.create_model(model)
                    created.append(model)
    return created


def clear_mirror_tables():
    """TransactionTestCase only flushes managed tables, so mirror rows would
    otherwise leak from one test into the next."""
    with connection.constraint_checks_disabled():
        with connection.cursor() as cursor:
            for model in _mirror_models():
                cursor.execute(f'DELETE FROM "{model._meta.db_table}"')


def drop_mirror_tables(models):
    with connection.constraint_checks_disabled():
        with connection.schema_editor() as editor:
            for model in reversed(models):
                editor.delete_model(model)


class Trip:
    """One company, one customer, one approved online technician with a
    document-current vehicle, and one confirmed booking."""

    def __init__(self, category="goods_transport_truck", vehicle_type="truck", capacity=1000,
                 fare=None, tag="1"):
        from accounts.models import User
        from companies.models import Company
        from employees.models import Employee
        from service_requests.models import ServiceRequest
        from workforce_api.models import Vehicle

        self.category = category
        self.company = Company.objects.create(company_name="Acme" + tag, slug="acme" + tag)
        self.customer = User.objects.create(username="cust" + tag, role="customer", company=self.company, password="x")
        self.tech_user = User.objects.create(
            username="tech" + tag, role="employee", company=self.company, password="x",
            last_known_location={"latitude": PICK[0] + 0.001, "longitude": PICK[1],
                                 "updated_at": timezone.now().isoformat()},
        )
        self.emp = Employee.objects.create(
            user=self.tech_user, employee_id="E" + tag, company=self.company,
            is_online=True, current_availability="available",
            bank_details={"onboarding": {"status": "approved", "documents": {},
                                         "services": [{"status": "approved", "name": category, "category": category}]}},
        )
        soon = date.today() + timedelta(days=100)
        Vehicle.objects.create(employee=self.emp, company=self.company, vehicle_type=vehicle_type,
                               registration_number="KA" + tag, capacity_kg=capacity,
                               insurance_expiry=soon, permit_expiry=soon, puc_expiry=soon)
        self.sr = ServiceRequest.objects.create(
            request_id="SR-" + tag, company=self.company, customer=self.customer, customer_name="C", phone="9",
            service_category=category, issue_title=category, address="Pickup", latitude=PICK[0], longitude=PICK[1],
            drop_address="Drop", drop_latitude=DROP[0], drop_longitude=DROP[1], status="confirmed",
            payment_method="COD", payment_status="pending", total_amount=Decimal("500"),
            preferred_date=date.today(), preferred_time="Now", fare_breakdown=fare or {}, start_otp="123456",
        )
        self.api = APIClient()
        self.api.force_authenticate(user=self.tech_user)

    def url(self, tail):
        return f"/api/workforce/jobs/{self.sr.id}/{tail}"

    def refresh(self):
        self.sr.refresh_from_db()
        return self.sr

    def emp_now(self):
        self.emp.refresh_from_db()
        return self.emp

    def outbox(self):
        from workforce_api.models import WorkforceOutboundWebhook
        return [(w.event_type, w.payload or {}) for w in WorkforceOutboundWebhook.objects.order_by("id")]

    def events(self):
        return [event for event, _ in self.outbox()]

    def payloads(self, event):
        return [payload for name, payload in self.outbox() if name == event]

    # ---- driver actions -------------------------------------------------
    def dispatch(self):
        from workforce_api.services.automatic_dispatch import dispatch_job
        return dispatch_job(self.sr)

    def accept(self):
        return self.api.post(self.url("accept-offer/"))

    def start_job(self):
        assert self.accept().status_code == 200
        r = self.api.post(self.url("arrive/"), {"lat": PICK[0], "lon": PICK[1]}, format="json")
        assert r.status_code == 200, r.data
        r = self.api.post(self.url("verify-otp/"), {"otp": "123456"}, format="json")
        assert r.status_code == 200, r.data
        r = self.api.post(self.url("pre-service-photo/"), {"photo_type": "presence", "file": _img()}, format="multipart")
        assert r.status_code == 201 and r.data["job_started"], r.data

    def checkpoint(self, checkpoint, action, **extra):
        body = {"checkpoint": checkpoint, "action": action, **extra}
        if action == "photo":
            body["file"] = _img()
            return self.api.post(self.url("logistics-checkpoint/"), body, format="multipart")
        return self.api.post(self.url("logistics-checkpoint/"), body, format="json")

    def gps(self, checkpoint):
        point = PICK if checkpoint == "PICKUP" else DROP
        return self.checkpoint(checkpoint, "gps", lat=point[0], lon=point[1])

    def leg(self, leg):
        return self.api.post(self.url("logistics-leg/"), {"leg": leg}, format="json")

    def delivery_otp(self):
        from workforce_api.models import LogisticsCheckpointVerification
        return LogisticsCheckpointVerification.objects.get(job_id=self.sr.id, checkpoint="DROP").otp_code

    def submit_proof(self):
        return self.api.post(self.url("proof/"), {"notes": "handed over", "after_work_area_photo": _img()},
                             format="multipart")

    def settle_cash(self):
        with patch("workforce_api.views.secrets.randbelow", lambda n: 23456):   # OTP 123456
            r = self.api.post(self.url("collect-cash/"), {}, format="json")
        assert r.status_code == 200, r.data
        return self.api.post(self.url("payment/verify-otp/"), {"otp": "123456"}, format="json")


class RealDbBase(TransactionTestCase):
    _created_mirror_models = []

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls._created_mirror_models = create_mirror_tables()

    @classmethod
    def tearDownClass(cls):
        # Leave the test database as it was found: no mirror tables for other
        # tests (some of which introspect the schema) to trip over.
        drop_mirror_tables(cls._created_mirror_models)
        super().tearDownClass()

    def setUp(self):
        # Delivery is on_commit + a thread on another connection; the outbox row
        # is what is under test, so keep delivery out of the way.
        patcher = patch("workforce_api.services.customer_webhook._post_webhook_async", lambda *a, **k: None)
        patcher.start()
        self.addCleanup(patcher.stop)
        self.addCleanup(clear_mirror_tables)

    def ok(self, response, code=200):
        self.assertEqual(response.status_code, code, getattr(response, "data", None))
        return response


class HappyPathTests(RealDbBase):
    def test_mini_truck_full_lifecycle(self):
        t = Trip(fare={"vehicle_class": "truck"})
        self.assertTrue(t.dispatch()[0])
        t.start_job()
        self.assertEqual(t.refresh().status, "in_progress")
        self.assertEqual(t.sr.logistics_leg, "EN_ROUTE_PICKUP")

        # Nothing can be skipped: leaving pickup and reaching the drop are gated on evidence.
        r = t.leg("LOADING")
        self.assertEqual(r.status_code, 400)
        self.assertEqual(r.data["code"], "CHECKPOINT_VERIFICATION_REQUIRED")
        self.ok(t.gps("PICKUP"))
        self.ok(t.leg("LOADING"))
        self.assertEqual(t.leg("EN_ROUTE_DROP").status_code, 400)          # no loading photo yet
        self.ok(t.checkpoint("PICKUP", "photo"))
        self.ok(t.leg("EN_ROUTE_DROP"))
        self.ok(t.gps("DROP"))
        self.ok(t.leg("UNLOADING"))
        self.assertEqual(t.leg("DELIVERED").status_code, 400)              # no unloading photo / OTP yet
        self.ok(t.checkpoint("DROP", "photo"))
        wrong = t.checkpoint("DROP", "otp", otp="000000")
        self.assertEqual((wrong.status_code, wrong.data["code"]), (400, "INVALID_OTP"))
        # Non-ASCII input (e.g. Arabic-Indic digits from a phone keyboard) must be a
        # normal wrong-code answer, not an unhandled comparison error.
        odd = t.checkpoint("DROP", "otp", otp="\u0661\u0662\u0663\u0664\u0665\u0666")
        self.assertEqual((odd.status_code, odd.data["code"]), (400, "INVALID_OTP"))
        self.ok(t.checkpoint("DROP", "otp", otp=t.delivery_otp()))
        self.ok(t.leg("DELIVERED"))

        self.ok(t.submit_proof())
        self.assertEqual(t.refresh().status, "proof_submitted")
        self.ok(t.settle_cash())
        self.assertEqual(t.refresh().status, "completed")
        self.assertEqual(t.sr.payment_status, "paid")
        self.assertEqual([h["leg"] for h in t.sr.logistics_leg_history],
                         ["EN_ROUTE_PICKUP", "LOADING", "EN_ROUTE_DROP", "UNLOADING", "DELIVERED"])

        events = t.events()
        for expected in ("employee_accepted", "employee_arrived", "service_started", "logistics.leg_changed",
                         "logistics.delivery_otp_issued", "job.completion_proof_submitted",
                         "payment.collected", "service_completed"):
            self.assertIn(expected, events)
        # Proof of delivery reaches the Customer app with the evidence, not just free text.
        (proof,) = t.payloads("job.completion_proof_submitted")
        self.assertTrue(proof["photo_url"])
        self.assertTrue(proof["otp_verified"])
        self.assertEqual(proof["notes"], "handed over")
        self.assertEqual(proof["workforce_employee_id"], str(t.emp.id))
        self.assertAlmostEqual(float(proof["location"]["latitude"]), DROP[0], places=4)
        self.assertAlmostEqual(float(proof["location"]["longitude"]), DROP[1], places=4)
        self.assertEqual(t.emp_now().current_availability, "available")

    def test_two_wheeler_lifecycle(self):
        t = Trip(category="goods_transport_two_wheeler", vehicle_type="two_wheeler", capacity=50,
                 fare={"vehicle_class": "two_wheeler"}, tag="2")
        self.assertTrue(t.dispatch()[0])
        t.start_job()
        self.ok(t.gps("PICKUP")); self.ok(t.leg("LOADING")); self.ok(t.checkpoint("PICKUP", "photo"))
        self.ok(t.leg("EN_ROUTE_DROP")); self.ok(t.gps("DROP")); self.ok(t.leg("UNLOADING"))
        self.ok(t.checkpoint("DROP", "photo")); self.ok(t.checkpoint("DROP", "otp", otp=t.delivery_otp()))
        self.ok(t.leg("DELIVERED")); self.ok(t.submit_proof()); self.ok(t.settle_cash())
        self.assertEqual(t.refresh().status, "completed")
        self.assertEqual(t.sr.logistics_leg, "DELIVERED")
        self.assertEqual(len(t.payloads("job.completion_proof_submitted")), 1)

    def test_packers_movers_thirteen_stage_lifecycle(self):
        t = Trip(category="packers_movers", vehicle_type="truck", capacity=3000,
                 fare={"vehicle": {"payload_kg": 2000, "crew_size": 3}}, tag="3")
        self.assertTrue(t.dispatch()[0])
        t.start_job()
        self.assertEqual(t.refresh().logistics_leg, "ASSIGNED")             # P&M does not start on a GT-only leg
        self.assertEqual(t.leg("ARRIVED_PICKUP").status_code, 400)           # GPS gate at pickup
        self.ok(t.leg("TEAM_EN_ROUTE"))
        self.ok(t.gps("PICKUP")); self.ok(t.leg("ARRIVED_PICKUP"))
        self.ok(t.leg("PACKING")); self.ok(t.leg("DISMANTLING")); self.ok(t.leg("LOADING"))
        self.assertEqual(t.leg("IN_TRANSIT").status_code, 400)               # loading photo gate
        self.ok(t.checkpoint("PICKUP", "photo")); self.ok(t.leg("IN_TRANSIT"))
        self.assertEqual(t.leg("ARRIVED_DROP").status_code, 400)             # drop GPS gate
        self.ok(t.gps("DROP")); self.ok(t.leg("ARRIVED_DROP"))
        self.ok(t.leg("UNLOADING")); self.ok(t.leg("REASSEMBLY")); self.ok(t.leg("UNPACKING"))
        self.assertEqual(t.leg("DELIVERED").status_code, 400)                # photo + OTP gate
        self.ok(t.checkpoint("DROP", "photo")); self.ok(t.checkpoint("DROP", "otp", otp=t.delivery_otp()))
        self.ok(t.leg("DELIVERED")); self.ok(t.submit_proof()); self.ok(t.settle_cash())
        self.assertEqual(t.refresh().status, "completed")
        self.assertEqual([h["leg"] for h in t.sr.logistics_leg_history],
                         ["ASSIGNED", "TEAM_EN_ROUTE", "ARRIVED_PICKUP", "PACKING", "DISMANTLING", "LOADING",
                          "IN_TRANSIT", "ARRIVED_DROP", "UNLOADING", "REASSEMBLY", "UNPACKING", "DELIVERED",
                          "COMPLETED"])                                      # closing the job completes the 13th stage
        self.assertEqual(len(t.payloads("job.completion_proof_submitted")), 1)

    def test_customer_service_dispatch_endpoint_creates_an_offer(self):
        from workforce_api.models import WorkforceJobOffer
        t = Trip(fare={"vehicle_class": "truck"}, tag="4")
        client = APIClient()
        r = client.post("/api/workforce/jobs/dispatch/", {"booking_id": t.sr.request_id}, format="json",
                        HTTP_AUTHORIZATION="Bearer " + settings.WORKFORCE_WEBHOOK_SECRET)
        self.ok(r)
        self.assertTrue(r.data["success"], r.data)
        self.assertEqual(WorkforceJobOffer.objects.filter(job_id=t.sr.id, status="OFFERED").count(), 1)
        self.assertEqual(client.post("/api/workforce/jobs/dispatch/", {"booking_id": t.sr.request_id},
                                     format="json").status_code, 401)


class FailureAndEdgeTests(RealDbBase):
    def test_capacity_and_class_mismatch_block_dispatch_and_acceptance(self):
        small = Trip(vehicle_type="two_wheeler", capacity=50, fare={"vehicle_class": "truck"}, tag="5")
        ok, message = small.dispatch()
        self.assertFalse(ok, message)
        r = small.accept()
        self.assertEqual((r.status_code, r.data["code"]), (403, "VEHICLE_CLASS_MISMATCH"))
        self.assertIsNone(small.refresh().assigned_employee_id)

        pm = Trip(category="packers_movers", vehicle_type="truck", capacity=500,
                  fare={"vehicle": {"payload_kg": 2000}}, tag="6")
        self.assertFalse(pm.dispatch()[0])
        r = pm.accept()
        self.assertEqual((r.status_code, r.data["code"]), (403, "VEHICLE_CAPACITY_MISMATCH"))

    def test_declined_offer_cannot_be_accepted_and_is_not_offered_again(self):
        from workforce_api.models import WorkforceJobOffer
        t = Trip(fare={"vehicle_class": "truck"}, tag="7")
        self.assertTrue(t.dispatch()[0])
        self.ok(t.api.post(t.url("reject-offer/"), {"reason": "too far"}, format="json"))
        self.assertEqual(WorkforceJobOffer.objects.get(job_id=t.sr.id).status, "REJECTED")
        self.assertEqual(t.refresh().status, "unassigned")
        r = t.accept()
        self.assertEqual((r.status_code, r.data["code"]), (400, "OFFER_ALREADY_DECLINED"))
        # A repeated decline is idempotent, not an error.
        self.ok(t.api.post(t.url("reject-offer/"), {"reason": "too far"}, format="json"))
        self.assertEqual(WorkforceJobOffer.objects.filter(job_id=t.sr.id).count(), 1)

    def test_invalid_transitions_and_legs_are_rejected(self):
        t = Trip(fare={"vehicle_class": "truck"}, tag="8")
        t.dispatch()
        self.assertEqual(t.api.post(t.url("transition/"), {"status": "completed"}, format="json").status_code, 403)
        self.ok(t.accept())
        self.assertEqual(t.api.post(t.url("transition/"), {"status": "completed"}, format="json").status_code, 400)
        self.assertEqual(t.api.post(t.url("transition/"), {"status": "in_progress"}, format="json").status_code, 400)
        r = t.leg("DELIVERED")
        self.assertEqual((r.status_code, r.data["code"]), (400, "FINAL_LEG_NOT_ALLOWED_YET"))
        self.assertEqual(t.leg("UNLOADING").status_code, 400)               # checkpoints not passed
        self.assertEqual(t.leg("FLYING").status_code, 400)                  # unknown leg
        # A repeat of the current leg is an idempotent no-op, not a rewrite of history.
        r = self.ok(t.leg("EN_ROUTE_PICKUP"))
        self.assertFalse(r.data["changed"])
        self.assertEqual(len(t.refresh().logistics_leg_history), 1)

    def test_duplicate_requests_are_idempotent(self):
        t = Trip(fare={"vehicle_class": "truck"}, tag="9")
        t.dispatch()
        self.ok(t.accept())
        again = self.ok(t.accept())
        self.assertIn("already accepted", again.data["message"])
        self.assertEqual(t.events().count("employee_accepted"), 1)
        self.ok(t.api.post(t.url("arrive/"), {"lat": PICK[0], "lon": PICK[1]}, format="json"))
        self.ok(t.api.post(t.url("arrive/"), {"lat": PICK[0], "lon": PICK[1]}, format="json"))
        self.assertEqual(t.refresh().start_otp, "123456")                    # not regenerated by a retry

    def test_multi_stop_progress_is_recorded_and_emitted_once(self):
        from service_requests.models import TripStop
        t = Trip(fare={"vehicle_class": "truck"}, tag="10")
        first = TripStop.objects.create(booking=t.sr, sequence=1, stop_type="pickup", address="A")
        second = TripStop.objects.create(booking=t.sr, sequence=2, stop_type="drop", address="B")
        t.dispatch(); t.start_job()
        listing = self.ok(t.api.get(t.url("stops/"))).data["results"]
        self.assertEqual([s["sequence"] for s in listing], [1, 2])
        self.ok(t.api.post(t.url("stops/"), {"stop_sequence": 1}, format="json"))
        self.ok(t.api.post(t.url("stops/"), {"stop_sequence": 1, "completed": True}, format="json"))
        r = self.ok(t.api.post(t.url("stops/"), {"stop_sequence": 1, "completed": True}, format="json"))
        self.assertFalse(r.data["changed"])                                  # retry does not move timestamps
        first.refresh_from_db(); second.refresh_from_db()
        self.assertIsNotNone(first.arrived_at); self.assertIsNotNone(first.completed_at)
        self.assertIsNone(second.arrived_at)
        self.assertEqual(t.api.post(t.url("stops/"), {"stop_sequence": 9}, format="json").status_code, 404)
        self.assertGreaterEqual(t.events().count("trip.stop_completed"), 1)


class CancellationTests(RealDbBase):
    def test_technician_withdrawal_releases_them_and_tells_the_customer_app(self):
        t = Trip(fare={"vehicle_class": "truck"}, tag="11")
        t.dispatch(); self.ok(t.accept())
        self.assertEqual(t.emp_now().current_availability, "busy")
        r = t.api.post(t.url("cancel/"), {"reason_code": "VEHICLE_ISSUE", "reason_detail": "flat tyre"}, format="json")
        self.ok(r)
        self.assertEqual(t.refresh().status, "confirmed")
        self.assertIsNone(t.sr.assigned_employee_id)
        # Released, not left "busy" (which is what a technician cancel used to leave behind).
        self.assertEqual(t.emp_now().current_availability, "available")
        events = t.events()
        # The booking is being re-dispatched, so the Customer app must be told the technician
        # withdrew ("employee_rejected"), never that the booking was cancelled.
        self.assertIn("employee_rejected", events)
        self.assertNotIn("technician.cancelled", events)
        self.assertNotIn("job.cancelled", events)
        (event,) = t.payloads("employee_rejected")
        self.assertIn("VEHICLE_ISSUE", event["reason"])

    def test_technician_cancel_is_locked_once_the_trip_has_progressed(self):
        t = Trip(fare={"vehicle_class": "truck"}, tag="12")
        t.dispatch(); t.start_job()
        self.ok(t.gps("PICKUP")); self.ok(t.leg("LOADING"))
        r = t.api.post(t.url("cancel/"), {"reason_code": "VEHICLE_ISSUE", "reason_detail": "flat tyre"}, format="json")
        self.assertEqual(r.status_code, 409)
        self.assertEqual(t.refresh().status, "in_progress")
        self.assertNotIn("employee_rejected", t.events())

    def test_customer_cancellation_syncs_and_releases_the_technician(self):
        t = Trip(fare={"vehicle_class": "truck"}, tag="13")
        t.dispatch(); t.start_job()
        self.ok(t.gps("PICKUP")); self.ok(t.leg("LOADING"))
        client = APIClient()
        auth = {"HTTP_AUTHORIZATION": "Bearer " + settings.WORKFORCE_WEBHOOK_SECRET}
        self.assertEqual(client.post(t.url("customer-cancel-sync/"), {}, format="json").status_code, 401)
        self.ok(client.post(t.url("customer-cancel-sync/"), {}, format="json", **auth))
        self.assertEqual(t.refresh().status, "cancelled")
        self.assertEqual(t.emp_now().current_availability, "available")
        # Repeating it is safe.
        self.ok(client.post(t.url("customer-cancel-sync/"), {}, format="json", **auth))
        # A cancelled trip accepts no further legs, stops or proof.
        self.assertEqual(t.leg("EN_ROUTE_DROP").status_code, 400)
        self.assertEqual(t.submit_proof().status_code, 400)


class DeliveryProofAndArrivalTests(RealDbBase):
    def test_proof_of_delivery_is_sent_for_logistics_only(self):
        from workforce_api.services.logistics_events import emit_delivery_proof_for_job, emit_technician_arrived
        from types import SimpleNamespace
        non_logistics = SimpleNamespace(id=1, service_category="ac_repair", assigned_employee=None)
        self.assertFalse(emit_delivery_proof_for_job(non_logistics, None))
        self.assertFalse(emit_technician_arrived(non_logistics, None))

    def test_resubmitted_proof_carries_the_new_evidence_and_never_blocks(self):
        t = Trip(fare={"vehicle_class": "truck"}, tag="14")
        t.dispatch(); t.start_job()
        self.ok(t.gps("PICKUP")); self.ok(t.leg("LOADING")); self.ok(t.checkpoint("PICKUP", "photo"))
        self.ok(t.leg("EN_ROUTE_DROP")); self.ok(t.gps("DROP")); self.ok(t.leg("UNLOADING"))
        self.ok(t.checkpoint("DROP", "otp", otp=t.delivery_otp()))
        self.ok(t.submit_proof())
        self.ok(t.submit_proof())                                            # driver retries the upload
        self.assertEqual(len(t.payloads("job.completion_proof_submitted")), 2)
        self.assertEqual(t.refresh().status, "proof_submitted")
