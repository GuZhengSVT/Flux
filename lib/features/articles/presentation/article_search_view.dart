// 检索结果视图（T022）。
//
// 复用卡片的**内容区**（[ArticleCardBody]）而不是另画一套结果行：卡片已经处理好了
// 「三态控件独立于收藏」「缺图不占位」「大字号不截断操作控件」这些细节，另画一套必然
// 会漏掉其中几条，而且两处的视觉会慢慢漂移。
//
// 与浏览列表的差异只有两处，都是**可解释的**：
//   1) 卡片下方多一条命中片段（带高亮）——这正是「检索结果」与「列表」的区别；
//   2) 结果按相关性排序（MATCH 路径），因此**不显示分页底栏**里的「已加载 N / M」那种
//      浏览语义，只显示命中总数。
//
// 空态分三种（架构第 7 节要求状态可区分）：还没搜、无结果、失败。三者的下一步动作
// 完全不同（输入关键词 / 换关键词 / 重试），因此不能共用一句文案。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flux/core/core.dart';
import 'package:flux/core/design/design_tokens.dart';
import 'package:flux/l10n/l10n.dart';
import 'package:flux/ui/ui.dart';

import '../application/article_search_state.dart';
import '../application/article_search_use_case.dart';
import '../application/article_card_view.dart';
import 'article_card.dart';
import 'article_detail_page.dart';
import 'article_list_controller.dart';
import 'reader/reader_chrome.dart';
import 'reader/search_snippet_view.dart';

/// 检索结果视图。
class ArticleSearchView extends ConsumerWidget {
  /// 构造视图。
  const ArticleSearchView({required this.state, super.key});

  /// 检索状态。
  final ArticleSearchState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    if (state.error case final AppError error) {
      return FluxEmptyState(
        icon: FluxIcon.alertError,
        title: l10n.searchFailed(error.message),
        body: l10n.searchEmptyBody,
        action: FilledButton(
          onPressed: () => ref.read(searchControllerProvider.notifier).run(),
          child: Text(l10n.searchRetry),
        ),
      );
    }

    if (state.isIdle) {
      return FluxEmptyState(
        icon: FluxIcon.inboxEmpty,
        title: l10n.searchIdleTitle,
        body: l10n.searchIdleBody,
      );
    }

    if (state.isEmptyResult) {
      return FluxEmptyState(
        icon: FluxIcon.inboxEmpty,
        title: l10n.searchEmptyTitle,
        body: l10n.searchEmptyBody,
        tone: EmptyStateTone.muted,
      );
    }

    final ArticleCardViewMode mode =
        ref.watch(cardViewModeProvider).value ?? ArticleCardViewMode.normal;

    return Column(
      children: <Widget>[
        _SearchResultHeader(total: state.total, loading: state.loading),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(FluxSpacing.md),
            itemCount: state.results.length,
            itemBuilder: (BuildContext context, int index) {
              final ArticleSearchResult result = state.results[index];
              return Padding(
                padding: EdgeInsets.only(
                  bottom: index == state.results.length - 1
                      ? 0
                      : FluxSpacing.xs,
                ),
                child: _SearchResultCard(result: result, mode: mode),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// 结果头：命中数与加载指示。
class _SearchResultHeader extends StatelessWidget {
  const _SearchResultHeader({required this.total, required this.loading});

  final int total;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: FluxSpacing.md,
        vertical: FluxSpacing.xxs,
      ),
      child: Row(
        children: <Widget>[
          if (loading) ...<Widget>[
            const FluxLoadingIndicator(size: 14),
            const SizedBox(width: FluxSpacing.xxs),
          ],
          Text(
            AppLocalizations.of(context).searchResultsCount(total),
            style: theme.textTheme.labelSmall,
          ),
        ],
      ),
    );
  }
}

/// 一条检索结果：卡片内容 + 命中片段。
class _SearchResultCard extends ConsumerWidget {
  const _SearchResultCard({required this.result, required this.mode});

  final ArticleSearchResult result;
  final ArticleCardViewMode mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ArticleListEntry entry = result.entry;
    return FluxCard(
      onTap: () => _open(context),
      semanticsLabel: entry.title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          ArticleCardBody(
            entry: entry,
            mode: mode,
            metaLine: _metaLine(l10n),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                ReadingStateControl(
                  state: entry.readingState,
                  size: FluxIconSize.small,
                  // 检索结果里只读：三态由列表页负责切换，这里是「找到并打开」的入口。
                  // 让它可改会引入「改完之后这一条还符不符合当前筛选」的即时重排问题。
                  onChanged: null,
                ),
                FavoriteToggle(
                  favorite: entry.favorite,
                  size: FluxIconSize.small,
                  onChanged: null,
                ),
              ],
            ),
          ),
          if (result.hit.snippets.isNotEmpty) ...<Widget>[
            const SizedBox(height: FluxSpacing.xxs),
            SearchSnippetView(snippets: result.hit.snippets),
          ],
        ],
      ),
    );
  }

  /// 元信息行（与列表卡片同一规则，含「已脱离订阅」标注）。
  String _metaLine(AppLocalizations l10n) {
    final String time = result.entry.publishedAtMissing
        ? l10n.readingPublishedUnknown
        : formatLocalTime(result.entry.effectiveTime);
    if (result.entry.detachedFromFeed) {
      return '${result.entry.feedName}（${l10n.detachedFeedLabel}） · $time';
    }
    return '${result.entry.feedName} · $time';
  }

  Future<void> _open(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => ArticleDetailPage(
          articleId: result.articleId,
          initialTitle: result.entry.title,
        ),
      ),
    );
  }
}
