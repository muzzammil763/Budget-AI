import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum UserBubbleStyle {
  classic('Classic'),
  ledger('Ledger'),
  savings('Savings'),
  cashFlow('Cash flow'),
  growth('Growth'),
  receipt('Receipt'),
  nightBudget('Night budget'),
  vault('Vault'),
  paperCurl('Paper curl'),
  sketchFrame('Sketch frame');

  const UserBubbleStyle(this.label);

  final String label;
}

class BubbleStyleSettingsService {
  BubbleStyleSettingsService._();

  static final BubbleStyleSettingsService instance =
      BubbleStyleSettingsService._();
  static const String _styleKey = 'budget_user_bubble_style';

  final ValueNotifier<UserBubbleStyle> style = ValueNotifier<UserBubbleStyle>(
    UserBubbleStyle.classic,
  );
  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();

  Future<void> initialize() async {
    final saved = await _preferences.getString(_styleKey);
    final migrated = switch (saved) {
      'flexingCat' => UserBubbleStyle.paperCurl,
      'facepalm' => UserBubbleStyle.sketchFrame,
      _ => null,
    };
    style.value = UserBubbleStyle.values.firstWhere(
      (candidate) => candidate.name == saved,
      orElse: () => migrated ?? UserBubbleStyle.classic,
    );
  }

  Future<void> setStyle(UserBubbleStyle value) async {
    style.value = value;
    await _preferences.setString(_styleKey, value.name);
  }

  UserBubbleStyle get current => style.value;
}
