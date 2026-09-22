// 首页与滚动的帧级基线（T050 补充；架构第 8 节「60Hz 常规滚动多数帧 16.7ms 内」）。
//
// 为什么单独一个文件：这份用例要挂**真实的组件树**（阅读页 + 真实 Provider 装配），
// 因此需要 test/app 的 TestBootstrap；而 perf_baseline_test.dart 只测数据库层，两者的
// 依赖面与运行时长差别很大，混在一起会让「只想跑数据库基线」的人被迫等组件渲染。
//
// 默认**不采集**（50000 行数据集要几十秒），用 PERF_SEED_DATASET=true 显式触发。
//
// 口径说明（如实）：
//   1) 这里测的是**测试进程内的帧构建与布局耗时**，不是 VSync 对齐后的实际呈现；
//   2) 滚动用 ScrollPosition.jumpTo 而不是手势拖动：拖动会把指针事件分发与手势竞技场
//      一起算进帧耗时，而那部分与「滚动一帧要构建多少内容」无关。分开测才能看出真正的
//      瓶颈在哪；
//   3) **分两段测**：在已加载批次内滚动（稳态）与滚动到底触发下一批加载（有数据库读取）。
//      只报一个合并数字会掩盖「是稳态慢还是加载慢」——两者的修法完全不同。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flux/features/articles/presentation/reading_page.dart';
import 'package:flux/features/articles/presentation/article_card.dart';
import 'package:flux/infrastructure/local/database.dart';
import 'package:flux/infrastructure/local/perf_dataset.dart';

import '../app/test_harness.dart';

/// 是否采集（见文件头）。
const bool kRunFrameBaseline = bool.fromEnvironment('PERF_SEED_DATASET');

/// 60Hz 下的一帧预算。
const int kFrameBudgetMicros = 16700;

void main() {
  testWidgets('首屏与滚动帧耗时（50000 行数据集）', (WidgetTester tester) async {
    if (!kRunFrameBaseline) {
      markTestSkipped('未设置 PERF_SEED_DATASET=true，跳过帧基线');
      return;
    }
    final AppDatabase db = AppDatabase.memory();
    addTearDown(db.close);
    await db.customSelect('SELECT 1').get();
    await seedPerfDataset(db);

    final TestBootstrap bootstrap = TestBootstrap(database: db);
    addTearDown(bootstrap.dispose);
    await setSurfaceSize(tester, const Size(1400, 900));

    final Stopwatch firstFrame = Stopwatch()..start();
    await tester.pumpWidget(
      wrapFluxApp(
        child: const Scaffold(body: ReadingPage()),
        overrides: bootstrap.overrides(),
      ),
    );
    await tester.pump();
    firstFrame.stop();
    final int firstFrameMs = firstFrame.elapsedMilliseconds;
    await tester.pumpAndSettle();

    // 取**列表自己的** Scrollable：页面上还有别的可滚动部件（工具栏的 Wrap、
    // SegmentedButton 等），用 .first 会拿到它们——那些位置的 maxScrollExtent 是 0，
    // jumpTo 变成空操作，测出来的「帧耗时」只是几微秒的空转。
    final ScrollPosition position = tester
        .state<ScrollableState>(
          find.descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          ),
        )
        .position;
    // 自检：这个位置必须真的是**列表**的位置，而且确实能动。
    //
    // 为什么值得写：测出来的帧耗时如果只有几十微秒，最可能的解释不是「很快」，而是
    // 「这一帧什么都没干」——例如取到了别的 Scrollable、或者 jumpTo 被夹回原处。
    // 一条会静默测出假数字的性能用例比没有用例更糟，因此这里先证明测量本身有效。
    expect(
      position.maxScrollExtent,
      greaterThan(1000),
      reason: '取到的 ScrollPosition 不是文章列表（可滚距离过小）',
    );
    // 虚拟化自检：已加载 100 条，但**构建出来的卡片**必须远少于它。
    //
    // 这条断言是这套基线里最重要的一条：一旦列表退化成非虚拟化渲染（例如有人把
    // ListView.builder 换成 Column + SingleChildScrollView），帧耗时数字会变差，但
    // 「变差多少」是个连续量、容易被忽略；而「构建了 100 张卡片」这个事实是二值的。
    final int builtCards = find.byType(ArticleCardBody).evaluate().length;
    expect(
      builtCards,
      lessThan(60),
      reason: '虚拟化失效：已加载 100 条却构建了 $builtCards 张卡片',
    );

    // 第一段：稳态滚动。在**已加载的 100 条**范围内来回移动，不触发下一批加载。
    final List<int> steady = <int>[];
    for (int i = 0; i < 40; i++) {
      final double target = (i % 2 == 0 ? i : 40 - i) * 120.0;
      final Stopwatch frame = Stopwatch()..start();
      position.jumpTo(target.clamp(0, position.maxScrollExtent));
      await tester.pump();
      frame.stop();
      steady.add(frame.elapsedMicroseconds);
    }

    // 第二段：滚动到底触发下一批（含一次数据库读取与 100 行新内容构建）。
    final List<int> batchFrames = <int>[];
    int loadedBatches = 1;
    for (int i = 0; i < 6; i++) {
      final Stopwatch frame = Stopwatch()..start();
      position.jumpTo(position.maxScrollExtent);
      await tester.pump();
      await tester.pump();
      frame.stop();
      batchFrames.add(frame.elapsedMicroseconds);
      if (position.maxScrollExtent > (loadedBatches * 100 * 120.0)) {
        loadedBatches++;
      }
    }

    // 第三段：**帧耗时是否随已加载条数增长**。
    //
    // 这是比「P95 是多少」更重要的性质：虚拟化列表的帧耗时应当与已加载总量**无关**
    // （只与视口内条数有关）。若它随批次线性上升，说明有人在每帧遍历全部已加载条目
    // （例如在 build 里对整个 entries 做筛选或排序），而那类缺陷在 100 条时完全看不出来。
    //
    // 测量方式刻意与上一段区分：**只在列表顶部附近移动**（远不到底，因此不会触发新的
    // 批次加载），每轮之间刻意把位置推到最底以加载一批。这样「测量」与「加载」彻底分开
    // ——把两者混在一起时，测出来的差异可能只是「这次顺带读了几千行数据库」，
    // 而那属于上一段的结论。实测过：混在一起的写法会得到 1.7 秒的假数字。
    final List<double> roundP50 = <double>[];
    for (int round = 0; round < 6; round++) {
      final List<int> samples = <int>[];
      for (int i = 0; i < 20; i++) {
        final Stopwatch frame = Stopwatch()..start();
        position.jumpTo((i % 2 == 0 ? i : 20 - i) * 120.0);
        await tester.pump();
        frame.stop();
        samples.add(frame.elapsedMicroseconds);
      }
      samples.sort();
      roundP50.add(samples[samples.length ~/ 2] / 1000);
      // 加载下一批（不计入任何一次测量）。
      position.jumpTo(position.maxScrollExtent);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
    }

    final Map<String, Object?> report = <String, Object?>{
      'mode': 'debug',
      'note': '帧构建/布局耗时（测试进程内），非 VSync 呈现帧率；滚动用 jumpTo 驱动',
      'generatedAt': DateTime.now().toIso8601String(),
      'firstFrameMs': firstFrameMs,
      'loadedBatchesAfterScroll': loadedBatches,
      'steadyScroll': _stats(steady),
      'batchLoadFrames': _stats(batchFrames),
      'frameCostVsLoadedBatches': <String, Object?>{
        'loadedBatchesAtStart': loadedBatches,
        'topOfListP50MsPerRound': roundP50,
        'note':
            '每轮在列表顶部附近的帧耗时中位数；轮次之间各加载一批。'
            '数值不随轮次上升即说明帧耗时与已加载总量无关',
      },
    };
    final Directory out = Directory('build');
    if (!out.existsSync()) {
      out.createSync(recursive: true);
    }
    File('build/perf_frames.json')
        .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(report));
    // ignore: avoid_print
    print('PERF_FRAMES ${jsonEncode(report)}');
    expect(find.byType(ReadingPage), findsOneWidget);
    // 帧耗时不得随已加载条数显著增长。用 3 倍留足 JIT 预热与调度抖动的余量
    // （实测第一轮最慢、之后下降；真正的「每帧遍历全部条目」会表现为几十倍差距）。
    // 与 5ms 取较大者：绝对耗时很小时比值没有意义（0.02ms 变 0.05ms 不是回归）。
    expect(
      roundP50.last,
      lessThan(math.max(roundP50.first * 3, 5)),
      reason:
          '帧耗时随已加载条数增长：第 1 轮 ${roundP50.first}ms、'
          '第 ${roundP50.length} 轮 ${roundP50.last}ms（各轮 $roundP50）',
    );
  }, timeout: const Timeout(Duration(minutes: 20)));
}

/// 一组帧耗时的统计（微秒 → 毫秒，并统计越预算的帧数）。
Map<String, Object?> _stats(List<int> samples) {
  final List<int> sorted = <int>[...samples]..sort();
  return <String, Object?>{
    'samples': samples.length,
    'p50Ms': sorted[sorted.length ~/ 2] / 1000,
    'p95Ms':
        sorted[((sorted.length * 95) ~/ 100).clamp(0, sorted.length - 1)] /
        1000,
    'maxMs': sorted.last / 1000,
    'meanMs': sorted.reduce((int a, int b) => a + b) / sorted.length / 1000,
    'over16_7ms': samples.where((int v) => v > kFrameBudgetMicros).length,
    'note': '超过 16.7ms 的帧数',
  };
}
