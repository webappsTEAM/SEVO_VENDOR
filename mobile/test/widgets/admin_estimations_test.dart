import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/features/admin/data/vendor_estimation_repository.dart';
import 'package:mobile/features/admin/domain/vendor_estimation.dart';
import 'package:mobile/features/admin/presentation/estimations/admin_estimation_detail_screen.dart';
import 'package:mobile/features/admin/presentation/estimations/admin_estimations_screen.dart';

Map<String, dynamic> _lead(int id, String status, {Map<String, dynamic>? extra}) => {
      'id': id,
      'request_id': 'AC-$id',
      'status': status,
      'customer_name': 'Ravi Kumar',
      'phone': '9876543210',
      'email': '',
      'address': '12 Lake Road, Hosur',
      'preferred_date': '2026-09-30',
      'preferred_time': 'Morning',
      'created_at': '2026-09-29T08:00:00Z',
      'ac_details': {'ac_brand': 'Daikin', 'ac_type': 'Split AC', 'ac_capacity': '1.5_TON', 'ac_quantity': 2, 'customer_symptom': 'Not cooling'},
      'fee': {'status': 'PENDING'},
      'technician': {'name': status == 'REQUESTED' ? null : 'Suresh', 'phone': '9000000000'},
      'rate_card_snapshot': [
        {'id': 1, 'item_name': 'Gas refill', 'category': 'Gas', 'unit': 'kg', 'price': 1850},
      ],
      'findings': [
        {'title': 'Gas leak', 'severity': 'HIGH', 'description': 'Pressure drop', 'recommended_action': 'Braze joint'},
      ],
      ...?extra,
    };

class FakeRepo extends VendorEstimationRepository {
  FakeRepo() : super(Dio());

  final calls = <String>[];
  Object? failList;
  String detailStatus = 'REQUESTED';
  Map<String, dynamic>? detailExtra;

  @override
  Future<VendorEstimationList> list({String status = 'all', String? date, String? search, int? page}) async {
    calls.add('list:$status:${search ?? ''}:${date ?? ''}');
    if (failList != null) throw failList!;
    return VendorEstimationList.fromJson({
      'results': [_lead(1, 'REQUESTED'), _lead(2, 'TECHNICIAN_ASSIGNED')],
      'metrics': {'all': 2, 'requested': 1, 'assigned': 1, 'in_progress': 0, 'quotation_sent': 0, 'completed': 0},
    });
  }

  @override
  Future<VendorEstimation> detail(int id) async => VendorEstimation.fromJson(_lead(id, detailStatus, extra: detailExtra));

  @override
  Future<VendorEstimation> confirm(int id) async {
    calls.add('confirm:$id');
    detailStatus = 'VENDOR_CONFIRMED';
    return VendorEstimation.fromJson(_lead(id, 'VENDOR_CONFIRMED'));
  }

  @override
  Future<VendorEstimation> startJourney(int id) async {
    calls.add('start:$id');
    return VendorEstimation.fromJson(_lead(id, 'TECHNICIAN_ON_THE_WAY'));
  }

  @override
  Future<VendorEstimation> reviseQuotation(int id, int quoteId) async => VendorEstimation.fromJson(_lead(id, 'QUOTATION_SENT'));

  @override
  Future<VendorEstimation> adminReviewQuotation(int id, int quoteId,
      {required String action, required String notes, bool autoConvert = false}) async {
    calls.add('review:$quoteId:$action:$autoConvert');
    return VendorEstimation.fromJson(_lead(id, 'QUOTATION_SENT'));
  }

  @override
  Future<VendorEstimation> progressRepair(int id, String stage) async {
    calls.add('repair:$stage');
    return VendorEstimation.fromJson(_lead(id, 'REPAIR_IN_PROGRESS'));
  }

  @override
  Future<List<VendorTechnician>> technicians() async => const [VendorTechnician(id: '5', name: 'Suresh', phone: '9000000000')];

  @override
  Future<VendorEstimation> assignTechnician(int id, {String? technicianId, required String name, required String phone}) async {
    calls.add('assign:$technicianId:$name');
    return VendorEstimation.fromJson(_lead(id, 'TECHNICIAN_ASSIGNED'));
  }

  @override
  Future<VendorEstimation> verifyOtp(int id, String otp) async {
    calls.add('otp:$otp');
    return VendorEstimation.fromJson(_lead(id, 'INSPECTION_IN_PROGRESS'));
  }

  @override
  Future<void> collectFee(int id, {required String paymentMethod, String reference = ''}) async => calls.add('fee:$paymentMethod');
}

Future<void> _pump(WidgetTester t, FakeRepo repo, Widget screen) async {
  t.view.physicalSize = const Size(900, 3200);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(ProviderScope(
    overrides: [vendorEstimationRepositoryProvider.overrideWithValue(repo)],
    child: MaterialApp(home: screen),
  ));
  await t.pumpAndSettle();
}

void main() {
  test('model parses list payload, metrics and stage titles', () {
    final list = VendorEstimationList.fromJson({
      'results': [_lead(1, 'TECHNICIAN_ASSIGNED')],
      'metrics': {'all': 3},
    });
    expect(list.leads.single.reference, 'AC-1');
    expect(list.leads.single.capacityLabel, '1.5 TON');
    expect(list.metrics!['all'], 3);
    expect(estimationStageTitle(list.leads.single), 'Technician Suresh Assigned — Ready for Journey');
    expect(estimationStatusLabel('TECHNICIAN_ON_THE_WAY'), 'TECHNICIAN ON THE WAY');
  });

  test('money uses Indian grouping', () {
    expect(money(1850), '₹1,850.00');
    expect(money(123456.5), '₹1,23,456.50');
  });

  group('AC Estimations list', () {
    testWidgets('renders header, metrics, tabs and lead cards from the API', (t) async {
      final repo = FakeRepo();
      await _pump(t, repo, const AdminEstimationsScreen());
      expect(find.text('AC Inspection & Quotation Manager'), findsOneWidget);
      expect(find.text('VENDOR PORTAL'), findsOneWidget);
      expect(find.text('Total Leads'), findsOneWidget);
      expect(find.text('All Leads'), findsOneWidget);
      expect(find.text('AC-1'), findsOneWidget);
      expect(find.text('Daikin Split AC'), findsNWidgets(2));
      expect(find.text('Capacity: 1.5 TON • Qty: 2'), findsNWidgets(2));
      expect(find.text('"Not cooling"'), findsNWidgets(2));
      expect(find.text('₹199 PENDING'), findsNWidgets(2));
      expect(find.text('Tech: Suresh'), findsOneWidget);
      expect(repo.calls.first, 'list:all::');
    });

    testWidgets('tab requeries with the Web status id', (t) async {
      final repo = FakeRepo();
      await _pump(t, repo, const AdminEstimationsScreen());
      await t.tap(find.text('New Requests').last);
      await t.pumpAndSettle();
      expect(repo.calls.last, 'list:requested::');
    });

    testWidgets('shows Request failed with the API error', (t) async {
      final repo = FakeRepo()..failList = const VendorEstimationException('Request failed');
      await _pump(t, repo, const AdminEstimationsScreen());
      expect(find.text('Request failed'), findsWidgets);
      expect(find.text('Retry'), findsOneWidget);
    });
  });

  group('AC Estimation lead console', () {
    testWidgets('REQUESTED shows Accept Lead and confirms it', (t) async {
      final repo = FakeRepo();
      await _pump(t, repo, const AdminEstimationDetailScreen(leadId: 1));
      expect(find.text('New Lead Unconfirmed — Vendor Acceptance Required'), findsOneWidget);
      expect(find.text('Ravi Kumar'), findsOneWidget);
      expect(find.text('Gas refill'), findsOneWidget);
      expect(find.text('Gas leak'), findsOneWidget);
      await t.tap(find.text('Accept Lead'));
      await t.pumpAndSettle();
      expect(repo.calls, contains('confirm:1'));
      expect(find.text('Assign Technician'), findsOneWidget);
    });

    testWidgets('assign technician sheet posts the chosen technician', (t) async {
      final repo = FakeRepo()..detailStatus = 'VENDOR_CONFIRMED';
      await _pump(t, repo, const AdminEstimationDetailScreen(leadId: 1));
      await t.tap(find.text('Assign Technician'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField).first, 'Suresh');
      await t.tap(find.text('Confirm Assignment'));
      await t.pumpAndSettle();
      expect(repo.calls, contains('assign:null:Suresh'));
    });

    testWidgets('assigned lead can start the trip', (t) async {
      final repo = FakeRepo()..detailStatus = 'TECHNICIAN_ASSIGNED';
      await _pump(t, repo, const AdminEstimationDetailScreen(leadId: 1));
      expect(find.text('Reassign'), findsOneWidget);
      await t.tap(find.text('Start Trip'));
      await t.pumpAndSettle();
      expect(repo.calls, contains('start:1'));
      expect(find.text('Mark Arrived'), findsOneWidget);
    });

    testWidgets('arrived lead verifies the customer OTP', (t) async {
      final repo = FakeRepo()..detailStatus = 'TECHNICIAN_ARRIVED';
      await _pump(t, repo, const AdminEstimationDetailScreen(leadId: 1));
      await t.tap(find.text('Enter Customer Start OTP'));
      await t.pumpAndSettle();
      final verify = find.widgetWithText(FilledButton, 'Verify & Start Inspection');
      expect(t.widget<FilledButton>(verify).onPressed, isNull);
      await t.enterText(find.byType(TextField).last, '123456');
      await t.pump();
      await t.tap(verify);
      await t.pumpAndSettle();
      expect(repo.calls, contains('otp:123456'));
    });

    testWidgets('quotation awaiting admin review can be approved', (t) async {
      final repo = FakeRepo()
        ..detailStatus = 'INSPECTION_COMPLETED'
        ..detailExtra = {
          'latest_quotation': {
            'id': 9,
            'quote_ref': 'Q-9',
            'version': 1,
            'status': 'SUBMITTED_FOR_ADMIN_REVIEW',
            'total_amount': 2183,
            'tax_amount': 333,
            'items': [
              {'service_name': 'Gas refill', 'item_type': 'GAS', 'quantity': 1, 'unit': 'kg', 'unit_price': 1850},
            ],
          },
        };
      await _pump(t, repo, const AdminEstimationDetailScreen(leadId: 1));
      expect(find.text('Quotation #Q-9 (v1)'), findsOneWidget);
      expect(find.text('₹2,183.00'), findsOneWidget);
      await t.tap(find.text('Approve & Release to Customer'));
      await t.pumpAndSettle();
      await t.tap(find.text('Confirm Approval'));
      await t.pumpAndSettle();
      expect(repo.calls, contains('review:9:APPROVE:false'));
    });

    testWidgets('approved job walks the repair stages and offers fee collection', (t) async {
      final repo = FakeRepo()..detailStatus = 'CUSTOMER_APPROVED';
      await _pump(t, repo, const AdminEstimationDetailScreen(leadId: 1));
      expect(find.textContaining('Approved for AC Repair'), findsOneWidget);
      await t.tap(find.widgetWithText(FilledButton, 'Start Repair'));
      await t.pumpAndSettle();
      expect(repo.calls, contains('repair:START_REPAIR'));
      expect(find.text('Collect / Waive Fee'), findsOneWidget);
    });
  });
}
