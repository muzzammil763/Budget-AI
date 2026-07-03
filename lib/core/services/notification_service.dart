import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart'
    hide PendingNotificationRequest;
import 'package:budget_ai/core/models/notification_payload.dart';
import 'package:budget_ai/core/storage/shared_prefs_service.dart';
import 'package:budget_ai/features/mac_companion/data/mac_companion_service.dart';

export 'package:flutter_local_notifications/flutter_local_notifications.dart'
    show PendingNotificationRequest;

/// Risk level for approval notifications.
enum RiskLevel { safe, caution, destructive, irreversible, unknown }

extension RiskLevelExtension on RiskLevel {
  String get displayName {
    switch (this) {
      case RiskLevel.safe:
        return '✅ Safe';
      case RiskLevel.caution:
        return '⚠️ Caution';
      case RiskLevel.destructive:
        return '🔥 Destructive';
      case RiskLevel.irreversible:
        return '☠️ Irreversible';
      case RiskLevel.unknown:
        return '❓ Unknown';
    }
  }

  String get shortName {
    switch (this) {
      case RiskLevel.safe:
        return 'Safe';
      case RiskLevel.caution:
        return 'Caution';
      case RiskLevel.destructive:
        return 'Destructive';
      case RiskLevel.irreversible:
        return 'Irreversible';
      case RiskLevel.unknown:
        return 'Unknown';
    }
  }

  String get emoji {
    switch (this) {
      case RiskLevel.safe:
        return '✅';
      case RiskLevel.caution:
        return '⚠️';
      case RiskLevel.destructive:
        return '🔥';
      case RiskLevel.irreversible:
        return '☠️';
      case RiskLevel.unknown:
        return '❓';
    }
  }

  String get colorHex {
    switch (this) {
      case RiskLevel.safe:
        return '#4CAF50';
      case RiskLevel.caution:
        return '#FF9800';
      case RiskLevel.destructive:
        return '#F44336';
      case RiskLevel.irreversible:
        return '#9C27B0';
      case RiskLevel.unknown:
        return '#757575';
    }
  }
}

RiskLevel riskLevelFromString(String value) {
  switch (value.toLowerCase()) {
    case 'safe':
      return RiskLevel.safe;
    case 'caution':
    case 'warning':
      return RiskLevel.caution;
    case 'destructive':
    case 'dangerous':
    case 'danger':
      return RiskLevel.destructive;
    case 'irreversible':
    case 'critical':
      return RiskLevel.irreversible;
    default:
      return RiskLevel.unknown;
  }
}

/// Payload type for notification routing.
enum NotificationPayloadType { approval, responseReady, general }

/// Notification action identifiers.
class NotificationActions {
  static const String approve = 'approve';
  static const String deny = 'deny';
  static const String openApp = 'open_app';
  static const String dismiss = 'dismiss';
}

/// Notification channel identifiers.
class NotificationChannels {
  static const String approvalRequests = 'approval_requests';
  static const String responseReady = 'response_ready';
  static const String generalAlerts = 'general_alerts';
}

/// Centralized notification service for OpenGate.
///
/// Handles approval notifications, response ready notifications,
/// and general alerts with rich, actionable content.
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  static NotificationService get instance => _instance;

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  final _approvalQueueController =
      StreamController<List<ApprovalNotificationPayload>>.broadcast();
  Stream<List<ApprovalNotificationPayload>> get approvalQueueStream =>
      _approvalQueueController.stream;

  final _pendingApprovals = <String, ApprovalNotificationPayload>{};

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  /// Callback fired when a notification action is tapped.
  Function(String actionId, String? payload)? onNotificationAction;

  /// Callback fired when a notification is tapped (not an action).
  Function(String? payload)? onNotificationTapped;

  // ── Pending action queue for background/foreground routing ──
  final List<Map<String, String>> _pendingActionQueue = [];
  final _pendingActionController = StreamController<void>.broadcast();

  /// Enqueue a notification action for later processing.
  void enqueueAction(String actionId, String payload) {
    _pendingActionQueue.add({'actionId': actionId, 'payload': payload});
    _pendingActionController.add(null);
  }

  /// Remove and return all pending actions.
  List<Map<String, String>> flushPendingActions() {
    final actions = List<Map<String, String>>.from(_pendingActionQueue);
    _pendingActionQueue.clear();
    return actions;
  }

  /// Stream that fires when a new action is enqueued.
  Stream<void> get onPendingActions => _pendingActionController.stream;

  /// Handle a notification action for remote command approvals directly.
  /// Returns true if handled remotely, false if it should be processed by UI.
  Future<bool> handleRemoteApprovalAction({
    required String actionId,
    required String payload,
  }) async {
    if (actionId != NotificationActions.approve &&
        actionId != NotificationActions.deny) {
      return false;
    }
    final approvalPayload = parseApprovalPayload(payload);
    if (approvalPayload == null) return false;

    // Only handle remote commands (bash, edit, write, etc.) directly.
    // Local tools and local GitHub ops need the UI context.
    final kind = approvalPayload.kind;
    if (kind == 'local_tool' || kind == 'local_github_branch_delete') {
      return false;
    }

    final requestId = approvalPayload.approvalRequestId;
    if (requestId == null || requestId.isEmpty) return false;

    final approved = actionId == NotificationActions.approve;
    try {
      await MacCompanionService.instance
          .respondToCommandApproval(
            requestId: requestId,
            approved: approved,
          );
      dismissApprovalNotification(approvalPayload.requestId);
      debugPrint(
        '[NotificationService] Remote approval handled: ${approved ? 'approved' : 'denied'} for $requestId',
      );
      return true;
    } catch (e) {
      debugPrint('[NotificationService] Remote approval failed: $e');
    }
    return false;
  }

  /// Initialize the notification service.
  /// Must be called before using any notification methods.
  Future<void> initialize() async {
    if (_isInitialized) return;

    final androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    final iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    final initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notifications.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: _onNotificationResponse,
    );

    if (Platform.isAndroid) {
      await _createAndroidNotificationChannels();
    }

    _isInitialized = true;
    debugPrint('[NotificationService] Initialized');
  }

  Future<void> _createAndroidNotificationChannels() async {
    final androidPlugin =
        _notifications.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin == null) return;

    await androidPlugin.createNotificationChannel(
      const AndroidNotificationChannel(
        NotificationChannels.approvalRequests,
        'Approval Requests',
        description: 'Notifications for pending command approvals',
        importance: Importance.high,
        enableVibration: true,
        enableLights: true,
        showBadge: true,
      ),
    );

    await androidPlugin.createNotificationChannel(
      const AndroidNotificationChannel(
        NotificationChannels.responseReady,
        'Response Ready',
        description: 'Notifications when AI responses are complete',
        importance: Importance.defaultImportance,
        enableVibration: false,
        showBadge: false,
      ),
    );

    await androidPlugin.createNotificationChannel(
      const AndroidNotificationChannel(
        NotificationChannels.generalAlerts,
        'General Alerts',
        description: 'General system alerts and notifications',
        importance: Importance.low,
        enableVibration: false,
        showBadge: false,
      ),
    );

    // Group channel for multiple approvals
    await androidPlugin.createNotificationChannel(
      const AndroidNotificationChannel(
        '${NotificationChannels.approvalRequests}_group',
        'Approval Group',
        description: 'Grouped approval notifications',
        importance: Importance.high,
        enableVibration: true,
        showBadge: true,
      ),
    );
  }

  void _onNotificationResponse(NotificationResponse response) {
    final payload = response.payload;
    final actionId = response.actionId;

    if (actionId != null && actionId.isNotEmpty) {
      onNotificationAction?.call(actionId, payload);
    } else {
      onNotificationTapped?.call(payload);
    }
  }

  /// Request notification permission (iOS only; Android handled at install).
  Future<bool> requestPermission() async {
    if (Platform.isIOS) {
      final iosPlugin = _notifications.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      return await iosPlugin?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          false;
    }
    return true;
  }

  // ───────────────────────────────────────────────────────────
  // Settings helpers
  // ───────────────────────────────────────────────────────────

  static const _approvalNotificationsKey = 'approval_notifications_enabled';
  static const _responseNotificationsKey = 'response_notifications_enabled';
  static const _approvalSoundKey = 'approval_sound_enabled';
  static const _approvalVibrationKey = 'approval_vibration_enabled';
  static const _backgroundOnlyKey = 'notifications_background_only';
  static const _dndStartKey = 'dnd_start_hour';
  static const _dndEndKey = 'dnd_end_hour';
  static const _dndDestructiveBypassKey = 'dnd_destructive_bypass';

  bool get approvalNotificationsEnabled {
    return SharedPrefsService.instance.getBool(_approvalNotificationsKey) ??
        true;
  }

  Future<void> setApprovalNotificationsEnabled(bool value) async {
    await SharedPrefsService.instance.setBool(_approvalNotificationsKey, value);
  }

  bool get responseNotificationsEnabled {
    return SharedPrefsService.instance.getBool(_responseNotificationsKey) ??
        true;
  }

  Future<void> setResponseNotificationsEnabled(bool value) async {
    await SharedPrefsService.instance.setBool(_responseNotificationsKey, value);
  }

  bool get approvalSoundEnabled {
    return SharedPrefsService.instance.getBool(_approvalSoundKey) ?? true;
  }

  Future<void> setApprovalSoundEnabled(bool value) async {
    await SharedPrefsService.instance.setBool(_approvalSoundKey, value);
  }

  bool get approvalVibrationEnabled {
    return SharedPrefsService.instance.getBool(_approvalVibrationKey) ?? true;
  }

  Future<void> setApprovalVibrationEnabled(bool value) async {
    await SharedPrefsService.instance.setBool(_approvalVibrationKey, value);
  }

  bool get backgroundOnlyEnabled {
    return SharedPrefsService.instance.getBool(_backgroundOnlyKey) ?? true;
  }

  Future<void> setBackgroundOnlyEnabled(bool value) async {
    await SharedPrefsService.instance.setBool(_backgroundOnlyKey, value);
  }

  int get dndStartHour {
    return SharedPrefsService.instance.getInt(_dndStartKey) ?? 23;
  }

  Future<void> setDndStartHour(int value) async {
    await SharedPrefsService.instance.setInt(_dndStartKey, value);
  }

  int get dndEndHour {
    return SharedPrefsService.instance.getInt(_dndEndKey) ?? 7;
  }

  Future<void> setDndEndHour(int value) async {
    await SharedPrefsService.instance.setInt(_dndEndKey, value);
  }

  bool get dndDestructiveBypass {
    return SharedPrefsService.instance.getBool(_dndDestructiveBypassKey) ?? true;
  }

  Future<void> setDndDestructiveBypass(bool value) async {
    await SharedPrefsService.instance.setBool(_dndDestructiveBypassKey, value);
  }

  /// Check if Do Not Disturb is currently active.
  bool get isDndActive {
    final now = DateTime.now();
    final start = dndStartHour;
    final end = dndEndHour;
    if (start < end) {
      return now.hour >= start && now.hour < end;
    } else {
      return now.hour >= start || now.hour < end;
    }
  }

  /// Check if a notification should be suppressed due to DND.
  bool _shouldSuppressDnd(RiskLevel riskLevel) {
    if (!isDndActive) return false;
    if (dndDestructiveBypass &&
        (riskLevel == RiskLevel.destructive ||
            riskLevel == RiskLevel.irreversible)) {
      return false;
    }
    return true;
  }

  // ───────────────────────────────────────────────────────────
  // Approval notifications
  // ───────────────────────────────────────────────────────────

  /// Show an approval notification for a pending command.
  ///
  /// Returns the notification ID, or null if suppressed by settings.
  Future<int?> showApprovalNotification(
    ApprovalNotificationPayload payload, {
    bool appInBackground = true,
  }) async {
    if (!isInitialized) {
      debugPrint('[NotificationService] Not initialized, skipping approval notification');
      return null;
    }

    if (!approvalNotificationsEnabled) return null;
    if (backgroundOnlyEnabled && !appInBackground) return null;

    final riskLevel = riskLevelFromString(payload.riskLevel);
    if (_shouldSuppressDnd(riskLevel)) return null;

    _pendingApprovals[payload.requestId] = payload;
    _approvalQueueController.add(List.unmodifiable(_pendingApprovals.values));

    final id = payload.requestId.hashCode.abs();

    final title = '🔒 Approval: ${payload.toolName}';
    final body = _truncate(payload.command, 80);
    final riskText = riskLevel.shortName;
    final affectedText = payload.affectedPaths.isNotEmpty
        ? ' — ${_truncate(payload.affectedPaths.first, 40)}'
        : '';

    // Android actions
    final androidActions = [
      AndroidNotificationAction(
        NotificationActions.approve,
        'Approve',
        showsUserInterface: false,
        cancelNotification: true,
      ),
      AndroidNotificationAction(
        NotificationActions.deny,
        'Deny',
        showsUserInterface: false,
        cancelNotification: true,
      ),
      const AndroidNotificationAction(
        NotificationActions.openApp,
        'Open App',
        showsUserInterface: true,
      ),
    ];

    final androidDetails = AndroidNotificationDetails(
      NotificationChannels.approvalRequests,
      'Approval Requests',
      channelDescription: 'Pending command approvals',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
      enableVibration: approvalVibrationEnabled,
      vibrationPattern: approvalVibrationEnabled
          ? Int64List.fromList([0, 300, 100, 300])
          : null,
      enableLights: true,
      color: Color(int.parse(riskLevel.colorHex.replaceFirst('#', '0xFF'))),
      category: AndroidNotificationCategory.reminder,
      styleInformation: BigTextStyleInformation(
        '${payload.command}\n\n${riskLevel.emoji} $riskText$affectedText',
        contentTitle: title,
        summaryText: '$riskText — tap to review',
      ),
      actions: androidActions,
      groupKey: 'approvals',
      setAsGroupSummary: false,
    );

    final iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: approvalSoundEnabled,
      sound: approvalSoundEnabled ? 'default' : null,
      interruptionLevel: riskLevel == RiskLevel.destructive ||
              riskLevel == RiskLevel.irreversible
          ? InterruptionLevel.timeSensitive
          : InterruptionLevel.active,
      categoryIdentifier: 'approval',
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notifications.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: details,
      payload: payload.toPayloadString(),
    );

    // Update group summary
    await _updateApprovalGroupSummary();

    return id;
  }

  /// Dismiss an approval notification by request ID.
  Future<void> dismissApprovalNotification(String requestId) async {
    final id = requestId.hashCode.abs();
    await _notifications.cancel(id: id);
    _pendingApprovals.remove(requestId);
    _approvalQueueController.add(List.unmodifiable(_pendingApprovals.values));
    await _updateApprovalGroupSummary();
  }

  /// Dismiss all approval notifications.
  Future<void> dismissAllApprovalNotifications() async {
    for (final requestId in _pendingApprovals.keys.toList()) {
      await dismissApprovalNotification(requestId);
    }
  }

  /// Get all pending approval payloads.
  List<ApprovalNotificationPayload> get pendingApprovals =>
      List.unmodifiable(_pendingApprovals.values);

  /// Get pending approval count.
  int get pendingApprovalCount => _pendingApprovals.length;

  /// Update the group summary notification for multiple approvals.
  Future<void> _updateApprovalGroupSummary() async {
    if (!Platform.isAndroid) return;
    if (_pendingApprovals.isEmpty) {
      await _notifications.cancel(id: 999999);
      return;
    }

    final count = _pendingApprovals.length;
    final summaryId = 999999;
    final lines = _pendingApprovals.values.take(5).map((p) {
      final risk = riskLevelFromString(p.riskLevel);
      return '${risk.emoji} ${p.toolName}: ${_truncate(p.command, 40)}';
    }).toList();

    final inboxStyle = InboxStyleInformation(
      lines,
      contentTitle: '🔒 $count approvals pending',
      summaryText: count > 5 ? '+${count - 5} more' : '$count pending',
    );

    final androidDetails = AndroidNotificationDetails(
      '${NotificationChannels.approvalRequests}_group',
      'Approval Group',
      channelDescription: 'Grouped approval notifications',
      importance: Importance.high,
      priority: Priority.high,
      styleInformation: inboxStyle,
      groupKey: 'approvals',
      setAsGroupSummary: true,
      showWhen: true,
      enableVibration: false,
    );

    await _notifications.show(
      id: summaryId,
      title: '🔒 $count approvals pending',
      body: count > 1 ? '$count commands need your approval' : '1 command needs approval',
      notificationDetails: NotificationDetails(android: androidDetails),
    );
  }

  // ───────────────────────────────────────────────────────────
  // Response ready notifications
  // ───────────────────────────────────────────────────────────

  /// Show a response ready notification.
  ///
  /// Returns the notification ID, or null if suppressed by settings.
  Future<int?> showResponseReadyNotification(
    ResponseReadyPayload payload, {
    bool appInBackground = true,
  }) async {
    if (!isInitialized) {
      debugPrint('[NotificationService] Not initialized, skipping response notification');
      return null;
    }

    if (!responseNotificationsEnabled) return null;
    if (backgroundOnlyEnabled && !appInBackground) return null;

    final id = payload.chatId.hashCode.abs();
    final modelName = payload.modelUsed ?? 'AI';
    final status = payload.hasError ? '❌' : '✅';
    final title = '$status Response from $modelName';
    final body = payload.summary?.isNotEmpty == true
        ? _truncate(payload.summary!, 120)
        : '${payload.toolCallCount} tool call(s) executed. Tap to view.';

    final androidDetails = AndroidNotificationDetails(
      NotificationChannels.responseReady,
      'Response Ready',
      channelDescription: 'AI response completion notifications',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      showWhen: true,
      enableVibration: false,
      styleInformation: BigTextStyleInformation(
        body,
        contentTitle: title,
        summaryText: 'Tap to view full response',
      ),
      actions: [
        const AndroidNotificationAction(
          NotificationActions.openApp,
          'Open',
          showsUserInterface: true,
        ),
        const AndroidNotificationAction(
          NotificationActions.dismiss,
          'Dismiss',
        ),
      ],
    );

    final iosDetails = const DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: false,
      interruptionLevel: InterruptionLevel.passive,
      categoryIdentifier: 'response',
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notifications.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: details,
      payload: payload.toPayloadString(),
    );

    return id;
  }

  /// Dismiss a response notification by chat ID.
  Future<void> dismissResponseNotification(String chatId) async {
    final id = chatId.hashCode.abs();
    await _notifications.cancel(id: id);
  }

  // ───────────────────────────────────────────────────────────
  // General alert notifications
  // ───────────────────────────────────────────────────────────

  /// Show a general alert notification.
  Future<void> showGeneralAlert({
    required String title,
    required String body,
    String? payload,
    bool appInBackground = true,
  }) async {
    if (!isInitialized) return;
    if (backgroundOnlyEnabled && !appInBackground) return;

    final androidDetails = const AndroidNotificationDetails(
      NotificationChannels.generalAlerts,
      'General Alerts',
      channelDescription: 'General system alerts',
      importance: Importance.low,
      priority: Priority.low,
      showWhen: true,
      enableVibration: false,
    );

    final iosDetails = const DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: false,
      presentSound: false,
      interruptionLevel: InterruptionLevel.passive,
    );

    await _notifications.show(
      id: title.hashCode.abs(),
      title: title,
      body: body,
      notificationDetails: NotificationDetails(android: androidDetails, iOS: iosDetails),
      payload: payload,
    );
  }

  // ───────────────────────────────────────────────────────────
  // Utility
  // ───────────────────────────────────────────────────────────

  /// Cancel all notifications.
  Future<void> cancelAll() async {
    await _notifications.cancelAll();
    _pendingApprovals.clear();
    _approvalQueueController.add(List.unmodifiable(_pendingApprovals.values));
  }

  /// Get all active notification IDs.
  Future<List<dynamic>> getPendingNotifications() async {
    return await _notifications.pendingNotificationRequests();
  }

  /// Parse payload type from a raw payload string.
  NotificationPayloadType parsePayloadType(String payload) {
    try {
      final json = jsonDecode(payload) as Map<String, dynamic>;
      if (json.containsKey('requestId')) return NotificationPayloadType.approval;
      if (json.containsKey('chatId') && json.containsKey('toolCallCount')) {
        return NotificationPayloadType.responseReady;
      }
      return NotificationPayloadType.general;
    } catch (_) {
      return NotificationPayloadType.general;
    }
  }

  /// Parse approval payload from notification response.
  ApprovalNotificationPayload? parseApprovalPayload(String payload) {
    try {
      return ApprovalNotificationPayload.fromPayloadString(payload);
    } catch (_) {
      return null;
    }
  }

  /// Parse response ready payload from notification response.
  ResponseReadyPayload? parseResponsePayload(String payload) {
    try {
      return ResponseReadyPayload.fromPayloadString(payload);
    } catch (_) {
      return null;
    }
  }

  String _truncate(String text, int maxLength) {
    if (text.length <= maxLength) return text;
    return '${text.substring(0, maxLength - 3)}...';
  }
}
