import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:budget_ai/app/theme/app_theme.dart';
import 'package:budget_ai/core/widgets/toast_helper.dart';
import 'package:budget_ai/features/chat/domain/chat_model_config.dart';
import 'package:budget_ai/features/chat/domain/models/ai_models.dart';
import 'package:budget_ai/features/finance/presentation/screens/finances_screen.dart';
import 'package:budget_ai/features/settings/presentation/screens/api_keys_screen.dart';
import 'package:budget_ai/features/memory/presentation/screens/memories_screen.dart';
import 'package:budget_ai/features/settings/data/app_backup_service.dart';

import 'package:budget_ai/features/settings/data/api_key_storage_service.dart';
import 'package:budget_ai/features/finance/data/finance_service.dart';
import 'package:budget_ai/features/memory/data/memory_service.dart';
import 'package:budget_ai/core/storage/shared_prefs_service.dart';

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
  late String _selectedModel;

  @override
  void initState() {
    super.initState();
    _selectedModel = SharedPrefsService.getSelectedDeepSeekModel() ?? 'deepseek-v4-flash';
    _loadPackageInfo();
  }

  Future<void> _loadPackageInfo() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() => _packageInfo = info);
    }
  }

  void _onModelChanged(String? modelId) {
    if (modelId == null || modelId == _selectedModel) return;
    setState(() => _selectedModel = modelId);
    SharedPrefsService.setSelectedDeepSeekModel(modelId);
    showAppToast(
      context,
      message: 'Model changed to ${AIModels.getModelById("deepseek", modelId)?.name ?? modelId}',
      type: ToastificationType.success,
    );
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
          _buildModelSelector(theme),
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
            icon: CupertinoIcons.cloud_upload,
            title: 'Export Backup',
            subtitle: 'Save finances, memories & API keys',
            onTap: _exportBackup,
          ),
          _buildNavTile(
            theme,
            icon: CupertinoIcons.cloud_download,
            title: 'Restore Backup',
            subtitle: 'Restore from a backup file',
            onTap: _restoreBackup,
          ),
          if (_packageInfo != null) ...[
            const SizedBox(height: 16),
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

  Widget _buildModelSelector(ThemeData theme) {
    final models = AIModels.deepseekModels;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
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
            Icon(Icons.smart_toy_outlined, size: 22, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Model',
                    style: AppTheme.bodyMedium.copyWith(
                      color: theme.colorScheme.onSurface,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: theme.colorScheme.outline.withValues(alpha: 0.4),
                      ),
                    ),
                    child: DropdownButton<String>(
                      value: _selectedModel,
                      isExpanded: true,
                      underline: const SizedBox.shrink(),
                      icon: Icon(Icons.keyboard_arrow_down, color: theme.colorScheme.primary),
                      style: AppTheme.bodyMedium.copyWith(
                        color: theme.colorScheme.onSurface,
                        fontSize: 13,
                      ),
                      items: models.map((model) {
                        return DropdownMenuItem<String>(
                          value: model.id,
                          child: Text(model.name),
                        );
                      }).toList(),
                      onChanged: _onModelChanged,
                    ),
                  ),
                ],
              ),
            ),
          ],
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

  Future<void> _exportBackup() async {
    try {
      final allMemories = await MemoryService.instance.getAll();
      final allFinances = await FinanceService.instance.getAll();
      final deepseekKey = await ApiKeyStorageService.getDeepSeekApiKey() ?? '';
      final searchKey = await ApiKeyStorageService.getSearchApiKey() ?? '';

      final backup = {
        'version': 2,
        'app': 'Budget AI',
        'timestamp': DateTime.now().toIso8601String(),
        'api_keys': {
          'deepseek': deepseekKey,
          'searchapi': searchKey,
        },
        'data': {
          'finances': allFinances.map((e) => e.toJson()).toList(),
          'memories': allMemories.map((m) => m.toJson()).toList(),
        },
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

      final restoreResult = await AppBackupService.instance.restoreFromFile(file);

      if (!mounted) return;
      if (restoreResult['ok'] == true) {
        showAppToast(
          context,
          message: restoreResult['message']?.toString() ?? 'Backup restored successfully!',
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
