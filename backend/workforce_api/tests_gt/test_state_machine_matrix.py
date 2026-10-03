"""GT state machine matrix: terminal states are closed, illegal jumps are rejected for non-superusers, and every target is a known state."""
from types import SimpleNamespace

from django.core.exceptions import ValidationError as DjValidationError
from django.test import SimpleTestCase
from rest_framework.exceptions import ValidationError as DrfValidationError

from service_requests.state_machine import ALLOWED_TRANSITIONS, apply_transition, can_transition

TERMINAL = ("completed", "cancelled", "unable_to_complete")
ILLEGAL = [
    ("completed", "assigned"), ("completed", "in_progress"), ("completed", "cancelled"), ("cancelled", "assigned"), ("cancelled", "accepted"),
    ("cancelled", "confirmed"), ("unable_to_complete", "assigned"), ("assigned", "offering"), ("assigned", "completed"), ("accepted", "completed"),
    ("accepted", "confirmed"), ("in_progress", "assigned"), ("in_progress", "completed"), ("on_hold", "proof_submitted"), ("proof_submitted", "in_progress"),
    ("arrived", "accepted"), ("on_the_way", "assigned"), ("unassigned", "completed"), ("confirmed", "completed"), ("confirmed", "in_progress"),
]


class StateMatrixTests(SimpleTestCase):
    def test_terminal_states_have_no_exits(self):
        for s in TERMINAL:
            self.assertEqual(ALLOWED_TRANSITIONS.get(s), [], s)

    def test_every_target_is_a_known_state(self):
        known = set(ALLOWED_TRANSITIONS) | {"customer_rejected"}   # customer_rejected is a quotation dead-end (no exits), not a GT state
        for src, targets in ALLOWED_TRANSITIONS.items():
            for t in targets:
                self.assertIn(t, known, f"{src} -> {t} targets an unknown state")

    def test_illegal_transitions_are_rejected(self):
        for src, dst in ILLEGAL:
            self.assertFalse(can_transition(src, dst), f"{src}->{dst} should be illegal")
            job = SimpleNamespace(status=src, id=1)
            with self.assertRaises((DjValidationError, DrfValidationError), msg=f"{src}->{dst}"):
                apply_transition(job, dst, actor=SimpleNamespace(is_superuser=False))

    def test_same_state_is_a_noop(self):
        job = SimpleNamespace(status="completed", id=1)
        self.assertEqual(apply_transition(job, "completed"), "completed")
