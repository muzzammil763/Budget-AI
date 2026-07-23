import 'dart:async';

import 'package:budget_ai/src/auth/auth_screens.dart';
import 'package:budget_ai/src/auth/encryption_restore_screen.dart';
import 'package:budget_ai/src/auth/encryption_setup_screen.dart';
import 'package:budget_ai/src/sync/account_encryption_service.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum _EncryptionState { checking, needsSetup, needsRestore, ready }

/// Gates access to [child] behind mandatory end-to-end encryption. Every
/// authenticated session must either generate a key (first device on this
/// account) or restore one (any later device) before it can reach the app.
class EncryptionGate extends StatefulWidget {
  const EncryptionGate({super.key, required this.child});

  final Widget child;

  @override
  State<EncryptionGate> createState() => _EncryptionGateState();
}

class _EncryptionGateState extends State<EncryptionGate> {
  _EncryptionState _state = _EncryptionState.checking;
  String? _remoteFingerprint;
  String? _checkedUserId;
  Timer? _retryTimer;

  @override
  void initState() {
    super.initState();
    _check();
  }

  @override
  void didUpdateWidget(covariant EncryptionGate oldWidget) {
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
    if (mounted) setState(() => _state = _EncryptionState.checking);
    try {
      final metadata = await Supabase.instance.client
          .from('user_encryption')
          .select('key_fingerprint')
          .eq('user_id', user.id)
          .maybeSingle();
      final hasLocalKey = await AccountEncryptionService.instance.hasKey(
        user.id,
      );
      final stillCurrentUser =
          user.id == Supabase.instance.client.auth.currentUser?.id;
      if (!mounted || !stillCurrentUser) return;
      setState(() {
        _remoteFingerprint = metadata?['key_fingerprint'] as String?;
        _state = hasLocalKey
            ? _EncryptionState.ready
            : metadata == null
            ? _EncryptionState.needsSetup
            : _EncryptionState.needsRestore;
      });
    } catch (_) {
      // Offline or a transient failure while checking status — retry
      // shortly instead of locking the user out or letting them through
      // without encryption confirmed.
      _retryTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) _check();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return switch (_state) {
      _EncryptionState.checking => const AuthLoadingScreen(),
      _EncryptionState.needsSetup => EncryptionSetupScreen(onDone: _check),
      _EncryptionState.needsRestore => EncryptionRestoreScreen(
        remoteFingerprint: _remoteFingerprint,
        onDone: _check,
      ),
      _EncryptionState.ready => widget.child,
    };
  }
}
