import 'package:budget_ai/src/storage/local_settings_store.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class UserNameSettingsService {
  UserNameSettingsService._();

  static final UserNameSettingsService instance = UserNameSettingsService._();
  static const String _userNameKey = 'budget_user_name';
  static const String _userNameOwnerKey = 'budget_user_name_owner';

  final ValueNotifier<String> userName = ValueNotifier<String>('');
  final LocalSettingsStore _settings = LocalSettingsStore.instance;

  Future<void> initialize() async {
    userName.value = (await _settings.getString(_userNameKey))?.trim() ?? '';
    await syncFromUser(Supabase.instance.client.auth.currentUser);
  }

  Future<void> setUserName(String value) async {
    final normalized = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    final user = Supabase.instance.client.auth.currentUser;
    userName.value = normalized;
    await _settings.setString(
      _userNameKey,
      normalized,
      scope: SettingSyncScope.account,
    );
    if (user != null) {
      await _settings.setString(_userNameOwnerKey, user.id);
    } else {
      await _settings.remove(_userNameOwnerKey);
    }
  }

  Future<void> syncFromUser(User? user) async {
    if (user == null) return;
    if (await _settings.isPending(_userNameKey)) return;

    final remoteName =
        (user.userMetadata?['display_name'] as String?)?.trim().replaceAll(
          RegExp(r'\s+'),
          ' ',
        ) ??
        '';
    final localOwner = await _settings.getString(_userNameOwnerKey);

    if (remoteName.isNotEmpty) {
      await applySyncedName(remoteName, user.id);
      return;
    }

    if (userName.value.isNotEmpty &&
        (localOwner == null || localOwner == user.id)) {
      await _settings.setString(_userNameOwnerKey, user.id);
      return;
    }

    if (localOwner != null && localOwner != user.id) {
      userName.value = '';
      await _settings.setValue(
        _userNameKey,
        '',
        scope: SettingSyncScope.account,
        pendingSync: false,
      );
      await _settings.setString(_userNameOwnerKey, user.id);
    }
  }

  Future<void> applySyncedName(String value, String userId) async {
    final normalized = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    userName.value = normalized;
    await _settings.setValue(
      _userNameKey,
      normalized,
      scope: SettingSyncScope.account,
      pendingSync: false,
    );
    await _settings.setString(_userNameOwnerKey, userId);
  }

  String get current => userName.value;
}
