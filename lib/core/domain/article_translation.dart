// 分段全文翻译（T035；架构 4.2「译文与原文按段落关联，原文始终保留；超长翻译分段、
// 可取消，只重试失败段」，SET-011 的翻译目标语言，SET-061 的单材料预算）。
//
// 这一层只描述**事实与规则**，不做 IO、不碰网络：
//   1) 段落切分与回填**共用同一个遍历实现**（mapTranslation）。切分与回填各写一遍
//      遍历是最容易漂移的一处——两边的顺序或层级判断只要差一个分支，「第 3 段的译文」
//      就会画到第 4 段上，而译文看上去仍然是通顺的中文，用户无从察觉；
//   2) 译文与原文**分列存放**：ArticleTranslation 与源正文（articles.body）不是同一份
//      数据，回填只发生在渲染期，源正文列一个字都不动（架构 4.2「原文始终保留」）；
//   3) 段落级状态（translated / failed / pending）与源文本摘要一起落库，因此
//      「取消保留已完成段」「只重试失败段」「正文改了则译文过期」都不需要重新调模型。
library;

import '../digest/sha256.dart';
import '../result.dart';

import 'article_identity.dart';
import 'document_tree.dart';

/// 一个可翻译块在文档树里的角色。
///
/// 只列**承载文字**的三种块：标题、段落、列表项。代码块、公式、图片、分隔线、表格与
/// 未解析块不产生翻译单元——把代码或公式交给模型改写会把「原文照抄」变成一次静默的
/// 内容损坏（见 mapTranslation 的说明）。
enum TranslationBlockKind {
  /// 标题。
  heading,

  /// 段落（含引用块内部的段落）。
  paragraph,

  /// 列表项（层级由 TranslationUnit.level 表达）。
  listItem,
}

/// 单个段落译文的处理状态。
enum TranslationSegmentStatus {
  /// 尚未翻译（未开始、被取消，或本轮未选中）。
  pending,

  /// 已得到译文。
  translated,

  /// 本次尝试失败；可以只重试这一段。
  failed,
}

/// 一个翻译单元（切分结果，也是回填的定位依据）。
final class TranslationUnit {
  /// 构造单元。
  const TranslationUnit({
    required this.index,
    required this.path,
    required this.kind,
    required this.level,
    required this.sourceText,
    required this.sourceDigest,
  });

  /// 顺序号（与 TranslationSegment.index 一一对应）。
  ///
  /// 用顺序号而不是「块下标」：列表项与引用块内部的块没有稳定的顶层下标，而顺序号
  /// 对切分与回填是同一个含义。
  final int index;

  /// 到该块的下标路径（顶层块是 [i]，列表项内的段落是 [i, k, j]）。
  ///
  /// 路径只在本进程内用于回填定位，**不落库**：落库的是顺序号 + 源文本摘要。
  final List<int> path;

  /// 块角色。
  final TranslationBlockKind kind;

  /// 层级：标题是级别（1–6），列表项是嵌套深度（1–），段落实 0。
  final int level;

  /// 源文本（压平后的可见文字）。
  final String sourceText;

  /// 源文本摘要（段落级缓存键与「这一段改了吗」的判据）。
  final String sourceDigest;

  @override
  String toString() =>
      'TranslationUnit(#$index ${kind.name} L$level ${sourceText.length}ch)';
}

/// 一段译文及其状态。
final class TranslationSegment {
  /// 构造段落译文。
  const TranslationSegment({
    required this.index,
    required this.kind,
    required this.level,
    required this.sourceDigest,
    required this.sourceText,
    required this.status,
    this.translatedText,
    this.sourceTruncated = false,
  });

  /// 顺序号。
  final int index;

  /// 块角色。
  final TranslationBlockKind kind;

  /// 层级（标题级别 / 列表嵌套深度）。
  final int level;

  /// 源文本摘要。
  final String sourceDigest;

  /// 源文本（保留它，「原文始终保留」在数据层也成立：即使正文后来变了，
  /// 失败的那一段仍能显示当时发给模型的原文）。
  final String sourceText;

  /// 状态。
  final TranslationSegmentStatus status;

  /// 译文；status 不是 translated 时为 null。
  final String? translatedText;

  /// 源文本是否因超过单段预算而被截断（SET-061 的 8000 字符口径）。
  ///
  /// 截断必须被记下来：只翻译了前半段却把结果当作整段译文展示，是本任务最危险的
  /// 一种「看起来成功」。界面据此说明，用户才知道该去读原文的后半段。
  final bool sourceTruncated;

  /// 是否已有可显示的译文。
  bool get isTranslated =>
      status == TranslationSegmentStatus.translated &&
      (translatedText?.trim().isNotEmpty ?? false);

  /// 复制并覆盖部分字段。
  TranslationSegment copyWith({
    TranslationSegmentStatus? status,
    String? translatedText,
  }) => TranslationSegment(
    index: index,
    kind: kind,
    level: level,
    sourceDigest: sourceDigest,
    sourceText: sourceText,
    status: status ?? this.status,
    translatedText: translatedText ?? this.translatedText,
    sourceTruncated: sourceTruncated,
  );

  @override
  String toString() =>
      'TranslationSegment(#$index ${status.name} truncated=$sourceTruncated)';
}

/// 一篇文章某个目标语言的整份译文（T035 的独立结构）。
///
/// 为什么不是 articles 上的一个列：译文与源正文的**生命周期与失效判据都不同**——源正文
/// 变了译文就过期（sourceDigest），用户也可能同时保留中英两份译文。混进 articles 会
/// 让「源正文还在不在」与「译文对应哪一版正文」变得无从判断。
final class ArticleTranslation {
  /// 构造译文。
  const ArticleTranslation({
    required this.articleId,
    required this.targetLanguage,
    required this.sourceDigest,
    required this.segments,
    this.id,
    this.sourceLength = 0,
    this.modelLabel,
    this.createdAt,
    this.updatedAt,
  });

  /// 本机自增 id；尚未落库时为 null。
  final int? id;

  /// 文章 id。
  final int articleId;

  /// 目标语言（SET-011 的 translationTarget：zh-Hans / en）。
  final String targetLanguage;

  /// 翻译时所依据的源正文摘要（正文变了则整份译文过期）。
  final String sourceDigest;

  /// 源正文长度（字符数，用于界面说明）。
  final int sourceLength;

  /// 段落数组（顺序即文档顺序）。
  final List<TranslationSegment> segments;

  /// 产出译文的模型标识（别名/模型ID）；未知为 null。
  final String? modelLabel;

  /// 首次生成时刻（UTC）。
  final DateTime? createdAt;

  /// 最后更新时刻（UTC）。
  final DateTime? updatedAt;

  /// 已翻译段数。
  int get translatedCount =>
      segments.where((TranslationSegment s) => s.isTranslated).length;

  /// 失败段数。
  int get failedCount => segments
      .where(
        (TranslationSegment s) => s.status == TranslationSegmentStatus.failed,
      )
      .length;

  /// 未完成段数（取消或未开始）。
  int get pendingCount => segments.length - translatedCount - failedCount;

  /// 段落总数。
  int get totalCount => segments.length;

  /// 是否全部完成。
  bool get isComplete =>
      segments.isNotEmpty && pendingCount == 0 && failedCount == 0;

  /// 是否还有可重试的失败段。
  bool get hasFailed => failedCount > 0;

  /// 是否有段被截断（界面据此说明）。
  bool get hasTruncatedSource =>
      segments.any((TranslationSegment s) => s.sourceTruncated);

  /// 按顺序号取段；不存在时返回 null。
  TranslationSegment? segmentAt(int index) {
    for (final TranslationSegment segment in segments) {
      if (segment.index == index) {
        return segment;
      }
    }
    return null;
  }

  /// 与给定源正文摘要相比是否已过期。
  bool isStaleFor(String currentDigest) => sourceDigest != currentDigest;

  /// 复制并覆盖部分字段。
  ArticleTranslation copyWith({
    List<TranslationSegment>? segments,
    String? modelLabel,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? id,
  }) => ArticleTranslation(
    id: id ?? this.id,
    articleId: articleId,
    targetLanguage: targetLanguage,
    sourceDigest: sourceDigest,
    sourceLength: sourceLength,
    segments: segments ?? this.segments,
    modelLabel: modelLabel ?? this.modelLabel,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  @override
  String toString() =>
      'ArticleTranslation(article=$articleId lang=$targetLanguage '
      '$translatedCount/$totalCount failed=$failedCount)';
}

/// 一次切分（也是回填）的结果。
final class TranslationSplit {
  /// 构造结果。
  const TranslationSplit({required this.units, required this.document});

  /// 翻译单元（按文档顺序）。
  final List<TranslationUnit> units;

  /// 回填后的文档树（没有给译文时与源文档结构相同）。
  final DocDocument document;
}

/// 段落切分与回填的**唯一**实现。
///
/// translations 是「路径键 → 译文」（键是路径用点连接）；为空时本函数只做切分
/// （返回的 document 与源文档结构一致，因为未翻译的块原样返回）。
///
/// 切分规则（架构 4.2「译文与原文按段落关联」）：
///   * 标题、段落、列表项各为一个单元；引用块与列表**向下递归**，因此嵌套内容也被
///     逐段处理，而不是被压成一坨；
///   * 列表项内的段落按「列表项」计数（层级 = 嵌套深度），因此超长列表不会变成
///     一个巨大的段落；
///   * 代码块、公式、图片、分隔线、表格与未解析块**不产生单元**，原样保留。
///     理由：把代码或公式交给模型改写会静默损坏内容，而「表格逐格翻译」需要另一套
///     结构回填规则（属后续范围）；宁可少翻，不可翻错。
TranslationSplit mapTranslation(
  DocDocument source, {
  Map<String, String> translations = const <String, String>{},
}) {
  final List<TranslationUnit> units = <TranslationUnit>[];

  String keyOf(List<int> path) => path.join('.');

  List<DocInline> substitute(
    List<int> path,
    List<DocInline> inlines,
    TranslationBlockKind kind,
    int level,
  ) {
    final String text = docInlinePlainText(inlines).trim();
    units.add(
      TranslationUnit(
        index: units.length,
        path: path,
        kind: kind,
        level: level,
        sourceText: text,
        sourceDigest: translationDigestOf(text),
      ),
    );
    final String? translated = translations[keyOf(path)];
    if (translated == null || translated.trim().isEmpty) {
      return inlines;
    }
    // 回填成一个纯文本行内节点：译文的强调/链接边界与原文不一定对应，硬套原文的
    // 行内结构会让译文里出现指向错误的链接文字。
    return <DocInline>[DocText(translated)];
  }

  // 两个本地函数互相调用（列表要递归进项内的块，块要回到列表），而 Dart 的本地函数
  // 必须先声明后使用，因此用一个 late 变量把入口暴露给另一方。
  late DocNode Function(DocNode node, List<int> path, int listDepth) mapNode;

  List<DocNode> mapNodes(List<DocNode> nodes, List<int> prefix, int listDepth) {
    final List<DocNode> out = <DocNode>[];
    for (int i = 0; i < nodes.length; i++) {
      out.add(mapNode(nodes[i], <int>[...prefix, i], listDepth));
    }
    return out;
  }

  mapNode = (DocNode node, List<int> path, int listDepth) {
    switch (node) {
      case DocHeading(:final int level, :final List<DocInline> children):
        return DocHeading(
          level,
          substitute(path, children, TranslationBlockKind.heading, level),
        );
      case DocParagraph(:final List<DocInline> children):
        return DocParagraph(
          substitute(
            path,
            children,
            listDepth > 0
                ? TranslationBlockKind.listItem
                : TranslationBlockKind.paragraph,
            listDepth,
          ),
        );
      case DocBlockQuote(:final List<DocNode> children):
        return DocBlockQuote(mapNodes(children, path, listDepth));
      case DocList(
        :final bool ordered,
        :final List<DocListItem> items,
        :final int start,
      ):
        return DocList(
          ordered: ordered,
          start: start,
          items: <DocListItem>[
            for (int k = 0; k < items.length; k++)
              DocListItem(
                checked: items[k].checked,
                children: mapNodes(items[k].children, <int>[
                  ...path,
                  k,
                ], listDepth + 1),
              ),
          ],
        );
      default:
        // 代码块 / 公式 / 图片 / 分隔线 / 表格 / 未解析块：不产生单元，原样保留。
        return node;
    }
  };

  final List<DocNode> children = mapNodes(source.children, const <int>[], 0);
  return TranslationSplit(units: units, document: DocDocument(children));
}

/// 只做切分（不回填）。
List<TranslationUnit> splitTranslationUnits(DocDocument document) =>
    mapTranslation(document).units;

/// 把译文回填进文档树（未翻译的段显示原文）。
///
/// 找不到对应段（例如译文来自另一版正文）时该段保持原文——回填**从不**猜测段落。
DocDocument applyTranslation(
  DocDocument source,
  ArticleTranslation translation,
) {
  final TranslationSplit split = mapTranslation(source);
  final Map<String, String> texts = <String, String>{};
  for (final TranslationUnit unit in split.units) {
    final TranslationSegment? segment = translation.segmentAt(unit.index);
    if (segment == null || !segment.isTranslated) {
      continue;
    }
    texts[unit.path.join('.')] = segment.translatedText!;
  }
  return mapTranslation(source, translations: texts).document;
}

/// 段落文本摘要（段落级缓存键与「这一段改了吗」的判据）。
String translationDigestOf(String text) => sha256HexOfString(text);

/// 「为什么不做全文翻译」的原因标识（界面据此给不同文案）。
///
/// 住在 core 而不是 features：它与 [translationBlockReason] 是同一份规则的两种呈现，
/// 分开会让「判定返回的原因」与「界面认识的原因」漂移成两套字符串。
abstract final class TranslationSkipReason {
  /// 没有正文（源没给正文）。
  static const String noBody = 'noBody';

  /// 源只提供了摘要（架构 4.2：summaryOnly 不标全文，也不提供全文翻译）。
  static const String summaryOnly = 'summaryOnly';

  /// 没有可用的启用模型。
  static const String noModel = 'noModel';

  /// 目标语言不在 SET-011 的取值域内。
  static const String unsupportedLanguage = 'unsupportedLanguage';

  /// 文档里没有任何可翻译块（例如正文只有一张图）。
  static const String noTranslatableText = 'noTranslatableText';
}

/// 「能不能做全文翻译」的判定（纯函数；界面与用例共用同一份口径）。
///
/// 返回 null 表示可以翻译；否则返回 TranslationSkipReason 的取值。
///
/// 三条判定的顺序有意义：**summaryOnly 必须早于「有没有可翻译文字」**。源只提供摘要时，
/// 那段文字在形式上确实是一段可翻译的正文（有文字、也能被切成段落），因此它一定通得过
/// 后面那条判定；把摘要当全文翻译会把「摘要的译文」呈现成「全文的译文」——用户会以为
/// 读到了全文，而界面上没有任何线索。顺序反了就会让这条判定被永远掩盖。
String? translationBlockReason({
  required BodyCompleteness completeness,
  required bool hasBody,
  required bool hasTranslatableParagraphs,
}) {
  if (!hasBody) {
    return TranslationSkipReason.noBody;
  }
  if (completeness == BodyCompleteness.summaryOnly) {
    return TranslationSkipReason.summaryOnly;
  }
  if (!hasTranslatableParagraphs) {
    return TranslationSkipReason.noTranslatableText;
  }
  return null;
}

/// 单段源文本预算（SET-061：默认 8000 字符）。
///
/// 与单文摘要共用同一个数字口径，但**不共用代码**：摘要的截断是整篇一次，翻译是逐段
/// 判断「这一段是否超预算」，两者的调用点形状不同。
const int kTranslationSegmentCharBudget = 8000;

/// 按预算准备一段待翻译的文本（在**rune 边界**截断，不切坏代理对）。
final class TranslationSegmentInput {
  /// 构造结果。
  const TranslationSegmentInput({
    required this.text,
    required this.originalLength,
    required this.truncated,
  });

  /// 实际发送的文本。
  final String text;

  /// 截断前的字符数。
  final int originalLength;

  /// 是否发生过截断。
  final bool truncated;
}

/// 按 kTranslationSegmentCharBudget 准备单段文本。
///
/// 超长段**标截断而不分块**：分块会把用户的一次「翻译」变成不可预期的 N 次计费调用，
/// 而界面上的进度单位是「段」（与 T034 的单文摘要同一取舍）。
TranslationSegmentInput prepareTranslationSegment(
  String text, {
  int budget = kTranslationSegmentCharBudget,
}) {
  final List<int> runes = text.runes.toList(growable: false);
  if (budget <= 0 || runes.length <= budget) {
    return TranslationSegmentInput(
      text: text,
      originalLength: runes.length,
      truncated: false,
    );
  }
  return TranslationSegmentInput(
    text: String.fromCharCodes(runes.take(budget)),
    originalLength: runes.length,
    truncated: true,
  );
}

/// 译文的读写端口（存储实现住在 infrastructure）。
abstract interface class ArticleTranslationStore {
  /// 按「文章 + 目标语言」读取；不存在时返回 Ok(null)。
  Future<Result<ArticleTranslation?>> find({
    required int articleId,
    required String targetLanguage,
  });

  /// 写入（或整体覆盖）一份译文。
  ///
  /// 约定：本方法的实现**只写译文自己的结构**，不触碰 articles 的任何列——「原文始终
  /// 保留」因此是结构性的，而不是靠调用方记得别写错列。
  Future<Result<ArticleTranslation>> save(ArticleTranslation translation);

  /// 删除一篇文章的全部译文（用户主动清理）。
  Future<Result<void>> deleteAll(int articleId);
}
