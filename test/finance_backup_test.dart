import 'dart:convert';
import 'dart:io';

import 'package:budget_ai/src/finances/finance_backup_service.dart';
import 'package:budget_ai/src/finances/finance_service.dart';
import 'package:budget_ai/src/storage/local_finance_store.dart';
import 'package:budget_ai/src/storage/local_settings_store.dart';
import 'package:budget_ai/src/sync/finance_sync_preference_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('budget_ai_backup_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => directory.path);
    await LocalFinanceStore.instance.clearAll();
    FinanceService.instance.invalidateCache();
    await LocalSettingsStore.instance.clearExcept(const {});
    FinanceSyncPreferenceService.instance.resetLocalState();
  });

  tearDown(() async {
    FinanceService.instance.invalidateCache();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await directory.delete(recursive: true);
  });

  test('a backup restores every entry and skips identical ones', () async {
    final finances = FinanceService.instance;
    await finances.add(_entry('lunch', 12));
    await finances.add(_entry('salary', 900, type: FinanceEntryType.income));
    final backup = finances.buildExportJson(await finances.getAll());
    expect(jsonDecode(backup)['app'], 'Budget AI');

    expect(await finances.importFromJson(backup), 0);

    await finances.delete('lunch');
    await finances.update(_entry('salary', 950, type: FinanceEntryType.income));
    expect(await finances.importFromJson(backup), 2);

    final restored = {
      for (final entry in await finances.getAll()) entry.id: entry.amount,
    };
    expect(restored, {'lunch': 12, 'salary': 900});
  });

  test('restoring a file that is not a backup is rejected', () async {
    await expectLater(
      FinanceService.instance.importFromJson('{"hello": "world"}'),
      throwsFormatException,
    );
  });

  test('cloud sync is off until the account choice is known', () async {
    final preference = FinanceSyncPreferenceService.instance;
    await preference.load();
    expect(preference.enabled.value, isFalse);
    expect(await preference.knownAccountValue(), isNull);

    await preference.applySyncedValue(true);
    expect(preference.enabled.value, isTrue);
    expect(await preference.knownAccountValue(), isTrue);
    expect(
      await LocalSettingsStore.instance.isPending(
        FinanceSyncPreferenceService.storageKey,
      ),
      isFalse,
    );

    await preference.setEnabled(false);
    expect(preference.enabled.value, isFalse);
    expect(
      await LocalSettingsStore.instance.isPending(
        FinanceSyncPreferenceService.storageKey,
      ),
      isTrue,
    );
  });

  test('entries at risk depend on whether cloud sync is on', () async {
    final finances = FinanceService.instance;
    await finances.add(_entry('coffee', 4));
    await finances.add(_entry('rent', 700));

    var atRisk = await FinanceBackupService.instance.entriesAtRisk();
    expect(atRisk.syncEnabled, isFalse);
    expect(atRisk.count, 2);
    expect(atRisk.entriesLabel, '2 entries');

    await FinanceSyncPreferenceService.instance.applySyncedValue(true);
    await LocalFinanceStore.instance.markClean({'coffee': 1});
    await finances.delete('rent');

    atRisk = await FinanceBackupService.instance.entriesAtRisk();
    expect(atRisk.syncEnabled, isTrue);
    expect(atRisk.isEmpty, isTrue);
  });

  test('backup files are named by date', () {
    expect(
      FinanceBackupService.backupFileName(DateTime(2026, 3, 7)),
      'BudgetAI-Backup-2026-03-07.json',
    );
  });
}

FinanceEntry _entry(
  String id,
  double amount, {
  FinanceEntryType type = FinanceEntryType.expense,
}) {
  final date = DateTime(2026, 10, 1);
  return FinanceEntry(
    id: id,
    type: type,
    date: date,
    hasTime: false,
    description: id,
    amount: amount,
    category: 'Other',
    createdAt: date,
  );
}
