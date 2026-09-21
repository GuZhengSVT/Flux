// 阅读统计的查询形状与聚合规则（T023；架构 5.3）。
//
// 分工：reading_session.dart 管「一段阅读怎么算、算在哪一天」；本文件管「已经按天
// 聚好的秒数怎么画」——年度热力图的格子布局、近七日柱状图的数据点、图例与历史年份。
// 两者都是纯函数，因此界面只做映射，不做日期算术。
//
// 三条与验收条件直接对应的选择：
//   1) **0 值与「不在这一年」是两种格子**。热力图上「那天读了 0 分钟」与「那天不在
//      本年度网格里」必须可辨（前者是数据，后者是布局留白），否则用户会以为日历缺角；
//   2) **分钟数是估计值的展示口径**。秒数落库，界面按分钟取整展示，并保证「有秒数就
//      至少显示 1 分钟」——显示 0 分钟会与「那天没读」混淆；
//   3) **历史年份来自数据**，不是「今年往前 N 年」。用户可能只读了三年前的一段时间，
//      凭空列出没有数据的年份只会让人以为统计丢失。
library;

import 'reading_session.dart';

/// 某一天的有效阅读秒数（已按 local_date 聚合）。
final class ReadingDayTotal {
  /// 构造一天的总量。
  const ReadingDayTotal({required this.localDate, required this.seconds});

  /// 本地日期键（YYYY-MM-DD，按会话时区归属）。
  final String localDate;

  /// 当日有效秒数合计。
  final int seconds;

  @override
  String toString() => 'ReadingDayTotal($localDate, ${seconds}s)';
}

/// 热力图格子的活跃档位（0 = 当天没有记录）。
enum HeatmapLevel {
  /// 没有有效阅读（0 值；与「不在这一年」不同，见 [HeatmapCell.inYear]）。
  none,

  /// 少量。
  low,

  /// 中等。
  medium,

  /// 较多。
  high,

  /// 很多。
  max,
}

/// 一个热力图格子。
final class HeatmapCell {
  /// 构造格子。
  const HeatmapCell({
    required this.localDate,
    required this.seconds,
    required this.level,
    required this.inYear,
  });

  /// 日期键（YYYY-MM-DD）。
  final String localDate;

  /// 当日有效秒数。
  final int seconds;

  /// 活跃档位。
  final HeatmapLevel level;

  /// 是否属于正在展示的那一年。
  ///
  /// false 表示这个格子只是布局占位（年末补齐整周、年初对齐星期），界面上必须与
  /// 「读了 0 分钟」区分开：前者是空白，后者是一个真实的零值。
  final bool inYear;
}

/// 一列（一周）格子；[weekIndex] 从 0 开始。
final class HeatmapWeek {
  /// 构造一周。
  const HeatmapWeek({required this.weekIndex, required this.days});

  /// 周序号（列序号）。
  final int weekIndex;

  /// 该周的 7 个格子（周一 → 周日）。
  final List<HeatmapCell> days;
}

/// 年度热力图。
final class YearHeatmap {
  /// 构造热力图。
  const YearHeatmap({
    required this.year,
    required this.weeks,
    required this.totalSeconds,
    required this.activeDays,
  });

  /// 年份。
  final int year;

  /// 周列（周一为每列第一格）。
  final List<HeatmapWeek> weeks;

  /// 全年有效秒数合计。
  final int totalSeconds;

  /// 有记录的天数（用于「这一年读了 N 天」这类文案）。
  final int activeDays;

  /// 全年是否没有任何数据（界面据此显示空态而不是一整片空格子）。
  bool get isEmpty => activeDays == 0;
}

/// 近七日柱状图的一个数据点。
final class WeeklyBar {
  /// 构造数据点。
  const WeeklyBar({
    required this.localDate,
    required this.seconds,
    required this.weekdayLabel,
    required this.dateLabel,
  });

  /// 日期键。
  final String localDate;

  /// 有效秒数。
  final int seconds;

  /// 星期标签（用于柱下方，例如「周一」）。由调用方按本地化传入。
  final String weekdayLabel;

  /// 日期标签（例如 9/22）。
  final String dateLabel;
}

/// 近七日柱状图数据。
final class WeeklyBars {
  /// 构造数据。
  const WeeklyBars({required this.bars, required this.maxSeconds});

  /// 七根柱，按时间升序（最早的在左）。
  final List<WeeklyBar> bars;

  /// 最大秒数（柱高归一化用）；全为 0 时为 0。
  final int maxSeconds;

  /// 合计秒数。
  int get totalSeconds =>
      bars.fold<int>(0, (int sum, WeeklyBar bar) => sum + bar.seconds);

  /// 七天是否全为 0。
  bool get isEmpty => totalSeconds == 0;
}

/// 把秒数折算成展示用的分钟数。
///
/// 规则：向下取整，但**只要秒数大于 0 就至少 1 分钟**。
/// 「读了 40 秒」显示成 0 分钟会与「那天没读」在界面上无法区分，而热力图的 0 值
/// 可辨正是验收条件之一。
int displayMinutes(int seconds) {
  if (seconds <= 0) {
    return 0;
  }
  final int minutes = seconds ~/ 60;
  return minutes == 0 ? 1 : minutes;
}

/// 秒数 → 热力图档位。
///
/// 阈值按**分钟**给出（10/30/60），因为这是给人看的粒度；口径是估计值而不是
/// 目标，因此取整数值、不引入百分比。
HeatmapLevel heatmapLevelFor(int seconds) {
  if (seconds <= 0) {
    return HeatmapLevel.none;
  }
  final int minutes = seconds ~/ 60;
  if (minutes < 10) {
    return HeatmapLevel.low;
  }
  if (minutes < 30) {
    return HeatmapLevel.medium;
  }
  if (minutes < 60) {
    return HeatmapLevel.high;
  }
  return HeatmapLevel.max;
}

/// 一个日期键（YYYY-MM-DD）是否属于 [year]。
bool localDateInYear(String localDate, int year) =>
    localDate.startsWith('$year-');

/// 构造某年的热力图网格。
///
/// 布局规则（周一为每列第一格，7 行 N 列）：
///   * 第一列 = 包含 1 月 1 日的那一周（可能含上一年末的几天）；
///   * 最后一列 = 包含 12 月 31 日的那一周（可能含下一年初的几天）；
///   * 落在年外或超出 [today] 的格子 [HeatmapCell.inYear] 为 false。
///
/// [todayWallClock] 是「今天」的当地读数（按 reading_session.dart 的编码约定），
/// 用来把未来的日子标成不可有数据的空格；传 null 表示不限制（历史年份）。
YearHeatmap buildYearHeatmap({
  required int year,
  required List<ReadingDayTotal> totals,
  DateTime? todayWallClock,
}) {
  // 用累加而不是构造 Map 字面量：同一日期出现两次时（存储层已按日聚合，但调用方完全
  // 可能传入多来源的合计，例如按文章查询后再汇总）字面量会让后一条**覆盖**而不是相加，
  // 于是热力图上少算一段。这一条由 reading_stats_widget_test 的「合计与活跃天数」用例抓到。
  final Map<String, int> byDate = <String, int>{};
  for (final ReadingDayTotal total in totals) {
    if (!localDateInYear(total.localDate, year)) {
      continue;
    }
    byDate.update(
      total.localDate,
      (int existing) => existing + total.seconds,
      ifAbsent: () => total.seconds,
    );
  }

  final DateTime first = DateTime.utc(year, 1, 1);
  final DateTime last = DateTime.utc(year, 12, 31);
  // DateTime.weekday: 周一 = 1 … 周日 = 7。把网格起点退到包含 1 月 1 日的那个周一。
  final DateTime gridStart = first.subtract(Duration(days: first.weekday - 1));
  // 网格终点推到包含 12 月 31 日的那个周日。
  final DateTime gridEnd = last.add(Duration(days: 7 - last.weekday));

  final List<HeatmapWeek> weeks = <HeatmapWeek>[];
  int weekIndex = 0;
  for (
    DateTime cursor = gridStart;
    !cursor.isAfter(gridEnd);
    cursor = cursor.add(const Duration(days: 7))
  ) {
    final List<HeatmapCell> days = <HeatmapCell>[];
    for (int offset = 0; offset < 7; offset++) {
      final DateTime day = cursor.add(Duration(days: offset));
      final String key = localDateKey(day);
      final bool inYear = day.year == year;
      // 未来的日子不算「0 值」：它还没有发生。用 inYear=false 表达它，使界面不必
      // 再判一次「这个格子是不是未来」。
      final bool beforeToday =
          todayWallClock == null || !day.isAfter(todayWallClock);
      final int seconds = inYear && beforeToday ? (byDate[key] ?? 0) : 0;
      days.add(
        HeatmapCell(
          localDate: key,
          seconds: seconds,
          level: heatmapLevelFor(seconds),
          inYear: inYear && beforeToday,
        ),
      );
    }
    weeks.add(HeatmapWeek(weekIndex: weekIndex, days: days));
    weekIndex++;
  }

  return YearHeatmap(
    year: year,
    weeks: weeks,
    totalSeconds: byDate.values.fold<int>(0, (int a, int b) => a + b),
    activeDays: byDate.values.where((int v) => v > 0).length,
  );
}

/// 构造近七日柱状图数据（含今天，按当地读数）。
///
/// [weekdayLabelOf] 与 [dateLabelOf] 由调用方注入：标签是**本地化文案**，
/// core 不带 l10n 依赖（架构 2.2 的分层与 l10n_test 的口径一致）。
WeeklyBars buildWeeklyBars({
  required List<ReadingDayTotal> totals,
  required DateTime todayWallClock,
  required String Function(DateTime day) weekdayLabelOf,
  required String Function(DateTime day) dateLabelOf,
}) {
  final Map<String, int> byDate = <String, int>{
    for (final ReadingDayTotal total in totals) total.localDate: total.seconds,
  };
  final DateTime today = DateTime.utc(
    todayWallClock.year,
    todayWallClock.month,
    todayWallClock.day,
  );
  final List<WeeklyBar> bars = <WeeklyBar>[];
  int maxSeconds = 0;
  for (int offset = 6; offset >= 0; offset--) {
    final DateTime day = today.subtract(Duration(days: offset));
    final String key = localDateKey(day);
    final int seconds = byDate[key] ?? 0;
    if (seconds > maxSeconds) {
      maxSeconds = seconds;
    }
    bars.add(
      WeeklyBar(
        localDate: key,
        seconds: seconds,
        weekdayLabel: weekdayLabelOf(day),
        dateLabel: dateLabelOf(day),
      ),
    );
  }
  return WeeklyBars(bars: bars, maxSeconds: maxSeconds);
}

/// 从日期键里取年份；解析失败返回 null（历史年份列表用它做过滤与排序）。
int? yearOfLocalDate(String localDate) {
  if (localDate.length < 4) {
    return null;
  }
  return int.tryParse(localDate.substring(0, 4));
}

/// 一次统计查询的结果（页面状态用的聚合视图）。
final class ReadingStatsSnapshot {
  /// 构造快照。
  const ReadingStatsSnapshot({required this.years, required this.dailyTotals});

  /// 有数据的年份，倒序（最近的在前）。
  final List<int> years;

  /// 被查询区间内的按日合计。
  final List<ReadingDayTotal> dailyTotals;

  /// 没有任何数据（页面据此显示空态）。
  bool get isEmpty => years.isEmpty && dailyTotals.isEmpty;
}
