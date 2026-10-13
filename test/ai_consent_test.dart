import 'package:budget_ai/src/helpers/app_theme.dart';
import 'package:budget_ai/src/settings/ai_consent.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => AiConsent.debugGranted = null);

  Future<bool?> ask(WidgetTester tester) async {
    AiConsent.debugGranted = false;
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async => result = await AiConsent.ensure(context),
              child: const Text('ask'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('ask'));
    await tester.pumpAndSettle();
    expect(find.text('Before Budget AI replies'), findsOneWidget);
    expect(find.text('What is shared'), findsOneWidget);
    return result;
  }

  testWidgets('agreeing grants consent', (tester) async {
    await ask(tester);
    await tester.ensureVisible(find.byKey(const ValueKey('ai-consent-agree')));
    await tester.tap(find.byKey(const ValueKey('ai-consent-agree')));
    await tester.pumpAndSettle();
    expect(find.text('Before Budget AI replies'), findsNothing);
    expect(await AiConsent.isGranted(), isTrue);
  });

  testWidgets('declining keeps consent off', (tester) async {
    await ask(tester);
    await tester.ensureVisible(
      find.byKey(const ValueKey('ai-consent-decline')),
    );
    await tester.tap(find.byKey(const ValueKey('ai-consent-decline')));
    await tester.pumpAndSettle();
    expect(await AiConsent.isGranted(), isFalse);
  });
}
