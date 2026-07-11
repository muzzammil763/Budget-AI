import 'dart:io';

import 'package:flutter/services.dart';

class IosBackgroundTaskService {
  IosBackgroundTaskService._();

  static const MethodChannel _channel = MethodChannel(
    'budget_ai/ios_background_task',
  );

  static Future<bool> start() async {
    if (!Platform.isIOS) return false;
    return await _channel.invokeMethod<bool>('start') ?? false;
  }

  static Future<bool> stop() async {
    if (!Platform.isIOS) return false;
    return await _channel.invokeMethod<bool>('stop') ?? false;
  }
}
