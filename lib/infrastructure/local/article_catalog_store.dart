// 文章阅读数据层（T017；架构 4.1 的 F-STATE 与「列表分页/虚拟化」）。
//
// 职责边界：本文件只做**读列表**与**按 id 改状态**，不做任何产品判断——
// 「later 打开后仍为 later」的规则在用例层，但它的**最后一层保险**在 SQL 条件里
// （markReadIfUnread 只匹配 unread，见下）。正文、身份、导入都属于 T009/T013，
// 不在本文件里。
//
// 三条与产品规则直接对应的实现选择：
//
//   1) 排序用「发布时间，缺失则抓取时间」。SQL 里用 COALESCE(published_at,
//      fetched_at) 而不是「先按 published_at 排序，再 Dart 里补一次」——两段式排序
//      会让没有日期的文章整段沉底或整段上浮，而不是按它实际被看到的时间参与排序。
//      架构 4.1 要求「发布时间未知则使用抓取时间排序并注明」，因此这里必须让两者
//      在**同一次排序**里可比。

//   2) 相同时间用本机 id 作稳定次序（架构 4.1「相同时间用稳定身份作次序」）。
//      没有这一层，同一批同时刻的文章在两次查询里可能换位置，分页会出现重复/漏行。

//   3) [setReadingState] / [setFavorite] **只改自己那一个字段**。批量改阅读状态
//      不得顺手动收藏（手册 6.3「批量未读不影响收藏」）；这条规则在实现里是结构性的：
//      两个方法各自写死的补丁里根本没有对方那个列。
library;

import 'package:drift/drift.dart';

import 'package:flux/core/core.dart';

import 'database.dart';
import 'tables/article_tables.dart';

/// 一条订阅在列表渲染时需要的两个字段。
///
/// 打包成一个私有值类型而不是 `Map<int, String>`：列表要显示来源名，而外开链接与
/// 详情页要显示地址，一次查询同时取回比让调用方为地址再查一次更省往返；用记录类型
/// 明确写出字段名，也避免「第二个 String 是什么」在调用点变成猜测。
final class FeedSnapshot {
  /// 构造快照。
  const FeedSnapshot({required this.name, required this.url});

  /// 订阅显示名（用户可改，因此这是**当前**值）。
  final String name;

  /// 规范化地址。
  final String url;
}

/// 文章阅读数据层。
final class DriftArticleCatalogStore implements ArticleCatalogStore {
  /// 绑定一个已打开的数据库。
  const DriftArticleCatalogStore(this._db);

  final AppDatabase _db;

  @override
  Future<Result<ArticlePage>> listArticles(ArticleQuery query) async {
    final Result<void> validation = validateArticleQuery(query);
    if (validation.isErr) {
      return Err<ArticlePage>(validation.errorOrNull!);
    }
    try {
      final int total = (await _count(
        filter: query.filter,
        feedId: query.feedId,
      )).unwrap();

      final SimpleSelectStatement<$ArticlesTable, Article> select =
          _db.select(_db.articles)
            ..orderBy(<OrderClauseGenerator<$ArticlesTable>>[
              ($ArticlesTable t) => OrderingTerm.desc(
                // COALESCE：没有发布时间时按抓取时间参与同一次排序（架构 4.1）。
                coalesce<DateTime>(<Expression<DateTime>>[
                  t.publishedAt,
                  t.fetchedAt,
                ]),
              ),
              // 稳定次序：同一时刻按本机 id 倒排，避免分页出现重复/漏行
              // （架构 4.1「相同时间用稳定身份作次序」）。
              ($ArticlesTable t) => OrderingTerm.desc(t.id),
            ])
            ..limit(query.limit, offset: query.offset);
      _applyFilterSimple(select, filter: query.filter, feedId: query.feedId);

      final List<Article> rows = await select.get();
      final Map<int, FeedSnapshot> feedNames = await _feedSnapshots(
        rows.map((Article a) => a.feedId).whereType<int>().toSet(),
      );
      final List<ArticleListEntry> entries = <ArticleListEntry>[
        for (final Article row in rows) _toEntry(row, feedNames: feedNames),
      ];
      return Ok<ArticlePage>(
        ArticlePage(entries: entries, total: total, offset: query.offset),
      );
    } on Exception catch (error, stackTrace) {
      return Err<ArticlePage>(_storage('listArticles', error, stackTrace));
    }
  }

  @override
  Future<Result<int>> countArticles({
    ArticleFilter filter = ArticleFilter.all,
    int? feedId,
  }) async {
    try {
      return Ok<int>((await _count(filter: filter, feedId: feedId)).unwrap());
    } on Exception catch (error, stackTrace) {
      return Err<int>(_storage('countArticles', error, stackTrace));
    }
  }

  @override
  Future<Result<ArticleListEntry?>> findArticle(int articleId) async {
    try {
      final Article? row =
          await (_db.select(_db.articles)
                ..where(($ArticlesTable t) => t.id.equals(articleId))
                ..limit(1))
              .getSingleOrNull();
      if (row == null) {
        return const Ok<ArticleListEntry?>(null);
      }
      final int? feedIdOfRow = row.feedId;
      final Map<int, FeedSnapshot> names = await _feedSnapshots(
        feedIdOfRow == null ? const <int>{} : <int>{feedIdOfRow},
      );
      return Ok<ArticleListEntry?>(_toEntry(row, feedNames: names));
    } on Exception catch (error, stackTrace) {
      return Err<ArticleListEntry?>(_storage('findArticle', error, stackTrace));
    }
  }

  @override
  Future<Result<List<ArticleListEntry>>> findArticles(
    List<int> articleIds,
  ) async {
    if (articleIds.isEmpty) {
      return const Ok<List<ArticleListEntry>>(<ArticleListEntry>[]);
    }
    try {
      // 只返回确实存在的行：界面可能拿着一个已被删除的 id，静默忽略比抛错合适。
      final List<Article> rows =
          await (_db.select(_db.articles)
                ..where(($ArticlesTable t) => t.id.isIn(articleIds))
                ..orderBy(<OrderClauseGenerator<$ArticlesTable>>[
                  ($ArticlesTable t) => OrderingTerm.desc(t.id),
                ]))
              .get();
      final Map<int, FeedSnapshot> names = await _feedSnapshots(
        rows.map((Article a) => a.feedId).whereType<int>().toSet(),
      );
      return Ok<List<ArticleListEntry>>(<ArticleListEntry>[
        for (final Article row in rows) _toEntry(row, feedNames: names),
      ]);
    } on Exception catch (error, stackTrace) {
      return Err<List<ArticleListEntry>>(
        _storage('findArticles', error, stackTrace),
      );
    }
  }

  @override
  Future<Result<List<int>>> listArticleIds({
    ArticleFilter filter = ArticleFilter.all,
    int? feedId,
  }) async {
    try {
      final SimpleSelectStatement<$ArticlesTable, Article> select =
          _db.select(_db.articles)
            ..orderBy(<OrderClauseGenerator<$ArticlesTable>>[
              (Articles t) => OrderingTerm.desc(t.id),
            ]);
      _applyFilterSimple(select, filter: filter, feedId: feedId);
      final List<Article> rows = await select.get();
      return Ok<List<int>>(
        rows.map((Article a) => a.id).toList(growable: false),
      );
    } on Exception catch (error, stackTrace) {
      return Err<List<int>>(_storage('listArticleIds', error, stackTrace));
    }
  }

  @override
  Future<Result<int>> setReadingState({
    required List<int> articleIds,
    required ReadingState state,
  }) async {
    if (articleIds.isEmpty) {
      return const Ok<int>(0);
    }
    try {
      final int changed =
          await (_db.update(
            _db.articles,
          )..where((Articles t) => t.id.isIn(articleIds))).write(
            ArticlesCompanion(
              readingState: Value<ReadingState>(state),
              updatedAt: Value<DateTime>(DateTime.now().toUtc()),
              // favorite 有意不出现：批量改阅读状态不得动收藏
              // （手册 6.3「批量未读不影响收藏」）。这不是靠调用方记得，
              // 而是这一个补丁里根本没有那个列。
            ),
          );
      return Ok<int>(changed);
    } on Exception catch (error, stackTrace) {
      return Err<int>(_storage('setReadingState', error, stackTrace));
    }
  }

  @override
  Future<Result<int>> setFavorite({
    required List<int> articleIds,
    required bool favorite,
  }) async {
    if (articleIds.isEmpty) {
      return const Ok<int>(0);
    }
    try {
      final int changed =
          await (_db.update(
            _db.articles,
          )..where((Articles t) => t.id.isIn(articleIds))).write(
            ArticlesCompanion(
              favorite: Value<bool>(favorite),
              updatedAt: Value<DateTime>(DateTime.now().toUtc()),
              // readingState 有意不出现：收藏不改变阅读状态（架构 4.1）。
            ),
          );
      return Ok<int>(changed);
    } on Exception catch (error, stackTrace) {
      return Err<int>(_storage('setFavorite', error, stackTrace));
    }
  }

  @override
  Future<Result<int>> markReadIfUnread(int articleId) async {
    try {
      // 条件写：WHERE 里带 reading_state = 'unread'。
      //
      // 为什么把规则放在 SQL 而不是「先读出来判断再写」：读-判断-写之间存在窗口，
      // 两次打开同一篇文章（或同步在中间落地了一个 later）会让判断失效。条件写让
      // 「later 不会被打开动作改成 read」在数据库层成立——受影响 0 行就是没改。
      final int changed =
          await (_db.update(_db.articles)..where(
                ($ArticlesTable t) =>
                    t.id.equals(articleId) &
                    t.readingState.equalsValue(ReadingState.unread),
              ))
              .write(
                ArticlesCompanion(
                  readingState: const Value<ReadingState>(ReadingState.read),
                  updatedAt: Value<DateTime>(DateTime.now().toUtc()),
                ),
              );
      return Ok<int>(changed);
    } on Exception catch (error, stackTrace) {
      return Err<int>(_storage('markReadIfUnread', error, stackTrace));
    }
  }

  @override
  Future<Result<String?>> readArticleBody(int articleId) async {
    try {
      // 只查正文一列：这篇文章可能有几十 KB 的其它字段（规范化链接、指纹等），
      // 详情页一个都不需要。
      final String? body =
          await (_db.selectOnly(_db.articles)
                ..addColumns(<Expression<Object>>[_db.articles.body])
                ..where(_db.articles.id.equals(articleId)))
              .map((TypedResult row) => row.read(_db.articles.body))
              .getSingleOrNull();
      return Ok<String?>(body);
    } on Exception catch (error, stackTrace) {
      return Err<String?>(_storage('readArticleBody', error, stackTrace));
    }
  }

  @override
  Future<Result<void>> saveAiSummary({
    required int articleId,
    required AiSummaryRecord summary,
  }) async {
    try {
      // 补丁里**只有** ai_summary 三列：源摘要、正文、正文哈希、三态与收藏都不出现，
      // 因此「写 AI 摘要顺手改了源代码的摘要」在这个实现里不可能发生。
      final int changed =
          await (_db.update(
            _db.articles,
          )..where(($ArticlesTable t) => t.id.equals(articleId))).write(
            ArticlesCompanion(
              aiSummary: Value<String?>(summary.text),
              aiSummaryAt: Value<DateTime?>(summary.generatedAt),
              aiSummaryModel: Value<String?>(summary.modelLabel),
            ),
          );
      if (changed == 0) {
        return Err<void>(
          StorageError(
            operation: 'saveAiSummary',
            detail: '文章 $articleId 不存在',
            isMissing: true,
          ),
        );
      }
      return okUnit();
    } on Exception catch (error, stackTrace) {
      return Err<void>(_storage('saveAiSummary', error, stackTrace));
    }
  }

  @override
  Future<Result<AiSummaryRecord?>> readAiSummary(int articleId) async {
    try {
      final Article? row =
          await (_db.select(_db.articles)
                ..where(($ArticlesTable t) => t.id.equals(articleId))
                ..limit(1))
              .getSingleOrNull();
      if (row == null) {
        return const Ok<AiSummaryRecord?>(null);
      }
      final String? text = row.aiSummary;
      final DateTime? at = row.aiSummaryAt;
      if (text == null || text.isEmpty || at == null) {
        // 文本或时间缺一即视为「没有 AI 摘要」：只有文本没有时间，界面无法说明它是
        // 什么时候生成的（而一个没有时间的摘要在正文改动后无法被判断是否还对应）。
        return const Ok<AiSummaryRecord?>(null);
      }
      return Ok<AiSummaryRecord?>(
        AiSummaryRecord(
          text: text,
          generatedAt: at,
          modelLabel: row.aiSummaryModel,
        ),
      );
    } on Exception catch (error, stackTrace) {
      return Err<AiSummaryRecord?>(
        _storage('readAiSummary', error, stackTrace),
      );
    }
  }

  @override
  Future<Result<List<int>>> listArticlesMissingSummary({
    required int limit,
    int? feedId,
    int offset = 0,
  }) async {
    if (limit <= 0) {
      return const Ok<List<int>>(<int>[]);
    }
    try {
      // 「缺摘要」= 源摘要与 AI 摘要都为空（空白串也算缺：源里给一个空 <description>
      // 不是「有摘要」）。排序与列表一致（时间倒序、id 稳定），因此自动摘要总是先补
      // 用户最可能看到的那几篇。
      final SimpleSelectStatement<$ArticlesTable, Article> select =
          _db.select(_db.articles)
            ..where(
              ($ArticlesTable t) =>
                  _blank(t.summary) & _blank(t.aiSummary) & _inFeed(t, feedId),
            )
            ..orderBy(<OrderClauseGenerator<$ArticlesTable>>[
              ($ArticlesTable t) => OrderingTerm.desc(
                coalesce<DateTime>(<Expression<DateTime>>[
                  t.publishedAt,
                  t.fetchedAt,
                ]),
              ),
              ($ArticlesTable t) => OrderingTerm.desc(t.id),
            ])
            ..limit(limit, offset: offset);
      final List<Article> rows = await select.get();
      return Ok<List<int>>(<int>[for (final Article row in rows) row.id]);
    } on Exception catch (error, stackTrace) {
      return Err<List<int>>(
        _storage('listArticlesMissingSummary', error, stackTrace),
      );
    }
  }

  /// 「这一列是空的」（NULL 或只有空白）。
  Expression<bool> _blank(GeneratedColumn<String> column) {
    final Expression<String> trimmed = column.trim();
    return column.isNull() | trimmed.equals('');
  }

  /// 可选的来源限定。
  Expression<bool> _inFeed($ArticlesTable t, int? feedId) =>
      feedId == null ? const Constant<bool>(true) : t.feedId.equals(feedId);

  @override
  Future<Result<int>> restoreArticleStates(
    List<ArticleStateSnapshot> snapshots,
  ) async {
    if (snapshots.isEmpty) {
      return const Ok<int>(0);
    }
    try {
      // 必须在一个事务里：撤销到一半失败会留下「部分恢复」的状态，而用户已经看到
      // 「已撤销」的提示——那比不撤销更糟（架构第 8 节：不用假象代替状态）。
      final int restored = await _db.transaction<int>(() async {
        int changed = 0;
        for (final ArticleStateSnapshot snapshot in snapshots) {
          changed +=
              await (_db.update(_db.articles)..where(
                    ($ArticlesTable t) => t.id.equals(snapshot.articleId),
                  ))
                  .write(
                    ArticlesCompanion(
                      readingState: Value<ReadingState>(snapshot.readingState),
                      favorite: Value<bool>(snapshot.favorite),
                      updatedAt: Value<DateTime>(DateTime.now().toUtc()),
                    ),
                  );
        }
        return changed;
      });
      return Ok<int>(restored);
    } on Exception catch (error, stackTrace) {
      return Err<int>(_storage('restoreArticleStates', error, stackTrace));
    }
  }

  /// 统计条数（分页的 total 与空态判断共用）。
  Future<Result<int>> _count({
    required ArticleFilter filter,
    required int? feedId,
  }) async {
    final Expression<bool>? predicate = _predicate(
      filter: filter,
      feedId: feedId,
    );
    // COUNT(*) 在 SQL 里算：列表可能上万行，把整行（含正文大字段）读进内存再在
    // Dart 里计数是数量级差异。
    final JoinedSelectStatement<$ArticlesTable, Article> select =
        _db.selectOnly(_db.articles)
          ..addColumns(<Expression<Object>>[countAll()]);
    if (predicate != null) {
      select.where(predicate);
    }
    final TypedResult row = await select.getSingle();
    return Ok<int>(row.read(countAll()) ?? 0);
  }

  /// 给单表查询套上筛选（计数与取 id 用）。
  void _applyFilterSimple(
    SimpleSelectStatement<$ArticlesTable, Article> select, {
    required ArticleFilter filter,
    required int? feedId,
  }) {
    final Expression<bool>? predicate = _predicate(
      filter: filter,
      feedId: feedId,
    );
    if (predicate != null) {
      select.where(($ArticlesTable _) => predicate);
    }
  }

  /// 按 feed id 批量取显示名（列表避免逐行查询订阅）。
  ///
  /// 用一次 IN 查询而不是在循环里逐行 findFeedById：列表一页 50 行时那是 50 次
  /// 往返。返回 Map 而不是列表，是因为调用方按 feedId 取值，顺序无意义。
  ///
  /// 已脱离源的收藏**不在**这个查询里：它们的 feed_id 为 NULL，取不到也就不该取
  /// ——它们的来源由行上的快照列回答（见 [_toEntry]）。
  Future<Map<int, FeedSnapshot>> _feedSnapshots(Set<int> feedIds) async {
    if (feedIds.isEmpty) {
      return const <int, FeedSnapshot>{};
    }
    final List<Feed> rows = await (_db.select(
      _db.feeds,
    )..where(($FeedsTable t) => t.id.isIn(feedIds))).get();
    return <int, FeedSnapshot>{
      for (final Feed row in rows)
        row.id: FeedSnapshot(name: row.name, url: row.normalizedUrl),
    };
  }

  /// 构造筛选条件；无条件时返回 null。
  Expression<bool>? _predicate({
    required ArticleFilter filter,
    required int? feedId,
  }) {
    final Expression<bool>? filterPredicate = switch (filter) {
      ArticleFilter.all => null,
      // **只匹配 unread**：later 有独立入口，不能算进未读，否则用户会看到一个
      // 永远清不掉的角标（架构 4.1）。
      ArticleFilter.unread => _db.articles.readingState.equalsValue(
        ReadingState.unread,
      ),
      ArticleFilter.later => _db.articles.readingState.equalsValue(
        ReadingState.later,
      ),
      // 收藏与阅读状态无关：已读未读都可能是收藏。
      ArticleFilter.favorite => _db.articles.favorite.equals(true),
    };
    final Expression<bool>? feedPredicate = feedId == null
        ? null
        : _db.articles.feedId.equals(feedId);

    if (filterPredicate == null) {
      return feedPredicate;
    }
    if (feedPredicate == null) {
      return filterPredicate;
    }
    return filterPredicate & feedPredicate;
  }

  /// 行 → 读取模型。
  ///
  /// 来源显示名按两种来源取值，优先级明确：
  ///   1) 未脱离源（feed_id 非空）→ 现查订阅表的名字，用户改名后立即生效；
  ///   2) 已脱离源（feed_id 为空）→ 行上的 [Articles.feedTitle] 快照。这是
  ///      **冻结值**，源被重新添加或再次删除都不改写它（架构 4.1 的「来源快照」）。
  /// 两种都取不到时返回空串而不是编一个名字：界面会因此显示一个可辨认的空来源，
  /// 而不会假装这篇文章来自某个源。
  static ArticleListEntry _toEntry(
    Article row, {
    required Map<int, FeedSnapshot> feedNames,
  }) {
    final int? feedId = row.feedId;
    final FeedSnapshot? live = feedId == null ? null : feedNames[feedId];
    return ArticleListEntry(
      id: row.id,
      feedId: feedId,
      feedName: live?.name ?? row.feedTitle ?? '',
      feedTitle: row.feedTitle,
      feedUrl: row.feedUrl,
      title: row.title,
      readingState: row.readingState,
      favorite: row.favorite,
      bodyCompleteness: row.bodyCompleteness,
      publishedAt: row.publishedAt,
      fetchedAt: row.fetchedAt,
      summary: row.summary,
      aiSummary: row.aiSummary,
      aiSummaryAt: row.aiSummaryAt,
      aiSummaryModel: row.aiSummaryModel,
      sourceUrl: row.sourceUrl,
      author: row.author,
      imageUrl: row.imageUrl,
    );
  }

  static StorageError _storage(
    String operation,
    Object error,
    StackTrace stackTrace,
  ) => StorageError(
    operation: operation,
    // 只保留异常类型：sqlite 的原始文本可能带上语句与参数值。
    detail: error.runtimeType.toString(),
    cause: error,
    stackTrace: stackTrace,
  );
}
