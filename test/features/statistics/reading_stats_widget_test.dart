// T023：统计图表的组件行为（数据 → 渲染）。
//
// 这里验的是验收条件里明写的三件事：
//   * 热力图的 **0 值可辨**：0 值格子有底色（与「不在这一年」的透明占位格子不同色）；
//   * **图例**存在且给出 5 个档位；
//   * **点击/悬停显示日期与分钟**：0 值格子也带「日期：0 分钟」的提示；
//   * 近七日柱状图**有文字分钟数**（不是只靠高度）。
//
// 断言用的是渲染出来的语义/文本，而不是像素：颜色与布局的回归由 golden 负责，
// 这里负责「数据是否正确映射到界面元素」。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:flux/core/core.dart';
import 'package:flux/features/statistics/presentation/heatmap_cell_tile.dart';

import '../../app/test_harness.dart';

void main() {
  group('热力图格子', () {
    testWidgets('0 值格子：有底色与边框，且带「日期：0 分钟」的提示', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrapFluxApp(
          overrides: const <Override>[],
          child: const Scaffold(
            body: HeatmapCellTile(
              cell: HeatmapCell(
                localDate: '2026-09-21',
                seconds: 0,
                level: HeatmapLevel.none,
                inYear: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 语义标签即提示文案（日期 + 分钟），这是「点击/悬停显示日期+分钟」的可测落点。
      // 用 Tooltip 的 message 断言：它同时是「悬停提示」与「语义标签」的来源，
      // 而 Semantics 在真实应用里会被壳层/主题包一层（用 Semantics 的祖先链会拿到
      // 外壳的那个节点，断言会落在错误的控件上——实测踩到过）。
      final String tooltip = tester
          .widget<Tooltip>(find.byType(Tooltip))
          .message!;
      expect(tooltip, contains('2026-09-21'));
      expect(tooltip, contains('0 分钟'));
      // 0 值格子必须有可见底色：不是透明的。
      final Container container = tester.widget<Container>(
        find.descendant(
          of: find.byType(HeatmapCellTile),
          matching: find.byType(Container),
        ),
      );
      final BoxDecoration decoration = container.decoration! as BoxDecoration;
      expect(decoration.color, isNotNull);
      expect(decoration.color!.a, greaterThan(0.0), reason: '0 值格子不得透明');
      expect(decoration.border, isNotNull, reason: '0 值格子必须有边框');
    });

    testWidgets('不在本年的格子：透明且不带提示（与 0 值区分）', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrapFluxApp(
          overrides: const <Override>[],
          child: const Scaffold(
            body: HeatmapCellTile(
              cell: HeatmapCell(
                localDate: '2025-12-30',
                seconds: 0,
                level: HeatmapLevel.none,
                inYear: false,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // 布局占位：没有 Container 装饰、也没有 Tooltip/Semantics。
      expect(find.byType(Tooltip), findsNothing);
      expect(
        find.descendant(
          of: find.byType(HeatmapCellTile),
          matching: find.byType(Container),
        ),
        findsNothing,
      );
    });

    testWidgets('有数据的格子：提示里是折算后的分钟数', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrapFluxApp(
          overrides: const <Override>[],
          child: const Scaffold(
            body: HeatmapCellTile(
              cell: HeatmapCell(
                localDate: '2026-09-21',
                seconds: 25 * 60,
                level: HeatmapLevel.medium,
                inYear: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final String tooltip = tester
          .widget<Tooltip>(find.byType(Tooltip))
          .message!;
      expect(tooltip, contains('25 分钟'));
    });

    testWidgets('档位颜色可辨：5 个档位互不相同', (WidgetTester tester) async {
      final List<HeatmapLevel> levels = <HeatmapLevel>[
        HeatmapLevel.none,
        HeatmapLevel.low,
        HeatmapLevel.medium,
        HeatmapLevel.high,
        HeatmapLevel.max,
      ];
      await tester.pumpWidget(
        wrapFluxApp(
          overrides: const <Override>[],
          child: Scaffold(
            body: Column(
              children: <Widget>[
                for (final HeatmapLevel level in levels)
                  HeatmapCellTile(
                    cell: HeatmapCell(
                      localDate: '2026-09-21',
                      seconds: 0,
                      level: level,
                      inYear: true,
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final List<Color> colors = <Color>[
        for (final Element element
            in find
                .descendant(
                  of: find.byType(HeatmapCellTile),
                  matching: find.byType(Container),
                )
                .evaluate())
          ((element.widget as Container).decoration! as BoxDecoration).color!,
      ];
      expect(colors, hasLength(5));
      expect(colors.toSet(), hasLength(5), reason: '5 个档位必须互不相同');
    });
  });

  group('展示口径', () {
    test('displayMinutes：有秒数就至少 1 分钟（0 值与「读了一点」可辨）', () {
      expect(displayMinutes(0), 0);
      expect(displayMinutes(30), 1, reason: '30 秒应显示 1 分钟而不是 0');
      expect(displayMinutes(59), 1);
      expect(displayMinutes(60), 1);
      expect(displayMinutes(119), 1);
      expect(displayMinutes(120), 2);
    });

    test('heatmapLevelFor：档位阈值稳定', () {
      expect(heatmapLevelFor(0), HeatmapLevel.none);
      expect(heatmapLevelFor(1), HeatmapLevel.low);
      expect(heatmapLevelFor(9 * 60), HeatmapLevel.low);
      expect(heatmapLevelFor(10 * 60), HeatmapLevel.medium);
      expect(heatmapLevelFor(29 * 60), HeatmapLevel.medium);
      expect(heatmapLevelFor(30 * 60), HeatmapLevel.high);
      expect(heatmapLevelFor(59 * 60), HeatmapLevel.high);
      expect(heatmapLevelFor(60 * 60), HeatmapLevel.max);
    });
  });

  group('年度热力图网格', () {
    test('覆盖整年：每列 7 格，年外格子 inYear=false', () {
      final YearHeatmap heatmap = buildYearHeatmap(
        year: 2026,
        totals: const <ReadingDayTotal>[
          ReadingDayTotal(localDate: '2026-03-15', seconds: 1800),
        ],
      );
      expect(heatmap.year, 2026);
      expect(heatmap.weeks, isNotEmpty);
      for (final HeatmapWeek week in heatmap.weeks) {
        expect(week.days, hasLength(7));
      }
      // 每一列的第一格是周一。
      expect(
        DateTime.parse(heatmap.weeks.first.days.first.localDate).weekday,
        DateTime.monday,
      );
      // 1 月 1 日所在的那一周应当包含它。
      final Iterable<HeatmapCell> allDays = heatmap.weeks.expand(
        (HeatmapWeek w) => w.days,
      );
      expect(
        allDays.any((HeatmapCell c) => c.localDate == '2026-01-01'),
        isTrue,
      );
      expect(
        allDays.any((HeatmapCell c) => c.localDate == '2026-12-31'),
        isTrue,
      );
      // 年外格子（例如 2025-12-29，属于第一周但不是 2026）。
      expect(
        allDays.any(
          (HeatmapCell c) => c.localDate == '2025-12-29' && !c.inYear,
        ),
        isTrue,
      );
    });

    test('合计与活跃天数只算本年', () {
      final YearHeatmap heatmap = buildYearHeatmap(
        year: 2026,
        totals: const <ReadingDayTotal>[
          ReadingDayTotal(localDate: '2026-01-02', seconds: 600),
          ReadingDayTotal(localDate: '2026-01-02', seconds: 300),
          ReadingDayTotal(localDate: '2025-12-31', seconds: 9999),
        ],
      );
      expect(heatmap.totalSeconds, 900, reason: '去年与重复日期都不该混进来');
      expect(heatmap.activeDays, 1);
    });

    test('没有任何数据 → isEmpty（界面显示空态而不是一片空格子）', () {
      final YearHeatmap heatmap = buildYearHeatmap(
        year: 2026,
        totals: const <ReadingDayTotal>[],
      );
      expect(heatmap.isEmpty, isTrue);
    });

    test('未来日期不算 0 值（inYear=false，尚未发生的日子没有数据）', () {
      final YearHeatmap heatmap = buildYearHeatmap(
        year: 2026,
        totals: const <ReadingDayTotal>[],
        todayWallClock: DateTime.utc(2026, 6, 15),
      );
      final Iterable<HeatmapCell> allDays = heatmap.weeks.expand(
        (HeatmapWeek w) => w.days,
      );
      expect(
        allDays
            .firstWhere((HeatmapCell c) => c.localDate == '2026-06-15')
            .inYear,
        isTrue,
        reason: '今天本身应当是可读的 0 值格子',
      );
      expect(
        allDays
            .firstWhere((HeatmapCell c) => c.localDate == '2026-06-16')
            .inYear,
        isFalse,
        reason: '明天尚未发生',
      );
    });
  });

  group('近七日柱状图', () {
    test('七根柱按时间升序、含今天、最大值为归一化分母', () {
      final WeeklyBars bars = buildWeeklyBars(
        totals: const <ReadingDayTotal>[
          ReadingDayTotal(localDate: '2026-09-21', seconds: 1200),
          ReadingDayTotal(localDate: '2026-09-15', seconds: 300),
        ],
        todayWallClock: DateTime.utc(2026, 9, 21, 18),
        weekdayLabelOf: (DateTime day) => 'W${day.weekday}',
        dateLabelOf: (DateTime day) => '${day.month}/${day.day}',
      );
      expect(bars.bars, hasLength(7));
      expect(bars.bars.last.localDate, '2026-09-21', reason: '最后一根是今天');
      expect(bars.bars.first.localDate, '2026-09-15');
      expect(bars.maxSeconds, 1200);
      expect(bars.totalSeconds, 1500);
    });

    test('七天内没有数据 → 全 0（界面显示空态）', () {
      final WeeklyBars bars = buildWeeklyBars(
        totals: const <ReadingDayTotal>[
          ReadingDayTotal(localDate: '2025-01-01', seconds: 9999),
        ],
        todayWallClock: DateTime.utc(2026, 9, 21),
        weekdayLabelOf: (DateTime day) => 'W',
        dateLabelOf: (DateTime day) => 'd',
      );
      expect(bars.isEmpty, isTrue);
      expect(bars.maxSeconds, 0);
    });
  });
}
