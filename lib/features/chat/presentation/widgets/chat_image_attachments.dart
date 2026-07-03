import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class ChatImageThumbnail extends StatelessWidget {
  final String path;
  final double size;

  const ChatImageThumbnail({super.key, required this.path, required this.size});

  @override
  Widget build(BuildContext context) {
    if (_isSvgPath(path)) {
      return Container(
        width: size,
        height: size,
        color: const Color(0xFFF4F4EE),
        child: Center(
          child: SvgPicture.file(
            File(path),
            width: size * 0.56,
            height: size * 0.56,
            placeholderBuilder: (context) => const SizedBox.shrink(),
          ),
        ),
      );
    }

    return Image.file(
      File(path),
      width: size,
      height: size,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) {
        return Container(
          width: size,
          height: size,
          color: const Color(0xFFF4F4EE),
          alignment: Alignment.center,
          child: Icon(
            Icons.broken_image_outlined,
            size: size * 0.42,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        );
      },
    );
  }

  bool _isSvgPath(String path) {
    return _fileExtension(path) == 'svg';
  }

  String _fileExtension(String fileName) {
    final dotIndex = fileName.lastIndexOf('.');
    if (dotIndex < 0 || dotIndex == fileName.length - 1) {
      return '';
    }
    return fileName.substring(dotIndex + 1).toLowerCase();
  }
}

class AttachedImagesPreview extends StatelessWidget {
  final List<String> imagePaths;
  final ValueChanged<int> onRemoveImage;
  final ValueChanged<String>? onTapImage;

  const AttachedImagesPreview({
    super.key,
    required this.imagePaths,
    required this.onRemoveImage,
    this.onTapImage,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final borderColor = theme.colorScheme.outline;

    return Container(
      height: 48,
      margin: const EdgeInsets.only(top: 8),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: imagePaths.length,
        itemBuilder: (context, index) {
          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Stack(
              children: [
                GestureDetector(
                  onTap: onTapImage != null
                      ? () => onTapImage!(imagePaths[index])
                      : null,
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: borderColor.withValues(alpha: 0.3),
                        width: 1,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(11),
                      child: ChatImageThumbnail(
                        path: imagePaths[index],
                        size: 48,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 2,
                  right: 2,
                  child: GestureDetector(
                    onTap: () => onRemoveImage(index),
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: Colors.red.shade400,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: theme.colorScheme.surface,
                          width: 1,
                        ),
                      ),
                      child: Icon(
                        Icons.close,
                        size: 12,
                        color: theme.colorScheme.onError,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
