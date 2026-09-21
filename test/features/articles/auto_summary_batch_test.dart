// T034：缺摘要自动摘要批处理（SET-037 关时零调用 / SET-064 当天上限 / 缓存命中 / 不覆盖源摘要）。
//
// 这一组用例盯的是「钱会不会在自己不知道的情况下花掉」：
//   - SET-037 关闭时**一个请求都不发**（用请求计数断言）；
//   - 当天额度用尽后不再发起（SET-064 是硬边界，不是提示）；
//   - 命中结果缓存时**一个请求都不发**但仍落库；
//   - 失败**不写库**（不把失败固化成一条假摘要）；
//   - AI 摘要写的是 ai_summary 三列，**源摘要不动**。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:flux/core/core.dart';
import 'package:flux/features/ai/application/ai_task_budget.dart';
import 'package:flux/features/ai/application/ai_task_runner.dart';
import 'package:flux/features/ai/domain/ai_model.dart';
import 'package:flux/features/ai/domain/ai_protocol.dart';
import 'package:flux/features/articles/application/article_ai_text_tasks.dart';
import 'package:flux/features/articles/application/auto_summary_batch.dart';

import '../ai/ai_runner_support.dart';
import 'summary_test_support.dart';

void main() {
  late FakeClock clock;
  late RecordingSink sink;
  late ScriptedAiFactory factory;
  late FakeSummaryArticleStore articles;
  late FakeResultCache cache;
  late FakeDailySummaryCounter counter;

  setUp(() {
    clock = FakeClock(start: DateTime.utc(2026, 9, 22, 4));
    sink = RecordingSink();
    factory = ScriptedAiFactory(<String, List<AiAttemptScript>>{
      'main': <AiAttemptScript>[
        const ScriptSuccess(deltas: <String>['摘', '要']),
      ],
    });
    articles = FakeSummaryArticleStore();
    cache = FakeResultCache();
    counter = FakeDailySummaryCounter();
  });

  AiModel model() => const AiModel(
    alias: 'main',
    protocol: AiProtocol.openAiChatCompletions,
    baseUrl: 'https://main.example.com',
    modelId: 'main-model',
  );

  AutoSummaryBatchService service() => AutoSummaryBatchService(
    articles: articles,
    cache: cache,
    summary: ArticleSummaryService(
      runner: AiTaskRunner(
        credentials: const AlwaysCredentialStore(),
        factory: factory,
        diagnostics: sink,
        budget: const AiTaskBudget(),
        clock: clock,
      ),
      clock: clock,
    ),
    counter: counter,
    zone: const FixedOffsetZone(Duration(hours: 8), ianaName: 'Asia/Shanghai'),
    clock: clock,
    diagnostics: sink,
  );

  test('SET-037 关闭时一个请求都不发（默认关）', () async {
    articles.add(1, body: '正文一', sourceSummary: null);
    final AutoSummaryBatchReport report = await service().runBatch(
      enabled: false,
      dailyLimit: 50,
      models: <AiModel>[model()],
    );
    expect(report.disabled, isTrue);
    expect(report.attempted, 0);
    expect(factory.totalIssued, 0, reason: '关闭时不得发出任何模型请求');
    expect(articles.saved, isEmpty);
  });

  test('开启后补齐缺摘要的文章，写 ai_summary 且源摘要不动', () async {
    articles.add(1, body: '正文一', sourceSummary: '源摘要');
    articles.add(2, body: '正文二', sourceSummary: null);
    // 第 2 篇已有源摘要，因此只有第 1 篇是「缺摘要」的候选——这里用 store 的行为
    // 表达该规则（实现里是 summary 与 ai_summary 都为空）。
    articles.missing = <int>[2];
    final AutoSummaryBatchReport report = await service().runBatch(
      enabled: true,
      dailyLimit: 50,
      models: <AiModel>[model()],
    );
    expect(report.succeeded, 1);
    expect(report.failed, 0);
    expect(factory.totalIssued, 1);
    expect(articles.saved.single.articleId, 2);
    expect(articles.saved.single.summary.text, '摘要');
    expect(
      articles.saved.single.summary.modelLabel,
      'main/main-model',
      reason: '记录生成用的模型标识',
    );
    // 源摘要仍在（写的是 ai_summary 三列）。
    expect(articles.sourceSummaryOf(1), '源摘要');
    expect(articles.sourceSummaryOf(2), isNull);
    expect(counter.usedToday, 1, reason: '成功才扣当天额度');
  });

  test('当天额度已用尽时不发请求（SET-064 是硬边界）', () async {
    articles.missing = <int>[1];
    counter.used = 50;
    final AutoSummaryBatchReport report = await service().runBatch(
      enabled: true,
      dailyLimit: 50,
      models: <AiModel>[model()],
    );
    expect(report.stoppedByQuota, isTrue);
    expect(report.attempted, 0);
    expect(factory.totalIssued, 0);
  });

  test('一批不超过当天剩余额度（剩余 2 时最多跑 2 篇）', () async {
    articles.missing = <int>[1, 2, 3, 4];
    for (final int id in <int>[1, 2, 3, 4]) {
      articles.add(id, body: '正文 $id');
    }
    counter.used = 48;
    final AutoSummaryBatchReport report = await service().runBatch(
      enabled: true,
      dailyLimit: 50,
      models: <AiModel>[model()],
      limitPerRun: 5,
    );
    expect(report.attempted, 2, reason: '剩余额度 2，不得跑第 3 篇');
    expect(factory.totalIssued, 2);
    expect(counter.usedToday, 50);
  });

  test('结果缓存命中时一个请求都不发，但仍落库', () async {
    articles.add(1, body: '正文一');
    articles.missing = <int>[1];
    cache.seed(
      text: '缓存里的摘要',
      providerAlias: 'main',
      modelId: 'main-model',
      // 缓存键与批处理算出来的必须一致（同模型、同提示、同语言）。
      keyForRequest: () => cache.lastKey,
    );
    final AutoSummaryBatchReport report = await service().runBatch(
      enabled: true,
      dailyLimit: 50,
      models: <AiModel>[model()],
    );
    expect(report.fromCache, 1);
    expect(factory.totalIssued, 0, reason: '缓存命中不得发请求');
    expect(articles.saved.single.summary.text, '缓存里的摘要');
    expect(counter.usedToday, 0, reason: '缓存命中不消耗当天额度（没有产生费用）');
  });

  test('生成失败不写库、不扣额度（不把失败固化成假摘要）', () async {
    factory.scriptsByAlias['main'] = <AiAttemptScript>[
      ScriptFailure(
        error: NetworkError(uri: 'https://main.example.com', reason: 'boom'),
      ),
    ];
    // 让五次无响应规则立刻终止（阈值 1）。
    articles.add(1, body: '正文一');
    articles.missing = <int>[1];
    final AutoSummaryBatchService sut = AutoSummaryBatchService(
      articles: articles,
      cache: cache,
      summary: ArticleSummaryService(
        runner: AiTaskRunner(
          credentials: const AlwaysCredentialStore(),
          factory: factory,
          diagnostics: sink,
          budget: const AiTaskBudget(),
          clock: clock,
          failoverThreshold: 1,
        ),
        clock: clock,
      ),
      counter: counter,
      zone: const FixedOffsetZone(Duration(hours: 8)),
      clock: clock,
      diagnostics: sink,
    );
    final AutoSummaryBatchReport report = await sut.runBatch(
      enabled: true,
      dailyLimit: 50,
      models: <AiModel>[model()],
    );
    expect(report.failed, 1);
    expect(report.succeeded, 0);
    expect(articles.saved, isEmpty, reason: '失败不得写摘要');
    expect(counter.usedToday, 0, reason: '失败不扣额度');
  });

  test('没有正文的文章不发起请求（如实跳过）', () async {
    articles.add(1, body: null);
    articles.missing = <int>[1];
    final AutoSummaryBatchReport report = await service().runBatch(
      enabled: true,
      dailyLimit: 50,
      models: <AiModel>[model()],
    );
    expect(report.attempted, 0);
    expect(factory.totalIssued, 0);
    expect(counter.usedToday, 0);
  });

  test('读不到当天计数时不发请求（额度不可确认 → fail-closed）', () async {
    articles.missing = <int>[1];
    counter.failRead = true;
    final AutoSummaryBatchReport report = await service().runBatch(
      enabled: true,
      dailyLimit: 50,
      models: <AiModel>[model()],
    );
    expect(report.error, isNotNull);
    expect(factory.totalIssued, 0);
  });

  test('跨午夜后额度按新的当天计数（日期键来自设备时区）', () async {
    // 设备时区 +8：UTC 04:00 是当地 12:00（9-22）；UTC 20:00 是当地 9-23 04:00。
    articles.missing = <int>[1];
    articles.add(1, body: '正文一');
    counter.used = 50;
    await service().runBatch(
      enabled: true,
      dailyLimit: 50,
      models: <AiModel>[model()],
    );
    expect(counter.readKeys.last, '2026-09-22');
    clock.advance(const Duration(hours: 17));
    final AutoSummaryBatchReport next = await service().runBatch(
      enabled: true,
      dailyLimit: 50,
      models: <AiModel>[model()],
      limitPerRun: 1,
    );
    expect(counter.readKeys.last, '2026-09-23', reason: '跨午夜后按新的一天计');
    expect(next.attempted, 1, reason: '新的一天额度重新可用');
  });
}
