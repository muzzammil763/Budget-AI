import 'dart:async';

import 'package:budget_ai/src/auth/auth_screens.dart';
import 'package:budget_ai/src/auth/auth_service.dart';
import 'package:budget_ai/src/auth/legacy_data_unlock_screen.dart';
import 'package:budget_ai/src/sync/finance_sync_service.dart';
import 'package:budget_ai/src/sync/legacy_encryption_migration_service.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum _LegacyDataState { checking, needsPassword, ready }

/// Converts finance data saved by the retired end-to-end encryption before
/// [child] is shown. Devices that still hold the old key, and accounts that
/// were already converted, pass straight through while the sync service
/// finishes the conversion in the background. Only a device without the
/// key waits for the server and, if needed, asks for the account password.
class LegacyDataGate extends StatefulWidget {
  const LegacyDataGate({super.key, required this.child});

  final Widget child;

  @override
  State<LegacyDataGate> createState() => _LegacyDataGateState();
}

class _LegacyDataGateState extends State<LegacyDataGate> {
  _LegacyDataState _state = _LegacyDataState.checking;
  String? _checkedUserId;
  Timer? _retryTimer;

  @override
  void initState() {
    super.initState();
    _check();
  }

  @override
  void didUpdateWidget(covariant LegacyDataGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId != _checkedUserId) _check();
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    super.dispose();
  }

  Future<void> _check() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    _retryTimer?.cancel();
    _checkedUserId = user.id;
    final migration = LegacyEncryptionMigrationService.instance;
    final password = AuthService.instance.pendingPassword;

    if (await migration.canMigrateSilently(user.id)) {
      AuthService.instance.clearPendingPassword();
      if (_isCurrent(user.id)) {
        setState(() => _state = _LegacyDataState.ready);
      }
      return;
    }

    if (mounted) setState(() => _state = _LegacyDataState.checking);
    try {
      final status = await migration.migrate(user.id, password: password);
      AuthService.instance.clearPendingPassword();
      if (!_isCurrent(user.id)) return;
      if (status == LegacyMigrationStatus.complete) {
        unawaited(FinanceSyncService.instance.syncNow());
      }
      setState(() {
        _state = status == LegacyMigrationStatus.complete
            ? _LegacyDataState.ready
            : _LegacyDataState.needsPassword;
      });
    } catch (_) {
      // Offline or a transient failure: retry instead of skipping the
      // conversion, which would leave this account's old entries behind.
      _retryTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) _check();
      });
    }
  }

  bool _isCurrent(String userId) {
    return mounted && userId == Supabase.instance.client.auth.currentUser?.id;
  }

  void _unlocked() {
    unawaited(FinanceSyncService.instance.syncNow());
    setState(() => _state = _LegacyDataState.ready);
  }

  @override
  Widget build(BuildContext context) {
    return switch (_state) {
      _LegacyDataState.checking => const AuthLoadingScreen(),
      _LegacyDataState.needsPassword => LegacyDataUnlockScreen(
        onDone: _unlocked,
      ),
      _LegacyDataState.ready => widget.child,
    };
  }
}
