import 'dart:convert';
import 'dart:math';
import 'package:image/image.dart' as img;
import 'package:budget_ai/src/chat/chat_image_widgets.dart';
import 'package:budget_ai/src/chat/chat_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const pixel =
    'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=';
void main() {
  testWidgets(
    'generated placeholder and image keep square dimensions and response insets',
    (tester) async {
      Widget host(Widget child) => MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: 360, child: child),
          ),
        ),
      );
      await tester.pumpWidget(host(const GeneratedChatImage()));
      final placeholder = tester.getRect(find.byType(AspectRatio).first);
      expect(placeholder.left, 12);
      expect(placeholder.width, 336);
      expect(placeholder.height, 336);
      await tester.pumpWidget(host(const GeneratedChatImage(dataUrl: pixel)));
      await tester.pump();
      expect(tester.getRect(find.byType(AspectRatio).first), placeholder);
      expect(find.text('Budget AI'), findsOneWidget);
      await tester.tap(find.byType(GeneratedChatImage));
      await tester.pumpAndSettle();
      expect(find.byType(GeneratedImageViewer), findsOneWidget);
      expect(find.byTooltip('Share image'), findsOneWidget);
      expect(find.text('Budget AI'), findsOneWidget);
    },
  );

  testWidgets(
    'photo normalization bounds JPEG upload while preserving dimensions',
    (tester) async {
      await tester.runAsync(() async {
        final random = Random(7);
        final photo = img.Image(width: 900, height: 700);
        for (final pixel in photo) {
          pixel.setRgb(
            random.nextInt(256),
            random.nextInt(256),
            random.nextInt(256),
          );
        }
        final source = img.encodePng(photo);
        expect(source.length, greaterThan(384 * 1024));
        final prepared = await prepareChatImage(source);
        expect(prepared, startsWith('data:image/jpeg;base64,'));
        final bytes = base64Decode(prepared.split(',').last);
        expect(bytes.length, lessThanOrEqualTo(768 * 1024));
        final decoded = img.decodeJpg(bytes)!;
        expect(decoded.width, 900);
        expect(decoded.height, 700);
      });
    },
  );

  test('images survive serialization and copying of local messages', () {
    final user = ChatMessage(
      text: '',
      isUser: true,
      timestamp: DateTime(2026),
      images: [pixel],
    );
    final restored = ChatMessage.fromJson(
      jsonDecode(jsonEncode(user.toJson())),
    );
    expect(restored.copyWith(text: 'Receipt').images, [pixel]);
    final output = ChatMessageBlock(
      id: 'image',
      type: ChatMessageBlockType.image,
      text: pixel,
      isComplete: true,
    );
    expect(
      ChatMessageBlock.fromJson(output.toJson()).type,
      ChatMessageBlockType.image,
    );
    expect(ChatMessage.fromJson({'text': 'Old chat'}).images, isEmpty);
  });
  testWidgets('attachment preview opens viewer and exposes removal', (
    tester,
  ) async {
    int? removed;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatImageStrip(
            images: [pixel],
            onRemove: (index) => removed = index,
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Remove image 1'));
    expect(removed, 0);
    expect(tester.getSize(find.byType(ChatImageView)), const Size(64, 64));
    await tester.tapAt(
      tester.getBottomLeft(find.byType(ChatImageView)) + const Offset(12, -12),
    );
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsOneWidget);
  });
  testWidgets('single sent attachment does not stretch across the bubble', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.centerRight,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ChatImageStrip(images: [pixel]),
                Text('Receipt'),
              ],
            ),
          ),
        ),
      ),
    );
    expect(tester.getSize(find.byType(ChatImageStrip)).width, 72);
    expect(tester.getSize(find.byType(ChatImageView)), const Size(72, 72));
  });
  testWidgets('invalid saved image renders a fallback', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: ChatImageView(dataUrl: 'invalid')),
    );
    expect(find.text('Image unavailable'), findsOneWidget);
  });
}
