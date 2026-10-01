import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../support/dev_shot.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/features/admin/data/seller_applications_repository.dart';
import 'package:mobile/features/admin/data/vendor_stock_repository.dart';
import 'package:mobile/features/admin/domain/seller_application.dart';
import 'package:mobile/features/admin/domain/vendor_stock.dart';
import 'package:mobile/features/admin/presentation/seller_applications/seller_application_detail_screen.dart';
import 'package:mobile/features/admin/presentation/seller_applications/seller_applications_screen.dart';
import 'package:mobile/features/admin/presentation/stock/admin_stock_screen.dart';

Map<String, dynamic> _app(int id, String store, String status, {Map<String, dynamic>? extra}) => {
      'id': id,
      'store_name': store,
      'company_name': '$store Pvt Ltd',
      'registration_status': status,
      'fssai_license_number': id == 1 ? '12345678901234' : null,
      'gst_number': '29ABCDE1234F1Z5',
      'store_address': '12 Market Road',
      'created_at': '2026-09-01T10:00:00Z',
      'owner': {'first_name': 'Asha', 'last_name': 'Rao', 'mobile_number': '9876543210', 'email': 'asha@x.in'},
      'documents_status': {
        'fssai': {'status': 'approved'},
        'gst': {'status': 'pending'},
      },
      'categories_status': [
        {'id': 'oil', 'name': 'Oil', 'status': 'pending'},
        {'id': 'dairy', 'name': 'Dairy', 'status': 'approved'},
        {'id': 'snacks', 'name': 'Snacks', 'status': 'pending'},
      ],
      ...?extra,
    };

class FakeSellerRepo extends SellerApplicationsRepository {
  FakeSellerRepo() : super(Dio());

  final calls = <String>[];

  @override
  Future<List<SellerApplication>> list({String? status}) async {
    calls.add('list:${status ?? 'all'}');
    return [
      SellerApplication.fromJson(_app(1, 'Fresh Basket', 'submitted')),
      SellerApplication.fromJson(_app(2, 'Green Mart', 'approved')),
      SellerApplication.fromJson(_app(3, 'Daily Needs', 'correction_required')),
    ];
  }

  @override
  Future<SellerApplication> detail(int id) async => SellerApplication.fromJson(_app(id, 'Fresh Basket', 'submitted', extra: {
        'is_company_active': false,
        'is_accepting_orders': false,
        'onboarding_data': {
          'documents': {
            'fssai': {'title': 'FSSAI Licence', 'status': 'approved', 'document_number': 'F-1', 'file_url': 'https://x/f.pdf'},
            'gst': {'title': 'GST Certificate', 'status': 'pending'},
          },
          'categories': [
            {'id': 'oil', 'name': 'Oil', 'status': 'pending'},
          ],
        },
      }));

  @override
  Future<void> verifyDocument(int id, String docKey, String action, {String reason = ''}) async =>
      calls.add('verify:$id:$docKey:$action:$reason');

  @override
  Future<void> bulkApproveAllPending(int id) async => calls.add('bulk:$id');

  @override
  Future<void> decideCategory(int id, String categoryId, String action, {String reason = ''}) async =>
      calls.add('category:$id:$categoryId:$action');

  @override
  Future<void> requestCorrection(int id, String notes) async => calls.add('correction:$id:$notes');

  @override
  Future<void> approve(int id) async => calls.add('approve:$id');

  @override
  Future<void> reject(int id, String reason) async => calls.add('reject:$id:$reason');
}

class FakeStockRepo extends VendorStockRepository {
  FakeStockRepo() : super(Dio());

  final calls = <String>[];
  Object? failList;

  @override
  Future<List<VendorStockProduct>> list() async {
    calls.add('list');
    if (failList != null) throw failList!;
    return [
      VendorStockProduct.fromJson({
        'product_id': 10,
        'name': 'Tomato',
        'vegetable_gram': '1 kg',
        'state': 'in_stock',
        'today_available_display': '12 kg',
        'price': '40.00',
        'mrp': '50.00',
        'offer_price': '40.00',
        'reorder_level_display': '2 kg',
        'restock_level_display': '10 kg',
        'is_claimed': true,
        'is_mine': true,
      }),
      VendorStockProduct.fromJson({
        'product_id': 11,
        'name': 'Onion',
        'state': 'out_of_stock',
        'today_available_display': '0 kg',
        'price': '30.00',
        'is_claimed': true,
        'is_mine': false,
      }),
    ];
  }

  @override
  Future<VendorStockWriteResult> restock(int productId, {required double quantity, required String unit}) async {
    calls.add('restock:$productId:$quantity:$unit');
    return const VendorStockWriteResult(
      message: 'Restocked 5 kg.',
      data: {'today_available_display': '17 kg', 'state': 'in_stock'},
    );
  }

  @override
  Future<VendorStockWriteResult> markOutOfStock(int productId) async {
    calls.add('out:$productId');
    return const VendorStockWriteResult(data: {'state': 'out_of_stock', 'today_available_display': '0 kg'});
  }

  @override
  Future<VendorStockWriteResult> updateDetails(int productId, Map<String, dynamic> payload) async {
    calls.add('edit:$productId:${payload.keys.toList()..sort()}');
    return const VendorStockWriteResult(message: 'Details updated.', data: {'price': '45.00'});
  }

  @override
  Future<List<VendorStockHistoryRow>> history(int productId) async => [
        VendorStockHistoryRow.fromJson({
          'date': '2026-09-28',
          'opening_display': '10 kg',
          'restocked_grams': 5000,
          'sold_grams': 0,
          'closing_display': '15 kg',
        }),
      ];
}

Future<void> _pumpSeller(WidgetTester tester, FakeSellerRepo repo, Widget screen) async {
  tester.view.physicalSize = const Size(900, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(
    overrides: [sellerApplicationsRepositoryProvider.overrideWithValue(repo)],
    child: MaterialApp(home: screen),
  ));
  await tester.pumpAndSettle();
}

Future<void> _pumpStock(WidgetTester tester, FakeStockRepo repo) async {
  tester.view.physicalSize = const Size(900, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(
    overrides: [vendorStockRepositoryProvider.overrideWithValue(repo)],
    child: const MaterialApp(home: AdminStockScreen()),
  ));
  await tester.pumpAndSettle();
}

void main() {
  group('SellerApplication model', () {
    test('counts Web statuses and documents', () {
      final a = SellerApplication.fromJson(_app(1, 'S', 'under_review'));
      expect(a.isPending, isTrue);
      expect(a.docCount, 2);
      expect(a.approvedDocCount, 1);
      expect(sellerStatusLabel('correction_required'), 'Correction Required');
      expect(sellerStatusLabel('submitted'), 'Under Review');
    });
  });

  group('Seller Applications list', () {
    testWidgets('renders header, KPI counts and cards from the API', (tester) async {
      final repo = FakeSellerRepo();
      await _pumpSeller(tester, repo, const SellerApplicationsScreen());
      expect(find.text('Seller Applications'), findsOneWidget);
      expect(find.text('Review merchant dossiers'), findsOneWidget);
      expect(find.text('Seller Hub Applications (3)'), findsOneWidget);
      expect(find.text('Fresh Basket'), findsOneWidget);
      expect(find.text('FSSAI: 12345678901234'), findsOneWidget);
      expect(find.text('FSSAI: Pending'), findsNWidgets(2));
      expect(find.text('1/2 Docs Approved'), findsNWidgets(3));
      expect(find.text('+1'), findsNWidgets(3));
      expect(repo.calls.first, 'list:all');
    });

    testWidgets('has the Profile Change Requests tab next to the other application tabs', (tester) async {
      final repo = FakeSellerRepo();
      await _pumpSeller(tester, repo, const SellerApplicationsScreen());
      expect(find.text('Technician Applications'), findsOneWidget);
      expect(find.text('Seller Hub Applications (3)'), findsOneWidget);
      expect(find.text('Profile Change Requests'), findsOneWidget);
    });

    testWidgets('status chip re-queries with the Web status value', (tester) async {
      final repo = FakeSellerRepo();
      await _pumpSeller(tester, repo, const SellerApplicationsScreen());
      await tester.tap(find.text('Approved').first);
      await tester.pumpAndSettle();
      expect(repo.calls.last, 'list:approved');
    });

    testWidgets('search filters locally by store name', (tester) async {
      final repo = FakeSellerRepo();
      await _pumpSeller(tester, repo, const SellerApplicationsScreen());
      await tester.enterText(find.byType(TextField), 'green');
      await tester.pumpAndSettle();
      expect(find.text('Green Mart'), findsOneWidget);
      expect(find.text('Fresh Basket'), findsNothing);
      await tester.enterText(find.byType(TextField), 'zzz');
      // The empty-state artwork floats forever, so advance by time, not "settle".
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('No Seller Applications Found'), findsOneWidget);
    });
  });

  group('Seller Application dossier', () {
    testWidgets('overview shows entity, owner and audit info', (tester) async {
      final repo = FakeSellerRepo();
      await _pumpSeller(tester, repo, const SellerApplicationDetailScreen(applicationId: 1));
      expect(find.text('Storefront & Corporate Entity'), findsOneWidget);
      expect(find.text('29ABCDE1234F1Z5'), findsOneWidget);
      expect(find.text('Asha Rao'), findsOneWidget);
      expect(find.text('Approve Application'), findsOneWidget);
    });

    testWidgets('documents tab approves, bulk-approves and rejects with reason', (tester) async {
      final repo = FakeSellerRepo();
      await _pumpSeller(tester, repo, const SellerApplicationDetailScreen(applicationId: 1));
      await tester.tap(find.text('Documents (2)'));
      await tester.pumpAndSettle();
      expect(find.text('FSSAI Licence'), findsOneWidget);
      expect(find.text('Doc #: F-1'), findsOneWidget);
      await tester.tap(find.text('Approve').last);
      await tester.pumpAndSettle();
      expect(repo.calls, contains('verify:1:gst:approve:'));
      await tester.tap(find.text('Bulk Approve All Pending'));
      await tester.pumpAndSettle();
      expect(repo.calls, contains('bulk:1'));
      await tester.tap(find.text('Reject').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'blurry');
      await tester.tap(find.text('Confirm Rejection'));
      await tester.pumpAndSettle();
      expect(repo.calls, contains('verify:1:gst:reject:blurry'));
    });

    testWidgets('categories tab decides a category', (tester) async {
      final repo = FakeSellerRepo();
      await _pumpSeller(tester, repo, const SellerApplicationDetailScreen(applicationId: 1));
      await tester.tap(find.text('Categories (1)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Decline'));
      await tester.pumpAndSettle();
      expect(repo.calls, contains('category:1:oil:reject'));
    });

    testWidgets('reject requires a reason; correction and approve call the API', (tester) async {
      final repo = FakeSellerRepo();
      await _pumpSeller(tester, repo, const SellerApplicationDetailScreen(applicationId: 1));

      await tester.tap(find.text('Reject').first);
      await tester.pumpAndSettle();
      final confirm = find.widgetWithText(FilledButton, 'Confirm Rejection');
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
      await tester.enterText(find.byType(TextField).last, 'Fake licence');
      await tester.pump();
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(repo.calls, contains('reject:1:Fake licence'));

      await tester.tap(find.text('Request Correction'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'Re-upload FSSAI');
      await tester.pump();
      await tester.tap(find.text('Send Correction Request'));
      await tester.pumpAndSettle();
      expect(repo.calls, contains('correction:1:Re-upload FSSAI'));

      await tester.tap(find.text('Approve Application'));
      await tester.pumpAndSettle();
      expect(find.textContaining('not marked as approved yet'), findsOneWidget);
      await tester.tap(find.text('Approve & Activate Seller'));
      await tester.pumpAndSettle();
      expect(repo.calls, contains('approve:1'));
    });
  });

  group('Stock Management', () {
    testWidgets('renders cards, states and read-only lock', (tester) async {
      final repo = FakeStockRepo();
      await _pumpStock(tester, repo);
      expect(find.text('Stock management'), findsOneWidget);
      expect(find.text('Tomato'), findsOneWidget);
      expect(find.text('In stock'), findsOneWidget);
      expect(find.text('Out of stock'), findsOneWidget);
      expect(find.text('₹40.00'), findsOneWidget);
      expect(find.text('MRP ₹50.00'), findsOneWidget);
      expect(find.textContaining('Managed by another vendor'), findsOneWidget);
      // The locked product cannot be restocked, but its history stays available.
      final restock = find.widgetWithText(OutlinedButton, 'Restock');
      expect(tester.widget<OutlinedButton>(restock.at(1)).onPressed, isNull);
      expect(tester.widget<OutlinedButton>(restock.at(0)).onPressed, isNotNull);
    });

    testWidgets('restock validates quantity, posts, patches the card and flashes', (tester) async {
      final repo = FakeStockRepo();
      await _pumpStock(tester, repo);
      await tester.tap(find.widgetWithText(OutlinedButton, 'Restock').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add stock'));
      await tester.pumpAndSettle();
      expect(find.text('Enter a quantity greater than zero.'), findsOneWidget);
      expect(repo.calls, isNot(contains(startsWith('restock'))));

      await tester.enterText(find.byType(TextField).first, '5');
      await tester.tap(find.text('Add stock'));
      await tester.pumpAndSettle();
      expect(repo.calls, contains('restock:10:5.0:kg'));
      expect(find.text('Restocked 5 kg.'), findsOneWidget);
      expect(find.text('17 kg'), findsOneWidget);
      // Success clears the earlier validation error.
      expect(find.text('Enter a quantity greater than zero.'), findsNothing);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('mark out of stock, edit price and history', (tester) async {
      final repo = FakeStockRepo();
      await _pumpStock(tester, repo);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Mark out of stock').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm — mark out of stock'));
      await tester.pumpAndSettle();
      expect(repo.calls, contains('out:10'));
      await tester.pump(const Duration(seconds: 5));

      await tester.tap(find.widgetWithText(OutlinedButton, 'Edit price').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      // Only filled fields are sent (price + offer price were prefilled).
      expect(repo.calls.any((c) => c.startsWith('edit:10:[offer_price, price]')), isTrue);
      expect(find.text('Details updated.'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));

      await tester.tap(find.widgetWithText(OutlinedButton, 'History').first);
      await tester.pumpAndSettle();
      expect(find.text('Last 7 days'), findsOneWidget);
      expect(find.text('2026-09-28'), findsOneWidget);
      expect(find.text('+5000g'), findsOneWidget);
    });

    testWidgets('shows the API error with retry', (tester) async {
      final repo = FakeStockRepo()..failList = const VendorStockException('Could not load your stock.');
      await _pumpStock(tester, repo);
      expect(find.text('Could not load your stock.'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });
  });

  testWidgets('dev screenshots', (tester) async {
    await loadShotFonts();
    shotSurface(tester, width: 360, height: 2300);
    await tester.pumpWidget(ProviderScope(
      overrides: [sellerApplicationsRepositoryProvider.overrideWithValue(FakeSellerRepo())],
      child: const MaterialApp(home: SellerApplicationsScreen()),
    ));
    await shoot(tester, 'sellerapps_360');
  }, skip: !shotsEnabled);
}
