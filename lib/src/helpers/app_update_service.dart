import 'dart:async';
import 'dart:io';

import 'package:budget_ai/src/helpers/app_button.dart';
import 'package:budget_ai/src/helpers/app_theme.dart';
import 'package:budget_ai/src/helpers/responsive_info_sheet.dart';
import 'package:budget_ai/src/storage/local_settings_store.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:in_app_update_flutter/in_app_update_flutter.dart';

/// Google Play in-app updates for store releases (native changes). Small
/// Dart-only fixes arrive through Shorebird patches instead and need no
/// prompt.
///
/// A release with Play update priority 4–5 is installed immediately (full
/// screen); anything else downloads in the background and then offers a
/// restart. A declined version is not offered again for two days.
class AppUpdateService {
  AppUpdateService._();

  static final AppUpdateService instance = AppUpdateService._();

  static const _declinedKey = 'app_update_declined';
  static const _declineWindow = Duration(days: 2);
  static const _immediatePriority = 4;

  final InAppUpdateFlutter _plugin = InAppUpdateFlutter();
  StreamSubscription<InstallStateAndroid>? _installSubscription;
  bool _checking = false;
  bool _sheetOpen = false;

  bool get _supported => !kIsWeb && Platform.isAndroid && kReleaseMode;

  /// Checks Google Play once per call; safe to call on launch and resume.
  Future<void> check(BuildContext context) async {
    if (!_supported || _checking) return;
    _checking = true;
    try {
      final info = await _plugin.checkUpdateAndroid();
      if (!context.mounted) return;

      if (info.installStatus == InstallStatusAndroid.downloaded) {
        await _offerRestart(context);
        return;
      }
      if (info.updateAvailability !=
          UpdateAvailabilityAndroid.updateAvailable) {
        return;
      }

      if (info.updatePriority >= _immediatePriority &&
          info.isImmediateUpdateAllowed) {
        await _plugin.startImmediateUpdateAndroid();
        return;
      }

      final version = info.availableVersionCode;
      if (!info.isFlexibleUpdateAllowed || await _recentlyDeclined(version)) {
        return;
      }
      if (!context.mounted) return;
      _listenForDownload(context);
      final result = await _plugin.startFlexibleUpdateAndroid();
      if (result == UpdateResultAndroid.userCanceled) {
        await _rememberDecline(version);
      }
    } catch (error) {
      // Not installed from Play, offline, or Play is unavailable.
      debugPrint('[AppUpdate] Check skipped: $error');
    } finally {
      _checking = false;
    }
  }

  void _listenForDownload(BuildContext context) {
    _installSubscription ??= _plugin.installStateStreamAndroid.listen((state) {
      if (state.status == InstallStatusAndroid.downloaded && context.mounted) {
        unawaited(_offerRestart(context));
      }
    });
  }

  Future<void> _offerRestart(BuildContext context) async {
    if (_sheetOpen) return;
    _sheetOpen = true;
    try {
      final restart = await _showReadySheet(context) ?? false;
      if (restart) await _plugin.completeUpdateAndroid();
    } catch (error) {
      debugPrint('[AppUpdate] Install failed: $error');
    } finally {
      _sheetOpen = false;
    }
  }

  Future<bool> _recentlyDeclined(int? version) async {
    final saved = await LocalSettingsStore.instance.getString(_declinedKey);
    final parts = saved?.split('@');
    if (parts == null || parts.length != 2) return false;
    final declinedAt = DateTime.tryParse(parts[1]);
    return parts[0] == '$version' &&
        declinedAt != null &&
        DateTime.now().difference(declinedAt) < _declineWindow;
  }

  Future<void> _rememberDecline(int? version) => LocalSettingsStore.instance
      .setString(_declinedKey, '$version@${DateTime.now().toIso8601String()}');

  static Future<bool?> _showReadySheet(BuildContext context) {
    final theme = Theme.of(context);
    final onPrimary = AppTheme.readableOn(theme.colorScheme.primary);
    return ResponsiveInfoSheet.show<bool>(
      context,
      title: 'Update ready',
      headerIcon: Icon(
        CupertinoIcons.arrow_down_circle,
        size: 30,
        color: onPrimary,
      ),
      gradientColors: [
        theme.colorScheme.primary,
        theme.colorScheme.primary.withValues(alpha: 0.78),
      ],
      contentWidgets: [const _ReadyContent()],
    );
  }
}

class _ReadyContent extends StatelessWidget {
  const _ReadyContent();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'A new version of Budget AI has downloaded. Restart to finish '
            'updating; your entries and chats stay as they are.',
            textAlign: TextAlign.center,
            style: AppTheme.bodyMedium.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 18),
          AppButton(
            key: const ValueKey('app-update-restart'),
            text: 'Restart to update',
            icon: CupertinoIcons.arrow_clockwise,
            onPressed: () => Navigator.of(context).pop(true),
          ),
          const SizedBox(height: 4),
          TextButton(
            key: const ValueKey('app-update-later'),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Later'),
          ),
        ],
      ),
    );
  }
}
