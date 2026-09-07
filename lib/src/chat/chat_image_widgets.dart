import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Normalize camera/HEIC/gallery inputs to an API-compatible, bounded PNG.
Future<String> prepareChatImage(Uint8List bytes) async {
  if (bytes.length > 25 * 1024 * 1024) {
    throw const FormatException('Choose an image smaller than 25 MB.');
  }
  final descriptor = await ui.ImmutableBuffer.fromUint8List(bytes);
  final imageDescriptor = await ui.ImageDescriptor.encoded(descriptor);
  final longest = imageDescriptor.width > imageDescriptor.height
      ? imageDescriptor.width
      : imageDescriptor.height;
  try {
    var targetLongest = longest.clamp(1, 1600);
    while (true) {
      final scale = targetLongest / longest;
      final codec = await imageDescriptor.instantiateCodec(
        targetWidth: (imageDescriptor.width * scale).round(),
        targetHeight: (imageDescriptor.height * scale).round(),
      );
      try {
        final frame = await codec.getNextFrame();
        try {
          final encoded = await frame.image.toByteData(
            format: ui.ImageByteFormat.png,
          );
          if (encoded == null) {
            throw const FormatException('Could not prepare this image.');
          }
          if (encoded.lengthInBytes <= 4 * 1024 * 1024) {
            return 'data:image/png;base64,${base64Encode(encoded.buffer.asUint8List())}';
          }
          final ratio = math.sqrt((4 * 1024 * 1024) / encoded.lengthInBytes);
          targetLongest = (targetLongest * ratio * 0.9).floor().clamp(
            320,
            targetLongest - 1,
          );
        } finally {
          frame.image.dispose();
        }
      } finally {
        codec.dispose();
      }
      if (targetLongest <= 320) {
        throw const FormatException(
          'Could not reduce this image enough. Choose another image.',
        );
      }
    }
  } finally {
    imageDescriptor.dispose();
    descriptor.dispose();
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
