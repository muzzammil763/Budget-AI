import 'dart:async';

import 'package:budget_ai/src/helpers/app_theme.dart';
import 'package:budget_ai/src/chat/chat_model_config.dart';
import 'package:budget_ai/src/chat/unified_chat_screen.dart';
import 'package:budget_ai/src/onboarding/onboarding_screen.dart';
import 'package:budget_ai/src/splash/splash_screen.dart';
import 'package:budget_ai/src/helpers/app_route_observer.dart';
import 'package:budget_ai/src/helpers/notification_service.dart';
import 'package:budget_ai/src/finances/finance_service.dart';
import 'package:budget_ai/src/settings/currency_settings_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _onboardingCompletedKey = 'onboarding_completed';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');
  await CurrencySettingsService.instance.initialize();
  await NotificationService.instance.initialize();
  unawaited(FinanceService.instance.applySavingsRollover());
  final preferences = SharedPreferencesAsync();
  final onboardingCompleted =
      await preferences.getBool(_onboardingCompletedKey) ?? false;
  runApp(MyApp(showOnboarding: !onboardingCompleted));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, this.showOnboarding = false});

  final bool showOnboarding;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Budget AI',
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      navigatorObservers: [appRouteObserver],
      home: SplashScreen(
        child: showOnboarding
            ? const OnboardingScreen()
            : UnifiedChatScreen(config: ChatModelConfig.deepseek),
      ),
    );
  }
}
