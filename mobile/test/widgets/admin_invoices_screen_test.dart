import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/features/admin/domain/admin_invoice.dart';
import 'package:mobile/features/admin/presentation/invoices/admin_invoices_providers.dart';
import 'package:mobile/features/admin/presentation/invoices/admin_invoices_screen.dart';

void main() {
  final sampleInvoices = [
    AdminInvoice(
      id: 201,
      invoiceNumber: 'INV-20260908-0001',
      status: 'PARTIALLY_PAID',
      statusDisplay: 'Partially Paid',
      billToName: 'Priya Rajan',
      serviceName: 'AC Compressor & Gas Charge',
      serviceCategory: 'AC Service',
      totalAmount: 3650.0,
      amountPaid: 500.0,
      balanceDue: 3150.0,
      advancePercent: 20.0,
      advanceAmount: 730.0,
      balanceAmount: 2920.0,
      issuedAt: DateTime(2026, 9, 8),
      items: const [
        AdminInvoiceItem(
          id: 1,
          name: 'AC Compressor 1.5 Ton',
          quantity: 1.0,
          unit: 'unit',
          unitPrice: 3000.0,
          totalAmount: 3000.0,
        ),
        AdminInvoiceItem(
          id: 2,
          name: 'R32 Gas Charging',
          quantity: 1.0,
          unit: 'can',
          unitPrice: 650.0,
          totalAmount: 650.0,
        ),
      ],
      payments: [
        AdminInvoicePayment(
          id: 1,
          amount: 500.0,
          method: 'UPI',
          reference: 'UPI-78945612',
          recordedAt: DateTime(2026, 9, 8),
        ),
      ],
    ),
    AdminInvoice(
      id: 202,
      invoiceNumber: 'INV-20260908-0002',
      status: 'PAID',
      statusDisplay: 'Paid',
      billToName: 'Karthik S',
      serviceName: 'Water Purifier Filter Replacement',
      serviceCategory: 'Water Purifier',
      totalAmount: 1850.0,
      amountPaid: 1850.0,
      balanceDue: 0.0,
      issuedAt: DateTime(2026, 9, 7),
    ),
  ];

  Widget buildTestWidget({
    List<AdminInvoice>? invoices,
    Object? error,
  }) {
    return ProviderScope(
      overrides: [
        if (error != null)
          adminInvoicesListProvider.overrideWith((ref) => Future.error(error))
        else ...[
          adminInvoicesListProvider.overrideWith(
            (ref) => Future.value(invoices ?? sampleInvoices),
          ),
          adminInvoiceDetailProvider(201).overrideWith(
            (ref) => Future.value(sampleInvoices.first),
          ),
        ],
      ],
      child: const MaterialApp(
        home: AdminInvoicesScreen(),
      ),
    );
  }

  group('AdminInvoicesScreen Widget Tests', () {
    testWidgets('renders Web header, KPIs, tab counts and invoice rows', (tester) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Customer Invoices & Billing'), findsOneWidget);
      expect(
        find.text('Tax invoices generated automatically for completed service requests and approved quotations.'),
        findsOneWidget,
      );
      expect(find.text('Export CSV'), findsOneWidget);
      expect(find.text('Refresh'), findsOneWidget);
      expect(find.text('Search invoice, customer, job...'), findsOneWidget);

      // KPIs computed like the Web page.
      expect(find.text('Total Invoiced'), findsOneWidget);
      expect(find.text('₹5,500.00'), findsOneWidget);
      expect(find.text('₹2,350.00'), findsOneWidget); // collected
      expect(find.text('1 fully paid invoices'), findsOneWidget);
      expect(find.text('1 Paid · 1 Unpaid'), findsOneWidget);

      // Web status tabs with counts.
      expect(find.widgetWithText(ChoiceChip, 'All Invoices (2)'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'Paid (1)'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'Partial (1)'), findsOneWidget);

      // Rows.
      expect(find.text('INV-20260908-0001'), findsOneWidget);
      expect(find.text('Priya Rajan'), findsOneWidget);
      expect(find.text('₹3,650.00'), findsOneWidget);
      expect(find.text('₹3,150.00 due'), findsWidgets);
      expect(find.text('Settled'), findsOneWidget);
      expect(find.text('Partially Paid'), findsOneWidget);
    });

    testWidgets('status tab and search filter locally', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ChoiceChip, 'Paid (1)'));
      await tester.pumpAndSettle();
      expect(find.text('INV-20260908-0002'), findsOneWidget);
      expect(find.text('INV-20260908-0001'), findsNothing);

      await tester.tap(find.widgetWithText(ChoiceChip, 'All Invoices (2)'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'karthik');
      await tester.pump();
      expect(find.text('INV-20260908-0002'), findsOneWidget);
      expect(find.text('INV-20260908-0001'), findsNothing);
    });

    testWidgets('tapping invoice card opens detail sheet', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.text('INV-20260908-0001'));
      await tester.pumpAndSettle();

      expect(find.text('Invoice Date'), findsOneWidget);
      expect(find.text('Download PDF'), findsOneWidget);
      expect(find.text('LINE ITEMS'), findsOneWidget);
      expect(find.text('AC Compressor 1.5 Ton × 1.0 unit'), findsOneWidget);
      expect(find.text('PAYMENTS HISTORY'), findsOneWidget);
      expect(find.text('Ref: UPI-78945612'), findsOneWidget);
      expect(find.text('Record a payment'), findsOneWidget);
    });

    testWidgets('renders empty state when no invoices match', (tester) async {
      await tester.pumpWidget(buildTestWidget(invoices: []));
      await tester.pumpAndSettle();

      expect(find.text('No invoices found'), findsOneWidget);
      expect(find.text('No invoices match the selected filter criteria.'), findsOneWidget);
    });

    testWidgets('renders error state on fetch failure', (tester) async {
      await tester.pumpWidget(buildTestWidget(error: Exception('Failed to connect to backend')));
      await tester.pumpAndSettle();

      expect(find.text('Unable to load invoices'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });
  });

  group('Admin Invoices Responsive Layout Tests', () {
    for (final width in [320.0, 360.0, 390.0, 412.0]) {
      testWidgets('renders without overflow at ${width}px width', (
        WidgetTester tester,
      ) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(buildTestWidget());
        await tester.pumpAndSettle();

        expect(find.text('Customer Invoices & Billing'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
