import 'package:budget_ai/src/onboarding/onboarding_screen.dart';
import 'package:budget_ai/src/settings/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const packageInfoChannel = MethodChannel(
    'dev.fluttercommunity.plus/package_info',
  );
  const permissionsChannel = MethodChannel(
    'flutter.baseflow.com/permissions/methods',
  );

  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(packageInfoChannel, (_) async {
          return {
            'appName': 'Budget AI',
            'packageName': 'com.example.budget_ai',
            'version': '1.0.0',
            'buildNumber': '1',
            'buildSignature': '',
            'installerStore': null,
          };
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(permissionsChannel, (_) async => 1);
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(packageInfoChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(permissionsChannel, null);
  });

  testWidgets('Budget Hub launches onboarding in revisit mode', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 932));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('replay-onboarding')),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const ValueKey('replay-onboarding')));
    final onboarding = find.byType(OnboardingScreen);
    for (
      var attempt = 0;
      attempt < 20 && onboarding.evaluate().isEmpty;
      attempt++
    ) {
      await tester.pump(const Duration(milliseconds: 250));
    }

    expect(onboarding, findsOneWidget);
    expect(tester.widget<OnboardingScreen>(onboarding).isRevisit, isTrue);
  });
}
