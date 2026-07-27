import 'package:budget_ai/src/auth/auth_service.dart';
import 'package:budget_ai/src/helpers/app_theme.dart';
import 'package:budget_ai/src/helpers/responsive_info_sheet.dart';
import 'package:budget_ai/src/helpers/toast_helper.dart';
import 'package:budget_ai/src/settings/user_name_settings_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:toastification/toastification.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key, required this.nameEditor});

  final Widget nameEditor;

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  bool _isSendingReset = false;

  String get _email => AuthService.instance.user?.email ?? 'Email unavailable';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: Navigator.of(context).pop,
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
        ),
        title: const Text('Account'),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          children: [
            _buildProfileHero(theme),
            const SizedBox(height: 8),
            widget.nameEditor,
            _buildPasswordCard(theme),
            const SizedBox(height: 8),
            _buildSignOutCard(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileHero(ThemeData theme) {
    return ValueListenableBuilder<String>(
      valueListenable: UserNameSettingsService.instance.userName,
      builder: (context, name, _) {
        final displayName = name.trim().isEmpty ? 'Budget AI account' : name;
        final initial = name.trim().isEmpty
            ? '?'
            : name.trim()[0].toUpperCase();
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                theme.colorScheme.primary,
                theme.colorScheme.primary.withValues(alpha: 0.76),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: theme.colorScheme.primary.withValues(alpha: 0.18),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: theme.colorScheme.onPrimary.withValues(alpha: 0.5),
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  initial,
                  style: AppTheme.headingSmall.copyWith(
                    color: theme.colorScheme.onPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.headingSmall.copyWith(
                        color: theme.colorScheme.onPrimary,
                        fontSize: 18,
                      ),
                    ),
                    Text(
                      _email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.bodySmall.copyWith(
                        color: theme.colorScheme.onPrimary.withValues(
                          alpha: 0.78,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPasswordCard(ThemeData theme) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _isSendingReset ? null : _sendPasswordReset,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: _cardDecoration(theme),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: _isSendingReset
                    ? Padding(
                        padding: const EdgeInsets.all(11),
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: theme.colorScheme.primary,
                        ),
                      )
                    : Icon(
                        CupertinoIcons.lock_rotation,
                        color: theme.colorScheme.primary,
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Change password',
                      style: AppTheme.bodyMedium.copyWith(
                        color: theme.colorScheme.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Send a secure reset link to $_email',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.bodySmall.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                CupertinoIcons.chevron_right,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant.withValues(
                  alpha: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSignOutCard(ThemeData theme) {
    return OutlinedButton.icon(
      onPressed: _signOut,
      icon: const Icon(CupertinoIcons.square_arrow_right),
      label: const Text('Sign Out'),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        foregroundColor: theme.colorScheme.error,
        side: BorderSide(color: theme.colorScheme.error.withValues(alpha: 0.5)),
      ),
    );
  }

  BoxDecoration _cardDecoration(ThemeData theme) => BoxDecoration(
    color: theme.colorScheme.surface,
    borderRadius: BorderRadius.circular(12),
    border: Border.all(
      color: theme.colorScheme.outline.withValues(alpha: 0.28),
    ),
  );

  Future<void> _sendPasswordReset() async {
    final userEmail = AuthService.instance.user?.email;
    if (userEmail == null || userEmail.isEmpty) {
      showAppToast(
        context,
        message: 'No account email is available',
        type: ToastificationType.error,
      );
      return;
    }

    final confirmed = await ResponsiveInfoSheet.confirm(
      context,
      title: 'Change Password?',
      message:
          'Budget AI will email a secure password-reset link to $userEmail. '
          'Open that link on this device to choose a new password.',
      icon: CupertinoIcons.lock_rotation,
      confirmLabel: 'Send Email',
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isSendingReset = true);
    try {
      await AuthService.instance.sendPasswordRecovery(userEmail);
      if (!mounted) return;
      showAppToast(
        context,
        message: 'Password reset email sent to $userEmail',
        type: ToastificationType.success,
      );
    } catch (error) {
      if (!mounted) return;
      showAppToast(
        context,
        message: friendlyAuthError(error),
        type: ToastificationType.error,
      );
    } finally {
      if (mounted) setState(() => _isSendingReset = false);
    }
  }

  Future<void> _signOut() async {
    final confirmed = await ResponsiveInfoSheet.confirm(
      context,
      title: 'Sign Out?',
      message:
          'Your finance data stays on this device. You will need to sign in '
          'again to use AI chat.',
      icon: CupertinoIcons.square_arrow_right,
      confirmLabel: 'Sign Out',
      isRed: true,
      onConfirm: () async {
        try {
          await AuthService.instance.signOut();
        } catch (error) {
          if (mounted) {
            showAppToast(
              context,
              message: friendlyAuthError(error),
              type: ToastificationType.error,
            );
          }
          rethrow;
        }
      },
    );
    if (confirmed == true && mounted) Navigator.of(context).pop();
  }
}
