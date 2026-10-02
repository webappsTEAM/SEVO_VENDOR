"""Customer phone/email must not reach a technician before the job is theirs."""
from types import SimpleNamespace
from django.test import SimpleTestCase
from workforce_api.serializers import WorkforceJobSerializer


def _ser(user):
    return WorkforceJobSerializer(context={"request": SimpleNamespace(user=user)})


def _user(emp_id, role="employee"):
    return SimpleNamespace(is_authenticated=True, role=role, is_superuser=False, is_staff=False,
                           employee_profile=SimpleNamespace(id=emp_id))


def _job(assigned):
    return SimpleNamespace(assigned_employee_id=assigned, phone="9876500011", email="c@example.com", customer=None)


class ContactHiddenTests(SimpleTestCase):
    def test_unassigned_job_hides_contact_from_technician(self):
        s = _ser(_user(7)); j = _job(None)
        self.assertEqual(s.get_phone(j), ""); self.assertEqual(s.get_email(j), "")

    def test_other_technicians_job_hides_contact(self):
        s = _ser(_user(7)); j = _job(8)
        self.assertEqual(s.get_phone(j), "")

    def test_assigned_technician_sees_contact(self):
        s = _ser(_user(7)); j = _job(7)
        self.assertEqual(s.get_phone(j), "9876500011"); self.assertEqual(s.get_email(j), "c@example.com")

    def test_vendor_admin_unaffected(self):
        s = _ser(_user(7, role="vendor")); j = _job(None)
        self.assertEqual(s.get_phone(j), "9876500011")
