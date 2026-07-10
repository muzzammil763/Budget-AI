import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:budget_ai/src/helpers/notification_payload.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart'
    hide PendingNotificationRequest;

export 'package:flutter_local_notifications/flutter_local_notifications.dart'
    show PendingNotificationRequest;

enum NotificationPayloadType { responseReady, general }

class NotificationActions {
  static const String openApp = 'open_app';
  static const String dismiss = 'dismiss';
}

class NotificationChannels {
  static const String responseReady = 'response_ready';
  static const String generalAlerts = 'general_alerts';
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  static NotificationService get instance => _instance;

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  Function(String actionId, String? payload)? onNotificationAction;
  Function(String? payload)? onNotificationTapped;

  final List<Map<String, String>> _pendingActionQueue = [];
  final _pendingActionController = StreamController<void>.broadcast();

  void enqueueAction(String actionId, String payload) {
    _pendingActionQueue.add({'actionId': actionId, 'payload': payload});
    _pendingActionController.add(null);
  }

  List<Map<String, String>> flushPendingActions() {
    final actions = List<Map<String, String>>.from(_pendingActionQueue);
    _pendingActionQueue.clear();
    return actions;
  }

  Stream<void> get onPendingActions => _pendingActionController.stream;

  Future<void> initialize() async {
    if (_isInitialized) return;

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    const initSettings = InitializationSettings(
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
    final androidPlugin = _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (androidPlugin == null) return;

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

  Future<bool> requestPermission() async {
    if (Platform.isIOS) {
      await initialize();
      final iosPlugin = _notifications
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      return await iosPlugin?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          false;
    }
    if (Platform.isAndroid) {
      await initialize();
    }
    return true;
  }

  // In-memory defaults — resets on every app restart.
  bool _responseNotificationsEnabled = true;
  bool _backgroundOnlyEnabled = true;
  int _dndStartHour = 23;
  int _dndEndHour = 7;

  bool get responseNotificationsEnabled => _responseNotificationsEnabled;

  Future<void> setResponseNotificationsEnabled(bool value) async {
    _responseNotificationsEnabled = value;
  }

  bool get backgroundOnlyEnabled => _backgroundOnlyEnabled;

  Future<void> setBackgroundOnlyEnabled(bool value) async {
    _backgroundOnlyEnabled = value;
  }

  int get dndStartHour => _dndStartHour;

  Future<void> setDndStartHour(int value) async {
    _dndStartHour = value;
  }

  int get dndEndHour => _dndEndHour;

  Future<void> setDndEndHour(int value) async {
    _dndEndHour = value;
  }

  bool get isDndActive {
    final now = DateTime.now();
    final start = dndStartHour;
    final end = dndEndHour;
    if (start < end) {
      return now.hour >= start && now.hour < end;
    }
    return now.hour >= start || now.hour < end;
  }

  Future<int?> showResponseReadyNotification(
    ResponseReadyPayload payload, {
    bool appInBackground = true,
  }) async {
    if (!isInitialized) {
      debugPrint(
        '[NotificationService] Not initialized, skipping response notification',
      );
      return null;
    }

    if (!responseNotificationsEnabled) return null;
    if (backgroundOnlyEnabled && !appInBackground) return null;
    if (isDndActive) return null;

    final id = payload.chatId.hashCode.abs();
    final title = payload.hasError ? 'Response Error' : 'Response Ready';
    final body = payload.summary ?? 'Your AI response is ready.';

    final androidDetails = AndroidNotificationDetails(
      NotificationChannels.responseReady,
      'Response Ready',
      channelDescription: 'AI response completion notifications',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      showWhen: true,
      enableVibration: false,
      category: AndroidNotificationCategory.status,
      styleInformation: BigTextStyleInformation(body, contentTitle: title),
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: false,
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

  Future<void> dismissResponseNotification(String chatId) async {
    await _notifications.cancel(id: chatId.hashCode.abs());
  }

  Future<void> showGeneralAlert({
    required String title,
    required String body,
    String? payload,
    bool appInBackground = true,
  }) async {
    if (!isInitialized) return;
    if (backgroundOnlyEnabled && !appInBackground) return;

    final androidDetails = AndroidNotificationDetails(
      NotificationChannels.generalAlerts,
      'General Alerts',
      channelDescription: 'General system alerts and notifications',
      importance: Importance.low,
      priority: Priority.low,
      showWhen: true,
      enableVibration: false,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: false,
      presentSound: false,
    );

    await _notifications.show(
      id: DateTime.now().millisecondsSinceEpoch.remainder(100000),
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      ),
      payload: payload,
    );
  }

  Future<void> cancelAll() async {
    await _notifications.cancelAll();
  }

  Future<List<dynamic>> getPendingNotifications() async {
    return await _notifications.pendingNotificationRequests();
  }

  NotificationPayloadType parsePayloadType(String payload) {
    try {
      final json = jsonDecode(payload) as Map<String, dynamic>;
      if (json.containsKey('chatId') && json.containsKey('toolCallCount')) {
        return NotificationPayloadType.responseReady;
      }
      return NotificationPayloadType.general;
    } catch (_) {
      return NotificationPayloadType.general;
    }
  }

  ResponseReadyPayload? parseResponsePayload(String payload) {
    try {
      return ResponseReadyPayload.fromPayloadString(payload);
    } catch (_) {
      return null;
    }
  }

  void dispose() {
    _pendingActionController.close();
  }
}
