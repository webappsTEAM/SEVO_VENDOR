import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/jobs/data/job_actions_repository.dart';
import 'package:mobile/features/jobs/domain/job.dart';
import 'package:mobile/features/jobs/domain/job_payment.dart';
import 'package:mobile/features/jobs/presentation/widgets/cash_collection_sheet.dart';
import 'package:mobile/shared/widgets/otp_input_field.dart';

class FakeJobActionsRepository implements JobActionsRepository {
  bool collectCashCalled = false;
  bool verifyOtpCalled = false;
  String? lastVerifiedOtp;

  CashCollectionResult collectResult = const CashCollectionResult(
    message: 'Cash collection recorded.',
    paymentStatus: 'CASH_PENDING',
    amountDue: 500.0,
    amountReceived: 500.0,
    changeReturned: 0.0,
  );

  @override
  Future<CashCollectionResult> collectCash(int jobId, double amountReceived) async {
    collectCashCalled = true;
    return collectResult;
  }

  @override
  Future<String> verifyPaymentOtp(int jobId, String otp) async {
    verifyOtpCalled = true;
    lastVerifiedOtp = otp;
    return 'Payment verified.';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final testJob = Job(
  id: 42,
  requestId: '#REQ-0042',
  serviceTitle: 'Ceiling Fan Installation',
  status: 'in_progress',
  totalAmount: 500.0,
  isOffer: false,
  isAcceptedByCurrentEmployee: true,
  isAssignedToCurrentEmployee: true,
  canCancel: false,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('CashCollectionSheet transitions to OTP step when CASH_PENDING returned', (tester) async {
    final fakeRepo = FakeJobActionsRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          jobActionsRepositoryProvider.overrideWithValue(fakeRepo),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => CashCollectionSheet.show(context, testJob),
                child: const Text('Open Sheet'),
              ),
            ),
          ),
        ),
      ),
    );

    // 1. Open the Cash Collection Sheet
    await tester.tap(find.text('Open Sheet'));
    await tester.pumpAndSettle();

    expect(find.text('Collect Cash — #REQ-0042'), findsOneWidget);
    expect(find.text('CONFIRM CASH RECEIVED'), findsOneWidget);
    expect(find.text('Amount Due:'), findsOneWidget);

    // 2. Tap Confirm Cash Received
    await tester.tap(find.text('CONFIRM CASH RECEIVED'));
    await tester.pumpAndSettle();

    expect(fakeRepo.collectCashCalled, isTrue);

    // 3. Verify that Step 2 OTP is immediately shown
    expect(find.text('Verify Payment OTP — #REQ-0042'), findsOneWidget);
    expect(find.text('Customer Confirmation Code Required'), findsOneWidget);
    expect(find.byType(OtpInputField), findsOneWidget);
    expect(find.text('VERIFY & COMPLETE'), findsOneWidget);

    // 4. Enter 6-digit OTP and submit
    final textFields = find.descendant(of: find.byType(OtpInputField), matching: find.byType(TextField));
    expect(textFields, findsNWidgets(6));

    for (int i = 0; i < 6; i++) {
      await tester.enterText(textFields.at(i), '${i + 1}');
    }
    await tester.pump();

    // Verify & Complete button should now be enabled
    await tester.tap(find.text('VERIFY & COMPLETE'));
    await tester.pumpAndSettle();

    expect(fakeRepo.verifyOtpCalled, isTrue);
    expect(fakeRepo.lastVerifiedOtp, equals('123456'));
    expect(find.text('Payment verified.'), findsOneWidget);
  });

  testWidgets('CashCollectionSheet immediately closes on PAID status with success SnackBar', (tester) async {
    final fakeRepo = FakeJobActionsRepository();
    fakeRepo.collectResult = const CashCollectionResult(
      message: 'Cash payment confirmed! Job is COMPLETED.',
      paymentStatus: 'PAID',
      amountDue: 500.0,
      amountReceived: 500.0,
      changeReturned: 0.0,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          jobActionsRepositoryProvider.overrideWithValue(fakeRepo),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => CashCollectionSheet.show(context, testJob),
                child: const Text('Open Sheet'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Sheet'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('CONFIRM CASH RECEIVED'));
    await tester.pumpAndSettle();

    expect(fakeRepo.collectCashCalled, isTrue);
    expect(find.text('Verify Payment OTP — #REQ-0042'), findsNothing);
    expect(find.text('Cash payment confirmed! Job is COMPLETED.'), findsOneWidget);
  });
}
