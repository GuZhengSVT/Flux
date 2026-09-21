// 全文检索数据层（T022；架构 4.2 的 F-SEARCH）。
//
// 职责边界：本文件只做「按执行计划查出 id 与命中片段」，不做产品判断——范围与筛选的
// 语义来自 domain（[SearchScope]）。它**不**返回完整文章行：命中片段来自 fts5，整行数据
// 仍由列表层按 id 取（两处读同一份来源，不会出现「片段说命中、点进去没有」的错位）。
//
// 两条查询路径（由 [planSearch] 决定；实测语义见 domain 文件顶部的说明）：
//
//   MATCH 路径：查询是 ≥3 字符的连续片段。用 fts5 的 MATCH + bm25 排序 + snippet() 高亮；
//   片段直接来自索引，因此长正文的命中点不必把全文读进内存。
//
//   LIKE 路径：查询不足 3 字符（trigram 索引里不存在这样的项）。用 LIKE 子串匹配，
//   **不带相关性排序**（LIKE 没有排名概念），退回列表的既有次序（时间倒序）；片段由
//   应用层在取回的行上截取（[snippetAround]）。
//
// 来源名（feeds.name）**不进索引**，而是在查询里现查：
//   * 索引列必须是 articles 里逐字存在的列，否则 fts5 的 'rebuild'（它直接从 content 表
//     重新扫描、不执行触发器）会造出与触发器不一致的索引——实测过：rebuild 后来源名全为
//     null，来源名搜索整个失效；
//   * 现查还有个好处：源改名后检索**立即**生效，不需要维护索引，也不会出现「列表显示
//     A 源、按 A 源搜不到」。
//
// 为什么用 customSelect 而不是 drift 的类型化查询：MATCH/bm25/snippet 都是虚拟表上的
// 函数，drift 的查询构造器表达不了。参数仍走占位符（[Variable]），不做字符串拼接。
library;

import 'package:drift/drift.dart';

import 'package:flux/core/core.dart';

import 'database.dart';

/// LIKE 子句使用的转义符。
///
/// 写成常量而不是在每处字面量里重复：转义符与 [escapeLikePattern] 里用的必须**完全**
/// 是同一个字符，两处写两遍迟早会漂移（那时转义失效、% 又变成通配符）。
const String kLikeEscape = r'\';

/// 片段省略号在 SQL 里的字面量。
///
/// 用字面量而不是绑定参数：snippet() 的省略号是固定的产品文案，不是用户输入；
/// 把它做成参数会让每个查询的参数顺序里都多一个与检索语义无关的项。
const String _snippetEllipsis = "'…'";

/// 全文检索数据层。
final class DriftArticleSearchStore implements ArticleSearchPort {
  /// 绑定一个已打开的数据库。
  const DriftArticleSearchStore(this._db);

  final AppDatabase _db;

  @override
  Future<Result<SearchPage>> search(SearchQuery query) async {
    final Result<void> validation = validateSearchQuery(query);
    if (validation.isErr) {
      return Err<SearchPage>(validation.errorOrNull!);
    }
    final SearchPlan? plan = planSearch(query.text);
    if (plan == null) {
      // 空查询不是「匹配一切」：返回一个明确无结果的页，界面给空态提示。
      // 把它当成匹配全部会让用户在清空搜索框的瞬间看到全库文章，看起来像卡住。
      return Ok<SearchPage>(
        SearchPage(hits: const <SearchHit>[], total: 0, offset: query.offset),
      );
    }

    try {
      return Ok<SearchPage>(
        plan.mode == SearchMode.match
            ? await _searchByMatch(query, plan)
            : await _searchByLike(query, plan),
      );
    } on Exception catch (error, stackTrace) {
      return Err<SearchPage>(_storage('search', error, stackTrace));
    }
  }

  @override
  Future<Result<int>> rebuildIndex() async {
    try {
      // fts5 内置的 rebuild：直接从 content 表（articles）重新扫描，因此结果与触发器
      // 逐行维护的索引严格一致（前提是索引列都逐字来自 articles——见文件头说明）。
      await _db.customStatement(
        "INSERT INTO articles_fts(articles_fts) VALUES('rebuild')",
      );
      final QueryRow row = await _db
          .customSelect('SELECT COUNT(*) AS c FROM articles_fts')
          .getSingle();
      return Ok<int>(row.read<int>('c'));
    } on Exception catch (error, stackTrace) {
      return Err<int>(_storage('rebuildIndex', error, stackTrace));
    }
  }

  /// MATCH 路径。
  ///
  /// 两个**实测**得出的结构决定（都来自 1 万行数据集上的计时，见 perf 用例）：
  ///
  ///   1) **用 UNION ALL 合并「内容命中」与「来源名命中」，不要写成一个 OR**。
  ///      写成 OR EXISTS 的形式时，SQLite 无法把任一侧下推到索引，退化成对 articles
  ///      的**全表扫描**：1 万行上实测 17.6 秒。改成 UNION ALL 之后两侧各走索引
  ///      （内容侧走 fts 虚拟表索引、来源侧走 feeds 主键），同一条查询降到 18 毫秒。
  ///
  ///   2) **snippet 高亮只对当页的 id 计算**，不写进排序子查询。写进去时 SQLite 会在
  ///      排序与分页**之前**为每个命中行算四次 snippet：一个命中一万篇的常见词就是四万次
  ///      高亮计算，哪怕最终只返回 50 条。拆开之后只算「当页条数 × 4」次。
  ///
  /// 排序 (1) 内容命中优先、(2) bm25、(3) 时间倒序：来源名命中的行没有 bm25 值，
  /// 不单独分组就会与内容命中混在一起且次序不稳定。
  Future<SearchPage> _searchByMatch(SearchQuery query, SearchPlan plan) async {
    final String union = _matchUnionSql(query);
    final List<Variable<Object>> unionVars = _matchUnionVariables(query, plan);
    final List<QueryRow> ranked = await _db
        .customSelect(
          'SELECT article_id, rank, feed_only FROM ($union) '
          'ORDER BY src, feed_only, rank, article_id DESC LIMIT ? OFFSET ?',
          variables: <Variable<Object>>[
            ...unionVars,
            Variable<Object>(query.limit),
            Variable<Object>(query.offset),
          ],
        )
        .get();

    // 只对这一页的 id 取高亮片段（见上面的性能说明）。
    final List<int> pageIds = <int>[
      for (final QueryRow row in ranked) row.read<int>('article_id'),
    ];
    final Map<int, Map<String, String>> snippets = pageIds.isEmpty
        ? const <int, Map<String, String>>{}
        : await _snippetsFor(pageIds, plan);

    final QueryRow countRow = await _db
        .customSelect(
          'SELECT COUNT(*) AS c FROM ($union)',
          variables: unionVars,
        )
        .getSingle();

    return SearchPage(
      hits: <SearchHit>[
        for (final QueryRow row in ranked)
          _hitFromMatchRow(
            row,
            snippets[row.read<int>('article_id')] ?? const <String, String>{},
          ),
      ],
      total: countRow.read<int>('c'),
      offset: query.offset,
    );
  }

  /// 为给定的 [ids] 计算各字段的高亮片段。
  ///
  /// 用一次 IN 查询而不是逐条查：一页 50 条逐个往返是 50 次查询。snippet() 只能在带
  /// MATCH 的语句里调用，因此这里仍要起一次 MATCH 查询，但 WHERE 额外限定了 rowid
  /// 集合，参与高亮计算的只有这一页。
  Future<Map<int, Map<String, String>>> _snippetsFor(
    List<int> ids,
    SearchPlan plan,
  ) async {
    final String placeholders = List<String>.filled(ids.length, '?').join(', ');
    final List<QueryRow> rows = await _db
        .customSelect(
          'SELECT rowid AS rid, '
          'snippet(articles_fts, 0, char(1), char(2), $_snippetEllipsis, 12) AS s_title, '
          'snippet(articles_fts, 1, char(1), char(2), $_snippetEllipsis, 12) AS s_author, '
          'snippet(articles_fts, 2, char(1), char(2), $_snippetEllipsis, 12) AS s_summary, '
          'snippet(articles_fts, 3, char(1), char(2), $_snippetEllipsis, 12) AS s_body '
          'FROM articles_fts WHERE articles_fts MATCH ? AND rowid IN ($placeholders)',
          variables: <Variable<Object>>[
            Variable<Object>(plan.matchPhrase!),
            for (final int id in ids) Variable<Object>(id),
          ],
        )
        .get();
    return <int, Map<String, String>>{
      for (final QueryRow row in rows)
        row.read<int>('rid'): <String, String>{
          for (final String column in const <String>[
            's_title',
            's_author',
            's_summary',
            's_body',
          ])
            if (row.data[column] case final String text) column: text,
        },
    };
  }

  /// LIKE 路径。
  ///
  /// 不连 fts 子查询：LIKE 无法用 bm25 排序，连了也只得到一堆 null 列。直接查 articles，
  /// 片段在 Dart 侧截取（[snippetAround]）。
  Future<SearchPage> _searchByLike(SearchQuery query, SearchPlan plan) async {
    final String like = plan.likePattern!;
    final String scope = _scopeSql(query);
    final List<Variable<Object>> predicateVars = <Variable<Object>>[
      Variable<Object>(like),
      Variable<Object>(like),
      Variable<Object>(like),
      Variable<Object>(like),
      Variable<Object>(_feedNameLike(plan.normalized)),
      Variable<Object>(_feedNameLike(plan.normalized)),
      for (final Object? p in _scopeParams(query.feedId)) Variable<Object>(p),
    ];

    final QueryRow countRow = await _db
        .customSelect(
          'SELECT COUNT(*) AS c FROM articles a WHERE ${_likePredicate()}$scope',
          variables: predicateVars,
        )
        .getSingle();

    final List<QueryRow> rows = await _db
        .customSelect(
          'SELECT a.id AS article_id, a.title, a.author, a.summary, a.body '
          'FROM articles a WHERE ${_likePredicate()}$scope '
          'ORDER BY COALESCE(a.published_at, a.fetched_at) DESC, a.id DESC '
          'LIMIT ? OFFSET ?',
          variables: <Variable<Object>>[
            ...predicateVars,
            Variable<Object>(query.limit),
            Variable<Object>(query.offset),
          ],
        )
        .get();

    return SearchPage(
      hits: <SearchHit>[
        for (final QueryRow row in rows) _hitFromLikeRow(row, plan.normalized),
      ],
      total: countRow.read<int>('c'),
      offset: query.offset,
    );
  }

  /// MATCH 路径的合并查询（内容命中 UNION ALL 来源名命中）。
  ///
  /// 来源名分支里「排除已由内容分支收录的行」是必要的：一篇既内容命中、又来自匹配来源名
  /// 的文章会同时出现在两个分支里，不去重就会出现**同一条结果两遍**。这里用 UNION ALL
  /// 加显式排除，而不是 UNION：UNION 的隐式去重要额外排序整个结果集，而这个排除只作用于
  /// 来源名分支（命中行通常很少）。
  ///
  /// 来源名分支还要覆盖「已脱离订阅的收藏」：它们的 feed_id 为 NULL，join 不到 feeds，
  /// 来源名在 articles.feed_title 快照里——因此该分支的条件是
  /// 「feeds.name 命中 OR feed_title 快照命中」。
  static String _matchUnionSql(SearchQuery query) {
    final String scope = _scopeSql(query);
    return ''
        'SELECT a.id AS article_id, bm25(articles_fts) AS rank, '
        '0 AS feed_only, 0 AS src '
        'FROM articles a JOIN articles_fts ON articles_fts.rowid = a.id '
        'WHERE articles_fts MATCH ?$scope '
        'UNION ALL '
        'SELECT a.id AS article_id, NULL AS rank, 1 AS feed_only, 1 AS src '
        'FROM articles a '
        "WHERE (a.feed_title LIKE ? ESCAPE '$kLikeEscape' "
        'OR EXISTS (SELECT 1 FROM feeds fe WHERE fe.id = a.feed_id '
        "AND fe.name LIKE ? ESCAPE '$kLikeEscape')) "
        'AND a.id NOT IN (SELECT rowid FROM articles_fts '
        'WHERE articles_fts MATCH ?) '
        '$scope';
  }

  /// [_matchUnionSql] 的绑定参数（顺序必须与其中的问号一一对应）。
  static List<Variable<Object>> _matchUnionVariables(
    SearchQuery query,
    SearchPlan plan,
  ) {
    final List<Variable<Object>> scopeVars = <Variable<Object>>[
      for (final Object? p in _scopeParams(query.feedId)) Variable<Object>(p),
    ];
    return <Variable<Object>>[
      // 内容分支：MATCH 短语 + 范围参数。
      Variable<Object>(plan.matchPhrase!),
      ...scopeVars,
      // 来源名分支：快照列 LIKE、feeds.name LIKE、去重子查询的 MATCH 短语 + 范围参数。
      Variable<Object>(_feedNameLike(plan.normalized)),
      Variable<Object>(_feedNameLike(plan.normalized)),
      Variable<Object>(plan.matchPhrase!),
      ...scopeVars,
    ];
  }

  /// 来源名命中：现查 feeds.name（未脱离源）或行上的快照（已脱离源）。
  ///
  /// 与列表页显示来源名的规则**同一条**（见 ArticleListEntry.feedName 的说明），
  /// 因此不会出现「列表显示 A 源、按 A 源搜不到」。
  static String _feedNamePredicate() =>
      // ignore: prefer_single_quotes
      "(a.feed_title LIKE ? ESCAPE '$kLikeEscape' "
      'OR EXISTS (SELECT 1 FROM feeds fe WHERE fe.id = a.feed_id '
      "AND fe.name LIKE ? ESCAPE '$kLikeEscape'))";

  /// LIKE 路径的内容判定：四个可检索字段任一命中，或来源名命中。
  static String _likePredicate() =>
      // ignore: prefer_single_quotes
      "(a.title LIKE ? ESCAPE '$kLikeEscape' "
      "OR a.author LIKE ? ESCAPE '$kLikeEscape' "
      "OR a.summary LIKE ? ESCAPE '$kLikeEscape' "
      "OR a.body LIKE ? ESCAPE '$kLikeEscape' "
      'OR ${_feedNamePredicate()})';

  /// 范围与筛选（与列表的筛选共用同一条口径）。
  static String _scopeSql(SearchQuery query) {
    if (query.scope == SearchScope.all) {
      return '';
    }
    final StringBuffer buffer = StringBuffer(' AND ');
    switch (query.filter) {
      case ArticleFilter.all:
        buffer.write('1 = 1');
      case ArticleFilter.unread:
        // 只匹配 unread：later 有独立入口（与列表筛选同一条规则）。
        // 用枚举的 name 而不是字面量：库里存的文本与枚举名必须一致（见 reading_state
        // 列的 CHECK 约束），从枚举取值可以让这条一致性由类型系统兜住。
        buffer.write('a.reading_state = \'${ReadingState.unread.name}\'');
      case ArticleFilter.later:
        buffer.write('a.reading_state = \'${ReadingState.later.name}\'');
      case ArticleFilter.favorite:
        buffer.write('a.favorite = 1');
    }
    if (query.feedId != null) {
      buffer.write(' AND a.feed_id = ?');
    }
    return buffer.toString();
  }

  /// 范围 SQL 里的绑定参数（顺序必须与 [_scopeSql] 一致）。
  static List<Object?> _scopeParams(int? feedId) =>
      feedId == null ? const <Object?>[] : <Object?>[feedId];

  /// 从 MATCH 行组装一条结果。
  static SearchHit _hitFromMatchRow(
    QueryRow row,
    Map<String, String> snippetsByColumn,
  ) {
    final List<SearchSnippet> snippets = <SearchSnippet>[];
    void add(SearchField field, String column) {
      final String? raw = snippetsByColumn[column];
      if (raw == null || raw.isEmpty) {
        return;
      }
      final List<HighlightSegment> segments = parseHighlightMarkers(raw);
      if (segments.any((HighlightSegment s) => s.isMatch)) {
        // snippet() 的输出自带省略号（它按 token 截断并在两端插入我们给的省略符），
        // 因此不需要再标 truncated：标记已经在文本里。
        snippets.add(SearchSnippet(field: field, segments: segments));
      }
    }

    add(SearchField.title, 's_title');
    add(SearchField.author, 's_author');
    add(SearchField.summary, 's_summary');
    add(SearchField.body, 's_body');
    return SearchHit(
      articleId: row.read<int>('article_id'),
      snippets: snippets,
      rank: row.data['rank'] as double?,
    );
  }

  /// 从 LIKE 行组装一条结果（片段在 Dart 侧截取）。
  static SearchHit _hitFromLikeRow(QueryRow row, String query) {
    final List<SearchSnippet> snippets = <SearchSnippet>[];
    void add(SearchField field, String column) {
      final Object? raw = row.data[column];
      if (raw is! String) {
        return;
      }
      final SearchSnippet? snippet = snippetAround(
        text: raw,
        query: query,
        field: field,
      );
      if (snippet != null) {
        snippets.add(snippet);
      }
    }

    add(SearchField.title, 'title');
    add(SearchField.author, 'author');
    add(SearchField.summary, 'summary');
    add(SearchField.body, 'body');
    return SearchHit(
      articleId: row.read<int>('article_id'),
      snippets: snippets,
      // LIKE 没有排名概念：不是「排名为 0」，而是**没有**排名，因此为 null。
      rank: null,
    );
  }

  /// 来源名的 LIKE 模式。
  static String _feedNameLike(String text) => escapeLikePattern(text);

  static StorageError _storage(
    String operation,
    Object error,
    StackTrace stackTrace,
  ) => StorageError(
    operation: operation,
    // 只保留异常类型：sqlite 的原始文本可能带上语句与参数值（含用户查询词）。
    detail: error.runtimeType.toString(),
    cause: error,
    stackTrace: stackTrace,
  );
}
