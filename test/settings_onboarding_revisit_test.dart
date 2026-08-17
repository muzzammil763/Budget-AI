import 'package:budget_ai/src/onboarding/onboarding_screen.dart';
import 'package:budget_ai/src/helpers/app_button.dart';
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

  testWidgets('Budget Hub contains account details and danger actions', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 932));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
    await tester.pump(const Duration(milliseconds: 500));

    expect(
      find.byKey(const ValueKey('settings-account-email')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('settings-account-name')), findsOneWidget);
    expect(find.text('Name'), findsOneWidget);
    expect(find.text('Email unavailable'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('settings-delete-account')),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('DANGER ZONE'), findsOneWidget);
    expect(find.byKey(const ValueKey('settings-sign-out')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('settings-delete-account')),
      findsOneWidget,
    );
  });

  testWidgets('Budget Hub exposes Fast Responses with its pricing tradeoff', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 932));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
    await tester.pump(const Duration(milliseconds: 500));

    await tester.scrollUntilVisible(
      find.text('Fast Responses'),
      400,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text('Fast Responses'), findsOneWidget);
    expect(
      find.text('Lower latency with higher OpenAI token pricing'),
      findsOneWidget,
    );
  });

  testWidgets('account deletion requires the exact custom-keyboard phrase', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 932));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
    await tester.pump(const Duration(milliseconds: 500));
    final deleteAction = find.byKey(const ValueKey('settings-delete-account'));
    await tester.scrollUntilVisible(
      deleteAction,
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -180));
    await tester.pump();
    await tester.tap(deleteAction);
    await tester.pump(const Duration(milliseconds: 500));

    final confirmButton = find.byKey(
      const ValueKey('confirm-delete-account-phrase'),
    );
    expect(find.text('Enter DELETE MY ACCOUNT to continue'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('delete-account-phrase-cursor')),
      findsOneWidget,
    );
    final cursorFinder = find.byKey(
      const ValueKey('delete-account-phrase-cursor'),
    );
    expect(
      tester.getTopLeft(cursorFinder).dx,
      lessThan(tester.getTopLeft(find.text('DELETE MY ACCOUNT')).dx),
    );
    expect(tester.widget<AppButton>(confirmButton).onPressed, isNull);

    final keyboard = tester.widget<InlineNameKeyboard>(
      find.byType(InlineNameKeyboard),
    );
    for (final character in 'DELETE MY ACCOUNT'.characters) {
      if (character == ' ') {
        keyboard.onSpace();
      } else {
        keyboard.onLetter(character);
      }
    }
    await tester.pump();
    expect(
      tester.getTopLeft(cursorFinder).dx,
      greaterThan(tester.getTopLeft(find.text('DELETE MY ACCOUNT')).dx),
    );
    expect(tester.widget<AppButton>(confirmButton).onPressed, isNotNull);

    tester.widget<AppButton>(confirmButton).onPressed!();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('This Cannot Be Undone'), findsOneWidget);
    expect(find.text('Confirm Delete'), findsOneWidget);
  });
}
