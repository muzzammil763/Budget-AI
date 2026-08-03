import 'dart:async';

import 'package:budget_ai/src/helpers/app_constants.dart';
import 'package:budget_ai/src/settings/user_name_settings_service.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService extends ChangeNotifier {
  AuthService._();

  static final AuthService instance = AuthService._();

  StreamSubscription<AuthState>? _authSubscription;
  Session? _session;
  bool _initialized = false;
  bool _passwordRecovery = false;

  // Held only in memory, only long enough for the encryption layer to
  // derive/verify this device's data key against the account password
  // right after an auth event. Never persisted, never sent anywhere.
  String? _pendingPassword;

  SupabaseClient get _client => Supabase.instance.client;

  bool get initialized => _initialized;
  bool get isPasswordRecovery => _passwordRecovery;
  Session? get session => _session;
  User? get user => _session?.user;
  String? get accessToken => _session?.accessToken;
  bool get isAuthenticated =>
      _session != null && _session!.user.emailConfirmedAt != null;

  /// The most recently typed password, if any consumer has not yet claimed
  /// it. Does not clear it — call [clearPendingPassword] once done with it.
  String? get pendingPassword => _pendingPassword;

  void clearPendingPassword() {
    _pendingPassword = null;
  }

  Future<void> initialize() async {
    if (_initialized) return;
    _session = _client.auth.currentSession;
    _authSubscription = _client.auth.onAuthStateChange.listen(_handleAuthState);
    _initialized = true;
    notifyListeners();
  }

  void _handleAuthState(AuthState state) {
    _session = state.session ?? _client.auth.currentSession;
    switch (state.event) {
      case AuthChangeEvent.passwordRecovery:
        _passwordRecovery = true;
      case AuthChangeEvent.signedOut:
        _passwordRecovery = false;
        _session = null;
        _pendingPassword = null;
      case AuthChangeEvent.signedIn:
      case AuthChangeEvent.tokenRefreshed:
      case AuthChangeEvent.userUpdated:
      case AuthChangeEvent.initialSession:
      case AuthChangeEvent.mfaChallengeVerified:
        break;
      default:
        break;
    }
    if (_session?.user case final user?) {
      unawaited(UserNameSettingsService.instance.syncFromUser(user));
    }
    notifyListeners();
  }

  Future<AuthResponse> register({
    required String name,
    required String email,
    required String password,
  }) async {
    final normalizedName = name.trim().replaceAll(RegExp(r'\s+'), ' ');
    final response = await _client.auth.signUp(
      email: email.trim().toLowerCase(),
      password: password,
      emailRedirectTo: AppConstants.authConfirmRedirect,
      data: {'display_name': normalizedName},
    );
    await UserNameSettingsService.instance.setUserName(normalizedName);
    _pendingPassword = password;
    return response;
  }

  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    final response = await _client.auth.signInWithPassword(
      email: email.trim().toLowerCase(),
      password: password,
    );
    _pendingPassword = password;
    return response;
  }

  Future<AuthResponse> verifySignupCode({
    required String email,
    required String code,
  }) {
    return _client.auth.verifyOTP(
      email: email.trim().toLowerCase(),
      token: code.trim(),
      type: OtpType.signup,
    );
  }

  Future<void> resendSignupConfirmation(String email) async {
    await _client.auth.resend(
      type: OtpType.signup,
      email: email.trim().toLowerCase(),
      emailRedirectTo: AppConstants.authConfirmRedirect,
    );
  }

  Future<void> sendPasswordRecovery(String email) {
    return _client.auth.resetPasswordForEmail(
      email.trim().toLowerCase(),
      redirectTo: AppConstants.passwordRecoveryRedirect,
    );
  }

  Future<void> updatePassword(String password) async {
    await _client.auth.updateUser(UserAttributes(password: password));
    _passwordRecovery = false;
    _session = _client.auth.currentSession;
    _pendingPassword = password;
    notifyListeners();
  }

  Future<void> refreshSession() async {
    try {
      final response = await _client.auth.refreshSession();
      _session = response.session ?? _client.auth.currentSession;
      notifyListeners();
    } on AuthException {
      _session = _client.auth.currentSession;
      notifyListeners();
      rethrow;
    }
  }

  void cancelPasswordRecovery() {
    _passwordRecovery = false;
    notifyListeners();
  }

  Future<void> signOut() async {
    await _client.auth.signOut();
    _session = null;
    _passwordRecovery = false;
    _pendingPassword = null;
    notifyListeners();
  }

  Future<void> deleteAccount() async {
    try {
      final response = await _client.functions.invoke('delete-account');
      if (response.status < 200 || response.status >= 300) {
        throw AuthException('Account deletion could not be completed.');
      }
    } on FunctionException catch (error) {
      if (error.status == 404) {
        throw AuthException('Account deletion service is not deployed yet.');
      }
      throw AuthException('Account deletion could not be completed.');
    }
    // Deleting a Supabase user does not itself clear the JWT stored on this
    // device. A local sign-out removes it immediately; the server already
    // removed the user and all account-owned rows cascade with that deletion.
    await _client.auth.signOut(scope: SignOutScope.local);
    _session = null;
    _passwordRecovery = false;
    _pendingPassword = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }
}

String friendlyAuthError(Object error) {
  if (error is! AuthException) {
    return 'Something went wrong. Please try again.';
  }

  final message = error.message.toLowerCase();
  if (message.contains('email not confirmed')) {
    return 'Confirm your email before signing in.';
  }
  if (message.contains('invalid login credentials')) {
    return 'The email or password is incorrect.';
  }
  if (message.contains('user already registered')) {
    return 'Check your inbox to continue, or sign in if you already confirmed.';
  }
  if (message.contains('password') && message.contains('weak')) {
    return 'Use at least 8 characters with uppercase, lowercase, and a number.';
  }
  if (message.contains('rate limit') || message.contains('too many')) {
    return 'Too many attempts. Please wait a moment and try again.';
  }
  if (message.contains('expired') || message.contains('invalid token')) {
    return 'This link or code has expired. Request a new one.';
  }
  if (message.contains('network') || message.contains('socket')) {
    return 'Check your internet connection and try again.';
  }
  if (message.contains('account deletion service')) {
    return 'Account deletion is not available on the server yet.';
  }
  if (message.contains('account deletion')) {
    return 'Your account could not be deleted. Please try again.';
  }
  return 'Authentication could not be completed. Please try again.';
}
