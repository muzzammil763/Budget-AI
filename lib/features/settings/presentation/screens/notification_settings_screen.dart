import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:budget_ai/app/theme/app_theme.dart';
import 'package:budget_ai/core/models/notification_payload.dart';
import 'package:budget_ai/core/services/notification_service.dart';
import 'package:budget_ai/core/widgets/toast_helper.dart';
import 'package:toastification/toastification.dart';

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  late bool _approvalNotifications;
  late bool _responseNotifications;
  late bool _approvalSound;
  late bool _approvalVibration;
  late bool _backgroundOnly;
  late bool _dndDestructiveBypass;

  @override
  void initState() {
    super.initState();
    final svc = NotificationService.instance;
    _approvalNotifications = svc.approvalNotificationsEnabled;
    _responseNotifications = svc.responseNotificationsEnabled;
    _approvalSound = svc.approvalSoundEnabled;
    _approvalVibration = svc.approvalVibrationEnabled;
    _backgroundOnly = svc.backgroundOnlyEnabled;
    _dndDestructiveBypass = svc.dndDestructiveBypass;
  }

  Future<void> _setApprovalNotifications(bool value) async {
    await NotificationService.instance.setApprovalNotificationsEnabled(value);
    setState(() => _approvalNotifications = value);
  }

  Future<void> _setResponseNotifications(bool value) async {
    await NotificationService.instance.setResponseNotificationsEnabled(value);
    setState(() => _responseNotifications = value);
  }

  Future<void> _setApprovalSound(bool value) async {
    await NotificationService.instance.setApprovalSoundEnabled(value);
    setState(() => _approvalSound = value);
  }

  Future<void> _setApprovalVibration(bool value) async {
    await NotificationService.instance.setApprovalVibrationEnabled(value);
    setState(() => _approvalVibration = value);
  }

  Future<void> _setBackgroundOnly(bool value) async {
    await NotificationService.instance.setBackgroundOnlyEnabled(value);
    setState(() => _backgroundOnly = value);
  }

  Future<void> _setDndDestructiveBypass(bool value) async {
    await NotificationService.instance.setDndDestructiveBypass(value);
    setState(() => _dndDestructiveBypass = value);
  }

  void _sendTestNotification() {
    final payload = ApprovalNotificationPayload(
      requestId: 'test_${DateTime.now().millisecondsSinceEpoch}',
      toolName: 'bash',
      command: 'rm -rf /Users/test/test-project',
      arguments: const {'command': 'rm -rf /Users/test/test-project'},
      riskLevel: 'destructive',
      affectedPaths: const ['/Users/test/test-project'],
      sessionId: 'test',
      timestamp: DateTime.now(),
      chatId: 'test',
    );
    NotificationService.instance.showApprovalNotification(
      payload,
      appInBackground: true,
    );
    showAppToast(
      context,
      message: 'Test approval notification sent!',
      type: ToastificationType.success,
    );
  }

  void _sendTestResponseNotification() {
    final payload = ResponseReadyPayload(
      chatId: 'test_${DateTime.now().millisecondsSinceEpoch}',
      modelUsed: 'DeepSeek-V3',
      toolCallCount: 3,
      status: 'success',
      summary: 'Modified 2 files, committed changes, and pushed to origin.',
      timestamp: DateTime.now(),
      hasError: false,
    );
    NotificationService.instance.showResponseReadyNotification(
      payload,
      appInBackground: true,
    );
    showAppToast(
      context,
      message: 'Test response notification sent!',
      type: ToastificationType.success,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: Navigator.of(context).pop,
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
        ),
        title: const Text('Notifications'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(8),
        children: [
          _buildSectionHeader(context, 'Approval Notifications'),
          _buildSwitchCard(
            context,
            icon: CupertinoIcons.bell,
            title: 'Approval Notifications',
            subtitle: 'Notify when a command needs approval',
            value: _approvalNotifications,
            onChanged: _setApprovalNotifications,
          ),
          _buildSwitchCard(
            context,
            icon: CupertinoIcons.speaker,
            title: 'Sound',
            subtitle: 'Play sound for approval notifications',
            value: _approvalSound,
            onChanged: _setApprovalSound,
            enabled: _approvalNotifications,
          ),
          _buildSwitchCard(
            context,
            icon: CupertinoIcons.waveform,
            title: 'Vibration',
            subtitle: 'Vibrate for approval notifications',
            value: _approvalVibration,
            onChanged: _setApprovalVibration,
            enabled: _approvalNotifications,
          ),
          const SizedBox(height: 12),
          _buildSectionHeader(context, 'Response Notifications'),
          _buildSwitchCard(
            context,
            icon: CupertinoIcons.check_mark_circled,
            title: 'Response Ready',
            subtitle: 'Notify when AI response is complete',
            value: _responseNotifications,
            onChanged: _setResponseNotifications,
          ),
          const SizedBox(height: 12),
          _buildSectionHeader(context, 'Behavior'),
          _buildSwitchCard(
            context,
            icon: CupertinoIcons.app,
            title: 'Background Only',
            subtitle: 'Only notify when app is not in foreground',
            value: _backgroundOnly,
            onChanged: _setBackgroundOnly,
          ),
          const SizedBox(height: 12),
          _buildSectionHeader(context, 'Do Not Disturb'),
          _buildSwitchCard(
            context,
            icon: CupertinoIcons.moon,
            title: 'Bypass DND for Destructive',
            subtitle: 'Critical commands always notify during quiet hours',
            value: _dndDestructiveBypass,
            onChanged: _setDndDestructiveBypass,
          ),
          const SizedBox(height: 12),
          _buildSectionHeader(context, 'Testing'),
          _buildActionCard(
            context,
            icon: CupertinoIcons.bell_fill,
            title: 'Send Test Approval',
            subtitle: 'Simulate a destructive command approval request',
            onTap: _sendTestNotification,
            color: theme.colorScheme.primary,
          ),
          _buildActionCard(
            context,
            icon: CupertinoIcons.check_mark_circled,
            title: 'Send Test Response',
            subtitle: 'Simulate a response completion notification',
            onTap: _sendTestResponseNotification,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: Text(
        title.toUpperCase(),
        style: AppTheme.bodySmall.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Widget _buildSwitchCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    bool enabled = true,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: enabled ? () => onChanged(!value) : null,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: theme.colorScheme.outline),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                color: enabled
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTheme.headingSmall.copyWith(
                        color: enabled
                            ? theme.colorScheme.onSurface
                            : theme.colorScheme.onSurfaceVariant,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: AppTheme.bodySmall.copyWith(
                        color: enabled
                            ? theme.colorScheme.onSurfaceVariant
                            : theme.colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              CupertinoSwitch(
                value: value,
                onChanged: enabled ? onChanged : null,
                activeTrackColor: Colors.green,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    required Color color,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: theme.colorScheme.outline),
          ),
          child: Row(
            children: [
              Icon(icon, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTheme.headingSmall.copyWith(
                        color: theme.colorScheme.onSurface,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: AppTheme.bodySmall.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                CupertinoIcons.chevron_right,
                color: theme.colorScheme.onSurfaceVariant,
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
