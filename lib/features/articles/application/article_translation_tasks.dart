// 分段全文翻译的用例层（T035；架构 4.2「译文与原文按段落关联，原文始终保留；超长翻译
// 分段、可取消，只重试失败段」、SET-011 的翻译目标语言、SET-061 的单段预算、T030 的结果
// 缓存）。
//
// 这一层回答六件事，每一件都对应一条产品规则而不是实现细节：
//
//   1) **逐段调用**（并发上限 maxConcurrency，默认 1）。故障转移链本身就是串行的
//      （架构 4.5），而分段翻译里「并发 2」意味着同时有两条模型流在花钱；串行让进度
//      x/y 与计费顺序都是确定的，也让取消能在段边界干净地停下来；
//   2) **取消保留已完成段**：取消只停止后续段，已翻译的那些留在译文里（架构 4.2 的
//      「可取消」不等于「取消即丢弃」）；未完成的段在渲染时显示**原文**；
//   3) **部分成功**：单段失败不回滚整份译文，失败段标 failed 并可**单独重试**，
//      「重试失败段」只重跑失败的，不重跑全部（架构 4.2 的「只重试失败段」）；
//   4) **原文永远保留**：本层只产出 ArticleTranslation（独立结构），源正文列不出现
//      在任何写入里——「原文始终保留」是结构性的；
//   5) **段落级缓存**（T030 的 AiResultCache）：键 = 段落文本摘要 + 目标语言 + 模型，
//      命中时**一个请求都不发**，但该段落照样算作已完成；
//   6) **summaryOnly 不提供全文翻译**：只有摘要的正文没有「全文」可翻，本层直接返回
//      一个带原因的结论让界面标注「仅摘要」，而不是把摘要当成正文去翻。
library;

import 'package:flux/core/core.dart';

import 'package:flux/features/ai/application/ai_task_runner.dart';
import 'package:flux/features/ai/domain/ai_message.dart';
import 'package:flux/features/ai/domain/ai_model.dart';
import 'package:flux/features/ai/domain/ai_task_record.dart';
import 'package:flux/features/ai/domain/ai_task_store.dart';

/// 目标语言与翻译指令的取值域。
///
/// 只支持中英两种：SET-011 的 translationTarget 取值域就是 zh-Hans / en（SET 注册表与
/// 设置页都按这一份口径校验），因此这里不做「任意语言码都行」的宽松处理——宽松会让一句
/// 拼错的语言码变成一个静默的英文翻译。
enum TranslationLanguage {
  /// 简体中文。
  chinese(code: 'zh-Hans', displayName: '简体中文'),

  /// 英文。
  english(code: 'en', displayName: 'English');

  const TranslationLanguage({required this.code, required this.displayName});

  /// 稳定语言码（与 SET-011 的取值一致）。
  final String code;

  /// 界面显示名（提示词里用它说明目标语言，避免模型猜语言码的含义）。
  final String displayName;

  /// 由语言码还原；未知码返回 null（调用方按「目标语言无效」处理）。
  static TranslationLanguage? fromCode(String? code) {
    for (final TranslationLanguage value in TranslationLanguage.values) {
      if (value.code == code) {
        return value;
      }
    }
    return null;
  }
}

/// 一次翻译的产出（供界面渲染与落库）。
final class TranslationOutcome {
  /// 构造产出。
  const TranslationOutcome({
    this.translation,
    this.error,
    this.skippedReason,
    this.requestsIssued = 0,
    this.cacheHits = 0,
    this.cancelled = false,
  });

  /// 译文（含段落状态）；被跳过时为 null。
  final ArticleTranslation? translation;

  /// 失败原因（整份任务级；单段失败在段落状态里）。
  final AppError? error;

  /// 跳过原因（没有正文 / summaryOnly / 没有可用模型 / 目标语言无效）。
  final String? skippedReason;

  /// 本次真实发出的请求数（有用例用它断言缓存命中和取消时不再发请求）。
  final int requestsIssued;

  /// 命中的段落级缓存数。
  final int cacheHits;

  /// 是否被取消（已完成的段仍然落在 translation 里）。
  final bool cancelled;

  /// 是否产出了可显示的译文（哪怕只是部分）。
  bool get hasTranslation => translation != null;
}

/// 一次翻译的段级进度（界面显示「已完成 x/y 段」）。
final class TranslationProgress {
  /// 构造进度。
  const TranslationProgress({
    required this.translated,
    required this.failed,
    required this.total,
  });

  /// 已完成的段数（有可用译文的段）。
  final int translated;

  /// 失败的段数（可单独重试）。
  final int failed;

  /// 段落总数。
  final int total;

  /// 是否全部完成。
  bool get isComplete => total > 0 && translated + failed == total;
}

/// 分段全文翻译服务。
final class TranslationService {
  /// 构造服务。
  const TranslationService({
    required this.runner,
    required this.cache,
    required this.clock,
    this.diagnostics,
    this.segmentBudget = kTranslationSegmentCharBudget,
  });

  /// 任务队列（预算、五次规则、故障转移都在它里面）。
  final AiTaskRunner runner;

  /// 段落级结果缓存（T030）。
  final AiResultCache cache;

  /// 时钟。
  final Clock clock;

  /// 诊断（可空：本层不强制宿主提供日志端口）。
  final DiagnosticSink? diagnostics;

  /// 单段源文本预算（SET-061）。
  final int segmentBudget;

  /// 翻译一篇文档。
  ///
  /// articleId 只用于译文结构的归属与诊断；本方法**不写库**（写库由调用方通过
  /// ArticleTranslationStore 完成），因此「什么时候存」只有一处判断。
  ///
  /// summaryOnly 的文章**不提供全文翻译**：本层接受一个显式的 completeness，因此这条
  /// 规则只有一份实现（translationBlockReason），界面与批处理都走它；调用方忘了判，
  /// 这里也会拦下来。
  ///
  /// onlyFailed 非空时只重跑这些段的顺序号（「重试失败段」，不重跑全部）；
  /// 空集合表示**没有**要重试的段（调用方据此不发请求）。
  Future<TranslationOutcome> translate({
    required int articleId,
    required DocDocument document,
    required String targetLanguage,
    required List<AiModel> models,
    required String sourceDigest,
    required int sourceLength,
    BodyCompleteness completeness = BodyCompleteness.sourceBody,
    ArticleTranslation? existing,
    Set<int>? onlyFailed,
    AiCancellation? cancellation,
    void Function(TranslationProgress progress)? onProgress,
  }) async {
    final TranslationLanguage? language = TranslationLanguage.fromCode(
      targetLanguage,
    );
    if (language == null) {
      return const TranslationOutcome(
        skippedReason: TranslationSkipReason.unsupportedLanguage,
      );
    }
    if (models.isEmpty) {
      return TranslationOutcome(
        skippedReason: TranslationSkipReason.noModel,
        error: ProviderError(
          provider: '-',
          kind: 'noEnabledModel',
          detail: '没有可用的启用模型',
        ),
      );
    }
    final List<TranslationUnit> units = splitTranslationUnits(document);
    final String? blocked = translationBlockReason(
      completeness: completeness,
      hasBody: true,
      hasTranslatableParagraphs: units.isNotEmpty,
    );
    if (blocked != null) {
      return TranslationOutcome(skippedReason: blocked);
    }

    // 起点是「已有译文的那些段」：重试失败段因此天然只覆盖失败的那几段，已完成的段
    // 既不重跑也不丢（架构 4.2 的「只重试失败段」）。
    final Map<int, TranslationSegment> carried = <int, TranslationSegment>{
      if (existing != null)
        for (final TranslationSegment segment in existing.segments)
          if (segment.isTranslated && _unitDigestsMatch(units, segment))
            segment.index: segment,
    };

    final List<String> routeModelIds = <String>[
      for (final AiModel model in models) model.modelId,
    ];
    int requests = 0;
    int cacheHits = 0;
    bool cancelled = false;
    String? modelLabel;

    final List<TranslationSegment> resolved = <TranslationSegment>[];

    /// 每段落定后回报一次进度：界面据此显示「已完成 x/y 段」。
    ///
    /// 进度是**已完成的段数**，不含失败与未开始——它回答的是「现在能读到多少译文」，
    /// 而失败段在界面上另有入口（重试失败段），混进分子会让进度看起来虚高。
    void report() {
      int translated = 0;
      int failed = 0;
      for (final TranslationSegment segment in resolved) {
        if (segment.isTranslated) {
          translated++;
        } else if (segment.status == TranslationSegmentStatus.failed) {
          failed++;
        }
      }
      onProgress?.call(
        TranslationProgress(
          translated: translated,
          failed: failed,
          total: units.length,
        ),
      );
    }

    for (final TranslationUnit unit in units) {
      final TranslationSegment? done = carried[unit.index];
      if (done != null) {
        resolved.add(
          TranslationSegment(
            index: unit.index,
            kind: unit.kind,
            level: unit.level,
            sourceDigest: unit.sourceDigest,
            sourceText: unit.sourceText,
            status: TranslationSegmentStatus.translated,
            translatedText: done.translatedText,
          ),
        );
        report();
        continue;
      }
      final bool selected =
          onlyFailed == null || onlyFailed.contains(unit.index);
      if (!selected) {
        // 未被本轮选中（例如「只重试失败段」时那些从未开始过的段）：保持 pending，
        // 不参与进度分母的变化，也不被写成 failed。
        resolved.add(
          TranslationSegment(
            index: unit.index,
            kind: unit.kind,
            level: unit.level,
            sourceDigest: unit.sourceDigest,
            sourceText: unit.sourceText,
            status: TranslationSegmentStatus.pending,
          ),
        );
        report();
        continue;
      }
      if (cancellation != null && cancellation.isCancelled) {
        cancelled = true;
        resolved.add(
          TranslationSegment(
            index: unit.index,
            kind: unit.kind,
            level: unit.level,
            sourceDigest: unit.sourceDigest,
            sourceText: unit.sourceText,
            status: TranslationSegmentStatus.pending,
          ),
        );
        report();
        continue;
      }
      final TranslationSegmentInput prepared = prepareTranslationSegment(
        unit.sourceText,
        budget: segmentBudget,
      );
      final String cacheKey = translationCacheKey(
        prepared: prepared,
        unit: unit,
        language: language,
        routeModelIds: routeModelIds,
        modelId: models.first.modelId,
      );
      // ---- 段落级缓存：命中时一个请求都不发 --------------------------------
      final Result<AiResultCacheEntry?> hit = await cache.find(cacheKey);
      final AiResultCacheEntry? entry = hit.valueOrNull;
      if (entry != null && entry.text.trim().isNotEmpty) {
        cacheHits++;
        modelLabel ??= entry.providerAlias.isEmpty
            ? null
            : '${entry.providerAlias}/${entry.modelId}';
        resolved.add(
          TranslationSegment(
            index: unit.index,
            kind: unit.kind,
            level: unit.level,
            sourceDigest: unit.sourceDigest,
            sourceText: unit.sourceText,
            status: TranslationSegmentStatus.translated,
            translatedText: entry.text,
            sourceTruncated: prepared.truncated,
          ),
        );
        report();
        continue;
      }

      requests++;
      final AiTaskOutcome outcome = await runner.run(
        taskId: 'translate-$articleId-${unit.index}',
        request: AiRequest(
          modelId: models.first.modelId,
          messages: <AiMessage>[
            AiMessage.system(translationSystemPrompt(language)),
            AiMessage.user(buildTranslationUserMessage(prepared, unit)),
          ],
          cancellation: cancellation,
        ),
        models: models,
      );
      final bool ok =
          (outcome.status == TaskStatus.succeeded ||
              outcome.status == TaskStatus.partial) &&
          outcome.hasResult;
      if (!ok) {
        // 单段失败**不回滚**整份译文：标 failed，可单独重试（架构 4.2）。
        if (outcome.status == TaskStatus.cancelled) {
          cancelled = true;
          // 取消的那一段**不是失败**：它是「还没翻到」。标成 failed 会让界面提示
          // 「这一段失败了，请重试」，而真相是用户自己按了取消——两者对用户的含义
          // 完全不同（一个是网络/服务商的问题，一个是自己的操作）。
          resolved.add(
            TranslationSegment(
              index: unit.index,
              kind: unit.kind,
              level: unit.level,
              sourceDigest: unit.sourceDigest,
              sourceText: unit.sourceText,
              status: TranslationSegmentStatus.pending,
            ),
          );
          report();
          continue;
        }
        resolved.add(
          TranslationSegment(
            index: unit.index,
            kind: unit.kind,
            level: unit.level,
            sourceDigest: unit.sourceDigest,
            sourceText: unit.sourceText,
            status: TranslationSegmentStatus.failed,
            sourceTruncated: prepared.truncated,
          ),
        );
        report();
        continue;
      }
      final String text = outcome.text!;
      modelLabel ??= outcome.alias == null
          ? null
          : '${outcome.alias}/${outcome.modelId ?? ''}';
      // 只有**成功**的段落才写缓存（与 T030 同一纪律：失败不写缓存）。
      await cache.save(
        AiResultCacheEntry(
          key: cacheKey,
          text: text,
          providerAlias: outcome.alias ?? '',
          modelId: outcome.modelId ?? '',
          createdAt: clock.now(),
        ),
      );
      resolved.add(
        TranslationSegment(
          index: unit.index,
          kind: unit.kind,
          level: unit.level,
          sourceDigest: unit.sourceDigest,
          sourceText: unit.sourceText,
          status: TranslationSegmentStatus.translated,
          translatedText: text,
          sourceTruncated: prepared.truncated,
        ),
      );
      report();
    }

    final ArticleTranslation translation = ArticleTranslation(
      id: existing?.id,
      articleId: articleId,
      targetLanguage: targetLanguage,
      sourceDigest: sourceDigest,
      sourceLength: sourceLength,
      segments: resolved,
      modelLabel: modelLabel ?? existing?.modelLabel,
      createdAt: existing?.createdAt ?? clock.now(),
      updatedAt: clock.now(),
    );
    diagnostics?.info(
      '翻译完成 article=$articleId lang=$targetLanguage '
      'translated=${translation.translatedCount}/${translation.totalCount} '
      'failed=${translation.failedCount} requests=$requests '
      'cacheHits=$cacheHits cancelled=$cancelled',
      tag: 'ai.translate',
    );
    return TranslationOutcome(
      translation: translation,
      requestsIssued: requests,
      cacheHits: cacheHits,
      cancelled: cancelled,
    );
  }

  /// 已有译文段是否仍与当前正文的同一段对应。
  ///
  /// 用源文本摘要比对而不是顺序号：正文在两次翻译之间被刷新过时，顺序号可能仍然重合，
  /// 而那一刻的「第 3 段」已经是另一段文字——直接复用会把上一版正文的译文贴到新正文的
  /// 段上，而这种错位在界面上完全看不出来。
  static bool _unitDigestsMatch(
    List<TranslationUnit> units,
    TranslationSegment segment,
  ) {
    if (segment.index < 0 || segment.index >= units.length) {
      return false;
    }
    return units[segment.index].sourceDigest == segment.sourceDigest;
  }
}

/// 一段的段落级缓存键（T030 的 AiResultCacheKey 合成）。
///
/// 键里带上目标语言与整条路由模型链：换语言、换模型、换故障转移顺序都会得到新键，
/// 因此一个英文模型产出的段落不会被当成中文目标的译文复用（与 T030 同一口径）。
String translationCacheKey({
  required TranslationSegmentInput prepared,
  required TranslationUnit unit,
  required TranslationLanguage language,
  required List<String> routeModelIds,
  required String modelId,
}) {
  final List<AiMessage> messages = <AiMessage>[
    AiMessage.system(translationSystemPrompt(language)),
    AiMessage.user(buildTranslationUserMessage(prepared, unit)),
  ];
  return AiResultCacheKey.of(
    kind: AiTaskKind.translate,
    snapshot: AiInputSnapshot(
      messages: messages,
      modelId: modelId,
      language: language.code,
    ),
    routeModelIds: routeModelIds,
  ).value;
}

/// 翻译的系统提示词。
///
/// 三条要求都是产品边界而不是文风偏好：
///   * 「只翻译」——不加解释、不补充背景，否则译文里会混进模型自己写的话；
///   * 「保留专有名词」——人名/产品名/代码标识符被意译会让译文无法与原文对照；
///   * 「只输出译文」——带前缀（「译文：」）会让渲染出来的段落多出一层噪声。
String translationSystemPrompt(TranslationLanguage language) =>
    '你是翻译引擎。把用户给出的这一段文字翻译成${language.displayName}。'
    '只翻译，不要解释、不要补充原文没有的信息、不要总结。'
    '保留专有名词、产品名、人名与代码标识符的原有形式。'
    '直接输出译文，不要加任何前缀或说明。';

/// 拼装一段的用户消息（截断必须说明）。
String buildTranslationUserMessage(
  TranslationSegmentInput input,
  TranslationUnit unit,
) {
  final StringBuffer buffer = StringBuffer()
    ..writeln('待翻译的${translationBlockLabel(unit.kind)}：')
    ..writeln(input.text);
  if (input.truncated) {
    // 截断必须**说出来**：不说的话模型会把半段当成完整一段翻译，而用户看到的译文没有
    // 任何线索指向「原文本来就还有一半」。
    buffer.writeln(
      '（本段已截断：原文 ${input.originalLength} 字符，此处仅 '
      '${input.text.length} 字符。请不要据此补充原文没给出的内容。）',
    );
  }
  return buffer.toString();
}

/// 块角色的中文标签（进提示词，让模型知道这一段是标题还是列表项）。
String translationBlockLabel(TranslationBlockKind kind) => switch (kind) {
  TranslationBlockKind.heading => '标题',
  TranslationBlockKind.paragraph => '段落',
  TranslationBlockKind.listItem => '列表项',
};
