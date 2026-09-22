// 定时任务的一次运行：占位行 → 跑编排 → 原地收尾（T040）。
//
// 为什么单独一层而不是让调度器直接调编排服务：**占位行是这一层的唯一理由**。
//
//   1) 任务开始时先写一条 `running` 行，应用被系统终止后下一次启动才有东西可以如实标成
//      `interrupted`（否则「上次到底跑过没有」在数据上是空白）；
//   2) 结束时用**同一个版本号**原地收尾，而不是再追加一条：追加会让每次定时生成都留下
//      一条永远停在 `running` 的历史行，用户会以为有任务卡住了；
//   3) 收尾时**即使占位行不见了也要保存结果**（插入而不是报错）：任务可能已经真实跑完
//      并计过费，把结果丢掉是这里代价最大的错误。
//
// 手动生成（今日页的按钮）**不走这条路**：它由用户当场确认费用，没有「被系统终止后要
// 说清楚」的问题，因此直接追加版本即可。两条路径的差别只在占位，不在编排。
library;

import 'package:flux/core/core.dart';
import 'package:flux/features/ai/domain/ai_message.dart';

import 'news_run_inputs.dart';
import 'news_run_service.dart';
import 'news_source_config.dart';

/// 一次定时运行的执行器。
final class DailyNewsRunner {
  /// 构造执行器。
  const DailyNewsRunner({
    required this.runs,
    required this.runInput,
    required this.diagnostics,
    required this.clock,
  });

  /// 版本存储（读写占位行）。
  final NewsRunStore runs;

  /// 跑一次编排（由组合根把「按当前设置造一个服务」与调用接在一起）。
  ///
  /// 收成「输入 → 产出」一个函数而不是「造服务 + 调服务」两步：这一层唯一关心的是
  /// **占位行怎么收尾**，让它去认识 [NewsRunService] 的构造参数（budget、toolExecutor、
  /// 核验预算……）只会把「占位」这件事的测试绑死在编排层的装配细节上。
  ///
  /// [SessionLocalZone] 一起传进去，而不是让实现自己再读一次设备时区：占位行记录的是
  /// `run` 收到的那个时区，编排层若用另一个时刻读到的时区算日界线，两条记录就会在同一次
  /// 任务上写着两个时区（跨午夜时还会写成两个日期）。
  final Future<NewsRunOutcome> Function(
    NewsRunInput input,
    SessionLocalZone zone,
  )
  runInput;

  /// 诊断记录。
  final DiagnosticSink diagnostics;

  /// 时钟。
  final Clock clock;

  /// 跑一次并返回编排结果。
  ///
  /// [config] 与 [globalEnabled] 由调用方（组合根）读好传入：这一层不读设置，与
  /// [NewsRunService] 同一口径（设置由构造服务的人读一次并冻结）。
  Future<NewsRunOutcome?> run({
    required String localDate,
    required SessionLocalZone zone,
    required NewsConfigState config,
    required bool globalEnabled,
    required AiCancellation cancellation,
  }) async {
    final int version = await _nextVersion(localDate, zone.ianaName);
    // 占位行用**一次快照**：这一行的存在意义只是「有一次任务在进行」，因此它的快照沿用
    // 本次运行的输入（与最终结果同一份），不另造一个假的。
    // 用与编排层**同一套**日界线口径算当天的 UTC 区间（不自己再写一遍偏移运算）。
    final NewsDayRange range = newsDayRange(
      nowUtc: clock.now().toUtc(),
      zone: zone,
    );
    final NewsInputSnapshot placeholder = NewsInputSnapshot(
      localDate: localDate,
      deviceTimeZone: zone.ianaName,
      utcOffsetMinutes: range.utcOffsetMinutes,
      dayStartUtc: range.startUtc,
      dayEndUtc: range.endUtc,
      frozenAtUtc: clock.now().toUtc(),
      candidates: const <NewsMaterial>[],
      requiredSites: config.promptInput.enabledSites,
      keywords: config.keywords,
      blockedQueryTerms: config.blockedQueryTerms,
      excludedTopics: config.excludedTopics,
      promptVersionRef: 'scheduled#pending',
      promptText: '',
      maxArticles: 0,
      maxSites: 0,
      maxQueries: 0,
      singleMaterialBudget: 0,
      globalEnabled: globalEnabled,
      language: config.language,
    );
    final Result<NewsRunRecord> reserved = await runs.reserveRunning(
      NewsRunRecord(
        localDate: localDate,
        timeZone: zone.ianaName,
        version: version,
        status: TaskStatus.running,
        snapshot: placeholder,
        siteResults: const <NewsSiteFetchResult>[],
        materials: const <NewsMaterial>[],
        items: const <NewsDraftItem>[],
        createdAt: clock.now().toUtc(),
      ),
    );
    if (reserved.isErr) {
      // 占位写不进去**不阻止这次运行**：定时任务的价值在于产出总结，而占位行只影响
      // 「被终止后能不能说清」。结果会用 append 落库（收尾时的兜底插入同一条路径）。
      diagnostics.warning(
        '定时总结占位行写入失败 kind=${reserved.errorOrNull!.kind}'
        '（仍继续运行）',
        tag: 'news.daily',
      );
    }

    final NewsRunOutcome outcome = await runInput(
      NewsRunInput(
        taskId: 'news-scheduled-$localDate-$version',
        config: config,
        globalEnabled: globalEnabled,
        cancellation: cancellation,
        regenerate: false,
      ),
      zone,
    );
    await _finalize(reservedVersion: version, outcome: outcome);
    return outcome;
  }

  /// 用同一个版本号收尾占位行。
  ///
  /// 编排层在成功/部分成功时**已经**用自己的版本号追加过一条（`news_run_service.run` 内部
  /// 走 append），因此成功路径上这里只需要把占位行收拾掉，不能再写一条——否则一次成功运行
  /// 会留下两条内容相同的版本。
  ///
  /// 为什么成功时占位行的版本号通常与结果不同：占位行占了「下一个版本号」，而编排层读到的
  /// 最大值已经包含它，于是结果落在再下一个号上。留下一个未用的版本号是无害的（版本号只是
  /// 次序），而**留一条永远 running 的行**是有害的：用户会以为有任务卡住了。两者取前者。
  Future<void> _finalize({
    required int reservedVersion,
    required NewsRunOutcome outcome,
  }) async {
    final NewsRunRecord? record = outcome.record;
    if (record != null && outcome.ok) {
      await _clearPlaceholderIfStillRunning(
        localDate: outcome.snapshot.localDate,
        timeZone: outcome.snapshot.deviceTimeZone,
        version: reservedVersion,
      );
      return;
    }
    // 失败/取消/中断：把占位行**原地**改成终态。分开写两次（先删占位、再追加结果）会留下
    // 「一条都没有」的窗口，而那正是「这次到底跑了没有」最需要答案的时刻。
    final NewsRunRecord finalized = NewsRunRecord(
      localDate: outcome.snapshot.localDate,
      timeZone: outcome.snapshot.deviceTimeZone,
      version: reservedVersion,
      status: outcome.status,
      snapshot: outcome.snapshot,
      siteResults: record?.siteResults ?? const <NewsSiteFetchResult>[],
      materials: record?.materials ?? const <NewsMaterial>[],
      items: record?.items ?? const <NewsDraftItem>[],
      createdAt: clock.now().toUtc(),
      draftText: record?.draftText,
      providerAlias: record?.providerAlias,
      modelId: record?.modelId,
      consumedTokens: record?.consumedTokens ?? 0,
      attemptCount: record?.attemptCount ?? 0,
      errorKind: outcome.error?.kind ?? record?.errorKind,
      verificationMethod: record?.verificationMethod,
      stage: outcome.stage ?? record?.stage,
    );
    final Result<NewsRunRecord> saved = await runs.completeReserved(finalized);
    if (saved.isErr) {
      diagnostics.warning(
        '定时总结收尾失败 kind=${saved.errorOrNull!.kind}',
        tag: 'news.daily',
      );
    }
  }

  /// 删掉一条**仍在 running** 的占位行（编排层已用自己的版本号落库成功）。
  ///
  /// 判据里**必须**包含 `status == running`：按版本号无条件删除是危险的——那个号可能与
  /// 一条真实结果重合（例如用户手动生成恰好落在同一个号上），删除会把结果一起删掉。
  Future<void> _clearPlaceholderIfStillRunning({
    required String localDate,
    required String timeZone,
    required int version,
  }) async {
    final Result<List<NewsRunRecord>> versions = await runs.loadVersions(
      localDate: localDate,
      timeZone: timeZone,
    );
    if (versions.isErr) {
      return;
    }
    for (final NewsRunRecord row in versions.valueOrNull!) {
      if (row.version == version && row.status == TaskStatus.running) {
        final Result<void> deleted = await runs.deleteVersion(
          localDate: localDate,
          timeZone: timeZone,
          version: version,
        );
        if (deleted.isErr) {
          diagnostics.warning(
            '占位行清理失败 kind=${deleted.errorOrNull!.kind}'
            '（该行会被下一次启动标为 interrupted，不会伪称完成）',
            tag: 'news.daily',
          );
        }
        return;
      }
    }
  }

  /// 取下一个版本号（与编排层的口径一致：同日期同时区最大值 + 1）。
  Future<int> _nextVersion(String localDate, String timeZone) async {
    final Result<List<NewsRunRecord>> existing = await runs.loadVersions(
      localDate: localDate,
      timeZone: timeZone,
    );
    if (existing.isErr) {
      // 读不到时按 1 记：唯一约束会拒绝重复，而不是静默覆盖一条既有版本。
      return 1;
    }
    int max = 0;
    for (final NewsRunRecord record in existing.valueOrNull!) {
      if (record.version > max) {
        max = record.version;
      }
    }
    return max + 1;
  }
}
