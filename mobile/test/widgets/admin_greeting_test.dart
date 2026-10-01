import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/shared/widgets/admin_greeting.dart';

void main() {
  test('nameFor uses the first name and falls back to Admin', () {
    expect(AdminGreeting.nameFor('Preethi'), 'Preethi');
    expect(AdminGreeting.nameFor('  '), 'Admin');
    expect(AdminGreeting.nameFor(null), 'Admin');
  });

  test('timeLabel formats 12-hour clock', () {
    expect(AdminGreeting.timeLabel(DateTime(2026, 9, 29, 16, 14)), '4:14 PM');
    expect(AdminGreeting.timeLabel(DateTime(2026, 9, 29, 0, 5)), '12:05 AM');
    expect(AdminGreeting.timeLabel(DateTime(2026, 9, 29, 12, 0)), '12:00 PM');
  });

  testWidgets('shows greeting, summary, Live pill and updated time', (tester) async {
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: Scaffold(body: AdminGreeting(updatedAt: DateTime(2026, 9, 29, 16, 14))),
      ),
    ));
    expect(find.text('Hello, Admin'), findsOneWidget);
    expect(find.text("Here's what's happening with your workforce today."), findsOneWidget);
    expect(find.text('Live'), findsOneWidget);
    expect(find.text('Updated 4:14 PM'), findsOneWidget);
  });
}
