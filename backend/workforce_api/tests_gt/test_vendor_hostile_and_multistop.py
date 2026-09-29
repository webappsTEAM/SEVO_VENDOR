"""
Vendor API probes on the real (mirrored) DB: hostile inputs never 5xx, other drivers/anonymous
callers are refused, and a multi-stop trip (Pickup -> Stop -> Drop) is served in order with exact
coordinates and per-stop progress reaching the Customer app.
"""
from decimal import Decimal
from unittest.mock import patch

from rest_framework.test import APIClient

from .test_realdb_gt_lifecycle import DROP, PICK, RealDbBase, Trip


class VendorHostileInputTests(RealDbBase):
    def _running(self, tag):
        t = Trip(fare={"vehicle_class": "truck"}, tag=tag)
        self.assertTrue(t.dispatch()[0]); t.start_job()
        return t

    def test_anonymous_and_other_driver_are_refused(self):
        t = self._running("20")
        anon = APIClient()
        for tail, method in (("stops/", "get"), ("stops/", "post"), ("logistics-leg/", "post"), ("live-tracking/", "get")):
            r = getattr(anon, method)(t.url(tail), {}, format="json") if method == "post" else anon.get(t.url(tail))
            self.assertIn(r.status_code, (401, 403), (tail, r.status_code))
        other = Trip(fare={"vehicle_class": "truck"}, tag="21")             # a different approved driver
        for tail, method in (("stops/", "get"), ("stops/", "post"), ("logistics-leg/", "post")):
            r = other.api.get(t.url(tail)) if method == "get" else other.api.post(t.url(tail), {"stop_sequence": 1, "leg": "LOADING"}, format="json")
            self.assertIn(r.status_code, (403, 404), (tail, r.status_code))

    def test_hostile_stop_leg_gps_and_checkpoint_payloads_never_5xx(self):
        t = self._running("22")
        bodies = [None, {}, {"stop_id": "abc"}, {"stop_id": -1}, {"stop_id": 10 ** 20}, {"stop_sequence": "x"}, {"stop_sequence": None, "stop_id": None},
                  {"stop_id": [1]}, {"stop_id": {"a": 1}}, {"stop_sequence": 1.5}]
        for b in bodies:
            r = t.api.post(t.url("stops/"), b, format="json")
            self.assertLess(r.status_code, 500, (b, r.status_code, getattr(r, "data", None)))
        for leg in (None, "", "NOPE", 5, ["LOADING"], "loading", "DELIVERED", "COMPLETED", "EN_ROUTE_PICKUP"):
            r = t.api.post(t.url("logistics-leg/"), {"leg": leg}, format="json")
            self.assertLess(r.status_code, 500, (leg, r.status_code, getattr(r, "data", None)))
        for lat, lon in ((999, 0), (-999, 0), ("x", "y"), (None, None), (float("nan") if False else "NaN", 1), (0, 0), (91, 181)):
            r = t.checkpoint("PICKUP", "gps", lat=lat, lon=lon)
            self.assertLess(r.status_code, 500, (lat, lon, r.status_code))
            self.assertNotEqual(r.status_code, 200, (lat, lon))
        for cp, act in (("NOWHERE", "gps"), ("PICKUP", "explode"), (None, None), ("PICKUP", "otp")):
            r = t.api.post(t.url("logistics-checkpoint/"), {"checkpoint": cp, "action": act}, format="json")
            self.assertLess(r.status_code, 500, (cp, act, r.status_code))
        for otp in (None, "", "12", "1234567", "abcdef", "١٢٣٤٥٦", "0" * 500):
            r = t.api.post(t.url("verify-otp/"), {"otp": otp}, format="json")
            self.assertLess(r.status_code, 500, (otp, r.status_code))

    def test_leg_cannot_be_skipped_or_reversed(self):
        t = self._running("23")
        for leg in ("EN_ROUTE_DROP", "UNLOADING", "DELIVERED"):
            r = t.leg(leg)
            self.assertEqual(r.status_code, 400, (leg, r.status_code))
        self.assertEqual(t.refresh().logistics_leg, "EN_ROUTE_PICKUP")


class MultiStopVendorTests(RealDbBase):
    def test_pickup_stop_drop_served_in_order_with_coordinates_and_progress_emitted(self):
        from service_requests.models import TripStop
        t = Trip(fare={"vehicle_class": "truck"}, tag="30")
        # created out of order on purpose: the API must answer by sequence
        TripStop.objects.create(booking=t.sr, sequence=3, stop_type="DROP", address="Drop Rd", latitude=DROP[0], longitude=DROP[1])
        TripStop.objects.create(booking=t.sr, sequence=2, stop_type="WAYPOINT", address="Mid", latitude=12.745, longitude=77.83)
        TripStop.objects.create(booking=t.sr, sequence=1, stop_type="PICKUP", address="Pickup St", latitude=PICK[0], longitude=PICK[1])
        t.dispatch(); t.start_job()
        listing = self.ok(t.api.get(t.url("stops/"))).data["results"]
        self.assertEqual([s["stop_type"] for s in listing], ["PICKUP", "WAYPOINT", "DROP"])
        self.assertEqual([s["sequence"] for s in listing], [1, 2, 3])
        self.assertEqual((listing[1]["latitude"], listing[1]["longitude"]), (12.745, 77.83))
        # drive the full trip; the middle stop is arrived + completed on the way
        self.ok(t.gps("PICKUP")); self.ok(t.leg("LOADING")); self.ok(t.checkpoint("PICKUP", "photo")); self.ok(t.leg("EN_ROUTE_DROP"))
        mid = listing[1]["id"]
        self.ok(t.api.post(t.url("stops/"), {"stop_id": mid}, format="json"))
        done = self.ok(t.api.post(t.url("stops/"), {"stop_id": mid, "completed": True}, format="json")).data
        self.assertTrue(done["changed"] or done["completed_at"])
        after = self.ok(t.api.get(t.url("stops/"))).data["results"]
        self.assertIsNotNone(after[1]["arrived_at"]); self.assertIsNotNone(after[1]["completed_at"])
        self.assertIsNone(after[2]["arrived_at"])                              # drop untouched
        evs = t.events()
        self.assertGreaterEqual(evs.count("trip.stop_completed"), 1)
        # the Customer app is told which stop, by sequence/id
        (payload, *_) = t.payloads("trip.stop_completed")
        self.assertEqual(payload.get("stop_id") or payload.get("id"), mid)
        # finish: drop checkpoint gates still apply after a multi-stop leg
        self.ok(t.gps("DROP")); self.ok(t.leg("UNLOADING"))
        self.assertEqual(t.leg("DELIVERED").status_code, 400)
