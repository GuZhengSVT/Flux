// 文章列表的读模型与筛选/分页状态（T017）。
//
// 为什么把「筛选 + 已加载批数」做成一个不可变值对象而不是页面里的两个变量：
// 它们必须**同时**变化才有意义（换筛选就要回到第 1 批；继续加载要保持筛选）。分成两个
// 独立变量时，任何一处忘记同步都会让用户看到「未读筛选的第 3 批」这种不存在的组合。
//
// 用**偏移量**而不是游标：架构 4.1 要求「列表分页/虚拟化」，偏移量足以满足，而游标
// 需要一套稳定的排序键编解码；这里的排序已经有 id 兜底稳定，不需要额外机制。
//
// T019+ 把「翻页」改成「按批加载」（架构 4.1 的「列表分页/虚拟化」在桌面滚动阅读下的
// 实际形态）：列表是一个**连续滚动**的面板，而不是一页页翻。用户滚到底就要看到下一批，
// 而不是先找到「下一页」按钮。因此状态里留下的是「已经加载了几批」，而不是「当前第几页」
// ——这两件事在界面上不同：前者没有「最后一页」这个会让人以为内容到此为止的东西。
library;

import 'package:flux/core/core.dart';

/// 列表状态（筛选 + 页偏移 + 分页大小）。
class ArticleListState {
  /// 构造状态。
  const ArticleListState({
    this.filter = ArticleFilter.all,
    this.feedId,
    this.batchSize = defaultBatchSize,
    this.loadedBatches = 1,
  }) : assert(batchSize > 0, '每批数量必须为正'),
       assert(loadedBatches >= 1, '至少要加载第一批');

  /// 每批条数。
  ///
  /// 100 而不是 50：列表一屏大约能看到 8–12 张卡片，50 条在快速滚动时会在两屏之内
  /// 用完，于是「滚动到底加载下一批」变成一次连续的等待。100 条给用户一段连续的滚动，
  /// 同时不至于让一次查询把整库读进内存。
  static const int defaultBatchSize = 100;

  /// 当前筛选。
  final ArticleFilter filter;

  /// 来源限定；null 表示全部来源。
  final int? feedId;

  /// 每批数量。
  final int batchSize;

  /// 当前已加载的批数（从 1 开始：第一批总是随首屏加载）。
  final int loadedBatches;

  /// 当前已加载条数上限（作为分页窗口的 limit）。
  int get loadedLimit => batchSize * loadedBatches;

  /// 对应到存储层的查询。
  ArticleQuery get query => ArticleQuery(
    filter: filter,
    feedId: feedId,
    // 从 0 开始一次读「已加载的这批窗口」：连续滚动下用户是在一个列表里往回看，
    // 而不是在翻页。分批只影响**什么时候**多读一段，不影响已经看到的内容顺序。
    offset: 0,
    limit: loadedLimit,
  );

  /// 换筛选（并**重置到第一批**）。
  ///
  /// 不重置时用户会看到一个「未读筛选、已经滚到第 8 批」的组合：那 8 批里有 7 批
  /// 属于上一次筛选，而界面看起来只是列表。重置是唯一能让「看到的」与「筛选」一致的
  /// 做法。
  ArticleListState withFilter(ArticleFilter next) =>
      ArticleListState(filter: next, feedId: feedId, batchSize: batchSize);

  /// 换来源限定（并重置到第一批，理由同上）。
  ArticleListState withFeed(int? nextFeedId) => ArticleListState(
    filter: filter,
    feedId: nextFeedId,
    batchSize: batchSize,
  );

  /// 多加载一批。
  ///
  /// 只在还有未加载内容时有意义；调用方负责按 [hasMore] 判断，因为「是否还有更多」
  /// 需要总数，而总数只有读完之后才知道。
  ArticleListState loadMoreBatch() {
    return ArticleListState(
      filter: filter,
      feedId: feedId,
      batchSize: batchSize,
      loadedBatches: loadedBatches + 1,
    );
  }

  /// 是否还有未加载的文章（供界面决定「加载更多」是否可用、滚动到底是否继续加载）。
  bool hasMore(int total) => loadedLimit < total;
}

/// 三种批量范围里「当前筛选结果」对应的查询条件。
ArticleListState scopedForFilter(ArticleListState state) => state;
