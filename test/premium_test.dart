import 'package:budget_ai/src/billing/bubble_style_access.dart';
import 'package:budget_ai/src/billing/paywall_screen.dart';
import 'package:budget_ai/src/billing/premium_gate.dart';
import 'package:budget_ai/src/chat/chat_provider.dart';
import 'package:budget_ai/src/chat/user_bubble_style_surface.dart';
import 'package:budget_ai/src/billing/subscription_service.dart';
import 'package:budget_ai/src/helpers/app_theme.dart';
import 'package:budget_ai/src/settings/ai_usage_service.dart';
import 'package:budget_ai/src/settings/bubble_style_screen.dart';
import 'package:budget_ai/src/settings/bubble_style_settings_service.dart';
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

  testWidgets('paywall preselects Plus Monthly with yearly inside each plan', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const PaywallScreen(reason: PaywallReason.freeMessageUsed),
      ),
    );
    await tester.pump();

    expect(find.textContaining('Keep your'), findsOneWidget);
    expect(find.textContaining(r'Get Plus · $6.99/month'), findsOneWidget);
    // Only the selected plan opens its Monthly/Yearly options.
    expect(
      find.byKey(const ValueKey('paywall-option-plus-yearly')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('paywall-option-pro-yearly')),
      findsNothing,
    );
    expect(find.text('SAVE 23%'), findsOneWidget);
    expect(find.text('Save 16% when you pay yearly'), findsOneWidget);
    expect(find.text('Save 24% when you pay yearly'), findsOneWidget);
    expect(find.text('Most popular'), findsOneWidget);
    for (final name in ['Free', 'Lite', 'Plus', 'Pro']) {
      expect(find.text(name), findsWidgets);
    }
    expect(find.textContaining('gpt-'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('paywall-plan-pro')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('paywall-option-pro-yearly')));
    await tester.pumpAndSettle();
    expect(find.textContaining(r'Get Pro · $109.99/year'), findsOneWidget);
    await tester.pumpAndSettle();
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

    expect(find.text('Free AI messages used'), findsOneWidget);
    expect(find.textContaining('Plus · 150 AI messages'), findsOneWidget);
    final seePlans = find.byKey(const ValueKey('premium-sheet-see-plans'));
    await tester.ensureVisible(seePlans);
    await tester.pumpAndSettle();
    await tester.tap(seePlans);
    await tester.pumpAndSettle();
    expect(find.byType(PaywallScreen), findsOneWidget);
  });

  test('bubble styles unlock by plan', () {
    PremiumGate.debugPaywallEnabled = true;
    addTearDown(() => PremiumGate.debugPaywallEnabled = null);
    expect(BubbleStyleAccess.presetCount(PremiumTier.free), 2);
    expect(BubbleStyleAccess.presetCount(PremiumTier.lite), 5);
    expect(BubbleStyleAccess.presetCount(PremiumTier.plus), 8);
    expect(BubbleStyleAccess.presetCount(PremiumTier.pro), 11);
    expect(
      BubbleStyleAccess.isUnlocked(UserBubbleStyle.outline, PremiumTier.free),
      isTrue,
    );
    expect(
      BubbleStyleAccess.isUnlocked(UserBubbleStyle.custom, PremiumTier.plus),
      isFalse,
    );

    AiUsageService.instance.usage.value = AiUsageInfo(
      enabled: true,
      messagesUsed: 0,
      messagesLimit: 1,
      tokensUsed: 0,
      tokensLimit: 1000,
      plan: AiPlanTier.free,
      renewsOn: DateTime.utc(2026, 11),
    );
    addTearDown(() => AiUsageService.instance.usage.value = null);
    expect(
      BubbleStyleAccess.effective(UserBubbleStyle.vault),
      UserBubbleStyle.classic,
    );
    expect(
      BubbleStyleAccess.effective(UserBubbleStyle.outline),
      UserBubbleStyle.outline,
    );
    PremiumGate.debugPaywallEnabled = false;
    expect(
      BubbleStyleAccess.effective(UserBubbleStyle.vault),
      UserBubbleStyle.vault,
    );
  });

  testWidgets('locked bubble styles keep previews and open their plan', (
    tester,
  ) async {
    PremiumGate.debugPaywallEnabled = true;
    addTearDown(() => PremiumGate.debugPaywallEnabled = null);
    AiUsageService.instance.usage.value = AiUsageInfo(
      enabled: true,
      messagesUsed: 0,
      messagesLimit: 1,
      tokensUsed: 0,
      tokensLimit: 1000,
      plan: AiPlanTier.free,
      renewsOn: DateTime.utc(2026, 11),
    );
    addTearDown(() => AiUsageService.instance.usage.value = null);
    await tester.binding.setSurfaceSize(const Size(400, 4000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light(), home: const BubbleStyleScreen()),
    );
    await tester.pump();

    expect(find.text('FREE'), findsOneWidget);
    expect(find.text('Unlock with Lite'), findsOneWidget);
    expect(find.text('Unlock with Plus'), findsOneWidget);
    expect(find.text('Unlock with Pro'), findsOneWidget);
    // Every preset still draws its preview bubble, locked or not.
    expect(find.byType(UserBubbleStyleSurface), findsNWidgets(11));

    await tester.tap(find.byKey(const ValueKey('bubble-style-preset:growth')));
    await tester.pumpAndSettle();
    expect(find.byType(PaywallScreen), findsOneWidget);
    expect(find.textContaining(r'Get Plus'), findsOneWidget);
    expect(
      BubbleStyleSettingsService.instance.current,
      UserBubbleStyle.classic,
    );
  });
}
