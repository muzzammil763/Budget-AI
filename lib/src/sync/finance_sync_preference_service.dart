import 'package:budget_ai/src/storage/local_settings_store.dart';
import 'package:flutter/foundation.dart';

/// Whether the signed-in account syncs its finance entries to the cloud.
///
/// Off by default: entries stay on the device until the user turns Cloud Sync
/// on. The choice belongs to the account (`users.finance_sync_enabled`) so it
/// follows the user to other devices; accounts that existed before the opt-in
/// were migrated with sync on.
class FinanceSyncPreferenceService {
  FinanceSyncPreferenceService._();

  static final FinanceSyncPreferenceService instance =
      FinanceSyncPreferenceService._();

  static const storageKey = 'finance_cloud_sync_enabled';

  final ValueNotifier<bool> enabled = ValueNotifier(false);

  Future<void> load() async {
    enabled.value =
        await LocalSettingsStore.instance.getBool(storageKey) ?? false;
  }

  /// The account's choice as last known on this device, or null before this
  /// device has learned it. Account sync pushes the column only when known,
  /// so a fresh install can never overwrite the account's choice.
  Future<bool?> knownAccountValue() {
    return LocalSettingsStore.instance.getBool(storageKey);
  }

  /// A user-made change, queued for account sync.
  Future<void> setEnabled(bool value) async {
    enabled.value = value;
    await LocalSettingsStore.instance.setBool(
      storageKey,
      value,
      scope: SettingSyncScope.account,
    );
  }

  /// The account's choice pulled from the server.
  Future<void> applySyncedValue(bool value) async {
    if (await knownAccountValue() == value) {
      enabled.value = value;
      return;
    }
    await LocalSettingsStore.instance.setValue(
      storageKey,
      value,
      scope: SettingSyncScope.account,
    );
    enabled.value = value;
  }

  void resetLocalState() {
    enabled.value = false;
  }
}
