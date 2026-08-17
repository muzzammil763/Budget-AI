import 'package:budget_ai/src/storage/local_finance_store.dart';
import 'package:budget_ai/src/storage/local_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('local settings reset preserves only onboarding completion', () async {
    final settings = LocalSettingsStore.instance;
    await settings.setBool('onboarding_completed', true);
    await settings.setString('budget_user_name', 'Previous user');
    await settings.setBool('feature_notifications_enabled', true);
    await settings.setBool('ai_fast_responses_enabled', true);

    await settings.clearExcept({'onboarding_completed'});

    expect(await settings.getBool('onboarding_completed'), isTrue);
    expect(await settings.getString('budget_user_name'), isNull);
    expect(await settings.getBool('feature_notifications_enabled'), isNull);
    expect(await settings.getBool('ai_fast_responses_enabled'), isNull);
  });

  test('local finance reset removes active and deleted rows', () async {
    final finances = LocalFinanceStore.instance;
    finances.resetVolatileFallback();
    await finances.replaceActive([
      {'id': 'previous-user-entry', 'type': 'expense', 'amount': 25},
    ]);

    await finances.clearAll();

    expect(await finances.isEmpty(), isTrue);
    expect(await finances.readActive(), isEmpty);
    expect(await finances.pendingRows(), isEmpty);
  });
}
