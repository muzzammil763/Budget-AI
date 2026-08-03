import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

enum SettingSyncScope { local, account }

class LocalSettingsStore {
  LocalSettingsStore._();

  static final LocalSettingsStore instance = LocalSettingsStore._();
  static const _migrationKey = 'legacy_shared_preferences_migrated_v1';

  final Map<String, Object?> _memoryFallback = {};
  final Map<String, Map<String, Object?>> _memoryRows = {};
  final ValueNotifier<int> changes = ValueNotifier(0);
  final ValueNotifier<int> accountPendingChanges = ValueNotifier(0);
  Future<Database?>? _opening;

  Future<Database?> _database() {
    return _opening ??= _openDatabase();
  }

  Future<Database?> _openDatabase() async {
    try {
      final root = await getDatabasesPath();
      return openDatabase(
        p.join(root, 'budget_ai_local.db'),
        version: 1,
        onCreate: (database, _) async {
          await database.execute('''
            CREATE TABLE local_settings (
              key TEXT PRIMARY KEY,
              value_json TEXT NOT NULL,
              sync_scope TEXT NOT NULL
                CHECK (sync_scope IN ('local', 'account')),
              updated_at INTEGER NOT NULL,
              sync_state TEXT NOT NULL DEFAULT 'clean'
                CHECK (sync_state IN ('clean', 'pending', 'failed'))
            )
          ''');
          await database.execute('''
            CREATE INDEX local_settings_sync_idx
            ON local_settings (sync_scope, sync_state, updated_at)
          ''');
        },
      );
    } on MissingPluginException catch (error) {
      debugPrint('[LocalSettingsStore] Using memory fallback: $error');
      return null;
    } catch (error) {
      debugPrint('[LocalSettingsStore] Could not open SQLite: $error');
      return null;
    }
  }

  Future<void> migrateLegacyPreferences() async {
    if (await getBool(_migrationKey) == true) return;
    final legacy = await SharedPreferencesAsync().getAll();
    for (final entry in legacy.entries) {
      if (entry.value is! String &&
          entry.value is! bool &&
          entry.value is! int &&
          entry.value is! double &&
          entry.value is! List<String>) {
        continue;
      }
      if (await containsKey(entry.key)) continue;
      await setValue(
        entry.key,
        entry.value,
        scope: _scopeForLegacyKey(entry.key),
        pendingSync: _scopeForLegacyKey(entry.key) == SettingSyncScope.account,
      );
    }
    await setBool(_migrationKey, true);
  }

  SettingSyncScope _scopeForLegacyKey(String key) {
    const accountKeys = {
      'budget_user_name',
      'budget_selected_model_id',
      'budget_currency_display_text',
      'budget_custom_currencies',
      'budget_user_bubble_style',
    };
    return accountKeys.contains(key)
        ? SettingSyncScope.account
        : SettingSyncScope.local;
  }

  Future<bool> containsKey(String key) async {
    final database = await _database();
    if (database == null) return _memoryFallback.containsKey(key);
    final rows = await database.query(
      'local_settings',
      columns: const ['key'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<Object?> getValue(String key) async {
    final database = await _database();
    if (database == null) return _memoryFallback[key];
    final rows = await database.query(
      'local_settings',
      columns: const ['value_json'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return jsonDecode(rows.single['value_json']! as String);
  }

  Future<bool> isPending(String key) async {
    final database = await _database();
    if (database == null) {
      return _memoryRows[key]?['sync_state'] == 'pending';
    }
    final rows = await database.query(
      'local_settings',
      columns: const ['sync_state'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isNotEmpty && rows.single['sync_state'] == 'pending';
  }

  Future<String?> getString(String key) async {
    final value = await getValue(key);
    return value is String ? value : null;
  }

  Future<bool?> getBool(String key) async {
    final value = await getValue(key);
    return value is bool ? value : null;
  }

  Future<List<String>?> getStringList(String key) async {
    final value = await getValue(key);
    if (value is! List) return null;
    return value.whereType<String>().toList(growable: false);
  }

  Future<void> setString(
    String key,
    String value, {
    SettingSyncScope scope = SettingSyncScope.local,
  }) {
    return setValue(
      key,
      value,
      scope: scope,
      pendingSync: scope == SettingSyncScope.account,
    );
  }

  Future<void> setBool(
    String key,
    bool value, {
    SettingSyncScope scope = SettingSyncScope.local,
  }) {
    return setValue(
      key,
      value,
      scope: scope,
      pendingSync: scope == SettingSyncScope.account,
    );
  }

  Future<void> setStringList(
    String key,
    List<String> value, {
    SettingSyncScope scope = SettingSyncScope.local,
  }) {
    return setValue(
      key,
      value,
      scope: scope,
      pendingSync: scope == SettingSyncScope.account,
    );
  }

  Future<void> setValue(
    String key,
    Object? value, {
    required SettingSyncScope scope,
    bool pendingSync = false,
  }) async {
    final updatedAt = DateTime.now().toUtc().microsecondsSinceEpoch;
    final database = await _database();
    if (database == null) {
      _memoryFallback[key] = value;
      _memoryRows[key] = {
        'key': key,
        'value_json': jsonEncode(value),
        'sync_scope': scope.name,
        'updated_at': updatedAt,
        'sync_state': pendingSync ? 'pending' : 'clean',
      };
      changes.value++;
      if (pendingSync && scope == SettingSyncScope.account) {
        accountPendingChanges.value++;
      }
      return;
    }
    await database.insert('local_settings', {
      'key': key,
      'value_json': jsonEncode(value),
      'sync_scope': scope.name,
      'updated_at': updatedAt,
      'sync_state': pendingSync ? 'pending' : 'clean',
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    changes.value++;
    if (pendingSync && scope == SettingSyncScope.account) {
      accountPendingChanges.value++;
    }
  }

  Future<void> remove(String key) async {
    final database = await _database();
    if (database == null) {
      _memoryFallback.remove(key);
      _memoryRows.remove(key);
      changes.value++;
      return;
    }
    await database.delete('local_settings', where: 'key = ?', whereArgs: [key]);
    changes.value++;
  }

  Future<Map<String, Object?>> getAll() async {
    final database = await _database();
    if (database == null) return Map.unmodifiable(_memoryFallback);
    final rows = await database.query('local_settings', orderBy: 'key');
    return {
      for (final row in rows)
        row['key']! as String: jsonDecode(row['value_json']! as String),
    };
  }

  Future<List<Map<String, Object?>>> accountRows() async {
    final database = await _database();
    if (database == null) {
      return _memoryRows.values
          .where((row) => row['sync_scope'] == SettingSyncScope.account.name)
          .map(Map<String, Object?>.from)
          .toList(growable: false)
        ..sort(
          (left, right) => (left['updated_at']! as int).compareTo(
            right['updated_at']! as int,
          ),
        );
    }
    return database.query(
      'local_settings',
      where: "sync_scope = 'account'",
      orderBy: 'updated_at, key',
    );
  }

  Future<void> markAccountCleanThrough(int updatedAt) async {
    final database = await _database();
    if (database == null) {
      for (final row in _memoryRows.values) {
        if (row['sync_scope'] == SettingSyncScope.account.name &&
            row['sync_state'] == 'pending' &&
            (row['updated_at']! as int) <= updatedAt) {
          row['sync_state'] = 'clean';
        }
      }
      return;
    }
    await database.rawUpdate(
      "UPDATE local_settings SET sync_state = 'clean' "
      "WHERE sync_scope = 'account' AND sync_state = 'pending' "
      'AND updated_at <= ?',
      [updatedAt],
    );
  }

  Future<void> clearExcept(Set<String> preservedKeys) async {
    final database = await _database();
    _memoryFallback.removeWhere((key, _) => !preservedKeys.contains(key));
    _memoryRows.removeWhere((key, _) => !preservedKeys.contains(key));
    if (database != null) {
      if (preservedKeys.isEmpty) {
        await database.delete('local_settings');
      } else {
        final placeholders = List.filled(preservedKeys.length, '?').join(',');
        await database.delete(
          'local_settings',
          where: 'key NOT IN ($placeholders)',
          whereArgs: preservedKeys.toList(growable: false),
        );
      }
    }
    changes.value++;
    accountPendingChanges.value++;
  }
}
