"""
End-to-End Test for Phase P: Real Rider Pickup & Delivery for Marketplace Orders.

Lifecycle:
READY_FOR_PICKUP -> Dispatch Job Created -> 2-Wheeler Rider Accepts ->
Pickup Arrival (Pickup OTP generated) -> Wrong OTP rejected (attempts counter increments) ->
Correct Pickup OTP verified -> HANDED_OVER -> Physical stock deducted exactly once ->
Delivery Arrival (Delivery OTP generated to customer) -> 5 Wrong OTPs triggers lockout ->
Fresh Delivery OTP verified -> DELIVERED -> Job completed -> Zero double deduction confirmed.
"""
import os
import sys
import django
import secrets
from datetime import timedelta
from decimal import Decimal

sys.stdout.reconfigure(encoding='utf-8')

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "workforce_core.settings")
django.setup()

from django.utils import timezone
from django.contrib.auth import get_user_model
from rest_framework.test import APIRequestFactory, force_authenticate

from companies.models import Company
from employees.models import Employee
from service_requests.models import ServiceRequest
from workforce_api.models import (
    Vehicle,
    SellerHubCategory,
    SellerProduct,
    SellerInventory,
    SellerInventoryBatch,
    SellerInventoryMovement,
    SellerOrder,
    SellerOrderItem,
    SellerOrderAuditLog,
    SellerOrderStatusOutbox,
    WorkforceJobOffer,
    WorkforceNotification,
    Warehouse,
    SellerWarehouseAssignment,
)
from workforce_api.views_seller_hub import (
    SellerOrderStatusTransitionView,
    SellerOrderRiderArrivePickupView,
    SellerOrderRiderVerifyPickupOTPView,
    SellerOrderRiderArriveDeliveryView,
    SellerOrderRiderVerifyDeliveryOTPView,
    SellerHubMetricsView,
    SellerOrderListView,
    SellerOrderAdminOverrideView,
    SellerOrderAvailableRidersView,
    SellerOrderRetryDispatchView,
)
from workforce_api.views import WorkforceJobAcceptOfferView
from workforce_api.services.automatic_dispatch import (
    check_candidate_eligibility,
    canonical_service_match,
    get_eligible_candidates,
    get_available_riders_summary,
    dispatch_job,
    dispatch_pending_jobs,
)

User = get_user_model()
factory = APIRequestFactory()

def run_e2e_verification():
    print("\n" + "="*80)
    print("🚀 STARTING PHASE P END-TO-END RIDER PICKUP & DELIVERY VERIFICATION")
    print("="*80)

    # 1. Setup Test Company, Merchant User, and 2-Wheeler Rider
    suffix = secrets.token_hex(4)
    company, _ = Company.objects.get_or_create(
        slug=f"seller-co-{suffix}",
        defaults={
            "company_name": f"Fresh Grocery Superstore {suffix}",
            "address": "100 MG Road, Indiranagar, Bengaluru, KA 560038",
            "business_type": "grocery_supplier",
            "is_active": True,
        }
    )

    from workforce_api.models import Warehouse, SellerWarehouseAssignment
    wh_test, _ = Warehouse.objects.get_or_create(
        name=f"E2E Fulfillment Hub {suffix}",
        defaults={
            "code": f"WH-E2E-{suffix[:4].upper()}",
            "address": "Indiranagar Hub, Bangalore",
            "latitude": Decimal("12.9716000"),
            "longitude": Decimal("77.5946000"),
            "city": "Bangalore",
            "is_active": True,
        }
    )
    SellerWarehouseAssignment.objects.update_or_create(
        company=company,
        defaults={"warehouse": wh_test}
    )

    merchant_user, _ = User.objects.get_or_create(
        username=f"merchant_{suffix}",
        defaults={"email": f"merchant_{suffix}@example.com", "first_name": "Store", "last_name": "Owner"}
    )
    merchant_user.company_id = company.id
    merchant_user.save()

    rider_user, _ = User.objects.get_or_create(
        username=f"rider_{suffix}",
        defaults={"email": f"rider_{suffix}@example.com", "first_name": "Raju", "last_name": "Rider"}
    )
    rider_user.company_id = company.id
    rider_user.save()

    rider_emp, _ = Employee.objects.get_or_create(
        user=rider_user,
        defaults={
            "company": company,
            "employee_id": f"EMP-{suffix.upper()}",
            "phone": "9876543210",
            "title": "Delivery Rider",
            "is_active": True,
            "is_online": True,
            "current_availability": "available",
            "bank_details": {"onboarding": {"status": "approved"}},
        }
    )
    rider_emp.bank_details = {"onboarding": {"status": "approved"}}
    rider_emp.save()

    # Setup Rider 2-Wheeler Vehicle with valid documents
    today = timezone.now().date()
    vehicle, _ = Vehicle.objects.get_or_create(
        company=company,
        registration_number=f"KA-04-{suffix.upper()}",
        defaults={
            "employee": rider_emp,
            "vehicle_type": Vehicle.VehicleType.TWO_WHEELER,
            "insurance_expiry": today + timedelta(days=180),
            "permit_expiry": today + timedelta(days=180),
            "puc_expiry": today + timedelta(days=180),
            "rc_verified": True,
            "is_active": True,
        }
    )

    # Setup Product & Inventory
    category, _ = SellerHubCategory.objects.get_or_create(
        slug=f"groceries-{suffix}",
        defaults={"name": "Groceries", "is_active": True}
    )

    product, _ = SellerProduct.objects.get_or_create(
        company=company,
        sku=f"SKU-OIL-{suffix}",
        defaults={
            "title": "Organic Sunflower Oil 1L",
            "category": category,
            "mrp": Decimal("200.00"),
            "selling_price": Decimal("180.00"),
            "barcode": f"890123456{suffix[:4]}",
            "status": SellerProduct.Status.APPROVED,
        }
    )

    inventory, _ = SellerInventory.objects.get_or_create(
        company=company,
        product=product,
        defaults={
            "on_hand_qty": Decimal("50.000"),
            "reserved_qty": Decimal("0.000"),
            "low_stock_threshold": Decimal("5.000"),
        }
    )

    # 2. Create SellerOrder in NEW state
    order = SellerOrder.objects.create(
        source_order_id=f"ORD-CUST-{suffix}",
        company=company,
        order_number=f"SO-2026-{suffix}",
        customer_name="Anita Sharma",
        customer_phone="9123456780",
        delivery_address="Flat 402, Sunshine Apts, Koramangala 4th Block, Bengaluru 560034",
        total_amount=Decimal("360.00"),
        status=SellerOrder.Status.NEW,
    )

    item = SellerOrderItem.objects.create(
        order=order,
        product=product,
        product_title=product.title,
        sku=product.sku,
        ordered_quantity=Decimal("2.000"),
        unit_price=Decimal("180.00"),
        line_total=Decimal("360.00"),
    )

    print(f"✅ Initialized Order #{order.order_number} (Status: {order.status}) with 2x {product.title}")

    # 3. Transition through: ACCEPTED -> PICKING -> PACKED -> READY_FOR_PICKUP
    transition_view = SellerOrderStatusTransitionView.as_view()

    # ACCEPT (Reserves 2 units)
    req = factory.post(f"/api/workforce/seller-hub/orders/{order.id}/transition/", {"action": "accept"}, format="json")
    force_authenticate(req, user=merchant_user)
    resp = transition_view(req, pk=order.id)
    assert resp.status_code == 200, f"Accept failed: {resp.data}"
    order.refresh_from_db()
    assert order.status == SellerOrder.Status.ACCEPTED

    # START PICKING
    req = factory.post(f"/api/workforce/seller-hub/orders/{order.id}/transition/", {"action": "start_picking"}, format="json")
    force_authenticate(req, user=merchant_user)
    resp = transition_view(req, pk=order.id)
    assert resp.status_code == 200, f"Start picking failed: {resp.data}"
    order.refresh_from_db()
    assert order.status == SellerOrder.Status.PICKING

    # MARK PACKED
    req = factory.post(f"/api/workforce/seller-hub/orders/{order.id}/transition/", {"action": "mark_packed"}, format="json")
    force_authenticate(req, user=merchant_user)
    resp = transition_view(req, pk=order.id)
    assert resp.status_code == 200, f"Mark packed failed: {resp.data}"
    order.refresh_from_db()
    assert order.status == SellerOrder.Status.PACKED

    # MARK READY (Creates Dispatch Job & Runs Dispatch Engine)
    req = factory.post(f"/api/workforce/seller-hub/orders/{order.id}/transition/", {"action": "mark_ready"}, format="json")
    force_authenticate(req, user=merchant_user)
    resp = transition_view(req, pk=order.id)
    assert resp.status_code == 200, f"Mark ready failed: {resp.data}"
    order.refresh_from_db()
    assert order.status == SellerOrder.Status.READY_FOR_PICKUP
    assert order.dispatch_job is not None, "Dispatch job ServiceRequest was not created!"
    assert order.dispatch_job.service_category == "two_wheeler_delivery"
    print(f"✅ Order #{order.order_number} transitioned to READY_FOR_PICKUP -> Dispatch Job #{order.dispatch_job.id} created!")

    # 4. Verify Job Offer Created & Rider Accepts
    # Create or retrieve offer for the 2-wheeler rider
    now = timezone.now()
    offer, _ = WorkforceJobOffer.objects.get_or_create(
        job=order.dispatch_job,
        employee=rider_emp,
        defaults={
            "status": WorkforceJobOffer.Status.OFFERED,
            "offered_at": now,
            "expires_at": now + timedelta(minutes=5),
        }
    )

    accept_view = WorkforceJobAcceptOfferView.as_view()
    req = factory.post(f"/api/workforce/jobs/{order.dispatch_job.id}/accept-offer/", {}, format="json")
    force_authenticate(req, user=rider_user)
    resp = accept_view(req, pk=order.dispatch_job.id)
    assert resp.status_code == 200, f"Rider offer accept failed: {resp.data}"

    order.refresh_from_db()
    assert order.status == SellerOrder.Status.ASSIGNED, f"Order status should be ASSIGNED, got {order.status}"
    assert order.handling_technician == rider_emp, "Handling technician was not linked on SellerOrder!"
    print(f"✅ 2-Wheeler Rider #{rider_emp.id} accepted offer -> SellerOrder status is ASSIGNED!")

    # 5. Verify manual handover is blocked
    req = factory.post(f"/api/workforce/seller-hub/orders/{order.id}/transition/", {"action": "handover"}, format="json")
    force_authenticate(req, user=merchant_user)
    resp = transition_view(req, pk=order.id)
    assert resp.status_code == 400, "Manual handover should be rejected!"
    assert resp.data["code"] == "MANUAL_HANDOVER_DISABLED"
    print("✅ Verified manual handover action is blocked for merchants.")

    # 6. Rider Arrives for Pickup (Generates Pickup OTP)
    arrive_pickup_view = SellerOrderRiderArrivePickupView.as_view()
    req = factory.post(f"/api/workforce/seller-hub/orders/{order.id}/arrive-pickup/", {}, format="json")
    force_authenticate(req, user=rider_user)
    resp = arrive_pickup_view(req, pk=order.id)
    assert resp.status_code == 200, f"Arrive pickup failed: {resp.data}"

    order.refresh_from_db()
    assert order.handover_otp_hash is not None, "handover_otp_hash must be generated!"
    assert order.handover_otp_attempts == 0

    # Retrieve plain OTP from merchant notification
    notif = WorkforceNotification.objects.filter(
        recipient=merchant_user,
        notification_type="ORDER_PICKUP_OTP",
        related_object_id=str(order.id),
    ).first()
    assert notif is not None, "Merchant notification with Pickup OTP not found!"
    pickup_otp = notif.message.split("Pickup Handover OTP is ")[1].split(".")[0].strip()
    print(f"✅ Rider marked arrival for pickup -> Pickup OTP issued: {pickup_otp}")

    # 7. Test Wrong Pickup OTP
    verify_pickup_view = SellerOrderRiderVerifyPickupOTPView.as_view()
    req = factory.post(f"/api/workforce/seller-hub/orders/{order.id}/verify-pickup-otp/", {"otp": "000000"}, format="json")
    force_authenticate(req, user=rider_user)
    resp = verify_pickup_view(req, pk=order.id)
    assert resp.status_code == 400, "Wrong OTP should be rejected!"
    assert resp.data["attempts_remaining"] == 4
    order.refresh_from_db()
    assert order.handover_otp_attempts == 1
    print("✅ Wrong pickup OTP rejected. Attempts counter correctly incremented to 1 (4 remaining).")

    # 8. Test Correct Pickup OTP (Transitions to HANDED_OVER & Deducts Stock Exactly Once)
    inventory.refresh_from_db()
    stock_before = inventory.on_hand_qty

    req = factory.post(f"/api/workforce/seller-hub/orders/{order.id}/verify-pickup-otp/", {"otp": pickup_otp}, format="json")
    force_authenticate(req, user=rider_user)
    resp = verify_pickup_view(req, pk=order.id)
    assert resp.status_code == 200, f"Correct pickup OTP failed: {resp.data}"

    order.refresh_from_db()
    assert order.status == SellerOrder.Status.HANDED_OVER, f"Expected HANDED_OVER, got {order.status}"
    assert order.handover_otp_used_at is not None
    assert order.inventory_deducted is True

    inventory.refresh_from_db()
    stock_after = inventory.on_hand_qty
    assert stock_before - stock_after == Decimal("2.000"), f"Expected stock reduction of 2, before={stock_before}, after={stock_after}"

    movements = SellerInventoryMovement.objects.filter(
        inventory=inventory,
        movement_type=SellerInventoryMovement.MovementType.ORDER_DEDUCTED,
        reference_id=order.source_order_id,
    )
    assert movements.count() == 1, f"Expected exactly 1 ORDER_DEDUCTED movement, found {movements.count()}"
    print(f"✅ Correct Pickup OTP verified -> Status: HANDED_OVER. Stock deducted: {stock_before} -> {stock_after} (1 movement).")

    # 9. Rider Arrives at Customer Location (Generates Delivery OTP)
    arrive_delivery_view = SellerOrderRiderArriveDeliveryView.as_view()
    req = factory.post(f"/api/workforce/seller-hub/orders/{order.id}/arrive-delivery/", {}, format="json")
    force_authenticate(req, user=rider_user)
    resp = arrive_delivery_view(req, pk=order.id)
    assert resp.status_code == 200, f"Arrive delivery failed: {resp.data}"

    order.refresh_from_db()
    assert order.delivery_otp_hash is not None, "delivery_otp_hash must be generated!"
    assert order.delivery_otp_attempts == 0

    # Retrieve plain Delivery OTP from notification
    cust_notif = WorkforceNotification.objects.filter(
        notification_type="ORDER_DELIVERY_OTP",
        related_object_id=str(order.id),
    ).first()
    # Note: customer recipient might be none if customer user wasn't mocked, check notification message
    if not cust_notif:
        cust_notif = WorkforceNotification.objects.filter(
            notification_type="ORDER_DELIVERY_OTP",
        ).order_by("-created_at").first()

    assert cust_notif is not None, "Delivery OTP notification not found!"
    delivery_otp = cust_notif.message.split("Order #" + order.order_number + " is ")[1].split(".")[0].strip()
    print(f"✅ Rider marked arrival at customer -> Delivery OTP issued: {delivery_otp}")

    # 10. Test 5 Wrong Delivery OTPs (Lockout Behavior)
    verify_delivery_view = SellerOrderRiderVerifyDeliveryOTPView.as_view()
    for attempt in range(1, 6):
        req = factory.post(f"/api/workforce/seller-hub/orders/{order.id}/verify-delivery-otp/", {"otp": f"99999{attempt}"}, format="json")
        force_authenticate(req, user=rider_user)
        resp = verify_delivery_view(req, pk=order.id)
        assert resp.status_code == 400

    order.refresh_from_db()
    assert order.delivery_otp_attempts >= 5

    # 6th attempt should be locked out
    req = factory.post(f"/api/workforce/seller-hub/orders/{order.id}/verify-delivery-otp/", {"otp": delivery_otp}, format="json")
    force_authenticate(req, user=rider_user)
    resp = verify_delivery_view(req, pk=order.id)
    assert resp.status_code == 400
    assert resp.data["code"] == "OTP_ATTEMPTS_EXCEEDED"
    print("✅ 5-attempt lockout verified. Extra attempt correctly rejected with OTP_ATTEMPTS_EXCEEDED.")

    # 11. Rider Arrives Again to Reset Lockout & Obtain Fresh Delivery OTP
    req = factory.post(f"/api/workforce/seller-hub/orders/{order.id}/arrive-delivery/", {}, format="json")
    force_authenticate(req, user=rider_user)
    resp = arrive_delivery_view(req, pk=order.id)
    assert resp.status_code == 200

    order.refresh_from_db()
    assert order.delivery_otp_attempts == 0
    fresh_notif = WorkforceNotification.objects.filter(
        notification_type="ORDER_DELIVERY_OTP",
    ).order_by("-created_at").first()
    fresh_delivery_otp = fresh_notif.message.split("Order #" + order.order_number + " is ")[1].split(".")[0].strip()

    # 12. Verify Fresh Delivery OTP -> DELIVERED
    req = factory.post(f"/api/workforce/seller-hub/orders/{order.id}/verify-delivery-otp/", {"otp": fresh_delivery_otp}, format="json")
    force_authenticate(req, user=rider_user)
    resp = verify_delivery_view(req, pk=order.id)
    assert resp.status_code == 200, f"Verify fresh delivery OTP failed: {resp.data}"

    order.refresh_from_db()
    assert order.status == SellerOrder.Status.DELIVERED, f"Expected DELIVERED, got {order.status}"
    assert order.delivered_at is not None
    assert order.delivery_otp_used_at is not None

    # Verify dispatch job completed
    order.dispatch_job.refresh_from_db()
    assert order.dispatch_job.status == "completed"

    # Confirm stock was NOT double deducted
    inventory.refresh_from_db()
    assert inventory.on_hand_qty == stock_after, f"Stock changed unexpectedly on delivery! expected={stock_after}, actual={inventory.on_hand_qty}"
    movements_after = SellerInventoryMovement.objects.filter(
        inventory=inventory,
        movement_type=SellerInventoryMovement.MovementType.ORDER_DEDUCTED,
        reference_id=order.source_order_id,
    )
    assert movements_after.count() == 1, f"Found {movements_after.count()} stock deduction movements, expected exactly 1!"

    # 13. Verify Audit Logs
    audit_logs = list(SellerOrderAuditLog.objects.filter(order=order).order_by("created_at"))
    print(f"\n📋 Full Fulfilment Audit Trail ({len(audit_logs)} events):")
    for log in audit_logs:
        print(f"  • [{log.created_at.strftime('%H:%M:%S')}] {log.action}: {log.from_status} -> {log.to_status} (by {log.actor.username if log.actor else 'System'})")

    print("\n" + "="*80)
    print("🎉 ALL PHASE P END-TO-END VERIFICATION CHECKS PASSED SUCCESSFULLY!")
    print("="*80 + "\n")


def run_phase_q_hardening_verification():
    print("\n" + "="*80)
    print("🚀 STARTING PHASE Q HARDENING: STATUS PROPAGATION & ADMIN OVERRIDE VERIFICATION")
    print("="*80)

    suffix = secrets.token_hex(4)
    company, _ = Company.objects.get_or_create(
        slug=f"co-q-{suffix}",
        defaults={
            "company_name": f"Super Mart Q {suffix}",
            "address": "42 Commercial Street, Tasker Town, Bengaluru 560001",
            "business_type": "grocery_supplier",
            "is_active": True,
        }
    )

    wh_q, _ = Warehouse.objects.get_or_create(
        name=f"Hub Q {suffix}",
        defaults={
            "code": f"WH-Q-{suffix[:4].upper()}",
            "address": "Tasker Town Hub, Bangalore",
            "latitude": Decimal("12.9800000"),
            "longitude": Decimal("77.6000000"),
            "city": "Bangalore",
            "is_active": True,
        }
    )
    SellerWarehouseAssignment.objects.update_or_create(
        company=company,
        defaults={"warehouse": wh_q}
    )

    merchant_user, _ = User.objects.get_or_create(
        username=f"merchant_q_{suffix}",
        defaults={"email": f"merchant_q_{suffix}@example.com", "first_name": "Store", "last_name": "Manager"}
    )
    merchant_user.company_id = company.id
    merchant_user.save()

    rider_user, _ = User.objects.get_or_create(
        username=f"rider_q_{suffix}",
        defaults={"email": f"rider_q_{suffix}@example.com", "first_name": "Speedy", "last_name": "Rider"}
    )
    rider_user.company_id = company.id
    rider_user.save()

    rider_emp, _ = Employee.objects.get_or_create(
        user=rider_user,
        defaults={
            "company": company,
            "employee_id": f"EMP-Q-{suffix.upper()}",
            "phone": "9876500001",
            "title": "Delivery Rider",
            "is_active": True,
            "is_online": True,
            "current_availability": "available",
            "bank_details": {"onboarding": {"status": "approved"}},
        }
    )

    # Platform Admin / Superuser
    admin_user, _ = User.objects.get_or_create(
        username=f"admin_q_{suffix}",
        defaults={
            "email": f"admin_q_{suffix}@sevoplatform.com",
            "first_name": "Platform",
            "last_name": "Admin",
            "is_superuser": True,
            "is_staff": True,
        }
    )
    admin_user.is_superuser = True
    admin_user.is_staff = True
    admin_user.save()

    category, _ = SellerHubCategory.objects.get_or_create(
        slug="beverages-q",
        defaults={"name": "Beverages Q", "sort_order": 1, "is_active": True}
    )

    product, _ = SellerProduct.objects.get_or_create(
        company=company,
        sku=f"SKU-JUICE-{suffix.upper()}",
        defaults={
            "title": "Fresh Orange Juice 1L",
            "category": category,
            "mrp": Decimal("120.00"),
            "selling_price": Decimal("99.00"),
            "status": SellerProduct.Status.APPROVED,
        }
    )

    inventory, _ = SellerInventory.objects.get_or_create(
        company=company,
        product=product,
        defaults={
            "on_hand_qty": Decimal("30.000"),
            "reserved_qty": Decimal("0.000"),
            "low_stock_threshold": Decimal("5.000"),
        }
    )

    # Create Order
    order = SellerOrder.objects.create(
        company=company,
        order_number=f"SO-Q-{suffix}",
        source_order_id=f"ORD-Q-{suffix}",
        customer_name="Anita Sharma",
        customer_phone="9988776655",
        delivery_address="304 Palm Grove, Indiranagar, Bengaluru",
        total_amount=Decimal("198.00"),
        status=SellerOrder.Status.NEW,
    )

    SellerOrderItem.objects.create(
        order=order,
        product=product,
        product_title=product.title,
        sku=product.sku,
        ordered_quantity=Decimal("2.000"),
        unit_price=Decimal("99.00"),
        line_total=Decimal("198.00"),
    )

    # 1. Accept and progress to READY_FOR_PICKUP
    transition_view = SellerOrderStatusTransitionView.as_view()
    for act in ["accept", "start_picking", "mark_packed", "mark_ready"]:
        req = factory.post(f"/api/workforce/seller-hub/orders/{order.id}/transition/", {"action": act}, format="json")
        force_authenticate(req, user=merchant_user)
        resp = transition_view(req, pk=order.id)
        assert resp.status_code == 200, f"Transition {act} failed: {resp.data}"

    order.refresh_from_db()
    assert order.status == SellerOrder.Status.READY_FOR_PICKUP

    # 2. Rider accepts offer -> Transitions to ASSIGNED
    accept_view = WorkforceJobAcceptOfferView.as_view()
    now = timezone.now()
    WorkforceJobOffer.objects.get_or_create(
        job=order.dispatch_job,
        employee=rider_emp,
        defaults={"status": WorkforceJobOffer.Status.OFFERED, "offered_at": now, "expires_at": now + timedelta(minutes=5)}
    )
    req = factory.post(f"/api/workforce/jobs/{order.dispatch_job.id}/accept-offer/", {}, format="json")
    force_authenticate(req, user=rider_user)
    resp = accept_view(req, pk=order.dispatch_job.id)
    assert resp.status_code == 200

    order.refresh_from_db()
    assert order.status == SellerOrder.Status.ASSIGNED
    assert order.handling_technician == rider_emp
    print("✅ Status.ASSIGNED state established on order.")

    # 3. Status Propagation Audit 1: Dashboard Metrics
    metrics_view = SellerHubMetricsView.as_view()
    req = factory.get("/api/workforce/seller-hub/metrics/")
    force_authenticate(req, user=merchant_user)
    resp = metrics_view(req)
    assert resp.status_code == 200
    assert resp.data["in_prep_orders_count"] >= 1, f"Expected in_prep_orders_count >= 1, got {resp.data['in_prep_orders_count']}"
    print(f"✅ Status Propagation (Metrics): in_prep_orders_count correctly includes ASSIGNED orders ({resp.data['in_prep_orders_count']} orders).")

    # 4. Status Propagation Audit 2: IN_PREPARATION Status Filter in Orders List
    orders_list_view = SellerOrderListView.as_view()
    req = factory.get("/api/workforce/seller-hub/orders/?status=IN_PREPARATION")
    force_authenticate(req, user=merchant_user)
    resp = orders_list_view(req)
    assert resp.status_code == 200
    order_ids = [o["id"] for o in resp.data.get("results", [])]
    assert order.id in order_ids, f"Order #{order.id} (ASSIGNED) was not found in IN_PREPARATION list!"
    print("✅ Status Propagation (Filtering): status=IN_PREPARATION query successfully returned the ASSIGNED order.")

    # 5. Status Propagation Audit 3: Outbox Event Payload Serialization
    outbox_evt = SellerOrderStatusOutbox.objects.filter(order=order, new_status="ASSIGNED").first()
    assert outbox_evt is not None, "Outbox event for ASSIGNED transition was not created!"
    assert "assigned_at" in outbox_evt.payload["timestamps"], "assigned_at timestamp missing in outbox payload!"
    assert outbox_evt.payload["rider"] is not None, "rider metadata missing in outbox payload!"
    assert outbox_evt.payload["rider"]["name"] == "Speedy Rider"
    assert outbox_evt.payload["dispatch_job_id"] == order.dispatch_job_id
    print(f"✅ Status Propagation (Outbox): Event payload serialized with rider info: {outbox_evt.payload['rider']['name']} and assigned_at timestamp.")

    # 6. Admin Override Security: Rejection for Non-Admin
    override_view = SellerOrderAdminOverrideView.as_view()
    req = factory.post(f"/api/workforce/seller-hub/orders/{order.id}/admin-override/", {
        "action": "admin_override_handover",
        "reason": "Rider phone battery dead",
    }, format="json")
    force_authenticate(req, user=merchant_user)
    resp = override_view(req, pk=order.id)
    assert resp.status_code == 403, f"Non-admin should be rejected with 403, got {resp.status_code}"
    assert resp.data["code"] == "FORBIDDEN_NOT_ADMIN"
    print("✅ Admin Override Security: Merchant user correctly rejected with 403 FORBIDDEN_NOT_ADMIN.")

    # 7. Admin Override Validation: Reason Required
    req = factory.post(f"/api/workforce/seller-hub/orders/{order.id}/admin-override/", {
        "action": "admin_override_handover",
        "reason": "   ",
    }, format="json")
    force_authenticate(req, user=admin_user)
    resp = override_view(req, pk=order.id)
    assert resp.status_code == 400, "Blank reason should be rejected!"
    assert resp.data["code"] == "REASON_REQUIRED"
    print("✅ Admin Override Validation: Blank justification reason rejected with 400 REASON_REQUIRED.")

    # 8. Admin Override: Force Handover
    inventory.refresh_from_db()
    stock_before_handover = inventory.on_hand_qty

    req = factory.post(f"/api/workforce/seller-hub/orders/{order.id}/admin-override/", {
        "action": "admin_override_handover",
        "reason": "Rider phone battery failed at store; physical handover verified by store manager via emergency phone.",
    }, format="json")
    force_authenticate(req, user=admin_user)
    resp = override_view(req, pk=order.id)
    assert resp.status_code == 200, f"Admin override handover failed: {resp.data}"

    order.refresh_from_db()
    assert order.status == SellerOrder.Status.HANDED_OVER
    assert order.inventory_deducted is True
    assert order.handed_over_at is not None

    inventory.refresh_from_db()
    assert stock_before_handover - inventory.on_hand_qty == Decimal("2.000"), "Stock should be deducted upon handover!"

    audit_handover = SellerOrderAuditLog.objects.filter(
        order=order,
        action="Admin Override Handover"
    ).first()
    assert audit_handover is not None, "Distinguishable 'Admin Override Handover' audit log not found!"
    assert "Reason: Rider phone battery failed" in audit_handover.notes
    assert audit_handover.actor == admin_user
    print(f"✅ Admin Override Handover: Successfully force-transitioned to HANDED_OVER. Stock deducted (30 -> {inventory.on_hand_qty}). Distinct audit log created.")

    # 9. Admin Override: Force Deliver
    req = factory.post(f"/api/workforce/seller-hub/orders/{order.id}/admin-override/", {
        "action": "admin_override_deliver",
        "reason": "Customer SMS delivery network failure confirmed by platform ops; customer verbally confirmed receipt to dispatcher.",
    }, format="json")
    force_authenticate(req, user=admin_user)
    resp = override_view(req, pk=order.id)
    assert resp.status_code == 200, f"Admin override deliver failed: {resp.data}"

    order.refresh_from_db()
    assert order.status == SellerOrder.Status.DELIVERED
    assert order.delivered_at is not None

    order.dispatch_job.refresh_from_db()
    assert order.dispatch_job.status == "completed"

    # Confirm stock was NOT double deducted
    inventory.refresh_from_db()
    assert inventory.on_hand_qty == Decimal("28.000"), f"Stock changed unexpectedly on deliver override! {inventory.on_hand_qty}"

    movements = SellerInventoryMovement.objects.filter(
        inventory=inventory,
        movement_type=SellerInventoryMovement.MovementType.ORDER_DEDUCTED,
        reference_id=order.source_order_id,
    )
    assert movements.count() == 1, f"Found {movements.count()} stock movements, expected exactly 1!"

    audit_deliver = SellerOrderAuditLog.objects.filter(
        order=order,
        action="Admin Override Delivery"
    ).first()
    assert audit_deliver is not None, "Distinguishable 'Admin Override Delivery' audit log not found!"
    assert "Reason: Customer SMS delivery network failure" in audit_deliver.notes
    assert audit_deliver.actor == admin_user
    print(f"✅ Admin Override Delivery: Successfully force-transitioned to DELIVERED. Dispatch Job completed. Stock deduction strictly deduplicated (1 movement).")

    # 10. Verify Full Audit History for Admin Override Order
    all_audits = list(SellerOrderAuditLog.objects.filter(order=order).order_by("created_at"))
    print(f"\n📋 Full Fulfilment & Admin Override Audit Trail ({len(all_audits)} events):")
    for log in all_audits:
        print(f"  • [{log.created_at.strftime('%H:%M:%S')}] {log.action}: {log.from_status} -> {log.to_status} (by {log.actor.username if log.actor else 'System'})")
        if log.notes:
            print(f"    Note: \"{log.notes}\"")

def run_phase_r_rider_availability_verification():
    print("\n" + "="*80)
    print("🚀 STARTING PHASE R: RIDER DISPATCH DIAGNOSIS, VENDOR VISIBILITY & RETRY VERIFICATION")
    print("="*80)

    suffix = secrets.token_hex(4)
    company, _ = Company.objects.get_or_create(
        slug=f"seller-co-r-{suffix}",
        defaults={
            "company_name": f"QuickMart Grocery {suffix}",
            "address": "456 100ft Road, Indiranagar, Bengaluru 560038",
            "business_type": "grocery_supplier",
            "is_active": True,
        }
    )

    wh_r, _ = Warehouse.objects.get_or_create(
        name=f"Hub R {suffix}",
        defaults={
            "code": f"WH-R-{suffix[:4].upper()}",
            "address": "Indiranagar Hub, Bangalore",
            "latitude": Decimal("12.9750000"),
            "longitude": Decimal("77.6400000"),
            "city": "Bangalore",
            "is_active": True,
        }
    )
    SellerWarehouseAssignment.objects.update_or_create(
        company=company,
        defaults={"warehouse": wh_r}
    )

    merchant_user, _ = User.objects.get_or_create(
        username=f"merchant_r_{suffix}",
        defaults={"email": f"merchant_r_{suffix}@example.com", "first_name": "Store", "last_name": "Manager"}
    )
    merchant_user.company_id = company.id
    merchant_user.save()

    rider_user, _ = User.objects.get_or_create(
        username=f"rider_r_{suffix}",
        defaults={"email": f"rider_r_{suffix}@example.com", "first_name": "Kaviya", "last_name": "K"}
    )
    rider_user.company_id = company.id
    rider_user.save()

    # Initial State: Technician appears "ONLINE" in the top bar presence toggle,
    # but availability is "offline", no vehicle on file, no GPS telemetry.
    rider_emp, _ = Employee.objects.get_or_create(
        user=rider_user,
        defaults={
            "company": company,
            "employee_id": f"EMP-R-{suffix.upper()}",
            "phone": "9876543211",
            "title": "Delivery Partner",
            "is_active": True,
            "is_online": True, # Top-bar presence is ONLINE
            "current_availability": "offline", # Not yet available
            "bank_details": {
                "onboarding": {
                    "status": "approved",
                    "services": [{"name": "two_wheeler_delivery", "status": "approved"}]
                }
            },
        }
    )

    # Setup Product & Inventory
    category, _ = SellerHubCategory.objects.get_or_create(
        slug=f"dairy-r-{suffix}",
        defaults={"name": "Dairy & Beverages", "is_active": True}
    )

    product, _ = SellerProduct.objects.get_or_create(
        company=company,
        sku=f"SKU-MILK-{suffix}",
        defaults={
            "title": "Fresh Farm Milk 1L",
            "category": category,
            "mrp": Decimal("75.00"),
            "selling_price": Decimal("68.00"),
            "status": SellerProduct.Status.APPROVED,
        }
    )

    inventory, _ = SellerInventory.objects.get_or_create(
        company=company,
        product=product,
        defaults={"on_hand_qty": Decimal("40.000"), "reserved_qty": Decimal("0.000")}
    )

    # 1. Create Order #1 and transition to READY_FOR_PICKUP
    order = SellerOrder.objects.create(
        source_order_id=f"ORD-R1-{suffix}",
        company=company,
        order_number=f"SO-R1-{suffix}",
        customer_name="Priya Nair",
        customer_phone="9811223344",
        delivery_address="Indiranagar 5th Cross, Bengaluru 560038",
        total_amount=Decimal("136.00"),
        status=SellerOrder.Status.PACKED,
    )
    SellerOrderItem.objects.create(
        order=order,
        product=product,
        product_title=product.title,
        sku=product.sku,
        ordered_quantity=Decimal("2.000"),
        unit_price=Decimal("68.00"),
        line_total=Decimal("136.00"),
    )

    transition_view = SellerOrderStatusTransitionView.as_view()
    req = factory.post(f"/api/workforce/seller-hub/orders/{order.id}/transition/", {"action": "mark_ready"}, format="json")
    force_authenticate(req, user=merchant_user)
    resp = transition_view(req, pk=order.id)
    assert resp.status_code == 200, f"Mark ready failed: {resp.data}"
    order.refresh_from_db()
    assert order.status == SellerOrder.Status.READY_FOR_PICKUP

    # 2. Check Candidate Rejection Gates (Step 1 of Prompt)
    is_match, method, matched = canonical_service_match("two_wheeler_delivery", ["two_wheeler_delivery"], [])
    assert is_match is True, "Service category matching failed!"

    is_elig, reason, gate_results = check_candidate_eligibility(rider_emp, "two_wheeler_delivery")
    assert is_elig is False, "Candidate should fail eligibility when vehicle is missing!"
    assert gate_results["G3"] is False, f"Gate 3 vehicle check should fail! Got {gate_results}"
    print(f"✅ Step 1: Confirmed rejection gate for candidate with no vehicle on file: '{reason}' (G3=FAIL).")

    # 3. Test Vendor-Visible Available Riders Endpoint (GET /available-riders/)
    avail_view = SellerOrderAvailableRidersView.as_view()
    req = factory.get(f"/api/workforce/seller-hub/orders/{order.id}/available-riders/")
    force_authenticate(req, user=merchant_user)
    resp = avail_view(req, pk=order.id)
    assert resp.status_code == 200, f"Available riders query failed: {resp.data}"
    assert resp.data["eligible_count"] == 0, "Eligible count should be 0 before gate resolution."
    assert len(resp.data["ineligible_riders"]) >= 1, "Ineligible riders diagnostic should list candidate."
    print(f"✅ Step 2: Vendor Available-Riders endpoint returned: eligible_count=0, summary='{resp.data['diagnostic_summary']}'.")

    # 4. Resolve Eligibility: Add Two-Wheeler Vehicle, Set Availability, and Send Live GPS Ping
    today = timezone.now().date()
    vehicle, _ = Vehicle.objects.get_or_create(
        company=company,
        registration_number=f"KA-03-R-{suffix.upper()}",
        defaults={
            "employee": rider_emp,
            "vehicle_type": Vehicle.VehicleType.TWO_WHEELER,
            "insurance_expiry": today + timedelta(days=120),
            "permit_expiry": today + timedelta(days=120),
            "puc_expiry": today + timedelta(days=120),
            "rc_verified": True,
            "is_active": True,
        }
    )
    rider_emp.current_availability = "available"
    rider_emp.save(update_fields=["current_availability"])

    # Fresh GPS telemetry (~0.5 km from store center)
    now_iso = timezone.now().isoformat()
    rider_user.last_known_location = {
        "latitude": 12.9750,
        "longitude": 77.5980,
        "captured_at": now_iso,
        "updated_at": now_iso,
    }
    rider_user.save(update_fields=["last_known_location"])

    # Re-check candidate eligibility
    is_elig_after, reason_after, gate_results_after = check_candidate_eligibility(rider_emp, "two_wheeler_delivery")
    assert is_elig_after is True, f"Eligibility failed after vehicle & availability: {reason_after}"

    # Re-query Vendor Available Riders Endpoint
    req = factory.get(f"/api/workforce/seller-hub/orders/{order.id}/available-riders/")
    force_authenticate(req, user=merchant_user)
    resp = avail_view(req, pk=order.id)
    assert resp.status_code == 200
    assert resp.data["eligible_count"] == 1, f"Expected 1 eligible candidate, got {resp.data['eligible_count']}"
    assert resp.data["eligible_riders"][0]["employee_id"] == rider_emp.id
    assert resp.data["eligible_riders"][0]["distance_km"] <= 5.0
    print(f"✅ Step 3: Verified Vendor Available-Riders endpoint returns 1 eligible candidate ({rider_emp.user.username}, {resp.data['eligible_riders'][0]['distance_km']} km away).")

    # 5. Test Vendor-Triggered Retry Dispatch (POST /retry-dispatch/)
    retry_view = SellerOrderRetryDispatchView.as_view()
    req = factory.post(f"/api/workforce/seller-hub/orders/{order.id}/retry-dispatch/", {}, format="json")
    force_authenticate(req, user=merchant_user)
    resp = retry_view(req, pk=order.id)
    assert resp.status_code == 200, f"Retry dispatch failed: {resp.data}"
    assert resp.data["success"] is True, f"Retry dispatch was not successful: {resp.data}"
    print(f"✅ Step 4: Vendor-triggered retry dispatch succeeded: '{resp.data['message']}'.")

    # Verify WorkforceJobOffer created
    offers = WorkforceJobOffer.objects.filter(job=order.dispatch_job, status=WorkforceJobOffer.Status.OFFERED)
    assert offers.count() == 1, f"Expected exactly 1 active offer, found {offers.count()}"
    offer = offers.first()
    assert offer.employee == rider_emp, "Offer was not assigned to candidate rider!"

    # 6. Test Idempotency of Retry Dispatch (No Duplicate / Orphaned Offers)
    req = factory.post(f"/api/workforce/seller-hub/orders/{order.id}/retry-dispatch/", {}, format="json")
    force_authenticate(req, user=merchant_user)
    resp = retry_view(req, pk=order.id)
    assert resp.status_code == 200
    offers_after_dup = WorkforceJobOffer.objects.filter(job=order.dispatch_job, status=WorkforceJobOffer.Status.OFFERED)
    assert offers_after_dup.count() == 1, "Duplicate offer created on retry!"
    print("✅ Step 5: Verified retry dispatch idempotency (no duplicate/orphaned offers created).")

    # 7. Rider Accepts Offer -> Status transitions to ASSIGNED
    accept_view = WorkforceJobAcceptOfferView.as_view()
    req = factory.post(f"/api/workforce/jobs/{order.dispatch_job.id}/accept-offer/", {}, format="json")
    force_authenticate(req, user=rider_user)
    resp = accept_view(req, pk=order.dispatch_job.id)
    assert resp.status_code == 200, f"Accept offer failed: {resp.data}"

    order.refresh_from_db()
    assert order.status == SellerOrder.Status.ASSIGNED
    assert order.handling_technician == rider_emp
    print(f"✅ Step 6: Rider accepted offer -> Order #{order.order_number} is ASSIGNED to {rider_emp.user.username}.")

    # 8. Test Automatic Periodic Reconciliation Sweep (dispatch_pending_jobs)
    # Create Order #2 when candidate is temporarily busy/holding offer, then frees up
    order2 = SellerOrder.objects.create(
        source_order_id=f"ORD-R2-{suffix}",
        company=company,
        order_number=f"SO-R2-{suffix}",
        customer_name="Vikram Seth",
        customer_phone="9877665544",
        delivery_address="Indiranagar 100ft Rd, Bengaluru 560038",
        total_amount=Decimal("68.00"),
        status=SellerOrder.Status.PACKED,
    )
    SellerOrderItem.objects.create(
        order=order2,
        product=product,
        product_title=product.title,
        sku=product.sku,
        ordered_quantity=Decimal("1.000"),
        unit_price=Decimal("68.00"),
        line_total=Decimal("68.00"),
    )

    req = factory.post(f"/api/workforce/seller-hub/orders/{order2.id}/transition/", {"action": "mark_ready"}, format="json")
    force_authenticate(req, user=merchant_user)
    resp = transition_view(req, pk=order2.id)
    assert resp.status_code == 200
    order2.refresh_from_db()
    assert order2.status == SellerOrder.Status.READY_FOR_PICKUP

    # Set up a second 2-wheeler rider who initially had a stale GPS (> 3600s ago)
    rider2_user, _ = User.objects.get_or_create(
        username=f"rider2_r_{suffix}",
        defaults={"email": f"rider2_r_{suffix}@example.com", "first_name": "Deepak", "last_name": "R"}
    )
    rider2_user.company_id = company.id
    stale_iso = (timezone.now() - timedelta(hours=3)).isoformat()
    rider2_user.last_known_location = {"latitude": 12.9750, "longitude": 77.6410, "updated_at": stale_iso}
    rider2_user.save()

    rider2_emp, _ = Employee.objects.get_or_create(
        user=rider2_user,
        defaults={
            "company": company,
            "employee_id": f"EMP-R2-{suffix.upper()}",
            "phone": "9876543212",
            "title": "Delivery Partner",
            "is_active": True,
            "is_online": True,
            "current_availability": "available",
            "bank_details": {
                "onboarding": {
                    "status": "approved",
                    "services": [{"name": "two_wheeler_delivery", "status": "approved"}]
                }
            },
        }
    )
    Vehicle.objects.get_or_create(
        company=company,
        registration_number=f"KA-04-R-{suffix.upper()}",
        defaults={
            "employee": rider2_emp,
            "vehicle_type": Vehicle.VehicleType.TWO_WHEELER,
            "insurance_expiry": today + timedelta(days=120),
            "permit_expiry": today + timedelta(days=120),
            "puc_expiry": today + timedelta(days=120),
            "rc_verified": True,
            "is_active": True,
        }
    )

    # Initially, Order2 has no offers because rider2's GPS is stale
    offers_ord2_init = WorkforceJobOffer.objects.filter(job=order2.dispatch_job, status=WorkforceJobOffer.Status.OFFERED)
    assert offers_ord2_init.count() == 0

    # Rider2 refreshes GPS telemetry
    fresh_iso = timezone.now().isoformat()
    rider2_user.last_known_location = {"latitude": 12.9750, "longitude": 77.6410, "updated_at": fresh_iso}
    rider2_user.save(update_fields=["last_known_location"])

    # Run the periodic reconciliation sweep (dispatch_pending_jobs)
    sweep_result = dispatch_pending_jobs()
    print(f"✅ Step 7: Periodic reconciliation sweep executed: {sweep_result['pending_jobs_found']} pending found, {sweep_result['dispatched_count']} dispatched.")

    # Confirm Order2 automatically received an offer during the sweep!
    offers_ord2_after = WorkforceJobOffer.objects.filter(job=order2.dispatch_job, status=WorkforceJobOffer.Status.OFFERED)
    assert offers_ord2_after.count() == 1, "Periodic sweep should have offered Order #2 to Rider #2!"
    assert offers_ord2_after.first().employee == rider2_emp
    print(f"✅ Step 8: Confirmed periodic sweep automatically offered stuck Order #{order2.order_number} to {rider2_emp.user.username} without manual action.")

    print("\n" + "="*80)
    print("🎉 ALL PHASE R DIAGNOSIS, VISIBILITY & RETRY TESTS PASSED 100%!")
    print("="*80 + "\n")


if __name__ == "__main__":
    run_e2e_verification()
    run_phase_q_hardening_verification()
    run_phase_r_rider_availability_verification()


