import 'package:flutter/material.dart';

import '../models/article.dart';
import '../theme/flux_theme.dart';
import 'lazy_network_image.dart';

class ArticleListTile extends StatelessWidget {
  const ArticleListTile({
    super.key,
    required this.article,
    required this.feedTitle,
    required this.onTap,
    required this.onReadToggle,
    required this.onFavoriteToggle,
    this.groupName,
    this.onLongPress,
    this.onSecondaryTap,
    this.showThumbnail = true,
    this.selected = false,
  });

  final Article article;
  final String feedTitle;
  final String? groupName;
  final VoidCallback onTap;
  final VoidCallback onReadToggle;
  final VoidCallback onFavoriteToggle;
  final VoidCallback? onLongPress;
  final void Function(Offset position)? onSecondaryTap;
  final bool showThumbnail;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final isDark = theme.brightness == Brightness.dark;
    final subtitle = article.summary ?? article.contentHtml ?? '';
    final cleanSummary = _stripHtml(subtitle);

    return GestureDetector(
      onSecondaryTapDown: onSecondaryTap == null
          ? null
          : (details) => onSecondaryTap!(details.globalPosition),
      child: Stack(
        children: [
          InkWell(
            onTap: onTap,
            onLongPress: onLongPress,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
              decoration: BoxDecoration(
                color: selected
                    ? FluxColors.red.withValues(alpha: 0.12)
                    : isDark
                    ? FluxColors.darkSurface.withValues(alpha: 0.42)
                    : FluxColors.bone.withValues(alpha: 0.42),
                border: Border(
                  left: BorderSide(
                    color: article.isRead ? Colors.transparent : FluxColors.red,
                    width: 3,
                  ),
                  bottom: BorderSide(color: Theme.of(context).dividerColor),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                article.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: textTheme.titleMedium?.copyWith(
                                  fontWeight: article.isRead
                                      ? FontWeight.w500
                                      : FontWeight.w800,
                                  color: article.isRead
                                      ? Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant
                                      : null,
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: onFavoriteToggle,
                              visualDensity: VisualDensity.compact,
                              tooltip: article.isFavorite ? '取消收藏' : '收藏',
                              icon: Icon(
                                article.isFavorite
                                    ? Icons.star_rounded
                                    : Icons.star_border_rounded,
                                color: article.isFavorite
                                    ? FluxColors.wireGold
                                    : null,
                              ),
                            ),
                          ],
                        ),
                        if (cleanSummary.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            cleanSummary,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            if (article.isReadLater)
                              const Padding(
                                padding: EdgeInsets.only(right: 8),
                                child: Icon(
                                  Icons.bookmark,
                                  size: 14,
                                  color: FluxColors.red,
                                ),
                              ),
                            Text(
                              feedTitle,
                              style: textTheme.labelMedium?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (groupName != null && groupName!.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: FluxColors.red.withValues(
                                      alpha: 0.4,
                                    ),
                                  ),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                                child: Text(
                                  groupName!,
                                  style: textTheme.labelSmall?.copyWith(
                                    color: FluxColors.red,
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(width: 8),
                            Text(
                              _formatDate(
                                article.publishedAt ?? article.fetchedAt,
                              ),
                              style: textTheme.labelMedium?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (showThumbnail && article.imageUrl != null) ...[
                    const SizedBox(width: 12),
                    LazyNetworkImage(
                      url: article.imageUrl!,
                      width: 96,
                      height: 96,
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (!article.isRead)
            const Positioned(
              left: 0,
              top: 0,
              child: CustomPaint(
                size: Size(14, 14),
                painter: _UnreadTrianglePainter(),
              ),
            ),
        ],
      ),
    );
  }

  String _stripHtml(String html) {
    if (html.isEmpty) return '';
    final withoutTags = html.replaceAll(RegExp(r'<[^>]*>'), ' ');
    return withoutTags
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll('&nbsp;', ' ')
        .trim();
  }

  String _formatDate(DateTime? date) {
    if (date == null) return '';
    final local = date.toLocal();
    final now = DateTime.now();
    if (local.year == now.year &&
        local.month == now.month &&
        local.day == now.day) {
      return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    }
    return '${local.month}/${local.day}';
  }
}

class _UnreadTrianglePainter extends CustomPainter {
  const _UnreadTrianglePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = FluxColors.red;
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
