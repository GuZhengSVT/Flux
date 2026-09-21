// 统计页状态（T023）。
//
// 状态里刻意**不预先算好热力图与柱状图**：两者的标签是本地化文案，而控制器没有
// BuildContext。把年/日聚合结果与「今天」留给界面，界面用同一组纯函数
// （buildYearHeatmap / buildWeeklyBars）构造图形——这样 l10n 只出现在有 context 的地方，
// 而布局规则仍然只有一处实现。
library;

import 'package:flux/core/core.dart';

/// 统计页状态。
final class ReadingStatsState {
  /// 构造状态。
  const ReadingStatsState({
    required this.loaded,
    required this.enabled,
    required this.idleMinutes,
    required this.years,
    required this.selectedYear,
    required this.dailyTotals,
    required this.todayWallClock,
    this.error,
    this.actionMessage,
  });

  /// 是否已从存储读到有效值。
  final bool loaded;

  /// SET-015 的统计开关。
  final bool enabled;

  /// SET-015 的空闲暂停分钟数（1–30）。
  final int idleMinutes;

  /// 有数据的年份（倒序）。
  final List<int> years;

  /// 当前展示的年份。
  final int selectedYear;

  /// 覆盖 [selectedYear] 与近七日的按日合计。
  final List<ReadingDayTotal> dailyTotals;

  /// 「今天」的当地读数（按 SessionLocalZone 的编码约定）。
  final DateTime todayWallClock;

  /// 读取失败原因。
  final AppError? error;

  /// 最近一次动作的结果说明（清空成功/失败）。
  final String? actionMessage;

  /// 复制并覆盖字段。
  ReadingStatsState copyWith({
    bool? loaded,
    bool? enabled,
    int? idleMinutes,
    List<int>? years,
    int? selectedYear,
    List<ReadingDayTotal>? dailyTotals,
    DateTime? todayWallClock,
    AppError? error,
    bool clearError = false,
    String? actionMessage,
    bool clearActionMessage = false,
  }) => ReadingStatsState(
    loaded: loaded ?? this.loaded,
    enabled: enabled ?? this.enabled,
    idleMinutes: idleMinutes ?? this.idleMinutes,
    years: years ?? this.years,
    selectedYear: selectedYear ?? this.selectedYear,
    dailyTotals: dailyTotals ?? this.dailyTotals,
    todayWallClock: todayWallClock ?? this.todayWallClock,
    error: clearError ? null : (error ?? this.error),
    actionMessage: clearActionMessage
        ? null
        : (actionMessage ?? this.actionMessage),
  );

  /// 某个年份是否有数据。
  bool hasDataFor(int year) => years.contains(year);
}
