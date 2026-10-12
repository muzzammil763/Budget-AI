import 'dart:async';

import 'package:budget_ai/src/auth/auth_screens.dart';
import 'package:budget_ai/src/auth/auth_service.dart';
import 'package:budget_ai/src/auth/encryption_restore_screen.dart';
import 'package:budget_ai/src/auth/encryption_setup_screen.dart';
import 'package:budget_ai/src/sync/account_encryption_service.dart';
import 'package:budget_ai/src/sync/encrypted_finance_sync_service.dart';
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

    // Local secure-storage read only — no network wait. A device that
    // already holds its data key can go straight to the app; there is
    // nothing the server can tell us that should block that.
    final hasLocalKey = await AccountEncryptionService.instance.hasKey(user.id);
    final pendingPassword = AuthService.instance.pendingPassword;

    if (hasLocalKey) {
      if (!mounted ||
          user.id != Supabase.instance.client.auth.currentUser?.id) {
        return;
      }
      setState(() => _state = _EncryptionState.ready);
      // Only a fresh login/password-change leaves a pending password —
      // refresh the server-side envelope for it in the background so
      // other devices can keep unlocking automatically.
      if (pendingPassword != null) {
        unawaited(
          EncryptedFinanceSyncService.instance.pushPasswordWrap(
            pendingPassword,
          ),
        );
        AuthService.instance.clearPendingPassword();
      }
      return;
    }

    // No local key: a new device, a reinstall, or first-ever setup. This
    // genuinely needs to ask the server what state the account is in
    // before deciding what to show, so briefly blocking here is expected.
    if (mounted) setState(() => _state = _EncryptionState.checking);
    try {
      final metadata = await Supabase.instance.client
          .from('user_encryption')
          .select(
            'key_fingerprint,password_salt,wrapped_key_ciphertext,'
            'wrapped_key_nonce,wrapped_key_mac',
          )
          .eq('user_id', user.id)
          .maybeSingle();

      var unlocked = false;
      // Try unlocking with whatever password was just typed to sign in,
      // before falling back to the "couldn't unlock automatically" screen.
      if (metadata != null && pendingPassword != null) {
        final salt = metadata['password_salt'] as String?;
        final ciphertext = metadata['wrapped_key_ciphertext'] as String?;
        final nonce = metadata['wrapped_key_nonce'] as String?;
        final mac = metadata['wrapped_key_mac'] as String?;
        if (salt != null &&
            ciphertext != null &&
            nonce != null &&
            mac != null) {
          try {
            await AccountEncryptionService.instance.unwrapKeyWithPassword(
              user.id,
              pendingPassword,
              WrappedKeyPayload(
                salt: salt,
                ciphertext: ciphertext,
                nonce: nonce,
                mac: mac,
              ),
              metadata['key_fingerprint']! as String,
            );
            unlocked = true;
          } catch (_) {
            // Wrong password, or a stale envelope — fall through to the
            // manual recovery-key screen below.
          }
        }
      }

      final stillCurrentUser =
          user.id == Supabase.instance.client.auth.currentUser?.id;
      if (!mounted || !stillCurrentUser) return;

      if (unlocked && pendingPassword != null) {
        unawaited(
          EncryptedFinanceSyncService.instance.pushPasswordWrap(
            pendingPassword,
          ),
        );
        AuthService.instance.clearPendingPassword();
      }

      setState(() {
        _state = unlocked
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
      _EncryptionState.needsRestore => EncryptionRestoreScreen(onDone: _check),
      _EncryptionState.ready => widget.child,
    };
  }
}
