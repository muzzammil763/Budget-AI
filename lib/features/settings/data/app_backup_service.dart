import 'dart:convert';
import 'dart:io';

import 'package:budget_ai/features/finance/data/finance_service.dart';
import 'package:budget_ai/features/memory/data/memory_service.dart';
import 'package:budget_ai/features/settings/data/api_key_storage_service.dart';
import 'package:budget_ai/core/storage/shared_prefs_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class AppBackupService {
  AppBackupService._();
  static final AppBackupService instance = AppBackupService._();

  static const _backupVersion = 2;

  String _backupFileName(DateTime exportedAt) {
    final hour = exportedAt.hour == 0
        ? 12
        : exportedAt.hour > 12
        ? exportedAt.hour - 12
        : exportedAt.hour;
    final minute = exportedAt.minute.toString().padLeft(2, '0');
    final period = exportedAt.hour >= 12 ? 'PM' : 'AM';
    final date =
        '${exportedAt.month.toString().padLeft(2, '0')}-${exportedAt.day.toString().padLeft(2, '0')}-${exportedAt.year}';
    return 'Backup Budget AI $date $hour $minute $period.json';
  }

  Future<Map<String, dynamic>> createBackup() async {
    final finances = await FinanceService.instance.getAll();
    final memories = await MemoryService.instance.getAll();
    final deepseekKeys = await ApiKeyStorageService.getDeepSeekApiKeys();
    final searchKeys = await ApiKeyStorageService.getSearchApiKeys();
    final selectedModel =
        SharedPrefsService.getSelectedDeepSeekModel() ??
        SharedPrefsService.instance.getString('deepseek_selected_model');

    final backup = {
      'version': _backupVersion,
      'exported_at': DateTime.now().toIso8601String(),
      'app': 'Budget AI',
      'api_keys': {'deepseek': deepseekKeys, 'searchapi': searchKeys},
      'settings': {
        if (selectedModel != null && selectedModel.isNotEmpty)
          'selected_deepseek_model': selectedModel,
      },
      'data': {
        'finances': finances.map((e) => e.toJson()).toList(),
        'memories': memories.map((m) => m.toJson()).toList(),
      },
    };

    return backup;
  }

  Future<File> saveBackupToFile() async {
    final now = DateTime.now();
    final backup = await createBackup();
    final jsonStr = const JsonEncoder.withIndent('  ').convert(backup);

    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/${_backupFileName(now)}');
    return file.writeAsString(jsonStr);
  }

  Future<void> shareBackup() async {
    final file = await saveBackupToFile();
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'application/json')],
        subject: 'Budget AI Backup',
      ),
    );
  }

  String? _extractKey(dynamic value) {
    if (value == null) return null;
    if (value is String) {
      // Clean up the key - remove brackets, quotes, etc.
      var cleaned = value.trim();
      // Handle case where key is stored as JSON array string like '["key"]'
      if (cleaned.startsWith('[') && cleaned.endsWith(']')) {
        try {
          final parsed = jsonDecode(cleaned);
          if (parsed is List && parsed.isNotEmpty) {
            cleaned = parsed.first.toString().trim();
          }
        } catch (_) {
          // Just remove the brackets
          cleaned = cleaned.substring(1, cleaned.length - 1).trim();
        }
      }
      // Remove surrounding quotes if present
      if (cleaned.startsWith('"') && cleaned.endsWith('"')) {
        cleaned = cleaned.substring(1, cleaned.length - 1).trim();
      }
      if (cleaned.startsWith("'") && cleaned.endsWith("'")) {
        cleaned = cleaned.substring(1, cleaned.length - 1).trim();
      }
      return cleaned.isEmpty ? null : cleaned;
    }
    if (value is List && value.isNotEmpty) {
      return _extractKey(value.first);
    }
    return value.toString().trim();
  }

  List<String> _extractKeys(dynamic value) {
    if (value == null) return const [];
    if (value is List) {
      return value
          .map(_extractKey)
          .whereType<String>()
          .where((key) => key.isNotEmpty)
          .toSet()
          .toList();
    }
    final key = _extractKey(value);
    return key == null || key.isEmpty ? const [] : [key];
  }

  Future<Map<String, dynamic>> restoreFromFile(File file) async {
    try {
      final content = await file.readAsString();
      final backup = jsonDecode(content) as Map<String, dynamic>;

      final app = backup['app']?.toString() ?? '';
      final restoredItems = <String>[];

      // Restore API keys - handle both Budget AI and OpenGate formats
      final apiKeys = backup['api_keys'] as Map<String, dynamic>?;

      if (apiKeys != null) {
        // Budget AI format
        final deepseekKeys = _extractKeys(apiKeys['deepseek']);
        final searchKeys = _extractKeys(apiKeys['searchapi']);

        if (deepseekKeys.isNotEmpty) {
          await ApiKeyStorageService.saveApiKeys('deepseek', deepseekKeys);
          restoredItems.add(
            deepseekKeys.length == 1
                ? 'DeepSeek key'
                : '${deepseekKeys.length} DeepSeek keys',
          );
        }
        if (searchKeys.isNotEmpty) {
          await ApiKeyStorageService.saveApiKeys('searchapi', searchKeys);
          restoredItems.add(
            searchKeys.length == 1
                ? 'SearchAPI key'
                : '${searchKeys.length} SearchAPI keys',
          );
        }
      } else if (app == 'OpenGate') {
        // OpenGate format - try different possible locations
        final data = backup['data'] as Map<String, dynamic>?;
        final settings = data?['settings'] as Map<String, dynamic>?;

        // Try to find keys in various locations
        dynamic deepseekValue =
            backup['deepseek_api_key'] ??
            settings?['deepseek_api_key'] ??
            settings?['api_keys']?['deepseek'];
        dynamic searchValue =
            backup['searchapi_api_key'] ??
            settings?['searchapi_api_key'] ??
            settings?['api_keys']?['searchapi'];

        final deepseekKey = _extractKey(deepseekValue);
        final searchKey = _extractKey(searchValue);

        if (deepseekKey != null && deepseekKey.isNotEmpty) {
          await ApiKeyStorageService.saveApiKeys('deepseek', [deepseekKey]);
          restoredItems.add('DeepSeek key');
        }
        if (searchKey != null && searchKey.isNotEmpty) {
          await ApiKeyStorageService.saveApiKeys('searchapi', [searchKey]);
          restoredItems.add('SearchAPI key');
        }
      }

      final settings = backup['settings'] as Map<String, dynamic>?;
      final selectedModel =
          settings?['selected_deepseek_model']?.toString() ??
          backup['selected_deepseek_model']?.toString();
      if (selectedModel != null && selectedModel.isNotEmpty) {
        await SharedPrefsService.setSelectedDeepSeekModel(selectedModel);
        await SharedPrefsService.instance.setString(
          'deepseek_selected_model',
          selectedModel,
        );
        restoredItems.add('selected model');
      }

      final data = backup['data'] as Map<String, dynamic>? ?? {};

      // Restore finances - handle both list and object formats
      var financesList = <dynamic>[];
      final rawFinances = data['finances'];
      if (rawFinances is List) {
        financesList = rawFinances;
      } else if (rawFinances is Map && rawFinances['finances'] is List) {
        // Old format where buildExportJson wrapped in object
        financesList = rawFinances['finances'] as List<dynamic>;
      }
      var financeCount = 0;
      for (final item in financesList) {
        if (item is Map<String, dynamic>) {
          try {
            final entry = FinanceEntry.fromJson(item);
            await FinanceService.instance.add(entry);
            financeCount++;
          } catch (_) {}
        }
      }
      if (financeCount > 0) {
        restoredItems.add('$financeCount finances');
      }

      // Restore memories - handle both list and object formats
      var memoriesList = <dynamic>[];
      final rawMemories = data['memories'];
      if (rawMemories is List) {
        memoriesList = rawMemories;
      } else if (rawMemories is Map && rawMemories['memories'] is List) {
        // Old format where buildExportJson wrapped in object
        memoriesList = rawMemories['memories'] as List<dynamic>;
      }
      var memoryCount = 0;
      for (final item in memoriesList) {
        if (item is Map<String, dynamic>) {
          try {
            final key = item['key']?.toString() ?? '';
            final title = item['title']?.toString() ?? '';
            final content = item['content']?.toString() ?? '';
            final type = item['type']?.toString() ?? 'fact';
            if (key.isNotEmpty) {
              await MemoryService.instance.write(
                key: key,
                title: title,
                content: content,
                type: type,
              );
              memoryCount++;
            }
          } catch (_) {}
        }
      }
      if (memoryCount > 0) {
        restoredItems.add('$memoryCount memories');
      }

      if (restoredItems.isEmpty) {
        return {'ok': true, 'message': 'Backup loaded but nothing to restore.'};
      }

      return {'ok': true, 'message': 'Restored: ${restoredItems.join(", ")}'};
    } catch (e) {
      return {'ok': false, 'error': 'Failed to restore backup: $e'};
    }
  }
}
