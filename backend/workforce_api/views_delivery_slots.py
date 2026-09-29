"""
workforce_api/views_delivery_slots.py

Delivery Slots & Capacity Scheduling Admin Management APIs.
Allows Platform Administrators to create, list, update, and manage delivery windows
scoped to fulfillment warehouses with overlap detection and capacity controls.
"""

import logging
from django.db import models
from rest_framework import status, permissions
from rest_framework.views import APIView
from rest_framework.response import Response

from accounts.platform import is_platform_admin_user
from workforce_api.models import Warehouse, DeliverySlot, DeliverySlotBooking
from workforce_api.serializers import DeliverySlotSerializer

logger = logging.getLogger(__name__)


def _parse_days(days_str):
    """
    Parses comma-separated day string into a set of integers (0=Mon..6=Sun).
    Empty string implies all days: {0, 1, 2, 3, 4, 5, 6}.
    """
    if not days_str or not days_str.strip():
        return set(range(7))
    try:
        return {int(d.strip()) for d in days_str.split(",") if d.strip().isdigit()}
    except Exception:
        return set(range(7))


def check_slot_overlap(warehouse_id, start_time, end_time, applicable_days, exclude_slot_id=None):
    """
    Validates whether a candidate slot time window overlaps with any active slot
    on the same warehouse for intersecting calendar days.
    Returns (has_overlap, conflicting_slot).
    """
    candidate_days = _parse_days(applicable_days)

    active_slots = DeliverySlot.objects.filter(
        warehouse_id=warehouse_id,
        is_active=True,
    )
    if exclude_slot_id:
        active_slots = active_slots.exclude(id=exclude_slot_id)

    for slot in active_slots:
        # Time window intersection: start1 < end2 and end1 > start2
        if start_time < slot.end_time and end_time > slot.start_time:
            slot_days = _parse_days(slot.applicable_days)
            if candidate_days & slot_days:
                return True, slot

    return False, None


class AdminDeliverySlotListCreateView(APIView):
    """
    GET  /api/workforce/admin/delivery-slots/ – List delivery slots with warehouse & active status filters
    POST /api/workforce/admin/delivery-slots/ – Create a new delivery slot with overlap validation (Platform Admin only)
    """
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        if not is_platform_admin_user(request.user):
            return Response(
                {"error": "Only platform administrators can manage delivery slots.", "code": "FORBIDDEN"},
                status=status.HTTP_403_FORBIDDEN,
            )

        queryset = DeliverySlot.objects.select_related("warehouse").all()

        warehouse_id = request.query_params.get("warehouse_id", "").strip()
        if warehouse_id and warehouse_id.isdigit():
            queryset = queryset.filter(warehouse_id=int(warehouse_id))

        is_active_param = request.query_params.get("is_active", "").strip().lower()
        if is_active_param in ("true", "1"):
            queryset = queryset.filter(is_active=True)
        elif is_active_param in ("false", "0"):
            queryset = queryset.filter(is_active=False)

        slot_type = request.query_params.get("slot_type", "").strip()
        if slot_type:
            queryset = queryset.filter(slot_type__iexact=slot_type)

        search = request.query_params.get("search", "").strip()
        if search:
            queryset = queryset.filter(
                models.Q(label__icontains=search) |
                models.Q(warehouse__name__icontains=search)
            )

        queryset = queryset.order_by("warehouse__name", "start_time")
        serializer = DeliverySlotSerializer(queryset, many=True)
        return Response(serializer.data, status=status.HTTP_200_OK)

    def post(self, request):
        if not is_platform_admin_user(request.user):
            return Response(
                {"error": "Only platform administrators can create delivery slots.", "code": "FORBIDDEN"},
                status=status.HTTP_403_FORBIDDEN,
            )

        data = request.data.copy() if hasattr(request.data, "copy") else dict(request.data)
        warehouse_id = data.get("warehouse_id") or data.get("warehouse")
        if not warehouse_id:
            return Response(
                {"error": "Warehouse ID is required to create a delivery slot.", "code": "WAREHOUSE_REQUIRED"},
                status=status.HTTP_400_BAD_REQUEST,
            )

        warehouse = Warehouse.objects.filter(pk=warehouse_id).first()
        if not warehouse:
            return Response(
                {"error": f"Warehouse #{warehouse_id} not found.", "code": "WAREHOUSE_NOT_FOUND"},
                status=status.HTTP_404_NOT_FOUND,
            )

        serializer = DeliverySlotSerializer(data=data)
        if not serializer.is_valid():
            return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)

        validated_data = serializer.validated_data
        start_time = validated_data["start_time"]
        end_time = validated_data["end_time"]
        applicable_days = validated_data.get("applicable_days", "")
        is_active = validated_data.get("is_active", True)

        # Overlap check for active slots
        if is_active:
            has_overlap, conflicting_slot = check_slot_overlap(
                warehouse_id=warehouse.id,
                start_time=start_time,
                end_time=end_time,
                applicable_days=applicable_days,
            )
            if has_overlap:
                return Response(
                    {
                        "error": (
                            f"Delivery slot window ({start_time.strftime('%H:%M')} - {end_time.strftime('%H:%M')}) "
                            f"overlaps with existing active slot '{conflicting_slot.label}' "
                            f"({conflicting_slot.start_time.strftime('%H:%M')} - {conflicting_slot.end_time.strftime('%H:%M')}) "
                            f"for warehouse '{warehouse.name}'."
                        ),
                        "code": "SLOT_OVERLAP",
                        "conflicting_slot_id": conflicting_slot.id,
                    },
                    status=status.HTTP_400_BAD_REQUEST,
                )

        slot = serializer.save(warehouse=warehouse)
        return Response(DeliverySlotSerializer(slot).data, status=status.HTTP_201_CREATED)


class AdminDeliverySlotDetailView(APIView):
    """
    GET    /api/workforce/admin/delivery-slots/<int:pk>/ – Get delivery slot details
    PATCH  /api/workforce/admin/delivery-slots/<int:pk>/ – Update delivery slot attributes / toggle active status
    DELETE /api/workforce/admin/delivery-slots/<int:pk>/ – Delete slot (blocked if referenced by bookings)
    """
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request, pk):
        if not is_platform_admin_user(request.user):
            return Response(
                {"error": "Only platform administrators can view delivery slot details.", "code": "FORBIDDEN"},
                status=status.HTTP_403_FORBIDDEN,
            )

        slot = DeliverySlot.objects.select_related("warehouse").filter(pk=pk).first()
        if not slot:
            return Response({"error": "Delivery slot not found.", "code": "NOT_FOUND"}, status=status.HTTP_404_NOT_FOUND)

        return Response(DeliverySlotSerializer(slot).data, status=status.HTTP_200_OK)

    def patch(self, request, pk):
        if not is_platform_admin_user(request.user):
            return Response(
                {"error": "Only platform administrators can modify delivery slots.", "code": "FORBIDDEN"},
                status=status.HTTP_403_FORBIDDEN,
            )

        slot = DeliverySlot.objects.select_related("warehouse").filter(pk=pk).first()
        if not slot:
            return Response({"error": "Delivery slot not found.", "code": "NOT_FOUND"}, status=status.HTTP_404_NOT_FOUND)

        data = request.data.copy() if hasattr(request.data, "copy") else dict(request.data)
        serializer = DeliverySlotSerializer(slot, data=data, partial=True)
        if not serializer.is_valid():
            return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)

        validated_data = serializer.validated_data
        start_time = validated_data.get("start_time", slot.start_time)
        end_time = validated_data.get("end_time", slot.end_time)
        applicable_days = validated_data.get("applicable_days", slot.applicable_days)
        is_active = validated_data.get("is_active", slot.is_active)
        warehouse_id = validated_data.get("warehouse_id", slot.warehouse_id)

        # Re-check overlap if slot is active
        if is_active:
            has_overlap, conflicting_slot = check_slot_overlap(
                warehouse_id=warehouse_id,
                start_time=start_time,
                end_time=end_time,
                applicable_days=applicable_days,
                exclude_slot_id=slot.id,
            )
            if has_overlap:
                return Response(
                    {
                        "error": (
                            f"Delivery slot window ({start_time.strftime('%H:%M')} - {end_time.strftime('%H:%M')}) "
                            f"overlaps with existing active slot '{conflicting_slot.label}' "
                            f"({conflicting_slot.start_time.strftime('%H:%M')} - {conflicting_slot.end_time.strftime('%H:%M')}) "
                            f"for warehouse '{slot.warehouse.name}'."
                        ),
                        "code": "SLOT_OVERLAP",
                        "conflicting_slot_id": conflicting_slot.id,
                    },
                    status=status.HTTP_400_BAD_REQUEST,
                )

        updated_slot = serializer.save()
        return Response(DeliverySlotSerializer(updated_slot).data, status=status.HTTP_200_OK)

    def delete(self, request, pk):
        if not is_platform_admin_user(request.user):
            return Response(
                {"error": "Only platform administrators can delete delivery slots.", "code": "FORBIDDEN"},
                status=status.HTTP_403_FORBIDDEN,
            )

        slot = DeliverySlot.objects.filter(pk=pk).first()
        if not slot:
            return Response({"error": "Delivery slot not found.", "code": "NOT_FOUND"}, status=status.HTTP_404_NOT_FOUND)

        if slot.bookings.exists():
            return Response(
                {
                    "error": "Cannot delete delivery slot because it has existing customer order bookings. Deactivate the slot instead.",
                    "code": "SLOT_HAS_BOOKINGS",
                    "bookings_count": slot.bookings.count(),
                },
                status=status.HTTP_400_BAD_REQUEST,
            )

        slot.delete()
        return Response({"message": "Delivery slot deleted successfully.", "id": pk}, status=status.HTTP_200_OK)
