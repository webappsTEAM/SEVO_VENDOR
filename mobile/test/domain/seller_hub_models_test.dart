import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/features/seller/domain/seller_hub_models.dart';

void main() {
  group('SellerHubMetrics', () {
    test('parses the /seller-hub/metrics/ payload', () {
      final m = SellerHubMetrics.fromJson({
        'catalogs_awaiting_approval': 3,
        'approved_products': 40,
        'active_categories': 20,
        'active_coupons': 6,
        'total_inventory_products': 55,
        'low_stock_items_count': 2,
        'out_of_stock_items_count': 0,
        'today_orders_count': 2,
        'pending_orders_count': 63,
        'in_prep_orders_count': 61,
        'completed_orders_count': 26,
        'cancelled_orders_count': 4,
        'total_returns_count': 2,
        'pending_returns_count': 1,
        'under_inspection_returns_count': 0,
        'resolved_returns_count': 1,
        'total_claims_count': 5,
        'open_claims_count': 2,
        'claims_requiring_response_count': 1,
      });
      expect(m.pendingOrders, 63);
      expect(m.inPrepOrders, 61);
      expect(m.activeCategories, 20);
      expect(m.activeCoupons, 6);
      expect(m.resolvedReturns, 1);
      expect(m.claimsRequiringResponse, 1);
    });

    test('missing counts default to zero; category/coupon counts stay null', () {
      final m = SellerHubMetrics.fromJson({});
      expect(m.todayOrders, 0);
      expect(m.activeCategories, isNull);
      expect(m.activeCoupons, isNull);
    });
  });

  group('SellerHubOrder', () {
    final listJson = {
      'id': 11,
      'order_number': 'SO-202609-6F31DF',
      'source_order_id': 'TEST-BASKET-ORDER-1',
      'customer_name': 'Combo Deal Buyer',
      'customer_phone': '9998887776',
      'fulfillment_type': 'DELIVERY',
      'payment_method': 'ONLINE',
      'payment_status': 'PAID',
      'total_amount': '2105.60',
      'status': 'NEW',
      'dispatch_job_id': null,
      'items_count': 3,
      'items_summary': 'Atta Flour 5kg (x4.000)',
      'created_at': '2026-09-29T10:04:00Z',
    };

    test('parses list fields and decimal strings', () {
      final o = SellerHubOrder.fromJson(listJson);
      expect(o.orderNumber, 'SO-202609-6F31DF');
      expect(o.totalAmount, closeTo(2105.60, 0.001));
      expect(o.fulfillmentLabel, 'Delivery');
      expect(o.isTerminal, isFalse);
      expect(o.items, isEmpty);
    });

    test('parses detail items, audit logs and pickup OTP', () {
      final o = SellerHubOrder.fromJson({
        ...listJson,
        'status': 'READY_FOR_PICKUP',
        'fulfillment_type': 'STORE_PICKUP',
        'pickup_otp': '4821',
        'items': [
          {
            'id': 5,
            'product_title': 'Atta Flour 5kg',
            'sku': 'ATTA-5',
            'ordered_quantity': '4.000',
            'line_total': '880.00',
            'is_picked': true,
            'is_packed': false,
            'available_stock': '12.000',
          },
        ],
        'audit_logs': [
          {'id': 1, 'action': 'ACCEPT', 'from_status': 'NEW', 'to_status': 'ACCEPTED', 'actor_name': 'Store'},
        ],
      });
      expect(o.isStorePickup, isTrue);
      expect(o.awaitingRider, isTrue);
      expect(o.pickupOtp, '4821');
      expect(o.items.single.orderedQuantity, 4);
      expect(o.items.single.isPicked, isTrue);
      expect(o.auditLogs.single.toStatus, 'ACCEPTED');
      final toggled = o.copyWithItems([o.items.single.copyWithPick(isPicked: false)]);
      expect(toggled.items.single.isPicked, isFalse);
    });

    test('order page parses paginated and bare-list responses', () {
      final paged = SellerHubOrderPage.fromJson({
        'count': 42,
        'results': [listJson],
      });
      expect(paged.count, 42);
      expect(paged.results, hasLength(1));

      final bare = SellerHubOrderPage.fromJson([listJson, listJson]);
      expect(bare.count, 2);

      expect(SellerHubOrderPage.fromJson(null).results, isEmpty);
    });
  });

  group('SellerRiderAvailability', () {
    test('parses the dispatch-gate shape', () {
      final r = SellerRiderAvailability.fromJson({
        'eligible_count': 1,
        'diagnostic_summary': '1 rider ready',
        'active_offer': {'employee_name': 'Ravi'},
        'eligible_riders': [
          {'employee_id': 1, 'name': 'Ravi', 'distance_km': 1.2, 'score': 0.9, 'gps_age_seconds': 14.2},
        ],
        'ineligible_riders': [
          {'employee_id': 2, 'name': 'Kumar', 'reason': 'Offline', 'gate': 'ONLINE'},
        ],
      });
      expect(r.eligibleCount, 1);
      expect(r.activeOfferEmployeeName, 'Ravi');
      expect(r.eligibleRiders.single.distanceKm, 1.2);
      expect(r.ineligibleRiders.single.gate, 'ONLINE');
      expect(r.nearbyRiders, isEmpty);
    });

    test('parses the warehouse-radius shape', () {
      final r = SellerRiderAvailability.fromJson({
        'warehouse_missing': true,
        'error': 'Store has no assigned fulfillment warehouse.',
        'code': 'WAREHOUSE_ASSIGNMENT_REQUIRED',
        'pickup_location': {'name': 'Unassigned Warehouse'},
        'total_active_riders': 0,
        'online_riders_count': 0,
        'riders_in_radius': 0,
        'riders': [
          {'employee_id': 3, 'name': 'Anil', 'distance_km': null, 'is_online': true},
        ],
      });
      expect(r.warehouseMissing, isTrue);
      expect(r.eligibleCount, isNull);
      expect(r.onlineRidersCount, 0);
      expect(r.pickupLocationName, 'Unassigned Warehouse');
      expect(r.nearbyRiders.single.isOnline, isTrue);
    });
  });

  group('SellerHubReturn', () {
    test('parses list + detail and derives workflow steps', () {
      final r = SellerHubReturn.fromJson({
        'id': 7,
        'return_number': 'RET-CLM-001',
        'source_return_id': 'CLM-TEST-RET-01',
        'order_number': 'ORD-CLM-001',
        'customer_name': 'Deepak Patel',
        'customer_phone': null,
        'reason': 'DAMAGED',
        'status': 'UNDER_SELLER_REVIEW',
        'quality_check_status': null,
        'items_count': 0,
        'created_at': '2026-09-19T08:00:00Z',
        'evidence_urls': ['/media/returns/1.jpg', ''],
        'items': [
          {'id': 1, 'product_title': 'Milk 1L', 'sku': 'MILK', 'returned_quantity': '2.000', 'restocked_quantity': '0'},
        ],
      });
      expect(r.needsReview, isTrue);
      expect(r.canClose, isFalse);
      expect(r.customerPhone, isNull);
      expect(r.evidenceUrls, ['/media/returns/1.jpg']);
      expect(r.items.single.returnedQuantity, 2);
    });

    test('state helpers follow the Web drawer conditions', () {
      SellerHubReturn withStatus(String s) => SellerHubReturn.fromJson({'id': 1, 'status': s, 'reason': 'X'});
      expect(withStatus('APPROVED').canSchedulePickup, isTrue);
      expect(withStatus('PICKUP_SCHEDULED').awaitingReceipt, isTrue);
      expect(withStatus('RECEIVED').canInspectOrRestock, isTrue);
      expect(withStatus('QUALITY_CHECK').canInspectOrRestock, isTrue);
      expect(withStatus('RESTOCKED').canClose, isTrue);
      expect(withStatus('DISCARDED').canClose, isTrue);
      expect(withStatus('CLOSED').canClose, isFalse);
    });
  });

  test('formatQuantity trims decimal zeros', () {
    expect(formatQuantity(4), '4');
    expect(formatQuantity(1.5), '1.5');
    expect(formatQuantity(0.125), '0.125');
  });
}
