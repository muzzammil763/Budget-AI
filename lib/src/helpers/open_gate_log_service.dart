import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:budget_ai/src/helpers/app_data_directory_service.dart';
import 'package:path/path.dart' as path;

class OpenGateLogService {
  const OpenGateLogService._();

  static const String prefix = 'OpenGateLogService:';
  static const int _maxLogBytes = 1024 * 1024;
  static const int _maxPendingLines = 200;
  static const Duration _heartbeatInterval = Duration(seconds: 10);

  static File? _logFile;
  static File? _runMarkerFile;
  static Timer? _heartbeatTimer;
  static bool _debugPrintHookInstalled = false;
  static bool _initialized = false;
  static final List<String> _pendingLines = <String>[];
  static void Function(String? message, {int? wrapWidth})? _originalDebugPrint;

  static void installDebugPrintHook() {
    if (_debugPrintHookInstalled) return;
    _debugPrintHookInstalled = true;
    _originalDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      final formatted = _format(message);
      _originalDebugPrint?.call(formatted, wrapWidth: wrapWidth);
      _persist(formatted);
    };
  }

  static Future<void> initialize() async {
    if (_initialized || kIsWeb) return;

    try {
      final logsDirectory =
          await AppDataDirectoryService.remoteAgentChildDirectory('logs');
      _logFile = File(path.join(logsDirectory.path, 'opengate.log'));
      _runMarkerFile = File(path.join(logsDirectory.path, 'active_run.json'));

      await _rotateLogIfNeeded();
      await _recordPreviousUncleanRunIfNeeded();

      _initialized = true;
      await _writeRunMarker('running');
      _flushPendingLines();
      log('Persistent logs ready: ${_logFile!.path}', area: 'Logs');

      _heartbeatTimer?.cancel();
      _heartbeatTimer = Timer.periodic(
        _heartbeatInterval,
        (_) => unawaited(_writeRunMarker('running')),
      );
    } catch (error, stack) {
      _originalDebugPrint?.call(
        _format(
          'Could not initialize file logging: $error\n$stack',
          area: 'Logs',
        ),
      );
    }
  }

  static void log(String? message, {String? area}) {
    debugPrint(_format(message, area: area));
  }

  static void logError(Object error, StackTrace? stack, {String? area}) {
    log('$error\n$stack', area: area ?? 'Error');
  }

  static Future<String?> currentLogPath() async {
    if (!_initialized) {
      await initialize();
    }
    return _logFile?.path;
  }

  static Future<void> markCleanShutdown() async {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    await _writeRunMarker('clean_shutdown');
  }

  static String _format(String? message, {String? area}) {
    final text = message ?? '';
    if (text.startsWith(prefix)) {
      return text;
    }

    final trimmedArea = area?.trim();
    if (trimmedArea != null && trimmedArea.isNotEmpty) {
      return '$prefix [$trimmedArea] $text';
    }

    if (text.startsWith('[')) {
      return '$prefix $text';
    }

    return '$prefix [App] $text';
  }

  static void _persist(String formattedMessage) {
    final line = '${DateTime.now().toIso8601String()} $formattedMessage\n';
    final file = _logFile;
    if (!_initialized || file == null) {
      _pendingLines.add(line);
      if (_pendingLines.length > _maxPendingLines) {
        _pendingLines.removeAt(0);
      }
      return;
    }

    unawaited(
      file.writeAsString(line, mode: FileMode.append).catchError((_) => file),
    );
  }

  static void _flushPendingLines() {
    final file = _logFile;
    if (file == null || _pendingLines.isEmpty) return;

    final lines = List<String>.from(_pendingLines);
    _pendingLines.clear();
    unawaited(
      file
          .writeAsString(lines.join(), mode: FileMode.append)
          .catchError((_) => file),
    );
  }

  static Future<void> _rotateLogIfNeeded() async {
    final file = _logFile;
    if (file == null || !await file.exists()) return;

    final length = await file.length();
    if (length <= _maxLogBytes) return;

    final rotatedPath = path.join(
      path.dirname(file.path),
      'opengate.previous.log',
    );
    final rotated = File(rotatedPath);
    if (await rotated.exists()) {
      await rotated.delete();
    }
    await file.rename(rotatedPath);
  }

  static Future<void> _recordPreviousUncleanRunIfNeeded() async {
    final markerFile = _runMarkerFile;
    final logFile = _logFile;
    if (markerFile == null || logFile == null || !await markerFile.exists()) {
      return;
    }

    try {
      final raw = await markerFile.readAsString();
      final marker = jsonDecode(raw);
      if (marker is! Map || marker['status'] == 'clean_shutdown') {
        return;
      }

      final summary = const JsonEncoder.withIndent('  ').convert(marker);
      await logFile.writeAsString(
        '${DateTime.now().toIso8601String()} '
        '${_format('Previous run ended without a clean shutdown. Last marker:\n$summary', area: 'Crash')}\n',
        mode: FileMode.append,
      );
    } catch (error, stack) {
      await logFile.writeAsString(
        '${DateTime.now().toIso8601String()} '
        '${_format('Could not read previous run marker: $error\n$stack', area: 'Crash')}\n',
        mode: FileMode.append,
      );
    }
  }

  static Future<void> _writeRunMarker(String status) async {
    final markerFile = _runMarkerFile;
    if (markerFile == null) return;

    try {
      final payload = {
        'status': status,
        'updated_at': DateTime.now().toIso8601String(),
        'pid': pid,
        'debug_mode': kDebugMode,
        'profile_mode': kProfileMode,
        'release_mode': kReleaseMode,
      };
      await markerFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(payload),
      );
    } catch (_) {
      // Nothing else can safely report marker write failures.
    }
  }
}
