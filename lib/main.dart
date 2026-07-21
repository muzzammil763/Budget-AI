import 'package:budget_ai/src/helpers/app_theme.dart';
import 'package:budget_ai/src/chat/chat_model_config.dart';
import 'package:budget_ai/src/chat/unified_chat_screen.dart';
import 'package:budget_ai/src/onboarding/onboarding_screen.dart';
import 'package:budget_ai/src/splash/splash_screen.dart';
import 'package:budget_ai/src/helpers/app_route_observer.dart';
import 'package:budget_ai/src/helpers/notification_service.dart';
import 'package:budget_ai/src/finances/finance_service.dart';
import 'package:budget_ai/src/settings/currency_settings_service.dart';
import 'package:budget_ai/src/settings/model_settings_service.dart';
import 'package:budget_ai/src/settings/user_name_settings_service.dart';
import 'package:budget_ai/src/settings/bubble_style_settings_service.dart';
import 'package:budget_ai/src/widgets/budget_home_widget_sync.dart';
import 'package:budget_ai/src/widgets/siri_finance_inbox.dart';
import 'package:budget_ai/src/widgets/siri_finance_realtime_sync.dart';
import 'package:device_preview/device_preview.dart';
// import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _onboardingCompletedKey = 'onboarding_completed';
// const _devicePreviewEnabled = true;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');
  await CurrencySettingsService.instance.initialize();
  await ModelSettingsService.instance.initialize();
  await UserNameSettingsService.instance.initialize();
  await BubbleStyleSettingsService.instance.initialize();
  await BudgetHomeWidgetSync.initialize();
  await SiriFinanceInbox.importPendingEntries();
  SiriFinanceRealtimeSync.initialize();
  await NotificationService.instance.initialize();
  await FinanceService.instance.applySavingsRollover();
  await FinanceService.instance.syncHomeWidget();
  final preferences = SharedPreferencesAsync();
  final onboardingCompleted =
      await preferences.getBool(_onboardingCompletedKey) ?? false;
  runApp(MyApp(showOnboarding: !onboardingCompleted));
  // runApp(
  //   DevicePreview(
  //     enabled: kDebugMode && _devicePreviewEnabled,
  //     builder: (_) => MyApp(showOnboarding: !onboardingCompleted),
  //   ),
  // );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, this.showOnboarding = false});

  final bool showOnboarding;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<UserBubbleStyle>(
      valueListenable: BubbleStyleSettingsService.instance.style,
      builder: (context, bubbleStyle, _) {
        final fontFamily = bubbleStyle.usesHandwrittenFont
            ? AppTheme.handwrittenFontFamily
            : AppTheme.defaultFontFamily;

        return MaterialApp(
          locale: DevicePreview.locale(context),
          builder: DevicePreview.appBuilder,
          title: 'Budget AI',
          theme: AppTheme.light(fontFamily: fontFamily),
          darkTheme: AppTheme.dark(fontFamily: fontFamily),
          themeMode: ThemeMode.system,
          navigatorObservers: [appRouteObserver],
          home: SplashScreen(
            child: showOnboarding
                ? const OnboardingScreen()
                : UnifiedChatScreen(config: ChatModelConfig.openAI),
          ),
        );
      },
    );
  }
}
