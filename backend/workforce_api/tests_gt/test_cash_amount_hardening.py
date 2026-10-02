"""Forensic QA regression: a driver-supplied cash amount must never crash the
collect-cash endpoint (NaN/Infinity/overflow used to raise an unhandled 500)."""
from workforce_api.tests_gt.test_realdb_gt_lifecycle import RealDbBase, Trip


class CashAmountHardeningTests(RealDbBase):
    def _delivered_trip(self):
        t = Trip(fare={"vehicle_class": "truck"})
        self.assertTrue(t.dispatch()[0])
        t.start_job()
        self.ok(t.gps("PICKUP")); self.ok(t.leg("LOADING"))
        self.ok(t.checkpoint("PICKUP", "photo")); self.ok(t.leg("EN_ROUTE_DROP"))
        self.ok(t.gps("DROP")); self.ok(t.leg("UNLOADING"))
        self.ok(t.checkpoint("DROP", "photo"))
        self.ok(t.checkpoint("DROP", "otp", otp=t.delivery_otp()))
        self.ok(t.leg("DELIVERED")); self.ok(t.submit_proof())
        return t

    def test_hostile_amounts_are_clean_400_and_valid_amount_still_works(self):
        t = self._delivered_trip()
        t.api.raise_request_exception = False
        for bad in ("NaN", "sNaN", "Infinity", "-Infinity", "1e20", "abc"):
            with self.subTest(amount_received=bad):
                r = t.api.post(t.url("collect-cash/"), {"amount_received": bad}, format="json")
                self.assertEqual(r.status_code, 400, (bad, getattr(r, "data", None)))
        # Default (no amount) = exact amount due must still succeed.
        r = t.api.post(t.url("collect-cash/"), {}, format="json")
        self.assertEqual(r.status_code, 200, getattr(r, "data", None))
