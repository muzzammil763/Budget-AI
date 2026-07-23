import 'package:budget_ai/src/helpers/app_theme.dart';
import 'package:budget_ai/src/helpers/responsive_info_sheet.dart';
import 'package:budget_ai/src/helpers/toast_helper.dart';
import 'package:budget_ai/src/sync/account_encryption_service.dart';
import 'package:budget_ai/src/sync/encrypted_finance_sync_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:toastification/toastification.dart';

class EncryptionSettingsScreen extends StatefulWidget {
  const EncryptionSettingsScreen({super.key});

  @override
  State<EncryptionSettingsScreen> createState() =>
      _EncryptionSettingsScreenState();
}

class _EncryptionSettingsScreenState extends State<EncryptionSettingsScreen> {
  final _recoveryController = TextEditingController();
  bool _loading = true;
  bool _working = false;
  bool _remoteEnabled = false;
  bool _localKeyAvailable = false;
  String? _visibleRecoveryKey;
  String? _remoteFingerprint;

  User? get _user => Supabase.instance.client.auth.currentUser;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _recoveryController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final user = _user;
    if (user == null) return;
    try {
      final metadata = await Supabase.instance.client
          .from('user_encryption')
          .select('key_fingerprint')
          .eq('user_id', user.id)
          .maybeSingle();
      final hasKey = await AccountEncryptionService.instance.hasKey(user.id);
      if (!mounted) return;
      setState(() {
        _remoteEnabled = metadata != null;
        _remoteFingerprint = metadata?['key_fingerprint'] as String?;
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
      title: 'Reset encryption?',
      message:
          'This permanently erases your synced finance history for this '
          'account and issues a brand-new recovery key. Any other device '
          'still holding the old key will no longer be able to read new '
          'data. This cannot be undone.',
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
        _remoteEnabled = true;
        _localKeyAvailable = true;
        _visibleRecoveryKey = newKey;
      });
      await _load();
    } catch (error) {
      if (mounted) _showError('Could not reset encryption.');
    } finally {
      if (mounted) setState(() => _working = false);
    }
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
      if (fingerprint != _remoteFingerprint) {
        throw const FormatException(
          'Recovery key does not match this account.',
        );
      }
      await AccountEncryptionService.instance.restoreRecoveryKey(
        user.id,
        _recoveryController.text,
      );
      if (!mounted) return;
      setState(() {
        _localKeyAvailable = true;
        _recoveryController.clear();
      });
      showAppToast(context, message: 'Recovery key accepted. Syncing data.');
      await EncryptedFinanceSyncService.instance.syncNow();
    } catch (error) {
      if (mounted) {
        _showError(
          error is FormatException
              ? error.message
              : 'The recovery key could not be restored.',
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _revealRecoveryKey() async {
    final user = _user;
    if (user == null) return;
    final auth = LocalAuthentication();
    try {
      if (!await auth.isDeviceSupported()) {
        _showError('Set up device authentication before revealing this key.');
        return;
      }
      final authenticated = await auth.authenticate(
        localizedReason: 'Authenticate to reveal your Budget AI recovery key',
        persistAcrossBackgrounding: true,
      );
      if (!authenticated) return;
      final key = await AccountEncryptionService.instance.createRecoveryKey(
        user.id,
      );
      if (mounted) setState(() => _visibleRecoveryKey = key);
    } catch (_) {
      if (mounted) _showError('The recovery key could not be revealed.');
    }
  }

  Future<void> _copyRecoveryKey() async {
    final key = _visibleRecoveryKey;
    if (key == null) return;
    await Clipboard.setData(ClipboardData(text: key));
    if (mounted) showAppToast(context, message: 'Recovery key copied.');
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
                      ? 'Enter your recovery key'
                      : 'Finishing setup…',
                  textAlign: TextAlign.center,
                  style: AppTheme.headingLarge.copyWith(fontSize: 25),
                ),
                const SizedBox(height: 10),
                Text(
                  'Finance entries are encrypted on this device before upload. '
                  'Supabase and Budget AI receive ciphertext and cannot read '
                  'your descriptions, categories, or amounts.',
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
                else if (!_localKeyAvailable) ...[
                  TextField(
                    controller: _recoveryController,
                    autocorrect: false,
                    enableSuggestions: false,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'Recovery key',
                      hintText: 'BAI1-…',
                    ),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: _working ? null : _restore,
                    child: Text(_working ? 'Checking…' : 'Restore and sync'),
                  ),
                ] else if (_visibleRecoveryKey == null)
                  OutlinedButton.icon(
                    onPressed: _revealRecoveryKey,
                    icon: const Icon(CupertinoIcons.eye),
                    label: const Text('Reveal recovery key'),
                  ),
                if (_visibleRecoveryKey case final recoveryKey?) ...[
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Save this recovery key',
                          style: AppTheme.headingSmall,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'You need it to decrypt finance data on another '
                          'device. We cannot recover it for you.',
                        ),
                        const SizedBox(height: 14),
                        SelectableText(
                          recoveryKey,
                          style: AppTheme.bodyMedium.copyWith(
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextButton.icon(
                          onPressed: _copyRecoveryKey,
                          icon: const Icon(CupertinoIcons.doc_on_doc),
                          label: const Text('Copy recovery key'),
                        ),
                      ],
                    ),
                  ),
                ],
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
                    'Lost access to your recovery key, or want to rotate '
                    'it? Resetting issues a new key and erases the old '
                    'synced history — other devices will need the new key.',
                    style: AppTheme.bodySmall.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _working ? null : _confirmReset,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: theme.colorScheme.error,
                      side: BorderSide(color: theme.colorScheme.error),
                    ),
                    icon: const Icon(CupertinoIcons.arrow_2_circlepath),
                    label: Text(
                      _working ? 'Resetting…' : 'Reset encryption',
                    ),
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
