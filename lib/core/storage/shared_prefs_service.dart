import 'package:flutter/cupertino.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SharedPrefsService {
  static SharedPreferences? _instance;
  static const _chatModeKey = 'chat_mode';
  static const _selectedDeepSeekModelKey = 'selected_deepseek_model';

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

  static String? getSelectedDeepSeekModel() {
    return instance.getString(_selectedDeepSeekModelKey);
  }

  static Future<void> setSelectedDeepSeekModel(String modelId) async {
    await instance.setString(_selectedDeepSeekModelKey, modelId);
  }

  static String? getChatMode() {
    return instance.getString(_chatModeKey);
  }

  static Future<void> setChatMode(String modeId) async {
    await instance.setString(_chatModeKey, modeId);
  }
}
