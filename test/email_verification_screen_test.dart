import 'package:budget_ai/src/auth/auth_screens.dart';
import 'package:budget_ai/src/helpers/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('code boxes fill as digits are typed', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: EmailVerificationScreen(
            email: 'tester@example.com',
            password: 'secret',
            onUseDifferentEmail: () {},
            onBackToLogin: () {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Enter your code'), findsOneWidget);
    expect(find.textContaining('6-digit code'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('otp-input')), '48a29');
    await tester.pump(const Duration(milliseconds: 300));
    for (final digit in ['4', '8', '2', '9']) {
      expect(find.text(digit), findsOneWidget);
    }
    expect(find.text('a'), findsNothing);
  });
}
