import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:budget_ai/src/helpers/app_theme.dart';
import 'package:budget_ai/src/helpers/responsive_info_sheet.dart';
import 'package:budget_ai/src/helpers/toast_helper.dart';
import 'package:budget_ai/src/finances/finance_service.dart';
import 'package:budget_ai/src/finances/finance_insights_screen.dart';
import 'package:budget_ai/src/finances/finances_screen.dart';
import 'package:budget_ai/src/loan/loans_screen.dart';
import 'package:budget_ai/src/onboarding/onboarding_screen.dart';
import 'package:budget_ai/src/settings/app_backup_service.dart';
import 'package:budget_ai/src/settings/currency_settings_service.dart';
import 'package:budget_ai/src/settings/permissions_screen.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:toastification/toastification.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  PackageInfo? _packageInfo;
  final TextEditingController _customCurrencyController =
      TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadPackageInfo();
  }

  @override
  void dispose() {
    _customCurrencyController.dispose();
    super.dispose();
  }

  Future<void> _loadPackageInfo() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() => _packageInfo = info);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: Navigator.of(context).pop,
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
        ),
        actions: [
          if (_packageInfo != null) ...[
            Text(
              '${_packageInfo!.version} (${_packageInfo!.buildNumber})',
              style: AppTheme.bodySmall.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
          ],
          const SizedBox(width: 8),
        ],
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        children: [
          _buildNavTile(
            theme,
            icon: CupertinoIcons.money_dollar_circle,
            title: 'Finances',
            subtitle: 'View and manage finances data',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const FinancesScreen()),
            ),
          ),
          _buildNavTile(
            theme,
            icon: Icons.handshake_outlined,
            title: 'Loans',
            subtitle: 'Borrowed and lent money with repayments',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const LoansScreen()),
            ),
          ),
          _buildNavTile(
            theme,
            icon: Icons.insights_rounded,
            title: 'Finance Insights',
            subtitle: 'Overall and monthly spending insights',
            onTap: _openInsights,
          ),
          ValueListenableBuilder<String>(
            valueListenable: CurrencySettingsService.instance.currency,
            builder: (context, currency, _) {
              return _buildNavTile(
                theme,
                icon: CupertinoIcons.money_dollar,
                title: 'Currency',
                subtitle:
                    'Amounts display as ${CurrencySettingsService.instance.formatAmount(1200)} using $currency',
                onTap: _showCurrencySheet,
              );
            },
          ),
          _buildNavTile(
            theme,
            icon: CupertinoIcons.checkmark_shield,
            title: 'Permissions',
            subtitle: 'Notifications and background mode',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PermissionsScreen()),
            ),
          ),
          _buildNavTile(
            theme,
            icon: CupertinoIcons.archivebox,
            title: 'Backup & Restore',
            subtitle: 'Backup & Restore finances data',
            onTap: _showBackupRestoreSheet,
          ),
          _buildNavTile(
            theme,
            icon: CupertinoIcons.sparkles,
            title: 'Onboarding',
            subtitle: 'Replay the welcome tour',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const OnboardingScreen(isReplay: true),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavTile(
    ThemeData theme, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(100),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(100),
            border: Border.all(
              color: theme.colorScheme.outline.withValues(alpha: 0.4),
            ),
          ),
          child: Row(
            children: [
              Icon(icon, size: 24, color: theme.colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTheme.bodyMedium.copyWith(
                        color: theme.colorScheme.onSurface,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: AppTheme.bodySmall.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 12,
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

  Future<void> _openInsights() async {
    final entries = await FinanceService.instance.getAll();
    if (!mounted) return;
    final now = DateTime.now();
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FinanceInsightsScreen(
          entries: List.from(entries),
          selectedMonth: DateTime(now.year, now.month),
        ),
      ),
    );
  }

  Future<void> _showCurrencySheet() async {
    final theme = Theme.of(context);
    _customCurrencyController.clear();

    await ResponsiveInfoSheet.show<void>(
      context,
      title: 'Currency',
      headerIcon: Icon(
        CupertinoIcons.money_dollar_circle,
        size: 30,
        color: AppTheme.readableOn(theme.colorScheme.primary),
      ),
      gradientColors: [
        theme.colorScheme.primary,
        theme.colorScheme.primary.withValues(alpha: 0.78),
      ],
      contentWidgets: [
        Text(
          'Choose how Budget AI displays money. This also updates AI finance responses and tool results.',
          style: AppTheme.bodyMedium.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontSize: 13,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 12),
        ValueListenableBuilder<String>(
          valueListenable: CurrencySettingsService.instance.currency,
          builder: (context, selectedCurrency, _) {
            return Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final option in kPresetCurrencyOptions)
                  _buildCurrencyChip(
                    theme,
                    option: option,
                    selected: option.displayText == selectedCurrency,
                    onTap: () => _selectCurrency(option.displayText),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        Text(
          'Custom',
          style: AppTheme.bodyMedium.copyWith(
            color: theme.colorScheme.onSurface,
            fontSize: 14,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _customCurrencyController,
                cursorColor: theme.colorScheme.primary,
                maxLength: 8,
                decoration: InputDecoration(
                  counterText: '',
                  hintText: 'e.g. AED, CHF, kr',
                  hintStyle: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant.withValues(
                      alpha: 0.68,
                    ),
                    fontSize: 14,
                  ),
                  filled: true,
                  fillColor: theme.colorScheme.surface,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 13,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(
                      color: theme.colorScheme.outline.withValues(alpha: 0.35),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: theme.colorScheme.primary),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 48,
              child: ElevatedButton(
                onPressed: () =>
                    _selectCurrency(_customCurrencyController.text),
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: theme.colorScheme.onPrimary,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text('Use'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _selectCurrency(String value) async {
    final normalized = value.trim();
    if (normalized.isEmpty) return;
    await CurrencySettingsService.instance.setCurrency(normalized);
    if (!mounted) return;
    Navigator.pop(context);
    showAppToast(
      context,
      message:
          'Currency set to ${CurrencySettingsService.instance.formatAmount(1200)}',
      type: ToastificationType.success,
    );
  }

  Widget _buildCurrencyChip(
    ThemeData theme, {
    required CurrencyOption option,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? theme.colorScheme.primary
              : theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected
                ? theme.colorScheme.primary
                : theme.colorScheme.outline.withValues(alpha: 0.32),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              option.displayText,
              style: AppTheme.bodyMedium.copyWith(
                color: selected
                    ? theme.colorScheme.onPrimary
                    : theme.colorScheme.onSurface,
                fontWeight: FontWeight.w900,
                fontSize: 14,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              option.name,
              style: AppTheme.bodySmall.copyWith(
                color: selected
                    ? theme.colorScheme.onPrimary.withValues(alpha: 0.76)
                    : theme.colorScheme.onSurfaceVariant,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showBackupRestoreSheet() async {
    final theme = Theme.of(context);
    await ResponsiveInfoSheet.show<void>(
      context,
      title: 'Backup & Restore',
      headerIcon: Icon(
        CupertinoIcons.archivebox,
        size: 30,
        color: AppTheme.readableOn(theme.colorScheme.primary),
      ),
      gradientColors: [
        theme.colorScheme.primary,
        theme.colorScheme.primary.withValues(alpha: 0.78),
      ],
      contentWidgets: [
        _buildSheetAction(
          theme,
          icon: CupertinoIcons.cloud_upload,
          title: 'Backup',
          subtitle: 'Create a dated JSON backup file',
          onTap: () {
            Navigator.pop(context);
            _exportBackup();
          },
        ),
        const SizedBox(height: 8),
        _buildSheetAction(
          theme,
          icon: CupertinoIcons.cloud_download,
          title: 'Restore',
          subtitle: 'Pick a JSON backup file to restore',
          onTap: () {
            Navigator.pop(context);
            _restoreBackup();
          },
        ),
      ],
    );
  }

  Widget _buildSheetAction(
    ThemeData theme, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(32),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(32),
          border: Border.all(
            color: theme.colorScheme.outline.withValues(alpha: 0.35),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: theme.colorScheme.primary, size: 24),
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
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: AppTheme.bodySmall.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              CupertinoIcons.chevron_right,
              size: 16,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _exportBackup() async {
    try {
      await AppBackupService.instance.shareBackup();
    } catch (e) {
      if (!mounted) return;
      showAppToast(
        context,
        message: 'Backup Failed: $e',
        type: ToastificationType.error,
      );
    }
  }

  Future<void> _restoreBackup() async {
    try {
      final result = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (result == null) return;

      final file = File(result.path!);
      if (!await file.exists()) {
        if (!mounted) return;
        showAppToast(
          context,
          message: 'File Not Found',
          type: ToastificationType.error,
        );
        return;
      }

      final restoreResult = await AppBackupService.instance.restoreFromFile(
        file,
      );

      if (!mounted) return;
      if (restoreResult['ok'] == true) {
        showAppToast(
          context,
          message:
              restoreResult['message']?.toString() ??
              'Backup Restored Successfully!',
          type: ToastificationType.success,
        );
      } else {
        showAppToast(
          context,
          message: restoreResult['error']?.toString() ?? 'Restore Failed',
          type: ToastificationType.error,
        );
      }
    } catch (e) {
      if (!mounted) return;
      showAppToast(
        context,
        message: 'Restore Failed: $e',
        type: ToastificationType.error,
      );
    }
  }
}
