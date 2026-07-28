import 'package:budget_ai/src/settings/account_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('account screen shows profile and security actions', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AccountScreen(
          nameEditor: SizedBox(key: ValueKey('account-name-editor')),
        ),
      ),
    );

    expect(find.text('Account'), findsOneWidget);
    expect(find.byKey(const ValueKey('account-name-editor')), findsOneWidget);
    expect(find.text('Budget AI account'), findsOneWidget);
    expect(find.text('Email unavailable'), findsOneWidget);
    expect(find.text('Change password'), findsOneWidget);
    expect(find.textContaining('Send a secure reset link'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Sign Out'),
      200,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text('Sign Out'), findsOneWidget);
  });
}
