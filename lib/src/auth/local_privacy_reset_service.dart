import 'package:budget_ai/src/chat/chat_session_repository.dart';
import 'package:budget_ai/src/finances/finance_service.dart';
import 'package:budget_ai/src/helpers/android_background_chat_service.dart';
import 'package:budget_ai/src/helpers/notification_service.dart';
import 'package:budget_ai/src/settings/bubble_style_settings_service.dart';
import 'package:budget_ai/src/settings/ai_response_settings_service.dart';
import 'package:budget_ai/src/settings/currency_settings_service.dart';
import 'package:budget_ai/src/settings/permission_preferences_service.dart';
import 'package:budget_ai/src/settings/user_name_settings_service.dart';
import 'package:budget_ai/src/speech/local_speech_model_manager.dart';
import 'package:budget_ai/src/storage/local_settings_store.dart';
import 'package:budget_ai/src/sync/account_encryption_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocalPrivacyResetService {
  LocalPrivacyResetService._();

  static const _onboardingCompletedKey = 'onboarding_completed';

  static Future<void> clearAfterAccountExit({String? userId}) async {
    await ChatSessionRepository.instance.deleteAllSessions();
    await AndroidBackgroundChatService.stop();
    await NotificationService.instance.clearForAccountExit();
    await FinanceService.instance.clearLocalData();
    if (userId != null) {
      await AccountEncryptionService.instance.clearDataKey(userId);
    }

    // Legacy preferences are cleared as well so a later migration can never
    // restore data belonging to the signed-out user.
    await SharedPreferencesAsync().clear();
    await LocalSettingsStore.instance.clearExcept({_onboardingCompletedKey});

    UserNameSettingsService.instance.resetLocalState();
    CurrencySettingsService.instance.resetLocalState();
    BubbleStyleSettingsService.instance.resetLocalState();
    PermissionPreferencesService.instance.resetLocalState();
    AiResponseSettingsService.instance.resetLocalState();
    LocalSpeechModelManager.instance.resetSelectionsWithoutRemovingDownloads();
  }
}
