import 'package:budget_ai/src/auth/auth_screens.dart';
import 'package:budget_ai/src/auth/auth_service.dart';
import 'package:budget_ai/src/helpers/app_button.dart';
import 'package:budget_ai/src/helpers/app_theme.dart';
import 'package:budget_ai/src/helpers/responsive_info_sheet.dart';
import 'package:budget_ai/src/helpers/toast_helper.dart';
import 'package:budget_ai/src/sync/legacy_encryption_migration_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:toastification/toastification.dart';

/// Asks for the account password when this device cannot unlock the
/// finance data saved by the retired encryption. The password that
/// protected that data is the one the account had when it was last used;
/// after a password reset, the old password is required instead.
class LegacyDataUnlockScreen extends StatefulWidget {
  const LegacyDataUnlockScreen({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  State<LegacyDataUnlockScreen> createState() => _LegacyDataUnlockScreenState();
}

class _LegacyDataUnlockScreenState extends State<LegacyDataUnlockScreen> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();
  bool _obscurePassword = true;
  bool _working = false;

  String? get _userId => Supabase.instance.client.auth.currentUser?.id;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _unlock() async {
    final userId = _userId;
    if (_working || userId == null) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _working = true);
    try {
      final status = await LegacyEncryptionMigrationService.instance.migrate(
        userId,
        password: _password.text,
      );
      if (!mounted) return;
      if (status == LegacyMigrationStatus.complete) {
        widget.onDone();
      } else {
        showAppToast(
          context,
          message: 'That password did not unlock your saved data.',
          type: ToastificationType.error,
        );
      }
    } catch (_) {
      if (mounted) {
        showAppToast(
          context,
          message: 'Could not reach Budget AI. Check your connection.',
          type: ToastificationType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _signOut() async {
    if (_working) return;
    setState(() => _working = true);
    try {
      await AuthService.instance.signOut();
    } catch (_) {
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

  Future<void> _confirmDiscard() async {
    final userId = _userId;
    if (userId == null) return;
    final confirmed = await ResponsiveInfoSheet.confirm(
      context,
      title: 'Continue without old data?',
      message:
          'Finance entries saved before this update stay locked without '
          'the password that protected them, and will be permanently '
          'deleted from the cloud. Entries already on another unlocked '
          'device are not affected. This cannot be undone.',
      icon: CupertinoIcons.exclamationmark_triangle_fill,
      confirmLabel: 'Delete and continue',
      isRed: true,
      onConfirm: () async {
        try {
          await LegacyEncryptionMigrationService.instance.discardLegacyData(
            userId,
          );
        } catch (_) {
          if (mounted) {
            showAppToast(
              context,
              message: 'Could not reach Budget AI. Check your connection.',
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
      eyebrow: 'ONE-TIME UPDATE',
      title: 'Unlock your\nsaved data',
      subtitle:
          'Budget AI no longer encrypts your entries. Enter the password '
          'you used when you last opened the app to move your saved '
          'finance data over.',
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AuthTextField(
              controller: _password,
              label: 'Password',
              hint: 'Your previous password',
              icon: CupertinoIcons.lock,
              obscureText: _obscurePassword,
              autofillHints: const [AutofillHints.password],
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _unlock(),
              validator: (value) => value == null || value.isEmpty
                  ? 'Enter your password.'
                  : null,
              trailing: IconButton(
                tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
                icon: Icon(
                  _obscurePassword
                      ? CupertinoIcons.eye
                      : CupertinoIcons.eye_slash,
                  size: 20,
                ),
              ),
            ),
            const SizedBox(height: 18),
            AppButton(
              text: 'Unlock',
              icon: CupertinoIcons.lock_open,
              isLoading: _working,
              onPressed: _unlock,
            ),
            const SizedBox(height: 12),
            Center(
              child: TextButton(
                onPressed: _working ? null : _signOut,
                child: const Text('Sign out'),
              ),
            ),
            Center(
              child: TextButton(
                onPressed: _working ? null : _confirmDiscard,
                child: Text(
                  'Continue without old data',
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
    );
  }
}
