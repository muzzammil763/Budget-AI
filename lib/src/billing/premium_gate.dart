import 'package:budget_ai/src/billing/paywall_screen.dart';
import 'package:budget_ai/src/billing/subscription_service.dart';
import 'package:budget_ai/src/chat/chat_provider.dart';
import 'package:budget_ai/src/helpers/toast_helper.dart';
import 'package:budget_ai/src/settings/ai_usage_service.dart';
import 'package:flutter/material.dart';
import 'package:toastification/toastification.dart';

/// Decides whether a new AI message (chat, voice, receipt, Monthly Summary)
/// may start, and answers refusals with the paywall. The server enforces the
/// limits either way; this only avoids a wasted round trip.
class PremiumGate {
  PremiumGate._();

  /// Premium is sold on Android only; iOS keeps its legacy limits.
  static bool get paywallEnabled => AiUsageService.clientPlatform == 'android';

  /// True when the next AI message can start. Otherwise shows the paywall
  /// (or the reset date on the top plan) and returns whether a purchase
  /// unlocked it.
  static Future<bool> ensure(BuildContext context) async {
    final info = AiUsageService.instance.usage.value;
    if (!paywallEnabled || info == null || !info.enabled) return true;
    if (!info.blocksNewMessage) return true;
    // RevenueCat can report a purchase before its webhook reaches the server.
    if (!info.isPaid &&
        SubscriptionService.instance.tier.value != PremiumTier.free) {
      return true;
    }
    return _block(context, info);
  }

  /// Applies a server refusal (HTTP 402) the app could not predict.
  static Future<void> handleRefusal(
    BuildContext context,
    PremiumRequiredException error,
  ) async {
    AiUsageService.instance.markMessagesExhausted();
    final info = AiUsageService.instance.usage.value;
    if (!paywallEnabled) return;
    await _block(context, info, freeLimit: error.isFreeLimit);
  }

  static Future<bool> _block(
    BuildContext context,
    AiUsageInfo? info, {
    bool? freeLimit,
  }) async {
    final isFree = freeLimit ?? !(info?.isPaid ?? false);
    if (!isFree && info?.plan == AiPlanTier.pro) {
      showAppToast(
        context,
        message:
            "You've used this month's AI messages. Your limit resets on "
            '${resetDateLabel(info!.renewsOn)}.',
        type: ToastificationType.info,
      );
      return false;
    }
    return PaywallScreen.show(
      context,
      reason: isFree
          ? PaywallReason.freeMessageUsed
          : PaywallReason.planLimitReached,
    );
  }

  static String resetDateLabel(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}';
  }
}
