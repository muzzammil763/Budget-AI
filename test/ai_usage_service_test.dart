import 'package:budget_ai/src/settings/ai_usage_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('compact quota progress follows the limit closest to exhaustion', () {
    final usage = AiUsageInfo(
      enabled: true,
      requestsUsed: 850,
      requestsLimit: 1000,
      tokensUsed: 2500000,
      tokensLimit: 5000000,
      renewsOn: DateTime.utc(2026, 8),
    );

    expect(usage.requestsFraction, 0.85);
    expect(usage.tokensFraction, 0.5);
    expect(usage.quotaFraction, 0.85);
  });

  test('compact quota progress remains clamped at full usage', () {
    final usage = AiUsageInfo(
      enabled: true,
      requestsUsed: 1001,
      requestsLimit: 1000,
      tokensUsed: 5100000,
      tokensLimit: 5000000,
      renewsOn: DateTime.utc(2026, 8),
    );

    expect(usage.quotaFraction, 1);
  });
}
