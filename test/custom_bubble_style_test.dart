import 'package:budget_ai/src/chat/user_bubble_style_surface.dart';
import 'package:budget_ai/src/settings/bubble_style_screen.dart';
import 'package:budget_ai/src/settings/bubble_style_settings_service.dart';
import 'package:budget_ai/src/settings/custom_bubble_style_edit_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('bubble picker exposes search and custom add controls', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: BubbleStyleScreen()));

    expect(
      find.byKey(const ValueKey('bubble-style-search-field')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('add-custom-bubble')), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('bubble-style-search-field')),
      'Ledger',
    );
    await tester.pump();

    expect(find.text('Ledger'), findsNWidgets(2));
    expect(find.text('Classic'), findsNothing);
  });

  testWidgets('custom editor provides colors shapes patterns and deletion', (
    tester,
  ) async {
    const custom = CustomBubbleStyle(
      id: 'ocean',
      name: 'Ocean notes',
      backgroundColorValue: 0xFF123456,
      textColorValue: 0xFFFFFFFF,
      shape: CustomBubbleShape.ticket,
      pattern: CustomBubblePattern.waves,
    );

    await tester.pumpWidget(
      const MaterialApp(home: CustomBubbleStyleEditScreen(style: custom)),
    );

    expect(find.text('Edit Custom Bubble'), findsOneWidget);
    expect(find.text('BUBBLE COLOR'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -650));
    await tester.pump();

    expect(find.text('TEXT COLOR'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -1600));
    await tester.pump();

    expect(find.text('SHAPE'), findsOneWidget);
    expect(find.text('PATTERN'), findsOneWidget);
    expect(find.text('Ticket'), findsOneWidget);
    expect(find.text('Waves'), findsOneWidget);
    expect(find.text('Delete Bubble'), findsOneWidget);
  });

  testWidgets('add action opens the custom bubble editor', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: BubbleStyleScreen()));
    await tester.tap(find.byKey(const ValueKey('add-custom-bubble')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Add Custom Bubble'), findsOneWidget);
    expect(find.byKey(const ValueKey('custom-bubble-name')), findsOneWidget);
  });

  testWidgets('all custom shapes and patterns paint with chosen text color', (
    tester,
  ) async {
    const textColor = Color(0xFFFFEEDD);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => SingleChildScrollView(
              child: Column(
                children: [
                  for (final shape in CustomBubbleShape.values)
                    for (final pattern in CustomBubblePattern.values)
                      UserBubbleStyleSurface(
                        style: UserBubbleStyle.custom,
                        customStyle: CustomBubbleStyle(
                          id: '${shape.name}-${pattern.name}',
                          name: 'Preview',
                          backgroundColorValue: 0xFF264653,
                          textColorValue: 0xFFFFEEDD,
                          shape: shape,
                          pattern: pattern,
                        ),
                        child: const Text('Custom preview'),
                      ),
                  Builder(
                    builder: (context) {
                      const custom = CustomBubbleStyle(
                        id: 'foreground',
                        name: 'Foreground',
                        backgroundColorValue: 0xFF000000,
                        textColorValue: 0xFFFFEEDD,
                        shape: CustomBubbleShape.rounded,
                        pattern: CustomBubblePattern.none,
                      );
                      expect(
                        UserBubbleStyleSurface.foregroundColor(
                          context,
                          UserBubbleStyle.custom,
                          customStyle: custom,
                        ),
                        textColor,
                      );
                      return const SizedBox.shrink();
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  test('custom bubble model round-trips through JSON', () {
    const style = CustomBubbleStyle(
      id: 'sunset',
      name: 'Sunset',
      backgroundColorValue: 0xFFD75A3D,
      textColorValue: 0xFFFFFFFF,
      shape: CustomBubbleShape.angular,
      pattern: CustomBubblePattern.diagonal,
    );

    expect(CustomBubbleStyle.fromJson(style.toJson()), style);
  });
}
