import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

class AndroidSettingsHelper {
  AndroidSettingsHelper._();
  static final AndroidSettingsHelper instance = AndroidSettingsHelper._();

  final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();
  AndroidDeviceInfo? _androidInfo;

  Future<void> initialize() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        _androidInfo = await _deviceInfo.androidInfo;
      } catch (e) {
        debugPrint('Failed to get Android device info: $e');
      }
    }
  }

  bool get isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  int? get androidVersion => _androidInfo?.version.sdkInt;
}
