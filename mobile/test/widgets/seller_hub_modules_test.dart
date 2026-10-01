import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/features/seller/data/seller_hub_repository.dart';
import 'package:mobile/features/seller/domain/seller_hub_models.dart';
import 'package:mobile/features/seller/presentation/catalog_uploads/seller_catalog_uploads_screen.dart';
import 'package:mobile/features/seller/presentation/categories/seller_categories_screen.dart';
import 'package:mobile/features/seller/presentation/categories_approval/seller_categories_approval_screen.dart';
import 'package:mobile/features/seller/presentation/claims/seller_claims_screen.dart';
import 'package:mobile/features/seller/presentation/coupons/seller_coupons_screen.dart';
import 'package:mobile/features/seller/presentation/inventory/seller_inventory_screen.dart';
import 'package:mobile/features/seller/presentation/reports_quality/seller_reports_quality_screen.dart';
import 'package:mobile/features/seller/presentation/warehouse/seller_warehouse_screen.dart';

class FakeRepo extends SellerHubRepository {
  FakeRepo() : super(Dio());

  final calls = <String>[];
  Object? failWith;

  List<SellerHubClaim> claims = [
    SellerHubClaim.fromJson({
      'id': 2,
      'claim_number': 'CLM-2026-0002',
      'description': 'Customer says 1 avocado was missing from pack.',
      'order_number': 'ORD-CLM-001',
      'claim_type': 'MISSING_ITEM',
      'claimed_amount': '30.00',
      'status': 'OPEN',
      'created_at': '2026-09-19T10:00:00',
    }),
  ];

  List<SellerHubInventoryItem> inventory = [
    SellerHubInventoryItem.fromJson({
      'id': 1,
      'product': 11,
      'product_title': 'Sunflower Oil 1L',
      'product_sku': 'BASKET-PROD-003',
      'product_unit': 'piece',
      'product_pack_size': '1',
      'product_category_name': 'Basket Grocery Category',
      'on_hand_qty': '60.000',
      'reserved_qty': '6.000',
      'available_qty': '54.000',
      'low_stock_threshold': '10.000',
      'product_selling_price': '130.00',
    }),
  ];

  @override
  Future<SellerHubMetrics> getMetrics() async => SellerHubMetrics.fromJson({
        'open_claims_count': 2,
        'claims_requiring_response_count': 1,
        'escalated_claims_count': 0,
        'resolved_claims_count': 1,
        'total_claims_count': 3,
        'total_products': 25,
        'approved_products': 16,
        'rejected_products': 9,
      });

  @override
  Future<List<SellerHubClaim>> getClaims({String status = 'ALL', String claimType = '', String search = ''}) async {
    calls.add('claims:$status:$claimType');
    if (failWith != null) throw failWith!;
    return claims;
  }

  @override
  Future<SellerHubClaim> getClaimDetail(int claimId) async => claims.first;

  @override
  Future<SellerHubClaim?> respondToClaim(int claimId, String response, {List<String> evidenceUrls = const []}) async {
    calls.add('respond:$claimId:$response');
    return null;
  }

  @override
  Future<List<SellerHubInventoryItem>> getInventory({String status = 'ALL', String search = '', int? categoryId}) async {
    calls.add('inventory:$status');
    return inventory;
  }

  @override
  Future<List<SellerActiveCategory>> getActiveCategories({bool leafOnly = false}) async => [
        SellerActiveCategory.fromJson({'id': 3, 'name': 'Oil', 'path': 'Groceries > Oil', 'is_leaf': true}),
      ];

  @override
  Future<List<SellerHubProduct>> getProducts({String status = '', int? categoryId, String search = ''}) async => [
        SellerHubProduct.fromJson({
          'id': 5,
          'title': 'Sunflower Oil 1L',
          'sku': 'BASKET-PROD-003',
          'category': 3,
          'category_name': 'Basket Grocery Category',
          'mrp': '150.00',
          'selling_price': '130.00',
          'status': 'APPROVED',
        }),
        SellerHubProduct.fromJson({
          'id': 6,
          'title': 'Organic Sunflower Oil 1L',
          'sku': 'SKU-OIL-12dbf942',
          'mrp': '200.00',
          'selling_price': '180.00',
          'status': 'REJECTED',
          'rejection_reason': 'sdargqerh',
        }),
      ];

  @override
  Future<List<SellerCatalogUploadBatch>> getProductBatches() async => [
        SellerCatalogUploadBatch.fromJson({'id': 7, 'file_name': 'feed.csv', 'total_rows': 3, 'status': 'COMPLETED'}),
      ];

  @override
  Future<List<SellerHubCategory>> getCategories() async => [
        SellerHubCategory.fromJson({'id': 1, 'name': 'Groceries', 'slug': 'mkt-groceries', 'is_active': true, 'sort_order': 1}),
        SellerHubCategory.fromJson(
            {'id': 2, 'name': 'Oil', 'slug': 'oil', 'is_active': true, 'parent_id': 1, 'products_count': 5}),
        SellerHubCategory.fromJson({'id': 3, 'name': 'Dairy & Beverages', 'slug': 'dairy', 'is_active': false}),
      ];

  @override
  Future<SellerPage<SellerApprovalStore>> getApprovalSellers({String search = '', bool hasPending = false, int page = 1}) async {
    calls.add('sellers:$hasPending:$page');
    return SellerPage(
      results: [
        SellerApprovalStore.fromJson({'id': 4, 'name': 'Basket Test Grocery Mart', 'approved_count': 4, 'total_count': 4}),
        SellerApprovalStore.fromJson({
          'id': 5,
          'name': 'Fresh Grocery Superstore 12dbf942',
          'warehouse_id': 9,
          'warehouse_name': 'E2E Fulfillment Hub 12dbf942',
          'rejected_count': 1,
          'total_count': 1,
        }),
      ],
      count: 88,
      totalPages: 5,
    );
  }

  @override
  Future<List<SellerWarehouse>> getWarehouses({String search = '', String? city, bool? isActive}) async => [
        SellerWarehouse.fromJson({
          'id': 1,
          'name': 'Hosur Hub (RTO)',
          'code': 'HHRTO',
          'city': 'Hosur',
          'region': 'TamilNadu',
          'address': 'Hosur Grocery Hub (RTO) near rto checkpost',
          'latitude': '12.7566',
          'longitude': '77.8350',
          'is_active': true,
          'assigned_sellers_count': 1,
        }),
        SellerWarehouse.fromJson({'id': 2, 'name': 'Central Slots Hub BLR', 'is_active': false}),
      ];

  @override
  Future<List<SellerHubCoupon>> getCoupons({String search = '', String status = 'all', String discountType = 'all'}) async {
    calls.add('coupons:$status:$discountType');
    return [
      SellerHubCoupon.fromJson({
        'id': 1,
        'code': 'FRESH20',
        'description': '20% discount on orders over Rs.100',
        'discount_type': 'percent',
        'discount_value': '20.00',
        'max_discount_amount': '100.00',
        'min_order_amount': '100.00',
        'usage_limit_per_user': 1,
        'times_used': 1,
        'is_active': true,
      }),
    ];
  }

  @override
  Future<SellerReportsSummary> getReportsSummary(String days) async {
    calls.add('summary:$days');
    return SellerReportsSummary.fromJson({
      'catalog_quality_score': 64.0,
      'approved_products_count': 16,
      'total_products_count': 25,
      'missing_images_count': 8,
      'fulfilled_order_gross_value': 2436,
      'delivered_orders_count': 26,
      'total_orders_count': 155,
      'fulfilment_success_rate': 17.3,
      'inventory_health_index': 90.9,
      'return_rate': 7.7,
      'claims_requiring_response_count': 1,
    });
  }

  @override
  Future<SellerReportsPerformance> getReportsPerformance(String days) async =>
      SellerReportsPerformance.fromJson(const {});

  @override
  Future<SellerQualityAudit> getQualityAudit() async =>
      SellerQualityAudit.fromJson(const {'total_issues_count': 3, 'missing_images_count': 8});
}

Future<void> _pump(WidgetTester tester, FakeRepo repo, Widget screen) async {
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
  group('Claims', () {
    testWidgets('renders KPIs, filters and claim cards', (tester) async {
      final repo = FakeRepo();
      await _pump(tester, repo, const SellerClaimsScreen());
      expect(find.text('Claims & Dispute Management'), findsOneWidget);
      expect(find.text('Needs Response'), findsNWidgets(2)); // tile + chip
      expect(find.text('Awaiting seller reply'), findsOneWidget);
      expect(find.text('All Claim Types'), findsOneWidget);
      expect(find.text('#CLM-2026-0002'), findsOneWidget);
      expect(find.text('Ord: #ORD-CLM-001'), findsOneWidget);
      expect(find.text('Missing / Undelivered Item'), findsOneWidget);
      expect(find.text('₹30.00'), findsOneWidget);
      expect(find.text('19 Sept 2026'), findsOneWidget);
      expect(repo.calls.first, 'claims:ALL:');
    });

    testWidgets('status chip sends the Web status id', (tester) async {
      final repo = FakeRepo();
      await _pump(tester, repo, const SellerClaimsScreen());
      await tester.tap(find.text('Open').first);
      await tester.pumpAndSettle();
      expect(repo.calls.last, 'claims:OPEN:');
    });

    testWidgets('View opens detail and seller response is sent', (tester) async {
      final repo = FakeRepo();
      await _pump(tester, repo, const SellerClaimsScreen());
      await tester.tap(find.text('View'));
      await tester.pumpAndSettle();
      expect(find.text('Submit Seller Response'), findsOneWidget);
      expect(find.text('Linked Operational Records'), findsOneWidget);
      await tester.enterText(find.byType(TextField).at(1), 'Packed intact, courier proof attached');
      await tester.pump();
      await tester.tap(find.text('Submit Statement'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(repo.calls, contains('respond:2:Packed intact, courier proof attached'));
    });

    testWidgets('error and empty states', (tester) async {
      final failing = FakeRepo()..failWith = const SellerHubException('Failed to load claims list');
      await _pump(tester, failing, const SellerClaimsScreen());
      expect(find.text('Error Loading Claims'), findsOneWidget);
    });

    testWidgets('empty state offers filing a dispute', (tester) async {
      final empty = FakeRepo()..claims = [];
      await _pump(tester, empty, const SellerClaimsScreen());
      expect(find.text('No Claims Found'), findsOneWidget);
      expect(find.text('File a New Dispute'), findsOneWidget);
    });
  });

  group('Inventory', () {
    testWidgets('computes Web metrics from rows and renders stock card', (tester) async {
      final repo = FakeRepo();
      await _pump(tester, repo, const SellerInventoryScreen());
      expect(find.text('Store Stock & Inventory'), findsOneWidget);
      expect(find.text('LIVE STOCK ENGINE'), findsOneWidget);
      expect(find.text('Tracked SKUs'), findsOneWidget);
      expect(find.text('₹7,800'), findsOneWidget); // 60 × 130
      expect(find.text('All Leaf Categories'), findsOneWidget);
      expect(find.text('Sunflower Oil 1L'), findsOneWidget);
      expect(find.text('54.000'), findsOneWidget);
      expect(find.text('In Stock'), findsWidgets);
      expect(find.text('≤ 10.0'), findsOneWidget);
      expect(find.text('Stock In'), findsOneWidget);
      expect(find.text('Adjust'), findsOneWidget);
      expect(repo.calls.first, 'inventory:ALL');
    });

    testWidgets('empty inventory with approved products prompts initialization', (tester) async {
      final repo = FakeRepo()..inventory = [];
      await _pump(tester, repo, const SellerInventoryScreen());
      expect(find.text('No Stock Initialized Yet'), findsOneWidget);
    });

    testWidgets('Stock In sheet requires a positive quantity', (tester) async {
      final repo = FakeRepo();
      await _pump(tester, repo, const SellerInventoryScreen());
      await tester.tap(find.text('Stock In'));
      await tester.pumpAndSettle();
      expect(find.text('Stock In / Replenish'), findsOneWidget);
      final confirm = find.widgetWithText(FilledButton, 'Confirm Stock In');
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
    });
  });

  group('Catalog Uploads', () {
    testWidgets('renders metric tiles, tabs and product actions', (tester) async {
      await _pump(tester, FakeRepo(), const SellerCatalogUploadsScreen());
      expect(find.text('Catalog Uploads & Products'), findsOneWidget);
      expect(find.text('Product Catalog (2)'), findsOneWidget);
      expect(find.text('Upload Batches (1)'), findsOneWidget);
      expect(find.text('Seller Hub Categories (1 Leaf Available)'), findsOneWidget);
      expect(find.text('Sunflower Oil 1L'), findsOneWidget);
      expect(find.text('13% OFF'), findsOneWidget);
      expect(find.text('Rejection Reason: sdargqerh'), findsOneWidget);
      expect(find.text('Edit & Resubmit'), findsOneWidget);
    });

    testWidgets('Rejected tile filters the catalog', (tester) async {
      await _pump(tester, FakeRepo(), const SellerCatalogUploadsScreen());
      await tester.tap(find.text('Rejected').first);
      await tester.pumpAndSettle();
      expect(find.text('Organic Sunflower Oil 1L'), findsOneWidget);
      expect(find.text('Sunflower Oil 1L'), findsNothing);
    });

    testWidgets('Bulk tab shows template download and file chooser', (tester) async {
      await _pump(tester, FakeRepo(), const SellerCatalogUploadsScreen());
      await tester.tap(find.text('Bulk Feed'));
      await tester.pumpAndSettle();
      expect(find.text('Bulk Catalog Spreadsheet Ingestion'), findsOneWidget);
      expect(find.text('Download CSV Template'), findsOneWidget);
      expect(find.text('Supports CSV, XLSX up to 500 rows per batch'), findsOneWidget);
    });
  });

  group('Categories', () {
    testWidgets('renders tree roots, expands children and hides admin actions for non-admins', (tester) async {
      await _pump(tester, FakeRepo(), const SellerCategoriesScreen());
      expect(find.text('Catalog Categories'), findsOneWidget);
      expect(find.text('Groceries'), findsOneWidget);
      expect(find.text('Oil'), findsNothing);
      expect(find.text('Hidden from sellers'), findsOneWidget);
      expect(find.text('Add Category'), findsNothing);

      await tester.tap(find.text('Expand All'));
      await tester.pumpAndSettle();
      expect(find.text('Oil'), findsOneWidget);
    });

    testWidgets('status filter shows only inactive categories', (tester) async {
      await _pump(tester, FakeRepo(), const SellerCategoriesScreen());
      await tester.tap(find.text('Inactive').first);
      await tester.pumpAndSettle();
      expect(find.text('Dairy & Beverages'), findsOneWidget);
      expect(find.text('Groceries'), findsNothing);
    });
  });

  group('Categories Approval', () {
    testWidgets('lists merchant stores with warehouse state and pagination', (tester) async {
      final repo = FakeRepo();
      await _pump(tester, repo, const SellerCategoriesApprovalScreen());
      expect(find.text('Basket Test Grocery Mart'), findsOneWidget);
      expect(find.text('Assign Warehouse'), findsOneWidget);
      expect(find.text('E2E Fulfillment Hub 12dbf942'), findsOneWidget);
      expect(find.text('Change'), findsOneWidget);
      expect(find.text('Showing 2 of 88 merchants'), findsOneWidget);
      expect(find.text('Page 1 of 5'), findsOneWidget);
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(repo.calls.last, 'sellers:false:2');
    });
  });

  group('Warehouses', () {
    testWidgets('renders facility metrics and cards', (tester) async {
      await _pump(tester, FakeRepo(), const SellerWarehouseScreen());
      expect(find.text('Fulfillment Warehouses'), findsOneWidget);
      expect(find.text('Hosur Hub (RTO)'), findsOneWidget);
      expect(find.text('12.7566, 77.8350'), findsOneWidget);
      expect(find.text('Missing GPS Pin'), findsOneWidget);
      expect(find.text('Deactivate'), findsOneWidget);
      expect(find.text('Activate'), findsOneWidget);
    });
  });

  group('Coupons', () {
    testWidgets('renders coupon rules and filters by status', (tester) async {
      final repo = FakeRepo();
      await _pump(tester, repo, const SellerCouponsScreen());
      expect(find.text('Promotional Coupons'), findsOneWidget);
      expect(find.text('FRESH20'), findsOneWidget);
      expect(find.text('Platform Universal'), findsOneWidget);
      expect(find.text('20.00% OFF'), findsOneWidget);
      expect(find.text('Capped at ₹100.00'), findsOneWidget);
      expect(find.text('1 / ∞'), findsOneWidget);
      expect(find.text('No Expiry Date'), findsOneWidget);
      await tester.tap(find.text('Disabled'));
      await tester.pumpAndSettle();
      expect(repo.calls.last, 'coupons:inactive:all');
    });
  });

  group('Reports & Quality', () {
    testWidgets('renders KPIs and reloads for a new period', (tester) async {
      final repo = FakeRepo();
      await _pump(tester, repo, const SellerReportsQualityScreen());
      expect(find.text('Seller Reports & Quality Controls'), findsOneWidget);
      expect(find.text('64.0%'), findsOneWidget);
      expect(find.text('Catalog Quality · Fair'), findsOneWidget);
      expect(find.text('₹2,436'), findsOneWidget);
      expect(find.text('Catalog Quality Breakdown'), findsOneWidget);
      expect(repo.calls.first, 'summary:30');
      await tester.tap(find.text('7 Days'));
      await tester.pumpAndSettle();
      expect(repo.calls.last, 'summary:7');
    });

    testWidgets('audit tab lists action items', (tester) async {
      await _pump(tester, FakeRepo(), const SellerReportsQualityScreen());
      await tester.tap(find.text('Quality Audit Checklist (3)'));
      await tester.pumpAndSettle();
      expect(find.text('3 Action Items'), findsOneWidget);
      expect(find.text('Products Missing Primary Images (8)'), findsOneWidget);
    });
  });
}
