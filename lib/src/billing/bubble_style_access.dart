import 'package:budget_ai/src/billing/premium_gate.dart';
import 'package:budget_ai/src/billing/subscription_service.dart';
import 'package:budget_ai/src/settings/ai_usage_service.dart';
import 'package:budget_ai/src/settings/bubble_style_settings_service.dart';

/// Which message bubble styles each Premium plan unlocks. Free keeps Classic
/// and Outline; every higher plan adds three presets, and Pro also unlocks
/// custom styles. Without the paywall (iOS) every style stays available.
class BubbleStyleAccess {
  BubbleStyleAccess._();

  static PremiumTier requiredTier(UserBubbleStyle style) => switch (style) {
    UserBubbleStyle.classic || UserBubbleStyle.outline => PremiumTier.free,
    UserBubbleStyle.ledger ||
    UserBubbleStyle.savings ||
    UserBubbleStyle.cashFlow => PremiumTier.lite,
    UserBubbleStyle.growth ||
    UserBubbleStyle.receipt ||
    UserBubbleStyle.nightBudget => PremiumTier.plus,
    UserBubbleStyle.vault ||
    UserBubbleStyle.paperCurl ||
    UserBubbleStyle.sketchFrame ||
    UserBubbleStyle.custom => PremiumTier.pro,
  };

  /// The plan bubble styles are judged against. Until the plan loads nothing
  /// is locked, so a paying user never sees their style flicker away.
  static PremiumTier get currentTier {
    if (!PremiumGate.paywallEnabled) return PremiumTier.pro;
    final usage = AiUsageService.instance.usage.value;
    if (usage == null) return PremiumTier.pro;
    return PremiumGate.tierOf(usage);
  }

  static bool isUnlocked(UserBubbleStyle style, [PremiumTier? tier]) =>
      requiredTier(style).index <= (tier ?? currentTier).index;

  /// The style chat actually draws: a style from a lapsed plan falls back to
  /// Classic while staying saved, so it returns if the plan comes back.
  static UserBubbleStyle effective(UserBubbleStyle selected) =>
      isUnlocked(selected) ? selected : UserBubbleStyle.classic;

  /// Preset styles available on [tier], for plan summaries.
  static int presetCount(PremiumTier tier) => UserBubbleStyle.values
      .where(
        (style) => style != UserBubbleStyle.custom && isUnlocked(style, tier),
      )
      .length;
}
