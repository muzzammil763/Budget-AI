import 'dart:async';

import 'package:budget_ai/app/theme/app_theme.dart';
import 'package:budget_ai/core/utils/vibration_manager.dart';
import 'package:budget_ai/features/chat/domain/chat_model_config.dart';
import 'package:budget_ai/features/chat/presentation/screens/unified_chat_screen.dart';
import 'package:budget_ai/features/onboarding/data/onboarding_service.dart';
import 'package:budget_ai/features/onboarding/presentation/screens/onboarding_screen.dart';
import 'package:budget_ai/features/splash/presentation/screens/splash_screen.dart';
import 'package:budget_ai/features/settings/data/android_settings_helper.dart';
import 'package:budget_ai/app/navigation/app_route_observer.dart';
import 'package:budget_ai/features/chat/data/repositories/chat_session_repository.dart';
import 'package:budget_ai/core/logging/open_gate_log_service.dart';
import 'package:budget_ai/features/finance/data/finance_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

void main() {
  OpenGateLogService.installDebugPrintHook();
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      await OpenGateLogService.initialize();
      WidgetsBinding.instance.addObserver(_ShutdownLogObserver());
      FlutterError.onError = (details) {
        FlutterError.presentError(details);
        OpenGateLogService.logError(
          details.exception,
          details.stack,
          area: 'FlutterError',
        );
      };
      PlatformDispatcher.instance.onError = (error, stack) {
        OpenGateLogService.logError(error, stack, area: 'PlatformError');
        return false;
      };

      await ChatSessionRepository.instance.init();
      await VibrationManager.instance.waitForInitialization();

      await AndroidSettingsHelper.instance.initialize();

      // Roll last month's savings into this month's income (1st, 1 AM entry)
      // without blocking startup.
      unawaited(FinanceService.instance.applySavingsRollover());

      final onboardingCompleted = await OnboardingService.instance
          .isCompleted();

      runApp(MyApp(showOnboarding: !onboardingCompleted));
    },
    (error, stack) {
      OpenGateLogService.logError(error, stack, area: 'ZoneError');
    },
  );
}

class _ShutdownLogObserver extends WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      unawaited(OpenGateLogService.markCleanShutdown());
    }
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, this.showOnboarding = false});

  final bool showOnboarding;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Budget AI',
      theme: AppTheme.light(fontFamily: 'Google Sans'),
      darkTheme: AppTheme.dark(fontFamily: 'Google Sans'),
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
