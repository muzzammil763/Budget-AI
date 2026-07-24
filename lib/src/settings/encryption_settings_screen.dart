import 'package:budget_ai/src/helpers/app_button.dart';
import 'package:budget_ai/src/helpers/app_theme.dart';
import 'package:budget_ai/src/helpers/responsive_info_sheet.dart';
import 'package:budget_ai/src/helpers/toast_helper.dart';
import 'package:budget_ai/src/sync/account_encryption_service.dart';
import 'package:budget_ai/src/sync/encrypted_finance_sync_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:toastification/toastification.dart';

class EncryptionSettingsScreen extends StatefulWidget {
  const EncryptionSettingsScreen({super.key});

  @override
  State<EncryptionSettingsScreen> createState() =>
      _EncryptionSettingsScreenState();
}

class _EncryptionSettingsScreenState extends State<EncryptionSettingsScreen> {
  bool _loading = true;
  bool _remoteEnabled = false;
  bool _localKeyAvailable = false;

  User? get _user => Supabase.instance.client.auth.currentUser;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final user = _user;
    if (user == null) return;
    try {
      final metadata = await Supabase.instance.client
          .from('user_encryption')
          .select('user_id')
          .eq('user_id', user.id)
          .maybeSingle();
      final hasKey = await AccountEncryptionService.instance.hasKey(user.id);
      if (!mounted) return;
      setState(() {
        _remoteEnabled = metadata != null;
        _localKeyAvailable = hasKey;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showError('Could not check encryption status.');
    }
  }

  Future<void> _confirmReset() async {
    final confirmed = await ResponsiveInfoSheet.confirm(
      context,
      title: 'Start fresh?',
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
          if (mounted) _showError('Could not reset encryption.');
          rethrow;
        }
      },
    );
    if (confirmed == true) {
      setState(() {
        _remoteEnabled = true;
        _localKeyAvailable = true;
      });
      await _load();
    }
  }

  void _showError(String message) {
    showAppToast(context, message: message, type: ToastificationType.error);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Encryption')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Icon(
                  _remoteEnabled && _localKeyAvailable
                      ? CupertinoIcons.lock_shield_fill
                      : CupertinoIcons.lock_shield,
                  size: 54,
                  color: AppTheme.highlight,
                ),
                const SizedBox(height: 18),
                Text(
                  _remoteEnabled && _localKeyAvailable
                      ? 'Your finance sync is protected'
                      : _remoteEnabled
                      ? "Couldn't unlock automatically"
                      : 'Finishing setup…',
                  textAlign: TextAlign.center,
                  style: AppTheme.headingLarge.copyWith(fontSize: 25),
                ),
                const SizedBox(height: 10),
                Text(
                  'Finance entries are encrypted on this device before upload. '
                  'Supabase and Budget AI receive ciphertext and cannot read '
                  'your descriptions, categories, or amounts. Signing in with '
                  'your password unlocks other devices automatically.',
                  textAlign: TextAlign.center,
                  style: AppTheme.bodyMedium.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 24),
                if (!_remoteEnabled)
                  Text(
                    "Encryption is always on for new sessions — this should "
                    "resolve on its own. If it doesn't, try reopening "
                    'Budget AI.',
                    textAlign: TextAlign.center,
                    style: AppTheme.bodySmall.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  )
                else if (!_localKeyAvailable)
                  Text(
                    'Sign out and sign back in on this device to try '
                    'unlocking again.',
                    textAlign: TextAlign.center,
                    style: AppTheme.bodySmall.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                const SizedBox(height: 24),
                const _PrivacyPoint(
                  icon: CupertinoIcons.device_phone_portrait,
                  text: 'SQLite remains the local source of truth.',
                ),
                const _PrivacyPoint(
                  icon: CupertinoIcons.chat_bubble_2,
                  text: 'Chat history always stays on this device.',
                ),
                const _PrivacyPoint(
                  icon: CupertinoIcons.waveform,
                  text: 'Downloaded speech models are never uploaded.',
                ),
                if (_remoteEnabled && _localKeyAvailable) ...[
                  const SizedBox(height: 24),
                  const Divider(),
                  const SizedBox(height: 12),
                  Text(
                    'Want to start over? Resetting erases the old synced '
                    'history and issues a brand-new key from this device — '
                    'other devices will need to sign in again to pick it up.',
                    style: AppTheme.bodySmall.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 12),
                  AppButton(
                    text: 'Reset encryption',
                    icon: CupertinoIcons.arrow_2_circlepath,
                    variant: AppButtonVariant.outlined,
                    isRed: true,
                    onPressed: _confirmReset,
                  ),
                ],
              ],
            ),
    );
  }
}

class _PrivacyPoint extends StatelessWidget {
  const _PrivacyPoint({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppTheme.highlight),
          const SizedBox(width: 12),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
