// T023：统计页端到端（真实内存库 + 真实控制器 + 真实界面）。
//
// 与纯函数/组件用例互补：这里验的是**接线**——真实 store 写进去的行能不能被控制器
// 读出来、聚合结果能不能出现在热力图与柱状图上、清空是否真的把库里的行删掉。
//
// 用假时钟与时区覆盖 provider：统计的时间必须能确定性构造，因此这一层不依赖真实
// 系统时间（生产组合根给的是 SystemClock + 设备时区，见 app_providers.dart）。
library;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:flux/core/core.dart';
import 'package:flux/features/statistics/application/reading_stats_ports.dart';
import 'package:flux/features/statistics/presentation/heatmap_cell_tile.dart';
import 'package:flux/features/statistics/presentation/reading_stats_page.dart';
import 'package:flux/infrastructure/local/database.dart';
import 'package:flux/infrastructure/local/reading_stats_store.dart';

import '../../app/test_harness.dart';

const SessionLocalZone shanghai = FixedOffsetZone(
  Duration(hours: 8),
  ianaName: 'Asia/Shanghai',
);

void main() {
  late TestBootstrap bootstrap;
  late FakeClock clock;
  late DriftReadingStatsStore store;
  late int articleId;

  setUp(() async {
    bootstrap = TestBootstrap();
    // 用「今天」固定为 2026-09-21（当地），让柱状图与热力图都有确定的数据。
    clock = FakeClock(start: DateTime.utc(2026, 9, 21, 4));
    store = DriftReadingStatsStore(bootstrap.database);
    await bootstrap.database.customSelect('SELECT 1').get();
    final int feedId = await bootstrap.database
        .into(bootstrap.database.feeds)
        .insert(
          FeedsCompanion.insert(
            syncId: 'feed-e2e',
            normalizedUrl: 'https://e2e.example.com/feed.xml',
            name: '端到端源',
          ),
        );
    articleId = await bootstrap.database
        .into(bootstrap.database.articles)
        .insert(
          ArticlesCompanion.insert(
            feedId: Value<int?>(feedId),
            title: '端到端文章',
            identityBasis: IdentityBasis.guid,
          ),
        );
  });

  tearDown(() async {
    await bootstrap.dispose();
  });

  /// 覆盖统计相关的三个 provider（时区、时钟、统计存储）。
  ///
  /// 必须走 bootstrapOverrides 的参数（而不是在这里再 override 一次）：Riverpod 禁止
  /// 同一容器里重复覆盖同一个 Provider，测试里再覆盖会直接断言失败。
  List<Override> statsOverrides() => bootstrap.overrides(
    sessionZone: shanghai,
    statsClock: clock,
    readingStatsStore: store,
  );

  Future<void> seed({required String localDate, required int seconds}) async {
    final DateTime startedAt = shanghai.toUtc(
      DateTime.utc(
        int.parse(localDate.substring(0, 4)),
        int.parse(localDate.substring(5, 7)),
        int.parse(localDate.substring(8, 10)),
        10,
      ),
    );
    await store.appendSessions(<ReadingSessionDraft>[
      ReadingSessionDraft(
        articleId: articleId,
        startedAt: startedAt,
        endedAt: startedAt.add(Duration(seconds: seconds)),
        effectiveSeconds: seconds,
        timeZone: 'Asia/Shanghai',
        localDate: localDate,
      ),
    ]);
  }

  testWidgets('有数据：热力图与柱状图都渲染出真实分钟数', (WidgetTester tester) async {
    await seed(localDate: '2026-09-21', seconds: 25 * 60);
    await seed(localDate: '2026-09-19', seconds: 5 * 60);
    await setSurfaceSize(tester, const Size(1200, 1400));

    await tester.pumpWidget(
      wrapFluxApp(
        child: const ReadingStatsPage(),
        overrides: statsOverrides(),
        localeOverride: const Locale('zh'),
      ),
    );
    await tester.pumpAndSettle();

    // 年份合计（30 分钟）与活跃天数（2 天）出现在页面上。
    expect(find.textContaining('30 分钟'), findsOneWidget);
    expect(find.textContaining('2 天'), findsOneWidget);
    // 近七日的柱顶文字：5 与 25 两个分钟数。
    expect(find.text('25'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
    // 热力图格子存在（0 值格子也应可见）。
    expect(find.byType(HeatmapCellTile), findsWidgets);
  });

  testWidgets('无数据：两处都显示空态，而不是一片空图表', (WidgetTester tester) async {
    await setSurfaceSize(tester, const Size(1200, 1400));
    await tester.pumpWidget(
      wrapFluxApp(
        child: const ReadingStatsPage(),
        overrides: statsOverrides(),
        localeOverride: const Locale('zh'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('这一年还没有阅读记录。'), findsOneWidget);
    expect(find.text('近七日还没有阅读记录。'), findsOneWidget);
  });

  testWidgets('清空：确认后库里的会话真的没了，且设置值不受影响', (WidgetTester tester) async {
    await seed(localDate: '2026-09-21', seconds: 600);
    await bootstrap.settingsRepository.write(
      SettingId.set015,
      <String, Object?>{'enabled': true, 'idlePauseMinutes': 7},
    );
    await setSurfaceSize(tester, const Size(1200, 1400));

    await tester.pumpWidget(
      wrapFluxApp(
        child: const ReadingStatsPage(),
        overrides: statsOverrides(),
        localeOverride: const Locale('zh'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('10 分钟'), findsWidgets);

    await tester.tap(find.text('清空统计'));
    await tester.pumpAndSettle();
    // 确认对话框必须先出现（破坏性操作不得一键完成）。
    expect(find.text('清空阅读统计？'), findsOneWidget);
    await tester.tap(find.text('清空'));
    await tester.pumpAndSettle();

    // 库里真的空了。
    expect((await store.activeYears()).unwrap(), isEmpty);
    expect(
      (await store.dailyTotals(
        fromDate: '2026-01-01',
        toDate: '2026-12-31',
      )).unwrap(),
      isEmpty,
    );
    // 设置值保留（关掉统计 ≠ 清空历史，反之亦然）。
    final Result<Object?> stored = await bootstrap.settingsRepository.read(
      SettingId.set015,
    );
    expect(
      (stored.valueOrNull! as Map<String, Object?>)['idlePauseMinutes'],
      7,
    );
    // 界面回到空态。
    expect(find.text('这一年还没有阅读记录。'), findsOneWidget);
  });

  testWidgets('取消清空：对话框关掉后数据仍在', (WidgetTester tester) async {
    await seed(localDate: '2026-09-21', seconds: 600);
    await setSurfaceSize(tester, const Size(1200, 1400));
    await tester.pumpWidget(
      wrapFluxApp(
        child: const ReadingStatsPage(),
        overrides: statsOverrides(),
        localeOverride: const Locale('zh'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('清空统计'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect((await store.activeYears()).unwrap(), <int>[2026]);
  });

  testWidgets('关掉开关只改设置，不删历史', (WidgetTester tester) async {
    await seed(localDate: '2026-09-21', seconds: 600);
    await setSurfaceSize(tester, const Size(1200, 1400));
    await tester.pumpWidget(
      wrapFluxApp(
        child: const ReadingStatsPage(),
        overrides: statsOverrides(),
        localeOverride: const Locale('zh'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    final Result<Object?> stored = await bootstrap.settingsRepository.read(
      SettingId.set015,
    );
    expect((stored.valueOrNull! as Map<String, Object?>)['enabled'], isFalse);
    // 历史仍在。
    expect((await store.activeYears()).unwrap(), <int>[2026]);
    // 页面明确说明「已关闭，本页显示的是已有历史」。
    expect(find.textContaining('阅读统计已关闭'), findsOneWidget);
  });

  testWidgets('年份切换：数据来自真实年份列表', (WidgetTester tester) async {
    await seed(localDate: '2024-03-01', seconds: 600);
    await seed(localDate: '2026-09-21', seconds: 900);
    await setSurfaceSize(tester, const Size(1200, 1400));
    await tester.pumpWidget(
      wrapFluxApp(
        child: const ReadingStatsPage(),
        overrides: statsOverrides(),
        localeOverride: const Locale('zh'),
      ),
    );
    await tester.pumpAndSettle();
    // 默认选中有数据的最近年份（2026 → 15 分钟）。
    expect(find.textContaining('15 分钟'), findsOneWidget);
    // 切到 2024。
    await tester.tap(find.byType(DropdownButton<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2024').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('10 分钟'), findsWidgets);
  });

  test('统计端口默认实现未被覆盖时必须抛错（漏接线不能静默）', () {
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[],
    );
    addTearDown(container.dispose);
    // Riverpod 会把 provider 内部抛出的错误包一层 ProviderException，因此断言的是
    // 「读取一定失败」以及失败原因指向**漏接线**（默认实现里的那段说明），而不是
    // 直接匹配 StateError 类型。
    expect(
      () => container.read(sessionZoneProvider),
      throwsA(
        predicate<Object>(
          (Object error) => error.toString().contains('未被组合根覆盖'),
          '错误信息必须指出是漏接线',
        ),
      ),
    );
    expect(
      () => container.read(readingStatsProvider),
      throwsA(
        predicate<Object>(
          (Object error) => error.toString().contains('未被组合根覆盖'),
          '错误信息必须指出是漏接线',
        ),
      ),
    );
  });
}
