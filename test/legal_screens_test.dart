import 'package:budget_ai/src/helpers/app_theme.dart';
import 'package:budget_ai/src/settings/legal_screens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dev.fluttercommunity.plus/package_info'),
          (_) async => {
            'appName': 'Budget AI',
            'packageName': 'com.budgetai',
            'version': '1.0.0',
            'buildNumber': '1',
          },
        );
  });

  Future<void> pump(WidgetTester tester, Widget screen, ThemeData theme) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(theme: theme, home: screen));
    await tester.pumpAndSettle();
  }

  for (final (name, theme) in [
    ('light', AppTheme.light()),
    ('dark', AppTheme.dark()),
  ]) {
    testWidgets('privacy policy renders its sections ($name)', (tester) async {
      await pump(tester, const PrivacyPolicyScreen(), theme);
      expect(find.text('PRIVACY POLICY'), findsOneWidget);
      expect(find.text('No ads or tracking'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Questions?'), 300);
      expect(find.text('Questions?'), findsOneWidget);
    });

    testWidgets('terms render their sections ($name)', (tester) async {
      await pump(tester, const TermsScreen(), theme);
      expect(find.text('TERMS & CONDITIONS'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Not financial advice'), 300);
      expect(find.text('Not financial advice'), findsOneWidget);
    });

    testWidgets('about shows the version and support email ($name)', (
      tester,
    ) async {
      await pump(tester, const AboutBudgetAiScreen(), theme);
      expect(find.text('Version 1.0.0 (1)'), findsOneWidget);
      await tester.scrollUntilVisible(find.text(kSupportEmail), 300);
      expect(find.text(kSupportEmail), findsOneWidget);
    });
  }
}
