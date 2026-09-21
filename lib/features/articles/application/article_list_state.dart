// 文章列表的读模型与筛选/分页状态（T017）。
//
// 为什么把「筛选 + 页码」做成一个不可变值对象而不是页面里的两个变量：
// 它们必须**同时**变化才有意义（换筛选就要回到第 1 页；翻页要保持筛选）。分成两个
// 独立变量时，任何一处忘记同步都会让用户看到「未读筛选的第 3 页」这种不存在的组合。
// 把两条规则收进 [ArticleListState.copyWith] 之后，「换筛选重置页码」成为唯一路径。
//
// 分页用**偏移量**而不是游标：架构 4.1 要求「列表分页/虚拟化」，偏移量足以满足，
// 而游标需要一套稳定的排序键编解码；这里的排序已经有 id 兜底稳定，不需要额外机制。
library;

import 'package:flux/core/core.dart';

/// 列表状态（筛选 + 页偏移 + 分页大小）。
class ArticleListState {
  /// 构造状态。
  const ArticleListState({
    this.filter = ArticleFilter.all,
    this.feedId,
    this.page = 0,
    this.pageSize = 50,
  }) : assert(page >= 0, '页码不能为负'),
       assert(pageSize > 0, '每页数量必须为正');

  /// 当前筛选。
  final ArticleFilter filter;

  /// 来源限定；null 表示全部来源。
  final int? feedId;

  /// 页号（从 0 开始）。
  final int page;

  /// 每页数量。
  final int pageSize;

  /// 对应到存储层的查询。
  ArticleQuery get query => ArticleQuery(
    filter: filter,
    feedId: feedId,
    offset: page * pageSize,
    limit: pageSize,
  );

  /// 换筛选（并**重置页码**）。
  ///
  /// 重置页码范围到第 3 页时会直接显示空列表（新筛选没有那么多页），用户会以为
  /// 筛选坏了。
  ArticleListState withFilter(ArticleFilter next) =>
      ArticleListState(filter: next, feedId: feedId, pageSize: pageSize);

  /// 换来源限定（并重置页码，理由同上）。
  ArticleListState withFeed(int? nextFeedId) =>
      ArticleListState(filter: filter, feedId: nextFeedId, pageSize: pageSize);

  /// 翻到指定页；越界时收敛到合法范围。
  ArticleListState atPage(int nextPage, {required int total}) {
    final int lastPage = pageCount(total) - 1;
    final int clamped = nextPage.clamp(0, lastPage < 0 ? 0 : lastPage);
    return ArticleListState(
      filter: filter,
      feedId: feedId,
      page: clamped,
      pageSize: pageSize,
    );
  }

  /// 给定总数时的页数（至少 1 页，让空列表也有一个合法的第 0 页）。
  int pageCount(int total) {
    if (total <= 0) {
      return 1;
    }
    return (total + pageSize - 1) ~/ pageSize;
  }

  /// 是否有上一页（供界面禁用按钮，而不是让用户点到一个空页）。
  bool get hasPrevious => page > 0;

  /// 是否有下一页。
  bool hasNext(int total) => page + 1 < pageCount(total);
}

/// 三种批量范围里「当前筛选结果」对应的查询条件。
ArticleListState scopedForFilter(ArticleListState state) => state;
