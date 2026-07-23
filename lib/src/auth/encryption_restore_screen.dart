import 'dart:async';

import 'package:budget_ai/src/auth/auth_screens.dart';
import 'package:budget_ai/src/auth/recovery_key_panel.dart';
import 'package:budget_ai/src/helpers/app_theme.dart';
import 'package:budget_ai/src/helpers/responsive_info_sheet.dart';
import 'package:budget_ai/src/helpers/toast_helper.dart';
import 'package:budget_ai/src/sync/account_encryption_service.dart';
import 'package:budget_ai/src/sync/encrypted_finance_sync_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:toastification/toastification.dart';

/// Shown when this account already has encryption enabled on another
/// device but this device doesn't hold the key yet (new device, reinstall).
/// The user must paste their recovery key to unlock their data, or wipe
/// and start over if the key is gone for good.
class EncryptionRestoreScreen extends StatefulWidget {
  const EncryptionRestoreScreen({
    super.key,
    required this.remoteFingerprint,
    required this.onDone,
  });

  final String? remoteFingerprint;
  final VoidCallback onDone;

  @override
  State<EncryptionRestoreScreen> createState() =>
      _EncryptionRestoreScreenState();
}

enum _RestoreStage { enterKey, saveNewKey }

class _EncryptionRestoreScreenState extends State<EncryptionRestoreScreen> {
  final _recoveryController = TextEditingController();
  _RestoreStage _stage = _RestoreStage.enterKey;
  bool _working = false;
  String? _newRecoveryKey;

  User? get _user => Supabase.instance.client.auth.currentUser;

  @override
  void dispose() {
    _recoveryController.dispose();
    super.dispose();
  }

  Future<void> _restore() async {
    final user = _user;
    if (user == null || _working) return;
    setState(() => _working = true);
    try {
      final bytes = AccountEncryptionService.parseRecoveryKey(
        _recoveryController.text,
      );
      final fingerprint = AccountEncryptionService.fingerprintForKey(bytes);
      if (widget.remoteFingerprint != null &&
          fingerprint != widget.remoteFingerprint) {
        throw const FormatException(
          'Recovery key does not match this account.',
        );
      }
      await AccountEncryptionService.instance.restoreRecoveryKey(
        user.id,
        _recoveryController.text,
      );
      unawaited(EncryptedFinanceSyncService.instance.syncNow());
      widget.onDone();
    } catch (error) {
      if (mounted) {
        showAppToast(
          context,
          message: error is FormatException
              ? error.message
              : 'The recovery key could not be restored.',
          type: ToastificationType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _confirmLostKey() async {
    final confirmed = await ResponsiveInfoSheet.confirm(
      context,
      title: 'Lost your recovery key?',
      message:
          'This permanently erases your synced finance history for this '
          'account and starts fresh with a brand-new key. Any device still '
          'holding the old key will no longer be able to read new data. '
          'This cannot be undone.',
      icon: CupertinoIcons.exclamationmark_triangle_fill,
      confirmLabel: 'Erase and start fresh',
    );
    if (confirmed == true) await _resetEncryption();
  }

  Future<void> _resetEncryption() async {
    if (_working) return;
    setState(() => _working = true);
    try {
      final newKey = await EncryptedFinanceSyncService.instance
          .resetEncryption();
      if (!mounted) return;
      setState(() {
        _newRecoveryKey = newKey;
        _stage = _RestoreStage.saveNewKey;
      });
    } catch (error) {
      if (mounted) {
        showAppToast(
          context,
          message: 'Could not reset encryption. Check your connection.',
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
      _RestoreStage.enterKey => AuthShell(
        eyebrow: 'THIS ACCOUNT IS PROTECTED',
        title: 'Enter your\nrecovery key',
        subtitle:
            'Paste the recovery key from the device where you first set '
            'up encryption to unlock your finance data here.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AuthTextField(
              controller: _recoveryController,
              label: 'Recovery key',
              hint: 'BAI1-…',
              icon: CupertinoIcons.lock_rotation,
              textCapitalization: TextCapitalization.characters,
              onSubmitted: (_) => _restore(),
            ),
            const SizedBox(height: 16),
            AuthPrimaryButton(
              label: 'Unlock my data',
              icon: CupertinoIcons.lock_open_fill,
              working: _working,
              onPressed: _restore,
            ),
            const SizedBox(height: 18),
            Center(
              child: TextButton(
                onPressed: _working ? null : _confirmLostKey,
                child: Text(
                  "I lost my recovery key",
                  style: AppTheme.bodySmall.copyWith(
                    color: Theme.of(context).colorScheme.error,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      _RestoreStage.saveNewKey => AuthShell(
        eyebrow: 'SAVE THIS NOW',
        title: 'Your new\nrecovery key',
        subtitle:
            'Your old encrypted history was erased. This new key protects '
            'everything going forward — save it before continuing.',
        child: RecoveryKeyPanel(
          recoveryKey: _newRecoveryKey!,
          continueLabel: 'Continue to Budget AI',
          onContinue: widget.onDone,
        ),
      ),
    };
  }
}
