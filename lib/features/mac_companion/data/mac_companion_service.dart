import 'package:flutter/foundation.dart';

enum MacCompanionState { disconnected }

class MacCompanionStateNotifier extends ValueNotifier<MacCompanionStateData> {
  MacCompanionStateNotifier() : super(const MacCompanionStateData());
}

class MacCompanionStateData {
  final bool hasRemoteConnection;
  final String? remoteHost;
  final int? remotePort;
  final String? remoteWorkspaceRoot;
  final List<Map<String, dynamic>> remoteAllowedRoots;
  final String? remoteWorkspaceLabel;
  final String? remoteToken;

  const MacCompanionStateData({
    this.hasRemoteConnection = false,
    this.remoteHost,
    this.remotePort,
    this.remoteWorkspaceRoot,
    this.remoteAllowedRoots = const [],
    this.remoteWorkspaceLabel,
    this.remoteToken,
  });
}

class MacCompanionService {
  static final MacCompanionService instance = MacCompanionService._();
  MacCompanionService._();

  final stateNotifier = MacCompanionStateNotifier();

  Future<void> initialize() async {}
  Future<void> clearSelectedRemoteWorkspace() async {}
  Future<void> clearActiveCommandSessionAllowlist() async {}
  void setActiveChatSessionId(String? id) {}

  Future<Map<String, dynamic>> respondToCommandApproval({
    required String requestId,
    required bool approved,
    bool rememberForSession = false,
  }) async => {'ok': true};

  Future<Map<String, dynamic>> startRemoteTerminalCommand({
    required String command,
    String? workingDirectory,
    String? workspaceRoot,
  }) async => {'error': 'Not available'};

  Future<Map<String, dynamic>> getRemoteTerminalProgress(String commandId) async =>
      {'error': 'Not available'};

  Future<Map<String, dynamic>> getRemoteCommandProgress(String commandId) async =>
      {'error': 'Not available'};

  Future<Map<String, dynamic>> listRemoteFiles({
    required String path,
    String? workspaceRoot,
    bool recursive = false,
    int? maxResults,
    Iterable<String>? ignoredDirectoryNames,
  }) async => {'error': 'Not available'};

  Future<Map<String, dynamic>> readRemoteFile(
    String path, {
    String? workspaceRoot,
    int? startLine,
    int? endLine,
    bool updateState = true,
  }) async => {'error': 'Not available'};

  Future<Map<String, dynamic>> searchRemoteFiles({
    required String query,
    String? workspaceRoot,
    int? maxResults,
  }) async => {'error': 'Not available'};

  Future<Map<String, dynamic>> captureRemoteScreenshot({
    String type = 'fullscreen',
    String format = 'png',
    Map<String, dynamic>? region,
  }) async => {'error': 'Not available'};

  Future<Map<String, dynamic>> recordRemoteScreen({
    String type = 'fullscreen',
    int durationSeconds = 5,
    Map<String, dynamic>? region,
    bool includeMicrophoneAudio = false,
    bool includeSystemAudio = false,
    String? systemAudioSourceId,
  }) async => {'error': 'Not available'};

  Future<Map<String, dynamic>> recordRemoteAudio({
    int durationSeconds = 5,
    bool includeMicrophoneAudio = true,
    bool includeSystemAudio = false,
    String? systemAudioSourceId,
  }) async => {'error': 'Not available'};

  Future<Map<String, dynamic>> captureRemoteCameraPhoto({
    String? cameraDeviceId,
  }) async => {'error': 'Not available'};

  Future<Map<String, dynamic>> recordRemoteCameraVideo({
    int durationSeconds = 5,
    String? cameraDeviceId,
    bool includeMicrophoneAudio = false,
  }) async => {'error': 'Not available'};

  Future<Map<String, dynamic>> sendRemoteFile(String sourcePath) async =>
      {'error': 'Not available'};

  Future<Map<String, dynamic>> uploadWhatsAppFile(String path) async =>
      {'error': 'Not available'};

  Future<Map<String, dynamic>> writeRemoteFile({
    required String path,
    required String content,
    String? workspaceRoot,
    String? mode,
  }) async => {'error': 'Not available'};
}
