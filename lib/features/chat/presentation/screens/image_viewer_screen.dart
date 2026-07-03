import 'dart:io';

import 'package:flutter/material.dart';
import 'package:budget_ai/app/theme/app_theme.dart';
import 'package:budget_ai/features/chat/data/services/remote_file_cache_service.dart';

class ImagePreviewScreen extends StatelessWidget {
  final String? imageUrl;
  final String? filePath;
  final Map<String, String>? headers;
  final String title;

  const ImagePreviewScreen.network({
    super.key,
    required this.imageUrl,
    this.headers,
    this.title = 'Image Preview',
  }) : filePath = null;

  const ImagePreviewScreen.file({
    super.key,
    required this.filePath,
    this.title = 'Image Preview',
  }) : imageUrl = null,
       headers = null;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black.withValues(alpha: 0.7),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          title,
          style: AppTheme.bodyMedium.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
      ),
      body: InteractiveViewer(
        maxScale: 10,
        child: Center(
          child: filePath != null
              ? Image.file(
                  File(filePath!),
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) {
                    return _buildError(context);
                  },
                )
              : FutureBuilder<File>(
                  future: RemoteFileCacheService.instance.getOrDownload(
                    url: imageUrl!,
                    headers: headers,
                  ),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting &&
                        !snapshot.hasData) {
                      return const Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      );
                    }
                    final file = snapshot.data;
                    if (file != null) {
                      return Image.file(
                        file,
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) {
                          return _buildError(context);
                        },
                      );
                    }
                    return _buildError(context);
                  },
                ),
        ),
      ),
    );
  }

  Widget _buildError(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.broken_image_outlined,
          color: Colors.white70,
          size: 64,
        ),
        const SizedBox(height: 16),
        Text(
          'Could not load image.',
          style: AppTheme.bodyMedium.copyWith(color: Colors.white70),
        ),
      ],
    );
  }
}
