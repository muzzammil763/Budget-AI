import 'package:budget_ai/src/helpers/app_button.dart';
import 'package:budget_ai/src/helpers/app_theme.dart';
import 'package:budget_ai/src/helpers/responsive_info_sheet.dart';
import 'package:budget_ai/src/settings/legal_screens.dart';
import 'package:budget_ai/src/storage/local_settings_store.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Records the user's agreement to send AI requests to OpenAI. Asked once per
/// device, right before the first message, voice note, or AI summary.
class AiConsent {
  AiConsent._();

  static const _key = 'ai_data_sharing_consent_v1';
  static bool? _granted;

  @visibleForTesting
  static set debugGranted(bool? value) => _granted = value;

  static Future<bool> isGranted() async {
    return _granted ??=
        await LocalSettingsStore.instance.getBool(_key) ?? false;
  }

  /// Returns true when the user has agreed, showing the consent sheet first
  /// if they have not been asked on this device yet.
  static Future<bool> ensure(BuildContext context) async {
    if (await isGranted()) return true;
    if (!context.mounted) return false;
    final agreed = await _show(context) ?? false;
    if (agreed) {
      _granted = true;
      await LocalSettingsStore.instance.setBool(_key, true);
    }
    return agreed;
  }

  static Future<bool?> _show(BuildContext context) {
    final theme = Theme.of(context);
    final onPrimary = AppTheme.readableOn(theme.colorScheme.primary);
    return ResponsiveInfoSheet.show<bool>(
      context,
      title: 'Before Budget AI replies',
      headerIcon: Icon(CupertinoIcons.sparkles, size: 30, color: onPrimary),
      gradientColors: [
        theme.colorScheme.primary,
        theme.colorScheme.primary.withValues(alpha: 0.78),
      ],
      contentWidgets: [const _ConsentContent()],
    );
  }
}

class _ConsentContent extends StatelessWidget {
  const _ConsentContent();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Budget AI uses OpenAI to understand your messages, voice notes, '
            'and receipts. Here is what that means for your data.',
            textAlign: TextAlign.center,
            style: AppTheme.bodyMedium.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 16),
          const _ConsentPoint(
            icon: CupertinoIcons.arrow_up_right_circle,
            title: 'What is shared',
            body:
                'The message, photo, or voice recording you send, plus the '
                'finance entries needed to answer, go to OpenAI through our '
                'secure server.',
          ),
          const _ConsentPoint(
            icon: CupertinoIcons.hand_raised,
            title: 'What is not',
            body:
                'Your data is never sold, never used for ads, and not used by '
                'us to train AI models.',
          ),
          const _ConsentPoint(
            icon: CupertinoIcons.device_phone_portrait,
            title: 'You stay in control',
            body:
                'Chat history stays on this device. Delete entries, chats, or '
                'your whole account at any time.',
          ),
          Center(
            child: TextButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const PrivacyPolicyScreen(),
                ),
              ),
              icon: const Icon(CupertinoIcons.lock_shield, size: 16),
              label: const Text('Read the Privacy Policy'),
            ),
          ),
          const SizedBox(height: 8),
          AppButton(
            key: const ValueKey('ai-consent-agree'),
            text: 'Agree & Continue',
            icon: CupertinoIcons.checkmark_alt,
            onPressed: () => Navigator.of(context).pop(true),
          ),
          const SizedBox(height: 4),
          TextButton(
            key: const ValueKey('ai-consent-decline'),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Not now'),
          ),
        ],
      ),
    );
  }
}

class _ConsentPoint extends StatelessWidget {
  const _ConsentPoint({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: theme.colorScheme.outline.withValues(alpha: 0.4),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 22, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTheme.bodyMedium.copyWith(
                      color: theme.colorScheme.onSurface,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    body,
                    style: AppTheme.bodySmall.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
