import 'package:budget_ai/src/finances/finance_backup_service.dart';
import 'package:budget_ai/src/finances/finance_service.dart';
import 'package:budget_ai/src/helpers/app_button.dart';
import 'package:budget_ai/src/helpers/app_theme.dart';
import 'package:budget_ai/src/helpers/responsive_info_sheet.dart';
import 'package:budget_ai/src/helpers/toast_helper.dart';
import 'package:budget_ai/src/sync/account_settings_sync_service.dart';
import 'package:budget_ai/src/sync/finance_sync_preference_service.dart';
import 'package:budget_ai/src/sync/finance_sync_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:toastification/toastification.dart';

/// Budget Hub actions for keeping finance entries safe: Cloud Sync, backup,
/// restore, and the warning shown before an account exit would erase
/// entries that exist only on this device.
class FinanceDataSafety {
  FinanceDataSafety._();

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  static String formatBackupDate(DateTime date) {
    return '${date.day} ${_months[date.month - 1]} ${date.year}';
  }

  /// Confirms and applies a Cloud Sync change from the Budget Hub toggle.
  static Future<void> setCloudSync(BuildContext context, bool enable) async {
    final confirmed = await ResponsiveInfoSheet.confirm(
      context,
      title: enable ? 'Turn On Cloud Sync?' : 'Turn Off Cloud Sync?',
      message: enable
          ? 'Your finance entries will be saved to your Budget AI account, so '
                'they are safe if you lose this phone and appear when you sign '
                'in on another device. Chat history always stays on this '
                'device.'
          : 'New entries and changes will be saved only on this device. '
                'Entries already synced stay in your account until you delete '
                'it. Back up regularly so you never lose your entries.',
      icon: enable ? CupertinoIcons.cloud_upload : CupertinoIcons.cloud,
      confirmLabel: enable ? 'Turn On' : 'Turn Off',
    );
    if (confirmed != true) return;
    await FinanceSyncPreferenceService.instance.setEnabled(enable);
    if (!context.mounted) return;
    showAppToast(
      context,
      message: enable
          ? 'Cloud Sync is on. Your entries are uploading.'
          : 'Cloud Sync is off. Entries now stay on this device.',
    );
  }

  /// Saves a backup file. Returns true once a backup was written.
  static Future<bool> saveBackup(BuildContext context) async {
    try {
      final count = await FinanceBackupService.instance.saveBackup();
      if (count == null || !context.mounted) return false;
      showAppToast(
        context,
        message: 'Backup saved with $count ${count == 1 ? 'entry' : 'entries'}',
      );
      return true;
    } catch (error) {
      debugPrint('[FinanceDataSafety] Backup failed: $error');
      if (context.mounted) {
        showAppToast(
          context,
          message: 'Could not save the backup. Please try again.',
          type: ToastificationType.error,
        );
      }
      return false;
    }
  }

  static Future<void> restoreBackup(BuildContext context) async {
    try {
      final restored = await FinanceBackupService.instance.restoreBackup();
      if (restored == null || !context.mounted) return;
      showAppToast(
        context,
        message: restored == 0
            ? 'Everything in this backup is already on your device'
            : 'Restored $restored ${restored == 1 ? 'entry' : 'entries'}',
      );
    } on FormatException catch (error) {
      if (!context.mounted) return;
      showAppToast(
        context,
        message: error.message,
        type: ToastificationType.error,
      );
    } catch (error) {
      debugPrint('[FinanceDataSafety] Restore failed: $error');
      if (!context.mounted) return;
      showAppToast(
        context,
        message: 'Could not open the backup. Please try again.',
        type: ToastificationType.error,
      );
    }
  }

  /// Before signing out: when entries would be erased from this device
  /// without a cloud copy, offers backup, Cloud Sync, or erasing them.
  /// Returns true once the user has been signed out.
  static Future<bool> confirmSignOut(
    BuildContext context, {
    required Future<void> Function() signOut,
  }) async {
    final atRisk = await FinanceBackupService.instance.entriesAtRisk();
    if (!context.mounted) return false;
    if (atRisk.isEmpty) {
      final confirmed = await ResponsiveInfoSheet.confirm(
        context,
        title: 'Sign Out?',
        message: atRisk.syncEnabled
            ? 'Your entries are synced to your account and will come back '
                  'when you sign in again. Chat history on this device will '
                  'be removed.'
            : 'Chat history and settings on this device will be removed. '
                  'You will need to sign in again to use Budget AI.',
        icon: CupertinoIcons.square_arrow_right,
        confirmLabel: 'Sign Out',
        isRed: true,
        onConfirm: signOut,
      );
      return confirmed == true;
    }
    final signedOut = await _showExitSheet(
      context,
      atRisk: atRisk,
      mode: _ExitMode.signOut,
      exit: signOut,
    );
    return signedOut == true;
  }

  /// Before deleting the account: offers a backup when there are entries,
  /// since deletion also removes any cloud copy. Returns true to continue.
  static Future<bool> offerBackupBeforeDelete(BuildContext context) async {
    final atRisk = EntriesAtRisk(
      count: (await FinanceService.instance.getAll()).length,
      syncEnabled: FinanceSyncPreferenceService.instance.enabled.value,
    );
    if (!context.mounted) return false;
    if (atRisk.isEmpty) return true;
    final proceed = await _showExitSheet(
      context,
      atRisk: atRisk,
      mode: _ExitMode.deleteAccount,
    );
    return proceed == true;
  }

  static Future<bool?> _showExitSheet(
    BuildContext context, {
    required EntriesAtRisk atRisk,
    required _ExitMode mode,
    Future<void> Function()? exit,
  }) {
    final theme = Theme.of(context);
    final warning = Colors.orange.shade700;
    return ResponsiveInfoSheet.show<bool>(
      context,
      title: mode == _ExitMode.signOut
          ? 'Keep Your Entries Safe'
          : 'Keep a Copy First?',
      headerIcon: Icon(
        CupertinoIcons.exclamationmark_shield_fill,
        size: 30,
        color: AppTheme.readableOn(warning),
      ),
      gradientColors: [warning, warning.withValues(alpha: 0.78)],
      contentWidgets: [
        _ExitSheetBody(atRisk: atRisk, mode: mode, exit: exit, theme: theme),
      ],
    );
  }
}

enum _ExitMode { signOut, deleteAccount }

class _ExitSheetBody extends StatefulWidget {
  const _ExitSheetBody({
    required this.atRisk,
    required this.mode,
    required this.exit,
    required this.theme,
  });

  final EntriesAtRisk atRisk;
  final _ExitMode mode;
  final Future<void> Function()? exit;
  final ThemeData theme;

  @override
  State<_ExitSheetBody> createState() => _ExitSheetBodyState();
}

class _ExitSheetBodyState extends State<_ExitSheetBody> {
  bool _backedUp = false;
  bool _backingUp = false;
  bool _syncing = false;
  bool _exiting = false;

  bool get _working => _backingUp || _syncing || _exiting;

  String get _message {
    final entries = widget.atRisk.entriesLabel;
    if (widget.mode == _ExitMode.deleteAccount) {
      return 'Deleting your account permanently erases your $entries from '
          'this device and from the cloud. Save a backup file first if you '
          'might want them later.';
    }
    if (widget.atRisk.syncEnabled) {
      return '$entries ${widget.atRisk.count == 1 ? 'has' : 'have'} not '
          'synced to your account yet. Signing out erases '
          '${widget.atRisk.count == 1 ? 'it' : 'them'} from this device. '
          'Sync now or save a backup so you don\'t lose '
          '${widget.atRisk.count == 1 ? 'it' : 'them'}.';
    }
    return 'Your $entries ${widget.atRisk.count == 1 ? 'is' : 'are'} saved '
        'only on this device. Signing out erases '
        '${widget.atRisk.count == 1 ? 'it' : 'them'} from this phone. Back '
        'up your entries or turn on Cloud Sync so you don\'t lose them.';
  }

  Future<void> _backup() async {
    setState(() => _backingUp = true);
    final saved = await FinanceDataSafety.saveBackup(context);
    if (!mounted) return;
    setState(() {
      _backingUp = false;
      _backedUp = _backedUp || saved;
    });
  }

  Future<void> _syncAndSignOut() async {
    setState(() => _syncing = true);
    if (!FinanceSyncPreferenceService.instance.enabled.value) {
      await FinanceSyncPreferenceService.instance.setEnabled(true);
    }
    // The account must remember Cloud Sync is on before sign-out clears this
    // device's settings, or the next sign-in would not pull the entries.
    final uploaded =
        await FinanceSyncService.instance.uploadPendingNow() &&
        await AccountSettingsSyncService.instance.pushNow();
    if (!mounted) return;
    if (!uploaded) {
      setState(() => _syncing = false);
      showAppToast(
        context,
        message:
            'Could not sync your entries. Check your connection, or save a '
            'backup instead.',
        type: ToastificationType.error,
      );
      return;
    }
    setState(() => _syncing = false);
    await _exit();
  }

  Future<void> _exit() async {
    final exit = widget.exit;
    if (exit == null) {
      Navigator.pop(context, true);
      return;
    }
    setState(() => _exiting = true);
    try {
      await exit();
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      debugPrint('[FinanceDataSafety] Sign out failed: $error');
      if (!mounted) return;
      setState(() => _exiting = false);
      showAppToast(
        context,
        message: 'Could not sign out. Please try again.',
        type: ToastificationType.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final lastBackup = FinanceBackupService.instance.lastBackupAt.value;
    final isSignOut = widget.mode == _ExitMode.signOut;
    final syncLabel = widget.atRisk.syncEnabled
        ? 'Sync Now & Sign Out'
        : 'Turn On Cloud Sync & Sign Out';
    final String exitLabel;
    if (isSignOut) {
      exitLabel = _backedUp
          ? 'Sign Out'
          : 'Sign Out & Erase ${widget.atRisk.entriesLabel}';
    } else {
      exitLabel = _backedUp ? 'Continue' : 'Continue Without Backup';
    }
    return PopScope(
      canPop: !_working,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _message,
            textAlign: TextAlign.center,
            style: AppTheme.bodyMedium.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _backedUp
                ? 'Backup saved. Keep the file somewhere safe.'
                : lastBackup == null
                ? 'You have never saved a backup on this device.'
                : 'Last backup: '
                      '${FinanceDataSafety.formatBackupDate(lastBackup)}',
            textAlign: TextAlign.center,
            style: AppTheme.bodySmall.copyWith(
              color: _backedUp
                  ? Colors.green.shade600
                  : theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 16),
          AppButton(
            key: const ValueKey('exit-sheet-backup'),
            text: _backedUp ? 'Save Another Backup' : 'Back Up Entries',
            icon: CupertinoIcons.arrow_down_doc,
            variant: _backedUp
                ? AppButtonVariant.outlined
                : AppButtonVariant.filled,
            isLoading: _backingUp,
            onPressed: _working ? null : _backup,
          ),
          if (isSignOut) ...[
            const SizedBox(height: 10),
            AppButton(
              key: const ValueKey('exit-sheet-sync'),
              text: syncLabel,
              icon: CupertinoIcons.cloud_upload,
              variant: AppButtonVariant.outlined,
              isLoading: _syncing,
              onPressed: _working ? null : _syncAndSignOut,
            ),
          ],
          const SizedBox(height: 10),
          AppButton(
            key: const ValueKey('exit-sheet-exit'),
            text: exitLabel,
            variant: AppButtonVariant.outlined,
            isRed: isSignOut || !_backedUp,
            isLoading: _exiting,
            onPressed: _working ? null : _exit,
          ),
          const SizedBox(height: 4),
          TextButton(
            onPressed: _working ? null : () => Navigator.pop(context, false),
            child: Text(
              'Cancel',
              style: AppTheme.bodyMedium.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
