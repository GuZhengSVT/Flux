// 文章列表读取与状态写入端口（T017；架构 4.1 的 F-STATE 与「列表分页」）。
//
// 为什么与 T013 的 [FeedArticleStore] 分开：
//   那个端口只服务「导入」——它拿到的是一批已解析好的文章，职责是幂等写入与
//   「不覆盖用户状态」。本端口服务**阅读**：按筛选与排序分页读列表、按 id 批量改
//   三态与收藏。两者的调用者、失败语义与安全边界都不同（导入不接受任意 id，阅读
//   不写正文）。合成一个接口会让导入流程拿到「按 id 改任意文章状态」的能力。
//
// 三条与产品规则直接对应的约定：
//   1) [ArticleFilter.unread] **只匹配 unread**：later 有独立入口，不能算进未读，
//      否则用户会看到一个永远清不掉的角标（架构 4.1）；
//   2) 排序按「发布时间，缺失则抓取时间」倒序，再用本机 id 作稳定次序——架构 4.1
//      要求「发布时间未知则使用抓取时间排序并注明；相同时间用稳定身份作次序」。
//      条目里带 [ArticleListEntry.publishedAtMissing]，让界面能注明而不是假装有日期；
//   3) [ArticleCatalogStore.markReadIfUnread] 是**条件写**：只有当前是 unread 才变
//      read。SET-010 的「later 打开后仍为 later」因此不是靠调用方记得判断，而是
//      在 SQL 条件里成立。
library;

import '../result.dart';
import '../error/app_error.dart';

import 'article_identity.dart';
import 'reading_state.dart';

/// 列表筛选。
enum ArticleFilter {
  /// 全部（含 later 与已读）。
  all,

  /// 仅未读：**只匹配 unread**，later 不在其中。
  unread,

  /// 稍后再读（独立入口）。
  later,

  /// 收藏（与阅读状态无关：已读未读都可能是收藏）。
  favorite,
}

/// 列表里的一行文章（含来源名，避免界面为每行再查一次订阅）。
class ArticleListEntry {
  /// 构造条目。
  const ArticleListEntry({
    required this.id,
    required this.feedId,
    required this.feedName,
    required this.title,
    required this.readingState,
    required this.favorite,
    required this.publishedAt,
    required this.fetchedAt,
    this.summary,
    this.sourceUrl,
    this.author,
    this.feedTitle,
    this.feedUrl,
    this.bodyCompleteness = BodyCompleteness.unknown,
  });

  /// 本机自增 id（列表操作与分页游标都以它为准）。
  final int id;

  /// 所属订阅；**null 表示已脱离源**（删除订阅时保留下来的收藏，架构 4.1）。
  ///
  /// 为什么不用一个哨兵 id 表示「没有源」：脱离源是一条真实且用户可见的状态
  /// （来源一栏显示的是冻结的快照，而不是某个现存的订阅）。用 null 表达它，界面就
  /// 无法在「忘了填 id」时静默退化成一个指向不存在订阅的整数。
  final int? feedId;

  /// 来源显示名（订阅的显示名，不是源自带名）。
  ///
  /// 已脱离源的文章由存储层填入 [feedTitle] 快照，因此界面读这一个字段就够，
  /// 不需要在每个调用点各判断一次「源还在不在」。
  final String feedName;

  /// 来源快照：脱离源时冻结的源显示名；未脱离源为 null。
  final String? feedTitle;

  /// 来源快照：脱离源时冻结的规范化地址；未脱离源为 null。
  final String? feedUrl;

  /// 是否已脱离源（删除订阅时保留下来的收藏）。
  bool get detachedFromFeed => feedId == null;

  /// 正文完整性四态（架构 4.2）。详情页据此显示「来源全文 / 仅摘要 / 本机提取 /
  /// 完整性未知」——**不在这一层做判断**，因为「源内的 content 字段就是全文吗」这个
  /// 问题只有导入路径知道（它看得到源里的字段结构）。界面只负责如实显示判定结果。
  final BodyCompleteness bodyCompleteness;

  /// 标题（导入时保证非空）。
  final String title;

  /// 阅读状态。
  final ReadingState readingState;

  /// 收藏（独立于阅读状态）。
  final bool favorite;

  /// 发布时间（UTC）；null 表示源未提供。
  final DateTime? publishedAt;

  /// 抓取时间（UTC）。
  final DateTime fetchedAt;

  /// 摘要（源内摘要清洗后的纯文本）；可为 null。
  final String? summary;

  /// 原始链接（保留查询参数，用于外开）。
  final String? sourceUrl;

  /// 作者。
  final String? author;

  /// 排序与展示使用的有效时间：发布时间优先，缺失时用抓取时间。
  DateTime get effectiveTime => publishedAt ?? fetchedAt;

  /// 发布时间是否缺失（界面据此注明「按抓取时间排序」）。
  bool get publishedAtMissing => publishedAt == null;
}

/// 一页文章。
class ArticlePage {
  /// 构造页。
  const ArticlePage({
    required this.entries,
    required this.total,
    required this.offset,
  });

  /// 本页条目（已按 [ArticleFilter] 与排序规则排列）。
  final List<ArticleListEntry> entries;

  /// 满足筛选条件的总条数（分页控件与空态判断用它，不用本页长度猜）。
  final int total;

  /// 本页起始偏移。
  final int offset;

  /// 是否还有下一页。
  bool get hasMore => offset + entries.length < total;
}

/// 校验一次分页查询的参数。
///
/// 为什么把校验放在 domain 而不是只靠 assert：assert 在 release 构建里被移除，
/// 而「limit 为 0」会让列表**永久显示为空**且没有任何错误——那是最难排查的一类
/// 问题。这里返回类型化失败，调用方（用例与界面）必须处理它。
Result<void> validateArticleQuery(ArticleQuery query) {
  if (query.offset < 0) {
    return Err<void>(
      ValidationError(field: 'articleQuery.offset', reason: '偏移不能为负'),
    );
  }
  if (query.limit <= 0) {
    return Err<void>(
      ValidationError(field: 'articleQuery.limit', reason: '每页数量必须为正'),
    );
  }
  return const Ok<void>(null);
}

/// 一次分页查询。
class ArticleQuery {
  /// 构造查询。
  const ArticleQuery({
    this.filter = ArticleFilter.all,
    this.feedId,
    this.offset = 0,
    this.limit = 50,
  }) : assert(offset >= 0, '偏移不能为负'),
       assert(limit > 0, '每页数量必须为正');

  /// 筛选。
  final ArticleFilter filter;

  /// 限定来源；null 表示不限。
  final int? feedId;

  /// 偏移。
  final int offset;

  /// 每页数量。
  final int limit;

  /// 换页返回新查询。
  ArticleQuery atPage(int newOffset) => ArticleQuery(
    filter: filter,
    feedId: feedId,
    offset: newOffset,
    limit: limit,
  );
}

/// 批量操作的范围（架构 4.1：范围选择为全部/筛选结果/所选行）。
enum BatchScope {
  /// 全部文章（忽略当前筛选）。
  all,

  /// 当前筛选结果（含来源限定）。
  filtered,

  /// 用户在界面上勾选的行。
  selected,
}

/// 一篇文章在批量操作**之前**的状态快照（撤销用）。
///
/// 为什么快照两个字段而不是只快照被改的那一个：架构第 7 节要求「危险操作显示影响和
/// 可用撤销」。撤销的语义是「回到操作之前」，因此必须能恢复这一行**当时**的全部用户
/// 状态；只恢复一个字段会让「撤销批量标未读」把收藏也一起留在某个中间态上。
///
/// 刻意不含正文与身份字段：批量操作从不改它们，把它们放进快照会让撤销看起来能恢复
/// 内容，而实际上没有那份旧内容可回填（会被误读成「撤销能找回被清理的正文」）。
class ArticleStateSnapshot {
  /// 构造快照。
  const ArticleStateSnapshot({
    required this.articleId,
    required this.readingState,
    required this.favorite,
  });

  /// 文章 id。
  final int articleId;

  /// 操作前的阅读状态。
  final ReadingState readingState;

  /// 操作前的收藏。
  final bool favorite;
}

/// 文章阅读端口。
///
/// 实现约定：所有方法不抛异常（除编程错误），失败翻译为 [Result.err]。
abstract interface class ArticleCatalogStore {
  /// 分页读出列表。
  Future<Result<ArticlePage>> listArticles(ArticleQuery query);

  /// 按筛选条件统计条数。
  Future<Result<int>> countArticles({
    ArticleFilter filter = ArticleFilter.all,
    int? feedId,
  });

  /// 读取单篇（详情页与状态切换前校验用）。
  Future<Result<ArticleListEntry?>> findArticle(int articleId);

  /// 按 id 集合取条目（批量操作的「所选行」范围解析用）。
  ///
  /// 只返回**确实存在**的行：界面可能拿着一个已被删除的 id，静默忽略比抛错合适。
  Future<Result<List<ArticleListEntry>>> findArticles(List<int> articleIds);

  /// 按范围取 id（[BatchScope.all] / [BatchScope.filtered] 的实现）。
  Future<Result<List<int>>> listArticleIds({
    ArticleFilter filter = ArticleFilter.all,
    int? feedId,
  });

  /// 批量设置阅读状态。
  ///
  /// 实现**只改** reading_state 与 updated_at：收藏是独立字段，批量改阅读状态
  /// 不得顺手动它（架构 4.1 与手册 6.3「批量未读不影响收藏」）。
  Future<Result<int>> setReadingState({
    required List<int> articleIds,
    required ReadingState state,
  });

  /// 批量设置收藏。
  ///
  /// 实现**只改** favorite 与 updated_at：收藏不改变阅读状态。
  Future<Result<int>> setFavorite({
    required List<int> articleIds,
    required bool favorite,
  });

  /// 条件写：仅当当前为 unread 时置为 read，返回受影响行数（0 表示未改动）。
  Future<Result<int>> markReadIfUnread(int articleId);

  /// 按快照恢复若干文章的用户状态（批量操作的撤销）。
  ///
  /// 实现必须在一个事务内完成：撤销到一半失败会留下一个「部分恢复」的状态，而用户
  /// 已经看到「已撤销」的提示——那比不撤销更糟。
  ///
  /// 只恢复 [ArticleStateSnapshot] 里的两个字段，不动标题、正文、身份与时间。
  Future<Result<int>> restoreArticleStates(
    List<ArticleStateSnapshot> snapshots,
  );

  /// 读取正文纯文本（详情页用）。
  ///
  /// 为什么单独一个方法而不是放进 [ArticleListEntry]：正文是大字段，列表一页 50 行
  /// 会让每次翻页都把这些文本读进内存；而详情页一次只需要一篇。用「按需读」把这
  /// 笔开销挪到真正需要它的那一次调用上。
  ///
  /// 返回 null 表示这篇文章没有正文（源只提供了摘要）。这与「文章不存在」不同：
  /// 前者是合法状态，界面要如实说明而不是报错。
  Future<Result<String?>> readArticleBody(int articleId);
}
