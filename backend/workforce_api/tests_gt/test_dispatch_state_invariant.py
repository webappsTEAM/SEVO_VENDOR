"""GT_DISPATCH_INVARIANT regression tests (real database rows, real views, real dispatch engine).

Production evidence (2026-10-01/02): two scheduled GT bookings showed Customer `dispatch_status=DISPATCHED` while Workforce
held no dispatch state, no offer and no notification. Cause: the dispatch endpoint always answered success=True, the scheduled
hold returned before any state row existed, and the 'window closed -> EXPIRED' UPDATE matched zero rows.

Invariant: the Workforce answer must say what really happened (dispatch_phase), every accepted job must own a durable
WorkforceDispatchState, and an expired window must not leave the booking silently 'confirmed'.
"""
from datetime import datetime
from unittest.mock import patch
from zoneinfo import ZoneInfo

from django.test import override_settings
from rest_framework.test import APIClient

from workforce_api.tests_gt.test_realdb_gt_lifecycle import PICK, RealDbBase, Trip

IST = ZoneInfo("Asia/Kolkata")
FIXED = datetime(2026, 10, 5, 10, 0, tzinfo=IST)          # "now" for every test: 10:00 IST
HELD = "03:00 PM"                                          # window opens 14:00  -> held at 10:00
OPEN = "10:30 AM"                                          # window 09:30-10:30  -> eligible at 10:00
CLOSED = "09:00 AM"                                        # window closed at 09:00 -> closed at 10:00


class DispatchInvariantTests(RealDbBase):
    def _trip(self, preferred_time, online=True, tag="1"):
        t = Trip(fare={"vehicle_class": "truck"}, tag=tag)
        t.sr.preferred_date = FIXED.date()
        t.sr.preferred_time = preferred_time
        t.sr.save(update_fields=["preferred_date", "preferred_time"])
        t.tech_user.last_known_location = {"latitude": PICK[0] + 0.001, "longitude": PICK[1], "updated_at": FIXED.isoformat()}
        t.tech_user.save(update_fields=["last_known_location"])
        if not online:
            t.emp.is_online = False
            t.emp.save(update_fields=["is_online"])
        return t

    def _post(self, t):
        with override_settings(WORKFORCE_WEBHOOK_SECRET="s3cr3t"), patch("django.utils.timezone.now", return_value=FIXED):
            r = APIClient().post("/api/workforce/jobs/dispatch/", {"booking_id": t.sr.request_id}, format="json",
                                 HTTP_AUTHORIZATION="Bearer s3cr3t")
        self.assertEqual(r.status_code, 200, getattr(r, "data", None))
        return r.data

    def _state(self, t):
        from workforce_api.models import WorkforceDispatchState
        return WorkforceDispatchState.objects.filter(job_id=t.sr.id).first()

    def _offers(self, t):
        from workforce_api.models import WorkforceJobOffer
        return list(WorkforceJobOffer.objects.filter(job_id=t.sr.id))

    # ---- held scheduled job ----------------------------------------------------------------------------------------
    def test_held_scheduled_job_gets_durable_state_and_truthful_phase(self):
        t = self._trip(HELD)
        data = self._post(t)
        self.assertEqual(data["dispatch_phase"], "HELD_SCHEDULED")
        self.assertTrue(data["success"] and data["accepted"])                 # still accepted (backward compatible)
        st = self._state(t)
        self.assertIsNotNone(st, "held job must own a durable dispatch state")
        self.assertEqual(st.dispatch_status, "RETRY_SCHEDULED")
        self.assertEqual(st.unassigned_reason_code, "SCHEDULED_HOLD")
        self.assertEqual(st.retry_at, datetime(2026, 10, 5, 14, 0, tzinfo=IST))   # = window open
        self.assertEqual(self._offers(t), [], "no premature offer before the window opens")

    def test_held_job_is_released_by_the_sweep_when_the_window_opens(self):
        from workforce_api.services import automatic_dispatch as ad
        t = self._trip(HELD)
        self._post(t)
        at_1405 = datetime(2026, 10, 5, 14, 5, tzinfo=IST)
        t.tech_user.last_known_location = {"latitude": PICK[0] + 0.001, "longitude": PICK[1], "updated_at": at_1405.isoformat()}
        t.tech_user.save(update_fields=["last_known_location"])
        with patch("django.utils.timezone.now", return_value=at_1405):
            ad.dispatch_pending_jobs()
        self.assertEqual(len(self._offers(t)), 1, "release must create the vendor offer")
        self.assertEqual(self._state(t).dispatch_status, "OFFER_ACTIVE")

    # ---- immediate / in-window job ------------------------------------------------------------------------------------
    def test_in_window_job_with_eligible_vendor_reports_offer_active(self):
        t = self._trip(OPEN)
        data = self._post(t)
        self.assertEqual(data["dispatch_phase"], "OFFER_ACTIVE")
        self.assertEqual(len(self._offers(t)), 1)
        self.assertEqual(self._state(t).dispatch_status, "OFFER_ACTIVE")

    def test_no_eligible_vendor_is_never_reported_as_offer_active(self):
        t = self._trip(OPEN, online=False)
        data = self._post(t)
        self.assertEqual(data["dispatch_phase"], "AWAITING_ELIGIBLE_VENDOR")
        self.assertEqual(self._offers(t), [], "no phantom offer")
        st = self._state(t)
        self.assertIsNotNone(st)
        self.assertEqual(st.dispatch_status, "RETRY_SCHEDULED")                # durable retry, not a lost booking
        t.sr.refresh_from_db()
        self.assertIsNone(t.sr.assigned_employee_id, "no phantom assignment")

    def test_no_vehicle_at_all_is_never_reported_as_offer_active(self):
        from workforce_api.models import Vehicle
        t = self._trip(OPEN)
        Vehicle.objects.all().delete()
        data = self._post(t)
        self.assertEqual(data["dispatch_phase"], "AWAITING_ELIGIBLE_VENDOR")
        self.assertEqual(self._offers(t), [])

    # ---- closed window ------------------------------------------------------------------------------------------------
    def test_closed_window_records_expiry_and_unassigns_the_booking(self):
        t = self._trip(CLOSED)
        data = self._post(t)
        self.assertEqual(data["dispatch_phase"], "WINDOW_CLOSED")
        st = self._state(t)
        self.assertIsNotNone(st, "the EXPIRED update used to match zero rows when no state existed")
        self.assertEqual(st.dispatch_status, "EXPIRED")
        self.assertEqual(st.unassigned_reason_code, "SCHEDULE_WINDOW_EXPIRED")
        t.sr.refresh_from_db()
        self.assertEqual(t.sr.status, "unassigned", "customer must not keep seeing 'confirmed' for a job nobody can take")
        self.assertEqual(self._offers(t), [])

    def test_sweep_expires_a_job_that_never_had_a_state_row(self):
        from workforce_api.services import automatic_dispatch as ad
        t = self._trip(CLOSED)                                                  # never POSTed: no state row exists
        self.assertIsNone(self._state(t))
        with patch("django.utils.timezone.now", return_value=FIXED):
            ad.dispatch_pending_jobs()
        st = self._state(t)
        self.assertIsNotNone(st)
        self.assertEqual(st.dispatch_status, "EXPIRED")
        t.sr.refresh_from_db()
        self.assertEqual(t.sr.status, "unassigned")

    def test_expiry_never_overwrites_an_assigned_job(self):
        from workforce_api.models import WorkforceDispatchState
        from workforce_api.services import automatic_dispatch as ad
        t = self._trip(CLOSED)
        WorkforceDispatchState.objects.create(job_id=t.sr.id, dispatch_status="ASSIGNED")
        ad._record_window_expired(t.sr.id, FIXED, t.sr)
        self.assertEqual(self._state(t).dispatch_status, "ASSIGNED")
