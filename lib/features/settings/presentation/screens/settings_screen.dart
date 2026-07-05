import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:budget_ai/app/theme/app_theme.dart';
import 'package:budget_ai/core/widgets/responsive_info_sheet.dart';
import 'package:budget_ai/core/widgets/toast_helper.dart';
import 'package:budget_ai/features/finance/presentation/screens/finances_screen.dart';
import 'package:budget_ai/features/settings/presentation/screens/api_keys_screen.dart';
import 'package:budget_ai/features/memory/presentation/screens/memories_screen.dart';
import 'package:budget_ai/features/settings/data/app_backup_service.dart';

import 'package:package_info_plus/package_info_plus.dart';
import 'package:toastification/toastification.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  PackageInfo? _packageInfo;

  @override
  void initState() {
    super.initState();
    _loadPackageInfo();
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
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        children: [
          _buildNavTile(
            theme,
            icon: Icons.key_outlined,
            title: 'API Keys',
            subtitle: 'DeepSeek & SearchAPI keys',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const APIKeysScreen()),
            ),
          ),
          _buildNavTile(
            theme,
            icon: CupertinoIcons.money_dollar_circle,
            title: 'Finances',
            subtitle: 'View and manage expenses',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const FinancesScreen()),
            ),
          ),
          _buildNavTile(
            theme,
            icon: CupertinoIcons.book,
            title: 'Memories',
            subtitle: 'Manage saved memories',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const MemoriesScreen()),
            ),
          ),
          _buildNavTile(
            theme,
            icon: CupertinoIcons.archivebox,
            title: 'Backup & Restore',
            subtitle:
                'Export or restore API keys, finances, memories, and model',
            onTap: _showBackupRestoreSheet,
          ),
          if (_packageInfo != null) ...[
            const SizedBox(height: 16),
            Center(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: Text(
                  'Budget AI ${_packageInfo!.version} (${_packageInfo!.buildNumber})',
                  style: AppTheme.bodySmall.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ],
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
      padding: const EdgeInsets.only(bottom: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: theme.colorScheme.outline.withValues(alpha: 0.4),
            ),
          ),
          child: Row(
            children: [
              Icon(icon, size: 22, color: theme.colorScheme.primary),
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
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            'Choose what you want to do with your Budget AI data.',
            style: AppTheme.bodySmall.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 13,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 16),
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
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
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
        message: 'Backup failed: $e',
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
          message: 'File not found',
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
              'Backup restored successfully!',
          type: ToastificationType.success,
        );
      } else {
        showAppToast(
          context,
          message: restoreResult['error']?.toString() ?? 'Restore failed',
          type: ToastificationType.error,
        );
      }
    } catch (e) {
      if (!mounted) return;
      showAppToast(
        context,
        message: 'Restore failed: $e',
        type: ToastificationType.error,
      );
    }
  }
}
