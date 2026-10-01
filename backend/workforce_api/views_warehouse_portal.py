"""
workforce_api/views_warehouse_portal.py

Dedicated Warehouse Operations Portal Views (Phase V).
Provides scoped APIs for warehouse staff to view their facility profile, orders, and stats.
Strictly isolates data by warehouse_id resolved server-side from the authenticated user's WarehouseStaff profile.
"""
import logging
from decimal import Decimal
from django.db import models, transaction
from django.utils import timezone
from rest_framework import permissions, status
from rest_framework.response import Response
from rest_framework.views import APIView
from rest_framework.pagination import PageNumberPagination

from .models import (
    Warehouse,
    WarehouseStaff,
    SellerOrder,
    SellerOrderAuditLog,
    SellerProduct,
    SellerInventory,
    SellerInventoryBatch,
    SellerInventoryMovement,
    WarehouseInboundRequest,
    WarehouseInboundRequestAuditLog,
    WarehouseInboundUnit,
    WarehouseReturn,
)
from .serializers import (
    WarehouseDetailSerializer,
    WarehouseSerializer,
    SellerOrderListSerializer,
    SellerOrderDetailSerializer,
    SellerOrderStatusTransitionSerializer,
    WarehouseInboundRequestSerializer,
    WarehouseInboundUnitSerializer,
    WarehouseReturnSerializer,
)
from workforce_api.services.seller_order_outbox import record_seller_order_status_event

logger = logging.getLogger(__name__)


def _resolve_warehouse_for_request(request):
    """
    Authoritatively resolves the Warehouse instance for the authenticated request.
    Warehouse operators are strictly scoped to their assigned WarehouseStaff facility.
    Platform admins can optionally override via ?warehouse_id= query param for administration.
    Returns (warehouse, error_response) tuple.
    """
    user = request.user
    if not user or not user.is_authenticated:
        return None, Response(
            {"error": "Authentication required.", "code": "UNAUTHENTICATED"},
            status=status.HTTP_401_UNAUTHORIZED,
        )

    # Check if user has a WarehouseStaff profile
    staff = WarehouseStaff.objects.select_related("warehouse").filter(user=user).first()
    if staff and staff.warehouse and staff.warehouse.is_active:
        return staff.warehouse, None

    # Platform Admins / Superadmins can view warehouse portal for any warehouse
    from accounts.platform import is_platform_admin_user
    if is_platform_admin_user(user) or getattr(user, "is_superuser", False):
        wh_id = request.query_params.get("warehouse_id")
        if wh_id:
            wh = Warehouse.objects.filter(id=wh_id).first()
            if wh:
                return wh, None
        # Default to first active warehouse for admin preview
        wh = Warehouse.objects.filter(is_active=True).first()
        if wh:
            return wh, None
        return None, Response(
            {"error": "No warehouse facility found.", "code": "NO_WAREHOUSE"},
            status=status.HTTP_404_NOT_FOUND,
        )

    return None, Response(
        {"error": "You do not have access to the warehouse operations portal.", "code": "FORBIDDEN_NOT_WAREHOUSE_STAFF"},
        status=status.HTTP_403_FORBIDDEN,
    )


class WarehousePortalProfileView(APIView):
    """
    GET   /api/workforce/warehouse/profile/ – Retrieve profile of current logged-in warehouse.
    PATCH /api/workforce/warehouse/profile/ – Update warehouse details (e.g. contact phone).
    """
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        warehouse, err_resp = _resolve_warehouse_for_request(request)
        if err_resp:
            return err_resp

        # Prefetch related assignments & staff
        wh = Warehouse.objects.prefetch_related(
            "staff_members", "staff_members__user", "seller_assignments", "seller_assignments__company"
        ).annotate(
            assigned_sellers_count_annotated=models.Count("seller_assignments", distinct=True)
        ).filter(id=warehouse.id).first()

        serializer = WarehouseDetailSerializer(wh or warehouse)
        return Response(serializer.data, status=status.HTTP_200_OK)

    def patch(self, request, pk=None):
        warehouse, err_resp = _resolve_warehouse_for_request(request)
        if err_resp:
            return err_resp

        allowed_fields = {"contact_phone", "address", "city", "region"}
        update_data = {k: v for k, v in request.data.items() if k in allowed_fields}

        for k, v in update_data.items():
            setattr(warehouse, k, str(v).strip())

        warehouse.save()
        wh = Warehouse.objects.prefetch_related(
            "staff_members", "staff_members__user", "seller_assignments", "seller_assignments__company"
        ).annotate(
            assigned_sellers_count_annotated=models.Count("seller_assignments", distinct=True)
        ).filter(id=warehouse.id).first()

        return Response(WarehouseDetailSerializer(wh or warehouse).data, status=status.HTTP_200_OK)


class WarehousePortalStatsView(APIView):
    """
    GET /api/workforce/warehouse/stats/ – Overview KPI metrics for the warehouse dashboard.
    """
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        warehouse, err_resp = _resolve_warehouse_for_request(request)
        if err_resp:
            return err_resp

        today_start = timezone.now().replace(hour=0, minute=0, second=0, microsecond=0)
        qs = SellerOrder.objects.filter(warehouse_id=warehouse.id)

        total_orders = qs.count()
        today_orders = qs.filter(created_at__gte=today_start).count()
        ready_for_pickup = qs.filter(status__in=[
            SellerOrder.Status.READY_FOR_PICKUP,
            SellerOrder.Status.PACKED,
            SellerOrder.Status.ASSIGNED,
        ]).count()
        in_preparation = qs.filter(status__in=[
            SellerOrder.Status.NEW,
            SellerOrder.Status.ACCEPTED,
            SellerOrder.Status.PICKING,
        ]).count()
        dispatched_today = qs.filter(
            status__in=[SellerOrder.Status.HANDED_OVER, SellerOrder.Status.DELIVERED],
            handed_over_at__gte=today_start,
        ).count()
        completed_total = qs.filter(status=SellerOrder.Status.DELIVERED).count()
        active_sellers_count = warehouse.seller_assignments.count()

        return Response({
            "warehouse_id": warehouse.id,
            "warehouse_name": warehouse.name,
            "warehouse_code": warehouse.code or f"WH-{warehouse.id}",
            "city": warehouse.city,
            "is_active": warehouse.is_active,
            "total_orders": total_orders,
            "today_orders": today_orders,
            "ready_for_pickup": ready_for_pickup,
            "in_preparation": in_preparation,
            "dispatched_today": dispatched_today,
            "completed_total": completed_total,
            "active_sellers_count": active_sellers_count,
        }, status=status.HTTP_200_OK)


class WarehousePortalOrdersPagination(PageNumberPagination):
    page_size = 25
    page_size_query_param = "page_size"
    max_page_size = 100


class WarehousePortalOrdersListView(APIView):
    """
    GET /api/workforce/warehouse/orders/ – Orders list strictly scoped to the logged-in warehouse.
    Supports filtering by status, search, and date.
    """
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        warehouse, err_resp = _resolve_warehouse_for_request(request)
        if err_resp:
            return err_resp

        queryset = SellerOrder.objects.filter(
            warehouse_id=warehouse.id
        ).select_related("company").prefetch_related("items", "items__product").order_by("-id")

        # Status filter
        status_filter = request.query_params.get("status", "").strip().upper()
        if status_filter and status_filter != "ALL":
            if status_filter == "IN_PREPARATION":
                queryset = queryset.filter(
                    status__in=[
                        SellerOrder.Status.NEW,
                        SellerOrder.Status.ACCEPTED,
                        SellerOrder.Status.PICKING,
                        SellerOrder.Status.PACKED,
                    ]
                )
            elif status_filter == "READY_FOR_PICKUP":
                queryset = queryset.filter(
                    status__in=[
                        SellerOrder.Status.READY_FOR_PICKUP,
                        SellerOrder.Status.ASSIGNED,
                    ]
                )
            elif status_filter == "COMPLETED":
                queryset = queryset.filter(
                    status__in=[
                        SellerOrder.Status.HANDED_OVER,
                        SellerOrder.Status.DELIVERED,
                    ]
                )
            elif status_filter in SellerOrder.Status.values:
                queryset = queryset.filter(status=status_filter)

        # Search filter
        search = request.query_params.get("search", "").strip()
        if search:
            queryset = queryset.filter(
                models.Q(order_number__icontains=search) |
                models.Q(source_order_id__icontains=search) |
                models.Q(delivery_group_id__icontains=search) |
                models.Q(customer_name__icontains=search) |
                models.Q(customer_phone__icontains=search) |
                models.Q(company__company_name__icontains=search)
            )

        # Date filter (e.g. today, last 7 days)
        date_param = request.query_params.get("date", "").strip().lower()
        if date_param == "today":
            today_start = timezone.now().replace(hour=0, minute=0, second=0, microsecond=0)
            queryset = queryset.filter(created_at__gte=today_start)

        paginator = WarehousePortalOrdersPagination()
        page = paginator.paginate_queryset(queryset, request)
        if page is not None:
            serializer = SellerOrderListSerializer(page, many=True)
            return paginator.get_paginated_response(serializer.data)

        serializer = SellerOrderListSerializer(queryset, many=True)
        return Response({"count": len(serializer.data), "results": serializer.data}, status=status.HTTP_200_OK)


class WarehousePortalOrderDetailView(APIView):
    """
    GET /api/workforce/warehouse/orders/<int:order_id>/ – Single order details strictly scoped to warehouse.
    """
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request, order_id):
        warehouse, err_resp = _resolve_warehouse_for_request(request)
        if err_resp:
            return err_resp

        order = SellerOrder.objects.filter(
            id=order_id,
            warehouse_id=warehouse.id
        ).select_related("company").prefetch_related("items", "items__product").first()

        if not order:
            return Response(
                {"error": "Order not found or does not belong to your warehouse.", "code": "ORDER_NOT_FOUND"},
                status=status.HTTP_404_NOT_FOUND,
            )

        serializer = SellerOrderDetailSerializer(order)
        return Response(serializer.data, status=status.HTTP_200_OK)


class WarehousePortalOrderStatusTransitionView(APIView):
    """
    POST /api/workforce/warehouse/orders/<int:order_id>/transition/ – Advance or Cancel order state from Warehouse Portal.
    Executes atomic state changes and inventory adjustments with row-locking strictly scoped to the assigned warehouse facility.
    """
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request, order_id):
        warehouse, err_resp = _resolve_warehouse_for_request(request)
        if err_resp:
            return err_resp

        user = request.user

        serializer = SellerOrderStatusTransitionSerializer(data=request.data)
        if not serializer.is_valid():
            return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)

        action = serializer.validated_data["action"]
        notes = serializer.validated_data.get("notes", "").strip()
        cancellation_reason = serializer.validated_data.get("cancellation_reason", "").strip()
        handover_ref = serializer.validated_data.get("handover_ref", "").strip()

        # Block manual handover/deliver for non-superusers (enforce 2-step OTP checkpoint flow)
        if action in ("handover", "deliver") and not getattr(user, "is_superuser", False):
            return Response(
                {
                    "error": "Manual handover and delivery actions are disabled. Orders must be verified by the assigned 2-wheeler rider using Pickup and Delivery OTP verification checkpoints.",
                    "code": "MANUAL_HANDOVER_DISABLED",
                    "action": action,
                },
                status=status.HTTP_400_BAD_REQUEST,
            )

        # Action to Target Status Mapping
        ACTION_TARGET_STATUS = {
            "accept": SellerOrder.Status.ACCEPTED,
            "start_picking": SellerOrder.Status.PICKING,
            "mark_packed": SellerOrder.Status.PACKED,
            "mark_ready": SellerOrder.Status.READY_FOR_PICKUP,
            "handover": SellerOrder.Status.HANDED_OVER,
            "deliver": SellerOrder.Status.DELIVERED,
            "cancel": SellerOrder.Status.CANCELLED,
        }

        target_status = ACTION_TARGET_STATUS.get(action)
        if not target_status:
            return Response({"error": f"Unknown transition action '{action}'."}, status=status.HTTP_400_BAD_REQUEST)

        with transaction.atomic():
            order = (
                SellerOrder.objects.select_for_update()
                .filter(pk=order_id, warehouse_id=warehouse.id)
                .first()
            )
            if not order:
                return Response(
                    {"error": "Order not found or does not belong to your warehouse facility.", "code": "ORDER_NOT_FOUND"},
                    status=status.HTTP_404_NOT_FOUND,
                )

            from_status = order.status

            # Validate State Machine Transition
            if not order.can_transition_to(target_status):
                return Response(
                    {
                        "error": f"Invalid state transition from '{from_status}' to '{target_status}'.",
                        "current_status": from_status,
                        "allowed_transitions": order.ALLOWED_TRANSITIONS.get(from_status, []),
                    },
                    status=status.HTTP_400_BAD_REQUEST,
                )

            now = timezone.now()

            # Handle status timestamps & state-specific logic
            if target_status == SellerOrder.Status.ACCEPTED:
                order.accepted_at = now
            elif target_status == SellerOrder.Status.PICKING:
                order.picking_at = now
            elif target_status == SellerOrder.Status.PACKED:
                order.packed_at = now
            elif target_status == SellerOrder.Status.READY_FOR_PICKUP:
                if warehouse.latitude is None or warehouse.longitude is None:
                    return Response(
                        {
                            "error": "Warehouse facility coordinates are missing. Please configure warehouse latitude and longitude before dispatching rider.",
                            "code": "WAREHOUSE_COORDINATES_MISSING",
                        },
                        status=status.HTTP_400_BAD_REQUEST,
                    )

                pickup_lat = warehouse.latitude
                pickup_lon = warehouse.longitude
                pickup_addr = warehouse.address or f"Warehouse: {warehouse.name}"

                order.ready_at = now

                # Delivery Group handling: Wait for all active sibling sub-orders before creating 1 consolidated dispatch job
                if order.delivery_group_id:
                    group_orders = list(
                        SellerOrder.objects.filter(
                            delivery_group_id=order.delivery_group_id
                        ).exclude(status=SellerOrder.Status.CANCELLED)
                    )

                    not_ready = [
                        o for o in group_orders
                        if o.id != order.id and o.status not in [
                            SellerOrder.Status.READY_FOR_PICKUP,
                            SellerOrder.Status.ASSIGNED,
                            SellerOrder.Status.HANDED_OVER,
                            SellerOrder.Status.DELIVERED,
                        ]
                    ]

                    if not_ready:
                        if not notes:
                            notes = f"Order ready for pickup. Waiting for {len(not_ready)} sibling seller order(s) in delivery group before dispatching rider."
                    else:
                        existing_sr = None
                        for o in group_orders:
                            if o.dispatch_job:
                                existing_sr = o.dispatch_job
                                break

                        if not existing_sr:
                            from service_requests.models import ServiceRequest
                            from workforce_api.services.automatic_dispatch import dispatch_job

                            total_group_amount = sum((o.total_amount for o in group_orders), Decimal("0.00"))
                            all_order_numbers = ", ".join(o.order_number for o in group_orders)
                            all_sellers = ", ".join(sorted(set(getattr(o.company, "company_name", f"Seller #{o.company_id}") for o in group_orders if o.company_id)))

                            sr = ServiceRequest.objects.create(
                                company=order.company,
                                service_category="goods_transport_two_wheeler",
                                job_type="DELIVERY",
                                request_kind=ServiceRequest.RequestKind.DIRECT,
                                customer_name=order.customer_name,
                                phone=order.customer_phone,
                                address=pickup_addr,
                                latitude=pickup_lat,
                                longitude=pickup_lon,
                                drop_address=order.delivery_address,
                                drop_contact_name=order.customer_name,
                                preferred_date=now.date(),
                                preferred_time="Immediate",
                                issue_title=f"Consolidated Delivery ({len(group_orders)} sub-orders): {all_order_numbers}",
                                description=f"Consolidated Warehouse Delivery for {order.customer_name} from {all_sellers}. Orders: {all_order_numbers}. Total: ₹{total_group_amount}",
                                total_amount=total_group_amount,
                                status="new_request",
                            )
                            for o in group_orders:
                                o.dispatch_job = sr
                                o.save(update_fields=["dispatch_job", "updated_at"])
                            order.dispatch_job = sr
                            dispatch_job(sr)
                        else:
                            order.dispatch_job = existing_sr
                            from workforce_api.services.automatic_dispatch import dispatch_job
                            if existing_sr.status in ["unassigned", "redispatching", "new_request"]:
                                dispatch_job(existing_sr)
                else:
                    # Single standalone order dispatch
                    if not order.dispatch_job:
                        from service_requests.models import ServiceRequest
                        from workforce_api.services.automatic_dispatch import dispatch_job

                        sr = ServiceRequest.objects.create(
                            company=order.company,
                            service_category="goods_transport_two_wheeler",
                            job_type="DELIVERY",
                            request_kind=ServiceRequest.RequestKind.DIRECT,
                            customer_name=order.customer_name,
                            phone=order.customer_phone,
                            address=pickup_addr,
                            latitude=pickup_lat,
                            longitude=pickup_lon,
                            drop_address=order.delivery_address,
                            drop_contact_name=order.customer_name,
                            preferred_date=now.date(),
                            preferred_time="Immediate",
                            issue_title=f"Marketplace Order Delivery #{order.order_number}",
                            description=f"Delivery of Order #{order.order_number} to {order.customer_name}. Total: ₹{order.total_amount}",
                            total_amount=order.total_amount,
                            status="new_request",
                        )
                        order.dispatch_job = sr
                        dispatch_job(sr)
                    elif order.dispatch_job and order.dispatch_job.status in ["unassigned", "redispatching", "new_request"]:
                        from workforce_api.services.automatic_dispatch import dispatch_job
                        update_fields = []
                        if order.dispatch_job.latitude != pickup_lat or order.dispatch_job.longitude != pickup_lon:
                            order.dispatch_job.latitude = pickup_lat
                            order.dispatch_job.longitude = pickup_lon
                            update_fields.extend(["latitude", "longitude"])
                        if order.dispatch_job.address != pickup_addr:
                            order.dispatch_job.address = pickup_addr
                            update_fields.append("address")
                        if update_fields:
                            order.dispatch_job.save(update_fields=list(set(update_fields)))
                        dispatch_job(order.dispatch_job)

            elif target_status == SellerOrder.Status.HANDED_OVER:
                order.handed_over_at = now
                if handover_ref:
                    order.handover_ref = handover_ref
                self._deduct_inventory_for_order(order, user, notes or f"Handover for order #{order.order_number}")
            elif target_status == SellerOrder.Status.DELIVERED:
                order.delivered_at = now
                self._deduct_inventory_for_order(order, user, notes or f"Delivered order #{order.order_number}")
            elif target_status == SellerOrder.Status.CANCELLED:
                order.cancelled_at = now
                order.cancellation_reason = cancellation_reason
                order.cancelled_by = user
                self._release_inventory_reservations(order, user, cancellation_reason)

                # Delivery group check for remaining active orders
                if order.delivery_group_id:
                    remaining_active = list(
                        SellerOrder.objects.filter(
                            delivery_group_id=order.delivery_group_id
                        ).exclude(pk=order.pk).exclude(status=SellerOrder.Status.CANCELLED)
                    )

                    if remaining_active and all(o.status in [SellerOrder.Status.READY_FOR_PICKUP, SellerOrder.Status.ASSIGNED] for o in remaining_active):
                        has_sr = any(o.dispatch_job for o in remaining_active)
                        if not has_sr:
                            if warehouse.latitude is not None:
                                from service_requests.models import ServiceRequest
                                from workforce_api.services.automatic_dispatch import dispatch_job

                                total_rem_amount = sum((o.total_amount for o in remaining_active), Decimal("0.00"))
                                all_order_numbers = ", ".join(o.order_number for o in remaining_active)
                                all_sellers = ", ".join(sorted(set(getattr(o.company, "company_name", f"Seller #{o.company_id}") for o in remaining_active if o.company_id)))

                                sr = ServiceRequest.objects.create(
                                    company=order.company,
                                    service_category="goods_transport_two_wheeler",
                                    job_type="DELIVERY",
                                    request_kind=ServiceRequest.RequestKind.DIRECT,
                                    customer_name=remaining_active[0].customer_name,
                                    phone=remaining_active[0].customer_phone,
                                    address=warehouse.address or f"Warehouse: {warehouse.name}",
                                    latitude=warehouse.latitude,
                                    longitude=warehouse.longitude,
                                    drop_address=remaining_active[0].delivery_address,
                                    drop_contact_name=remaining_active[0].customer_name,
                                    preferred_date=now.date(),
                                    preferred_time="Immediate",
                                    issue_title=f"Consolidated Delivery ({len(remaining_active)} sub-orders): {all_order_numbers}",
                                    description=f"Consolidated Delivery for {remaining_active[0].customer_name} from {all_sellers}. Orders: {all_order_numbers}. Total: ₹{total_rem_amount}",
                                    total_amount=total_rem_amount,
                                    status="new_request",
                                )
                                for o in remaining_active:
                                    o.dispatch_job = sr
                                    o.save(update_fields=["dispatch_job", "updated_at"])
                                dispatch_job(sr)

            order.status = target_status
            if notes:
                order.seller_notes = (order.seller_notes + f"\n[{now.strftime('%Y-%m-%d %H:%M')}] (Warehouse): " + notes).strip()

            order.save()

            # Create immutable audit log
            SellerOrderAuditLog.objects.create(
                order=order,
                from_status=from_status,
                to_status=target_status,
                action=f"Warehouse {action.replace('_', ' ').title()}",
                actor=user,
                notes=cancellation_reason if target_status == SellerOrder.Status.CANCELLED else notes,
            )

            # Record outbox status event within the same transaction
            record_seller_order_status_event(
                order=order,
                previous_status=from_status,
                new_status=target_status,
                event_type="seller_order.cancelled" if target_status == SellerOrder.Status.CANCELLED else "seller_order.status_updated",
                actor=user,
                cancellation_source="WAREHOUSE" if target_status == SellerOrder.Status.CANCELLED else None,
            )

        detail_serializer = SellerOrderDetailSerializer(order)
        return Response(
            {
                "message": f"Order status updated to '{target_status}'.",
                "order": detail_serializer.data,
            },
            status=status.HTTP_200_OK,
        )

    def _deduct_inventory_for_order(self, order, user, reason):
        if order.inventory_deducted:
            return
        for item in order.items.select_related("product"):
            if not item.product:
                continue
            inv = SellerInventory.objects.select_for_update().filter(
                company=order.company,
                product=item.product,
            ).first()

            if not inv:
                continue

            qty_to_deduct = item.ordered_quantity
            bal_before = inv.on_hand_qty
            bal_after = max(Decimal("0.000"), inv.on_hand_qty - qty_to_deduct)
            reserved_after = max(Decimal("0.000"), inv.reserved_qty - qty_to_deduct)

            inv.on_hand_qty = bal_after
            inv.reserved_qty = reserved_after
            inv.save(update_fields=["on_hand_qty", "reserved_qty", "updated_at"])

            # Deduct from batch if linked
            if item.batch:
                b = SellerInventoryBatch.objects.select_for_update().filter(pk=item.batch.pk).first()
                if b:
                    b.current_quantity = max(Decimal("0.000"), b.current_quantity - qty_to_deduct)
                    b.update_dynamic_status(save=True)

            # Record ORDER_DEDUCTED movement
            SellerInventoryMovement.objects.create(
                inventory=inv,
                batch=item.batch,
                movement_type=SellerInventoryMovement.MovementType.ORDER_DEDUCTED,
                quantity_change=-qty_to_deduct,
                balance_before=bal_before,
                balance_after=bal_after,
                reason=reason,
                reference_id=order.source_order_id or order.order_number,
                actor=user,
            )
        order.inventory_deducted = True
        order.save(update_fields=["inventory_deducted"])

    def _release_inventory_reservations(self, order, user, reason):
        for item in order.items.select_related("product"):
            if not item.product:
                continue
            inv = SellerInventory.objects.select_for_update().filter(
                company=order.company,
                product=item.product,
            ).first()

            if not inv:
                continue

            qty_to_release = item.ordered_quantity
            inv.reserved_qty = max(Decimal("0.000"), inv.reserved_qty - qty_to_release)
            inv.save(update_fields=["reserved_qty", "updated_at"])


class WarehousePortalInboundRequestListView(APIView):
    """
    GET /api/workforce/warehouse/inbound-requests/ – List inbound stock requests for the logged-in warehouse.
    Supports status filtering and text search.
    """
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        warehouse, err_resp = _resolve_warehouse_for_request(request)
        if err_resp:
            return err_resp

        queryset = WarehouseInboundRequest.objects.filter(
            warehouse_id=warehouse.id
        ).select_related(
            "product",
            "product__variant_group",
            "company",
            "warehouse",
            "requested_by",
            "reviewed_by",
            "shortfall_reported_by",
            "seller_shortfall_decided_by",
        ).annotate(
            annotated_total_units=models.Count("units", distinct=True),
            annotated_received_units=models.Count("units", filter=models.Q(units__status="RECEIVED"), distinct=True),
            annotated_pending_units=models.Count("units", filter=models.Q(units__status="PENDING_SCAN"), distinct=True),
            annotated_not_received_units=models.Count("units", filter=models.Q(units__status="NOT_RECEIVED"), distinct=True),
        ).prefetch_related(
            "audit_logs__actor",
            "product__images",
        ).order_by("-created_at")

        # Status filter
        status_filter = request.query_params.get("status", "").strip().upper()
        if status_filter and status_filter != "ALL":
            if status_filter in WarehouseInboundRequest.Status.values:
                queryset = queryset.filter(status=status_filter)

        # Search filter
        search = request.query_params.get("search", "").strip()
        if search:
            queryset = queryset.filter(
                models.Q(product__title__icontains=search) |
                models.Q(product__sku__icontains=search) |
                models.Q(product__barcode__icontains=search) |
                models.Q(company__company_name__icontains=search) |
                models.Q(requested_by__username__icontains=search)
            )

        paginator = WarehousePortalOrdersPagination()
        page = paginator.paginate_queryset(queryset, request)
        if page is not None:
            serializer = WarehouseInboundRequestSerializer(page, many=True)
            return paginator.get_paginated_response(serializer.data)

        serializer = WarehouseInboundRequestSerializer(queryset, many=True)
        return Response({"count": len(serializer.data), "results": serializer.data}, status=status.HTTP_200_OK)


class WarehousePortalInboundRequestDecisionView(APIView):
    """
    POST /api/workforce/warehouse/inbound-requests/<int:pk>/decision/ – Accept or Reject an inbound stock request.
    Payload: { "action": "ACCEPT" | "REJECT", "reviewer_note": "optional note" }
    """
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request, pk):
        from django.db import transaction
        warehouse, err_resp = _resolve_warehouse_for_request(request)
        if err_resp:
            return err_resp

        inbound_req = WarehouseInboundRequest.objects.filter(
            id=pk,
            warehouse_id=warehouse.id,
        ).select_related("product", "company", "warehouse", "requested_by").first()

        if not inbound_req:
            return Response(
                {"error": "Inbound request not found for your warehouse facility.", "code": "NOT_FOUND"},
                status=status.HTTP_404_NOT_FOUND,
            )

        if inbound_req.status != WarehouseInboundRequest.Status.PENDING:
            return Response(
                {
                    "error": f"Inbound request is already in status '{inbound_req.status}' and cannot be modified.",
                    "code": "INVALID_STATE",
                },
                status=status.HTTP_409_CONFLICT,
            )

        action = str(request.data.get("action", "")).strip().upper()
        reviewer_note = str(request.data.get("reviewer_note", "") or request.data.get("note", "")).strip()

        if action == "ACCEPT":
            # Defense-in-depth: Warehouse cannot accept intake for unapproved products
            if inbound_req.product.status != SellerProduct.Status.APPROVED:
                return Response(
                    {
                        "error": f"Cannot accept inbound storage request: Product '{inbound_req.product.title}' (SKU: {inbound_req.product.sku}) is not admin-approved (Current status: {inbound_req.product.status}).",
                        "code": "PRODUCT_NOT_APPROVED",
                    },
                    status=status.HTTP_400_BAD_REQUEST,
                )
            target_status = WarehouseInboundRequest.Status.ACCEPTED
        elif action == "REJECT":
            target_status = WarehouseInboundRequest.Status.REJECTED
        else:
            return Response(
                {"error": "Invalid action. Expected 'ACCEPT' or 'REJECT'.", "code": "INVALID_ACTION"},
                status=status.HTTP_400_BAD_REQUEST,
            )

        with transaction.atomic():
            from_status = inbound_req.status
            inbound_req.status = target_status
            inbound_req.reviewed_by = request.user
            inbound_req.reviewed_at = timezone.now()
            inbound_req.reviewer_note = reviewer_note
            inbound_req.save(update_fields=["status", "reviewed_by", "reviewed_at", "reviewer_note", "updated_at"])

            WarehouseInboundRequestAuditLog.objects.create(
                inbound_request=inbound_req,
                action=action,
                from_status=from_status,
                to_status=target_status,
                actor=request.user,
                notes=reviewer_note or (f"Inbound request {action.lower()}ed by warehouse staff."),
            )

            # Phase Y: Generate N unique per-unit barcodes immediately on ACCEPT
            if action == "ACCEPT":
                import uuid
                units_to_create = []
                for i in range(1, inbound_req.requested_quantity + 1):
                    token = uuid.uuid4().hex[:6].upper()
                    barcode_val = f"SEVO-INB-{inbound_req.id:04d}-{i:03d}-{token}"
                    units_to_create.append(
                        WarehouseInboundUnit(
                            inbound_request=inbound_req,
                            unit_number=i,
                            barcode=barcode_val,
                            status=WarehouseInboundUnit.Status.PENDING_SCAN,
                        )
                    )
                WarehouseInboundUnit.objects.bulk_create(units_to_create)

        # Refresh for response serialization
        inbound_req.refresh_from_db()
        serializer = WarehouseInboundRequestSerializer(inbound_req)
        return Response(serializer.data, status=status.HTTP_200_OK)


class WarehousePortalInboundRequestScanUnitView(APIView):
    """
    POST /api/workforce/warehouse/inbound-requests/<int:pk>/scan-unit/
    Phase Y: Scans a single physical unit barcode during warehouse intake.
    Validates barcode belongs to this request, rejects duplicates and wrong requests,
    marks unit as RECEIVED, and when all N units are verified, credits physical on-hand stock in SellerInventory.
    """
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request, pk):
        from decimal import Decimal
        from django.db import transaction

        warehouse, err_resp = _resolve_warehouse_for_request(request)
        if err_resp:
            return err_resp

        inbound_req = WarehouseInboundRequest.objects.filter(
            id=pk,
            warehouse_id=warehouse.id,
        ).select_related("product", "company", "warehouse").first()

        if not inbound_req:
            return Response(
                {"error": "Inbound request not found for your warehouse facility.", "code": "NOT_FOUND"},
                status=status.HTTP_404_NOT_FOUND,
            )

        if inbound_req.status not in [WarehouseInboundRequest.Status.ACCEPTED, WarehouseInboundRequest.Status.PENDING, WarehouseInboundRequest.Status.COMPLETED]:
            return Response(
                {
                    "error": f"Cannot scan units for inbound request in status '{inbound_req.status}'.",
                    "code": "INVALID_STATE",
                },
                status=status.HTTP_409_CONFLICT,
            )

        raw_barcode = str(request.data.get("barcode", "")).strip()
        if not raw_barcode:
            return Response(
                {"error": "Barcode is required.", "code": "MISSING_BARCODE"},
                status=status.HTTP_400_BAD_REQUEST,
            )

        with transaction.atomic():
            # Check if unit belongs to this request
            unit = WarehouseInboundUnit.objects.select_for_update().filter(
                inbound_request=inbound_req,
                barcode=raw_barcode,
            ).first()

            if not unit:
                # Check if it belongs to another inbound request for a diagnostic error
                other_unit = WarehouseInboundUnit.objects.filter(barcode=raw_barcode).first()
                if other_unit:
                    return Response(
                        {
                            "error": f"Barcode '{raw_barcode}' belongs to Inbound Request #{other_unit.inbound_request_id} (Product: {other_unit.inbound_request.product.title}), not Request #{inbound_req.id}.",
                            "code": "WRONG_REQUEST_BARCODE",
                            "scanned_barcode": raw_barcode,
                            "actual_request_id": other_unit.inbound_request_id,
                        },
                        status=status.HTTP_400_BAD_REQUEST,
                    )
                return Response(
                    {
                        "error": f"Scanned barcode '{raw_barcode}' does not match any unit in Inbound Request #{inbound_req.id}.",
                        "code": "INVALID_BARCODE",
                        "scanned_barcode": raw_barcode,
                    },
                    status=status.HTTP_400_BAD_REQUEST,
                )

            # Check if already scanned
            if unit.status == WarehouseInboundUnit.Status.RECEIVED:
                return Response(
                    {
                        "error": f"Unit #{unit.unit_number} (Barcode: {unit.barcode}) has already been scanned and verified.",
                        "code": "DUPLICATE_SCAN",
                        "scanned_barcode": raw_barcode,
                        "unit": WarehouseInboundUnitSerializer(unit).data,
                    },
                    status=status.HTTP_400_BAD_REQUEST,
                )

            # Mark unit as RECEIVED
            unit.status = WarehouseInboundUnit.Status.RECEIVED
            unit.scanned_by = request.user
            unit.scanned_at = timezone.now()
            unit.save(update_fields=["status", "scanned_by", "scanned_at", "updated_at"])

            # Recalculate progress
            total_units = inbound_req.units.count()
            received_units = inbound_req.units.filter(status=WarehouseInboundUnit.Status.RECEIVED).count()
            is_complete = (received_units >= total_units and total_units > 0)

            # Completion trigger: If all N units are received, finalize request and credit inventory
            if is_complete and inbound_req.status != WarehouseInboundRequest.Status.COMPLETED:
                from_status = inbound_req.status
                inbound_req.status = WarehouseInboundRequest.Status.COMPLETED
                inbound_req.save(update_fields=["status", "updated_at"])

                WarehouseInboundRequestAuditLog.objects.create(
                    inbound_request=inbound_req,
                    action="RECEIVE_COMPLETE",
                    from_status=from_status,
                    to_status=WarehouseInboundRequest.Status.COMPLETED,
                    actor=request.user,
                    notes=f"Physical intake verification completed: all {total_units} unit barcodes scanned into warehouse stock.",
                )

                # Credit physical stock in SellerInventory (strictly separate from admin approval gate)
                product = inbound_req.product
                inventory, _ = SellerInventory.objects.select_for_update().get_or_create(
                    company=inbound_req.company,
                    product=product,
                    defaults={"on_hand_qty": Decimal("0.000")}
                )
                balance_before = inventory.on_hand_qty
                inventory.on_hand_qty = balance_before + Decimal(str(total_units))
                inventory.save(update_fields=["on_hand_qty", "updated_at"])

                SellerInventoryMovement.objects.create(
                    inventory=inventory,
                    movement_type=SellerInventoryMovement.MovementType.STOCK_IN,
                    quantity_change=Decimal(str(total_units)),
                    balance_before=balance_before,
                    balance_after=inventory.on_hand_qty,
                    reason=f"Warehouse inbound scan verification completed: Request #{inbound_req.id} ({total_units} units received at {inbound_req.warehouse.name})",
                    actor=request.user,
                )

        return Response(
            {
                "message": f"Unit #{unit.unit_number} verified successfully.",
                "scanned_unit": WarehouseInboundUnitSerializer(unit).data,
                "received_units_count": received_units,
                "total_units_count": total_units,
                "pending_units_count": total_units - received_units,
                "is_complete": is_complete,
                "request_status": inbound_req.status,
            },
            status=status.HTTP_200_OK,
        )


class WarehousePortalInboundRequestLabelsPdfView(APIView):
    """
    GET /api/workforce/warehouse/inbound-requests/<int:pk>/labels-pdf/
    Phase Y: Downloads printable PDF barcode label sheet for an accepted Inbound Request.
    """
    permission_classes = [permissions.IsAuthenticated]

    def perform_content_negotiation(self, request, force=False):
        # Override to prevent DRF default format suffix negotiation from treating ?format=a4 as media format
        renderers = self.get_renderers()
        return (renderers[0], renderers[0].media_type)

    def get(self, request, pk):
        from django.http import HttpResponse
        from .services.inbound_labels_pdf import render_inbound_unit_labels_pdf

        warehouse, err_resp = _resolve_warehouse_for_request(request)
        if err_resp:
            return err_resp

        inbound_req = WarehouseInboundRequest.objects.filter(
            id=pk,
            warehouse_id=warehouse.id,
        ).select_related("product", "company", "warehouse").prefetch_related("units").first()

        if not inbound_req:
            return Response(
                {"error": "Inbound request not found.", "code": "NOT_FOUND"},
                status=status.HTTP_404_NOT_FOUND,
            )

        if not inbound_req.units.exists():
            return Response(
                {"error": "No unit barcodes generated for this request yet. The request must be accepted first.", "code": "NO_UNITS"},
                status=status.HTTP_400_BAD_REQUEST,
            )

        paper_size = request.query_params.get("format") or request.query_params.get("paper_size") or "a4"
        pdf_bytes = render_inbound_unit_labels_pdf(inbound_req, paper_size=paper_size)
        response = HttpResponse(pdf_bytes, content_type="application/pdf")
        filename = f"inbound_labels_req{inbound_req.id}_{inbound_req.product.sku}_{paper_size}.pdf"
        response["Content-Disposition"] = f'inline; filename="{filename}"'
        return response


class WarehousePortalInboundRequestUnitsListView(APIView):
    """
    GET /api/workforce/warehouse/inbound-requests/<int:pk>/units/
    Phase Y: Returns list of units and their scan statuses for an Inbound Request.
    """
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request, pk):
        warehouse, err_resp = _resolve_warehouse_for_request(request)
        if err_resp:
            return err_resp

        inbound_req = WarehouseInboundRequest.objects.filter(
            id=pk,
            warehouse_id=warehouse.id,
        ).select_related("product", "company", "warehouse").first()

        if not inbound_req:
            return Response(
                {"error": "Inbound request not found.", "code": "NOT_FOUND"},
                status=status.HTTP_404_NOT_FOUND,
            )

        units = inbound_req.units.all().order_by("unit_number")
        serializer = WarehouseInboundUnitSerializer(units, many=True)
        return Response(
            {
                "inbound_request_id": inbound_req.id,
                "product_title": inbound_req.product.title,
                "product_sku": inbound_req.product.sku,
                "requested_quantity": inbound_req.requested_quantity,
                "status": inbound_req.status,
                "units": serializer.data,
            },
            status=status.HTTP_200_OK,
        )


class WarehousePortalInboundRequestReportShortfallView(APIView):
    """
    POST /api/workforce/warehouse/inbound-requests/<int:pk>/report-shortfall/
    Phase Z: Warehouse-initiated shortfall reporting.
    Staff explicitly decides to stop intake and report a shortfall when confirmed scanned units < requested quantity.
    Moves request into SHORT_RECEIVED status awaiting seller accept/reject decision.
    """
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request, pk):
        warehouse, err_resp = _resolve_warehouse_for_request(request)
        if err_resp:
            return err_resp

        inbound_req = WarehouseInboundRequest.objects.filter(
            id=pk,
            warehouse_id=warehouse.id,
        ).select_related("product", "company", "warehouse").prefetch_related("units").first()

        if not inbound_req:
            return Response(
                {"error": "Inbound request not found.", "code": "NOT_FOUND"},
                status=status.HTTP_404_NOT_FOUND,
            )

        # Must be in ACCEPTED status (in-progress scanning)
        if inbound_req.status != WarehouseInboundRequest.Status.ACCEPTED:
            return Response(
                {
                    "error": f"Shortfall can only be reported on accepted in-progress requests. Current status: '{inbound_req.status}'.",
                    "code": "INVALID_STATE",
                },
                status=status.HTTP_400_BAD_REQUEST,
            )

        received_count = inbound_req.units.filter(status=WarehouseInboundUnit.Status.RECEIVED).count()
        total_requested = inbound_req.requested_quantity

        # If zero units were scanned, reporting shortfall is invalid (intake was not started)
        if received_count == 0:
            return Response(
                {
                    "error": "Cannot report shortfall when zero units have been scanned. If the entire shipment is missing/rejected, reject the request.",
                    "code": "NO_SCANNED_UNITS",
                },
                status=status.HTTP_400_BAD_REQUEST,
            )

        # If all units are already scanned, reporting shortfall is invalid
        if received_count >= total_requested:
            return Response(
                {
                    "error": f"Cannot report shortfall: all {total_requested} units have already been received and verified.",
                    "code": "ALL_UNITS_RECEIVED",
                },
                status=status.HTTP_400_BAD_REQUEST,
            )

        shortfall_note = str(request.data.get("shortfall_note", "") or request.data.get("note", "")).strip()
        if not shortfall_note:
            return Response(
                {
                    "error": "Shortfall explanatory note is required describing the missing or damaged items.",
                    "code": "MISSING_NOTE",
                },
                status=status.HTTP_400_BAD_REQUEST,
            )

        from django.db import transaction
        with transaction.atomic():
            from_status = inbound_req.status
            inbound_req.status = WarehouseInboundRequest.Status.SHORT_RECEIVED
            inbound_req.confirmed_quantity = received_count
            inbound_req.shortfall_note = shortfall_note
            inbound_req.shortfall_reported_by = request.user
            inbound_req.shortfall_reported_at = timezone.now()
            inbound_req.save(update_fields=[
                "status",
                "confirmed_quantity",
                "shortfall_note",
                "shortfall_reported_by",
                "shortfall_reported_at",
                "updated_at",
            ])

            WarehouseInboundRequestAuditLog.objects.create(
                inbound_request=inbound_req,
                action="SHORTFALL_REPORTED",
                from_status=from_status,
                to_status=WarehouseInboundRequest.Status.SHORT_RECEIVED,
                actor=request.user,
                notes=f"Warehouse reported shortfall: {received_count}/{total_requested} units scanned. Note: {shortfall_note}",
            )

        out_serializer = WarehouseInboundRequestSerializer(inbound_req)
        return Response(
            {
                "message": f"Shortfall reported successfully ({received_count} of {total_requested} units). Awaiting seller decision.",
                "inbound_request": out_serializer.data,
            },
            status=status.HTTP_200_OK,
        )


class WarehousePortalReturnsListView(APIView):
    """
    GET /api/workforce/warehouse/returns/
    Phase Z: Returns list of warehouse return records for the authenticated facility.
    Lists rejected inbound stock batches and units staged for return to sellers.
    """
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        warehouse, err_resp = _resolve_warehouse_for_request(request)
        if err_resp:
            return err_resp

        returns_qs = WarehouseReturn.objects.filter(
            warehouse_id=warehouse.id
        ).select_related(
            "inbound_request",
            "warehouse",
            "company",
            "product",
            "created_by"
        ).order_by("-created_at")

        serializer = WarehouseReturnSerializer(returns_qs, many=True)
        return Response({"returns": serializer.data, "results": serializer.data, "count": returns_qs.count()}, status=status.HTTP_200_OK)



