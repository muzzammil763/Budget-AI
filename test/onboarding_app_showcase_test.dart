import 'package:budget_ai/src/onboarding/onboarding_app_showcase.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('live onboarding demos animate without layout errors', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final brightness in Brightness.values) {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            brightness: brightness,
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF6558E8),
              brightness: brightness,
            ),
          ),
          home: const Scaffold(body: OnboardingAppShowcase()),
        ),
      );

      for (final duration in const [
        Duration(milliseconds: 1800),
        Duration(milliseconds: 1800),
        Duration(milliseconds: 2400),
        Duration(milliseconds: 2400),
        Duration(milliseconds: 2400),
      ]) {
        await tester.pump(duration);
        expect(tester.takeException(), isNull);
      }
    }
  });
}
