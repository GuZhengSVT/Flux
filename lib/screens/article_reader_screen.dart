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
import 'image_viewer_screen.dart';

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
  final _scrollController = ScrollController();
  double _readingProgress = 0;

  @override
  void initState() {
    super.initState();
    _article = widget.article;
    _scrollController.addListener(_updateReadingProgress);
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

  @override
  void dispose() {
    _scrollController
      ..removeListener(_updateReadingProgress)
      ..dispose();
    super.dispose();
  }

  void _updateReadingProgress() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final max = position.maxScrollExtent;
    final next = max <= 0 ? 0.0 : (position.pixels / max).clamp(0.0, 1.0);
    if ((next - _readingProgress).abs() > 0.01 && mounted) {
      setState(() => _readingProgress = next);
    }
  }

  void _toggleFavorite() {
    final previous = _article;
    final next = !previous.isFavorite;
    setState(() => _article = previous.copyWith(isFavorite: next));
    ref.read(feedControllerProvider.notifier).toggleFavorite(previous);
    _showFeedback(next ? '已收藏' : '已取消收藏');
  }

  void _toggleReadLater() {
    final previous = _article;
    final next = !previous.isReadLater;
    setState(() => _article = previous.copyWith(isReadLater: next));
    ref.read(feedControllerProvider.notifier).toggleReadLater(previous);
    _showFeedback(next ? '已加入稍后读' : '已移出稍后读');
  }

  void _showFeedback(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(milliseconds: 1400),
        ),
      );
  }

  void _openImage(String url) {
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 220),
        reverseTransitionDuration: const Duration(milliseconds: 180),
        pageBuilder: (context, animation, secondaryAnimation) =>
            ImageViewerScreen(url: url),
        transitionsBuilder: (context, animation, secondaryAnimation, child) =>
            FadeTransition(
              opacity: CurvedAnimation(
                parent: animation,
                curve: Curves.easeOut,
              ),
              child: child,
            ),
      ),
    );
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
    final contentHtml = _article.contentHtml ?? '';
    final hasRichContent = contentHtml.trim().isNotEmpty;
    final needsFullText =
        _article.link != null &&
        (contentHtml.trim().isEmpty || contentHtml.trim().length < 200);
    final readerFontSize = ref.watch(settingsProvider).readerFontSize;
    final videoUrl = _findVideoUrl(contentHtml);
    final summary = _plainText(_article.summary ?? '');
    final readingMinutes = _readingMinutes(contentHtml, summary);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.feedTitle),
        actions: [
          IconButton(
            tooltip: _article.isFavorite ? '取消收藏' : '收藏',
            icon: AnimatedSwitcher(
              duration: const Duration(milliseconds: 160),
              transitionBuilder: (child, animation) =>
                  ScaleTransition(scale: animation, child: child),
              child: Icon(
                _article.isFavorite
                    ? Icons.star_rounded
                    : Icons.star_border_rounded,
                key: ValueKey(_article.isFavorite),
                color: _article.isFavorite ? FluxColors.wireGold : null,
              ),
            ),
            onPressed: _toggleFavorite,
          ),
          IconButton(
            tooltip: _article.isReadLater ? '取消稍后读' : '稍后读',
            icon: Icon(
              _article.isReadLater
                  ? Icons.bookmark_rounded
                  : Icons.bookmark_border_rounded,
              color: _article.isReadLater ? FluxColors.red : null,
            ),
            onPressed: _toggleReadLater,
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
      body: Column(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            height: 2,
            alignment: Alignment.centerLeft,
            color: isDark ? FluxColors.darkRaised : FluxColors.newsprint,
            child: FractionallySizedBox(
              widthFactor: _readingProgress,
              child: const ColoredBox(color: FluxColors.red),
            ),
          ),
          Expanded(
            child: ColoredBox(
              color: isDark
                  ? FluxColors.darkSurface.withValues(alpha: 0.50)
                  : FluxColors.bone.withValues(alpha: 0.50),
              child: SelectionArea(
                child: ListView(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 28, 20, 48),
                  children: [
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 760),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              _article.title,
                              style: Theme.of(context).textTheme.headlineMedium
                                  ?.copyWith(height: 1.18, letterSpacing: 0),
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 10,
                              runSpacing: 4,
                              children: [
                                Text(
                                  widget.feedTitle,
                                  style: Theme.of(context).textTheme.labelLarge
                                      ?.copyWith(color: FluxColors.red),
                                ),
                                Text(
                                  _formatDate(
                                    _article.publishedAt ?? _article.fetchedAt,
                                  ),
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                      ),
                                ),
                                if (readingMinutes > 0)
                                  Text(
                                    '约 $readingMinutes 分钟阅读',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant,
                                        ),
                                  ),
                              ],
                            ),
                            if (_article.author != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                _article.author!,
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                              ),
                            ],
                            const SizedBox(height: 16),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Container(
                                width: 48,
                                height: 3,
                                color: FluxColors.red,
                              ),
                            ),
                            if (_article.imageUrl != null) ...[
                              const SizedBox(height: 20),
                              Hero(
                                tag: 'flux-image:${_article.imageUrl}',
                                child: LazyNetworkImage(
                                  url: _article.imageUrl!,
                                  height: 320,
                                  width: double.infinity,
                                  fit: BoxFit.cover,
                                  onTap: () => _openImage(_article.imageUrl!),
                                ),
                              ),
                            ],
                            if (summary.isNotEmpty) ...[
                              const SizedBox(height: 20),
                              Container(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  12,
                                  16,
                                  12,
                                ),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? FluxColors.darkRaised
                                      : FluxColors.newsprint,
                                  border: const Border(
                                    left: BorderSide(
                                      color: FluxColors.red,
                                      width: 3,
                                    ),
                                  ),
                                ),
                                child: Text(
                                  summary,
                                  style: Theme.of(context).textTheme.bodyLarge
                                      ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                        fontStyle: FontStyle.italic,
                                      ),
                                ),
                              ),
                            ],
                            if (videoUrl != null) ...[
                              const SizedBox(height: 20),
                              EmbeddedVideoPlayer(
                                url: videoUrl,
                                height: 220,
                                useCache: ref
                                    .watch(settingsProvider)
                                    .autoCacheVideos,
                              ),
                            ],
                            if (needsFullText)
                              Padding(
                                padding: const EdgeInsets.only(top: 20),
                                child: OutlinedButton.icon(
                                  onPressed: _fetchingFullText
                                      ? null
                                      : _fetchFullText,
                                  icon: _fetchingFullText
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.auto_stories),
                                  label: Text(
                                    _fetchingFullText ? '正在抓取全文...' : '抓取全文',
                                  ),
                                ),
                              ),
                            const SizedBox(height: 20),
                            if (hasRichContent)
                              ArticleContentView(
                                html: contentHtml,
                                baseUrl: _article.link,
                                fontSize: readerFontSize,
                                onOpenImage: _openImage,
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
                  ],
                ),
              ),
            ),
          ),
        ],
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

  String _plainText(String value) {
    return value
        .replaceAll(RegExp(r'<[^>]*>'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll('&nbsp;', ' ')
        .trim();
  }

  int _readingMinutes(String html, String summary) {
    final text = _plainText(html);
    final count = text.isEmpty ? summary.length : text.length;
    if (count == 0) return 0;
    return (count / 450).ceil().clamp(1, 99);
  }
}
