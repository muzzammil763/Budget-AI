import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OnboardingService {
  OnboardingService._();

  static final OnboardingService instance = OnboardingService._();

  static const _completedKey = 'onboarding_completed';
  static const _completedAtKey = 'onboarding_completed_at';
  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();

  Future<bool> isCompleted() async {
    try {
      return await _preferences.getBool(_completedKey) ?? false;
    } catch (e) {
      debugPrint('[Onboarding] Failed to read state: $e');
      return false;
    }
  }

  Future<void> markCompleted() async {
    try {
      await _preferences.setBool(_completedKey, true);
      await _preferences.setString(
        _completedAtKey,
        DateTime.now().toIso8601String(),
      );
    } catch (e) {
      debugPrint('[Onboarding] Failed to save state: $e');
    }
  }
}
