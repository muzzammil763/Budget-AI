import 'package:budget_ai/src/storage/local_settings_store.dart';
import 'package:flutter/foundation.dart';

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

  bool get usesHandwrittenFont =>
      this == UserBubbleStyle.paperCurl || this == UserBubbleStyle.sketchFrame;
}

class BubbleStyleSettingsService {
  BubbleStyleSettingsService._();

  static final BubbleStyleSettingsService instance =
      BubbleStyleSettingsService._();
  static const String _styleKey = 'budget_user_bubble_style';

  final ValueNotifier<UserBubbleStyle> style = ValueNotifier<UserBubbleStyle>(
    UserBubbleStyle.classic,
  );
  final LocalSettingsStore _settings = LocalSettingsStore.instance;

  Future<void> initialize() async {
    final saved = await _settings.getString(_styleKey);
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
    await _settings.setString(
      _styleKey,
      value.name,
      scope: SettingSyncScope.account,
    );
  }

  Future<void> applySyncedStyle(UserBubbleStyle value) async {
    style.value = value;
    await _settings.setValue(
      _styleKey,
      value.name,
      scope: SettingSyncScope.account,
      pendingSync: false,
    );
  }

  UserBubbleStyle get current => style.value;
}
