import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/features/admin/domain/admin_quotation.dart';
import 'package:mobile/features/admin/presentation/quotations/admin_quotation_approvals_screen.dart';
import 'package:mobile/features/admin/presentation/quotations/admin_quotation_providers.dart';

void main() {
  final accepted = [
    const AdminQuotation(
      id: 101,
      quoteNumber: 'QT-20260908-0001',
      quoteVersion: 2,
      title: 'AC Compressor & Gas Charge',
      serviceName: 'AC Compressor & Gas Charge',
      serviceCategory: 'AC Service',
      customerName: 'Priya Rajan',
      jobId: 5259,
      totalAmount: 3650.0,
      taxAmount: 657.0,
      netPayable: 3650.0,
      status: 'CUSTOMER_ACCEPTED',
      statusDisplay: 'Accepted',
      requiresStructuralClearance: true,
      isStructurallyCleared: false,
      items: [
        AdminQuoteItem(name: 'Compressor', quantity: 1, unit: 'unit', unitPrice: 2500, taxRate: 18, total: 2950),
      ],
    ),
  ];
  final held = [
    AdminQuotation.fromJson(const {
      'id': 102,
      'quote_number': 'QT-20260908-0002',
      'service_name': 'Exterior Painting',
      'service_category': 'paintings',
      'customer_name': 'Karthik S',
      'job_id': 5260,
      'net_payable': '1850.00',
      'tax_amount': '333.00',
      'status': 'PENDING_REVIEW',
      'measurements': [
        {'name': 'Front wall', 'length': 10, 'width': 12, 'area': 120},
      ],
    }),
  ];
  final history = [
    AdminQuotation.fromJson(const {
      'id': 103,
      'quote_number': 'QT-20260901-0009',
      'service_name': 'Ceiling',
      'service_category': 'paintings',
      'customer_name': 'Lokeshwari',
      'job_id': 5100,
      'net_payable': '999.00',
      'status': 'CONVERTED',
      'status_display': 'Converted',
    }),
  ];

  Widget buildTestWidget({
    List<AdminQuotation>? pendingApproval,
    List<AdminQuotation>? pendingReview,
    List<AdminQuotation>? all,
    Object? error,
  }) {
    Future<List<AdminQuotation>> value(List<AdminQuotation> v) =>
        error != null ? Future.error(error) : Future.value(v);
    return ProviderScope(
      overrides: [
        adminQuotesPendingApprovalProvider.overrideWith((ref) => value(pendingApproval ?? accepted)),
        adminQuotesPendingReviewProvider.overrideWith((ref) => value(pendingReview ?? held)),
        adminQuotesAllProvider.overrideWith((ref) => value(all ?? history)),
      ],
      child: const MaterialApp(home: AdminQuotationApprovalsScreen()),
    );
  }

  group('AdminQuotationApprovalsScreen Widget Tests', () {
    testWidgets('defaults to "Held before sending" like the Web, with tab counts', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Quotation Approvals & Review'), findsOneWidget);
      expect(
        find.text('Submitted by technician for CRM/Operations clearance. Releasing sends the quote to the customer.'),
        findsOneWidget,
      );
      expect(find.text('Refresh Queue'), findsOneWidget);
      expect(find.text('Held before sending (1)'), findsOneWidget);
      expect(find.text('Awaiting SEVO approval (1)'), findsOneWidget);
      expect(find.text('All Quotations & History (1)'), findsOneWidget);

      expect(find.text('QT-20260908-0002'), findsOneWidget);
      expect(find.text('HELD FOR CRM REVIEW'), findsOneWidget);
      expect(find.text('Release & Send to Customer'), findsOneWidget);
      expect(find.text('Reject Quote'), findsOneWidget);
    });

    testWidgets('acceptance tab shows approve & issue invoice actions', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Awaiting SEVO approval (1)'));
      await tester.pumpAndSettle();

      expect(find.text('QT-20260908-0001'), findsOneWidget);
      expect(find.text('v2'), findsOneWidget);
      expect(find.text('Structural clearance needed'), findsOneWidget);
      expect(find.text('AC Compressor & Gas Charge · Priya Rajan'), findsOneWidget);
      expect(find.text('₹3650'), findsOneWidget);
      expect(find.text('incl. GST ₹657'), findsOneWidget);
      expect(find.text('Approve & Issue Work Invoice'), findsOneWidget);
      expect(find.text('Reject'), findsOneWidget);
    });

    testWidgets('history tab is read-only with a status line', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('All Quotations & History (1)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('All Quotations & History (1)'));
      await tester.pumpAndSettle();

      expect(find.text('QT-20260901-0009'), findsOneWidget);
      expect(find.text('Status: Converted'), findsOneWidget);
      expect(find.text('Release & Send to Customer'), findsNothing);
    });

    testWidgets('expanding a card shows the milestone split and measurements', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();
      await tester.tap(find.text('QT-20260908-0002'));
      await tester.pumpAndSettle();

      expect(find.text('50% ADVANCE MILESTONE'), findsOneWidget);
      expect(find.text('₹925.00'), findsNWidgets(2)); // advance + balance
      expect(find.text('Front wall (10.0ft × 12.0ft)'), findsOneWidget);
    });

    testWidgets('empty queue uses the Web empty state', (tester) async {
      await tester.pumpWidget(buildTestWidget(pendingReview: []));
      await tester.pumpAndSettle();
      expect(find.text('No Quotations Pending'), findsOneWidget);
    });

    testWidgets('tapping approve opens confirmation dialog', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Awaiting SEVO approval (1)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Approve & Issue Work Invoice'));
      await tester.pumpAndSettle();

      expect(find.text('Approve QT-20260908-0001?'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
    });

    testWidgets('tapping reject opens reason input dialog', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reject Quote'));
      await tester.pumpAndSettle();

      expect(find.text('Reject QT-20260908-0002'), findsOneWidget);
      expect(find.text('Reason for rejection (shown in audit trail):'), findsOneWidget);
    });

    testWidgets('renders error state on API failure', (tester) async {
      await tester.pumpWidget(buildTestWidget(error: Exception('Network connection timed out')));
      await tester.pumpAndSettle();
      expect(find.text('Unable to load approval queue'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });
  });

  group('Quotation Approvals Responsive Layout Tests', () {
    for (final width in [320.0, 360.0, 390.0, 412.0]) {
      testWidgets('renders without overflow at ${width}px width', (tester) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(buildTestWidget());
        await tester.pumpAndSettle();

        expect(find.text('QT-20260908-0002'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
