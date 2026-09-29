"""
Work Start OTP hardening (real rows, real views):

* the 5-attempt cap is claimed atomically, so it cannot be out-run by
  concurrent guesses (the counter used to be read, compared and saved later);
* resend is refused once the job has started / finished / been cancelled, or
  once the OTP is already verified (a resend resets the attempt counter, so it
  must not be reachable outside the pre-start window).
"""
from workforce_api.models import PreServiceVerification
from workforce_api.tests_gt.test_realdb_gt_lifecycle import PICK, RealDbBase, Trip


class StartOtpAttemptCapTests(RealDbBase):
    def _arrived(self):
        t = Trip(fare={"vehicle_class": "truck"})
        self.assertTrue(t.dispatch()[0])
        self.assertEqual(t.accept().status_code, 200)
        r = t.api.post(t.url("arrive/"), {"lat": PICK[0], "lon": PICK[1]}, format="json")
        self.assertEqual(r.status_code, 200, r.data)
        return t

    def test_only_five_wrong_guesses_are_ever_evaluated(self):
        t = self._arrived()
        remaining = []
        for _ in range(5):
            r = t.api.post(t.url("verify-otp/"), {"otp": "000000"}, format="json")
            self.assertEqual((r.status_code, r.data["code"]), (400, "INVALID_OTP"))
            remaining.append(r.data["attempts_remaining"])
        self.assertEqual(remaining, [4, 3, 2, 1, 0])

        # The sixth attempt is refused outright -- even with the RIGHT code.
        r = t.api.post(t.url("verify-otp/"), {"otp": "123456"}, format="json")
        self.assertEqual((r.status_code, r.data["code"]), (400, "MAX_OTP_ATTEMPTS_EXCEEDED"))
        self.assertEqual(PreServiceVerification.objects.get(job_id=t.sr.id).otp_attempts, 5)
        self.assertFalse(PreServiceVerification.objects.get(job_id=t.sr.id).otp_verified)

    def test_correct_code_resets_the_counter_and_verifies(self):
        t = self._arrived()
        for _ in range(3):
            t.api.post(t.url("verify-otp/"), {"otp": "999999"}, format="json")
        r = t.api.post(t.url("verify-otp/"), {"otp": "123456"}, format="json")
        self.assertEqual(r.status_code, 200, r.data)
        psv = PreServiceVerification.objects.get(job_id=t.sr.id)
        self.assertTrue(psv.otp_verified)
        self.assertEqual(psv.otp_attempts, 0)

    def test_resend_restores_the_attempts_before_start(self):
        t = self._arrived()
        for _ in range(5):
            t.api.post(t.url("verify-otp/"), {"otp": "000000"}, format="json")
        r = t.api.post(t.url("resend-otp/"), {}, format="json")
        self.assertEqual(r.status_code, 200, r.data)
        self.assertEqual(PreServiceVerification.objects.get(job_id=t.sr.id).otp_attempts, 0)
        new_otp = t.refresh().start_otp
        r = t.api.post(t.url("verify-otp/"), {"otp": new_otp}, format="json")
        self.assertEqual(r.status_code, 200, r.data)


class StartOtpResendGuardTests(RealDbBase):
    def test_resend_is_refused_once_verified(self):
        t = Trip(fare={"vehicle_class": "truck"})
        self.assertTrue(t.dispatch()[0])
        t.start_job()                                    # arrive + verify OTP + selfie
        r = t.api.post(t.url("resend-otp/"), {}, format="json")
        self.assertEqual(r.status_code, 400, r.data)
        self.assertIn(r.data["code"], ("OTP_RESEND_NOT_ALLOWED", "OTP_ALREADY_VERIFIED"))

    def test_resend_is_refused_on_a_cancelled_job(self):
        t = Trip(fare={"vehicle_class": "truck"})
        self.assertTrue(t.dispatch()[0])
        self.assertEqual(t.accept().status_code, 200)
        t.sr.status = "cancelled"
        t.sr.save(update_fields=["status"])
        r = t.api.post(t.url("resend-otp/"), {}, format="json")
        self.assertEqual((r.status_code, r.data["code"]), (400, "OTP_RESEND_NOT_ALLOWED"))
