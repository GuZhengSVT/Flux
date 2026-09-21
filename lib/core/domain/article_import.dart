// 文章导入数据契约（T009 定义于 infrastructure/local，T012/T013 提升到 core）。
//
// 为什么提升：T013 的解析与去重流程位于 features/feeds，它必须**产出**这些结构
// 并交给存储层；而 features 层不得 import infrastructure（由
// test/core/architecture_layering_test.dart 拦截）。把这组纯数据放在 core 之后，
// 解析层（features）与写入层（infrastructure）引用同一份定义，不会各自长出一套
// 形状接近但不兼容的 DTO。
//
// 这里的类型**只描述数据**：不含网络、不含业务决策、不依赖 Flutter 或 drift。
library;

import 'article_identity.dart';

/// 待导入的一篇文章（解析层产出的纯数据，不含网络与业务决策）。
class ArticleImport {
  /// 构造一条待导入文章。
  const ArticleImport({
    required this.feedId,
    required this.title,
    required this.identityBasis,
    this.guid,
    this.guidPresent = false,
    this.normalizedLink,
    this.sourceUrl,
    this.fallbackFingerprint,
    this.fingerprintReliability,
    this.author,
    this.publishedAt,
    this.fetchedAt,
    this.body,
    this.bodyCompleteness = BodyCompleteness.unknown,
    this.bodyHash,
    this.summary,
  });

  /// 目标订阅的本机 id。
  final int feedId;

  /// 标题。
  final String title;

  /// 本行实际采用的识别规则。
  final IdentityBasis identityBasis;

  /// 源内 GUID（可能为空串，此时由 [guidPresent] 区分「没给」与「给了空值」）。
  final String? guid;

  /// GUID 存在性标记。
  final bool guidPresent;

  /// 规范化链接（仅用于身份匹配）。
  final String? normalizedLink;

  /// 原始链接，保留全部查询参数。
  final String? sourceUrl;

  /// 兜底指纹（来源 + 标题 + 时间）。
  final String? fallbackFingerprint;

  /// 兜底指纹可靠度。
  final FingerprintReliability? fingerprintReliability;

  /// 作者。
  final String? author;

  /// 发布时间（UTC）；null 表示源未提供。
  final DateTime? publishedAt;

  /// 抓取时间（UTC）。
  final DateTime? fetchedAt;

  /// 正文（已清洗的受控文档来源文本）。
  final String? body;

  /// 正文完整性四态。
  final BodyCompleteness bodyCompleteness;

  /// 正文哈希：**只判修订**，不参与身份判定。
  final String? bodyHash;

  /// 源内摘要。
  final String? summary;

  /// 换一个目标订阅返回新的导入项。
  ///
  /// 用途：「添加订阅」是一条**先建订阅行、再写文章**的流程，而文章的身份派生值
  /// （指纹）在解析阶段就已经算好，此时还不知道数据库分配的 feed id。与其把
  /// 指纹重算一遍（那会引入第二份身份规则），不如让调用方在拿到 id 后重新绑定。
  ///
  /// 注意：只有 [feedId] 被替换，其余字段（含指纹与正文哈希）原样保留——它们都
  /// 是由**源标识**与内容决定的，与目标行的 id 无关。
  ArticleImport withFeedId(int feedId) => ArticleImport(
    feedId: feedId,
    title: title,
    identityBasis: identityBasis,
    guid: guid,
    guidPresent: guidPresent,
    normalizedLink: normalizedLink,
    sourceUrl: sourceUrl,
    fallbackFingerprint: fallbackFingerprint,
    fingerprintReliability: fingerprintReliability,
    author: author,
    publishedAt: publishedAt,
    fetchedAt: fetchedAt,
    body: body,
    bodyCompleteness: bodyCompleteness,
    bodyHash: bodyHash,
    summary: summary,
  );
}

/// 一次批量导入的结果计数（用于导入预览与诊断，不用于 UI 文案）。
class ArticleImportOutcome {
  /// 构造导入结果。
  const ArticleImportOutcome({
    required this.inserted,
    required this.updated,
    required this.bodyUpdated,
    required this.unchanged,
  });

  /// 新增文章数。
  final int inserted;

  /// 已存在且内容字段确有变化（不含阅读状态/收藏）。
  final int updated;

  /// 其中正文被替换（正文哈希变化）的数量，[updated] 的子集。
  final int bodyUpdated;

  /// 已存在且无内容变化（重复导入的典型结果）。
  final int unchanged;

  /// 本次导入涉及的既有文章数（[updated] + [unchanged]），便于诊断「全量未变」。
  int get matched => updated + unchanged;
}
