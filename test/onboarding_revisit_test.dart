import 'package:budget_ai/src/onboarding/onboarding_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'revisited onboarding returns to its launcher from Back and Done',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 932));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const OnboardingScreen(isRevisit: true),
                  ),
                ),
                child: const Text('Open onboarding'),
              ),
            ),
          ),
        ),
      );

      Future<void> openOnboarding() async {
        await tester.tap(find.text('Open onboarding'));
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
      }

      await openOnboarding();
      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Open onboarding'), findsOneWidget);

      await openOnboarding();
      final pageView = tester.widget<PageView>(find.byType(PageView));
      pageView.controller!.jumpToPage(4);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.text('Done'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Open onboarding'), findsOneWidget);
      expect(find.byType(OnboardingScreen), findsNothing);
    },
  );
}
