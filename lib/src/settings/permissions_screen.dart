import 'dart:io';

import 'package:app_settings/app_settings.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:budget_ai/src/helpers/app_theme.dart';
import 'package:budget_ai/src/helpers/android_background_chat_service.dart';
import 'package:budget_ai/src/helpers/notification_service.dart';
import 'package:budget_ai/src/helpers/responsive_info_sheet.dart';
import 'package:permission_handler/permission_handler.dart';

class PermissionsScreen extends StatefulWidget {
  const PermissionsScreen({super.key});

  @override
  State<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends State<PermissionsScreen>
    with WidgetsBindingObserver {
  bool? _notificationGranted;
  bool? _backgroundBatteryGranted;
  bool _isLoading = true;
  bool _isRequestingRequired = false;

  bool get _requiredChatPermissionsGranted {
    if (!(_notificationGranted ?? false)) return false;
    if (Platform.isAndroid && !(_backgroundBatteryGranted ?? false)) {
      return false;
    }
    return true;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkPermissions();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Recheck permissions when app comes back from settings
      _checkPermissions();
    }
  }

  Future<void> _checkPermissions() async {
    setState(() => _isLoading = true);

    // Notification permission - use permission_handler for accurate check
    final notificationStatus = await Permission.notification.status;
    debugPrint(
      '[Permissions] Notification status: ${notificationStatus.isGranted}',
    );

    bool? backgroundBatteryGranted;
    if (Platform.isAndroid) {
      backgroundBatteryGranted =
          await AndroidBackgroundChatService.isBatteryOptimizationIgnored();
      debugPrint(
        '[Permissions] Background battery unrestricted: $backgroundBatteryGranted',
      );
    }

    if (mounted) {
      setState(() {
        _notificationGranted = notificationStatus.isGranted;
        _backgroundBatteryGranted = backgroundBatteryGranted;
        _isLoading = false;
      });
    }
  }

  Future<void> _requestNotificationPermission() async {
    final granted = Platform.isIOS
        ? await NotificationService.instance.requestPermission()
        : (await Permission.notification.request()).isGranted;
    final status = await Permission.notification.status;
    final isGranted = granted || status.isGranted;
    if (mounted) {
      setState(() => _notificationGranted = isGranted);
      if (!isGranted) {
        _showPermissionDeniedDialog('Notifications');
      }
    }
  }

  Future<void> _requestBackgroundBatteryPermission() async {
    if (!(_notificationGranted ?? false)) {
      await _requestNotificationPermission();
    }
    await AndroidBackgroundChatService.requestBatteryOptimizationExemption();
    final granted =
        await AndroidBackgroundChatService.isBatteryOptimizationIgnored();
    if (mounted) {
      setState(() => _backgroundBatteryGranted = granted);
    }
  }

  Future<void> _requestRequiredChatPermissions() async {
    if (_isRequestingRequired) return;
    setState(() => _isRequestingRequired = true);

    try {
      if (!(_notificationGranted ?? false)) {
        await _requestNotificationPermission();
      }

      if (Platform.isAndroid) {
        await AndroidBackgroundChatService.requestBatteryOptimizationExemption();
      }

      await _checkPermissions();
    } finally {
      if (mounted) {
        setState(() => _isRequestingRequired = false);
      }
    }
  }

  Future<void> _openNotificationSettings() async {
    await AppSettings.openAppSettings(type: AppSettingsType.notification);
  }

  Future<void> _showPermissionDeniedDialog(String permissionName) async {
    final confirmed = await ResponsiveInfoSheet.confirm(
      context,
      title: '$permissionName Permission Required',
      message:
          'You have denied $permissionName permission. Please open settings to enable it.',
      icon: CupertinoIcons.exclamationmark_triangle_fill,
      confirmLabel: 'Open Settings',
    );
    if (confirmed == true) {
      await AppSettings.openAppSettings();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: Navigator.of(context).pop,
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
        ),
        title: const Text('Permissions'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(8),
              children: [
                _buildRequiredPermissionsCard(),
                const SizedBox(height: 8),
                _buildPermissionCard(
                  icon: CupertinoIcons.bell,
                  title: 'Notifications',
                  isGranted: _notificationGranted ?? false,
                  onRequest: _requestNotificationPermission,
                  onOpenSettings: _openNotificationSettings,
                ),
                if (Platform.isAndroid) ...[
                  const SizedBox(height: 8),
                  _buildPermissionCard(
                    icon: CupertinoIcons.bolt_horizontal_circle,
                    title: 'Background Service',
                    isGranted:
                        (_notificationGranted ?? false) &&
                        (_backgroundBatteryGranted ?? false),
                    onRequest: _requestBackgroundBatteryPermission,
                    onOpenSettings: () => AppSettings.openAppSettings(),
                  ),
                ],
              ],
            ),
    );
  }

  Widget _buildRequiredPermissionsCard() {
    final theme = Theme.of(context);
    final granted = _requiredChatPermissionsGranted;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: granted
              ? Colors.green.withValues(alpha: 0.5)
              : theme.colorScheme.primary.withValues(alpha: 0.5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: granted ? Colors.green : theme.colorScheme.primary,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                granted
                    ? CupertinoIcons.check_mark_circled
                    : CupertinoIcons.bolt_horizontal_circle,
                color: granted ? Colors.white : theme.colorScheme.onPrimary,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                granted ? 'Chat Permissions Ready' : 'Chat Permissions',
                style: AppTheme.headingSmall.copyWith(
                  fontSize: 16,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
            if (!granted)
              SizedBox(
                height: 40,
                child: ElevatedButton(
                  onPressed: _isRequestingRequired
                      ? null
                      : _requestRequiredChatPermissions,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.colorScheme.primary,
                    foregroundColor: theme.colorScheme.onPrimary,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isRequestingRequired
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: theme.colorScheme.onPrimary,
                          ),
                        )
                      : const Text('Allow'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPermissionCard({
    required IconData icon,
    required String title,
    required bool isGranted,
    required VoidCallback onRequest,
    required VoidCallback onOpenSettings,
    bool isSettingsOnly = false,
  }) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isGranted
              ? Colors.green.withValues(alpha: 0.5)
              : theme.colorScheme.outline,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: isGranted ? Colors.green : theme.colorScheme.primary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    icon,
                    color: isGranted
                        ? Colors.white
                        : theme.colorScheme.onPrimary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: AppTheme.headingSmall.copyWith(
                          fontSize: 16,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isGranted)
                  Icon(
                    CupertinoIcons.check_mark_circled,
                    color: Colors.green,
                    size: 24,
                  )
                else
                  Icon(
                    CupertinoIcons.xmark_circle,
                    color: theme.colorScheme.error,
                    size: 24,
                  ),
              ],
            ),
            if (!isGranted) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: ElevatedButton.icon(
                  onPressed: isSettingsOnly ? onOpenSettings : onRequest,
                  icon: Icon(
                    isSettingsOnly
                        ? CupertinoIcons.settings
                        : CupertinoIcons.lock_open,
                    size: 18,
                  ),
                  label: Text(isSettingsOnly ? 'Open Settings' : 'Allow'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.colorScheme.primary,
                    foregroundColor: theme.colorScheme.onPrimary,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
