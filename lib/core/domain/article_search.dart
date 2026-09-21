// 本地全库检索（T022；架构 4.2「本地全库搜索标题/作者/来源/摘要/已存正文，文章内
// 查找独立。SQLite FTS5 需实测中文 tokenizer；确定子串/词匹配语义」）。
//
// 本文件是**纯的**：检索请求/结果的数据形状、FTS5 查询串的构造、以及高亮的切片规则。
// 它们都必须能被纯 Dart 逐条断言，因为「搜得到什么」是本任务唯一的产品语义，
// 而把它埋在 SQL 字符串拼接里就只能靠真实库去撞。
//
// ## 实测确定的检索语义（先写探针跑出结论，再据此实现；结论同时记入手册 7.2）
//
// 索引是 fts5 + tokenize=trigram（见 infrastructure/local/tables/article_search.drift），
// 实测行为如下，**没有**假设成分：
//
//   1) 默认 tokenizer（unicode61）对中文不可用：整段中文是一个 token，
//      MATCH '离线' 与 MATCH '离' 都零命中。这就是本任务不能用默认值的原因。
//   2) trigram 下，连续 **≥3 个字符**的片段可用 MATCH 短语命中（中文与 ASCII 同理）。
//      少于 3 个字符的串在 trigram 索引里**不存在**，MATCH 一定零命中。
//   3) 任意长度都可用 LIKE 命中（子串语义），且 pattern ≥3 字符时 SQLite 会把 LIKE
//      下推到 trigram 索引；ASCII 大小写不敏感。
//
// 因此检索分两条路径，由 [SearchPlan] 决定（**这是本任务的核心决定**）：
//
//   * [SearchMode.match]：查询是 ≥3 字符的连续片段时用 MATCH 短语，按 bm25 排序，
//     高亮用 fts5 的 snippet()；
//   * [SearchMode.like]：其余情况（例如「AI」「离线」这样的 1–2 字查询）用 LIKE 子串
//     匹配，排序退回列表的既有次序（时间倒序），高亮由本文件的 [highlightText] 标注。
//
// 两条路径给界面的是**同一种**结果形状（[SearchHit] + [SearchSnippet]），因此界面不需要
// 知道走的是哪一条。语义也在两处都写作「子串匹配（大小写不敏感）」——这正是架构 4.2
// 要求的「语义确定」。

import '../error/app_error.dart';
import '../result.dart';

import 'article_catalog.dart';

/// 检索范围（架构 4.2 与列表的筛选口径一致）。
enum SearchScope {
  /// 全部文章（忽略列表当前的筛选）。
  all,

  /// 当前筛选（阅读状态/收藏 + 来源限定）。
  currentFilter,
}

/// 索引里的可检索字段。
///
/// 顺序即 fts5 建表里的列顺序，snippet() 的列号与它对应（见 [indexOfField]）。
enum SearchField {
  /// 标题。
  title,

  /// 作者。
  author,

  /// 摘要。
  summary,

  /// 正文。
  body,
}

/// [SearchField] 在 fts5 表里的列序号。
int indexOfField(SearchField field) => SearchField.values.indexOf(field);

/// 高亮片段：一段文本，以及它是否是命中的那一段。
class HighlightSegment {
  /// 构造片段。
  const HighlightSegment({required this.text, required this.isMatch});

  /// 文本。
  final String text;

  /// 是否命中（界面据此加粗/换底色）。
  final bool isMatch;

  @override
  bool operator ==(Object other) =>
      other is HighlightSegment &&
      other.text == text &&
      other.isMatch == isMatch;

  @override
  int get hashCode => Object.hash(text, isMatch);

  @override
  String toString() => isMatch ? '[$text]' : text;
}

/// 一处命中片段（某个字段上的一段带高亮的文本）。
class SearchSnippet {
  /// 构造片段。
  const SearchSnippet({
    required this.field,
    required this.segments,
    this.truncatedStart = false,
    this.truncatedEnd = false,
  });

  /// 来源字段。
  final SearchField field;

  /// 带高亮的文本分段。
  final List<HighlightSegment> segments;

  /// 片段前是否被省略（界面可加省略号）。
  final bool truncatedStart;

  /// 片段后是否被省略。
  final bool truncatedEnd;

  /// 拼接成纯文本（高亮段不带标记），用于测试与无障碍朗读。
  String get plainText => segments.map((HighlightSegment s) => s.text).join();

  /// 是否含命中段。
  bool get hasMatch => segments.any((HighlightSegment s) => s.isMatch);
}

/// 一条检索结果。
class SearchHit {
  /// 构造结果。
  const SearchHit({required this.articleId, required this.snippets, this.rank});

  /// 文章 id（列表/详情用它取整行——检索只产出 id 与片段，不重复查询整行）。
  final int articleId;

  /// 命中片段（按字段顺序，只含真正命中的字段）。
  final List<SearchSnippet> snippets;

  /// 相关性（bm25；MATCH 路径才有，越小越相关）。LIKE 路径为 null。
  final double? rank;

  /// 命中字段集合。
  Set<SearchField> get matchedFields =>
      snippets.map((SearchSnippet s) => s.field).toSet();
}

/// 一页检索结果。
class SearchPage {
  /// 构造一页。
  const SearchPage({
    required this.hits,
    required this.total,
    required this.offset,
  });

  /// 本页结果。
  final List<SearchHit> hits;

  /// 命中总数（分页控件与「无结果」判断用它，不用本页长度猜）。
  final int total;

  /// 本页起始偏移。
  final int offset;

  /// 是否还有下一页。
  bool get hasMore => offset + hits.length < total;

  /// 是否无结果。
  bool get isEmpty => hits.isEmpty;
}

/// 一次检索请求。
class SearchQuery {
  /// 构造请求。
  const SearchQuery({
    required this.text,
    this.scope = SearchScope.all,
    this.filter = ArticleFilter.all,
    this.feedId,
    this.offset = 0,
    this.limit = 50,
  });

  /// 查询词（原样，未清洗；构造 SQL 时由本文件的纯函数处理）。
  final String text;

  /// 范围。
  final SearchScope scope;

  /// 范围是「当前筛选」时生效的筛选。
  final ArticleFilter filter;

  /// 范围是「当前筛选」时生效的来源限定。
  final int? feedId;

  /// 偏移。
  final int offset;

  /// 每页数量。
  final int limit;

  /// 换页。
  SearchQuery atPage(int newOffset) => SearchQuery(
    text: text,
    scope: scope,
    filter: filter,
    feedId: feedId,
    offset: newOffset,
    limit: limit,
  );
}

/// 检索路径。
enum SearchMode {
  /// 用 fts5 的 MATCH（查询是 ≥3 字符的连续片段）。
  match,

  /// 用 LIKE 子串匹配（其余情况）。
  like,
}

/// 一次检索的执行计划（纯函数算出来，可直接断言）。
class SearchPlan {
  /// 构造计划。
  const SearchPlan({
    required this.mode,
    required this.normalized,
    this.matchPhrase,
    this.likePattern,
  });

  /// 走哪条路径。
  final SearchMode mode;

  /// 归一化后的查询词（去首尾空白、折叠内部空白）。
  final String normalized;

  /// MATCH 路径的短语（已加引号并转义内部引号）。
  final String? matchPhrase;

  /// LIKE 路径的模式（已转义 % 与 _，含前后的 %）。
  final String? likePattern;
}

/// trigram tokenizer 的分段长度。
const int kTrigramLength = 3;

/// 按实测语义为 [text] 选定执行计划。
///
/// 规则（每条都对应文件顶部的实测结论）：
///   * 空查询（去空白后为空）→ 返回 null，调用方给空态，而不是把空串当成「匹配一切」；
///   * 查询是一段 ≥3 字符的连续文本 → MATCH；否则 → LIKE。
///
/// 为什么限定「一段连续文本」而不是只看整串长度：trigram 切的是连续字符窗口，一个被
/// 空白切开的查询（例如「AI 与 离线」各段都 <3）用 MATCH 会要求这些片段在原文里连续
/// 出现，与用户「这几个词都要有」的预期不符，且实测命中不了任何东西。交给 LIKE 是能
/// 保证结果正确的选择。
SearchPlan? planSearch(String text) {
  // 顺序要紧：先折叠再 trim。反过来（先 trim 再折叠）会让内部的多个空白变成**一个**
  // 空格后仍然保留在两端——例如 '  a  b  ' 会得到 ' a b '，那个首尾空格会让
  // isSingleRun 误判为「多段查询」而把本可 MATCH 的查询降级到 LIKE。
  final String normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (normalized.isEmpty) {
    return null;
  }
  final bool usableForMatch =
      isSingleRun(normalized) && normalized.length >= kTrigramLength;
  if (!usableForMatch) {
    return SearchPlan(
      mode: SearchMode.like,
      normalized: normalized,
      likePattern: escapeLikePattern(normalized),
    );
  }
  return SearchPlan(
    mode: SearchMode.match,
    normalized: normalized,
    matchPhrase: ftsPhrase(normalized),
  );
}

/// [text] 是否是一段连续文本（不含空白）。
bool isSingleRun(String text) => !text.contains(' ');

/// 把 [text] 包成一个 fts5 短语串。
///
/// 加引号有两个作用，缺一不可：
///   1) **防注入**：查询来自用户输入，而 fts5 的 MATCH 参数是一门小语言
///      （AND/OR/NEAR/*/^/括号/列名 col: 都有语义）。实测把用户输入原样送进 MATCH 会直接
///      抛语法错误（例如输入一个引号加 OR），既拿不到结果也可能改变查询含义。
///      包成短语后，其中所有字符都按字面量处理；
///   2) **子串语义**：trigram 下短语匹配即「这段连续字符要出现」，正是我们要的语义。
///
/// 短语内部的引号用**双写**转义（fts5 的规则，与 SQL 字符串的转义是两回事）。
String ftsPhrase(String text) => '"${text.replaceAll('"', '""')}"';

/// 把 [text] 转成 LIKE 模式（子串匹配；大小写不敏感由 SQL 的 LIKE 默认提供）。
///
/// 转义 %、_ 与转义符自身（反斜杠）：不转义时，用户输入一个 % 会变成「匹配任意串」，
/// 于是一次检索返回全库——这是实测最容易忽略的一类输入。调用方必须同时声明
/// ESCAPE 子句，否则转义符本身没有意义。
String escapeLikePattern(String text) {
  final String escaped = text
      .replaceAll(r'\', r'\\')
      .replaceAll('%', r'\%')
      .replaceAll('_', r'\_');
  return '%$escaped%';
}

/// 片段高亮的哨兵标记。
///
/// 用不可见控制字符而不是方括号：正文里本来就可能出现方括号（代码、引用、链接文字），
/// 用可见字符做标记会让「解析高亮」变成一件需要猜测的事。控制字符在剥掉标记后不会
/// 污染原文。
const String kHighlightStart = '\u0001';
const String kHighlightEnd = '\u0002';

/// 省略号。
const String kSnippetEllipsis = '…';

/// 把带哨兵标记的文本解析成高亮分段。
///
/// 纯函数，把「SQL 与 Dart 之间传递高亮的字符串协议」变成一个可断言的结构；
/// 未闭合的起始标记按字面量保留（宁可显示一个控制字符，也不静默丢字）。
List<HighlightSegment> parseHighlightMarkers(String marked) {
  final List<HighlightSegment> segments = <HighlightSegment>[];
  int index = 0;
  while (index < marked.length) {
    final int start = marked.indexOf(kHighlightStart, index);
    if (start == -1) {
      if (index < marked.length) {
        segments.add(
          HighlightSegment(text: marked.substring(index), isMatch: false),
        );
      }
      break;
    }
    if (start > index) {
      segments.add(
        HighlightSegment(text: marked.substring(index, start), isMatch: false),
      );
    }
    final int end = marked.indexOf(kHighlightEnd, start + 1);
    if (end == -1) {
      // 未闭合：把标记与剩余内容都当普通文本，不丢字。
      segments.add(
        HighlightSegment(text: marked.substring(start + 1), isMatch: false),
      );
      break;
    }
    segments.add(
      HighlightSegment(text: marked.substring(start + 1, end), isMatch: true),
    );
    index = end + 1;
  }
  return segments;
}

/// 在 [text] 里高亮 [query] 的全部出现（大小写不敏感的子串匹配）。
///
/// 这是 LIKE 路径的高亮实现：snippet() 只在 MATCH 下输出标记（实测 LIKE 下原样返回、
/// 完全不标注），因此短查询必须由应用层标注。语义与 MATCH 路径保持一致：都是子串、
/// 都大小写不敏感。
List<HighlightSegment> highlightText(String text, String query) {
  if (text.isEmpty || query.isEmpty) {
    return <HighlightSegment>[HighlightSegment(text: text, isMatch: false)];
  }
  final String haystack = text.toLowerCase();
  final String needle = query.toLowerCase();
  final List<HighlightSegment> segments = <HighlightSegment>[];
  int index = 0;
  while (true) {
    final int found = haystack.indexOf(needle, index);
    if (found == -1) {
      if (index < text.length) {
        segments.add(
          HighlightSegment(text: text.substring(index), isMatch: false),
        );
      }
      break;
    }
    if (found > index) {
      segments.add(
        HighlightSegment(text: text.substring(index, found), isMatch: false),
      );
    }
    segments.add(
      HighlightSegment(
        text: text.substring(found, found + needle.length),
        isMatch: true,
      ),
    );
    index = found + needle.length;
  }
  return segments.isEmpty
      ? <HighlightSegment>[HighlightSegment(text: text, isMatch: false)]
      : segments;
}

/// 从 [text] 里截一段**围绕首个命中**的上下文（LIKE 路径的 snippet 等价物）。
///
/// [contextChars] 是命中处前后各保留的字符数（按**字符**计，不是词——中文一个字就是一个
/// 字符，按词计会让中文片段短得看不出上下文）。截断处由 [truncatedStart] /
/// [truncatedEnd] 如实标出，界面据此显示省略号，而不是假装这段就是全文开头。
SearchSnippet? snippetAround({
  required String text,
  required String query,
  required SearchField field,
  int contextChars = 30,
}) {
  if (text.isEmpty || query.isEmpty) {
    return null;
  }
  final int found = text.toLowerCase().indexOf(query.toLowerCase());
  if (found == -1) {
    return null;
  }
  final int start = (found - contextChars).clamp(0, text.length);
  final int end = (found + query.length + contextChars).clamp(0, text.length);
  return SearchSnippet(
    field: field,
    segments: highlightText(text.substring(start, end), query),
    truncatedStart: start > 0,
    truncatedEnd: end < text.length,
  );
}

/// 校验一次检索请求。
///
/// 与列表分页同一条理由（见 validateArticleQuery）：limit 为 0 会让结果**永久显示为
/// 空**且没有任何错误，是最难排查的一类问题，因此必须返回类型化失败而不是靠 assert。
Result<void> validateSearchQuery(SearchQuery query) {
  if (query.offset < 0) {
    return Err<void>(
      ValidationError(field: 'searchQuery.offset', reason: '偏移不能为负'),
    );
  }
  if (query.limit <= 0) {
    return Err<void>(
      ValidationError(field: 'searchQuery.limit', reason: '每页数量必须为正'),
    );
  }
  return const Ok<void>(null);
}

/// 全库检索端口。
///
/// 为什么与 ArticleCatalogStore 分开：那个端口服务**列表浏览**（按时间分页、按三态
/// 筛选），本端口服务**检索**（子串匹配、片段高亮、按相关性排序）。合成一个会让列表
/// 的每个调用点都多一个「要不要传查询词」的分支，也会让检索的高亮能力渗透到列表实现里。
abstract interface class ArticleSearchPort {
  /// 执行一次检索。
  Future<Result<SearchPage>> search(SearchQuery query);

  /// 重建全文索引（损坏恢复与升级后的补建；幂等）。
  Future<Result<int>> rebuildIndex();
}
