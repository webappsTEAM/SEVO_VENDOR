import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../support/dev_shot.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/features/seller/data/seller_hub_repository.dart';
import 'package:mobile/features/seller/domain/seller_hub_models.dart';
import 'package:mobile/features/seller/presentation/home/seller_home_screen.dart';
import 'package:mobile/features/seller/presentation/orders/seller_orders_screen.dart';
import 'package:mobile/features/seller/presentation/returns/seller_returns_screen.dart';

SellerHubMetrics _metrics() => SellerHubMetrics.fromJson({
      'catalogs_awaiting_approval': 4,
      'active_categories': 20,
      'active_coupons': 6,
      'low_stock_items_count': 2,
      'out_of_stock_items_count': 1,
      'today_orders_count': 2,
      'pending_orders_count': 63,
      'in_prep_orders_count': 61,
      'completed_orders_count': 26,
      'total_returns_count': 2,
      'pending_returns_count': 1,
      'under_inspection_returns_count': 0,
      'resolved_returns_count': 1,
      'total_claims_count': 5,
      'open_claims_count': 2,
      'claims_requiring_response_count': 1,
    });

SellerHubOrder _order({int id = 1, String status = 'NEW', String number = 'SO-202609-6F31DF'}) =>
    SellerHubOrder.fromJson({
      'id': id,
      'order_number': number,
      'source_order_id': 'TEST-BASKET-ORDER-$id',
      'customer_name': 'Combo Deal Buyer',
      'customer_phone': '9998887776',
      'fulfillment_type': 'DELIVERY',
      'payment_method': 'ONLINE',
      'payment_status': 'PAID',
      'total_amount': '2105.60',
      'status': status,
      'items_count': 3,
      'items_summary': 'Atta Flour 5kg (x4.000), Basmati Rice 5kg (x2.000)',
      'created_at': '2026-09-29T10:04:00',
    });

SellerHubReturn _return({String status = 'UNDER_SELLER_REVIEW'}) => SellerHubReturn.fromJson({
      'id': 9,
      'return_number': 'RET-CLM-001',
      'source_return_id': 'CLM-TEST-RET-01',
      'order_number': 'ORD-CLM-001',
      'customer_name': 'Deepak Patel',
      'reason': 'DAMAGED',
      'status': status,
      'items_count': 0,
      'created_at': '2026-09-19T08:00:00',
    });

class FakeSellerHubRepository extends SellerHubRepository {
  FakeSellerHubRepository() : super(Dio());

  Object? metricsError;
  Object? ordersError;
  List<SellerHubOrder> orders = [_order()];
  int ordersCount = 1;
  List<SellerHubReturn> returns = [_return()];

  final orderQueries = <Map<String, Object>>[];
  final returnQueries = <Map<String, String>>[];
  final transitions = <(int, String)>[];
  final reviews = <(int, String, String)>[];

  @override
  Future<SellerHubMetrics> getMetrics() async {
    if (metricsError != null) throw metricsError!;
    return _metrics();
  }

  @override
  Future<SellerHomeSummary> getHomeSummary() async {
    final m = await getMetrics();
    return SellerHomeSummary(metrics: m, categoriesCount: m.activeCategories!, couponsCount: m.activeCoupons!);
  }

  @override
  Future<SellerHubOrderPage> getOrders({
    int page = 1,
    String status = 'ALL',
    String fulfillmentType = 'ALL',
    String search = '',
  }) async {
    orderQueries.add({'page': page, 'status': status, 'fulfillment': fulfillmentType, 'search': search});
    if (ordersError != null) throw ordersError!;
    return SellerHubOrderPage(results: orders, count: ordersCount);
  }

  @override
  Future<SellerHubOrder?> transitionOrder(
    int orderId,
    String action, {
    String notes = '',
    String cancellationReason = '',
  }) async {
    transitions.add((orderId, action));
    return null;
  }

  @override
  Future<List<SellerHubReturn>> getReturns({String status = 'ALL', String search = ''}) async {
    returnQueries.add({'status': status, 'search': search});
    return returns;
  }

  @override
  Future<SellerHubReturn> getReturnDetail(int returnId) async => returns.firstWhere((r) => r.id == returnId);

  @override
  Future<void> reviewReturn(
    int returnId, {
    required String decision,
    String sellerNotes = '',
    String rejectionReason = '',
  }) async {
    reviews.add((returnId, decision, rejectionReason));
  }
}

Future<void> _pump(WidgetTester tester, FakeSellerHubRepository repo, Widget screen) async {
  tester.view.physicalSize = const Size(1200, 3200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [sellerHubRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(home: screen),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('SellerHomeScreen', () {
    testWidgets('renders Merchant Center with live metrics from the API', (tester) async {
      await _pump(tester, FakeSellerHubRepository(), const SellerHomeScreen());

      expect(find.text('MERCHANT CENTER'), findsOneWidget);
      expect(find.text('Central command dashboard for your catalog, orders, inventory, and promotions'), findsOneWidget);
      expect(find.text('Seller Hub Foundation & Catalog Engine'), findsOneWidget);

      expect(find.text('Catalog Categories'), findsOneWidget);
      expect(find.text('Active Store Coupons'), findsOneWidget);
      expect(find.text('Merchant Store Status'), findsOneWidget);

      expect(find.text('63'), findsOneWidget); // Action Required
      expect(find.text('61'), findsOneWidget); // In Preparation
      expect(find.text('26'), findsOneWidget); // Completed
      expect(find.text('2 total cases'), findsOneWidget); // Return requests caption
      expect(find.text('1 need response'), findsOneWidget); // Claims caption
      expect(find.text('Pending Catalogs'), findsOneWidget);

      // No fabricated sales figure.
      expect(find.text("Today's Sales"), findsOneWidget);
      expect(find.text('₹0.00'), findsNothing);

      expect(find.text('9. Reports & Quality'), findsOneWidget);
      expect(find.text('20'), findsOneWidget); // category count
      expect(find.text('Manage (6)'), findsOneWidget);
      // No signed-in admin in this test: the non-admin variants are shown.
      expect(find.text('Browse Catalog'), findsOneWidget);
      expect(find.text('Add Products'), findsOneWidget);
    });

    testWidgets('shows an error state with retry when metrics fail', (tester) async {
      final repo = FakeSellerHubRepository()..metricsError = const SellerHubException('Request failed');
      await _pump(tester, repo, const SellerHomeScreen());

      expect(find.text('Unable to load Seller Hub metrics'), findsOneWidget);
      expect(find.text('Request failed'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      // Directory remains navigable.
      expect(find.text('2. Orders'), findsOneWidget);
    });
  });

  group('SellerOrdersScreen', () {
    testWidgets('renders header, metrics, filters and order cards', (tester) async {
      final repo = FakeSellerHubRepository();
      await _pump(tester, repo, const SellerOrdersScreen());

      expect(find.text('REAL FULFILMENT ENGINE'), findsOneWidget);
      expect(find.text('Action Required (New)'), findsOneWidget);
      expect(find.text('Fulfilled & Completed'), findsOneWidget);
      // Leading status tabs (the horizontal list builds off-screen tabs lazily);
      // "In Preparation" is also a metric tile label.
      expect(find.text('All Orders'), findsOneWidget);
      expect(find.text('New / Action Required'), findsOneWidget);
      expect(find.text('In Preparation'), findsNWidgets(2));
      expect(find.text('All Fulfilment Types'), findsOneWidget);

      expect(find.text('SO-202609-6F31DF'), findsOneWidget);
      expect(find.text('Combo Deal Buyer'), findsOneWidget);
      expect(find.text('₹ 2105.60'), findsOneWidget);
      expect(find.text('ONLINE (PAID)'), findsOneWidget);
      expect(find.text('New Order'), findsOneWidget);
      expect(find.text('Accept'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(repo.orderQueries.single, {'page': 1, 'status': 'ALL', 'fulfillment': 'ALL', 'search': ''});
    });

    testWidgets('status tab re-queries the API with the Web filter id', (tester) async {
      final repo = FakeSellerHubRepository();
      await _pump(tester, repo, const SellerOrdersScreen());

      await tester.tap(find.text('In Preparation').last);
      await tester.pumpAndSettle();
      expect(repo.orderQueries.last['status'], 'IN_PREPARATION');
    });

    testWidgets('search is debounced and sent as the search param', (tester) async {
      final repo = FakeSellerHubRepository();
      await _pump(tester, repo, const SellerOrdersScreen());

      await tester.enterText(find.byType(TextField), 'SO-2026');
      await tester.pump(const Duration(milliseconds: 100));
      expect(repo.orderQueries, hasLength(1));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(repo.orderQueries.last['search'], 'SO-2026');
    });

    testWidgets('per-status actions map to transition actions', (tester) async {
      final repo = FakeSellerHubRepository()
        ..orders = [
          _order(id: 1, status: 'NEW', number: 'SO-A'),
          _order(id: 2, status: 'ACCEPTED', number: 'SO-B'),
          _order(id: 3, status: 'PICKING', number: 'SO-C'),
          _order(id: 4, status: 'PACKED', number: 'SO-D'),
          _order(id: 5, status: 'READY_FOR_PICKUP', number: 'SO-E'),
        ]
        ..ordersCount = 5;
      await _pump(tester, repo, const SellerOrdersScreen());

      expect(find.text('Start Picking'), findsOneWidget);
      expect(find.text('Mark Packed'), findsOneWidget);
      expect(find.text('Dispatch Rider'), findsOneWidget);
      expect(find.text('Assigning Rider...'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);

      await tester.tap(find.text('Accept'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start Picking'));
      await tester.pumpAndSettle();
      expect(repo.transitions, [(1, 'accept'), (2, 'start_picking')]);
    });

    testWidgets('cancel requires a reason before confirming', (tester) async {
      final repo = FakeSellerHubRepository();
      await _pump(tester, repo, const SellerOrdersScreen());

      await tester.tap(find.text('Cancel'));
      // The card shows a busy spinner while the dialog is open.
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Cancel Fulfilment Order'), findsOneWidget);
      final confirm = find.widgetWithText(FilledButton, 'Confirm Cancellation');
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);

      await tester.enterText(find.byType(TextField).last, 'Out of stock');
      // A focused field's blinking cursor never "settles"; pump frames instead.
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(confirm);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      expect(repo.transitions, [(1, 'cancel')]);
    });

    testWidgets('empty state', (tester) async {
      final empty = FakeSellerHubRepository()
        ..orders = []
        ..ordersCount = 0;
      await _pump(tester, empty, const SellerOrdersScreen());
      expect(find.text('No Orders in Queue'), findsOneWidget);
    });

    testWidgets('error state with retry', (tester) async {
      final failing = FakeSellerHubRepository()..ordersError = const SellerHubException('Failed to fetch orders from server.');
      await _pump(tester, failing, const SellerOrdersScreen());
      expect(find.text('Error Loading Orders'), findsOneWidget);
      expect(find.text('Failed to fetch orders from server.'), findsOneWidget);
      failing.ordersError = null;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('SO-202609-6F31DF'), findsOneWidget);
    });
  });

  group('SellerReturnsScreen', () {
    testWidgets('renders summary tiles, filters and return cards', (tester) async {
      final repo = FakeSellerHubRepository();
      await _pump(tester, repo, const SellerReturnsScreen());

      expect(find.text('Returns & Reverse Logistics'), findsOneWidget);
      expect(find.text('Under Inspection'), findsOneWidget);
      expect(find.text('Resolved / Restocked'), findsOneWidget);
      expect(find.text('Total Returns'), findsOneWidget);
      expect(find.text('All Returns'), findsOneWidget);
      expect(find.text('Pending Review'), findsNWidgets(2)); // tile + chip
      expect(find.text('Approved'), findsOneWidget);
      expect(find.text('RET-CLM-001'), findsOneWidget);
      expect(find.text('#ORD-CLM-001'), findsOneWidget);
      expect(find.text('No phone'), findsOneWidget);
      expect(find.text('Under Review'), findsOneWidget);
      expect(find.text('Pending QC'), findsOneWidget);
      expect(find.text('19/09/2026'), findsOneWidget);
      expect(find.text('Manage'), findsOneWidget);
    });

    testWidgets('summary tiles filter like the Web', (tester) async {
      final repo = FakeSellerHubRepository();
      await _pump(tester, repo, const SellerReturnsScreen());

      await tester.tap(find.text('Under Inspection'));
      await tester.pumpAndSettle();
      expect(repo.returnQueries.last['status'], 'IN_INSPECTION');
      await tester.tap(find.text('Resolved / Restocked'));
      await tester.pumpAndSettle();
      expect(repo.returnQueries.last['status'], 'RESOLVED');
    });

    testWidgets('Manage opens the case and records a review decision', (tester) async {
      final repo = FakeSellerHubRepository();
      await _pump(tester, repo, const SellerReturnsScreen());

      await tester.tap(find.text('Manage'));
      await tester.pumpAndSettle();
      expect(find.text('Step 1: Seller Review Decision'), findsOneWidget);
      expect(find.text('Customer Information'), findsOneWidget);

      await tester.tap(find.text('Confirm Review Decision'));
      await tester.pumpAndSettle();
      expect(repo.reviews, [(9, 'approve', '')]);
    });

    testWidgets('closed-stage cases show the close step only', (tester) async {
      final repo = FakeSellerHubRepository()..returns = [_return(status: 'RESTOCKED')];
      await _pump(tester, repo, const SellerReturnsScreen());

      await tester.tap(find.text('Manage'));
      await tester.pumpAndSettle();
      expect(find.text('Final Step: Close Return Case'), findsOneWidget);
      expect(find.text('Step 1: Seller Review Decision'), findsNothing);
    });

    testWidgets('empty state', (tester) async {
      final repo = FakeSellerHubRepository()..returns = [];
      await _pump(tester, repo, const SellerReturnsScreen());
      expect(find.text('No Return Cases Found'), findsOneWidget);
    });
  });

  // Developer screenshots (skipped unless --dart-define=SHOTS=true).
  testWidgets('dev screenshots', (tester) async {
    await loadShotFonts();
    shotSurface(tester, width: 360, height: 1900);
    final repo = FakeSellerHubRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sellerHubRepositoryProvider.overrideWithValue(repo)],
        child: const MaterialApp(home: SellerOrdersScreen()),
      ),
    );
    await shoot(tester, 'orders_360');
  }, skip: !shotsEnabled);
}
