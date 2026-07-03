import 'dart:io';

import 'package:flutter/material.dart';
import 'package:budget_ai/app/theme/app_theme.dart';
import 'package:budget_ai/features/chat/data/services/remote_file_cache_service.dart';

class ChatResponseScreenshots extends StatelessWidget {
  const ChatResponseScreenshots({
    super.key,
    required this.screenshotUrls,
    required this.authToken,
    required this.onImageTap,
  });

  final List<String> screenshotUrls;
  final String authToken;
  final ValueChanged<String> onImageTap;

  @override
  Widget build(BuildContext context) {
    if (screenshotUrls.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(left: 8, right: 8, top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int i = 0; i < screenshotUrls.length; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            _ScreenshotImage(
              imageUrl: screenshotUrls[i],
              authToken: authToken,
              onTap: onImageTap,
            ),
          ],
        ],
      ),
    );
  }
}

class _ScreenshotImage extends StatelessWidget {
  const _ScreenshotImage({
    required this.imageUrl,
    required this.authToken,
    required this.onTap,
  });

  final String imageUrl;
  final String authToken;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 0),
      child: GestureDetector(
        onTap: () => onTap(imageUrl),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxHeight: 400),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: FutureBuilder<File?>(
                future: RemoteFileCacheService.instance.getOrDownload(
                  url: imageUrl,
                  headers: {'X-API-Key': authToken},
                ),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting &&
                      !snapshot.hasData) {
                    return Container(
                      height: 200,
                      alignment: Alignment.center,
                      child: CircularProgressIndicator(
                        color: theme.colorScheme.primary,
                      ),
                    );
                  }
                  final file = snapshot.data;
                  if (file != null) {
                    return Image.file(
                      file,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) {
                        return _ScreenshotError(theme: theme);
                      },
                    );
                  }
                  return _ScreenshotError(theme: theme);
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ScreenshotError extends StatelessWidget {
  const _ScreenshotError({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.broken_image_outlined,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
            size: 40,
          ),
          const SizedBox(height: 8),
          Text(
            'Could not render screenshot image.',
            style: AppTheme.bodySmall.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
