import 'package:flutter/material.dart';

import '../theme/flux_theme.dart';
import '../widgets/lazy_network_image.dart';

/// 全屏图片查看器。阅读器中的图片都可以进入这里进行缩放查看。
class ImageViewerScreen extends StatelessWidget {
  const ImageViewerScreen({super.key, required this.url, this.caption});

  final String url;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? FluxColors.darkBg : Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: const Text('图片预览'),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) => InteractiveViewer(
          minScale: 0.5,
          maxScale: 4,
          child: Center(
            child: Hero(
              tag: 'flux-image:$url',
              child: SizedBox(
                width: constraints.maxWidth,
                height: constraints.maxHeight,
                child: LazyNetworkImage(
                  url: url,
                  width: constraints.maxWidth,
                  height: constraints.maxHeight,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: caption == null || caption!.trim().isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: Text(
                  caption!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70),
                ),
              ),
            ),
    );
  }
}
