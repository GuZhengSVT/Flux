// 设置 → 新闻生成页的「每日定时总结」小节（T040；SET-056/057、D-08）。
//
// 三条界面承诺：
//
//   1) **状态是完整的**：开关、时点、下次运行时间、今日是否已完成、是否正在运行、以及「等待
//      配置」的**具体原因**（缺模型 / 缺 Key / 未确认费用告知 / 模型列表读失败）各有一句文案。
//      把它们合成一句「等待配置」会让用户不知道该去配什么——而这一项正是默认开启，用户
//      第一次打开设置时最可能看到的就是它。
//   2) **「等待配置」明确说不发请求**：这是 D-08 的核心承诺，界面上必须能看到，不能只写在
//      文档里。
//   3) **费用告知的确认是一句可读的告知**，不是「我已了解」这种空洞的勾选框：正文说清
//      「每天几点、会联网检索与调用模型、可能产生费用、当天已有成功版本不重复跑」，
//      以及 macOS 上应用退出后不后台执行、错过的时点下次启动补跑一次。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flux/core/core.dart';
import 'package:flux/core/design/design_tokens.dart';
import 'package:flux/features/settings/application/settings_controller.dart';
import 'package:flux/l10n/l10n.dart';
import 'package:flux/ui/ui.dart';

import '../application/daily_news_providers.dart';
import '../application/daily_news_scheduler.dart';
import '../application/daily_news_settings.dart';
import '../application/news_run_providers.dart';

/// 定时总结小节。
class NewsScheduleSection extends ConsumerStatefulWidget {
  /// 构造小节。
  const NewsScheduleSection({super.key});

  @override
  ConsumerState<NewsScheduleSection> createState() =>
      _NewsScheduleSectionState();
}

class _NewsScheduleSectionState extends ConsumerState<NewsScheduleSection> {
  bool _busy = false;
  bool _searchMissing = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadSearchState());
    // 进入设置页先刷新一次状态：它只**评估**（缺模型/缺 Key/未确认告知各有一句文案），
    // 不运行任务——打开设置不应该启动一次付费运行。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(ref.read(dailyNewsSchedulerProvider).refreshStatus());
    });
  }

  Future<void> _loadSearchState() async {
    final bool present = await hasEnabledSearchService(
      ref.read(newsSearchAvailabilityProvider),
    );
    if (!mounted) {
      return;
    }
    setState(() => _searchMissing = !present);
  }

  /// 写 SET-056（本机项）。
  Future<void> _setEnabled(bool value) async {
    await _write(SettingId.set056, value);
    await _reevaluate();
  }

  /// 写 SET-057（共通项）。
  Future<void> _setTime(int minutes) async {
    await _write(SettingId.set057, formatTimeOfDay(minutes));
    await _reevaluate();
  }

  Future<void> _write(SettingId id, Object? value) async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    final AppLocalizations l10n = AppLocalizations.of(context);
    final Result<Object?> written = await ref
        .read(settingsStoreProvider)
        .writeSetting(id, value);
    if (!mounted) {
      return;
    }
    setState(() => _busy = false);
    if (written.isErr) {
      // 写入失败必须可见：静默失败会让界面显示一个并未保存的时点。
      _notify(l10n.newsRequiredSaveFailed(written.errorOrNull!.kind));
    }
  }

  /// 让调度器按新设置重新评估一次（不必等到下一个整分钟）。
  Future<void> _reevaluate() async {
    await ref.read(dailyNewsSchedulerProvider).refreshStatus();
  }

  /// 确认费用与数据发送告知。
  Future<void> _acknowledge() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final Result<void> saved = await ref
        .read(newsCostNoticeStoreProvider)
        .acknowledge();
    if (!mounted) {
      return;
    }
    if (saved.isErr) {
      _notify(l10n.newsScheduleCostNoticeFailed(saved.errorOrNull!.kind));
      return;
    }
    _notify(l10n.newsScheduleCostNoticeDone);
    await _reevaluate();
  }

  void _notify(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final DailyNewsStatus? status = ref.watch(dailyNewsStatusProvider);
    final bool waiting = status?.kind == DailyNewsDueKind.waitingConfiguration;
    final bool needsCostNotice = status?.waitingReason == 'costNotice';
    // 开关与时点直接反映**当前策略**：状态还没评估过时用注册表默认值（与 SET-056/057 一致），
    // 因此第一次进入设置页也显示真实默认（开 / 20:00），而不是一个空控件。
    final bool enabled = status?.enabled ?? readDailyNewsEnabled(null);
    final int minutes =
        parseTimeOfDayMinutes(status?.timeOfDay) ?? readDailyNewsTime(null);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: enabled,
          onChanged: _busy
              ? null
              : (bool value) => unawaited(_setEnabled(value)),
          title: Text(l10n.newsScheduleEnableLabel),
          subtitle: Text(l10n.newsScheduleEnableHint),
        ),
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                l10n.newsScheduleTimeLabel,
                style: theme.textTheme.bodyMedium,
              ),
            ),
            Text(formatTimeOfDay(minutes), style: theme.textTheme.titleMedium),
            const SizedBox(width: FluxSpacing.xs),
            OutlinedButton(
              onPressed: _busy ? null : () => unawaited(_pickTime(minutes)),
              child: Text(l10n.newsScheduleTimeEdit),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: FluxSpacing.xxs),
          child: Text(
            l10n.newsScheduleTimeHint(status?.timeZone ?? '-'),
            style: theme.textTheme.labelSmall,
          ),
        ),
        // 关闭时也要有一行说明：开关关掉之后用户需要看到「这台设备不会自动跑」这句话，
        // 而不是只剩一个关着的开关（那与「还没评估过」在界面上无法区分）。
        _stateLine(l10n, status, enabled: enabled),
        if (waiting) ...<Widget>[
          const SizedBox(height: FluxSpacing.xs),
          StatusBanner(
            severity: StatusBannerSeverity.warning,
            title: l10n.newsScheduleWaitingTitle,
            message: _waitingReasonText(l10n, status?.waitingReason),
          ),
          if (needsCostNotice) ...<Widget>[
            Padding(
              padding: const EdgeInsets.only(top: FluxSpacing.xs),
              child: Text(
                l10n.newsScheduleCostNoticeBody(formatTimeOfDay(minutes)),
                style: theme.textTheme.bodySmall,
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton(
                onPressed: _busy ? null : () => unawaited(_acknowledge()),
                child: Text(l10n.newsScheduleCostNoticeAck),
              ),
            ),
          ],
        ],
        if (_searchMissing)
          Padding(
            padding: const EdgeInsets.only(top: FluxSpacing.xs),
            child: Text(
              l10n.newsScheduleSearchMissing,
              style: theme.textTheme.labelSmall,
            ),
          ),
        if (status?.lastErrorKind case final String kind) ...<Widget>[
          const SizedBox(height: FluxSpacing.xxs),
          Text(
            l10n.newsScheduleLastRunFailed(kind),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.tertiary,
            ),
          ),
        ],
        Padding(
          padding: const EdgeInsets.only(top: FluxSpacing.xs),
          child: Text(
            l10n.newsScheduleInterruptedNote,
            style: theme.textTheme.labelSmall,
          ),
        ),
      ],
    );
  }

  /// 一行状态：下次运行时间 / 今日已完成 / 正在运行 / 已关闭。
  Widget _stateLine(
    AppLocalizations l10n,
    DailyNewsStatus? status, {
    required bool enabled,
  }) {
    final ThemeData theme = Theme.of(context);
    if (status == null) {
      return const SizedBox.shrink();
    }
    if (!enabled) {
      return Text(l10n.newsScheduleDisabled, style: theme.textTheme.bodySmall);
    }
    if (status.running) {
      return Text(l10n.newsScheduleRunning, style: theme.textTheme.bodySmall);
    }
    if (status.completedToday) {
      return Text(
        l10n.newsScheduleCompletedToday,
        style: theme.textTheme.bodySmall,
      );
    }
    final DateTime? next = status.nextRunUtc;
    if (next == null) {
      return Text(l10n.newsScheduleDisabled, style: theme.textTheme.bodySmall);
    }
    // 用**评估时固化的偏移**把 UTC 换算成当地读数：界面显示的是「下次几点会跑」，
    // 而那一刻的当地时间正是用户关心的东西。
    final DateTime local = next.add(
      Duration(minutes: _offsetMinutesFor(status)),
    );
    String two(int value) => value.toString().padLeft(2, '0');
    return Text(
      l10n.newsScheduleNextRun(
        '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}',
      ),
      style: theme.textTheme.bodySmall,
    );
  }

  /// 从状态里的计划时刻反推设备偏移（分钟）。
  ///
  /// 不需要时区数据库：`scheduledAtUtc` 与「当地 `HH:mm`」的差正好是这个偏移，而它是调度器
  /// 在评估时用同一个 [SessionLocalZone] 算出来的，因此两者一定一致。没有计划时刻时按 0
  /// （即显示 UTC 读数）——显示一个编造的偏移比显示 UTC 更糟。
  int _offsetMinutesFor(DailyNewsStatus status) {
    final DateTime? scheduled = status.scheduledAtUtc;
    final int? minutes = parseTimeOfDayMinutes(status.timeOfDay);
    if (scheduled == null || minutes == null) {
      return 0;
    }
    final int wallMinutes =
        scheduled.toUtc().hour * 60 + scheduled.toUtc().minute;
    int offset = minutes - wallMinutes;
    // 归一化到 (-720, 720]：跨午夜时差值会绕一圈（例如 UTC-5 的 20:00 计划 → 差值 +1500）。
    while (offset <= -720) {
      offset += 1440;
    }
    while (offset > 720) {
      offset -= 1440;
    }
    return offset;
  }

  String _waitingReasonText(AppLocalizations l10n, String? reason) =>
      switch (reason) {
        'noEnabledModel' => l10n.newsScheduleWaitingNoModel,
        'noModelCredential' => l10n.newsScheduleWaitingNoCredential,
        'costNotice' => l10n.newsScheduleWaitingCostNotice,
        'modelReadFailed' => l10n.newsScheduleWaitingModelReadFailed,
        _ => l10n.newsScheduleWaitingUnknown,
      };

  Future<void> _pickTime(int currentMinutes) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: currentMinutes ~/ 60,
        minute: currentMinutes % 60,
      ),
      helpText: AppLocalizations.of(context).newsScheduleTimePickerTitle,
    );
    if (picked == null || !mounted) {
      return;
    }
    final int minutes = picked.hour * 60 + picked.minute;
    await _setTime(minutes);
    if (!mounted) {
      return;
    }
    _notify(
      AppLocalizations.of(context)
          .newsScheduleTimeSaved(formatTimeOfDay(minutes)),
    );
  }
}
