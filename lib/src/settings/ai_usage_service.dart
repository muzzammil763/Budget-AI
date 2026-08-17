import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AiUsageInfo {
  const AiUsageInfo({
    required this.enabled,
    required this.requestsUsed,
    required this.requestsLimit,
    required this.tokensUsed,
    required this.tokensLimit,
    this.fastRequestsUsed = 0,
    this.fastRequestsLimit = 100,
    required this.renewsOn,
  });

  final bool enabled;
  final int requestsUsed;
  final int requestsLimit;
  final int tokensUsed;
  final int tokensLimit;
  final int fastRequestsUsed;
  final int fastRequestsLimit;

  /// First day of next month (UTC) — when usage resets, since limits are
  /// enforced per UTC calendar month on the backend.
  final DateTime renewsOn;

  double get requestsFraction =>
      requestsLimit <= 0 ? 0 : (requestsUsed / requestsLimit).clamp(0, 1);

  double get tokensFraction =>
      tokensLimit <= 0 ? 0 : (tokensUsed / tokensLimit).clamp(0, 1);

  /// One operational progress value for compact surfaces. Whichever quota is
  /// closer to exhaustion governs whether the next AI request can run.
  double get quotaFraction =>
      requestsFraction >= tokensFraction ? requestsFraction : tokensFraction;
}

/// Reads this calendar month's AI usage against the user's monthly limits
/// directly from Supabase. Both `ai_usage_monthly` and `ai_user_limits`
/// already grant each authenticated user select access to their own row via
/// RLS, so no edge function or extra backend surface is needed for a
/// read-only display.
class AiUsageService {
  AiUsageService._();

  static final AiUsageService instance = AiUsageService._();

  static const int _defaultRequestLimit = 1000;
  static const int _defaultTokenLimit = 5000000;

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
      final currentMonth = _currentMonthUtc();
      final client = Supabase.instance.client;

      final results = await Future.wait([
        client
            .from('ai_usage_monthly')
            .select(
              'request_count, input_tokens, output_tokens, fast_request_count',
            )
            .eq('user_id', userId)
            .eq('usage_month', currentMonth)
            .maybeSingle(),
        client
            .from('ai_user_limits')
            .select(
              'enabled, monthly_request_limit, monthly_token_limit, '
              'monthly_fast_request_limit',
            )
            .eq('user_id', userId)
            .maybeSingle(),
      ]);

      final usageRow = results[0];
      final limitsRow = results[1];

      usage.value = AiUsageInfo(
        enabled: limitsRow?['enabled'] as bool? ?? true,
        requestsUsed: (usageRow?['request_count'] as num?)?.toInt() ?? 0,
        requestsLimit:
            (limitsRow?['monthly_request_limit'] as num?)?.toInt() ??
            _defaultRequestLimit,
        tokensUsed:
            ((usageRow?['input_tokens'] as num?)?.toInt() ?? 0) +
            ((usageRow?['output_tokens'] as num?)?.toInt() ?? 0),
        tokensLimit:
            (limitsRow?['monthly_token_limit'] as num?)?.toInt() ??
            _defaultTokenLimit,
        fastRequestsUsed:
            (usageRow?['fast_request_count'] as num?)?.toInt() ?? 0,
        fastRequestsLimit:
            (limitsRow?['monthly_fast_request_limit'] as num?)?.toInt() ?? 100,
        renewsOn: _startOfNextMonthUtc(),
      );
    } finally {
      isLoading.value = false;
    }
  }

  String _currentMonthUtc() {
    final now = DateTime.now().toUtc();
    final month = now.month.toString().padLeft(2, '0');
    return '${now.year}-$month-01';
  }

  DateTime _startOfNextMonthUtc() {
    final now = DateTime.now().toUtc();
    return now.month == 12
        ? DateTime.utc(now.year + 1, 1, 1)
        : DateTime.utc(now.year, now.month + 1, 1);
  }
}
