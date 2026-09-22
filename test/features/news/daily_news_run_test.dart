// T040：定时任务的占位行生命周期（架构 4.4/4.5）。
//
// 断言的是「被系统终止后能不能说清」这件事的数据基础：
//   * 任务开始时写一条 running 占位，且**不动**当前版本；
//   * 成功时占位行被原地收尾（不留永远 running 的孤儿行）；
//   * 失败/取消时占位行被改写成终态（而不是留下 running，也不是什么都不留）；
//   * 下一次启动能把上次的 running 标成 interrupted，且**不重发**。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:flux/core/core.dart';
import 'package:flux/features/ai/domain/ai_message.dart';
import 'package:flux/features/news/application/daily_news_run.dart';
import 'package:flux/features/news/application/news_run_service.dart';
import 'package:flux/features/news/application/news_source_config.dart';
import 'package:flux/infrastructure/local/diagnostics.dart';
import 'package:flux/infrastructure/local/feed_store_adapter.dart'
    show DiagnosticLogSink;

import 'news_run_test.dart' show MemoryNewsRunStore;

const SessionLocalZone shanghai = FixedOffsetZone(
  Duration(hours: 8),
  ianaName: 'Asia/Shanghai',
);

NewsConfigState config() => const NewsConfigState(
  globalEnabled: true,
  requiredSites: <NewsRequiredSite>[],
  keywords: <String>[],
  blockedQueryTerms: <String>[],
  excludedTopics: <String>[],
  mode: NewsPromptMode.composed,
  taskInstruction: '',
  outputSpec: '',
  advancedPrompt: '',
  versions: <NewsPromptVersion>[],
);

void main() {
  late FakeClock clock;
  late MemoryNewsRunStore runs;
  late DiagnosticLog diagnostics;

  setUp(() {
    clock = FakeClock(start: DateTime.utc(2026, 9, 22, 12));
    runs = MemoryNewsRunStore();
    diagnostics = DiagnosticLog(level: DiagnosticLevel.error);
  });

  test('成功：占位行原地收尾，不留孤儿 running 行', () async {
    // runInput 替身直接产出结果（不联网、不调用模型）。
    final DailyNewsRunner runner = DailyNewsRunner(
      runs: runs,
      runInput: (NewsRunInput input, SessionLocalZone zone) async =>
          NewsRunOutcome(
            status: TaskStatus.succeeded,
            snapshot: _snapshot('2026-09-22'),
            record: await _appendSucceeded(runs),
          ),
      diagnostics: DiagnosticLogSink(diagnostics),
      clock: clock,
    );
    final NewsRunOutcome? outcome = await runner.run(
      localDate: '2026-09-22',
      zone: shanghai,
      config: config(),
      globalEnabled: true,
      cancellation: AiCancellation(),
    );
    expect(outcome!.ok, isTrue);
    final List<NewsRunRecord> versions = (await runs.loadVersions(
      localDate: '2026-09-22',
      timeZone: 'Asia/Shanghai',
    )).valueOrNull!;
    // 占位行（v1，running）被清掉；编排层落的成功版本（v2）留下，且是当前版本。
    expect(versions, hasLength(1));
    expect(versions.single.version, 2);
    expect(versions.single.status, TaskStatus.succeeded);
    expect(versions.single.isCurrent, isTrue);
  });

  test('失败：占位行被改写为终态（不是留在 running，也不是什么都不留）', () async {
    final DailyNewsRunner runner = DailyNewsRunner(
      runs: runs,
      runInput: (NewsRunInput input, SessionLocalZone zone) async =>
          NewsRunOutcome(
            status: TaskStatus.failed,
            snapshot: _snapshot('2026-09-22'),
            error: NetworkError(uri: 'https://api.example.com', reason: 'stub'),
            stage: NewsRunStage.generate,
          ),
      diagnostics: DiagnosticLogSink(diagnostics),
      clock: clock,
    );
    await runner.run(
      localDate: '2026-09-22',
      zone: shanghai,
      config: config(),
      globalEnabled: true,
      cancellation: AiCancellation(),
    );
    final List<NewsRunRecord> versions = (await runs.loadVersions(
      localDate: '2026-09-22',
      timeZone: 'Asia/Shanghai',
    )).valueOrNull!;
    expect(versions, hasLength(1));
    expect(versions.single.status, TaskStatus.failed);
    expect(versions.single.errorKind, 'network');
    expect(versions.single.stage, NewsRunStage.generate);
    // 失败不产生当前版本（上一版成功总结仍然是用户看到的内容）。
    expect(versions.single.isCurrent, isFalse);
    expect(
      (await runs.loadCurrent(
        localDate: '2026-09-22',
        timeZone: 'Asia/Shanghai',
      )).valueOrNull,
      isNull,
    );
  });

  test('取消：占位行落 cancelled，保留已完成阶段', () async {
    final DailyNewsRunner runner = DailyNewsRunner(
      runs: runs,
      runInput: (NewsRunInput input, SessionLocalZone zone) async =>
          NewsRunOutcome(
            status: TaskStatus.cancelled,
            snapshot: _snapshot('2026-09-22'),
            error: CancelledError(reason: '用户取消'),
            stage: NewsRunStage.search,
          ),
      diagnostics: DiagnosticLogSink(diagnostics),
      clock: clock,
    );
    await runner.run(
      localDate: '2026-09-22',
      zone: shanghai,
      config: config(),
      globalEnabled: true,
      cancellation: AiCancellation()..cancel(),
    );
    final List<NewsRunRecord> versions = (await runs.loadVersions(
      localDate: '2026-09-22',
      timeZone: 'Asia/Shanghai',
    )).valueOrNull!;
    expect(versions.single.status, TaskStatus.cancelled);
    expect(versions.single.stage, NewsRunStage.search);
  });

  test('被终止后启动：running 行被标 interrupted，且不重发', () async {
    // 模拟上次进程在运行中被终止：库里留下一条 running 占位行。
    await runs.reserveRunning(
      NewsRunRecord(
        localDate: '2026-09-22',
        timeZone: 'Asia/Shanghai',
        version: 1,
        status: TaskStatus.running,
        snapshot: _snapshot('2026-09-22'),
        siteResults: const <NewsSiteFetchResult>[],
        materials: const <NewsMaterial>[],
        items: const <NewsDraftItem>[],
        createdAt: DateTime.utc(2026, 9, 22, 12),
      ),
    );
    final Result<int> marked = await runs.markRunningAsInterrupted(
      at: DateTime.utc(2026, 9, 22, 12, 5),
    );
    expect(marked.valueOrNull, 1);
    final List<NewsRunRecord> versions = (await runs.loadVersions(
      localDate: '2026-09-22',
      timeZone: 'Asia/Shanghai',
    )).valueOrNull!;
    expect(versions.single.status, TaskStatus.interrupted);
    // 库里**没有**成功版本：于是调度器仍然认为今天没跑过（会补跑一次），
    // 而那次补跑是一个新任务与新版本——这正是「不重放、但要补上今天」两件事的分工。
    expect(
      (await runs.loadCurrent(
        localDate: '2026-09-22',
        timeZone: 'Asia/Shanghai',
      )).valueOrNull,
      isNull,
    );
  });
}

/// 用内存 store 追加一条成功版本（模拟编排层的保存）。
///
/// 版本号按「当前最大值 + 1」算：真实编排层就是这么做的，而这也正是成功路径上结果版本号
/// 与占位版本号不同的原因（占位行已经占了那一个号）。
Future<NewsRunRecord> _appendSucceeded(MemoryNewsRunStore runs) async {
  final List<NewsRunRecord> existing = (await runs.loadVersions(
    localDate: '2026-09-22',
    timeZone: 'Asia/Shanghai',
  )).valueOrNull!;
  int max = 0;
  for (final NewsRunRecord row in existing) {
    if (row.version > max) {
      max = row.version;
    }
  }
  final Result<NewsRunRecord> saved = await runs.append(
    NewsRunRecord(
      localDate: '2026-09-22',
      timeZone: 'Asia/Shanghai',
      version: max + 1,
      status: TaskStatus.succeeded,
      snapshot: _snapshot('2026-09-22'),
      siteResults: const <NewsSiteFetchResult>[],
      materials: const <NewsMaterial>[],
      items: const <NewsDraftItem>[
        NewsDraftItem(
          index: 1,
          text: '条目。',
          sourceIds: <String>[],
          status: NewsItemStatus.kept,
        ),
      ],
      createdAt: DateTime.utc(2026, 9, 22, 12),
      isCurrent: true,
    ),
  );
  return saved.valueOrNull!;
}

NewsInputSnapshot _snapshot(String localDate) => NewsInputSnapshot(
  localDate: localDate,
  deviceTimeZone: 'Asia/Shanghai',
  utcOffsetMinutes: 480,
  dayStartUtc: DateTime.utc(2026, 9, 21, 16),
  dayEndUtc: DateTime.utc(2026, 9, 22, 16),
  frozenAtUtc: DateTime.utc(2026, 9, 22, 12),
  candidates: const <NewsMaterial>[],
  requiredSites: const <NewsRequiredSite>[],
  keywords: const <String>[],
  blockedQueryTerms: const <String>[],
  excludedTopics: const <String>[],
  promptVersionRef: 'scheduled#1',
  promptText: '任务段',
  maxArticles: 50,
  maxSites: 10,
  maxQueries: 10,
  singleMaterialBudget: 8000,
  globalEnabled: true,
);
