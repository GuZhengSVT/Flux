// T040：定时调度器（架构 4.4、D-08、手册 6.3「定时」节）。
//
// 断言的是**动作**而不是状态：到点真的只跑一次、等待配置一次请求都不发、补跑只补当天、
// 跨日不补、取消/终止落 interrupted。全部用假时钟，不真实等待、不真实出网。
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:flux/core/core.dart';
import 'package:flux/features/ai/domain/ai_message.dart';
import 'package:flux/features/news/application/daily_news_scheduler.dart';
import 'package:flux/features/news/application/news_run_service.dart';
import 'package:flux/infrastructure/local/diagnostics.dart';
import 'package:flux/infrastructure/local/feed_store_adapter.dart'
    show DiagnosticLogSink;

const SessionLocalZone shanghai = FixedOffsetZone(
  Duration(hours: 8),
  ianaName: 'Asia/Shanghai',
);

void main() {
  late FakeClock clock;
  late DiagnosticLog diagnostics;
  late List<String> runs;
  late List<DailyNewsStatus> published;
  late DailyNewsReadiness readiness;
  String? completedDate;
  int interruptedCalls = 0;

  setUp(() {
    // 当地 2026-09-22 19:00（还没到 20:00）。
    clock = FakeClock(start: DateTime.utc(2026, 9, 22, 11));
    diagnostics = DiagnosticLog(level: DiagnosticLevel.error);
    runs = <String>[];
    published = <DailyNewsStatus>[];
    readiness = DailyNewsReadiness.ok;
    completedDate = null;
    interruptedCalls = 0;
  });

  DailyNewsScheduler build({
    bool enabled = true,
    int minutes = 20 * 60,
    int Function()? localDateOfRun,
  }) {
    final DailyNewsScheduler scheduler = DailyNewsScheduler(
      readPolicy: () async => Ok<DailyNewsPolicy>(
        DailyNewsPolicy(
          enabled: enabled,
          timeOfDayMinutes: minutes,
          zone: shanghai,
        ),
      ),
      readReadiness: () async => readiness,
      successDateLoader: ({
        required String localDate,
        required String timeZone,
      }) async => completedDate,
      runNews:
          ({
            required String localDate,
            required SessionLocalZone zone,
            required AiCancellation cancellation,
          }) async {
            runs.add(localDate);
            return NewsRunOutcome(
              status: TaskStatus.succeeded,
              snapshot: _snapshot(localDate: localDate),
              record: _record(localDate: localDate),
            );
          },
      markInterruptedOnStartup: () async {
        interruptedCalls++;
        return const Ok<int>(0);
      },
      clock: clock,
      diagnostics: DiagnosticLogSink(diagnostics),
      onStatus: published.add,
      // 一分钟的检查周期：测试里不用它（直接调 runIfDue），但保持与生产一致。
      checkInterval: const Duration(minutes: 1),
    );
    addTearDown(scheduler.dispose);
    return scheduler;
  }

  group('到点触发（架构 4.4）', () {
    test('未到点不发请求；到点后运行一次', () async {
      final DailyNewsScheduler scheduler = build();
      await scheduler.runIfDue(trigger: DailyNewsTrigger.launch);
      expect(runs, isEmpty, reason: '当地 19:00 还没到 20:00');
      expect(scheduler.status!.kind, DailyNewsDueKind.notDue);
      expect(scheduler.status!.nextRunUtc, DateTime.utc(2026, 9, 22, 12));

      // 推进到当地 20:00。
      clock.advance(const Duration(hours: 1));
      final DailyNewsRunReport? report = await scheduler.runIfDue(
        trigger: DailyNewsTrigger.scheduled,
      );
      expect(report, isNotNull);
      expect(report!.catchUp, isFalse);
      expect(report.outcome.ok, isTrue);
      expect(runs, <String>['2026-09-22']);
      expect(scheduler.status!.kind, DailyNewsDueKind.due);
    });

    test('同一天到点后再检查不会重复运行（成功版本已存在）', () async {
      clock.advance(const Duration(hours: 1));
      final DailyNewsScheduler scheduler = build();
      await scheduler.runIfDue(trigger: DailyNewsTrigger.scheduled);
      expect(runs.length, 1);
      // 模拟任务成功落库：今天已有成功版本。
      completedDate = '2026-09-22';
      clock.advance(const Duration(minutes: 5));
      await scheduler.runIfDue(trigger: DailyNewsTrigger.scheduled);
      expect(runs.length, 1, reason: '当天成功版本存在则不重复自动收费');
      expect(scheduler.status!.kind, DailyNewsDueKind.alreadyGeneratedToday);
      expect(scheduler.status!.completedToday, isTrue);
    });
  });

  group('waitingConfiguration 零请求（D-08）', () {
    test('缺模型凭据：不发任何请求，状态是等待配置并给出原因', () async {
      readiness = const DailyNewsReadiness(
        ready: false,
        reason: 'noModelCredential',
      );
      clock.advance(const Duration(hours: 2)); // 早已过点
      final DailyNewsScheduler scheduler = build();
      final DailyNewsRunReport? report = await scheduler.runIfDue(
        trigger: DailyNewsTrigger.launch,
      );
      expect(report, isNull);
      expect(runs, isEmpty, reason: '等待配置不发任何请求');
      expect(scheduler.status!.kind, DailyNewsDueKind.waitingConfiguration);
      expect(scheduler.status!.waitingReason, 'noModelCredential');
      expect(scheduler.status!.enabled, isTrue, reason: '保留默认开启的偏好');
    });

    test('未确认费用告知：同样零请求，且原因可区分', () async {
      readiness = const DailyNewsReadiness(ready: false, reason: 'costNotice');
      clock.advance(const Duration(hours: 2));
      final DailyNewsScheduler scheduler = build();
      await scheduler.runIfDue(trigger: DailyNewsTrigger.launch);
      expect(runs, isEmpty);
      expect(scheduler.status!.waitingReason, 'costNotice');
    });

    test('配置完成后自动解除：同一个调度器下一次检查就跑', () async {
      readiness = const DailyNewsReadiness(
        ready: false,
        reason: 'noEnabledModel',
      );
      clock.advance(const Duration(hours: 2));
      final DailyNewsScheduler scheduler = build();
      await scheduler.runIfDue(trigger: DailyNewsTrigger.scheduled);
      expect(runs, isEmpty);

      readiness = DailyNewsReadiness.ok;
      await scheduler.runIfDue(trigger: DailyNewsTrigger.scheduled);
      expect(runs.length, 1, reason: '配置补齐后立即解除等待，无需重启');
    });
  });

  group('错过只补当日一次（架构 4.4）', () {
    test('应用关闭错过 20:00：启动时补跑今天一次', () async {
      // 启动时刻是当地 23:00（错过 20:00 三小时）。
      clock.set(DateTime.utc(2026, 9, 22, 15));
      final DailyNewsScheduler scheduler = build();
      await scheduler.onLaunch();
      expect(runs, <String>['2026-09-22']);
      expect(scheduler.status!.lastCatchUp, isTrue, reason: '这是一次补跑');
      expect(interruptedCalls, 1, reason: '启动时先标中断（不重放）');
    });

    test('补跑只补一次：同一启动周期内后续检查不再跑', () async {
      clock.set(DateTime.utc(2026, 9, 22, 15));
      final DailyNewsScheduler scheduler = build();
      await scheduler.onLaunch();
      expect(runs.length, 1);
      completedDate = '2026-09-22';
      await scheduler.runIfDue(trigger: DailyNewsTrigger.scheduled);
      expect(runs.length, 1);
    });

    test('跨日不补：今天还没到点时启动，什么都不跑', () async {
      // 当地 2026-09-23 10:00：昨天（09-22）那次已经永远错过。
      clock.set(DateTime.utc(2026, 9, 23, 2));
      final DailyNewsScheduler scheduler = build();
      await scheduler.onLaunch();
      expect(runs, isEmpty, reason: '昨日错过就放弃，不补历史日期');
      expect(scheduler.status!.localDate, '2026-09-23');
      expect(scheduler.status!.kind, DailyNewsDueKind.notDue);
    });

    test('跨日但次日已过点：补的是次日那一次（仍只有一次）', () async {
      // 当地 2026-09-23 22:00。
      clock.set(DateTime.utc(2026, 9, 23, 14));
      final DailyNewsScheduler scheduler = build();
      await scheduler.onLaunch();
      expect(runs, <String>['2026-09-23'], reason: '只补当天，不补 09-22');
    });
  });

  group('应用终止与并发（手册 6.3、架构 4.5）', () {
    test('启动时标记中断只做一次、失败不阻塞补跑', () async {
      final DailyNewsScheduler scheduler = DailyNewsScheduler(
        readPolicy: () async => const Ok<DailyNewsPolicy>(
          DailyNewsPolicy(
            enabled: true,
            timeOfDayMinutes: 1200,
            zone: shanghai,
          ),
        ),
        readReadiness: () async => DailyNewsReadiness.ok,
        successDateLoader: ({
          required String localDate,
          required String timeZone,
        }) async => null,
        runNews:
            ({
              required String localDate,
              required SessionLocalZone zone,
              required AiCancellation cancellation,
            }) async {
              runs.add(localDate);
              return NewsRunOutcome(
                status: TaskStatus.succeeded,
                snapshot: _snapshot(localDate: localDate),
              );
            },
        // 标中断失败：不应当阻塞今天该跑的那一次。
        markInterruptedOnStartup: () async {
          interruptedCalls++;
          return Err<int>(
            StorageError(operation: 'markRunning', detail: 'stub'),
          );
        },
        clock: clock,
        diagnostics: DiagnosticLogSink(diagnostics),
      );
      addTearDown(scheduler.dispose);
      clock.set(DateTime.utc(2026, 9, 22, 15));
      await scheduler.onLaunch();
      expect(interruptedCalls, 1);
      expect(runs, <String>['2026-09-22'], reason: '标中断失败不影响今天的补跑');
      // 再调一次 onLaunch：不会第二次标记中断（_startupChecked）。
      await scheduler.onLaunch();
      expect(interruptedCalls, 1);
    });

    test('运行中不再接受新触发（单并发闸门）', () async {
      final Completer<void> gate = Completer<void>();
      int started = 0;
      late DailyNewsScheduler scheduler;
      scheduler = DailyNewsScheduler(
        readPolicy: () async => const Ok<DailyNewsPolicy>(
          DailyNewsPolicy(
            enabled: true,
            timeOfDayMinutes: 1200,
            zone: shanghai,
          ),
        ),
        readReadiness: () async => DailyNewsReadiness.ok,
        successDateLoader: ({
          required String localDate,
          required String timeZone,
        }) async => null,
        runNews:
            ({
              required String localDate,
              required SessionLocalZone zone,
              required AiCancellation cancellation,
            }) async {
              started++;
              await gate.future;
              return NewsRunOutcome(
                status: TaskStatus.succeeded,
                snapshot: _snapshot(localDate: localDate),
              );
            },
        markInterruptedOnStartup: () async => const Ok<int>(0),
        clock: clock,
        diagnostics: DiagnosticLogSink(diagnostics),
      );
      addTearDown(scheduler.dispose);
      clock.advance(const Duration(hours: 1));
      final Future<DailyNewsRunReport?> first = scheduler.runIfDue(
        trigger: DailyNewsTrigger.scheduled,
      );
      await Future<void>.delayed(Duration.zero);
      expect(scheduler.isRunning, isTrue);
      // 第二次触发被闸门挡下：不会同时起两个任务（否则两个任务会争同一个版本号）。
      final DailyNewsRunReport? second = await scheduler.runIfDue(
        trigger: DailyNewsTrigger.launch,
      );
      expect(second, isNull);
      gate.complete();
      expect((await first)!.outcome.ok, isTrue);
      expect(started, 1);
    });

    test('dispose 后不再触发（也不会取消在途任务）', () async {
      final DailyNewsScheduler scheduler = build();
      scheduler.dispose();
      clock.advance(const Duration(hours: 2));
      final DailyNewsRunReport? report = await scheduler.runIfDue(
        trigger: DailyNewsTrigger.scheduled,
      );
      expect(report, isNull);
      expect(runs, isEmpty);
    });
  });

  group('关闭时不跑（SET-056）', () {
    test('关闭后即便过点也不运行，且状态说明是「关闭」而不是「等待配置」', () async {
      clock.advance(const Duration(hours: 2));
      final DailyNewsScheduler scheduler = build(enabled: false);
      await scheduler.runIfDue(trigger: DailyNewsTrigger.scheduled);
      expect(runs, isEmpty);
      expect(scheduler.status!.kind, DailyNewsDueKind.disabled);
      expect(scheduler.status!.enabled, isFalse);
    });

    test('自定义时间（SET-057）：改到早上 7 点后按新时间到点', () async {
      // 当地 07:00 = UTC 前一日 23:00。
      clock.set(DateTime.utc(2026, 9, 21, 23));
      final DailyNewsScheduler scheduler = build(minutes: 7 * 60);
      await scheduler.runIfDue(trigger: DailyNewsTrigger.scheduled);
      expect(runs, <String>['2026-09-22']);
      expect(scheduler.status!.timeOfDay, '07:00');
    });
  });

  group('状态发布（设置页与今日页读它）', () {
    test('每次评估都发布一次状态，且时间来自当次策略', () async {
      clock.advance(const Duration(hours: 2));
      final DailyNewsScheduler scheduler = build();
      await scheduler.runIfDue(trigger: DailyNewsTrigger.scheduled);
      expect(published, isNotEmpty);
      final DailyNewsStatus last = published.last;
      expect(last.timeOfDay, '20:00');
      expect(last.timeZone, 'Asia/Shanghai');
      expect(last.running, isFalse);
      expect(last.completedToday, isFalse);
    });
  });
}

NewsInputSnapshot _snapshot({required String localDate}) => NewsInputSnapshot(
  localDate: localDate,
  deviceTimeZone: 'Asia/Shanghai',
  utcOffsetMinutes: 480,
  dayStartUtc: DateTime.utc(2026, 9, 21, 16),
  dayEndUtc: DateTime.utc(2026, 9, 22, 16),
  frozenAtUtc: DateTime.utc(2026, 9, 22, 13),
  candidates: const <NewsMaterial>[],
  requiredSites: const <NewsRequiredSite>[],
  keywords: const <String>[],
  blockedQueryTerms: const <String>[],
  excludedTopics: const <String>[],
  promptVersionRef: 'zh-Hans#builtin',
  promptText: '任务段',
  maxArticles: 50,
  maxSites: 10,
  maxQueries: 10,
  singleMaterialBudget: 8000,
  globalEnabled: true,
);

NewsRunRecord _record({required String localDate}) => NewsRunRecord(
  localDate: localDate,
  timeZone: 'Asia/Shanghai',
  version: 1,
  status: TaskStatus.succeeded,
  snapshot: _snapshot(localDate: localDate),
  siteResults: const <NewsSiteFetchResult>[],
  materials: const <NewsMaterial>[],
  items: const <NewsDraftItem>[],
  createdAt: DateTime.utc(2026, 9, 22, 12),
  isCurrent: true,
);
