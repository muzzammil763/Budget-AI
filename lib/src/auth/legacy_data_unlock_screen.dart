import 'package:budget_ai/src/auth/auth_screens.dart';
import 'package:budget_ai/src/auth/auth_service.dart';
import 'package:budget_ai/src/helpers/app_button.dart';
import 'package:budget_ai/src/helpers/app_theme.dart';
import 'package:budget_ai/src/helpers/responsive_info_sheet.dart';
import 'package:budget_ai/src/helpers/toast_helper.dart';
import 'package:budget_ai/src/sync/encrypted_finance_sync_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:toastification/toastification.dart';

/// Shown when this account already has encryption enabled on another
/// device, but this device couldn't unlock it automatically with the
/// account password (a typo in the password just entered, or the
/// server-side envelope isn't there yet because no other device has
/// logged in since password-based unlock was introduced). Signing in
/// again is the normal way out; starting fresh is the last resort if
/// that keeps failing.
class EncryptionRestoreScreen extends StatefulWidget {
  const EncryptionRestoreScreen({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  State<EncryptionRestoreScreen> createState() =>
      _EncryptionRestoreScreenState();
}

class _EncryptionRestoreScreenState extends State<EncryptionRestoreScreen> {
  bool _working = false;

  Future<void> _signOutAndRetry() async {
    if (_working) return;
    setState(() => _working = true);
    try {
      await AuthService.instance.signOut();
    } catch (error) {
      if (mounted) {
        showAppToast(
          context,
          message: 'Could not sign out. Check your connection.',
          type: ToastificationType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _confirmReset() async {
    final confirmed = await ResponsiveInfoSheet.confirm(
      context,
      title: 'Start fresh on this device?',
      message:
          'This permanently erases your synced finance history for this '
          'account and starts over with a brand-new key from this device. '
          'Any other device will need to sign in again to pick up the new '
          'key. This cannot be undone.',
      icon: CupertinoIcons.exclamationmark_triangle_fill,
      confirmLabel: 'Erase and start fresh',
      isRed: true,
      onConfirm: () async {
        try {
          await EncryptedFinanceSyncService.instance.resetEncryption();
        } catch (error) {
          if (mounted) {
            showAppToast(
              context,
              message: 'Could not reset encryption. Check your connection.',
              type: ToastificationType.error,
            );
          }
          rethrow;
        }
      },
    );
    if (confirmed == true) widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    return AuthShell(
      eyebrow: 'THIS ACCOUNT IS PROTECTED',
      title: "Couldn't unlock\nautomatically",
      subtitle:
          "This device couldn't unlock your account with your password. "
          'Try signing in again, or use the device where your data is '
          'already unlocked to enable this one.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppButton(
            text: 'Sign out and try again',
            icon: CupertinoIcons.arrow_clockwise,
            isLoading: _working,
            onPressed: _signOutAndRetry,
          ),
          const SizedBox(height: 18),
          Center(
            child: TextButton(
              onPressed: _working ? null : _confirmReset,
              child: Text(
                'Start fresh instead',
                style: AppTheme.bodySmall.copyWith(
                  color: Theme.of(context).colorScheme.error,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
