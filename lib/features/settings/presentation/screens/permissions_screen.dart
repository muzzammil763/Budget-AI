import 'dart:io';

import 'package:app_settings/app_settings.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:budget_ai/app/theme/app_theme.dart';
import 'package:budget_ai/core/platform/android_background_agent_service.dart';
import 'package:budget_ai/core/widgets/responsive_info_sheet.dart';
import 'package:permission_handler/permission_handler.dart';

class PermissionsScreen extends StatefulWidget {
  const PermissionsScreen({super.key});

  @override
  State<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends State<PermissionsScreen>
    with WidgetsBindingObserver {
  bool? _notificationGranted;
  bool? _locationGranted;
  bool? _locationServiceEnabled;
  bool? _installPackagesGranted;
  bool? _backgroundBatteryGranted;
  bool _isLoading = true;

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

    final locationStatus = await Permission.locationWhenInUse.status;
    final locationServiceEnabled =
        await geo.Geolocator.isLocationServiceEnabled();
    debugPrint(
      '[Permissions] Location status: ${locationStatus.isGranted}, service: $locationServiceEnabled',
    );

    bool? installPackagesGranted;
    if (Platform.isAndroid) {
      final installStatus = await Permission.requestInstallPackages.status;
      installPackagesGranted = installStatus.isGranted;
    }

    bool? backgroundBatteryGranted;
    if (Platform.isAndroid) {
      backgroundBatteryGranted =
          await AndroidBackgroundAgentService.isBatteryOptimizationIgnored();
      debugPrint(
        '[Permissions] Background battery unrestricted: $backgroundBatteryGranted',
      );
    }

    if (mounted) {
      setState(() {
        _notificationGranted = notificationStatus.isGranted;
        _locationGranted = locationStatus.isGranted;
        _locationServiceEnabled = locationServiceEnabled;
        _installPackagesGranted = installPackagesGranted;
        _backgroundBatteryGranted = backgroundBatteryGranted;
        _isLoading = false;
      });
    }
  }

  Future<void> _requestNotificationPermission() async {
    final status = await Permission.notification.request();
    if (mounted) {
      setState(() => _notificationGranted = status.isGranted);
      if (!status.isGranted) {
        _showPermissionDeniedDialog('Notifications');
      }
    }
  }

  Future<void> _requestLocationPermission() async {
    final serviceEnabled = await geo.Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      await geo.Geolocator.openLocationSettings();
      if (mounted) {
        setState(() => _locationServiceEnabled = false);
      }
      return;
    }

    final status = await Permission.locationWhenInUse.request();
    if (mounted) {
      setState(() {
        _locationGranted = status.isGranted;
        _locationServiceEnabled = serviceEnabled;
      });
      if (!status.isGranted) {
        _showPermissionDeniedDialog('Location');
      }
    }
  }

  Future<void> _requestInstallPackagesPermission() async {
    final status = await Permission.requestInstallPackages.request();
    if (mounted) {
      setState(() => _installPackagesGranted = status.isGranted);
      if (!status.isGranted) {
        _showPermissionDeniedDialog('Install from Unknown Sources');
      }
    }
  }

  Future<void> _requestBackgroundBatteryPermission() async {
    if (!(_notificationGranted ?? false)) {
      await _requestNotificationPermission();
    }
    await AndroidBackgroundAgentService.requestBatteryOptimizationExemption();
    final granted =
        await AndroidBackgroundAgentService.isBatteryOptimizationIgnored();
    if (mounted) {
      setState(() => _backgroundBatteryGranted = granted);
    }
  }

  Future<void> _openNotificationSettings() async {
    await AppSettings.openAppSettings(type: AppSettingsType.notification);
  }

  Future<void> _openLocationSettings() async {
    await geo.Geolocator.openLocationSettings();
    await AppSettings.openAppSettings();
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
                _buildPermissionCard(
                  icon: CupertinoIcons.bell,
                  title: 'Notifications',
                  isGranted: _notificationGranted ?? false,
                  onRequest: _requestNotificationPermission,
                  onOpenSettings: _openNotificationSettings,
                ),
                const SizedBox(height: 8),
                _buildPermissionCard(
                  icon: CupertinoIcons.location,
                  title: 'Location',
                  isGranted:
                      (_locationGranted ?? false) &&
                      (_locationServiceEnabled ?? true),
                  onRequest: _requestLocationPermission,
                  onOpenSettings: _openLocationSettings,
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
                  const SizedBox(height: 8),
                  _buildPermissionCard(
                    icon: CupertinoIcons.cloud_download,
                    title: 'Install from Unknown Sources',
                    isGranted: _installPackagesGranted ?? false,
                    onRequest: _requestInstallPackagesPermission,
                    onOpenSettings: () => AppSettings.openAppSettings(),
                  ),
                ],
              ],
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
        color: isGranted
            ? Colors.green.withValues(alpha: 0.05)
            : theme.colorScheme.surface,
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: isGranted
                        ? Colors.green.withValues(alpha: 0.1)
                        : theme.colorScheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    icon,
                    color: isGranted ? Colors.green : theme.colorScheme.primary,
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
                      borderRadius: BorderRadius.circular(10),
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
