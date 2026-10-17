import 'package:budget_ai/src/billing/subscription_service.dart';
import 'package:flutter/painting.dart';

/// Each tier's accent, matching its Google Play subscription icon.
Color premiumTierAccent(PremiumTier tier) => switch (tier) {
  PremiumTier.lite => const Color(0xFF448AFF),
  PremiumTier.plus => const Color(0xFF8B5CF6),
  PremiumTier.pro => const Color(0xFFF2A51A),
  PremiumTier.free => const Color(0xFF448AFF),
};

Color premiumTierAccentDeep(PremiumTier tier) => switch (tier) {
  PremiumTier.lite => const Color(0xFF2E5FB8),
  PremiumTier.plus => const Color(0xFF6D3FE0),
  PremiumTier.pro => const Color(0xFFD9820B),
  PremiumTier.free => const Color(0xFF2E5FB8),
};

/// What each Budget AI plan includes, shown on the paywall and in Budget Hub.
/// The server's `plan_limits` table enforces the same numbers.
class PremiumPlanInfo {
  const PremiumPlanInfo({
    required this.tier,
    required this.name,
    required this.aiName,
    required this.messages,
    required this.fastReplies,
    required this.deepAnalysis,
    required this.fallbackMonthly,
    required this.fallbackYearly,
  });

  final PremiumTier tier;
  final String name;

  /// User-facing model name. Raw model ids are never shown.
  final String aiName;
  final int messages;
  final int fastReplies;
  final int deepAnalysis;

  /// Shown only until Google Play's localized prices load.
  final String fallbackMonthly;
  final String fallbackYearly;

  static const free = PremiumPlanInfo(
    tier: PremiumTier.free,
    name: 'Free',
    aiName: 'Swift AI',
    messages: 5,
    fastReplies: 0,
    deepAnalysis: 0,
    fallbackMonthly: r'$0',
    fallbackYearly: r'$0',
  );

  static const lite = PremiumPlanInfo(
    tier: PremiumTier.lite,
    name: 'Lite',
    aiName: 'Swift AI',
    messages: 100,
    fastReplies: 0,
    deepAnalysis: 0,
    fallbackMonthly: r'$1.99',
    fallbackYearly: r'$19.99',
  );

  static const plus = PremiumPlanInfo(
    tier: PremiumTier.plus,
    name: 'Plus',
    aiName: 'Smart AI',
    messages: 150,
    fastReplies: 15,
    deepAnalysis: 0,
    fallbackMonthly: r'$6.99',
    fallbackYearly: r'$64.99',
  );

  static const pro = PremiumPlanInfo(
    tier: PremiumTier.pro,
    name: 'Pro',
    aiName: 'Smart AI',
    messages: 160,
    fastReplies: 20,
    deepAnalysis: 30,
    fallbackMonthly: r'$9.99',
    fallbackYearly: r'$94.99',
  );

  static const paid = [lite, plus, pro];

  static PremiumPlanInfo of(PremiumTier tier) => switch (tier) {
    PremiumTier.free => free,
    PremiumTier.lite => lite,
    PremiumTier.plus => plus,
    PremiumTier.pro => pro,
  };
}
