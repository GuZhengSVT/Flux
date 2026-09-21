// 文章正文占位页（T017 范围内的**最简**实现）。
//
// 范围边界（架构第 3 节把正文阅读产品化列为 T019）：
//   本页只做三件事：显示标题 + 显示纯文本正文 + 提供关闭。
//   目录、上下篇、页内查找、代码高亮、公式渲染、滚动锚点恢复全部属 T019，本页
//   **不假装**它们存在（页面里有一条明确的范围说明，而不是一个看起来完整的阅读器）。
//
// 本页唯一不属于「占位」的职责是 SET-010 的自动标已读：打开正文且当前为 unread
// 时改成 read。这是 T017 的产品规则，因此它必须在这里真实生效，而不是等 T019。
// later 打开后仍为 later（用例层与 SQL 条件共同保证）。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flux/core/core.dart';
import 'package:flux/core/design/design_tokens.dart';
import 'package:flux/l10n/l10n.dart';
import 'package:flux/ui/ui.dart';

import '../application/article_ports.dart';
import '../application/article_state.dart';
import 'article_list_controller.dart';

/// 正文占位页。
class ArticleDetailPage extends ConsumerStatefulWidget {
  /// 构造页面。
  const ArticleDetailPage({
    required this.articleId,
    super.key,
    this.initialTitle,
  });

  /// 文章 id。
  final int articleId;

  /// 列表已有的标题（先渲染出来，避免打开瞬间出现一块空白）。
  final String? initialTitle;

  @override
  ConsumerState<ArticleDetailPage> createState() => _ArticleDetailPageState();
}

class _ArticleDetailPageState extends ConsumerState<ArticleDetailPage> {
  ArticleListEntry? _entry;
  String? _body;
  AppError? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    // 打开即读取并触发 SET-010 的自动标已读。
    //
    // 为什么在 initState 里而不是 build 里：build 可能被调用多次（主题变化、
    // 语言切换），在 build 里做写入会重复触发——虽然条件写让重复是幂等的，
    // 但「渲染触发写入」是应当避免的结构。
    unawaited(_load());
  }

  Future<void> _load() async {
    final ArticleCatalogStore store = ref.read(articleCatalogProvider);
    final Result<ArticleListEntry?> found = await store.findArticle(
      widget.articleId,
    );
    if (!mounted) {
      return;
    }
    if (found.isErr) {
      setState(() {
        _error = found.errorOrNull;
        _loading = false;
      });
      return;
    }
    final ArticleListEntry? entry = found.valueOrNull;
    final Result<String?> body = entry == null
        ? const Ok<String?>(null)
        : await store.readArticleBody(entry.id);
    if (!mounted) {
      return;
    }
    setState(() {
      _entry = entry;
      _body = body.valueOrNull;
      _loading = false;
    });

    if (entry == null) {
      return;
    }

    // SET-010：成功显示正文后，unread → read；later 与 read 不动。
    final bool autoMark = await ref.read(autoMarkReadProvider.future);
    if (!mounted) {
      return;
    }
    final Result<ArticleStateChange> change = await MarkReadOnOpenUseCase(
      articles: store,
    )(articleId: widget.articleId, autoMarkEnabled: autoMark);
    if (!mounted || change.isErr) {
      return;
    }
    if (change.unwrap().changed) {
      // 列表面向「未读」筛选，因此状态变化后需要重读，让刚才那行从筛选结果里退出。
      // 返回时列表就是一致的，不需要等用户下拉刷新。
      await ref.read(articleListControllerProvider.notifier).reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _entry?.title ?? widget.initialTitle ?? l10n.readingOpenArticle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        leading: IconButton(
          tooltip: l10n.subscriptionClose,
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(FluxSpacing.lg),
              children: <Widget>[
                if (_error case final AppError error)
                  StatusBanner(
                    severity: StatusBannerSeverity.error,
                    message: l10n.readingActionError(error.message),
                  ),
                if (_entry case final ArticleListEntry entry) ...<Widget>[
                  Text(entry.title, style: theme.textTheme.headlineSmall),
                  const SizedBox(height: FluxSpacing.xs),
                  Text(
                    _metaLine(l10n, entry),
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: FluxSpacing.md),
                  Row(
                    children: <Widget>[
                      ReadingStateControl(
                        state: entry.readingState,
                        onChanged: _setState,
                        size: FluxIconSize.small,
                      ),
                      const SizedBox(width: FluxSpacing.xs),
                      FavoriteToggle(
                        favorite: entry.favorite,
                        onChanged: (bool _) => _toggleFavorite(),
                        size: FluxIconSize.small,
                      ),
                    ],
                  ),
                  const Divider(height: FluxSpacing.lg),
                ],
                // 范围说明放在正文之前：让「这不是最终阅读器」这件事在最前面被看到，
                // 而不是让用户读完正文才发现没有目录。
                StatusBanner(
                  severity: StatusBannerSeverity.info,
                  message: l10n.readingDetailPlaceholderNotice,
                ),
                const SizedBox(height: FluxSpacing.md),
                if (_body case final String body)
                  SelectableText(body, style: theme.textTheme.bodyMedium)
                else
                  Text(
                    l10n.readingDetailNoBody,
                    style: theme.textTheme.bodyMedium,
                  ),
              ],
            ),
    );
  }

  /// 元信息行：来源 + 时间（发布时间缺失时明确注明）。
  String _metaLine(AppLocalizations l10n, ArticleListEntry entry) {
    final String time = entry.publishedAtMissing
        ? l10n.readingPublishedUnknown
        : formatLocalTime(entry.effectiveTime);
    return '${entry.feedName} · $time';
  }

  /// 单行三态切换。
  Future<void> _setState(ReadingState next) async {
    final Result<ArticleStateChange> result = await SetReadingStateUseCase(
      articles: ref.read(articleCatalogProvider),
    )(articleId: widget.articleId, state: next);
    if (!mounted) {
      return;
    }
    if (result.isErr) {
      setState(() => _error = result.errorOrNull);
      return;
    }
    setState(() => _error = null);
    await _reloadEntry();
  }

  /// 单行收藏切换。
  Future<void> _toggleFavorite() async {
    final Result<ArticleStateChange> result = await ToggleFavoriteUseCase(
      articles: ref.read(articleCatalogProvider),
    ).toggle(widget.articleId);
    if (!mounted) {
      return;
    }
    if (result.isErr) {
      setState(() => _error = result.errorOrNull);
      return;
    }
    setState(() => _error = null);
    await _reloadEntry();
  }

  /// 重读本页的条目（状态改动后）。
  Future<void> _reloadEntry() async {
    final Result<ArticleListEntry?> found = await ref
        .read(articleCatalogProvider)
        .findArticle(widget.articleId);
    if (!mounted || found.isErr) {
      return;
    }
    setState(() => _entry = found.valueOrNull);
    await ref.read(articleListControllerProvider.notifier).reload();
  }
}

/// 本地时间格式（不引入 intl 的 DateFormat：这里只需要一种固定形态）。
String formatLocalTime(DateTime utc) {
  final DateTime local = utc.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  final String date = '${local.year}-${two(local.month)}-${two(local.day)}';
  return '$date ${two(local.hour)}:${two(local.minute)}';
}
