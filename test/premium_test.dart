import 'package:budget_ai/src/billing/paywall_screen.dart';
import 'package:budget_ai/src/billing/premium_gate.dart';
import 'package:budget_ai/src/chat/chat_provider.dart';
import 'package:budget_ai/src/billing/subscription_service.dart';
import 'package:budget_ai/src/helpers/app_theme.dart';
import 'package:budget_ai/src/speech/openai_speech_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

void main() {
  test('Play products map to tiers and base plans', () {
    expect(
      SubscriptionService.planFor('budget_ai_plus:yearly', PackageType.custom),
      (PremiumTier.plus, PremiumPeriod.yearly),
    );
    expect(SubscriptionService.planFor('budget_ai_lite', PackageType.monthly), (
      PremiumTier.lite,
      PremiumPeriod.monthly,
    ));
    expect(
      SubscriptionService.planFor('budget_ai_pro:monthly', PackageType.annual),
      (PremiumTier.pro, PremiumPeriod.monthly),
    );
    expect(
      SubscriptionService.planFor('other_product', PackageType.monthly),
      isNull,
    );
  });

  test('speech 402 refusals become premium refusals', () {
    final refusal = premiumRefusalFrom(402, {
      'code': 'plan_limit_reached',
      'message': 'Limit reached',
    });
    expect(refusal?.code, 'plan_limit_reached');
    expect(refusal?.isFreeLimit, isFalse);
    expect(premiumRefusalFrom(429, {'code': 'premium_required'}), isNull);
    expect(premiumRefusalFrom(402, 'text'), isNull);
  });

  testWidgets('paywall preselects Yearly Plus and compares every plan', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const PaywallScreen(reason: PaywallReason.freeMessageUsed),
      ),
    );
    await tester.pump();

    expect(find.textContaining('Keep chatting'), findsOneWidget);
    expect(find.textContaining('Continue with Plus'), findsOneWidget);
    expect(find.textContaining(r'$79.99'), findsWidgets);
    for (final name in ['Free', 'Lite', 'Plus', 'Pro']) {
      expect(find.text(name), findsWidgets);
    }
    expect(find.text('Most popular'), findsOneWidget);
    expect(find.textContaining('gpt-'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('paywall-period-monthly')));
    await tester.tap(find.byKey(const ValueKey('paywall-plan-pro')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.textContaining(r'Continue with Pro · $12.99/mo'),
      findsOneWidget,
    );
  });

  testWidgets('a free-limit refusal shows the Premium sheet, not an error', (
    tester,
  ) async {
    PremiumGate.debugPaywallEnabled = true;
    addTearDown(() => PremiumGate.debugPaywallEnabled = null);
    await tester.binding.setSurfaceSize(const Size(400, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Builder(
          builder: (c) {
            context = c;
            return const Scaffold();
          },
        ),
      ),
    );

    PremiumGate.handleRefusal(
      context,
      PremiumRequiredException(
        providerName: 'OpenAI',
        code: 'premium_required',
        userMessage: 'Free message used',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Free AI message used'), findsOneWidget);
    expect(find.textContaining('Plus · 200 AI messages'), findsOneWidget);
    final seePlans = find.byKey(const ValueKey('premium-sheet-see-plans'));
    await tester.ensureVisible(seePlans);
    await tester.pumpAndSettle();
    await tester.tap(seePlans);
    await tester.pumpAndSettle();
    expect(find.byType(PaywallScreen), findsOneWidget);
  });
}
