import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class LocalFinanceStore {
  LocalFinanceStore._();

  static final LocalFinanceStore instance = LocalFinanceStore._();

  final Map<String, Map<String, dynamic>> _memoryRows = {};
  final ValueNotifier<int> changes = ValueNotifier(0);
  final ValueNotifier<int> pendingChanges = ValueNotifier(0);
  Future<Database?>? _opening;

  Future<Database?> _database() {
    return _opening ??= _openDatabase();
  }

  Future<Database?> _openDatabase() async {
    try {
      final root = await getDatabasesPath();
      return openDatabase(
        p.join(root, 'budget_ai_finance.db'),
        version: 1,
        onCreate: (database, _) async {
          await database.execute('''
            CREATE TABLE finance_entries (
              id TEXT PRIMARY KEY,
              payload_json TEXT NOT NULL,
              revision INTEGER NOT NULL DEFAULT 1,
              updated_at INTEGER NOT NULL,
              deleted_at INTEGER,
              sync_state TEXT NOT NULL DEFAULT 'pending'
                CHECK (sync_state IN ('clean', 'pending', 'failed'))
            )
          ''');
          await database.execute('''
            CREATE INDEX finance_entries_sync_idx
            ON finance_entries (sync_state, updated_at)
          ''');
        },
      );
    } on MissingPluginException catch (error) {
      debugPrint('[LocalFinanceStore] Using memory fallback: $error');
      return null;
    } catch (error) {
      debugPrint('[LocalFinanceStore] Could not open SQLite: $error');
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> readActive() async {
    final database = await _database();
    if (database == null) {
      return _memoryRows.values
          .where((row) => row['deleted_at'] == null)
          .map(
            (row) => Map<String, dynamic>.from(
              jsonDecode(row['payload_json']! as String) as Map,
            ),
          )
          .toList(growable: false);
    }
    final rows = await database.query(
      'finance_entries',
      columns: const ['payload_json'],
      where: 'deleted_at IS NULL',
    );
    return rows
        .map(
          (row) => Map<String, dynamic>.from(
            jsonDecode(row['payload_json']! as String) as Map,
          ),
        )
        .toList(growable: false);
  }

  Future<bool> isEmpty() async {
    final database = await _database();
    if (database == null) return _memoryRows.isEmpty;
    final result = Sqflite.firstIntValue(
      await database.rawQuery('SELECT COUNT(*) FROM finance_entries'),
    );
    return (result ?? 0) == 0;
  }

  Future<void> replaceActive(List<Map<String, dynamic>> entries) async {
    final now = DateTime.now().toUtc().microsecondsSinceEpoch;
    final incomingIds = entries.map((entry) => entry['id']! as String).toSet();
    final database = await _database();
    if (database == null) {
      var changed = false;
      for (final row in _memoryRows.values) {
        if (!incomingIds.contains(row['id']) && row['deleted_at'] == null) {
          row['deleted_at'] = now;
          row['updated_at'] = now;
          row['sync_state'] = 'pending';
          row['revision'] = (row['revision']! as int) + 1;
          changed = true;
        }
      }
      for (final entry in entries) {
        final id = entry['id']! as String;
        final payloadJson = jsonEncode(entry);
        final previous = _memoryRows[id];
        if (previous != null &&
            previous['deleted_at'] == null &&
            previous['payload_json'] == payloadJson) {
          continue;
        }
        _memoryRows[id] = {
          'id': id,
          'payload_json': payloadJson,
          'revision': (previous?['revision'] as int? ?? 0) + 1,
          'updated_at': now,
          'deleted_at': null,
          'sync_state': 'pending',
        };
        changed = true;
      }
      if (changed) {
        changes.value++;
        pendingChanges.value++;
      }
      return;
    }

    final changed = await database.transaction<bool>((transaction) async {
      var changed = false;
      final existingRows = {
        for (final row in await transaction.query(
          'finance_entries',
          columns: const ['id', 'payload_json', 'revision', 'deleted_at'],
        ))
          row['id']! as String: row,
      };
      if (incomingIds.isEmpty) {
        final count = await transaction.rawUpdate(
          '''
          UPDATE finance_entries
          SET deleted_at = ?, updated_at = ?, sync_state = 'pending',
              revision = revision + 1
          WHERE deleted_at IS NULL
          ''',
          [now, now],
        );
        changed = count > 0;
      } else {
        final placeholders = List.filled(incomingIds.length, '?').join(',');
        final count = await transaction.rawUpdate(
          '''
          UPDATE finance_entries
          SET deleted_at = ?, updated_at = ?, sync_state = 'pending',
              revision = revision + 1
          WHERE deleted_at IS NULL AND id NOT IN ($placeholders)
          ''',
          [now, now, ...incomingIds],
        );
        changed = count > 0;
      }
      for (final entry in entries) {
        final id = entry['id']! as String;
        final payloadJson = jsonEncode(entry);
        final existing = existingRows[id];
        if (existing != null &&
            existing['deleted_at'] == null &&
            existing['payload_json'] == payloadJson) {
          continue;
        }
        await transaction.rawInsert(
          '''
          INSERT INTO finance_entries (
            id, payload_json, revision, updated_at, deleted_at, sync_state
          ) VALUES (?, ?, 1, ?, NULL, 'pending')
          ON CONFLICT(id) DO UPDATE SET
            payload_json = excluded.payload_json,
            revision = finance_entries.revision + 1,
            updated_at = excluded.updated_at,
            deleted_at = NULL,
            sync_state = 'pending'
          ''',
          [id, payloadJson, now],
        );
        changed = true;
      }
      return changed;
    });
    if (changed) {
      changes.value++;
      pendingChanges.value++;
    }
  }

  Future<List<Map<String, dynamic>>> pendingRows() async {
    final database = await _database();
    if (database == null) {
      return _memoryRows.values
          .where((row) => row['sync_state'] == 'pending')
          .map(Map<String, dynamic>.from)
          .toList(growable: false);
    }
    return (await database.query(
      'finance_entries',
      where: "sync_state = 'pending'",
      orderBy: 'updated_at, id',
    )).map(Map<String, dynamic>.from).toList(growable: false);
  }

  Future<void> markClean(Map<String, int> revisions) async {
    if (revisions.isEmpty) return;
    final database = await _database();
    if (database == null) {
      for (final entry in revisions.entries) {
        final row = _memoryRows[entry.key];
        if (row != null && row['revision'] == entry.value) {
          row['sync_state'] = 'clean';
        }
      }
      return;
    }
    await database.transaction((transaction) async {
      for (final entry in revisions.entries) {
        await transaction.rawUpdate(
          "UPDATE finance_entries SET sync_state = 'clean' "
          'WHERE id = ? AND revision = ?',
          [entry.key, entry.value],
        );
      }
    });
  }

  Future<void> markActiveMissingRemotePending(Set<String> remoteIds) async {
    final now = DateTime.now().toUtc().microsecondsSinceEpoch;
    final database = await _database();
    var changed = false;
    if (database == null) {
      for (final row in _memoryRows.values) {
        if (row['deleted_at'] == null &&
            row['sync_state'] == 'clean' &&
            !remoteIds.contains(row['id'])) {
          row['revision'] = (row['revision']! as int) + 1;
          row['updated_at'] = now;
          row['sync_state'] = 'pending';
          changed = true;
        }
      }
    } else if (remoteIds.isEmpty) {
      changed =
          await database.rawUpdate(
            '''
            UPDATE finance_entries
            SET revision = revision + 1, updated_at = ?, sync_state = 'pending'
            WHERE deleted_at IS NULL AND sync_state = 'clean'
            ''',
            [now],
          ) >
          0;
    } else {
      final placeholders = List.filled(remoteIds.length, '?').join(',');
      changed =
          await database.rawUpdate(
            '''
            UPDATE finance_entries
            SET revision = revision + 1, updated_at = ?, sync_state = 'pending'
            WHERE deleted_at IS NULL AND sync_state = 'clean'
              AND id NOT IN ($placeholders)
            ''',
            [now, ...remoteIds],
          ) >
          0;
    }
    if (changed) {
      changes.value++;
      pendingChanges.value++;
    }
  }

  /// Marks every local row as pending so the next sync re-pushes (and
  /// re-encrypts) all of it from scratch. Used when the account's
  /// encryption key is rotated/reset, since previously-clean rows were
  /// only ever encrypted under the old key.
  Future<void> markAllPending() async {
    final now = DateTime.now().toUtc().microsecondsSinceEpoch;
    final database = await _database();
    var changed = false;
    if (database == null) {
      for (final row in _memoryRows.values) {
        row['revision'] = (row['revision']! as int) + 1;
        row['updated_at'] = now;
        row['sync_state'] = 'pending';
        changed = _memoryRows.isNotEmpty;
      }
    } else {
      changed =
          await database.rawUpdate(
            '''
            UPDATE finance_entries
            SET revision = revision + 1, updated_at = ?, sync_state = 'pending'
            ''',
            [now],
          ) >
          0;
    }
    if (changed) {
      changes.value++;
      pendingChanges.value++;
    }
  }

  Future<void> applyRemoteRows(List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty) return;
    final database = await _database();
    if (database == null) {
      var changed = false;
      for (final remote in rows) {
        final id = remote['id']! as String;
        final local = _memoryRows[id];
        if (local?['sync_state'] == 'pending') continue;
        if (local != null &&
            local['revision'] == remote['revision'] &&
            local['payload_json'] == remote['payload_json'] &&
            local['deleted_at'] == remote['deleted_at']) {
          continue;
        }
        _memoryRows[id] = Map<String, dynamic>.from(remote)
          ..['sync_state'] = 'clean';
        changed = true;
      }
      if (changed) changes.value++;
      return;
    }
    final changed = await database.transaction<bool>((transaction) async {
      var changed = false;
      for (final remote in rows) {
        final id = remote['id']! as String;
        final existing = await transaction.query(
          'finance_entries',
          columns: const [
            'sync_state',
            'revision',
            'payload_json',
            'deleted_at',
          ],
          where: 'id = ?',
          whereArgs: [id],
          limit: 1,
        );
        if (existing.isNotEmpty && existing.single['sync_state'] == 'pending') {
          continue;
        }
        final localRevision = existing.isEmpty
            ? 0
            : existing.single['revision']! as int;
        final remoteRevision = remote['revision']! as int;
        if (remoteRevision < localRevision) continue;
        if (existing.isNotEmpty &&
            remoteRevision == localRevision &&
            existing.single['payload_json'] == remote['payload_json'] &&
            existing.single['deleted_at'] == remote['deleted_at']) {
          continue;
        }
        await transaction.insert('finance_entries', {
          ...remote,
          'sync_state': 'clean',
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        changed = true;
      }
      return changed;
    });
    if (changed) changes.value++;
  }

  void resetVolatileFallback() {
    _memoryRows.clear();
  }

  Future<void> clearAll() async {
    final database = await _database();
    _memoryRows.clear();
    if (database != null) await database.delete('finance_entries');
    changes.value++;
    pendingChanges.value++;
  }
}
