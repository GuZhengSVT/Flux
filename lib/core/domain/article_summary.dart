// 文章摘要与 AI 摘要的取值类型（T034；架构 4.2「原文始终保留」「缺摘要的 AI 自动生成
// 是开关，关闭时截取正文」，SET-037/064）。
//
// 三条刻意的设计：
//   1) **AI 摘要不是源摘要的替换**。两者来源不同（订阅内容 vs 模型生成），因此在类型上
//      也是两个字段，界面上各自标注。用一个字段加一个「是否 AI」的布尔会让「摘要是谁写的」
//      这件事依赖一个容易被漏判的开关；
//   2) **关闭自动摘要时的兜底是「截取正文」而不是「什么都不显示」**（SET-037）。兜底结果
//      明确标成截取，用户才知道它不是摘要；
//   3) **当天上限的计数是本机事实**（SET-064），只限制缺摘要的自动任务，手动摘要独立。
library;

/// 一条 AI 摘要（含生成元数据）。
final class AiSummaryRecord {
  /// 构造记录。
  const AiSummaryRecord({
    required this.text,
    required this.generatedAt,
    this.modelLabel,
  });

  /// 摘要文本。
  final String text;

  /// 生成时刻（UTC）。
  final DateTime generatedAt;

  /// 生成用的模型标识（`别名/模型ID`）；未知为 null。
  final String? modelLabel;

  /// 模型标识文本（界面标注用；未知时给出「未知模型」而不是空串）。
  String get modelLabelText => modelLabel == null || modelLabel!.isEmpty
      ? kUnknownSummaryModel
      : modelLabel!;
}

/// 模型标识未知时的展示文本。
const String kUnknownSummaryModel = '未知模型';

/// 卡片与详情页上「这段摘要从哪来」。
enum SummaryOrigin {
  /// 源内摘要（订阅内容）。
  source,

  /// AI 生成。
  ai,

  /// 关闭自动摘要时从正文截取（SET-037 的兜底）。
  excerpt,
}

/// 列表卡片要显示的那一段摘要（已决定来源）。
final class DisplaySummary {
  /// 构造结果。
  const DisplaySummary({required this.text, required this.origin});

  /// 文本。
  final String text;

  /// 来源。
  final SummaryOrigin origin;
}

/// 摘要截取的默认长度（SET-037 关闭时的兜底：截正文而不是不显示）。
const int kSummaryExcerptLength = 160;

/// 从正文截取一段摘要（SET-037 关闭或失败时的兜底）。
///
/// 在**字符边界**（rune）处切，不在 UTF-16 码元处切：切一半代理对会产生一个无效字符，
/// 而中文/emoji 在 UTF-16 里都是两个码元。截断处标省略号，让用户知道后面还有内容。
DisplaySummary? excerptSummaryFrom(
  String? body, {
  int limit = kSummaryExcerptLength,
}) {
  if (body == null || limit <= 0) {
    return null;
  }
  final String normalized = body.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (normalized.isEmpty) {
    return null;
  }
  final List<int> runes = normalized.runes.toList(growable: false);
  if (runes.length <= limit) {
    return DisplaySummary(text: normalized, origin: SummaryOrigin.excerpt);
  }
  final String cut = String.fromCharCodes(runes.take(limit));
  return DisplaySummary(text: '$cut…', origin: SummaryOrigin.excerpt);
}

/// 为列表/详情决定显示哪一段摘要（**不**做 IO）。
///
/// 优先级：AI 摘要 → 源摘要 → 关闭时截正文。顺序即「信息量」的下降顺序：AI 摘要通常
/// 最长且针对全文，源摘要次之，截取只是「让卡片不空着」。
DisplaySummary? resolveDisplaySummary({
  String? aiSummary,
  String? sourceSummary,
  String? body,
  bool allowExcerpt = true,
}) {
  final String? ai = aiSummary?.trim();
  if (ai != null && ai.isNotEmpty) {
    return DisplaySummary(text: ai, origin: SummaryOrigin.ai);
  }
  final String? source = sourceSummary?.trim();
  if (source != null && source.isNotEmpty) {
    return DisplaySummary(text: source, origin: SummaryOrigin.source);
  }
  return allowExcerpt ? excerptSummaryFrom(body) : null;
}

/// 当天自动摘要任务的计数与上限（SET-064）。
///
/// 为什么要一个显式对象而不是在批处理里读一个整数：上限是**资源边界**（架构 4.4
/// 「仅靠时间不能控制费用」），做成对象之后调用点无法「只看剩余不看上限」，测试也能用
/// 小额度确定性地验证「第 N+1 个被拒绝」。
final class DailySummaryQuota {
  /// 以当天已用数与上限构造。
  DailySummaryQuota({required this.limit, this.usedToday = 0}) {
    if (limit < 0) {
      throw ArgumentError.value(limit, 'limit', '不能为负');
    }
    if (usedToday < 0) {
      throw ArgumentError.value(usedToday, 'usedToday', '不能为负');
    }
  }

  /// 当天上限（SET-064：默认 50）。
  final int limit;

  /// 当天已用数。
  final int usedToday;

  /// 剩余额度（不为负）。
  int get remaining => usedToday >= limit ? 0 : limit - usedToday;

  /// 是否已用尽。
  bool get isExhausted => usedToday >= limit;

  /// 还能再跑几个（与 remaining 同义，命名更贴近调用点）。
  int get availableForBatch => remaining;

  /// 消耗 [count] 个额度，返回**实际可用**的数量（已用尽时为 0，不超发）。
  ///
  /// 返回实际数量而不是一个布尔：批处理需要知道「这一批能跑几个」，而「能不能跑」
  /// 在批次中途会变化（跑完一个就用掉一个）。
  int take(int count) =>
      count <= 0 ? 0 : (count > remaining ? remaining : count);
}
