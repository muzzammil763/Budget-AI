import 'dart:convert';

import 'package:budget_ai/src/finances/finance_service.dart';
import 'package:budget_ai/src/storage/local_finance_store.dart';
import 'package:budget_ai/src/storage/local_settings_store.dart';
import 'package:budget_ai/src/sync/finance_sync_preference_service.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

/// Entries that would be lost if this device's data were erased.
class EntriesAtRisk {
  const EntriesAtRisk({required this.count, required this.syncEnabled});

  final int count;

  /// With Cloud Sync on, [count] is the entries not uploaded yet; with it
  /// off, every entry on the device.
  final bool syncEnabled;

  bool get isEmpty => count == 0;

  String get entriesLabel => '$count ${count == 1 ? 'entry' : 'entries'}';
}

/// Saves finance entries to a backup file the user keeps, and restores them.
class FinanceBackupService {
  FinanceBackupService._();

  static final FinanceBackupService instance = FinanceBackupService._();

  static const _lastBackupKey = 'finance_last_backup_at';

  /// When this device last saved a backup, or null if it never has.
  final ValueNotifier<DateTime?> lastBackupAt = ValueNotifier(null);

  Future<void> load() async {
    final raw = await LocalSettingsStore.instance.getString(_lastBackupKey);
    lastBackupAt.value = raw == null ? null : DateTime.tryParse(raw);
  }

  void resetLocalState() {
    lastBackupAt.value = null;
  }

  static String backupFileName(DateTime now) {
    String two(int value) => value.toString().padLeft(2, '0');
    return 'BudgetAI-Backup-${now.year}-${two(now.month)}-${two(now.day)}'
        '.json';
  }

  Future<EntriesAtRisk> entriesAtRisk() async {
    final syncEnabled = FinanceSyncPreferenceService.instance.enabled.value;
    final count = syncEnabled
        ? await LocalFinanceStore.instance.activePendingCount()
        : (await FinanceService.instance.getAll()).length;
    return EntriesAtRisk(count: count, syncEnabled: syncEnabled);
  }

  /// Asks where to save a backup of every entry. Returns the number of
  /// entries saved, or null when the user cancelled.
  Future<int?> saveBackup() async {
    final entries = await FinanceService.instance.getAll();
    final json = FinanceService.instance.buildExportJson(entries);
    final now = DateTime.now();
    final savedTo = await FilePicker.saveFile(
      dialogTitle: 'Save Budget AI backup',
      fileName: backupFileName(now),
      bytes: Uint8List.fromList(utf8.encode(json)),
    );
    if (savedTo == null) return null;
    lastBackupAt.value = now;
    await LocalSettingsStore.instance.setString(
      _lastBackupKey,
      now.toIso8601String(),
    );
    return entries.length;
  }

  /// Lets the user pick a backup file and merges it into this device's
  /// entries. Returns how many entries were added or changed, or null when
  /// the user cancelled. Throws [FormatException] for files that are not a
  /// Budget AI backup.
  Future<int?> restoreBackup() async {
    final file = await FilePicker.pickFile(dialogTitle: 'Choose a backup');
    if (file == null) return null;
    final String raw;
    try {
      raw = utf8.decode(await file.readAsBytes());
    } on FormatException {
      throw const FormatException('This file is not a Budget AI backup.');
    }
    try {
      return await FinanceService.instance.importFromJson(raw);
    } catch (error) {
      debugPrint('[FinanceBackupService] Restore failed: $error');
      throw const FormatException('This file is not a Budget AI backup.');
    }
  }
}
