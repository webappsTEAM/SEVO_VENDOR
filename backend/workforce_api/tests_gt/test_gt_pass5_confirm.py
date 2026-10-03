"""GT Pass 5 regression guard (source-level; vendor unit tests here are DB-less SimpleTestCase).
The customer cash CONFIRM view marked the payment PAID but never called apply_transition(job, "completed"), so the job stayed
proof_submitted (wallet never credited) until a replay. Behaviour is covered end-to-end by QA module m_e2e (E2E-01)."""
import inspect
from django.test import SimpleTestCase


class CustomerCashConfirmSourceGuard(SimpleTestCase):
    def test_confirm_view_closes_job(self):
        from workforce_api import views
        src = inspect.getsource(views.WorkforceCustomerPaymentConfirmView)
        a = src.index("is_fully_settled = True")
        b = src.index("Payment Confirmed but Job Did Not Close")
        self.assertIn('apply_transition(job, "completed"', src[a:b])


class BodyObjectGuardSource(SimpleTestCase):
    def test_guards_present(self):
        from workforce_api import views
        for name in ("WorkforceJobTransitionView", "WorkforceJobRejectOfferView"):
            self.assertIn("GT_BODY_OBJECT", inspect.getsource(getattr(views, name)))
