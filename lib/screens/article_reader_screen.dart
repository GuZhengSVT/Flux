import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/article.dart';
import '../providers/feed_provider.dart';
import '../providers/settings_provider.dart';
import '../theme/flux_theme.dart';
import '../widgets/article_content_view.dart';
import '../widgets/embedded_video_player.dart';
import '../widgets/lazy_network_image.dart';

class ArticleReaderScreen extends ConsumerStatefulWidget {
  const ArticleReaderScreen({
    super.key,
    required this.article,
    required this.feedTitle,
  });

  final Article article;
  final String feedTitle;

  @override
  ConsumerState<ArticleReaderScreen> createState() =>
      _ArticleReaderScreenState();
}

class _ArticleReaderScreenState extends ConsumerState<ArticleReaderScreen> {
  late Article _article;
  bool _fetchingFullText = false;

  @override
  void initState() {
    super.initState();
    _article = widget.article;
    if (!_article.isRead && _article.id != null) {
      // 打开详情页即标记已读；同步更新本地状态，避免 build 中重复触发。
      _article = _article.copyWith(isRead: true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref.read(feedControllerProvider.notifier).markRead(_article, true);
        }
      });
    }
  }

  Future<void> _fetchFullText() async {
    setState(() => _fetchingFullText = true);
    final updated = await ref
        .read(feedControllerProvider.notifier)
        .fetchFullText(_article);
    if (mounted) {
      setState(() {
        _article = updated ?? _article;
        _fetchingFullText = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final controller = ref.read(feedControllerProvider.notifier);
    final contentHtml = _article.contentHtml ?? '';
    final hasRichContent = contentHtml.trim().isNotEmpty;
    final needsFullText =
        _article.link != null &&
        (contentHtml.trim().isEmpty || contentHtml.trim().length < 200);
    final readerFontSize = ref.watch(settingsProvider).readerFontSize;
    final videoUrl = _findVideoUrl(contentHtml);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.feedTitle),
        actions: [
          IconButton(
            tooltip: _article.isFavorite ? '取消收藏' : '收藏',
            icon: Icon(
              _article.isFavorite
                  ? Icons.star_rounded
                  : Icons.star_border_rounded,
              color: _article.isFavorite ? FluxColors.wireGold : null,
            ),
            onPressed: () => controller.toggleFavorite(_article),
          ),
          IconButton(
            tooltip: _article.isReadLater ? '取消稍后读' : '稍后读',
            icon: Icon(
              _article.isReadLater
                  ? Icons.bookmark_rounded
                  : Icons.bookmark_border_rounded,
              color: _article.isReadLater ? FluxColors.red : null,
            ),
            onPressed: () => controller.toggleReadLater(_article),
          ),
          if (_article.link != null)
            IconButton(
              tooltip: '在浏览器打开',
              icon: const Icon(Icons.open_in_new),
              onPressed: () async {
                final uri = Uri.tryParse(_article.link!);
                if (uri != null) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
            ),
        ],
      ),
      body: ColoredBox(
        color: isDark
            ? FluxColors.darkSurface.withValues(alpha: 0.50)
            : FluxColors.bone.withValues(alpha: 0.50),
        child: SelectionArea(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            children: [
              Text(
                _article.title,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Text(
                    widget.feedTitle,
                    style: Theme.of(context).textTheme.labelLarge
                        ?.copyWith(color: FluxColors.red),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    _formatDate(_article.publishedAt ?? _article.fetchedAt),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              if (_article.author != null) ...[
                const SizedBox(height: 4),
                Text(
                  _article.author!,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              SizedBox(
                height: 28,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Container(width: 48, height: 3, color: FluxColors.red),
                ),
              ),
              if (!hasRichContent && _article.imageUrl != null) ...[
                LazyNetworkImage(
                  url: _article.imageUrl!,
                  height: 220,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
                const SizedBox(height: 20),
              ],
              if (videoUrl != null) ...[
                EmbeddedVideoPlayer(
                  url: videoUrl,
                  height: 220,
                  useCache: ref.watch(settingsProvider).autoCacheVideos,
                ),
                const SizedBox(height: 16),
              ],
              if (needsFullText)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: OutlinedButton.icon(
                    onPressed: _fetchingFullText ? null : _fetchFullText,
                    icon: _fetchingFullText
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.auto_stories),
                    label: Text(_fetchingFullText ? '正在抓取全文...' : '抓取全文'),
                  ),
                ),
              if (hasRichContent)
                ArticleContentView(
                  html: contentHtml,
                  baseUrl: _article.link,
                  fontSize: readerFontSize,
                  onOpenLink: (url) async {
                    final uri = Uri.tryParse(url);
                    if (uri != null) {
                      await launchUrl(
                        uri,
                        mode: LaunchMode.externalApplication,
                      );
                    }
                  },
                )
              else if (!needsFullText)
                const Text('该文章没有可显示正文，请打开原文阅读。'),
            ],
          ),
        ),
      ),
    );
  }

  String? _findVideoUrl(String html) {
    if (html.isEmpty) return null;
    final match = RegExp(
      r'https?://[^\s"<>]+\.(mp4|webm|m3u8|mov|avi)[^\s"<>]*',
      caseSensitive: false,
    ).firstMatch(html);
    return match?.group(0);
  }

  String _formatDate(DateTime? date) {
    if (date == null) return '';
    final local = date.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
  }
}
