import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Run from the repository root with:
// flutter test tool/generate_app_icons_test.dart
//
// Launcher icons use a minimal composition of the Budget AI bars, orbit, dot,
// and spark. Light and dark appearances invert the bars/background while
// retaining the same geometry. Android's monochrome layer uses the same mark.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('generate minimal Budget AI app icon assets', () async {
    await _writeFullColourIcon(
      'assets/icons/budget_mark_1024.png',
      pixels: 1024,
      markScale: 1,
    );

    const iosIconDirectory = 'ios/Runner/Assets.xcassets/AppIcon.appiconset';
    await _writeFullColourIcon(
      '$iosIconDirectory/AppIcon-Light-1024.png',
      pixels: 1024,
      markScale: 1,
      appearance: _IconAppearance.light,
    );
    await _writeFullColourIcon(
      '$iosIconDirectory/AppIcon-Dark-1024.png',
      pixels: 1024,
      markScale: 1,
    );
    await _writeMonochromeIcon(
      '$iosIconDirectory/AppIcon-Tinted-1024.png',
      pixels: 1024,
      markScale: 1,
    );

    for (final density in _androidDensities.entries) {
      final directory = 'android/app/src/main/res/mipmap-${density.key}';
      final legacyPixels = (48 * density.value).round();
      final adaptivePixels = (108 * density.value).round();

      await _writeFullColourIcon(
        '$directory/ic_launcher.png',
        pixels: legacyPixels,
        markScale: 1,
      );
      await _writeSolidIcon(
        '$directory/ic_launcher_background.png',
        pixels: adaptivePixels,
        color: _iconBackground,
      );
      await _writeFullColourIcon(
        '$directory/ic_launcher_foreground.png',
        pixels: adaptivePixels,
        markScale: 0.86,
        transparentBackground: true,
      );
      await _writeMonochromeIcon(
        '$directory/ic_launcher_monochrome.png',
        pixels: adaptivePixels,
        markScale: 0.86,
      );
    }
  });
}

const _androidDensities = <String, double>{
  'mdpi': 1,
  'hdpi': 1.5,
  'xhdpi': 2,
  'xxhdpi': 3,
  'xxxhdpi': 4,
};

const _iconBackground = Color(0xff020307);
const _iconAccent = Color(0xff448aff);
const _lightIconBackground = Color(0xfff4f7fb);

enum _IconAppearance { light, dark }

Future<void> _writeFullColourIcon(
  String path, {
  required int pixels,
  required double markScale,
  bool transparentBackground = false,
  _IconAppearance appearance = _IconAppearance.dark,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final outputSize = Size.square(pixels.toDouble());

  if (!transparentBackground) {
    canvas.drawColor(
      appearance == _IconAppearance.light
          ? _lightIconBackground
          : _iconBackground,
      BlendMode.src,
    );
  }

  final markPixels = pixels * markScale;
  final offset = (pixels - markPixels) / 2;
  canvas.save();
  canvas.translate(offset, offset);
  _paintMinimalMark(
    canvas,
    Rect.fromLTWH(0, 0, markPixels, markPixels),
    bars: appearance == _IconAppearance.light ? _iconBackground : Colors.white,
    accent: _iconAccent,
  );
  canvas.restore();

  await _writePicture(
    path,
    recorder.endRecording(),
    outputSize,
    opaqueRgb: !transparentBackground,
  );
}

Future<void> _writeSolidIcon(
  String path, {
  required int pixels,
  required Color color,
}) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawColor(color, BlendMode.src);
  await _writePicture(
    path,
    recorder.endRecording(),
    Size.square(pixels.toDouble()),
    opaqueRgb: true,
  );
}

Future<void> _writeMonochromeIcon(
  String path, {
  required int pixels,
  required double markScale,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final markPixels = pixels * markScale;
  final offset = (pixels - markPixels) / 2;
  _paintMonochromeMark(
    canvas,
    Rect.fromLTWH(offset, offset, markPixels, markPixels),
  );
  await _writePicture(
    path,
    recorder.endRecording(),
    Size.square(pixels.toDouble()),
  );
}

void _paintMonochromeMark(Canvas canvas, Rect bounds) {
  _paintMinimalMark(canvas, bounds, bars: Colors.white, accent: Colors.white);
}

void _paintMinimalMark(
  Canvas canvas,
  Rect bounds, {
  required Color bars,
  required Color accent,
}) {
  final center = bounds.center;
  final shortest = math.min(bounds.width, bounds.height);

  canvas.drawArc(
    Rect.fromCircle(center: center, radius: shortest * 0.355),
    math.pi * 0.82,
    math.pi * 1.53,
    false,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1, shortest * 0.018)
      ..strokeCap = StrokeCap.round
      ..shader = ui.Gradient.sweep(center, [
        accent.withValues(alpha: 0.18),
        accent,
      ]),
  );

  final baseline = center.dy + shortest * 0.18;
  final barWidth = shortest * 0.095;
  final gap = shortest * 0.06;
  final heights = [shortest * 0.19, shortest * 0.30, shortest * 0.42];
  final barsLeft = center.dx - (barWidth * 3 + gap * 2) / 2;
  for (var i = 0; i < 3; i++) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          barsLeft + i * (barWidth + gap),
          baseline - heights[i],
          barWidth,
          heights[i],
        ),
        Radius.circular(barWidth / 2),
      ),
      Paint()..color = bars,
    );
  }

  canvas.drawCircle(
    Offset(
      barsLeft + 2 * (barWidth + gap) + barWidth / 2,
      baseline - heights[2] - shortest * 0.075,
    ),
    shortest * 0.035,
    Paint()..color = accent,
  );

  final sparkCenter = Offset(
    bounds.right - shortest * 0.19,
    bounds.top + shortest * 0.19,
  );
  final r = shortest * 0.078;
  const pinch = 0.22;
  final spark = Path()
    ..moveTo(sparkCenter.dx, sparkCenter.dy - r)
    ..quadraticBezierTo(
      sparkCenter.dx + r * pinch,
      sparkCenter.dy - r * pinch,
      sparkCenter.dx + r,
      sparkCenter.dy,
    )
    ..quadraticBezierTo(
      sparkCenter.dx + r * pinch,
      sparkCenter.dy + r * pinch,
      sparkCenter.dx,
      sparkCenter.dy + r,
    )
    ..quadraticBezierTo(
      sparkCenter.dx - r * pinch,
      sparkCenter.dy + r * pinch,
      sparkCenter.dx - r,
      sparkCenter.dy,
    )
    ..quadraticBezierTo(
      sparkCenter.dx - r * pinch,
      sparkCenter.dy - r * pinch,
      sparkCenter.dx,
      sparkCenter.dy - r,
    )
    ..close();
  canvas.drawPath(spark, Paint()..color = accent);
}

Future<void> _writePicture(
  String path,
  ui.Picture picture,
  Size size, {
  bool opaqueRgb = false,
}) async {
  final image = await picture.toImage(size.width.round(), size.height.round());
  final data = await image.toByteData(
    format: opaqueRgb ? ui.ImageByteFormat.rawRgba : ui.ImageByteFormat.png,
  );
  if (data == null) throw StateError('Could not encode $path as PNG.');
  final bytes = Uint8List.view(
    data.buffer,
    data.offsetInBytes,
    data.lengthInBytes,
  );
  await File(path).writeAsBytes(
    opaqueRgb ? _encodeOpaquePng(bytes, image.width, image.height) : bytes,
  );
  image.dispose();
  picture.dispose();
}

/// Encodes opaque RGBA pixels as an RGB PNG. iOS app icons may not contain an
/// alpha channel, even when every alpha value is fully opaque.
Uint8List _encodeOpaquePng(Uint8List rgba, int width, int height) {
  final scanlines = Uint8List((width * 3 + 1) * height);
  var source = 0;
  var target = 0;
  for (var y = 0; y < height; y++) {
    scanlines[target++] = 0; // PNG filter: None.
    for (var x = 0; x < width; x++) {
      scanlines[target++] = rgba[source++];
      scanlines[target++] = rgba[source++];
      scanlines[target++] = rgba[source++];
      source++; // Discard alpha.
    }
  }

  final header = ByteData(13)
    ..setUint32(0, width)
    ..setUint32(4, height)
    ..setUint8(8, 8) // Bit depth.
    ..setUint8(9, 2) // Truecolour, no alpha.
    ..setUint8(10, 0) // Compression.
    ..setUint8(11, 0) // Filter.
    ..setUint8(12, 0); // No interlace.

  final png = BytesBuilder(copy: false)
    ..add(const [137, 80, 78, 71, 13, 10, 26, 10]);
  _addPngChunk(png, 'IHDR', header.buffer.asUint8List());
  _addPngChunk(png, 'IDAT', ZLibEncoder().convert(scanlines));
  _addPngChunk(png, 'IEND', const []);
  return png.takeBytes();
}

void _addPngChunk(BytesBuilder png, String type, List<int> data) {
  final typeBytes = ascii.encode(type);
  _addUint32(png, data.length);
  png
    ..add(typeBytes)
    ..add(data);
  _addUint32(png, _crc32([...typeBytes, ...data]));
}

void _addUint32(BytesBuilder bytes, int value) {
  final data = ByteData(4)..setUint32(0, value);
  bytes.add(data.buffer.asUint8List());
}

int _crc32(List<int> bytes) {
  var crc = 0xffffffff;
  for (final byte in bytes) {
    crc ^= byte;
    for (var bit = 0; bit < 8; bit++) {
      crc = (crc & 1) != 0 ? 0xedb88320 ^ (crc >> 1) : crc >> 1;
    }
  }
  return (crc ^ 0xffffffff) & 0xffffffff;
}
