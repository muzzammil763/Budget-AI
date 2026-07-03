import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:budget_ai/app/theme/app_theme.dart';
import 'package:budget_ai/core/widgets/toast_helper.dart';
import 'package:budget_ai/features/chat/presentation/widgets/chat_response_markdown.dart';
import 'package:budget_ai/features/finance/presentation/screens/finances_screen.dart';
import 'package:budget_ai/features/settings/presentation/screens/api_keys_screen.dart';
import 'package:budget_ai/features/memory/presentation/screens/memories_screen.dart';
import 'package:budget_ai/features/settings/presentation/screens/notification_settings_screen.dart';
import 'package:budget_ai/features/settings/presentation/screens/permissions_screen.dart';
import 'package:budget_ai/features/settings/presentation/screens/cache_manager_screen.dart';
import 'package:budget_ai/features/settings/presentation/screens/shared_preferences_screen.dart';
import 'package:budget_ai/features/settings/presentation/screens/tool_manager_screen.dart';

import 'package:budget_ai/features/settings/data/api_key_storage_service.dart';
import 'package:budget_ai/features/finance/data/finance_service.dart';
import 'package:budget_ai/features/memory/data/memory_service.dart';
import 'package:budget_ai/core/storage/shared_prefs_service.dart';
import 'package:budget_ai/core/widgets/responsive_info_sheet.dart';
import 'package:budget_ai/tools/settings/tool_settings.dart';

import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:toastification/toastification.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  PackageInfo? _packageInfo;
  late bool _hapticsEnabled;

  @override
  void initState() {
    super.initState();
    _hapticsEnabled = SharedPrefsService.getHapticsEnabled();
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
          _buildSectionHeader(theme, 'API Keys'),
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
          const SizedBox(height: 16),

          _buildSectionHeader(theme, 'Data'),
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
          const SizedBox(height: 16),

          _buildSectionHeader(theme, 'Tools'),
          _buildNavTile(
            theme,
            icon: Icons.build_outlined,
            title: 'Tool Manager',
            subtitle: 'Enable/disable tools and set access modes',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ToolManagerScreen()),
            ),
          ),
          const SizedBox(height: 16),

          _buildSectionHeader(theme, 'Preferences'),
          _buildSwitchTile(
            theme,
            icon: CupertinoIcons.hand_raised,
            title: 'Haptic Feedback',
            value: _hapticsEnabled,
            onChanged: (val) {
              setState(() => _hapticsEnabled = val);
              SharedPrefsService.setHapticsEnabled(val);
            },
          ),
          _buildNavTile(
            theme,
            icon: CupertinoIcons.bell,
            title: 'Notifications',
            subtitle: 'Approval and response notifications',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const NotificationSettingsScreen(),
              ),
            ),
          ),
          const SizedBox(height: 16),

          _buildSectionHeader(theme, 'System'),
          _buildNavTile(
            theme,
            icon: CupertinoIcons.lock,
            title: 'Permissions',
            subtitle: 'Check app permissions',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PermissionsScreen()),
            ),
          ),
          _buildNavTile(
            theme,
            icon: CupertinoIcons.delete,
            title: 'Cache Manager',
            subtitle: 'Manage cached files',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CacheManagerScreen()),
            ),
          ),
          _buildNavTile(
            theme,
            icon: CupertinoIcons.settings,
            title: 'Shared Preferences',
            subtitle: 'Inspect stored preferences',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const SharedPreferencesScreen(),
              ),
            ),
          ),
          const SizedBox(height: 16),

          _buildSectionHeader(theme, 'Backup & Restore'),
          _buildNavTile(
            theme,
            icon: CupertinoIcons.cloud_upload,
            title: 'Export Backup',
            subtitle: 'Save settings and data to file',
            onTap: _exportBackup,
          ),
          _buildNavTile(
            theme,
            icon: CupertinoIcons.cloud_download,
            title: 'Restore Backup',
            subtitle: 'Load settings and data from file',
            onTap: _restoreBackup,
          ),
          const SizedBox(height: 16),

          if (_packageInfo != null) ...[
            Center(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: Text(
                  'Budget AI v${_packageInfo!.version} (${_packageInfo!.buildNumber})',
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

  Widget _buildSectionHeader(ThemeData theme, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: Text(
        title,
        style: AppTheme.headingSmall.copyWith(
          color: theme.colorScheme.primary,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
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

  Widget _buildSwitchTile(
    ThemeData theme, {
    required IconData icon,
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
              child: Text(
                title,
                style: AppTheme.bodyMedium.copyWith(
                  color: theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ),
            Switch(
              value: value,
              onChanged: onChanged,
              activeColor: theme.colorScheme.primary,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _exportBackup() async {
    try {
      final allMemories = await MemoryService.instance.getAll();
      final allFinances = await FinanceService.instance.getAll();
      final memories = MemoryService.instance.buildExportJson(allMemories);
      final finances = FinanceService.instance.buildExportJson(allFinances);
      final deepseekKey = await ApiKeyStorageService.getDeepSeekApiKey() ?? '';
      final searchKey = await ApiKeyStorageService.getSearchApiKey() ?? '';

      final backup = {
        'version': 1,
        'app': 'Budget AI',
        'timestamp': DateTime.now().toIso8601String(),
        'api_keys': {
          'deepseek': deepseekKey,
          'searchapi': searchKey,
        },
        'memories': jsonDecode(memories),
        'finances': jsonDecode(finances),
      };

      final jsonStr = const JsonEncoder.withIndent('  ').convert(backup);
      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}/budget_ai_backup_${DateTime.now().millisecondsSinceEpoch}.json',
      );
      await file.writeAsString(jsonStr);

      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'Budget AI Backup',
      );
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
    // Simplified restore - would need file picker implementation
    showAppToast(
      context,
      message: 'Use the file picker to select a backup JSON file',
      type: ToastificationType.info,
    );
  }
}
