import 'package:budget_ai/src/banking/connected_banks_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Plaid launch overlay blurs and reports secure loading state', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              TextButton(onPressed: null, child: Text('Underlying action')),
              BankLaunchOverlay(),
            ],
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('bank-connect-loading-overlay')),
      findsOneWidget,
    );
    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Opening Plaid'), findsOneWidget);
    expect(find.text('Preparing your secure bank connection…'), findsOneWidget);
  });
}
