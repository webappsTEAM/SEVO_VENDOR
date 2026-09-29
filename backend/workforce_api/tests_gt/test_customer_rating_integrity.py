"""
Customer ratings (real rows, real views).

The two vendor feedback endpoints only required *a* logged-in session, so any
user -- including the technician being rated -- could post a rating against any
job id; and the technician-scoped endpoint resolved the technician from the URL
slot, which the Customer app fills with the JOB id, crediting the rating to
whichever unrelated employee shared that number.
"""
from django.test import override_settings
from rest_framework.test import APIClient

from workforce_api.tests_gt.test_realdb_gt_lifecycle import RealDbBase, Trip

SECRET = "rating-test-secret"


class CustomerRatingIntegrityTests(RealDbBase):
    def _delivered_trip(self):
        t = Trip(fare={"vehicle_class": "truck"})
        t.sr.status = "completed"
        t.sr.logistics_leg = "DELIVERED"
        t.sr.assigned_employee = t.emp
        t.sr.save(update_fields=["status", "logistics_leg", "assigned_employee"])
        return t

    def _decoy_employee(self, t):
        from accounts.models import User
        from employees.models import Employee
        user = User.objects.create(username="decoy", role="employee", company=t.company, password="x")
        return Employee.objects.create(user=user, employee_id="DECOY", company=t.company)

    def _rows(self, t):
        from workforce_api.models import WorkforceJobFeedback
        return list(WorkforceJobFeedback.objects.filter(job_id=t.sr.id))

    def test_the_bookings_customer_can_rate_the_assigned_technician(self):
        t = self._delivered_trip()
        api = APIClient()
        api.force_authenticate(user=t.customer)
        r = api.post(f"/api/workforce/jobs/{t.sr.id}/feedback/", {"rating": 4, "review": "on time"}, format="json")
        self.assertIn(r.status_code, (200, 201), r.data)
        rows = self._rows(t)
        self.assertEqual([(x.employee_id, x.rating) for x in rows], [(t.emp.id, 4)])

    def test_the_technician_cannot_rate_their_own_job(self):
        t = self._delivered_trip()
        r = t.api.post(f"/api/workforce/jobs/{t.sr.id}/feedback/", {"rating": 5}, format="json")
        self.assertEqual((r.status_code, r.data["code"]), (403, "FEEDBACK_FORBIDDEN"))
        r = t.api.post(f"/api/workforce/technicians/{t.emp.id}/feedback/",
                       {"rating": 5, "booking_id": t.sr.request_id}, format="json")
        self.assertEqual((r.status_code, r.data["code"]), (403, "FEEDBACK_FORBIDDEN"))
        self.assertEqual(self._rows(t), [])

    def test_a_stranger_cannot_rate_someone_elses_job(self):
        from accounts.models import User
        t = self._delivered_trip()
        stranger = User.objects.create(username="stranger", role="customer", company=t.company, password="x")
        api = APIClient()
        api.force_authenticate(user=stranger)
        r = api.post(f"/api/workforce/jobs/{t.sr.id}/feedback/", {"rating": 1}, format="json")
        self.assertEqual(r.status_code, 403)
        self.assertEqual(self._rows(t), [])

    def test_a_trip_that_has_not_been_delivered_cannot_be_rated(self):
        t = Trip(fare={"vehicle_class": "truck"})
        t.sr.assigned_employee = t.emp
        t.sr.save(update_fields=["assigned_employee"])
        api = APIClient()
        api.force_authenticate(user=t.customer)
        r = api.post(f"/api/workforce/jobs/{t.sr.id}/feedback/", {"rating": 5}, format="json")
        self.assertEqual((r.status_code, r.data["code"]), (400, "JOB_NOT_RATEABLE"))

    @override_settings(WORKFORCE_WEBHOOK_SECRET=SECRET)
    def test_customer_app_push_credits_the_assigned_technician_not_the_id_in_the_url(self):
        t = self._delivered_trip()
        decoy = self._decoy_employee(t)
        server = APIClient()
        server.credentials(HTTP_AUTHORIZATION=f"Bearer {SECRET}")
        # The Customer app puts a *job* id in the technician slot; make that number a real,
        # different employee's pk to prove the job decides who is credited.
        r = server.post(
            f"/api/workforce/technicians/{decoy.id}/feedback/",
            {"booking_id": t.sr.request_id, "workforce_job_id": str(t.sr.id), "rating": 3, "comments": "ok"},
            format="json",
        )
        self.assertIn(r.status_code, (200, 201), r.data)
        rows = self._rows(t)
        self.assertEqual([(x.employee_id, x.rating) for x in rows], [(t.emp.id, 3)])
        self.assertNotIn(decoy.id, [x.employee_id for x in rows])

    @override_settings(WORKFORCE_WEBHOOK_SECRET=SECRET)
    def test_a_delivered_but_not_yet_settled_trip_can_already_be_rated(self):
        t = Trip(fare={"vehicle_class": "truck"})
        t.sr.status = "in_progress"
        t.sr.logistics_leg = "DELIVERED"
        t.sr.assigned_employee = t.emp
        t.sr.save(update_fields=["status", "logistics_leg", "assigned_employee"])
        server = APIClient()
        server.credentials(HTTP_AUTHORIZATION=f"Bearer {SECRET}")
        r = server.post(f"/api/workforce/technicians/{t.emp.id}/feedback/",
                        {"booking_id": t.sr.request_id, "rating": 5}, format="json")
        self.assertIn(r.status_code, (200, 201), r.data)
