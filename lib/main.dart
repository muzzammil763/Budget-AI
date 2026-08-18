import 'package:budget_ai/src/auth/auth_gate.dart';
import 'package:budget_ai/src/auth/auth_service.dart';
import 'package:budget_ai/src/helpers/app_theme.dart';
import 'package:budget_ai/src/helpers/app_constants.dart';
import 'package:budget_ai/src/onboarding/onboarding_screen.dart';
import 'package:budget_ai/src/splash/splash_screen.dart';
import 'package:budget_ai/src/helpers/app_route_observer.dart';
import 'package:budget_ai/src/helpers/notification_service.dart';
import 'package:budget_ai/src/finances/finance_service.dart';
import 'package:budget_ai/src/settings/currency_settings_service.dart';
import 'package:budget_ai/src/settings/ai_response_settings_service.dart';
import 'package:budget_ai/src/settings/user_name_settings_service.dart';
import 'package:budget_ai/src/settings/bubble_style_settings_service.dart';
import 'package:budget_ai/src/settings/permission_preferences_service.dart';
import 'package:budget_ai/src/speech/openai_speech_service.dart';
import 'package:budget_ai/src/storage/local_settings_store.dart';
import 'package:budget_ai/src/sync/encrypted_finance_sync_service.dart';
import 'package:budget_ai/src/sync/account_settings_sync_service.dart';
import 'package:budget_ai/src/widgets/budget_home_widget_sync.dart';
import 'package:budget_ai/src/widgets/android_finance_app_actions.dart';
import 'package:budget_ai/src/widgets/siri_finance_inbox.dart';
import 'package:budget_ai/src/widgets/siri_finance_realtime_sync.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _onboardingCompletedKey = 'onboarding_completed';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: AppConstants.supabaseUrl,
    publishableKey: AppConstants.supabasePublishableKey,
  );
  await OpenAiSpeechService.removeLegacyOfflineSpeechArtifacts();
  await PermissionPreferencesService.instance.load();
  await AiResponseSettingsService.instance.load();
  await AuthService.instance.initialize();
  await CurrencySettingsService.instance.initialize();
  await UserNameSettingsService.instance.initialize();
  await BubbleStyleSettingsService.instance.initialize();
  await BudgetHomeWidgetSync.initialize();
  await AndroidFinanceAppActions.initialize();
  await SiriFinanceInbox.importPendingEntries();
  SiriFinanceRealtimeSync.initialize();
  await NotificationService.instance.initialize();
  await FinanceService.instance.applySavingsRollover();
  await FinanceService.instance.syncHomeWidget();
  await AccountSettingsSyncService.instance.initialize();
  await EncryptedFinanceSyncService.instance.initialize();
  final onboardingCompleted =
      await LocalSettingsStore.instance.getBool(_onboardingCompletedKey) ??
      false;
  runApp(MyApp(showOnboarding: !onboardingCompleted));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, this.showOnboarding = false});

  final bool showOnboarding;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<UserBubbleStyle>(
      valueListenable: BubbleStyleSettingsService.instance.style,
      builder: (context, _, _) {
        return MaterialApp(
          title: 'Budget AI',
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: ThemeMode.system,
          navigatorObservers: [appRouteObserver],
          home: SplashScreen(
            child: showOnboarding ? const OnboardingScreen() : const AuthGate(),
          ),
        );
      },
    );
  }
}
