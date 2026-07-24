import 'dart:async';
import 'dart:convert';

import 'package:budget_ai/src/auth/auth_service.dart';
import 'package:budget_ai/src/finances/finance_service.dart';
import 'package:budget_ai/src/helpers/network_reachability_service.dart';
import 'package:budget_ai/src/storage/local_finance_store.dart';
import 'package:budget_ai/src/sync/account_encryption_service.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

class EncryptedFinanceSyncService {
  EncryptedFinanceSyncService._();

  static final EncryptedFinanceSyncService instance =
      EncryptedFinanceSyncService._();
  static const _retryDelays = <Duration>[
    Duration(seconds: 2),
    Duration(seconds: 5),
    Duration(seconds: 10),
    Duration(seconds: 30),
    Duration(minutes: 1),
  ];
  static const _uploadBatchSize = 100;

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
        debugPrint('[EncryptedFinanceSyncService] Auth offline: $error');
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
        .channel('encrypted-finance:${user.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'encrypted_finance_entries',
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
            debugPrint(
              '[EncryptedFinanceSyncService] Realtime waiting: $error',
            );
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
    if (!await AccountEncryptionService.instance.hasKey(user.id)) {
      status.value = 'Recovery key required';
      return true;
    }
    status.value = 'Syncing…';
    try {
      final encryption = await _client
          .from('user_encryption')
          .select('key_fingerprint,encryption_version')
          .eq('user_id', user.id)
          .maybeSingle();
      if (encryption == null) {
        status.value = 'Not enabled';
        return true;
      }
      final localFingerprint = await AccountEncryptionService.instance
          .fingerprint(user.id);
      if (localFingerprint != encryption['key_fingerprint']) {
        throw StateError('The recovery key does not match this account.');
      }

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
        final payload = await AccountEncryptionService.instance.decrypt(
          user.id,
          EncryptedPayload(
            ciphertext: remote['ciphertext']! as String,
            nonce: remote['nonce']! as String,
            mac: remote['mac']! as String,
            version: remote['encryption_version']! as int,
          ),
        );
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
      debugPrint('[EncryptedFinanceSyncService] Sync deferred: $error');
      status.value = 'Waiting for connection';
      _scheduleRetry();
      return false;
    }
  }

  /// Wipes this account's synced ciphertext, rotates to a brand-new key,
  /// and re-queues every local entry to push (and re-encrypt) again. Any
  /// other device still holding the old key will no longer be able to
  /// decrypt anything synced under the new one — it will need to sign in
  /// again to pick up the new key.
  Future<void> resetEncryption() async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw StateError('Sign in before resetting encryption.');
    }
    status.value = 'Resetting…';
    try {
      await _client
          .from('encrypted_finance_entries')
          .delete()
          .eq('user_id', user.id);
      await AccountEncryptionService.instance.rotateDataKey(user.id);
      final fingerprint = await AccountEncryptionService.instance.fingerprint(
        user.id,
      );
      final row = <String, dynamic>{
        'user_id': user.id,
        'key_fingerprint': fingerprint,
        'encryption_version': 1,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };
      // The old wrap (if any) belonged to the key we just replaced. If a
      // password is available right now, re-wrap the fresh key with it
      // immediately; otherwise clear the stale wrap so nothing tries to
      // unwrap a key that no longer exists — the next fresh sign-in on
      // this device backfills it automatically.
      final password = AuthService.instance.pendingPassword;
      if (password != null) {
        final wrapped = await AccountEncryptionService.instance
            .wrapKeyWithPassword(user.id, password);
        row.addAll({
          'password_salt': wrapped.salt,
          'wrapped_key_ciphertext': wrapped.ciphertext,
          'wrapped_key_nonce': wrapped.nonce,
          'wrapped_key_mac': wrapped.mac,
        });
        AuthService.instance.clearPendingPassword();
      } else {
        row.addAll({
          'password_salt': null,
          'wrapped_key_ciphertext': null,
          'wrapped_key_nonce': null,
          'wrapped_key_mac': null,
        });
      }
      await _client.from('user_encryption').upsert(row);
      await LocalFinanceStore.instance.markAllPending();
      unawaited(syncNow());
    } catch (error) {
      status.value = 'Waiting for connection';
      rethrow;
    }
  }

  /// Wraps this device's cached data key under [password] and publishes the
  /// envelope to `user_encryption`, so any other device that knows the
  /// account password can unwrap the same data key on login instead of
  /// requiring a manually copied recovery key. Safe to call repeatedly
  /// (e.g. every login) — each call simply refreshes the stored envelope
  /// with a fresh salt.
  Future<void> pushPasswordWrap(String password) async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    try {
      final wrapped = await AccountEncryptionService.instance
          .wrapKeyWithPassword(user.id, password);
      await _client
          .from('user_encryption')
          .update({
            'password_salt': wrapped.salt,
            'wrapped_key_ciphertext': wrapped.ciphertext,
            'wrapped_key_nonce': wrapped.nonce,
            'wrapped_key_mac': wrapped.mac,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('user_id', user.id);
    } catch (error) {
      debugPrint('[EncryptedFinanceSyncService] Password wrap deferred: $error');
    }
  }

  Future<List<Map<String, dynamic>>> _readRemoteRows(String userId) async {
    final rows = await _client
        .from('encrypted_finance_entries')
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
      final encryptedRows = <Map<String, dynamic>>[];
      final pushedRevisions = <String, int>{};
      for (final row in batch) {
        final payload = Map<String, dynamic>.from(
          jsonDecode(row['payload_json']! as String) as Map,
        );
        final encrypted = await AccountEncryptionService.instance.encrypt(
          user.id,
          payload,
        );
        final updatedAt = DateTime.fromMicrosecondsSinceEpoch(
          row['updated_at']! as int,
          isUtc: true,
        );
        encryptedRows.add({
          'user_id': user.id,
          'entry_id': row['id'],
          'ciphertext': encrypted.ciphertext,
          'nonce': encrypted.nonce,
          'mac': encrypted.mac,
          'encryption_version': encrypted.version,
          'revision': row['revision'],
          'is_deleted': row['deleted_at'] != null,
          'client_updated_at': updatedAt.toIso8601String(),
          'device_id': _uuid.v4(),
          'operation_id': _uuid.v4(),
        });
        pushedRevisions[row['id']! as String] = row['revision']! as int;
      }
      await _client
          .from('encrypted_finance_entries')
          .upsert(encryptedRows, onConflict: 'user_id,entry_id');
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
