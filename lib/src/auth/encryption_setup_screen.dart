import 'dart:async';

import 'package:budget_ai/src/auth/auth_screens.dart';
import 'package:budget_ai/src/auth/auth_service.dart';
import 'package:budget_ai/src/helpers/app_button.dart';
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
/// the account's data key and wraps it under the just-typed account
/// password, so future devices unlock automatically on a normal login —
/// no separate key ever needs to be saved or copied.
class EncryptionSetupScreen extends StatefulWidget {
  const EncryptionSetupScreen({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  State<EncryptionSetupScreen> createState() => _EncryptionSetupScreenState();
}

class _EncryptionSetupScreenState extends State<EncryptionSetupScreen> {
  bool _working = false;
  bool _failed = false;

  User? get _user => Supabase.instance.client.auth.currentUser;

  @override
  void initState() {
    super.initState();
    _setUp();
  }

  Future<void> _setUp() async {
    final user = _user;
    if (user == null || _working) return;
    setState(() {
      _working = true;
      _failed = false;
    });
    try {
      final password = AuthService.instance.pendingPassword;
      if (password == null) {
        throw StateError(
          'Sign in again to finish setting up encryption.',
        );
      }
      await AccountEncryptionService.instance.createDataKey(user.id);
      final fingerprint = await AccountEncryptionService.instance.fingerprint(
        user.id,
      );
      final wrapped = await AccountEncryptionService.instance
          .wrapKeyWithPassword(user.id, password);
      await Supabase.instance.client.from('user_encryption').upsert({
        'user_id': user.id,
        'key_fingerprint': fingerprint,
        'encryption_version': 1,
        'password_salt': wrapped.salt,
        'wrapped_key_ciphertext': wrapped.ciphertext,
        'wrapped_key_nonce': wrapped.nonce,
        'wrapped_key_mac': wrapped.mac,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
      AuthService.instance.clearPendingPassword();
      unawaited(EncryptedFinanceSyncService.instance.syncNow());
      widget.onDone();
    } catch (error) {
      if (mounted) {
        setState(() => _failed = true);
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
    return AuthShell(
      eyebrow: 'PRIVATE BY DEFAULT',
      title: 'Protecting your\nfinance data',
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
                'Signing in with your password unlocks other devices '
                'automatically — nothing to copy or save.',
          ),
          const SizedBox(height: 8),
          if (_failed)
            AppButton(
              text: 'Try again',
              icon: CupertinoIcons.arrow_clockwise,
              isLoading: _working,
              onPressed: _setUp,
            )
          else
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
        ],
      ),
    );
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
