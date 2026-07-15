import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

class VibrationManager with WidgetsBindingObserver {
  static final VibrationManager instance = VibrationManager._internal();

  factory VibrationManager() => instance;

  VibrationManager._internal() {
    WidgetsBinding.instance.addObserver(this);
    _updateForegroundState(WidgetsBinding.instance.lifecycleState);
  }

  bool _isAppInForeground = true;
  DateTime? _lastStreamingFeedbackAt;

  static const _streamingFeedbackInterval = Duration(milliseconds: 140);

  bool get isAppInForeground => _isAppInForeground;

  bool get shouldVibrate => _isAppInForeground;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _updateForegroundState(state);
  }

  void _updateForegroundState(AppLifecycleState? state) {
    _isAppInForeground = state == null || state == AppLifecycleState.resumed;
  }

  Future<void> triggerFeedback({String type = 'selectionClick'}) async {
    if (!shouldVibrate) return;

    switch (type) {
      case 'lightImpact':
        HapticFeedback.lightImpact();
        break;
      case 'mediumImpact':
        HapticFeedback.mediumImpact();
        break;
      case 'heavyImpact':
        HapticFeedback.heavyImpact();
        break;
      default:
        HapticFeedback.selectionClick();
    }
  }

  /// A premium-quality haptic for streaming text responses.
  /// Uses [selectionClick] so response text feels alive without becoming
  /// intrusive during long streams.
  Future<void> triggerStreamingFeedback({bool isForeground = true}) async {
    if (!isForeground || !shouldVibrate) return;
    final now = DateTime.now();
    final lastFeedbackAt = _lastStreamingFeedbackAt;
    if (lastFeedbackAt != null &&
        now.difference(lastFeedbackAt) < _streamingFeedbackInterval) {
      return;
    }
    _lastStreamingFeedbackAt = now;
    HapticFeedback.selectionClick();
  }

  /// Checks whether haptic feedback should fire based on app foreground and
  /// an optional chat-screen visibility flag.
  bool canTrigger({required bool isChatScreenVisible}) {
    return shouldVibrate && isChatScreenVisible;
  }
}
