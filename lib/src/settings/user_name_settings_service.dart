import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UserNameSettingsService {
  UserNameSettingsService._();

  static final UserNameSettingsService instance = UserNameSettingsService._();
  static const String _userNameKey = 'budget_user_name';

  final ValueNotifier<String> userName = ValueNotifier<String>('');
  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();

  Future<void> initialize() async {
    userName.value = (await _preferences.getString(_userNameKey))?.trim() ?? '';
  }

  Future<void> setUserName(String value) async {
    final normalized = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (normalized.isEmpty) {
      await _preferences.remove(_userNameKey);
      userName.value = '';
      return;
    }
    await _preferences.setString(_userNameKey, normalized);
    userName.value = normalized;
  }

  String get current => userName.value;
}
