import 'package:budget_ai/src/storage/local_settings_store.dart';
import 'package:flutter/foundation.dart';

/// The user's *soft* on/off choice for notification and background features,
/// kept separate from the OS-level permission.
///
/// The OS never lets an app revoke its own permission, so turning a feature
/// "off" here does not touch the granted permission — it simply tells the
/// rest of the app to stop *using* it (no notifications are shown, the
/// background service is not started) until the user turns it back on. When
/// off, the feature stays dormant even though the OS permission is still
/// granted.
class PermissionPreferencesService {
  PermissionPreferencesService._();

  static final PermissionPreferencesService instance =
      PermissionPreferencesService._();

  static const _notificationsKey = 'feature_notifications_enabled';
  static const _backgroundKey = 'feature_background_enabled';

  /// Whether the user wants Budget AI to show notifications. Defaults to off
  /// until they enable it (which also triggers the OS permission request).
  final ValueNotifier<bool> notificationsEnabled = ValueNotifier(false);

  /// Whether the user wants Budget AI to keep working in the background
  /// (Android only). Defaults to off until enabled.
  final ValueNotifier<bool> backgroundEnabled = ValueNotifier(false);

  Future<void> load() async {
    notificationsEnabled.value =
        await LocalSettingsStore.instance.getBool(_notificationsKey) ?? false;
    backgroundEnabled.value =
        await LocalSettingsStore.instance.getBool(_backgroundKey) ?? false;
  }

  void resetLocalState() {
    notificationsEnabled.value = false;
    backgroundEnabled.value = false;
  }

  Future<void> setNotificationsEnabled(bool value) async {
    notificationsEnabled.value = value;
    await LocalSettingsStore.instance.setBool(_notificationsKey, value);
  }

  Future<void> setBackgroundEnabled(bool value) async {
    backgroundEnabled.value = value;
    await LocalSettingsStore.instance.setBool(_backgroundKey, value);
  }

  /// Records permissions the user granted from the first-run onboarding flow.
  ///
  /// These preferences are intentionally device-local. Signing in, creating an
  /// account, or pulling account settings must not replace them.
  Future<void> recordOnboardingGrants({
    required bool notificationsGranted,
    required bool backgroundGranted,
  }) async {
    await Future.wait([
      if (notificationsGranted && !notificationsEnabled.value)
        setNotificationsEnabled(true),
      if (backgroundGranted && !backgroundEnabled.value)
        setBackgroundEnabled(true),
    ]);
  }
}
