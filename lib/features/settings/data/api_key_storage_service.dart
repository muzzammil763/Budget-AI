import 'package:budget_ai/core/storage/shared_prefs_service.dart';

/// Service for storing API keys in [SharedPreferences] via
/// [SharedPrefsService]. Since this is a personal app, secure storage
/// is not required.
class ApiKeyStorageService {
  static const String _firepassKey = 'firepass_api_key';
  static const String _deepseekKey = 'deepseek_api_key';
  static const String _githubKey = 'github_api_key';
  static const String _searchApiKey = 'searchapi_api_key';
  static const String _xiaomiKey = 'xiaomi_api_key';

  static final _prefs = SharedPrefsService.instance;

  /// Save API key for a specific service
  static Future<void> saveApiKey(String service, String apiKey) async {
    await saveApiKeys(service, [apiKey]);
  }

  /// Save ordered API keys for a specific service.
  static Future<void> saveApiKeys(String service, List<String> apiKeys) async {
    final normalized = apiKeys
        .map((k) => k.trim())
        .where((k) => k.isNotEmpty)
        .toList();
    await _prefs.setStringList(_getServiceKey(service), normalized);
  }

  /// Add an API key to the end of the ordered list for a service.
  static Future<void> addApiKey(String service, String apiKey) async {
    final normalized = apiKey.trim();
    if (normalized.isEmpty) return;

    final existingKeys = await getApiKeys(service);
    if (existingKeys.contains(normalized)) return;

    await saveApiKeys(service, [...existingKeys, normalized]);
  }

  /// Get API key for a specific service
  static Future<String?> getApiKey(String service) async {
    final keys = await getApiKeys(service);
    return keys.isEmpty ? null : keys.first;
  }

  /// Get ordered API keys for a specific service.
  static Future<List<String>> getApiKeys(String service) async {
    return _prefs.getStringList(_getServiceKey(service)) ?? const [];
  }

  /// Delete API key for a specific service
  static Future<void> deleteApiKey(String service) async {
    await _prefs.remove(_getServiceKey(service));
  }

  /// Check if an API key exists for a specific service
  static Future<bool> hasApiKey(String service) async {
    final values = await getApiKeys(service);
    return values.isNotEmpty;
  }

  /// Clear all API keys
  static Future<void> clearAllApiKeys() async {
    await Future.wait([
      _prefs.remove(_firepassKey),
      _prefs.remove(_deepseekKey),
      _prefs.remove(_githubKey),
      _prefs.remove(_searchApiKey),
      _prefs.remove(_xiaomiKey),
    ]);
  }

  static String _getServiceKey(String service) {
    switch (service.toLowerCase()) {
      case 'firepass':
        return _firepassKey;
      case 'deepseek':
        return _deepseekKey;
      case 'github':
        return _githubKey;
      case 'searchapi':
        return _searchApiKey;
      case 'xiaomi':
      case 'xiaomimimo':
        return _xiaomiKey;
      default:
        return '${service}_api_key';
    }
  }

  // Convenience methods for specific services
  static Future<void> saveFirepassApiKey(String key) =>
      saveApiKey('firepass', key);
  static Future<String?> getFirepassApiKey() => getApiKey('firepass');
  static Future<List<String>> getFirepassApiKeys() => getApiKeys('firepass');
  static Future<void> deleteFirepassApiKey() => deleteApiKey('firepass');

  static Future<void> saveDeepSeekApiKey(String key) =>
      saveApiKey('deepseek', key);
  static Future<String?> getDeepSeekApiKey() => getApiKey('deepseek');
  static Future<List<String>> getDeepSeekApiKeys() => getApiKeys('deepseek');
  static Future<void> deleteDeepSeekApiKey() => deleteApiKey('deepseek');

  static Future<void> saveGithubApiKey(String key) => saveApiKey('github', key);
  static Future<String?> getGithubApiKey() => getApiKey('github');
  static Future<List<String>> getGithubApiKeys() => getApiKeys('github');
  static Future<void> deleteGithubApiKey() => deleteApiKey('github');

  static Future<void> saveSearchApiKey(String key) =>
      saveApiKey('searchapi', key);
  static Future<String?> getSearchApiKey() => getApiKey('searchapi');
  static Future<List<String>> getSearchApiKeys() => getApiKeys('searchapi');
  static Future<void> deleteSearchApiKey() => deleteApiKey('searchapi');

  static Future<void> saveXiaomiApiKey(String key) =>
      saveApiKey('xiaomi', key);
  static Future<String?> getXiaomiApiKey() => getApiKey('xiaomi');
  static Future<List<String>> getXiaomiApiKeys() =>
      getApiKeys('xiaomi');
  static Future<void> deleteXiaomiApiKey() => deleteApiKey('xiaomi');
}
