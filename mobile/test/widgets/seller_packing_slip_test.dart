import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/features/seller/data/seller_hub_repository.dart';
import 'package:mobile/features/seller/domain/seller_hub_models.dart';
import 'package:mobile/features/seller/presentation/orders/seller_orders_screen.dart';

SellerHubOrder _order() => SellerHubOrder.fromJson({
      'id': 1,
      'order_number': 'SO-202609-6F31DF',
      'source_order_id': 'TEST-1',
      'customer_name': 'Combo Deal Buyer',
      'customer_phone': '9998887776',
      'fulfillment_type': 'DELIVERY',
      'payment_method': 'ONLINE',
      'payment_status': 'PAID',
      'total_amount': '2105.60',
      'status': 'NEW',
      'items_count': 2,
      'items_summary': 'Atta Flour 5kg (x4.000)',
      'created_at': '2026-09-29T10:04:00',
    });

class _Repo extends SellerHubRepository {
  _Repo(this.slip) : super(Dio());

  final SellerPackingSlip slip;
  int labelRequests = 0;

  @override
  Future<SellerHubMetrics> getMetrics() async => SellerHubMetrics.fromJson({'total_orders_count': 1});

  @override
  Future<SellerHubOrderPage> getOrders({
    int page = 1,
    String status = 'ALL',
    String fulfillmentType = 'ALL',
    String search = '',
  }) async =>
      SellerHubOrderPage(results: [_order()], count: 1);

  @override
  Future<SellerPackingSlip> getPackingSlip(int orderId) async => slip;

  @override
  Future<Uint8List> downloadShippingLabelPdf(int orderId) async {
    labelRequests++;
    throw DioException(requestOptions: RequestOptions(path: '/label'), message: 'no label in test');
  }
}

SellerPackingSlip _slip({List<Map<String, dynamic>>? items}) => SellerPackingSlip.fromJson({
      'order_number': 'SO-202609-6F31DF',
      'seller': {'name': 'Fresh Basket Store', 'address': '12 Market Road, Hosur', 'phone': '9000000001'},
      'customer': {'name': 'Combo Deal Buyer', 'delivery_address': '5 Lake View, Hosur', 'phone': '9998887776'},
      'items': items ??
          [
            {'title': 'Atta Flour 5kg Premium Whole Wheat Chakki Fresh', 'sku': 'ATTA-5', 'pack_size': '5 kg', 'ordered_qty': '4.000', 'line_total': '1200.00'},
            {'title': 'Basmati Rice', 'sku': '', 'ordered_qty': '2.000', 'line_total': '905.60'},
          ],
      'payment_method': 'ONLINE',
      'payment_status': 'PAID',
      'total_amount': '2105.60',
    });

Future<void> _open(WidgetTester tester, _Repo repo, {double width = 400}) async {
  tester.view.physicalSize = Size(width, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(
    overrides: [sellerHubRepositoryProvider.overrideWithValue(repo)],
    child: const MaterialApp(home: SellerOrdersScreen()),
  ));
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('Preview Packing Slip'));
  // The order card shows a busy spinner while the sheet is open, so settle by time.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

void main() {
  testWidgets('shows all five table columns with real order data', (tester) async {
    await _open(tester, _Repo(_slip()));
    expect(find.text('PACKING SLIP'), findsOneWidget);
    expect(find.text('Order #SO-202609-6F31DF'), findsOneWidget);
    for (final h in ['CHECK', 'PRODUCT / SKU', 'UNIT / PACK', 'QTY', 'TOTAL PRICE']) {
      expect(find.text(h), findsOneWidget, reason: h);
    }
    expect(find.text('Atta Flour 5kg Premium Whole Wheat Chakki Fresh'), findsOneWidget);
    expect(find.text('SKU: ATTA-5'), findsOneWidget);
    expect(find.text('5 kg'), findsOneWidget);
    expect(find.text('₹ 1200.00'), findsOneWidget);
    // Missing SKU / unit fall back to a dash, nothing invented.
    expect(find.text('SKU: —'), findsOneWidget);
    expect(find.text('—'), findsWidgets);
    expect(find.text('Merchant / Store'.toUpperCase()), findsOneWidget);
    expect(find.text('Fresh Basket Store'), findsOneWidget);
    expect(find.text('Payment: ONLINE (PAID)'), findsOneWidget);
    expect(find.text('GRAND TOTAL'), findsOneWidget);
    expect(find.descendant(of: find.byType(DraggableScrollableSheet), matching: find.text('₹ 2105.60')), findsOneWidget);
    expect(find.byIcon(Icons.check_box_outline_blank_rounded), findsNWidgets(2));
  });

  testWidgets('does not overflow on narrow phones with long product names', (tester) async {
    // The orders page behind the sheet has its own 320px header quirks, so only
    // errors raised by the packing slip itself are asserted on.
    final errors = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    FlutterError.onError = errors.add;
    addTearDown(() => FlutterError.onError = previous);
    await _open(tester, _Repo(_slip()), width: 320);
    expect(find.text('TOTAL PRICE'), findsOneWidget);
    final fromSlip = errors.where((e) => '${e.stack}${e.context}'.contains('_PackingSlipSheet') || e.toString().contains('seller_order_actions'));
    expect(fromSlip, isEmpty);
  });

  testWidgets('empty items shows a clean state and still shows the total', (tester) async {
    await _open(tester, _Repo(_slip(items: [])));
    expect(find.text('No items available'), findsOneWidget);
    expect(find.text('CHECK'), findsOneWidget);
    expect(find.text('GRAND TOTAL'), findsOneWidget);
    expect(find.descendant(of: find.byType(DraggableScrollableSheet), matching: find.text('₹ 2105.60')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Shipping Label (PDF) action and close button are preserved', (tester) async {
    final repo = _Repo(_slip());
    await _open(tester, repo);
    await tester.tap(find.text('Shipping Label (PDF)'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(repo.labelRequests, 1);
    await tester.tap(find.byIcon(Icons.close_rounded).last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('PACKING SLIP'), findsNothing);
  });
}
