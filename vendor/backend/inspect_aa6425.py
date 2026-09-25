import os
import sys
import django
import json

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "workforce_core.settings")
django.setup()

from django.utils import timezone
from service_requests.models import ServiceRequest
from workforce_api.models import (
    WorkforceDispatchState,
    WorkforceJobOffer,
    WorkforceEventLog,
    WorkforceJobLifecycleEvent,
)
from workforce_api.services.automatic_dispatch import (
    get_scheduled_dispatch_window,
    DISPATCHABLE_STATUSES,
    check_candidate_eligibility,
    get_eligible_candidates,
)
from employees.models import Employee

def inspect():
    print("=== INSPECTING BOOKING #AA6425 ===")
    
    # 1. Look up ServiceRequest
    sr = ServiceRequest.objects.filter(models.Q(request_id__icontains="6425") | models.Q(id=6425)).first()
    if not sr:
        # Check by query
        srs = list(ServiceRequest.objects.filter(request_id__icontains="6425"))
        print("Matches by request_id contains 6425:", srs)
        sr = ServiceRequest.objects.order_by("-id").first()
        print("Latest ServiceRequest in DB:", sr.id, sr.request_id, sr.issue_title, sr.created_at)
        return

    print(f"ServiceRequest ID: {sr.id}")
    print(f"Request ID: {sr.request_id}")
    print(f"Status: {sr.status}")
    print(f"Company: {sr.company_id} ({sr.company})")
    print(f"Vendor ID: {sr.vendor_id}")
    print(f"Service Category: '{sr.service_category}'")
    print(f"Issue Title: '{sr.issue_title}'")
    print(f"Preferred Date: {sr.preferred_date}")
    print(f"Preferred Time: '{sr.preferred_time}'")
    print(f"Coordinates: lat={sr.latitude}, lon={sr.longitude}")
    print(f"Address: {sr.address}")
    print(f"Created At: {sr.created_at}")
    print(f"Updated At: {sr.updated_at}")
    
    # 2. Check dispatchability
    print("\n--- DISPATCHABILITY CHECK ---")
    print(f"Is status in DISPATCHABLE_STATUSES ({DISPATCHABLE_STATUSES})? {sr.status in DISPATCHABLE_STATUSES}")
    print(f"Has assigned employee? {sr.assigned_employee_id}")
    print(f"Has coords? lat={bool(sr.latitude)}, lon={bool(sr.longitude)}")
    
    # 3. Check Scheduled Window
    now = timezone.now()
    today = timezone.localdate()
    win = get_scheduled_dispatch_window(sr, now=now)
    print(f"Current server time (UTC): {now}")
    print(f"Current local date: {today}")
    print(f"Window is_future (held): {win.is_future}")
    print(f"Window is_eligible: {win.is_eligible}")
    print(f"Window is_closed: {win.is_closed}")
    print(f"Window scheduled_dt: {win.scheduled_dt}")
    print(f"Window window_open: {win.window_open}")
    print(f"Window window_close: {win.window_close}")
    
    # 4. Check WorkforceDispatchState
    print("\n--- WORKFORCE DISPATCH STATE ---")
    state = WorkforceDispatchState.objects.filter(job_id=sr.id).first()
    if state:
        print(f"Dispatch Status: {state.dispatch_status}")
        print(f"Attempt Count: {state.attempt_count}")
        print(f"Last Attempt At: {state.last_attempt_at}")
        print(f"Retry At: {state.retry_at}")
        print(f"Locked At: {state.locked_at}")
        print(f"Unassigned Reason Code: {state.unassigned_reason_code}")
        print(f"Unassigned Reason Message: {state.unassigned_reason_message}")
        print(f"Updated At: {state.updated_at}")
    else:
        print("No WorkforceDispatchState row exists for this job!")
        
    # 5. Check Lifecycle Events
    print("\n--- EVENT LOGS / JOURNEY ---")
    events = WorkforceEventLog.objects.filter(
        models.Q(payload__job_id=sr.id) | models.Q(payload__job_id=str(sr.id))
    ).order_by("created_at")
    print(f"Found {events.count()} WorkforceEventLog events:")
    for e in events:
        print(f"  [{e.created_at}] {e.event_type}: {e.payload}")
        
    lifecycle_events = WorkforceJobLifecycleEvent.objects.filter(job_id=sr.id).order_by("created_at")
    print(f"Found {lifecycle_events.count()} WorkforceJobLifecycleEvent events:")
    for le in lifecycle_events:
        print(f"  [{le.created_at}] {le.event_type}: {le.reason_code} - {le.reason_text}")

    # 6. Check Offers
    print("\n--- JOB OFFERS ---")
    offers = WorkforceJobOffer.objects.filter(job_id=sr.id).order_by("offered_at")
    print(f"Found {offers.count()} WorkforceJobOffer rows:")
    for o in offers:
        print(f"  Offer #{o.id}: Employee #{o.employee_id} ({o.employee}), Status={o.status}, RankScore={o.rank_score}, Expiry={o.expires_at}")

    # 7. Check Eligible Technicians in DB
    print("\n--- TECHNICIAN ELIGIBILITY DRY-RUN ---")
    candidates = get_eligible_candidates(sr, max_gps_age_seconds=86400, radius_km=50.0)
    print(f"Found {len(candidates)} candidates via get_eligible_candidates:")
    for idx, c in enumerate(candidates):
        emp = c.get("employee")
        print(f"  Candidate #{idx+1}: Tech #{emp.id} ({emp.user.username}), Distance={c.get('distance_km')}km, Score={c.get('score')}")

    # Check all active/online employees in this company or platform
    print("\n--- ALL EMPLOYEES AUDIT ---")
    emps = Employee.objects.filter(is_active=True).select_related("user", "company")
    print(f"Total active employees in DB: {emps.count()}")
    for emp in emps:
        is_el, reason, details = check_candidate_eligibility(emp, sr.service_category or sr.issue_title, sr)
        print(f"  Tech #{emp.id} ({emp.user.username}, Co: {emp.company_id}): is_online={emp.is_online}, avail={emp.current_availability}, is_eligible={is_el}, reason={reason}")

if __name__ == "__main__":
    from django.db import models
    inspect()
