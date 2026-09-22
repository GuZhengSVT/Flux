// 真实帧耗时采集（T052）：在 **profile/release** 构建下测滚动帧（架构第 8 节
// 「60Hz 常规滚动多数帧 16.7ms 内」）。
//
// 为什么必须在 profile/release 下另测一遍：
//   T050 的基线是 **debug** 模式（JIT、assert、无 AOT），实测稳态滚动 P50 23.2ms、
//   40 帧中 28 帧超预算。debug 的数字**不能**用来判定是否达标——assert 与未优化的
//   代码路径占了大头。T052 的职责之一就是给出 release 下的真实数字，据此决定
//   「滚动确实慢」还是「只是 debug 慢」。
//
// 为什么用 SchedulerBinding.addTimingsCallback 而不是 Stopwatch 包住 pump：
//   后者测的是「构建+布局在测试进程里花了多久」，不含光栅化，也不含与 vsync 的对齐；
//   而「60Hz 多数帧 16.7ms 内」说的是**端到端帧时间**（FrameTiming.totalSpan）。
//   addTimingsCallback 拿到的正是引擎上报的 FrameTiming，是这条验收唯一对的尺子。
//
// 执行：flutter drive --profile --driver=test_driver/perf_test.dart
//         --target=integration_test/t052_perf_test.dart
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kProfileMode, kReleaseMode;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:flux/features/articles/presentation/article_card.dart';
import 'package:flux/features/articles/presentation/reading_page.dart';
import 'package:flux/infrastructure/local/database.dart';
import 'package:flux/infrastructure/local/perf_dataset.dart';

import '../test/app/test_harness.dart';

/// 60Hz 下的一帧预算。
const int kFrameBudgetMicros = 16700;

void main() {
  final IntegrationTestWidgetsFlutterBinding binding =
      IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('滚动帧耗时（50000 行数据集，profile/release）', (WidgetTester tester) async {
    if (!const bool.fromEnvironment('PERF_SEED_DATASET')) {
      markTestSkipped('未设置 PERF_SEED_DATASET=true，跳过');
      return;
    }
    final AppDatabase db = AppDatabase.memory();
    addTearDown(db.close);
    await db.customSelect('SELECT 1').get();
    final PerfDatasetReport report = await seedPerfDataset(db);

    final TestBootstrap bootstrap = TestBootstrap(database: db);
    addTearDown(bootstrap.dispose);
    await setSurfaceSize(tester, const Size(1400, 900));

    // 引擎上报的帧时间（FrameTiming），真正的验收尺子。
    final List<FrameTiming> timings = <FrameTiming>[];
    void onTimings(List<FrameTiming> batch) => timings.addAll(batch);
    SchedulerBinding.instance.addTimingsCallback(onTimings);
    addTearDown(
      () => SchedulerBinding.instance.removeTimingsCallback(onTimings),
    );

    final Stopwatch firstFrame = Stopwatch()..start();
    await tester.pumpWidget(
      wrapFluxApp(
        child: const Scaffold(body: ReadingPage()),
        overrides: bootstrap.overrides(),
      ),
    );
    await tester.pump();
    firstFrame.stop();
    await tester.pumpAndSettle();

    final ScrollPosition position = tester
        .state<ScrollableState>(
          find.descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          ),
        )
        .position;
    // 自检（与 debug 基线同口径）：必须是**列表**的位置且确实能动，否则后面测到的是
    // 「什么都没干」的假数字。这条断言在 T050 实际救过一次（取到了不可滚动的
    // Scrollable，测出 0.019ms 的空转）。
    expect(
      position.maxScrollExtent,
      greaterThan(1000),
      reason: '取到的 ScrollPosition 不是文章列表',
    );
    final int builtCards = find.byType(ArticleCardBody).evaluate().length;
    expect(
      builtCards,
      lessThan(60),
      reason: '虚拟化失效：已加载 100 条却构建了 $builtCards 张卡片',
    );

    // 清掉预热帧（首屏含首次布局与着色器预热，不代表稳态）。
    timings.clear();

    // 稳态滚动：在已加载的 100 条内来回移动，不触发下一批加载。
    for (int i = 0; i < 60; i++) {
      final double target = (i % 2 == 0 ? i : 40 - i) * 120.0;
      position.jumpTo(target.clamp(0, position.maxScrollExtent));
      await tester.pump();
    }
    // 等引擎把剩余帧时间上报（批处理最多延迟约 1 秒）。
    await Future<void>.delayed(const Duration(seconds: 1));

    final List<int> steadyMicros = <int>[
      for (final FrameTiming t in timings)
        if (t.totalSpan.inMicroseconds > 0) t.totalSpan.inMicroseconds,
    ];

    // 滚动到底触发下一批：与稳态分开报，两者的修法完全不同。
    timings.clear();
    for (int i = 0; i < 5; i++) {
      position.jumpTo(position.maxScrollExtent);
      await tester.pump();
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    await Future<void>.delayed(const Duration(seconds: 1));
    final List<int> batchMicros = <int>[
      for (final FrameTiming t in timings)
        if (t.totalSpan.inMicroseconds > 0) t.totalSpan.inMicroseconds,
    ];

    final Map<String, Object?> result = <String, Object?>{
      'mode': kReleaseMode ? 'release' : (kProfileMode ? 'profile' : 'debug'),
      'generatedAt': DateTime.now().toIso8601String(),
      'dataset': <String, Object?>{
        'feeds': report.feeds,
        'articles': report.articles,
      },
      'firstFrameMs': firstFrame.elapsedMilliseconds,
      'steadyScroll': summarizeFrames(steadyMicros),
      'batchLoadFrames': summarizeFrames(batchMicros),
      'note':
          '真实引擎 FrameTiming.totalSpan（含光栅化与 vsync 对齐）；'
          '滚动由 ScrollPosition.jumpTo 驱动',
    };

    // 两个通道都写：binding.reportData（driver 侧能拿到）与磁盘文件（便于人查）。
    binding.reportData = result;
    try {
      final Directory dir = Directory('${Directory.systemTemp.path}/flux-t052')
        ..createSync(recursive: true);
      File(
        '${dir.path}/t052_perf_frames.json',
      ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(result));
    } on FileSystemException {
      // 写盘失败不影响结论：driver 侧还有 reportData 一条路。
    }

    // 只做「真的测到了」这类结构性断言；是否达标交给报告判定（阈值尚未批准，
    // 手册 6.4 要求未批准阈值不可写通过）。
    expect(
      steadyMicros.length,
      greaterThan(20),
      reason: '稳态帧样本太少（$steadyMicros.length），测量不可信',
    );
  });
}

/// 一组帧耗时的统计摘要。
Map<String, Object?> summarizeFrames(List<int> micros) {
  if (micros.isEmpty) {
    return <String, Object?>{'samples': 0};
  }
  final List<int> sorted = List<int>.from(micros)..sort();
  int at(double q) => sorted[(q * (sorted.length - 1)).round()];
  double mean = 0;
  for (final int v in micros) {
    mean += v;
  }
  return <String, Object?>{
    'samples': micros.length,
    'p50Ms': at(0.50) / 1000,
    'p95Ms': at(0.95) / 1000,
    'maxMs': sorted.last / 1000,
    'meanMs': mean / micros.length / 1000,
    'over16_7ms': micros.where((int v) => v > kFrameBudgetMicros).length,
  };
}
