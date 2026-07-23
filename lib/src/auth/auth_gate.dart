import 'package:budget_ai/src/auth/auth_screens.dart';
import 'package:budget_ai/src/auth/auth_service.dart';
import 'package:budget_ai/src/chat/chat_model_config.dart';
import 'package:budget_ai/src/chat/unified_chat_screen.dart';
import 'package:flutter/material.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = AuthService.instance;
    return AnimatedBuilder(
      animation: auth,
      builder: (context, _) {
        if (!auth.initialized) {
          return const AuthLoadingScreen();
        }
        if (auth.isPasswordRecovery) {
          return ResetPasswordScreen(onCancel: () async => auth.signOut());
        }
        if (auth.isAuthenticated) {
          return UnifiedChatScreen(config: ChatModelConfig.openAI);
        }
        return const AuthFlow();
      },
    );
  }
}
