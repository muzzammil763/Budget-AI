import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Server-side plan names. `legacy` is iOS before it has a paywall: the old
/// default limits with no Premium prompts.
enum AiPlanTier { free, lite, plus, pro, legacy }

class AiUsageInfo {
  const AiUsageInfo({
    required this.enabled,
    required this.messagesUsed,
    required this.messagesLimit,
    required this.tokensUsed,
    required this.tokensLimit,
    this.fastRequestsUsed = 0,
    this.fastRequestsLimit = 100,
    this.deepUsed = 0,
    this.deepLimit = 0,
    this.plan = AiPlanTier.legacy,
    this.subscriptionStatus,
    this.subscriptionPeriod,
    this.subscriptionExpiresAt,
    this.willRenew = false,
    this.isWeekly = false,
    required this.renewsOn,
  });

  final bool enabled;

  /// AI messages this month. One message is one user turn, including its tool
  /// rounds, voice transcription, and receipt analysis.
  final int messagesUsed;
  final int messagesLimit;
  final int tokensUsed;
  final int tokensLimit;
  final int fastRequestsUsed;
  final int fastRequestsLimit;
  final int deepUsed;
  final int deepLimit;
  final AiPlanTier plan;
  final String? subscriptionStatus;
  final String? subscriptionPeriod;

  /// Null with an active status means complimentary (never expires).
  final DateTime? subscriptionExpiresAt;
  final bool willRenew;

  /// Weekly subscribers count usage in their paid week, which resets on
  /// [renewsOn], instead of the calendar month.
  final bool isWeekly;

  /// "week" or "month", for usage copy.
  String get periodNoun => isWeekly ? 'week' : 'month';

  /// When usage resets: the next paid week for weekly plans, otherwise the
  /// first day of next month (UTC).
  final DateTime renewsOn;

  bool get isPaid =>
      plan == AiPlanTier.lite ||
      plan == AiPlanTier.plus ||
      plan == AiPlanTier.pro;

  bool get messagesExhausted => messagesUsed >= messagesLimit;

  bool get tokensExhausted => tokensUsed >= tokensLimit;

  /// The next new AI message would be refused by the server.
  bool get blocksNewMessage => !enabled || messagesExhausted || tokensExhausted;

  double get messagesFraction =>
      messagesLimit <= 0 ? 1 : (messagesUsed / messagesLimit).clamp(0, 1);

  double get tokensFraction =>
      tokensLimit <= 0 ? 1 : (tokensUsed / tokensLimit).clamp(0, 1);

  /// One operational progress value for compact surfaces. Whichever quota is
  /// closer to exhaustion governs whether the next AI message can run.
  double get quotaFraction =>
      messagesFraction >= tokensFraction ? messagesFraction : tokensFraction;

  AiUsageInfo copyWith({int? messagesUsed}) => AiUsageInfo(
    enabled: enabled,
    messagesUsed: messagesUsed ?? this.messagesUsed,
    messagesLimit: messagesLimit,
    tokensUsed: tokensUsed,
    tokensLimit: tokensLimit,
    fastRequestsUsed: fastRequestsUsed,
    fastRequestsLimit: fastRequestsLimit,
    deepUsed: deepUsed,
    deepLimit: deepLimit,
    plan: plan,
    subscriptionStatus: subscriptionStatus,
    subscriptionPeriod: subscriptionPeriod,
    subscriptionExpiresAt: subscriptionExpiresAt,
    willRenew: willRenew,
    isWeekly: isWeekly,
    renewsOn: renewsOn,
  );

  @visibleForTesting
  static AiUsageInfo fromPlanRow(Map<String, dynamic> row, DateTime renewsOn) {
    int count(String key) => (row[key] as num?)?.toInt() ?? 0;
    return AiUsageInfo(
      enabled: row['enabled'] as bool? ?? true,
      messagesUsed: count('messages_used'),
      messagesLimit: count('message_limit'),
      tokensUsed: count('tokens_used'),
      tokensLimit: count('token_limit'),
      fastRequestsUsed: count('fast_used'),
      fastRequestsLimit: count('fast_limit'),
      deepUsed: count('deep_used'),
      deepLimit: count('deep_limit'),
      plan: AiPlanTier.values.firstWhere(
        (tier) => tier.name == row['plan_tier'],
        orElse: () => AiPlanTier.free,
      ),
      subscriptionStatus: row['status'] as String?,
      subscriptionPeriod: row['period'] as String?,
      subscriptionExpiresAt: DateTime.tryParse(
        row['expires_at'] as String? ?? '',
      ),
      willRenew: row['will_renew'] as bool? ?? false,
      isWeekly: row['usage_window'] == 'week',
      renewsOn:
          DateTime.tryParse(row['resets_at'] as String? ?? '') ?? renewsOn,
    );
  }
}

/// Reads the signed-in user's AI plan and this month's (or paid week's) usage from
/// the `get_my_ai_plan` RPC. The server enforces the same numbers; the app
/// only uses them for the paywall, Budget Hub, and the usage sheet.
class AiUsageService {
  AiUsageService._();

  static final AiUsageService instance = AiUsageService._();

  /// Sent as `x-client-platform` so the server can apply the platform's plan
  /// rules (iOS has no paywall yet).
  static String get clientPlatform {
    if (kIsWeb) return 'web';
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    return 'other';
  }

  final ValueNotifier<AiUsageInfo?> usage = ValueNotifier<AiUsageInfo?>(null);
  final ValueNotifier<bool> isLoading = ValueNotifier<bool>(false);

  Future<void> refresh() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      usage.value = null;
      return;
    }

    isLoading.value = true;
    try {
      final rows = await Supabase.instance.client.rpc(
        'get_my_ai_plan',
        params: {'p_platform': clientPlatform},
      );
      final row = rows is List && rows.isNotEmpty ? rows.first : null;
      if (row is Map<String, dynamic>) {
        usage.value = AiUsageInfo.fromPlanRow(row, _startOfNextMonthUtc());
      }
    } finally {
      isLoading.value = false;
    }
  }

  /// Applies a refusal from the server without waiting for a refresh.
  void markMessagesExhausted() {
    final current = usage.value;
    if (current == null) return;
    usage.value = current.copyWith(messagesUsed: current.messagesLimit);
  }

  DateTime _startOfNextMonthUtc() {
    final now = DateTime.now().toUtc();
    return now.month == 12
        ? DateTime.utc(now.year + 1, 1, 1)
        : DateTime.utc(now.year, now.month + 1, 1);
  }
}
