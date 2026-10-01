"""Regression (browser/E2E QA 2026-10-01): a real booking's issue_title is free text
("Mini truck delivery — 3 Wheeler ..."), not a category. get_eligible_candidates retries
check_candidate_eligibility with that title when the category pass fails; the retry used to
skip the logistics vehicle gates, so a two-wheeler driver was OFFERED a 3-wheeler job
(acceptance then 403'd, but the wave slot and the nearest-driver priority were wasted)."""
from workforce_api.services.automatic_dispatch import check_candidate_eligibility, get_eligible_candidates

from .test_realdb_gt_lifecycle import RealDbBase, Trip


class FreeTextTitleCannotBypassVehicleGate(RealDbBase):
    def _trip(self, vehicle_type, capacity, tag, vclass="three_wheeler"):
        t = Trip(vehicle_type=vehicle_type, capacity=capacity, fare={"vehicle_class": vclass}, tag=tag)
        t.sr.issue_title = "Mini truck delivery — 3 Wheeler (500 kg Capacity) (Furnitures)"
        t.sr.save(update_fields=["issue_title"])
        return t

    def test_two_wheeler_not_eligible_via_issue_title_retry(self):
        t = self._trip("two_wheeler", 20, "21")
        ok, reason, _ = check_candidate_eligibility(t.emp, t.sr.issue_title, job=t.sr, purpose="offer_reception")
        self.assertFalse(ok, reason)
        ok, reason, _ = check_candidate_eligibility(t.emp, t.sr.service_category, job=t.sr, purpose="offer_reception")
        self.assertFalse(ok, reason)

    def test_not_in_candidate_list_and_no_offer_created(self):
        from workforce_api.models import WorkforceJobOffer
        t = self._trip("two_wheeler", 20, "22")
        self.assertEqual(get_eligible_candidates(t.sr, rejection_tally={}, radius_km=50), [])
        t.dispatch()
        self.assertFalse(WorkforceJobOffer.objects.filter(job_id=t.sr.id).exists())

    def test_matching_vehicle_still_eligible_with_free_text_title(self):
        t = self._trip("three_wheeler", 500, "23")
        ok, reason, _ = check_candidate_eligibility(t.emp, t.sr.issue_title, job=t.sr, purpose="offer_reception")
        self.assertTrue(ok, reason)
        self.assertTrue(t.dispatch()[0])
