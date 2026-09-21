// 解析产物 → 待入库项 的组装（T014 从 refresh_feed.dart 中抽出）。
//
// 为什么必须抽出来：T014 的「添加订阅」是**两步**的——先预览（抓取+解析，不写库），
// 用户确认后再入库。若把「规范化身份 → 清洗正文 → 组装 ArticleImport」留在刷新用例
// 内部，确认步骤只有两个选择：要么再抓一次（预览成功但确认时断网就会失败，用户看到
// 自己刚预览过的源「添加失败」），要么在添加用例里复制一份组装逻辑（两份身份/清洗
// 规则迟早漂移，而它们恰恰是最不能漂移的部分）。
//
// 因此这里只放**纯函数**：给定解析结果与目标 feedId，产出待入库项与统计。刷新用例、
// 添加用例、T015 的 OPML 导入都走同一条路径。
library;

import 'package:flux/core/core.dart';

import 'article_identity.dart';
import 'content_sanitizer.dart';
import 'feed_parser.dart';

/// 一次组装的结果。
class FeedImportBatch {
  /// 构造组装结果。
  const FeedImportBatch({
    required this.imports,
    required this.fetchedEntries,
    required this.rejectedEntries,
    required this.sanitizerLosses,
  });

  /// 待入库项（顺序与源内条目顺序一致）。
  final List<ArticleImport> imports;

  /// 源里解析出的条目数（含被跳过的）。
  final int fetchedEntries;

  /// 因缺少最小必需字段（标题与链接/标识都为空白）被跳过的条目数。
  final int rejectedEntries;

  /// 清洗过程中丢弃过内容的条目数（只记录数量，不记录内容）。
  final int sanitizerLosses;
}

/// 把一次解析结果组装成待入库项。
///
/// [feedIdentity] 参与兜底指纹，必须是**源级**稳定标识（用规范化后的订阅地址）；
/// 同一个 guid 在不同源里是不同的文章，因此不能省略。
FeedImportBatch buildFeedImportBatch({
  required int feedId,
  required ParsedFeed feed,
  required String feedIdentity,
  required DateTime fetchedAt,
  SanitizerLimits sanitizerLimits = const SanitizerLimits(),
}) {
  final List<NormalizedEntry> normalized = normalizeEntries(
    entries: feed.entries,
    feedIdentity: feedIdentity,
  );

  final List<ArticleImport> imports = <ArticleImport>[];
  int sanitizerLosses = 0;
  for (final NormalizedEntry entry in normalized) {
    final SanitizerReport report = sanitizeHtmlToDocument(
      entry.entry.contentHtml,
      limits: sanitizerLimits,
    );
    if (report.isLossy) {
      sanitizerLosses++;
    }
    imports.add(
      toArticleImport(
        feedId: feedId,
        entry: entry,
        report: report,
        fetchedAt: fetchedAt,
      ),
    );
  }

  return FeedImportBatch(
    imports: imports,
    fetchedEntries: feed.entries.length,
    rejectedEntries: feed.rejectedEntries,
    sanitizerLosses: sanitizerLosses,
  );
}

/// 把一个规范化条目 + 清洗结果组装成待入库项。
ArticleImport toArticleImport({
  required int feedId,
  required NormalizedEntry entry,
  required SanitizerReport report,
  required DateTime fetchedAt,
}) {
  final ParsedFeedEntry raw = entry.entry;
  // 正文 = 清洗后的受控文档的纯文本导出。用纯文本而不是 HTML 落库的原因：
  //   1) 「正文哈希变化 → 更新正文」需要一个**稳定**的修订判据，而未清洗的 HTML 里
  //      标签属性/空白/跟踪参数的微小变化会产生大量假修订；
  //   2) 受控文档树由渲染层按节点重建，落库只需要文本内容；
  //   3) 清洗已经把受控节点白名单化，不存在把原始 HTML 当权威的问题。
  final String? body = report.document.isEmpty
      ? null
      : docDocumentPlainText(report.document.children).trim();

  final bool hasSourceBody = body != null && body.isNotEmpty;
  // 完整性判定：有正文按「来源正文」，只有摘要按「摘要」。unknown 留给提取失败等
  // 尚未判定的情况（T024 的静态提取会产出 extracted）。
  final BodyCompleteness completeness = hasSourceBody
      ? BodyCompleteness.sourceBody
      : BodyCompleteness.summaryOnly;

  return ArticleImport(
    feedId: feedId,
    title: raw.title.isEmpty ? feedEntryFallbackTitle(raw) : raw.title,
    identityBasis: entry.identityBasis,
    guid: entry.guid,
    guidPresent: entry.guidPresent,
    normalizedLink: entry.normalizedLink,
    sourceUrl: entry.sourceUrl,
    fallbackFingerprint: entry.fallbackFingerprint,
    fingerprintReliability: entry.fingerprintReliability,
    author: raw.author,
    // 无日期用抓取时间：架构 4.1 要求「发布时间未知则使用抓取时间排序并注明」。
    // 注明的方式是把 publishedAt 置为 null、由界面对比 fetchedAt 判断，因此这里
    // **不**伪造 publishedAt——那会让「未知」变成「源声明的时刻」。
    publishedAt: raw.publishedAt,
    fetchedAt: fetchedAt,
    body: hasSourceBody ? body : null,
    bodyCompleteness: completeness,
    bodyHash: hasSourceBody ? bodyHashOf(body) : null,
    summary: feedEntrySummary(raw),
    imageUrl: feedEntryImageUrl(raw, report.document),
  );
}

/// 卡片的图片地址：优先源内 enclosure，其次正文里的第一张图。
///
/// 两个来源的顺序不是随意的：enclosure 是源**显式**声明的封面，而正文首图可能只是
/// 文章里的一张配图（甚至是一张表格截图）。有声明过的封面时用封面。
///
/// **两种来源都必须通过 [isSafeDocUrl]**：解析层虽然已经对正文里的图片跑过一次
/// 判定，但 enclosure 来自源文件里的另一个属性路径（见 feed_parser 的
/// _rssEnclosureImage），走过去的是另一段代码。在这里再判一次是**收口**：这一列
/// 之后会被卡片直接交给图片加载器，因此允许进入这一列的地址只认一种判定，那就是
/// 渲染层信任的同一个函数。
///
/// 返回 null 表示「这篇文章没有图」——架构第 7 节要求缺图不占位，因此 null 与
/// 「有图」是两种不同的卡片形态，不能用空串或占位地址代替。
String? feedEntryImageUrl(ParsedFeedEntry entry, DocDocument document) {
  final String? enclosure = entry.enclosureImageUrl;
  if (enclosure != null && isSafeDocUrl(enclosure)) {
    return enclosure;
  }
  for (final DocInline node in collectDocInlines(document)) {
    if (node is DocImageInline && isSafeDocUrl(node.url)) {
      return node.url;
    }
  }
  return null;
}

/// 无标题条目的兜底标题：用链接或日期构造，绝不留空。
///
/// 空标题在列表里会变成一行空白，用户无法判断那是什么；用链接至少可以识别。
String feedEntryFallbackTitle(ParsedFeedEntry entry) {
  final String? link = entry.link ?? entry.guid;
  if (link != null && link.isNotEmpty) {
    return link;
  }
  return '(无标题)';
}

/// 摘要：优先源内摘要，缺失时截取正文（架构 4.1：摘要优先源内摘要）。
String? feedEntrySummary(ParsedFeedEntry entry) {
  final String? summary = entry.summary;
  if (summary == null || summary.isEmpty) {
    return null;
  }
  // 源内摘要可能是 HTML：清洗成纯文本，避免列表里出现尖括号标签。
  final String plain = sanitizeHtmlToPlainText(summary);
  return plain.isEmpty ? null : plain;
}
