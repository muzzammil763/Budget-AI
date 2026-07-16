import 'dart:convert';
import 'dart:io';

import 'package:budget_ai/src/finances/finance_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class AppBackupService {
  AppBackupService._();
  static final AppBackupService instance = AppBackupService._();

  static const _backupVersion = 3;

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

    final backup = {
      'version': _backupVersion,
      'exported_at': DateTime.now().toIso8601String(),
      'app': 'Budget AI',
      'data': {'finances': finances.map((e) => e.toJson()).toList()},
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

  List<dynamic> _extractBackupList(
    Map<String, dynamic> backup,
    String key, {
    Map<String, dynamic>? data,
  }) {
    final candidates = <dynamic>[data?[key], backup[key]];

    for (final candidate in candidates) {
      if (candidate is List) return candidate;
      if (candidate is Map && candidate[key] is List) {
        return candidate[key] as List<dynamic>;
      }
    }

    return const [];
  }

  Future<Map<String, dynamic>> restoreFromFile(File file) async {
    try {
      final content = await file.readAsString();
      final backup = jsonDecode(content) as Map<String, dynamic>;

      final restoredItems = <String>[];

      final data = backup['data'] as Map<String, dynamic>? ?? {};

      // Restore finances.
      final financesList = _extractBackupList(backup, 'finances', data: data);
      var financeCount = 0;
      if (financesList.isNotEmpty) {
        financeCount = await FinanceService.instance.importFromJson(
          jsonEncode({'finances': financesList}),
        );
      }
      if (financeCount > 0) {
        restoredItems.add('$financeCount finances');
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
