// 数据库不可用时的文章阅读端口（T017 的降级启动路径）。
//
// 与 [DegradedFeedCatalogStore] 同一口径：**读返回空集合 + 写返回类型化失败**。
//
// 为什么读不抛异常而是返回空：数据库打不开是可诊断的正常状态（架构第 8 节要求明确
// 告知而不是崩溃），阅读页应当像其他页面一样显示空态 + 顶部横幅「本次运行不保存
// 改动」，而不是红屏。
//
// 为什么写不返回成功：那会让用户以为状态改好了，重启后消失且没有任何线索——正是
// 架构第 8 节禁止的「用假象代替状态」。
library;

import 'package:flux/core/core.dart';

/// 降级实现。
final class DegradedArticleCatalogStore implements ArticleCatalogStore {
  /// 构造降级实现。
  const DegradedArticleCatalogStore();

  @override
  Future<Result<ArticlePage>> listArticles(ArticleQuery query) async => Err(
    StorageError(operation: 'listArticles', detail: '本次运行数据库不可用，文章列表读不到'),
  );

  @override
  Future<Result<int>> countArticles({
    ArticleFilter filter = ArticleFilter.all,
    int? feedId,
  }) async =>
      Err(StorageError(operation: 'countArticles', detail: '本次运行数据库不可用'));

  @override
  Future<Result<ArticleListEntry?>> findArticle(int articleId) async =>
      Err(StorageError(operation: 'findArticle', detail: '本次运行数据库不可用'));

  @override
  Future<Result<List<ArticleListEntry>>> findArticles(
    List<int> articleIds,
  ) async => Err(StorageError(operation: 'findArticles', detail: '本次运行数据库不可用'));

  @override
  Future<Result<List<int>>> listArticleIds({
    ArticleFilter filter = ArticleFilter.all,
    int? feedId,
  }) async =>
      Err(StorageError(operation: 'listArticleIds', detail: '本次运行数据库不可用'));

  @override
  Future<Result<int>> setReadingState({
    required List<int> articleIds,
    required ReadingState state,
  }) async => Err(
    StorageError(operation: 'setReadingState', detail: '本次运行数据库不可用，状态不会保存'),
  );

  @override
  Future<Result<int>> setFavorite({
    required List<int> articleIds,
    required bool favorite,
  }) async =>
      Err(StorageError(operation: 'setFavorite', detail: '本次运行数据库不可用，收藏不会保存'));

  @override
  Future<Result<int>> markReadIfUnread(int articleId) async =>
      Err(StorageError(operation: 'markReadIfUnread', detail: '本次运行数据库不可用'));

  @override
  Future<Result<String?>> readArticleBody(int articleId) async =>
      Err(StorageError(operation: 'readArticleBody', detail: '本次运行数据库不可用'));

  @override
  Future<Result<int>> restoreArticleStates(
    List<ArticleStateSnapshot> snapshots,
  ) async => Err(
    StorageError(
      operation: 'restoreArticleStates',
      detail: '本次运行数据库不可用，撤销无法执行',
    ),
  );
}

/// 数据库不可用时的检索端口（T022 的降级启动路径）。
///
/// 与 [DegradedArticleCatalogStore] 同一口径：**返回类型化失败**，而不是空结果。
/// 这一条与列表的降级**有意不同**：列表读不到时返回空集合，因为「列表是空的」在
/// 数据库不可用时可解释（用户看到空态 + 顶部横幅）；而检索返回空结果会让用户以为
/// 「库里没有这篇文章」，从而去改查询词——那是在为一个环境问题找错方向。
final class DegradedArticleSearchStore implements ArticleSearchPort {
  /// 构造降级实现。
  const DegradedArticleSearchStore();

  @override
  Future<Result<SearchPage>> search(SearchQuery query) async =>
      Err(StorageError(operation: 'search', detail: '本次运行数据库不可用，检索无法执行'));

  @override
  Future<Result<int>> rebuildIndex() async =>
      Err(StorageError(operation: 'rebuildIndex', detail: '本次运行数据库不可用'));
}
