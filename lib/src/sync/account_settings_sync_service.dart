import 'dart:async';

import 'package:budget_ai/src/helpers/network_reachability_service.dart';
import 'package:budget_ai/src/settings/bubble_style_settings_service.dart';
import 'package:budget_ai/src/settings/currency_settings_service.dart';
import 'package:budget_ai/src/settings/model_settings_service.dart';
import 'package:budget_ai/src/settings/user_name_settings_service.dart';
import 'package:budget_ai/src/storage/local_settings_store.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

class AccountSettingsSyncService {
  AccountSettingsSyncService._();

  static final AccountSettingsSyncService instance =
      AccountSettingsSyncService._();
  static const _deviceIdKey = 'budget_ai_sync_device_id';
  static const _retryDelays = <Duration>[
    Duration(seconds: 2),
    Duration(seconds: 5),
    Duration(seconds: 10),
    Duration(seconds: 30),
    Duration(minutes: 1),
  ];

  final _uuid = const Uuid();
  RealtimeChannel? _channel;
  Timer? _retryTimer;
  String? _attachedUserId;
  bool _initialized = false;
  bool _syncing = false;
  bool _syncRequested = false;
  int _retryAttempt = 0;

  SupabaseClient get _client => Supabase.instance.client;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    _client.auth.onAuthStateChange.listen(
      (state) => unawaited(_attachForUser(state.session?.user)),
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('[AccountSettingsSyncService] Auth offline: $error');
        _scheduleRetry();
      },
    );
    LocalSettingsStore.instance.accountPendingChanges.addListener(
      _scheduleSync,
    );
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
      _retryTimer?.cancel();
      return;
    }
    _channel = _client
        .channel('account-settings:${user.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'user_settings',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: user.id,
          ),
          callback: (_) => unawaited(syncNow()),
        )
        .subscribe((status, error) {
          if (status == RealtimeSubscribeStatus.subscribed) {
            unawaited(syncNow());
          } else if (status == RealtimeSubscribeStatus.channelError ||
              status == RealtimeSubscribeStatus.timedOut) {
            debugPrint('[AccountSettingsSyncService] Realtime waiting: $error');
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
    if (user == null) return true;
    try {
      final settings = LocalSettingsStore.instance;
      final localRows = await settings.accountRows();
      final pendingRows = localRows
          .where((row) => row['sync_state'] == 'pending')
          .toList(growable: false);
      final remote = await _client
          .from('user_settings')
          .select()
          .eq('user_id', user.id)
          .maybeSingle();

      if (pendingRows.isNotEmpty || remote == null) {
        final pushedThrough = pendingRows.isEmpty
            ? null
            : pendingRows
                  .map((row) => row['updated_at']! as int)
                  .reduce((left, right) => left > right ? left : right);
        await _push(user, localRows);
        if (pushedThrough != null) {
          await settings.markAccountCleanThrough(pushedThrough);
        }
      } else {
        final latestRows = await settings.accountRows();
        if (latestRows.any((row) => row['sync_state'] == 'pending')) {
          _syncRequested = true;
          return true;
        }
        await _pull(user, remote);
      }
      _resetRetry();
      return true;
    } catch (error) {
      debugPrint('[AccountSettingsSyncService] Sync deferred: $error');
      _scheduleRetry();
      return false;
    }
  }

  Future<void> _push(User user, List<Map<String, Object?>> localRows) async {
    var updatedAt = DateTime.now().toUtc();
    if (localRows.isNotEmpty) {
      final latest = localRows
          .map((row) => row['updated_at']! as int)
          .reduce((left, right) => left > right ? left : right);
      updatedAt = DateTime.fromMicrosecondsSinceEpoch(latest, isUtc: true);
    }
    await _client.from('user_settings').upsert({
      'user_id': user.id,
      'display_name': UserNameSettingsService.instance.current,
      'model_id': ModelSettingsService.instance.current,
      'currency_display': CurrencySettingsService.instance.current,
      'custom_currencies':
          CurrencySettingsService.instance.customCurrencies.value,
      'bubble_style': BubbleStyleSettingsService.instance.current.name,
      'client_updated_at': updatedAt.toIso8601String(),
      'device_id': await _deviceId(),
    });
  }

  Future<void> _pull(User user, Map<String, dynamic> remote) async {
    await UserNameSettingsService.instance.applySyncedName(
      remote['display_name'] as String? ?? '',
      user.id,
    );
    await ModelSettingsService.instance.applySyncedModel(
      remote['model_id'] as String? ?? ModelSettingsService.instance.current,
    );
    await CurrencySettingsService.instance.applySyncedState(
      remote['currency_display'] as String? ??
          CurrencySettingsService.instance.current,
      (remote['custom_currencies'] as List? ?? const [])
          .whereType<String>()
          .toList(growable: false),
    );
    final bubbleName = remote['bubble_style'] as String? ?? '';
    final bubble = UserBubbleStyle.values.firstWhere(
      (value) => value.name == bubbleName,
      orElse: () => UserBubbleStyle.classic,
    );
    await BubbleStyleSettingsService.instance.applySyncedStyle(bubble);
  }

  Future<String> _deviceId() async {
    final settings = LocalSettingsStore.instance;
    final existing = await settings.getString(_deviceIdKey);
    if (existing != null) return existing;
    final created = _uuid.v4();
    await settings.setString(_deviceIdKey, created);
    return created;
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
