import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../services/media_cache.dart';
import '../theme/flux_theme.dart';

/// 针对大量图片场景的懒加载图片。
///
/// - 使用 `CachedNetworkImage`，磁盘缓存默认 7 天，超过上限按 LRU 清理。
/// - 只在 Widget 被列表构建时才开始请求（Flutter 虚拟化列表已保证可视区构建）。
/// - 使用 [memCacheWidth] / [memCacheHeight] 按显示尺寸解码，降低内存占用。
/// - 失败时显示几何占位块，不影响列表滚动。
class LazyNetworkImage extends StatelessWidget {
  const LazyNetworkImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius = const BorderRadius.all(Radius.circular(2)),
  });

  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final imageUrl = url.trim();
    if (imageUrl.isEmpty) {
      return _Placeholder(
        width: width,
        height: height,
        borderRadius: borderRadius,
      );
    }

    final memCacheWidth = (width != null && width!.isFinite && width! > 0)
        ? (width! * dpr).round()
        : null;
    final memCacheHeight = (height != null && height!.isFinite && height! > 0)
        ? (height! * dpr).round()
        : null;

    return ClipRRect(
      borderRadius: borderRadius,
      child: CachedNetworkImage(
        imageUrl: imageUrl,
        cacheManager: MediaCache.instance.images,
        width: width,
        height: height,
        fit: fit,
        memCacheWidth: memCacheWidth,
        memCacheHeight: memCacheHeight,
        filterQuality: FilterQuality.medium,
        placeholder: (context, url) => _Placeholder(
          width: width,
          height: height,
          borderRadius: borderRadius,
        ),
        errorWidget: (context, url, error) => _Placeholder(
          width: width,
          height: height,
          borderRadius: borderRadius,
        ),
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({this.width, this.height, required this.borderRadius});

  final double? width;
  final double? height;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = isDark ? FluxColors.darkRaised : FluxColors.newsprint;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(color: color, borderRadius: borderRadius),
      child: CustomPaint(painter: _DiagonalPainter(color: FluxColors.red)),
    );
  }
}

class _DiagonalPainter extends CustomPainter {
  _DiagonalPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.35)
      ..strokeWidth = 2;
    for (double x = -size.height; x < size.width; x += 28) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(x + size.height, size.height),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
