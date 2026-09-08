import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Decode native photo formats once, then send a metadata-free bounded image.
Future<String> prepareChatImage(Uint8List bytes) async {
  if (bytes.length > 25 * 1024 * 1024) {
    throw const FormatException('Choose an image smaller than 25 MB.');
  }
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  ui.ImageDescriptor? descriptor;
  try {
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    final scale = math.min(
      1.0,
      1600 / math.max(descriptor.width, descriptor.height),
    );
    final codec = await descriptor.instantiateCodec(
      targetWidth: math.max(1, (descriptor.width * scale).round()),
      targetHeight: math.max(1, (descriptor.height * scale).round()),
    );
    try {
      final frame = await codec.getNextFrame();
      try {
        final png = await frame.image.toByteData(
          format: ui.ImageByteFormat.png,
        );
        if (png == null) {
          throw const FormatException('Could not prepare this image.');
        }
        if (png.lengthInBytes <= 384 * 1024) {
          return 'data:image/png;base64,${base64Encode(png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes))}';
        }
        final raw = await frame.image.toByteData(
          format: ui.ImageByteFormat.rawStraightRgba,
        );
        if (raw == null) {
          throw const FormatException('Could not prepare this photo.');
        }
        return compute(_encodePhoto, (
          raw.buffer.asUint8List(raw.offsetInBytes, raw.lengthInBytes),
          frame.image.width,
          frame.image.height,
        ));
      } finally {
        frame.image.dispose();
      }
    } finally {
      codec.dispose();
    }
  } finally {
    descriptor?.dispose();
    buffer.dispose();
  }
}

String _encodePhoto((Uint8List, int, int) data) {
  final (bytes, width, height) = data;
  var photo = img.Image(width: width, height: height, numChannels: 3);
  // Flatten transparency onto white without retaining EXIF/GPS metadata.
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final offset = (y * width + x) * 4;
      final alpha = bytes[offset + 3] / 255;
      photo.setPixelRgb(
        x,
        y,
        (bytes[offset] * alpha + 255 * (1 - alpha)).round(),
        (bytes[offset + 1] * alpha + 255 * (1 - alpha)).round(),
        (bytes[offset + 2] * alpha + 255 * (1 - alpha)).round(),
      );
    }
  }
  while (true) {
    for (final quality in [85, 75, 65]) {
      final encoded = img.encodeJpg(photo, quality: quality);
      if (encoded.length <= 768 * 1024) {
        return 'data:image/jpeg;base64,${base64Encode(encoded)}';
      }
    }
    if (math.max(photo.width, photo.height) <= 320) {
      throw const FormatException('Could not prepare this photo for upload.');
    }
    photo = img.copyResize(
      photo,
      width: math.max(1, (photo.width * 0.8).round()),
      height: math.max(1, (photo.height * 0.8).round()),
    );
  }
}

class ChatImageStrip extends StatelessWidget {
  const ChatImageStrip({super.key, required this.images, this.onRemove});
  final List<String> images;
  final ValueChanged<int>? onRemove;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: SizedBox(
      width:
          images.length * (onRemove == null ? 72.0 : 64.0) +
          (images.length - 1) * 8,
      height: onRemove == null ? 72 : 64,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: images.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) => Stack(
          children: [
            SizedBox(
              width: onRemove == null ? 72 : 64,
              height: onRemove == null ? 72 : 64,
              child: ChatImageView(dataUrl: images[index], thumbnail: true),
            ),
            if (onRemove != null)
              Positioned(
                top: 0,
                right: 0,
                child: IconButton.filled(
                  tooltip: 'Remove image ${index + 1}',
                  onPressed: () => onRemove!(index),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black54,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(32, 32),
                    maximumSize: const Size(32, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    padding: EdgeInsets.zero,
                  ),
                  icon: const Icon(Icons.close, size: 18),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

class ChatImageView extends StatefulWidget {
  const ChatImageView({
    super.key,
    required this.dataUrl,
    this.thumbnail = false,
  });
  final String dataUrl;
  final bool thumbnail;

  @override
  State<ChatImageView> createState() => _ChatImageViewState();
}

class _ChatImageViewState extends State<ChatImageView> {
  Uint8List? _bytes;
  @override
  void initState() {
    super.initState();
    _decode();
  }

  @override
  void didUpdateWidget(ChatImageView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dataUrl != widget.dataUrl) _decode();
  }

  void _decode() {
    try {
      _bytes = Uri.parse(widget.dataUrl).data?.contentAsBytes();
    } catch (_) {
      _bytes = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    if (bytes == null) return const Text('Image unavailable');
    return Semantics(
      button: true,
      label: 'View attached image',
      child: GestureDetector(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (context) => Scaffold(
              appBar: AppBar(title: const Text('Image')),
              body: Center(
                child: InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 5,
                  child: Image.memory(
                    bytes,
                    errorBuilder: (_, _, _) => const Text('Image unavailable'),
                  ),
                ),
              ),
            ),
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Image.memory(
            bytes,
            fit: widget.thumbnail ? BoxFit.cover : BoxFit.contain,
            cacheWidth: widget.thumbnail ? 288 : 1024,
            errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined),
          ),
        ),
      ),
    );
  }
}
