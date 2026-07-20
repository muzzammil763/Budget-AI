import 'package:budget_ai/src/chat/user_bubble_style_surface.dart';
import 'package:budget_ai/src/settings/bubble_style_settings_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('all bubble silhouettes paint in ${brightness.name} mode', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: brightness),
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  for (final style in UserBubbleStyle.values)
                    Align(
                      alignment: Alignment.centerRight,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 280),
                        child: Builder(
                          builder: (context) {
                            return UserBubbleStyleSurface(
                              style: style,
                              child: Text(
                                'A message using the ${style.label} bubble.',
                                style: UserBubbleStyleSurface.messageTextStyle(
                                  context,
                                  style,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'message text uses the readable bubble foreground in ${brightness.name} mode',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(brightness: brightness),
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  for (final style in UserBubbleStyle.values) {
                    final textStyle = UserBubbleStyleSurface.messageTextStyle(
                      context,
                      style,
                    );
                    expect(
                      textStyle.color,
                      UserBubbleStyleSurface.foregroundColor(context, style),
                    );
                    expect(textStyle.fontSize, 16);
                  }
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        );
      },
    );
  }
}
