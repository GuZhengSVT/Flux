// 统一搜索结果结构（T031；架构 4.3「SearchProvider 统一结果结构」、
// 架构 4.4「引用只可使用真实获取的 sourceId，保存标题、URL、时间、最小摘录和材料哈希」）。
//
// 三家协议的响应**没有一处相同**：
//   Tavily  → results[{title, url, content, score, published_date}]
//   Brave   → web.results[{title, url, description, age}]，description 含 <b> 高亮标签
//   SearXNG → results[{title, url, content, publishedDate}]
// 若让上层消费这三家各自的形状，那么「引用校验」「材料哈希」「访问类别过滤」就要写三遍，
// 而三遍里必然有一遍先被改。因此这里定义**一个**结果形状，三个适配器各自负责翻译。
//
// 为什么 publishedAt 是可空且允许缺失：三家协议里只有 Tavily 的 published_date 与
// SearXNG 的 publishedDate 常见，Brave 只给一个相对时间字符串（如「3 days ago」）。
// 相对时间**不换算成绝对时刻**——换算需要抓取时刻作为基准，而这个基准不是协议事实，
// 猜出来的日期会被下游当作真实发布时间参与排序与展示。
library;

import 'package:flux/core/core.dart';

/// 结果的可访问类别（架构 4.3 的「访问类别」）。
///
/// 为什么要有这个分类而不是把三家结果混在一起：搜索 API 返回的东西性质不同——
/// 有的是一条新闻（带发布时间，适合做时间线），有的是一个文档/知识条目（无时间，
/// 适合做参考）。下游的「事件聚合/去重」与「引用标注」需要区分它们，否则一篇
/// 2019 年的文档会被当成今天的新闻。
enum SearchAccessCategory {
  /// 通用网页/知识条目（无明确时间性）。
  general,

  /// 技术资料（官方文档、代码仓库、问答站）。
  technical,

  /// 新闻（有发布时间，或来源域名属于常见新闻站）。
  news,
}

/// 一条统一的搜索结果。
final class SearchResult {
  /// 构造结果。
  const SearchResult({
    required this.sourceId,
    required this.title,
    required this.url,
    required this.snippet,
    required this.provider,
    required this.accessCategory,
    this.publishedAt,
    this.score,
    this.rank = 0,
  });

  /// 稳定的结果标识（协议标识 + 服务商返回序号的确定性摘要）。
  ///
  /// 为什么必须是**确定性摘要**而不是「按 URL」或「按标题」：
  ///   - 同一篇文章在不同检索里可能来自不同 URL（重定向、utm 参数、镜像站），
  ///     按 URL 会让同一篇内容拿到两个 sourceId，引用校验就会认为有两份独立证据；
  ///   - 服务商返回顺序稳定（同一查询同一次检索），把序号纳入哈希可以得到
  ///     「同一批结果里每条一个稳定 id」这一性质。
  ///
  /// 生成规则见 [searchResultSourceId]。
  final String sourceId;

  /// 标题（原样保留，不做「顺手清理」——标题是证据的一部分）。
  final String title;

  /// 网页地址（**已通过地址守卫**；不合格的地址在适配器与用例层被丢弃，不会到这里）。
  final String url;

  /// 片段（协议给的摘要；Brave 的 <b> 高亮标签已剥离）。
  final String snippet;

  /// 产出这条结果的服务协议（SearchProtocol.id）。
  final String provider;

  /// 访问类别。
  final SearchAccessCategory accessCategory;

  /// 发布时间（UTC）；协议未给出或只有相对时间时为 null。
  final DateTime? publishedAt;

  /// 服务商给出的相关度分数；协议未给出时为 null（不编造一个本地分数）。
  final double? score;

  /// 结果在本次检索里的序号（0 起）。
  final int rank;

  @override
  String toString() =>
      'SearchResult('
      '$sourceId, provider=$provider, category='
      '$accessCategory, title=${title.length} chars)';
}

/// 一次搜索的完整产出。
///
/// 为什么把 answer 与 results 分开而不是把答案塞进结果列表：答案没有 URL，把它混进
/// 列表会让「引用校验」面对一条永远无法核验的条目（架构 4.4 要求引用必须来自真实
/// 获取的材料）。分开之后，「有答案但没网页」与「有网页但没答案」在类型上就不同。
final class SearchResponse {
  /// 构造响应。
  const SearchResponse({
    required this.provider,
    required this.query,
    required this.results,
    this.answer,
    this.responseTime,
    this.totalResults,
  });

  /// 产出这次检索的协议标识。
  final String provider;

  /// 实际发出的查询词（用于诊断与「实际发送的查询符合本地规则」的核对）。
  final String query;

  /// 网页结果（顺序即服务商给出的相关度顺序）。
  final List<SearchResult> results;

  /// 服务商直接给出的答案摘要；未给出时为 null。
  ///
  /// **不是**一条可引用的网页：它没有地址。下游只能把它当参考，不能当证据。
  final String? answer;

  /// 服务商报告的耗时；未给出时为 null。
  final Duration? responseTime;

  /// 服务商报告的结果总数；未给出时为 null。
  ///
  /// 不把 results.length 伪装成总数：我们请求的只是前 N 条。
  final int? totalResults;
}

/// 计算一条结果的稳定 sourceId。
///
/// 组成：协议标识 + 结果序号。用**位置**而不是内容做输入，是因为服务商对同一次检索
/// 返回的顺序稳定，而内容会被服务商改写（摘要截断长度变化、高亮标签增删），
/// 用内容做输入会让同一篇材料在每次检索里换一个 id，历史引用随之全部失效。
String searchResultSourceId({required String provider, required int rank}) =>
    sha256HexOfString('flux.search|$provider|$rank').substring(0, 16);

/// 片段长度上限。
///
/// 单条片段最长 2000 字符。理由：片段会进 prompt 与引用摘录，而搜索服务偶尔会返回
/// 整页正文当摘要（Tavily 的 content 在某些页面上接近全文）。不设上限时一次 10 条
/// 结果就可能把单材料预算（SET-061 的 8000 字符）吃光，把一个「检索」任务变成一次
/// 意外的大额输入。
const int kSearchSnippetMaxLength = 2000;

/// 标题长度上限（防止一条畸形结果把界面撑坏）。
const int kSearchTitleMaxLength = 300;

/// 按上限截断文本（并去掉首尾空白）。
String clampSearchText(String text, int maxLength) {
  final String trimmed = text.trim();
  return trimmed.length <= maxLength
      ? trimmed
      : trimmed.substring(0, maxLength);
}
