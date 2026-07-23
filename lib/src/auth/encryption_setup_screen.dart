import 'dart:async';

import 'package:budget_ai/src/auth/auth_screens.dart';
import 'package:budget_ai/src/auth/recovery_key_panel.dart';
import 'package:budget_ai/src/helpers/app_theme.dart';
import 'package:budget_ai/src/helpers/toast_helper.dart';
import 'package:budget_ai/src/sync/account_encryption_service.dart';
import 'package:budget_ai/src/sync/encrypted_finance_sync_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:toastification/toastification.dart';

/// First-time encryption setup, shown once right after sign-up/first sign-in
/// for an account that has never enabled encryption on any device. Generates
/// the account's key and forces the user to acknowledge saving it before
/// they can reach the rest of the app.
class EncryptionSetupScreen extends StatefulWidget {
  const EncryptionSetupScreen({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  State<EncryptionSetupScreen> createState() => _EncryptionSetupScreenState();
}

enum _SetupStage { intro, saveKey }

class _EncryptionSetupScreenState extends State<EncryptionSetupScreen> {
  _SetupStage _stage = _SetupStage.intro;
  bool _working = false;
  String? _recoveryKey;

  User? get _user => Supabase.instance.client.auth.currentUser;

  Future<void> _setUp() async {
    final user = _user;
    if (user == null || _working) return;
    setState(() => _working = true);
    try {
      final recoveryKey = await AccountEncryptionService.instance
          .createRecoveryKey(user.id);
      final fingerprint = await AccountEncryptionService.instance.fingerprint(
        user.id,
      );
      await Supabase.instance.client.from('user_encryption').upsert({
        'user_id': user.id,
        'key_fingerprint': fingerprint,
        'encryption_version': 1,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
      unawaited(EncryptedFinanceSyncService.instance.syncNow());
      if (!mounted) return;
      setState(() {
        _recoveryKey = recoveryKey;
        _stage = _SetupStage.saveKey;
      });
    } catch (error) {
      if (mounted) {
        showAppToast(
          context,
          message: 'Could not set up encryption. Check your connection.',
          type: ToastificationType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return switch (_stage) {
      _SetupStage.intro => AuthShell(
        eyebrow: 'PRIVATE BY DEFAULT',
        title: 'Protect your\nfinance data',
        subtitle:
            'Budget AI encrypts every expense and income entry on this '
            'device before it ever leaves it. We only ever store '
            'ciphertext — not even Budget AI can read your entries.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _EncryptionPoint(
              icon: CupertinoIcons.lock_shield_fill,
              text: 'AES-256 encryption, generated fresh on this device.',
            ),
            const _EncryptionPoint(
              icon: CupertinoIcons.cloud_fill,
              text: 'Supabase only ever sees unreadable ciphertext.',
            ),
            const _EncryptionPoint(
              icon: CupertinoIcons.device_phone_portrait,
              text:
                  "You'll get a recovery key to unlock this account on "
                  'other devices.',
            ),
            const SizedBox(height: 8),
            AuthPrimaryButton(
              label: 'Set up encryption',
              icon: CupertinoIcons.lock_fill,
              working: _working,
              onPressed: _setUp,
            ),
          ],
        ),
      ),
      _SetupStage.saveKey => AuthShell(
        eyebrow: 'SAVE THIS NOW',
        title: 'Your recovery key',
        subtitle:
            "This is shown once. You'll need it to unlock your finance "
            'data on any other device — and we cannot recover it for you.',
        child: RecoveryKeyPanel(
          recoveryKey: _recoveryKey!,
          continueLabel: 'Continue to Budget AI',
          onContinue: widget.onDone,
        ),
      ),
    };
  }
}

class _EncryptionPoint extends StatelessWidget {
  const _EncryptionPoint({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: AppTheme.highlight),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: AppTheme.bodyMedium.copyWith(
                color: theme.colorScheme.onSurface,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
