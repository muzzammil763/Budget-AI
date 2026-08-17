import 'package:budget_ai/src/settings/ai_response_settings_service.dart';
import 'package:budget_ai/src/storage/local_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Fast responses defaults off and persists both toggle states', () async {
    final settings = LocalSettingsStore.instance;
    final service = AiResponseSettingsService.instance;
    await settings.clearExcept(const {});

    await service.load();
    expect(service.fastResponsesEnabled.value, isFalse);

    await service.setFastResponsesEnabled(true);
    service.fastResponsesEnabled.value = false;
    await service.load();
    expect(service.fastResponsesEnabled.value, isTrue);

    await service.setFastResponsesEnabled(false);
    service.fastResponsesEnabled.value = true;
    await service.load();
    expect(service.fastResponsesEnabled.value, isFalse);
  });
}
