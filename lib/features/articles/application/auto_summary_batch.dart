// 缺摘要自动 AI 摘要（T034；SET-037「默认关，可开；关/失败时截正文」、SET-064「当天
// 自动摘要任务数 50；只限制缺摘要自动任务，手动独立确认」、架构 4.4「仅靠时间不能控制费用」）。
//
// 五条这里才成立的行为：
//   1) **开关默认关**：SET-037 关闭时**一次 AI 调用都不发起**（用请求计数断言），列表照常
//      显示（缺摘要的文章由调用方用截取正文兜底，见 core 的 resolveDisplaySummary）；
//   2) **只在刷新批处理中执行**：本服务是显式的 runBatch，不由滚动/渲染触发——滚动触发
//      会让「滑一下列表」变成一串计费调用，而用户完全不知道钱花在哪；
//   3) **当天上限是硬边界**（SET-064）：本批最多跑剩余额度那么多，且**每个**任务执行前重查
//      剩余（跨午夜、别的批处理刚跑过都要算进去）；
//   4) **走结果缓存**（T030）：同一篇正文重复请求命中缓存，命中时**一个请求都不发**；
//   5) **失败不写库、不标成功**：失败的候选留在「缺摘要」里，下次还能补；不把失败固化成
//      一条假摘要。
library;

import 'package:flux/core/core.dart';

import 'package:flux/features/ai/domain/ai_message.dart';
import 'package:flux/features/ai/domain/ai_model.dart';
import 'package:flux/features/ai/domain/ai_task_record.dart';
import 'package:flux/features/ai/domain/ai_task_store.dart';

import 'article_ai_text_tasks.dart';

/// 一次自动摘要批处理的产出（供界面与诊断说明「跑了几个、为什么停」）。
final class AutoSummaryBatchReport {
  /// 构造产出。
  const AutoSummaryBatchReport({
    required this.attempted,
    required this.succeeded,
    required this.failed,
    required this.fromCache,
    this.stoppedByQuota = false,
    this.disabled = false,
    this.error,
  });

  /// 尝试过的文章数。
  final int attempted;

  /// 成功写入 AI 摘要的文章数。
  final int succeeded;

  /// 失败的文章数（留在缺摘要里，下次可补）。
  final int failed;

  /// 命中结果缓存的文章数（没有发出请求）。
  final int fromCache;

  /// 是否因为当天额度用尽而停止（还有候选未处理）。
  final bool stoppedByQuota;

  /// 是否因为 SET-037 关闭而完全没有执行。
  final bool disabled;

  /// 批处理级失败（读候选/读额度失败）。
  final AppError? error;

  /// 是否真的做了事。
  bool get didWork => attempted > 0;
}

/// 当天自动摘要已用数的读写端口。
///
/// 单独一个端口而不是往 AiTaskStore 上加方法：这一项是**本机运行计数**（不是任务记录），
/// 与「任务历史」的生命周期不同（计数会按天重置，任务历史长期保留）。
abstract interface class DailySummaryCounter {
  /// 读取 [localDate]（设备当地日期键）当天的已用数；没有记录时返回 0。
  Future<Result<int>> readUsed(String localDate);

  /// 记录 [localDate] 当天又用了 [count] 个额度。
  Future<Result<void>> addUsed(String localDate, int count);
}

/// 缺摘要自动摘要批处理。
final class AutoSummaryBatchService {
  /// 构造服务。
  const AutoSummaryBatchService({
    required this.articles,
    required this.cache,
    required this.summary,
    required this.counter,
    required this.zone,
    required this.clock,
    required this.diagnostics,
  });

  /// 文章端口（挑候选与写 AI 摘要）。
  final ArticleCatalogStore articles;

  /// 结果缓存（命中时一个请求都不发）。
  final AiResultCache cache;

  /// 单文摘要服务。
  final ArticleSummaryService summary;

  /// 当天计数。
  final DailySummaryCounter counter;

  /// 会话/日期时区（设备当地日期，架构 4.4「日界线采用设备时区」）。
  final SessionLocalZone zone;

  /// 时钟。
  final Clock clock;

  /// 诊断。
  final DiagnosticSink diagnostics;

  /// 跑一批自动摘要。
  ///
  /// [enabled] 是 SET-037 的开关值（**默认关**：调用方必须显式传 true 才会执行，因此「忘了
  /// 判断开关」不会变成一次默认开启的计费行为）。
  /// [dailyLimit] 是 SET-064 的当天上限。
  /// [models] 是当前启用模型（自动摘要也用故障转移链）。
  Future<AutoSummaryBatchReport> runBatch({
    required bool enabled,
    required int dailyLimit,
    required List<AiModel> models,
    int? feedId,
    int limitPerRun = 5,
    AiCancellation? cancellation,
  }) async {
    if (!enabled) {
      // SET-037 默认关：这里**什么都不做**、也**一个请求都不发**。
      diagnostics.info('自动摘要未开启（SET-037 关闭），跳过批处理', tag: 'ai.summary');
      return const AutoSummaryBatchReport(
        attempted: 0,
        succeeded: 0,
        failed: 0,
        fromCache: 0,
        disabled: true,
      );
    }
    final String today = localDateKey(zone.toLocal(clock.now()));
    final Result<int> usedResult = await counter.readUsed(today);
    if (usedResult.isErr) {
      // 读不到计数时**不发请求**：额度是费用边界，读不到就按「不能确认还有额度」处理。
      return AutoSummaryBatchReport(
        attempted: 0,
        succeeded: 0,
        failed: 0,
        fromCache: 0,
        error: usedResult.errorOrNull,
      );
    }
    final int usedBefore = usedResult.valueOrNull!;
    final int quota = DailySummaryQuota(
      limit: dailyLimit,
      usedToday: usedBefore,
    ).availableForBatch;
    if (quota <= 0) {
      diagnostics.info(
        '自动摘要当天额度已用尽 today=$today limit=$dailyLimit',
        tag: 'ai.summary',
      );
      return const AutoSummaryBatchReport(
        attempted: 0,
        succeeded: 0,
        failed: 0,
        fromCache: 0,
        stoppedByQuota: true,
      );
    }

    final int batch = quota < limitPerRun ? quota : limitPerRun;
    final Result<List<int>> candidates = await articles
        .listArticlesMissingSummary(limit: batch, feedId: feedId);
    if (candidates.isErr) {
      return AutoSummaryBatchReport(
        attempted: 0,
        succeeded: 0,
        failed: 0,
        fromCache: 0,
        error: candidates.errorOrNull,
      );
    }
    final List<int> ids = candidates.valueOrNull!;
    int succeeded = 0;
    int failed = 0;
    int fromCache = 0;
    // 剩余额度是**成功次数**的边界（失败不扣额度），因此按成功递减而不是按尝试次数：
    // 按尝试次数递减会让「连着失败两次」把当天的额度提前用光，而用户什么都没拿到。
    int remaining = quota;
    for (final int articleId in ids) {
      if (cancellation != null && cancellation.isCancelled) {
        break;
      }
      if (remaining <= 0) {
        break;
      }
      final Result<String?> bodyResult = await articles.readArticleBody(
        articleId,
      );
      if (bodyResult.isErr) {
        failed++;
        continue;
      }
      final Result<AiSummaryRecord?> cached = await _cachedSummary(
        body: bodyResult.valueOrNull,
        models: models,
      );
      if (cached.valueOrNull case final AiSummaryRecord hit) {
        // 命中缓存：**一个请求都不发**，但仍要落库（这次文章确实有了 AI 摘要）。
        final Result<void> saved = await articles.saveAiSummary(
          articleId: articleId,
          summary: hit,
        );
        if (saved.isErr) {
          failed++;
        } else {
          fromCache++;
          succeeded++;
        }
        continue;
      }
      final ArticleSummaryOutcome outcome = await summary.summarize(
        taskId: 'auto-summary-$articleId',
        body: bodyResult.valueOrNull,
        models: models,
        cancellation: cancellation,
      );
      if (outcome.summary case final AiSummaryRecord record) {
        // 只有生成成功才写库并扣额度：失败**不写**（不把失败固化成一条假摘要），
        // 也**不扣**当天额度（用户没拿到东西）。
        await counter.addUsed(today, 1);
        remaining = DailySummaryQuota(
          limit: dailyLimit,
          usedToday: usedBefore + succeeded + 1,
        ).availableForBatch;
        final Result<void> saved = await articles.saveAiSummary(
          articleId: articleId,
          summary: record,
        );
        if (saved.isErr) {
          failed++;
        } else {
          succeeded++;
        }
      } else if (outcome.error != null) {
        failed++;
        diagnostics.warning(
          '自动摘要失败 article=$articleId kind=${outcome.error!.kind}',
          tag: 'ai.summary',
        );
      }
    }
    final int attempted = succeeded + failed;
    diagnostics.info(
      '自动摘要批处理完成 today=$today attempted=$attempted succeeded=$succeeded '
      'failed=$failed fromCache=$fromCache',
      tag: 'ai.summary',
    );
    return AutoSummaryBatchReport(
      attempted: attempted,
      succeeded: succeeded,
      failed: failed,
      fromCache: fromCache,
      stoppedByQuota: attempted < ids.length,
    );
  }

  /// 查一次结果缓存；未命中返回 Ok(null)（缓存读失败也按未命中）。
  Future<Result<AiSummaryRecord?>> _cachedSummary({
    required String? body,
    required List<AiModel> models,
  }) async {
    final SummaryBody prepared = prepareSummaryBody(body);
    if (prepared.isEmpty || models.isEmpty) {
      return const Ok<AiSummaryRecord?>(null);
    }
    final String key = AiResultCacheKey.of(
      kind: AiTaskKind.summary,
      snapshot: AiInputSnapshot(
        messages: <AiMessage>[
          const AiMessage.system(kArticleSummaryPrompt),
          AiMessage.user(buildSummaryUserMessage(prepared)),
        ],
        modelId: models.first.modelId,
      ),
      routeModelIds: <String>[
        for (final AiModel model in models) model.modelId,
      ],
    ).value;
    final Result<AiResultCacheEntry?> hit = await cache.find(key);
    if (hit.isErr || hit.valueOrNull == null) {
      return const Ok<AiSummaryRecord?>(null);
    }
    final AiResultCacheEntry entry = hit.valueOrNull!;
    return Ok<AiSummaryRecord?>(
      AiSummaryRecord(
        text: entry.text,
        generatedAt: entry.createdAt,
        modelLabel: entry.providerAlias.isEmpty
            ? null
            : '${entry.providerAlias}/${entry.modelId}',
      ),
    );
  }
}
