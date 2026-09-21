// 检索用例（T022；架构 4.2 的 F-SEARCH）。
//
// 这一层只做三件存储层不该做的事：
//   1) **把「范围」翻译成存储层的参数**（全部 / 当前筛选），页面不必自己拼；
//   2) **把片段贴在整行数据上**：存储层只产出 id 与片段，列表卡片需要标题/来源/时间，
//      因此这里按 id 批量取回整行再与片段合并。用一次批量查询而不是逐条查——一页 50 条
//      逐个查就是 50 次往返；
//   3) **保住既有次序**：存储层按相关性（或时间）给出 id 顺序，合并整行后**必须**保持
//      那个顺序。用 map 查出来的行按 id 排序的话，相关性排序会被静默丢掉——那时界面
//      看起来「搜到了」，只是最相关的排到了中间。
//
// 为什么不用 ArticleListController 已有的列表读取：那个端口按筛选分页、不认识查询词，
// 也没有「按相关性排序」的入口。硬塞进去会让列表的每个调用点都要回答「这次是不是检索」。
library;

import 'package:flux/core/core.dart';

/// 一条检索结果（片段 + 整行）。
class ArticleSearchResult {
  /// 构造结果。
  const ArticleSearchResult({required this.entry, required this.hit});

  /// 列表卡片需要的整行数据（标题/来源/时间/状态）。
  final ArticleListEntry entry;

  /// 检索产出的命中片段与排名。
  final SearchHit hit;

  /// 文章 id（转发给 hit，页面用它打开详情）。
  int get articleId => hit.articleId;
}

/// 一页检索结果。
class ArticleSearchPage {
  /// 构造一页。
  const ArticleSearchPage({
    required this.results,
    required this.total,
    required this.offset,
  });

  /// 本页结果（已按存储层给的次序排列）。
  final List<ArticleSearchResult> results;

  /// 命中总数。
  final int total;

  /// 本页偏移。
  final int offset;

  /// 是否还有下一页。
  bool get hasMore => offset + results.length < total;

  /// 是否无结果。
  bool get isEmpty => results.isEmpty;
}

/// 检索用例。
class SearchArticlesUseCase {
  /// 构造用例。
  const SearchArticlesUseCase({required this.search, required this.articles});

  /// 检索端口。
  final ArticleSearchPort search;

  /// 整行读取端口（按 id 批量取）。
  final ArticleCatalogStore articles;

  /// 执行一次检索。
  ///
  /// 返回的 [Result] 只在**读取失败**时是 Err；「查无结果」是 Ok 的空页——
  /// 两者在界面上是完全不同的状态（一个是错误可重试，一个是「没有匹配」）。
  Future<Result<ArticleSearchPage>> call(SearchQuery query) async {
    final Result<SearchPage> found = await search.search(query);
    if (found.isErr) {
      return Err<ArticleSearchPage>(found.errorOrNull!);
    }
    final SearchPage page = found.unwrap();
    if (page.hits.isEmpty) {
      return Ok<ArticleSearchPage>(
        ArticleSearchPage(
          results: const <ArticleSearchResult>[],
          total: page.total,
          offset: page.offset,
        ),
      );
    }

    final Result<List<ArticleListEntry>> rows = await articles.findArticles(
      page.hits.map((SearchHit h) => h.articleId).toList(growable: false),
    );
    if (rows.isErr) {
      return Err<ArticleSearchPage>(rows.errorOrNull!);
    }
    // 以存储层的 id 次序重建列表：findArticles 返回的是它自己的排序（id 倒序），
    // 直接 zip 会把相关性与时间序都打乱。
    final Map<int, ArticleListEntry> byId = <int, ArticleListEntry>{
      for (final ArticleListEntry entry in rows.unwrap()) entry.id: entry,
    };
    final List<ArticleSearchResult> results = <ArticleSearchResult>[
      for (final SearchHit hit in page.hits)
        // 取不到整行的命中直接跳过：文章可能在检索与取行之间被删除，那种情况下
        // 给出一条没有标题的结果比少一条更糟（界面会显示一个空卡片）。
        if (byId[hit.articleId] case final ArticleListEntry entry)
          ArticleSearchResult(entry: entry, hit: hit),
    ];
    return Ok<ArticleSearchPage>(
      ArticleSearchPage(
        results: results,
        // total 用存储层的值而不是 results.length：本页可能因为上面的跳过而变短，
        // 但「命中总数」不该因此改变（那会让分页算错，出现永远翻不到的那一页）。
        total: page.total,
        offset: page.offset,
      ),
    );
  }
}
