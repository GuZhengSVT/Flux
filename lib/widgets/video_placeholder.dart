import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/flux_theme.dart';

/// 视频占位。
///
/// 第一版为了流畅度，不在列表里初始化播放器；
/// 点击后调用系统/外部播放器打开视频地址。
/// 后续版本可替换为内嵌 media_kit 播放器，此组件保持接口不变。
class VideoPlaceholder extends StatelessWidget {
  const VideoPlaceholder({
    super.key,
    required this.url,
    this.title = '视频',
    this.width,
    this.height,
    this.onTap,
  });

  final String url;
  final String title;
  final double? width;
  final double? height;
  final VoidCallback? onTap;

  Future<void> _open() async {
    final uri = Uri.tryParse(url);
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? FluxColors.darkRaised : const Color(0xFFE5E0D6);
    return InkWell(
      onTap: onTap ?? _open,
      borderRadius: BorderRadius.circular(2),
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(2),
          border: Border.all(color: FluxColors.red.withValues(alpha: 0.6)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.play_circle_fill, color: FluxColors.red, size: 48),
            const SizedBox(height: 4),
            Text(
              title,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: isDark ? FluxColors.darkText : FluxColors.black,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
