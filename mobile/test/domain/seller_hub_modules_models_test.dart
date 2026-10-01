import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/features/seller/domain/seller_hub_models.dart';
import 'package:mobile/features/seller/domain/seller_models.dart';
import 'package:mobile/features/seller/presentation/widgets/seller_hub_widgets.dart';

void main() {
  test('SellerHubClaim parses list + detail and derives actions', () {
    final c = SellerHubClaim.fromJson({
      'id': 2,
      'claim_number': 'CLM-2026-0002',
      'description': 'Customer says 1 avocado was missing from pack.',
      'order_number': 'ORD-CLM-001',
      'claim_type': 'MISSING_ITEM',
      'claimed_amount': '30.00',
      'status': 'OPEN',
      'created_at': '2026-09-19T10:00:00',
      'evidence_urls': ['https://x/y.jpg'],
      'admin_decision': 'PENDING',
    });
    expect(c.claimedAmount, 30);
    expect(c.typeLabel, 'Missing / Undelivered Item');
    expect(c.canRespond, isTrue);
    expect(c.hasAdminDecision, isFalse);
    expect(c.canEscalate, isTrue);
    expect(c.canClose, isTrue);

    final closed = SellerHubClaim.fromJson({'id': 1, 'status': 'CLOSED', 'seller_response': 'Packed fine'});
    expect(closed.canRespond, isFalse);
    expect(closed.canEscalate, isFalse);
    expect(closed.canClose, isFalse);
  });

  test('Inventory summary follows the Web metrics memo', () {
    SellerHubInventoryItem item(String onHand, String avail, String price, {bool expiring = false}) =>
        SellerHubInventoryItem.fromJson({
          'id': 1,
          'product': 1,
          'product_title': 'X',
          'product_sku': 'X',
          'product_unit': 'piece',
          'on_hand_qty': onHand,
          'available_qty': avail,
          'reserved_qty': '0',
          'low_stock_threshold': '10.000',
          'product_selling_price': price,
          'has_expiring_batches': expiring,
        });
    final items = [
      item('60.000', '54.000', '130.00'),
      item('6.000', '6.000', '349.00', expiring: true),
      item('0.000', '0.000', '99.00'),
    ];
    final s = SellerInventorySummary.of(items);
    expect(s.total, 3);
    expect(s.inStock, 1);
    expect(s.lowStock, 1);
    expect(s.outOfStock, 1);
    expect(s.expiring, 1);
    expect(s.totalValue, closeTo(60 * 130 + 6 * 349, 0.001));
    expect(items[1].stockStatus, 'LOW_STOCK');
    expect(items[2].stockStatus, 'OUT_OF_STOCK');
  });

  test('SellerHubProduct discount and pack label', () {
    final p = SellerHubProduct.fromJson({
      'id': 5,
      'title': 'Sunflower Oil 1L',
      'sku': 'BASKET-PROD-003',
      'category': 3,
      'mrp': '150.00',
      'selling_price': '130.00',
      'tax_rate': '0.00',
      'unit': 'piece',
      'pack_size': '1',
      'status': 'approved',
    });
    expect(p.discountPercent, 13);
    expect(p.packLabel, '1 piece');
    expect(p.status, 'APPROVED');
    expect(p.categoryId, 3);
  });

  test('Bulk preview, picker category and batches parse', () {
    final preview = SellerBulkPreview.fromJson({
      'total_rows': 3,
      'valid_rows_count': 2,
      'invalid_rows_count': 1,
      'can_import': true,
      'errors': [
        {'row': 3, 'sku': 'BAD', 'errors': ['Unknown category slug']},
      ],
      'items': [
        {'row_number': 2, 'title': 'Milk', 'sku': 'M1', 'selling_price': '55', 'mrp': '60', 'has_errors': false},
      ],
    });
    expect(preview.canImport, isTrue);
    expect(preview.errors.single.errors.single, 'Unknown category slug');

    final cat = SellerCatalogPickerCategory.fromJson({
      'id': 9,
      'name': 'Oil',
      'has_children': false,
      'path': [
        {'name': 'Groceries'},
        {'name': 'Oil'},
      ],
    });
    expect(cat.isLeaf, isTrue);
    expect(cat.pathString, 'Groceries > Oil');

    final batch = SellerCatalogUploadBatch.fromJson({'id': 7, 'file_name': 'feed.csv', 'status': 'completed'});
    expect(batch.status, 'COMPLETED');
  });

  test('Warehouse, approval store and category tree parse', () {
    final wh = SellerWarehouse.fromJson({
      'id': 1,
      'name': 'Hosur Hub (RTO)',
      'code': 'HHRTO',
      'latitude': '12.7566',
      'longitude': '77.8350',
      'is_active': true,
      'assigned_sellers_count': 1,
      'sellers': [
        {'id': 4, 'name': 'Basket Test Grocery Mart', 'slug': 'basket'},
      ],
    });
    expect(wh.hasGps, isTrue);
    expect(wh.sellers.single.name, 'Basket Test Grocery Mart');

    final store = SellerApprovalStore.fromJson({
      'id': 4,
      'name': 'Fresh Greens Store',
      'slug': 'fresh-greens-store',
      'rejected_count': 4,
      'total_count': 4,
    });
    expect(store.warehouseName, isNull);
    expect(store.rejectedCount, 4);

    final paths = flattenSellerCategoryTree([
      {
        'id': 1,
        'name': 'Groceries',
        'children': [
          {'id': 2, 'name': 'Oil', 'children': []},
        ],
      },
    ]);
    expect(paths.map((p) => p.path), ['Groceries', 'Groceries > Oil']);
  });

  test('Coupon status precedence matches the Web badge', () {
    final now = DateTime(2026, 9, 29);
    SellerHubCoupon c({bool active = true, String? until}) =>
        SellerHubCoupon.fromJson({'id': 1, 'code': 'FRESH20', 'is_active': active, 'valid_until': until});
    expect(c(active: false).statusAt(now), 'Inactive');
    expect(c(until: '2026-01-01T00:00:00').statusAt(now), 'Expired');
    expect(c().statusAt(now), 'Active');
  });

  test('Reports summary band and store profile decimal strings', () {
    expect(SellerReportsSummary.fromJson({'catalog_quality_score': 64.0}).catalogQualityBand, 'Fair');
    expect(SellerReportsSummary.fromJson({'catalog_quality_score': '85'}).catalogQualityBand, 'Optimal');
    expect(SellerReportsSummary.fromJson({}).catalogQualityBand, 'Needs Review');

    final profile = SellerStoreProfile.fromJson({
      'id': 1,
      'store_name': 'Hosur Fresh Mart',
      'delivery_radius_km': '10.00',
      'latitude': '12.740900',
      'longitude': 77.8253,
    });
    expect(profile.deliveryRadiusKm, 10);
    expect(profile.latitude, closeTo(12.7409, 1e-6));
    expect(profile.toJson()['longitude'], closeTo(77.8253, 1e-6));
  });

  test('formatRupeesCompact uses Indian grouping', () {
    expect(formatRupeesCompact(69404), '₹69,404');
    expect(formatRupeesCompact(150864), '₹1,50,864');
    expect(formatRupeesCompact(999), '₹999');
    expect(formatSellerLongDate(DateTime(2026, 9, 19)), '19 Sept 2026');
  });
}
