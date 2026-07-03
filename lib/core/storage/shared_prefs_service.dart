import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SharedPrefsService {
  static SharedPreferences? _instance;
  static const _workspaceRootKey = 'workspace_root';
  static const _workspaceLabelKey = 'workspace_label';
  static const _workspaceArchiveNameKey = 'workspace_archive_name';
  static const _workspaceSourceKey = 'workspace_source';
  static const _recentWorkspaceProjectsKey = 'recent_workspace_projects';
  static const _connectedWorkspaceProjectsKey = 'connected_workspace_projects';
  static const _allowedWorkspaceRootsKey = 'allowed_workspace_roots';
  static const _showConfiguredProvidersOnlyKey =
      'show_configured_providers_only';
  static const _homeProviderColumnCountKey = 'home_provider_column_count';
  static const _maxToolRoundsKey = 'max_tool_rounds';
  static const _maxTotalToolCallsKey = 'max_total_tool_calls';
  static const _macRemotePermissionModeKey = 'mac_remote_permission_mode';
  static const _lastSeenChangelogVersionKey = 'last_seen_changelog_version';
  static const _toolEnabledPrefix = 'tool_enabled_';
  static const _toolAccessModePrefix = 'tool_access_mode_';
  static const _chatModeKey = 'chat_mode';
  static const _webSearchProviderKey = 'web_search_provider';
  static const _hapticsEnabledKey = 'haptics_enabled';

  static Future<void> init() async {
    _instance ??= await SharedPreferences.getInstance();
    return debugPrint('SharedPrefsService Initialized');
  }

  static SharedPreferences get instance {
    final prefs = _instance;
    if (prefs == null) {
      throw StateError('SharedPrefsService Is Not Initialized');
    }
    return prefs;
  }

  static String? getWorkspaceRoot() {
    return instance.getString(_workspaceRootKey);
  }

  static Future<void> setWorkspaceRoot(String path) async {
    await instance.setString(_workspaceRootKey, path);
  }

  static String? getWorkspaceLabel() {
    return instance.getString(_workspaceLabelKey);
  }

  static Future<void> setWorkspaceLabel(String label) async {
    await instance.setString(_workspaceLabelKey, label);
  }

  static String? getWorkspaceArchiveName() {
    return instance.getString(_workspaceArchiveNameKey);
  }

  static Future<void> setWorkspaceArchiveName(String archiveName) async {
    await instance.setString(_workspaceArchiveNameKey, archiveName);
  }

  static Future<void> clearWorkspaceRoot() async {
    await instance.remove(_workspaceRootKey);
    await instance.remove(_workspaceLabelKey);
    await instance.remove(_workspaceArchiveNameKey);
  }

  static String? getWorkspaceSource() {
    return instance.getString(_workspaceSourceKey);
  }

  static Future<void> setWorkspaceSource(String source) async {
    await instance.setString(_workspaceSourceKey, source);
  }

  static Future<void> clearWorkspaceSource() async {
    await instance.remove(_workspaceSourceKey);
  }

  static List<Map<String, dynamic>> getRecentWorkspaceProjects() {
    final rawItems =
        instance.getStringList(_recentWorkspaceProjectsKey) ?? const [];
    final results = <Map<String, dynamic>>[];
    for (final item in rawItems) {
      try {
        final decoded = jsonDecode(item);
        if (decoded is Map<String, dynamic>) {
          results.add(decoded);
        }
      } catch (_) {
        // Ignore malformed entries.
      }
    }
    return results;
  }

  static Future<void> saveRecentWorkspaceProject({
    required String path,
    required String label,
    String source = 'local',
  }) async {
    final trimmedPath = path.trim();
    final trimmedLabel = label.trim().isEmpty ? path.trim() : label.trim();
    if (trimmedPath.isEmpty) return;

    final existing = getRecentWorkspaceProjects()
        .where((item) => (item['path']?.toString().trim() ?? '') != trimmedPath)
        .toList();

    existing.insert(0, {
      'path': trimmedPath,
      'label': trimmedLabel,
      'source': source,
      'updated_at': DateTime.now().toIso8601String(),
    });

    final limited = existing.take(12).map(jsonEncode).toList();
    await instance.setStringList(_recentWorkspaceProjectsKey, limited);
  }

  static Future<void> removeRecentWorkspaceProject(String path) async {
    final trimmedPath = path.trim();
    final updated = getRecentWorkspaceProjects()
        .where((item) => (item['path']?.toString().trim() ?? '') != trimmedPath)
        .map(jsonEncode)
        .toList();
    await instance.setStringList(_recentWorkspaceProjectsKey, updated);
  }

  static List<Map<String, dynamic>> getConnectedWorkspaceProjects({
    String? source,
  }) {
    final rawItems =
        instance.getStringList(_connectedWorkspaceProjectsKey) ?? const [];
    final results = <Map<String, dynamic>>[];
    for (final item in rawItems) {
      try {
        final decoded = jsonDecode(item);
        if (decoded is Map<String, dynamic>) {
          final itemSource = decoded['source']?.toString().trim() ?? '';
          if (source == null || source == itemSource) {
            results.add(decoded);
          }
        }
      } catch (_) {
        // Ignore malformed entries.
      }
    }
    return results;
  }

  static Future<void> setConnectedWorkspaceProjects(
    List<Map<String, dynamic>> projects,
  ) async {
    final normalized = <Map<String, dynamic>>[];
    final seen = <String>{};
    for (final project in projects) {
      final path = project['path']?.toString().trim() ?? '';
      final source = project['source']?.toString().trim() ?? '';
      if (path.isEmpty || source.isEmpty || !seen.add('$source::$path')) {
        continue;
      }
      final label = project['label']?.toString().trim();
      normalized.add({
        'path': path,
        'label': label?.isNotEmpty == true ? label! : path,
        'source': source,
        'updated_at':
            project['updated_at']?.toString().trim().isNotEmpty == true
            ? project['updated_at'].toString().trim()
            : DateTime.now().toIso8601String(),
      });
    }
    await instance.setStringList(
      _connectedWorkspaceProjectsKey,
      normalized.map(jsonEncode).toList(),
    );
  }

  static Future<void> saveConnectedWorkspaceProject({
    required String path,
    required String label,
    required String source,
    int maxPerSource = 2,
  }) async {
    final trimmedPath = path.trim();
    final trimmedSource = source.trim();
    if (trimmedPath.isEmpty || trimmedSource.isEmpty) return;

    final existing = getConnectedWorkspaceProjects()
        .where(
          (item) =>
              !((item['source']?.toString().trim() ?? '') == trimmedSource &&
                  (item['path']?.toString().trim() ?? '') == trimmedPath),
        )
        .toList();

    final sameSource = existing
        .where(
          (item) => (item['source']?.toString().trim() ?? '') == trimmedSource,
        )
        .toList();
    final otherSources = existing
        .where(
          (item) => (item['source']?.toString().trim() ?? '') != trimmedSource,
        )
        .toList();

    sameSource.insert(0, {
      'path': trimmedPath,
      'label': label.trim().isEmpty ? trimmedPath : label.trim(),
      'source': trimmedSource,
      'updated_at': DateTime.now().toIso8601String(),
    });

    await setConnectedWorkspaceProjects([
      ...otherSources,
      ...sameSource.take(maxPerSource),
    ]);
  }

  static Future<void> removeConnectedWorkspaceProject({
    required String path,
    required String source,
  }) async {
    final trimmedPath = path.trim();
    final trimmedSource = source.trim();
    final updated = getConnectedWorkspaceProjects()
        .where(
          (item) =>
              (item['path']?.toString().trim() ?? '') != trimmedPath ||
              (item['source']?.toString().trim() ?? '') != trimmedSource,
        )
        .toList();
    await setConnectedWorkspaceProjects(updated);
  }

  static Future<void> clearConnectedWorkspaceProjects({String? source}) async {
    if (source == null) {
      await instance.remove(_connectedWorkspaceProjectsKey);
      return;
    }
    final updated = getConnectedWorkspaceProjects()
        .where((item) => (item['source']?.toString().trim() ?? '') != source)
        .toList();
    await setConnectedWorkspaceProjects(updated);
  }

  static List<Map<String, dynamic>> getAllowedWorkspaceRoots() {
    final rawItems =
        instance.getStringList(_allowedWorkspaceRootsKey) ?? const [];
    final results = <Map<String, dynamic>>[];
    for (final item in rawItems) {
      try {
        final decoded = jsonDecode(item);
        if (decoded is Map<String, dynamic>) {
          results.add(decoded);
        }
      } catch (_) {
        // Ignore malformed entries.
      }
    }
    return results;
  }

  static Future<void> saveAllowedWorkspaceRoot({
    required String path,
    required String label,
  }) async {
    final trimmedPath = path.trim();
    final trimmedLabel = label.trim().isEmpty ? trimmedPath : label.trim();
    if (trimmedPath.isEmpty) return;

    final existing = getAllowedWorkspaceRoots()
        .where((item) => (item['path']?.toString().trim() ?? '') != trimmedPath)
        .toList();

    existing.insert(0, {
      'path': trimmedPath,
      'label': trimmedLabel,
      'updated_at': DateTime.now().toIso8601String(),
    });

    final limited = existing.take(20).map(jsonEncode).toList();
    await instance.setStringList(_allowedWorkspaceRootsKey, limited);
  }

  static Future<void> removeAllowedWorkspaceRoot(String path) async {
    final trimmedPath = path.trim();
    final updated = getAllowedWorkspaceRoots()
        .where((item) => (item['path']?.toString().trim() ?? '') != trimmedPath)
        .map(jsonEncode)
        .toList();
    await instance.setStringList(_allowedWorkspaceRootsKey, updated);
  }

  static bool getShowConfiguredProvidersOnly() {
    return instance.getBool(_showConfiguredProvidersOnlyKey) ?? false;
  }

  static Future<void> setShowConfiguredProvidersOnly(bool value) async {
    await instance.setBool(_showConfiguredProvidersOnlyKey, value);
  }

  static const _homeProviderLayoutKey = 'home_provider_layout';

  static String getHomeProviderLayout() {
    return instance.getString(_homeProviderLayoutKey) ?? 'grid';
  }

  static Future<void> setHomeProviderLayout(String value) async {
    final normalized = value == 'list' ? 'list' : 'grid';
    await instance.setString(_homeProviderLayoutKey, normalized);
  }

  static int getHomeProviderColumnCount() {
    return (instance.getInt(_homeProviderColumnCountKey) ?? 3).clamp(2, 3);
  }

  static Future<void> setHomeProviderColumnCount(int value) async {
    await instance.setInt(_homeProviderColumnCountKey, value.clamp(2, 3));
  }

  static int getMaxToolRounds() {
    return instance.getInt(_maxToolRoundsKey) ?? 12;
  }

  static Future<void> setMaxToolRounds(int value) async {
    await instance.setInt(_maxToolRoundsKey, value.clamp(1, 50));
  }

  static int getMaxTotalToolCalls() {
    return instance.getInt(_maxTotalToolCallsKey) ?? 20;
  }

  static Future<void> setMaxTotalToolCalls(int value) async {
    await instance.setInt(_maxTotalToolCallsKey, value.clamp(1, 100));
  }

  static String getMacRemotePermissionMode() {
    return instance.getString(_macRemotePermissionModeKey) ?? 'default';
  }

  static Future<void> setMacRemotePermissionMode(String value) async {
    final normalized = value == 'full_access' ? 'full_access' : 'default';
    await instance.setString(_macRemotePermissionModeKey, normalized);
  }

  static String getWebSearchProvider() {
    return instance.getString(_webSearchProviderKey) ?? 'duckduckgo';
  }

  static Future<void> setWebSearchProvider(String value) async {
    final normalized = value == 'searchapi' ? 'searchapi' : 'duckduckgo';
    await instance.setString(_webSearchProviderKey, normalized);
  }

  static bool getHapticsEnabled() {
    return instance.getBool(_hapticsEnabledKey) ?? true;
  }

  static Future<void> setHapticsEnabled(bool value) async {
    await instance.setBool(_hapticsEnabledKey, value);
  }

  static const defaultRemoteAgentHomePath = r'$HOME/.remoteAgent';
  static const defaultProjectsPath = r'$HOME/.remoteAgent/projects';

  static String getDefaultProjectsPath() => defaultProjectsPath;

  static String? getLastSeenChangelogVersion() {
    return instance.getString(_lastSeenChangelogVersionKey);
  }

  static Future<void> setLastSeenChangelogVersion(String version) async {
    await instance.setString(_lastSeenChangelogVersionKey, version);
  }

  static bool getToolEnabled(String toolName) {
    return instance.getBool('$_toolEnabledPrefix$toolName') ?? true;
  }

  static Future<void> setToolEnabled(String toolName, bool enabled) async {
    await instance.setBool('$_toolEnabledPrefix$toolName', enabled);
  }

  static String? getToolAccessMode(String toolName) {
    return instance.getString('$_toolAccessModePrefix$toolName');
  }

  static Future<void> setToolAccessMode(String toolName, String mode) async {
    final normalized = mode == 'full_access'
        ? 'full_access'
        : 'approval_required';
    await instance.setString('$_toolAccessModePrefix$toolName', normalized);
  }

  static Future<void> clearToolEnabled(String toolName) async {
    await instance.remove('$_toolEnabledPrefix$toolName');
  }

  static Future<void> clearToolAccessMode(String toolName) async {
    await instance.remove('$_toolAccessModePrefix$toolName');
  }

  static String? getChatMode() {
    return instance.getString(_chatModeKey);
  }

  static Future<void> setChatMode(String modeId) async {
    await instance.setString(_chatModeKey, modeId);
  }

  static Future<void> clearChatMode() async {
    await instance.remove(_chatModeKey);
  }

  // Workspace mention index disk cache — keyed per workspace path so repeated
  // selections load instantly without a network round-trip.
  static const _wmIndexCachePrefix = 'wm_idx::';
  static const _wmIndexCachePathsKey = 'wm_idx_paths';
  static const _wmIndexCacheMaxEntries = 8;

  static List<Map<String, dynamic>>? getWorkspaceMentionIndexCache(
    String path,
  ) {
    final raw = instance.getString('$_wmIndexCachePrefix$path');
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded.whereType<Map<String, dynamic>>().toList();
      }
    } catch (_) {}
    return null;
  }

  static Future<void> saveWorkspaceMentionIndexCache(
    String path,
    List<Map<String, dynamic>> rawResults,
  ) async {
    await instance.setString(
      '$_wmIndexCachePrefix$path',
      jsonEncode(rawResults),
    );
    final paths = List<String>.from(
      instance.getStringList(_wmIndexCachePathsKey) ?? const [],
    );
    paths.remove(path);
    paths.insert(0, path);
    if (paths.length > _wmIndexCacheMaxEntries) {
      final toEvict = paths.sublist(_wmIndexCacheMaxEntries);
      for (final p in toEvict) {
        await instance.remove('$_wmIndexCachePrefix$p');
      }
      paths.removeRange(_wmIndexCacheMaxEntries, paths.length);
    }
    await instance.setStringList(_wmIndexCachePathsKey, paths);
  }
}
