import 'dart:convert';
import 'dart:io';

import 'package:budget_ai/src/helpers/app_data_directory_service.dart';
import 'package:flutter/foundation.dart';

class OnboardingService {
  OnboardingService._();

  static final OnboardingService instance = OnboardingService._();

  static const _fileName = 'onboarding_state.json';

  Future<bool> isCompleted() async {
    try {
      final file = File(await AppDataDirectoryService.filePath(_fileName));
      if (!await file.exists()) return false;
      final decoded = jsonDecode(await file.readAsString());
      return decoded is Map<String, dynamic> && decoded['completed'] == true;
    } catch (e) {
      debugPrint('[Onboarding] Failed to read state: $e');
      return false;
    }
  }

  Future<void> markCompleted() async {
    try {
      final file = File(await AppDataDirectoryService.filePath(_fileName));
      await file.writeAsString(
        jsonEncode({
          'completed': true,
          'completedAt': DateTime.now().toIso8601String(),
        }),
      );
    } catch (e) {
      debugPrint('[Onboarding] Failed to save state: $e');
    }
  }
}
