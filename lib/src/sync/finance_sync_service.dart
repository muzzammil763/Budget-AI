import 'dart:async';
import 'dart:convert';

import 'package:budget_ai/src/finances/finance_service.dart';
import 'package:budget_ai/src/helpers/network_reachability_service.dart';
import 'package:budget_ai/src/storage/local_finance_store.dart';
import 'package:budget_ai/src/sync/legacy_encryption_migration_service.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

/// Two-way sync between the local SQLite finance store and the plain
/// `finance_entries` table. Realtime and verified connectivity restoration
/// only invalidate; every sync pushes pending local rows, then pulls the
/// account's full remote state.
class FinanceSyncService {
  FinanceSyncService._();

  static final FinanceSyncService instance = FinanceSyncService._();
  static const table = 'finance_entries';
  static const _retryDelays = <Duration>[
    Duration(seconds: 2),
    Duration(seconds: 5),
    Duration(seconds: 10),
    Duration(seconds: 30),
    Duration(minutes: 1),
  ];
  static const _uploadBatchSize = 100;
  // PostgREST returns at most this many rows per request (`max_rows`).
  static const _pageSize = 1000;
  static const _uuid = Uuid();

  RealtimeChannel? _channel;
  Timer? _retryTimer;
  String? _attachedUserId;
  bool _initialized = false;
  bool _syncing = false;
  bool _syncRequested = false;
  int _retryAttempt = 0;
  final ValueNotifier<String> status = ValueNotifier('Not enabled');

  SupabaseClient get _client => Supabase.instance.client;

  /// Builds a `finance_entries` row from a local entry payload. Entry times
  /// are stored as wall-clock timestamps, the same way the app records them.
  static Map<String, dynamic> remoteRow({
    required String userId,
    required Map<String, dynamic> payload,
    required int revision,
    required bool isDeleted,
    required DateTime clientUpdatedAt,
  }) {
    final entry = FinanceEntry.fromJson(payload);
    return {
      'user_id': userId,
      'id': entry.id,
      'type': entry.type.storageValue,
      'amount': entry.amount,
      'category': entry.category,
      'description': entry.description,
      'date': _wallClock(entry.date),
      'has_time': entry.hasTime,
      'created_at': _wallClock(entry.createdAt),
      'revision': revision,
      'is_deleted': isDeleted,
      'client_updated_at': clientUpdatedAt.toUtc().toIso8601String(),
      'device_id': _uuid.v4(),
      'operation_id': _uuid.v4(),
    };
  }

  /// Converts a `finance_entries` row back into the canonical local payload.
  static Map<String, dynamic> payloadFromRemote(Map<String, dynamic> row) {
    return FinanceEntry.fromJson({
      'id': row['id'],
      'type': row['type'],
      'date': row['date'],
      'has_time': row['has_time'],
      'description': row['description'],
      'amount': row['amount'],
      'category': row['category'],
      'created_at': row['created_at'],
    }).toJson();
  }

  /// Reads every row of [table] for [userId], one page at a time. A single
  /// request is silently capped at the API's `max_rows`, so reading without
  /// paging drops rows once an account grows past that limit.
  static Future<List<Map<String, dynamic>>> readAllRows(
    SupabaseClient client, {
    required String table,
    required String userId,
    required String orderBy,
    String columns = '*',
  }) async {
    final rows = <Map<String, dynamic>>[];
    for (var offset = 0; ; offset += _pageSize) {
      final page = await client
          .from(table)
          .select(columns)
          .eq('user_id', userId)
          .order(orderBy)
          .range(offset, offset + _pageSize - 1);
      rows.addAll(page.map(Map<String, dynamic>.from));
      if (page.length < _pageSize) return rows;
    }
  }

  static String _wallClock(DateTime value) {
    return (value.isUtc ? value.toLocal() : value).toIso8601String();
  }

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    _client.auth.onAuthStateChange.listen(
      (state) => unawaited(_attachForUser(state.session?.user)),
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('[FinanceSyncService] Auth offline: $error');
        _scheduleRetry();
      },
    );
    LocalFinanceStore.instance.pendingChanges.addListener(_scheduleSync);
    NetworkReachabilityService.instance.status.addListener(
      _handleNetworkStatusChanged,
    );
    NetworkReachabilityService.instance.start(keepAlive: true);
    unawaited(_attachForUser(_client.auth.currentUser));
  }

  void _handleNetworkStatusChanged() {
    if (!NetworkReachabilityService.instance.isOnline) return;
    _resetRetry();
    unawaited(syncNow());
  }

  void _scheduleSync() {
    unawaited(syncNow());
  }

  Future<void> _attachForUser(User? user) async {
    if (user?.id == _attachedUserId && _channel != null) {
      await syncNow();
      return;
    }
    if (_channel != null) {
      await _client.removeChannel(_channel!);
      _channel = null;
    }
    _attachedUserId = user?.id;
    if (user == null) {
      status.value = 'Sign in to sync';
      _retryTimer?.cancel();
      return;
    }
    _channel = _client
        .channel('finance:${user.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: table,
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: user.id,
          ),
          callback: (_) => unawaited(syncNow()),
        )
        .subscribe((realtimeStatus, error) {
          if (realtimeStatus == RealtimeSubscribeStatus.subscribed) {
            unawaited(syncNow());
          } else if (realtimeStatus == RealtimeSubscribeStatus.channelError ||
              realtimeStatus == RealtimeSubscribeStatus.timedOut) {
            status.value = 'Waiting for connection';
            debugPrint('[FinanceSyncService] Realtime waiting: $error');
            _scheduleRetry();
          }
        });
    await syncNow();
  }

  Future<void> syncNow() async {
    _syncRequested = true;
    if (_syncing) return;
    _syncing = true;
    try {
      while (_syncRequested) {
        _syncRequested = false;
        final succeeded = await _syncOnce();
        if (!succeeded) break;
      }
    } finally {
      _syncing = false;
    }
  }

  Future<bool> _syncOnce() async {
    final user = _client.auth.currentUser;
    if (user == null) {
      status.value = 'Sign in to sync';
      return true;
    }
    status.value = 'Syncing…';
    try {
      // Existing encrypted rows must land in finance_entries before the
      // first plain sync, so deletions recorded only in the legacy table
      // are not lost by re-uploading this device's copy.
      final migration = await LegacyEncryptionMigrationService.instance.migrate(
        user.id,
      );
      if (migration == LegacyMigrationStatus.needsPassword) {
        status.value = 'Password required';
        return true;
      }

      var remoteRows = await _readRemoteRows(user.id);
      await LocalFinanceStore.instance.markActiveMissingRemotePending(
        remoteRows.map((row) => row['id']! as String).toSet(),
      );

      final pending = await LocalFinanceStore.instance.pendingRows();
      if (pending.isNotEmpty) {
        await _pushPending(user, pending);
        remoteRows = await _readRemoteRows(user.id);
      }

      final merged = <Map<String, dynamic>>[];
      for (final remote in remoteRows) {
        final serverUpdatedAt = DateTime.parse(
          remote['server_updated_at']! as String,
        ).toUtc();
        merged.add({
          'id': remote['id'],
          'payload_json': jsonEncode(payloadFromRemote(remote)),
          'revision': remote['revision'],
          'updated_at': serverUpdatedAt.microsecondsSinceEpoch,
          'deleted_at': remote['is_deleted'] == true
              ? serverUpdatedAt.microsecondsSinceEpoch
              : null,
        });
      }
      await LocalFinanceStore.instance.applyRemoteRows(merged);
      FinanceService.instance.invalidateCacheFromSync();
      await FinanceService.instance.syncHomeWidget();
      status.value = 'Up to date';
      _resetRetry();
      return true;
    } catch (error) {
      debugPrint('[FinanceSyncService] Sync deferred: $error');
      status.value = 'Waiting for connection';
      _scheduleRetry();
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> _readRemoteRows(String userId) async {
    return readAllRows(_client, table: table, userId: userId, orderBy: 'id');
  }

  Future<void> _pushPending(
    User user,
    List<Map<String, dynamic>> pending,
  ) async {
    for (var offset = 0; offset < pending.length; offset += _uploadBatchSize) {
      final end = (offset + _uploadBatchSize).clamp(0, pending.length);
      final batch = pending.sublist(offset, end);
      final rows = <Map<String, dynamic>>[];
      final pushedRevisions = <String, int>{};
      for (final row in batch) {
        final payload = Map<String, dynamic>.from(
          jsonDecode(row['payload_json']! as String) as Map,
        );
        payload['id'] = row['id'];
        rows.add(
          remoteRow(
            userId: user.id,
            payload: payload,
            revision: row['revision']! as int,
            isDeleted: row['deleted_at'] != null,
            clientUpdatedAt: DateTime.fromMicrosecondsSinceEpoch(
              row['updated_at']! as int,
              isUtc: true,
            ),
          ),
        );
        pushedRevisions[row['id']! as String] = row['revision']! as int;
      }
      await _client.from(table).upsert(rows, onConflict: 'user_id,id');
      await LocalFinanceStore.instance.markClean(pushedRevisions);
    }
  }

  void _scheduleRetry() {
    if (_retryTimer?.isActive ?? false) return;
    final index = _retryAttempt.clamp(0, _retryDelays.length - 1);
    final delay = _retryDelays[index];
    _retryAttempt++;
    _retryTimer = Timer(delay, () {
      _retryTimer = null;
      unawaited(syncNow());
    });
  }

  void _resetRetry() {
    _retryAttempt = 0;
    _retryTimer?.cancel();
    _retryTimer = null;
  }
}
