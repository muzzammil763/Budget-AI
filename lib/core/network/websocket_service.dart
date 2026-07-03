import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:budget_ai/features/mac_companion/data/mac_companion_service.dart';

/// Service for real-time WebSocket communication with Mac backend.
class WebSocketService {
  WebSocketService._();
  static final WebSocketService instance = WebSocketService._();

  WebSocketChannel? _channel;
  Timer? _reconnectTimer;
  bool _isConnected = false;
  bool _isConnecting = false;
  bool _isDisposed = false;

  // Exponential backoff state.
  int _consecutiveFailures = 0;
  static const _backoffBase = Duration(seconds: 2);
  static const _backoffMax = Duration(seconds: 60);
  static const _apiMajorVersion = 1;
  static const _apiPrefix = '/api/v$_apiMajorVersion';
  static const _protocolVersion = 1;

  final ValueNotifier<bool> connectionState = ValueNotifier(false);
  final ValueNotifier<String?> lastError = ValueNotifier(null);
  final StreamController<Map<String, dynamic>> _messageController =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get messages => _messageController.stream;
  bool get isConnected => _isConnected;

  /// Derives the WebSocket URL from the backend base URL, defaulting to wss://
  /// when the base URL uses https://.
  static String _buildWsUrl(String host, int port) {
    // If the user supplied a full URL scheme, derive ws/wss from it.
    if (host.startsWith('https://') || host.startsWith('http://')) {
      final uri = Uri.parse(host);
      final scheme = uri.scheme == 'https' ? 'wss' : 'ws';
      final effectivePort = uri.hasPort ? uri.port : port;
      return '$scheme://${uri.host}:$effectivePort$_apiPrefix/ws';
    }
    // Bare MacRemote hosts are local development backends unless the user
    // explicitly saved https:// above.
    return 'ws://$host:$port$_apiPrefix/ws';
  }

  static String _messageId() =>
      DateTime.now().microsecondsSinceEpoch.toRadixString(36);

  static Map<String, dynamic> _envelope(
    String type,
    Map<String, dynamic> payload, {
    String? id,
  }) {
    return {
      'type': type,
      'id': id ?? _messageId(),
      'timestamp': DateTime.now().toIso8601String(),
      'protocol_version': _protocolVersion,
      'payload': payload,
    };
  }

  /// Connect to the Mac backend via WebSocket.
  Future<void> connect() async {
    if (_isDisposed || _isConnecting || _isConnected) return;

    _isConnecting = true;
    lastError.value = null;

    try {
      final state = MacCompanionService.instance.stateNotifier.value;
      final host = state.remoteHost;
      final port = state.remotePort ?? 8001;
      final token = state.remoteToken;

      if (host == null || token == null) {
        _isConnecting = false;
        lastError.value = 'Mac backend not configured';
        return;
      }

      final wsUrl = _buildWsUrl(host, port);

      _channel = WebSocketChannel.connect(
        Uri.parse(wsUrl),
        protocols: ['macremote.v1', 'macremote.token.$token'],
      );

      _channel!.stream.listen(
        (message) {
          try {
            final data = jsonDecode(message) as Map<String, dynamic>;
            _messageController.add(data);
          } catch (_) {
            _messageController.add({'type': 'message', 'data': message});
          }
        },
        onDone: () {
          _handleDisconnection('Connection closed');
        },
        onError: (error) {
          _handleDisconnection('Connection error: $error');
        },
        cancelOnError: true,
      );

      _channel!.sink.add(
        jsonEncode(
          _envelope('connect', {'api_major_version': _apiMajorVersion}),
        ),
      );

      _isConnected = true;
      _isConnecting = false;
      _consecutiveFailures = 0;
      connectionState.value = true;

      _reconnectTimer?.cancel();
      _reconnectTimer = null;
    } catch (e) {
      _isConnecting = false;
      _handleDisconnection('Failed to connect: $e');
    }
  }

  /// Handles disconnection and schedules a reconnect with exponential backoff.
  void _handleDisconnection(String error) {
    _isConnected = false;
    _isConnecting = false;
    connectionState.value = false;
    lastError.value = error;

    if (_isDisposed) return;

    _consecutiveFailures++;
    final delay = _backoffDelay(_consecutiveFailures);

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () {
      if (!_isDisposed && !_isConnected) {
        connect();
      }
    });
  }

  /// Returns the capped backoff delay for the given failure count.
  static Duration _backoffDelay(int failures) {
    final seconds = _backoffBase.inSeconds * (1 << (failures - 1).clamp(0, 5));
    return Duration(
      seconds: seconds.clamp(_backoffBase.inSeconds, _backoffMax.inSeconds),
    );
  }

  /// Send a message to the Mac backend.
  void sendMessage(Map<String, dynamic> message) {
    if (!_isConnected || _channel == null) {
      lastError.value = 'Not connected to backend';
      return;
    }
    try {
      final payload = Map<String, dynamic>.from(message);
      final type = payload.remove('type')?.toString() ?? 'message';
      _channel!.sink.add(jsonEncode(_envelope(type, payload)));
    } catch (e) {
      lastError.value = 'Failed to send message: $e';
    }
  }

  /// Send a task update or command.
  void sendTaskUpdate({
    required String taskId,
    required String status,
    String? message,
    Map<String, dynamic>? data,
  }) {
    sendMessage({
      'type': 'task_update',
      'task_id': taskId,
      'status': status,
      'message': message,
      'data': data,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  /// Send a ping to keep connection alive.
  void sendPing() {
    sendMessage({'type': 'ping'});
  }

  /// Disconnect from the backend.
  void disconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;

    try {
      _channel?.sink.close();
    } catch (_) {}

    _channel = null;
    _isConnected = false;
    _isConnecting = false;
    _consecutiveFailures = 0;
    connectionState.value = false;
  }

  /// Dispose the service — stops all reconnect attempts permanently.
  void dispose() {
    _isDisposed = true;
    disconnect();
    _messageController.close();
    connectionState.dispose();
    lastError.dispose();
  }
}
