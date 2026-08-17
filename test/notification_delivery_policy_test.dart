import 'package:budget_ai/src/helpers/notification_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('notification preference strictly gates delivery', () {
    expect(
      shouldDeliverNotification(
        preferenceEnabled: false,
        channelEnabled: true,
        backgroundOnly: false,
        appInBackground: true,
      ),
      isFalse,
    );
    expect(
      shouldDeliverNotification(
        preferenceEnabled: true,
        channelEnabled: true,
        backgroundOnly: false,
        appInBackground: true,
      ),
      isTrue,
    );
  });

  test('channel and background rules still apply when enabled', () {
    expect(
      shouldDeliverNotification(
        preferenceEnabled: true,
        channelEnabled: false,
        backgroundOnly: false,
        appInBackground: true,
      ),
      isFalse,
    );
    expect(
      shouldDeliverNotification(
        preferenceEnabled: true,
        channelEnabled: true,
        backgroundOnly: true,
        appInBackground: false,
      ),
      isFalse,
    );
  });
}
