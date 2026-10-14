import 'package:budget_ai/src/settings/ai_usage_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('compact quota progress follows the limit closest to exhaustion', () {
    final usage = AiUsageInfo(
      enabled: true,
      messagesUsed: 850,
      messagesLimit: 1000,
      tokensUsed: 2500000,
      tokensLimit: 5000000,
      renewsOn: DateTime.utc(2026, 8),
    );

    expect(usage.messagesFraction, 0.85);
    expect(usage.tokensFraction, 0.5);
    expect(usage.quotaFraction, 0.85);
  });

  test('compact quota progress remains clamped at full usage', () {
    final usage = AiUsageInfo(
      enabled: true,
      messagesUsed: 1001,
      messagesLimit: 1000,
      tokensUsed: 5100000,
      tokensLimit: 5000000,
      renewsOn: DateTime.utc(2026, 8),
    );

    expect(usage.quotaFraction, 1);
  });

  test('plan rows map to tiers and exhausted free messages', () {
    final usage = AiUsageInfo.fromPlanRow({
      'plan_tier': 'free',
      'enabled': true,
      'messages_used': 1,
      'message_limit': 1,
      'tokens_used': 1200,
      'token_limit': 60000,
    }, DateTime.utc(2026, 11));

    expect(usage.plan, AiPlanTier.free);
    expect(usage.isPaid, isFalse);
    expect(usage.blocksNewMessage, isTrue);

    final pro = AiUsageInfo.fromPlanRow({
      'plan_tier': 'pro',
      'messages_used': 10,
      'message_limit': 250,
      'token_limit': 1250000,
      'deep_limit': 50,
      'status': 'active',
    }, DateTime.utc(2026, 11));
    expect(pro.isPaid, isTrue);
    expect(pro.blocksNewMessage, isFalse);
    expect(pro.subscriptionExpiresAt, isNull);
  });
}
