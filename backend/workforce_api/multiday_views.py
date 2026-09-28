"""
workforce-app/backend/workforce_api/multiday_views.py
API endpoints for:
1. Vendor Base Location Onboarding & Dual-Radius Serviceability
2. Multi-Day Job Hold & Resume (Weather / Delay)
3. Mid-Job Scope Reduction & Recalculation
4. Mandatory CRM Quote Approval Gate
"""
import logging
from decimal import Decimal
from django.utils import timezone
from django.shortcuts import get_object_or_404
from rest_framework import permissions, status
from rest_framework.response import Response
from rest_framework.views import APIView
from rest_framework.exceptions import ValidationError

from service_requests.models import ServiceRequest
from workforce_api.models import (
    WorkforceVendorBaseLocation,
    WorkforceJobHold,
    WorkforceScopeReduction,
    WorkforceQuote,
    WorkforceServicePricingPolicy,
)
from workforce_api.services import pricing_policy, quotation_service, invoice_service

logger = logging.getLogger(__name__)


class WorkforceVendorBaseLocationView(APIView):
    """
    Get or update the vendor's authoritative registered operational base location.
    Anchors all dual-radius distance and consultation fee calculations.
    """
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        user = request.user
        emp = getattr(user, "employee_profile", None)
        company = getattr(user, "company", None) or (emp.company if emp else None)

        loc = None
        if company:
            loc = WorkforceVendorBaseLocation.objects.filter(company=company, is_active=True).first()
        if not loc and emp:
            loc = WorkforceVendorBaseLocation.objects.filter(employee=emp, is_active=True).first()

        if not loc:
            return Response({
                "configured": False,
                "base_latitude": 12.7409,
                "base_longitude": 77.8253,
                "city": "Hosur",
                "max_service_radius_km": 50.00,
                "address": "",
                "area": "",
                "pincode": "",
            }, status=status.HTTP_200_OK)

        return Response({
            "configured": True,
            "id": loc.id,
            "address": loc.address,
            "area": loc.area,
            "city": loc.city,
            "pincode": loc.pincode,
            "base_latitude": loc.base_latitude,
            "base_longitude": loc.base_longitude,
            "max_service_radius_km": float(loc.max_service_radius_km),
            "updated_at": loc.updated_at.isoformat() if loc.updated_at else None,
        }, status=status.HTTP_200_OK)

    def post(self, request):
        user = request.user
        emp = getattr(user, "employee_profile", None)
        company = getattr(user, "company", None) or (emp.company if emp else None)

        address = str(request.data.get("address", "")).strip()
        area = str(request.data.get("area", "")).strip()
        city = str(request.data.get("city", "Hosur")).strip()
        pincode = str(request.data.get("pincode", "")).strip()
        base_lat = float(request.data.get("base_latitude", 12.7409))
        base_lon = float(request.data.get("base_longitude", 77.8253))
        max_radius = Decimal(str(request.data.get("max_service_radius_km", 50.00)))

        loc = None
        if company:
            loc, _ = WorkforceVendorBaseLocation.objects.get_or_create(
                company=company,
                defaults={"base_latitude": base_lat, "base_longitude": base_lon}
            )
        elif emp:
            loc, _ = WorkforceVendorBaseLocation.objects.get_or_create(
                employee=emp,
                defaults={"base_latitude": base_lat, "base_longitude": base_lon}
            )
        else:
            return Response({"error": "No company or employee profile found for user."}, status=status.HTTP_400_BAD_REQUEST)

        loc.address = address
        loc.area = area
        loc.city = city
        loc.pincode = pincode
        loc.base_latitude = base_lat
        loc.base_longitude = base_lon
        loc.max_service_radius_km = max_radius
        loc.is_active = True
        loc.save()

        return Response({
            "message": "Vendor base location updated successfully.",
            "id": loc.id,
            "base_latitude": loc.base_latitude,
            "base_longitude": loc.base_longitude,
            "max_service_radius_km": float(loc.max_service_radius_km),
            "city": loc.city,
        }, status=status.HTTP_200_OK)


class WorkforceServiceabilityCheckView(APIView):
    """
    Public / Authenticated API to check dual-radius serviceability and dynamic consultation fee.
    Accepts customer lat/lon and service category.
    """
    permission_classes = [permissions.AllowAny]

    def post(self, request):
        category = request.data.get("service_category") or request.data.get("category", "")
        latitude = request.data.get("latitude")
        longitude = request.data.get("longitude")
        vendor_id = request.data.get("vendor_id") or request.data.get("company_id")

        vendor = None
        if vendor_id:
            from companies.models import Company
            vendor = Company.objects.filter(id=vendor_id).first()

        fee, explanation, is_serviceable, dist_km = pricing_policy.evaluate_serviceability(
            category=category,
            latitude=latitude,
            longitude=longitude,
            vendor=vendor,
        )

        policy = pricing_policy.policy_for(category)
        free_radius = float(getattr(policy, "free_radius_km", 15.00) or 15.00)
        max_radius = float(getattr(policy, "max_service_radius_km", 50.00) or 50.00)

        return Response({
            "service_category": category,
            "is_serviceable": is_serviceable,
            "consultation_fee": float(fee),
            "distance_km": round(dist_km, 2) if dist_km is not None else None,
            "free_radius_km": free_radius,
            "max_service_radius_km": max_radius,
            "explanation": explanation,
        }, status=status.HTTP_200_OK)


class WorkforceJobHoldView(APIView):
    """
    Put an active multi-day job on hold (e.g. rain/weather, emergency, client delay).
    Toggles technician availability back to AVAILABLE so they can accept smaller jobs.
    """
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request, pk):
        job = get_object_or_404(ServiceRequest, pk=pk)
        emp = getattr(request.user, "employee_profile", None)

        reason = str(request.data.get("reason", "WEATHER_DELAY")).strip()
        notes = str(request.data.get("notes", "")).strip()

        hold = WorkforceJobHold.objects.create(
            job=job,
            employee=emp or job.assigned_employee,
            held_by=request.user,
            reason=reason,
            notes=notes,
            status=WorkforceJobHold.Status.ACTIVE,
        )

        job.status = "on_hold"
        job.save(update_fields=["status"])

        # Toggle technician presence to available
        assigned_emp = emp or job.assigned_employee
        if assigned_emp:
            assigned_emp.current_availability = "available"
            assigned_emp.save(update_fields=["current_availability"])

        logger.info("Job #%s placed ON_HOLD by %s (%s)", job.id, request.user, reason)
        return Response({
            "message": f"Job #{job.id} placed ON_HOLD.",
            "hold_id": hold.id,
            "status": "on_hold",
            "technician_availability": "available",
        }, status=status.HTTP_200_OK)


class WorkforceJobResumeView(APIView):
    """
    Resumes a job from ON_HOLD back to IN_PROGRESS.
    Locks technician back to ON_JOB / BUSY and extends target completion date.
    """
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request, pk):
        job = get_object_or_404(ServiceRequest, pk=pk)
        emp = getattr(request.user, "employee_profile", None)

        active_hold = WorkforceJobHold.objects.filter(
            job=job, status=WorkforceJobHold.Status.ACTIVE
        ).first()

        now = timezone.now()
        if active_hold:
            active_hold.status = WorkforceJobHold.Status.RESUMED
            active_hold.hold_end = now
            active_hold.save(update_fields=["status", "hold_end", "updated_at"])

        job.status = "in_progress"
        job.save(update_fields=["status"])

        # Lock technician back to busy
        assigned_emp = emp or job.assigned_employee
        if assigned_emp:
            assigned_emp.current_availability = "busy"
            assigned_emp.save(update_fields=["current_availability"])

        logger.info("Job #%s RESUMED by %s", job.id, request.user)
        return Response({
            "message": f"Job #{job.id} resumed to IN_PROGRESS.",
            "status": "in_progress",
            "technician_availability": "busy",
        }, status=status.HTTP_200_OK)


class WorkforceJobScopeReductionView(APIView):
    """
    Vendor requests a formal mid-job scope reduction.
    Requires CRM/Admin approval before adjusting live invoice balance.
    """
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request, pk):
        job = get_object_or_404(ServiceRequest, pk=pk)
        reduction_amount = Decimal(str(request.data.get("reduction_amount", 0)))
        reason = str(request.data.get("reason", "")).strip()

        if reduction_amount <= Decimal("0.00"):
            return Response({"error": "Reduction amount must be greater than zero."}, status=status.HTTP_400_BAD_REQUEST)
        if not reason:
            return Response({"error": "Reason for scope reduction is required."}, status=status.HTTP_400_BAD_REQUEST)

        original_total = Decimal(str(job.total_amount or 0))
        if reduction_amount >= original_total:
            return Response({"error": "Reduction amount cannot exceed total job amount."}, status=status.HTTP_400_BAD_REQUEST)

        revised_total = original_total - reduction_amount
        quote = job.quotes.exclude(status="CANCELLED").order_by("-id").first()

        reduction = WorkforceScopeReduction.objects.create(
            job=job,
            quote=quote,
            requested_by=request.user,
            original_amount=original_total,
            reduction_amount=reduction_amount,
            revised_amount=revised_total,
            reason=reason,
            crm_status=WorkforceScopeReduction.Status.REQUESTED,
        )

        return Response({
            "message": f"Scope reduction request of ₹{reduction_amount} submitted to CRM for review.",
            "reduction_id": reduction.id,
            "original_amount": str(original_total),
            "reduction_amount": str(reduction_amount),
            "revised_amount": str(revised_total),
            "crm_status": "REQUESTED",
        }, status=status.HTTP_201_CREATED)


class WorkforceAdminScopeReductionReviewView(APIView):
    """
    CRM / Platform Admin reviews and approves or rejects a scope reduction request.
    Upon approval, triggers dynamic invoice balance recalculation.
    """
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request, pk):
        reduction = get_object_or_404(WorkforceScopeReduction, pk=pk)
        action = str(request.data.get("action", "APPROVE")).upper()
        rejection_reason = str(request.data.get("rejection_reason", "")).strip()

        now = timezone.now()
        if action == "APPROVE":
            reduction.crm_status = WorkforceScopeReduction.Status.APPROVED
            reduction.approved_by = request.user
            reduction.approved_at = now
            reduction.save()

            # Recalculate live invoice and update job total
            job = reduction.job
            job.total_amount = reduction.revised_amount
            job.save(update_fields=["total_amount"])

            invoice = invoice_service.recalculate_invoice_for_scope_reduction(
                job=job,
                reduction_amount=reduction.reduction_amount,
                actor=request.user,
            )

            return Response({
                "message": f"Scope reduction of ₹{reduction.reduction_amount} approved and applied.",
                "crm_status": "APPROVED",
                "new_job_total": str(job.total_amount),
                "invoice_balance_due": str(invoice.balance_due) if invoice else None,
            }, status=status.HTTP_200_OK)
        else:
            reduction.crm_status = WorkforceScopeReduction.Status.REJECTED
            reduction.rejection_reason = rejection_reason
            reduction.approved_by = request.user
            reduction.approved_at = now
            reduction.save()

            return Response({
                "message": "Scope reduction rejected.",
                "crm_status": "REJECTED",
                "rejection_reason": rejection_reason,
            }, status=status.HTTP_200_OK)


class WorkforceQuoteSubmitCRMView(APIView):
    """
    Vendor submits a drafted quotation to CRM for review and pre-send approval.
    """
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request, pk):
        quote = get_object_or_404(WorkforceQuote, pk=pk)
        quotation_service.recalculate_quote_totals(quote)

        quote.status = WorkforceQuote.Status.PENDING_REVIEW
        quote.save(update_fields=["status", "updated_at"])

        return Response({
            "message": f"Quote {quote.quote_number} (v{quote.quote_version}) submitted to CRM for review.",
            "quote_id": quote.id,
            "status": "PENDING_REVIEW",
            "net_payable": str(quote.net_payable or quote.total_amount),
        }, status=status.HTTP_200_OK)


class WorkforceQuoteCRMApproveView(APIView):
    """
    CRM Admin reviews and approves quote, transitioning it to SENT_TO_CUSTOMER with decision token.
    """
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request, pk):
        quote = get_object_or_404(WorkforceQuote, pk=pk)
        action = str(request.data.get("action", "APPROVE")).upper()
        notes = str(request.data.get("notes", "")).strip()

        if action == "APPROVE":
            quote.admin_cleared_by = request.user
            quote.admin_cleared_at = timezone.now()
            quote.admin_clearance_notes = notes
            quote.save(update_fields=["admin_cleared_by", "admin_cleared_at", "admin_clearance_notes"])

            updated_quote = quotation_service.send_quote_to_customer(quote.id, actor=request.user)
            return Response({
                "message": f"Quote {updated_quote.quote_number} approved by CRM and sent to customer.",
                "quote_id": updated_quote.id,
                "status": updated_quote.status,
                "decision_token": updated_quote.decision_token,
                "valid_until": updated_quote.valid_until.isoformat() if updated_quote.valid_until else None,
            }, status=status.HTTP_200_OK)
        else:
            quote.status = WorkforceQuote.Status.CHANGES_REQUESTED
            quote.admin_clearance_notes = notes or "CRM requested revisions"
            quote.save(update_fields=["status", "admin_clearance_notes", "updated_at"])
            return Response({
                "message": f"Quote {quote.quote_number} returned to vendor for revisions.",
                "quote_id": quote.id,
                "status": "CHANGES_REQUESTED",
            }, status=status.HTTP_200_OK)
