import 'dart:async';
import 'dart:convert';

import 'package:budget_ai/src/finances/finance_service.dart';
import 'package:budget_ai/src/helpers/network_reachability_service.dart';
import 'package:budget_ai/src/storage/local_finance_store.dart';
import 'package:budget_ai/src/storage/local_settings_store.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

/// Temporary, unencrypted counterpart to `EncryptedFinanceSyncService`. See
/// ENCRYPTION_REVERT_PLAN.md at the repo root for why this exists and how to
/// revert back to the encrypted path — that service and its supporting
/// encryption code are untouched and still fully intact.
class PlainFinanceSyncService {
  PlainFinanceSyncService._();

  static final PlainFinanceSyncService instance = PlainFinanceSyncService._();
  static const _retryDelays = <Duration>[
    Duration(seconds: 2),
    Duration(seconds: 5),
    Duration(seconds: 10),
    Duration(seconds: 30),
    Duration(minutes: 1),
  ];
  static const _uploadBatchSize = 100;
  static const _backfillDoneKey = 'plain_finance_backfill_done_v1';

  final _uuid = const Uuid();
  RealtimeChannel? _channel;
  Timer? _retryTimer;
  String? _attachedUserId;
  bool _initialized = false;
  bool _syncing = false;
  bool _syncRequested = false;
  int _retryAttempt = 0;
  final ValueNotifier<String> status = ValueNotifier('Not enabled');

  SupabaseClient get _client => Supabase.instance.client;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    _client.auth.onAuthStateChange.listen(
      (state) => unawaited(_attachForUser(state.session?.user)),
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('[PlainFinanceSyncService] Auth offline: $error');
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
    // The new plaintext table starts empty. Make sure every already-clean
    // local entry gets re-pushed once so existing data (previously only
    // synced under encryption) actually shows up here, not just future
    // edits. Guarded so it only ever runs once per device.
    if (await LocalSettingsStore.instance.getBool(_backfillDoneKey) != true) {
      await LocalFinanceStore.instance.markAllPending();
      await LocalSettingsStore.instance.setBool(_backfillDoneKey, true);
    }
    _channel = _client
        .channel('plain-finance:${user.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'plain_finance_entries',
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
            debugPrint('[PlainFinanceSyncService] Realtime waiting: $error');
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
      var remoteRows = await _readRemoteRows(user.id);
      await LocalFinanceStore.instance.markActiveMissingRemotePending(
        remoteRows.map((row) => row['entry_id']! as String).toSet(),
      );

      final pending = await LocalFinanceStore.instance.pendingRows();
      if (pending.isNotEmpty) {
        await _pushPending(user, pending);
        remoteRows = await _readRemoteRows(user.id);
      }

      final merged = <Map<String, dynamic>>[];
      for (final remote in remoteRows) {
        final payload = Map<String, dynamic>.from(remote['payload']! as Map);
        final serverUpdatedAt = DateTime.parse(
          remote['server_updated_at']! as String,
        ).toUtc();
        merged.add({
          'id': remote['entry_id'],
          'payload_json': jsonEncode(payload),
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
      debugPrint('[PlainFinanceSyncService] Sync deferred: $error');
      status.value = 'Waiting for connection';
      _scheduleRetry();
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> _readRemoteRows(String userId) async {
    final rows = await _client
        .from('plain_finance_entries')
        .select()
        .eq('user_id', userId)
        .order('server_updated_at');
    return rows.map(Map<String, dynamic>.from).toList(growable: false);
  }

  Future<void> _pushPending(
    User user,
    List<Map<String, dynamic>> pending,
  ) async {
    for (var offset = 0; offset < pending.length; offset += _uploadBatchSize) {
      final end = (offset + _uploadBatchSize).clamp(0, pending.length);
      final batch = pending.sublist(offset, end);
      final plainRows = <Map<String, dynamic>>[];
      final pushedRevisions = <String, int>{};
      for (final row in batch) {
        final payload = Map<String, dynamic>.from(
          jsonDecode(row['payload_json']! as String) as Map,
        );
        final updatedAt = DateTime.fromMicrosecondsSinceEpoch(
          row['updated_at']! as int,
          isUtc: true,
        );
        plainRows.add({
          'user_id': user.id,
          'entry_id': row['id'],
          'payload': payload,
          'revision': row['revision'],
          'is_deleted': row['deleted_at'] != null,
          'client_updated_at': updatedAt.toIso8601String(),
          'device_id': _uuid.v4(),
          'operation_id': _uuid.v4(),
        });
        pushedRevisions[row['id']! as String] = row['revision']! as int;
      }
      await _client
          .from('plain_finance_entries')
          .upsert(plainRows, onConflict: 'user_id,entry_id');
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
