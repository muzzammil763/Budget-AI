import 'dart:io';

import 'package:flutter/services.dart';

class AndroidBackgroundChatService {
  AndroidBackgroundChatService._();

  static const MethodChannel _channel = MethodChannel(
    'budget_ai/background_chat',
  );

  static Future<bool> start({
    String title = 'Budget AI chat running',
    String text = 'Keeping the active chat response connected.',
  }) async {
    if (!Platform.isAndroid) return false;
    return await _channel.invokeMethod<bool>('start', {
          'title': title,
          'text': text,
        }) ??
        false;
  }

  static Future<bool> stop() async {
    if (!Platform.isAndroid) return false;
    return await _channel.invokeMethod<bool>('stop') ?? false;
  }
}
