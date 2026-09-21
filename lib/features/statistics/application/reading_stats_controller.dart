// 统计页控制器（T023）。
//
// 三条与验收条件对应的行为：
//   1) **清空必须走确认对话框（在界面层）且只清会话**：控制器只负责执行，产品判断
//      （是否确认）留在界面；实现上只调用 ReadingStatsStore.clearAll，不触碰任何
//      其他表；
//   2) **关掉统计开关不删历史**：SET-015 的 enabled 与「清空历史」是两件事，
//      T023 的验收明写「可关闭可清空」——关闭只停止记录，历史仍在，用户可以在
//      统计页看到它并自己决定是否清除；
//   3) **年份下拉来自真实数据**（activeYears），不凭空列出「今年往前 N 年」；
//      用户只读了三年前的一段时间时，列出空年份会被读成「统计丢了」。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flux/core/core.dart';
import 'package:flux/features/settings/application/settings_controller.dart';
import 'package:flux/features/settings/application/settings_store.dart';

import 'reading_stats_ports.dart';
import 'reading_stats_state.dart';

/// 统计页控制器。
final class ReadingStatsController extends AsyncNotifier<ReadingStatsState> {
  ReadingStatsStore get _store => ref.read(readingStatsProvider);

  SettingsStore get _settings => ref.read(settingsStoreProvider);

  @override
  Future<ReadingStatsState> build() async {
    // watch：端口/时区被替换（组合根注入或测试覆盖）后必须重读，否则界面会继续显示
    // 旧来源的数据（与 SettingsController 的同类说明一致）。
    final ReadingStatsStore store = ref.watch(readingStatsProvider);
    final SessionLocalZone zone = ref.watch(sessionZoneProvider);
    final Clock clock = ref.watch(statsClockProvider);
    final DateTime todayWallClock = zone.toLocal(clock.now());

    final (bool enabled, int idleMinutes) = await _readSettings();
    final Result<List<int>> years = await store.activeYears();
    if (years.isErr) {
      return ReadingStatsState(
        loaded: false,
        enabled: enabled,
        idleMinutes: idleMinutes,
        years: const <int>[],
        selectedYear: todayWallClock.year,
        dailyTotals: const <ReadingDayTotal>[],
        todayWallClock: todayWallClock,
        error: years.errorOrNull,
      );
    }
    final List<int> activeYears = years.unwrap();
    // 默认选中「有数据的最近年份」，没有数据时选今年：前者让用户打开就看到内容，
    // 后者让空态仍然有一个明确的年份标题（而不是一个空白的选择器）。
    final int selected = activeYears.isEmpty
        ? todayWallClock.year
        : activeYears.first;
    final Result<List<ReadingDayTotal>> totals = await _loadTotals(
      selected,
      todayWallClock,
    );
    if (totals.isErr) {
      return ReadingStatsState(
        loaded: false,
        enabled: enabled,
        idleMinutes: idleMinutes,
        years: activeYears,
        selectedYear: selected,
        dailyTotals: const <ReadingDayTotal>[],
        todayWallClock: todayWallClock,
        error: totals.errorOrNull,
      );
    }
    return ReadingStatsState(
      loaded: true,
      enabled: enabled,
      idleMinutes: idleMinutes,
      years: activeYears,
      selectedYear: selected,
      dailyTotals: totals.unwrap(),
      todayWallClock: todayWallClock,
    );
  }

  /// 切换展示年份并重新拉取该年 + 近七日的数据。
  Future<void> selectYear(int year) async {
    final ReadingStatsState? current = state.value;
    if (current == null) {
      return;
    }
    state = AsyncData<ReadingStatsState>(
      current.copyWith(selectedYear: year, clearActionMessage: true),
    );
    final Result<List<ReadingDayTotal>> totals = await _loadTotals(
      year,
      current.todayWallClock,
    );
    if (totals.isErr) {
      state = AsyncData<ReadingStatsState>(
        current.copyWith(
          selectedYear: year,
          error: totals.errorOrNull,
          clearActionMessage: true,
        ),
      );
      return;
    }
    state = AsyncData<ReadingStatsState>(
      current.copyWith(
        selectedYear: year,
        dailyTotals: totals.unwrap(),
        loaded: true,
        clearError: true,
        clearActionMessage: true,
      ),
    );
  }

  /// 清空统计历史（界面已确认）。
  ///
  /// 返回是否成功，供界面决定提示文案。只清会话表，见 store 实现的说明。
  Future<bool> clearHistory() async {
    final Result<int> removed = await _store.clearAll();
    if (removed.isErr) {
      final ReadingStatsState? current = state.value;
      if (current != null) {
        state = AsyncData<ReadingStatsState>(
          current.copyWith(error: removed.errorOrNull),
        );
      }
      return false;
    }
    // 清空后重新加载：年份列表会变空、热力图为空态。重新加载而不是就地清空状态，
    // 是为了让「库里真的没有了」与「界面以为没有了」不会分叉。
    ref.invalidateSelf();
    await future;
    return true;
  }

  /// 切换 SET-015 的统计开关。
  ///
  /// 只改设置值，**不动历史数据**。写失败时保留原值并记错误（与设置页的
  /// 「写入失败必须可见」同一口径）。
  Future<bool> setEnabled(bool enabled) async {
    final ReadingStatsState? current = state.value;
    final Result<Object?> written = await _settings.writeSetting(
      SettingId.set015,
      <String, Object?>{
        'enabled': enabled,
        'idlePauseMinutes': current?.idleMinutes ?? 5,
      },
    );
    if (written.isErr) {
      if (current != null) {
        state = AsyncData<ReadingStatsState>(
          current.copyWith(error: written.errorOrNull),
        );
      }
      return false;
    }
    if (current != null) {
      state = AsyncData<ReadingStatsState>(
        current.copyWith(enabled: enabled, clearError: true),
      );
    }
    return true;
  }

  /// 清掉错误提示。
  void clearError() {
    final ReadingStatsState? current = state.value;
    if (current == null || current.error == null) {
      return;
    }
    state = AsyncData<ReadingStatsState>(current.copyWith(clearError: true));
  }

  /// 拉取某年全年 + 近 7 日的按日合计。
  ///
  /// 一次查询覆盖两个展示需求（年度热力图、近七日柱状图），避免界面为同一个视图
  /// 发两次请求、也避免两处数据来自不同时刻。跨年时取并集：从「今年」与「所展示年份」
  /// 里较早的 1 月 1 日，到「七年窗口的末日」与「所展示年份的 12 月 31 日」里较晚的一天。
  Future<Result<List<ReadingDayTotal>>> _loadTotals(
    int year,
    DateTime todayWallClock,
  ) async {
    final DateTime today = DateTime.utc(
      todayWallClock.year,
      todayWallClock.month,
      todayWallClock.day,
    );
    final DateTime weekStart = today.subtract(const Duration(days: 6));
    final DateTime from = DateTime.utc(year, 1, 1).isBefore(weekStart)
        ? DateTime.utc(year, 1, 1)
        : weekStart;
    final DateTime yearEnd = DateTime.utc(year, 12, 31);
    final DateTime to = yearEnd.isAfter(today) ? yearEnd : today;
    return _store.dailyTotals(
      fromDate: localDateKey(from),
      toDate: localDateKey(to),
    );
  }

  /// 读 SET-015（enabled / idlePauseMinutes）。
  Future<(bool, int)> _readSettings() async {
    final Result<Object?> value = await _settings.readSetting(SettingId.set015);
    final Object? raw =
        value.valueOrNull ??
        SettingRegistry.findById(SettingId.set015)?.defaultValue;
    Object? enabled;
    Object? minutes;
    if (raw is Map<String, Object?>) {
      enabled = raw['enabled'];
      minutes = raw['idlePauseMinutes'];
    }
    return (enabled is bool ? enabled : true, _clampMinutes(minutes));
  }

  /// 把分钟数夹到 SET-015 的范围（1–30）；非法值退回默认 5。
  static int _clampMinutes(Object? raw) {
    final int value = raw is int ? raw : 5;
    if (value < 1) {
      return 1;
    }
    if (value > 30) {
      return 30;
    }
    return value;
  }
}

/// 统计页控制器的 Provider。
final AsyncNotifierProvider<ReadingStatsController, ReadingStatsState>
readingStatsControllerProvider =
    AsyncNotifierProvider<ReadingStatsController, ReadingStatsState>(
      ReadingStatsController.new,
    );
