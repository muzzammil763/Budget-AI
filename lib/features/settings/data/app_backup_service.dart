import 'dart:convert';
import 'dart:io';

import 'package:budget_ai/features/finance/data/finance_service.dart';
import 'package:budget_ai/features/memory/data/memory_service.dart';
import 'package:budget_ai/core/storage/shared_prefs_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class AppBackupService {
  AppBackupService._();
  static final AppBackupService instance = AppBackupService._();

  static const _backupVersion = 1;
  static const _backupFileName = 'BudgetAI_Backup.json';

  Future<Map<String, dynamic>> createBackup() async {
    final finances = await FinanceService.instance.getAll();
    final memories = await MemoryService.instance.getAll();

    final backup = {
      'version': _backupVersion,
      'exported_at': DateTime.now().toIso8601String(),
      'app': 'Budget AI',
      'data': {
        'finances': finances.map((e) => e.toJson()).toList(),
        'memories': memories.map((m) => m.toJson()).toList(),
      },
    };

    return backup;
  }

  Future<File> saveBackupToFile() async {
    final backup = await createBackup();
    final jsonStr = const JsonEncoder.withIndent('  ').convert(backup);

    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$_backupFileName');
    return file.writeAsString(jsonStr);
  }

  Future<void> shareBackup() async {
    final file = await saveBackupToFile();
    await Share.shareXFiles(
      [XFile(file.path)],
      subject: 'Budget AI Backup',
    );
  }

  Future<Map<String, dynamic>> restoreFromFile(File file) async {
    try {
      final content = await file.readAsString();
      final backup = jsonDecode(content) as Map<String, dynamic>;

      final version = backup['version'] as int? ?? 0;
      if (version > _backupVersion) {
        return {
          'ok': false,
          'error': 'Backup was created with a newer version of Budget AI.',
        };
      }

      final data = backup['data'] as Map<String, dynamic>? ?? {};

      // Restore finances
      final financesList = data['finances'] as List<dynamic>? ?? [];
      for (final item in financesList) {
        if (item is Map<String, dynamic>) {
          try {
            final entry = FinanceEntry.fromJson(item);
            await FinanceService.instance.add(entry);
          } catch (_) {}
        }
      }

      // Restore memories
      final memoriesList = data['memories'] as List<dynamic>? ?? [];
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
            }
          } catch (_) {}
        }
      }

      return {'ok': true, 'message': 'Backup restored successfully.'};
    } catch (e) {
      return {'ok': false, 'error': 'Failed to restore backup: $e'};
    }
  }
}
