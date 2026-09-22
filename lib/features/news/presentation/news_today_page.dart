// 今日新闻页（T039 的产品化形态；架构 4.4「日期/历史/生成进度/来源跳转」的界面落点）。
//
// 这一页只做**如实呈现**，六条承诺与文档一一对应：
//
//   1) **日期与历史**：顶部是「近 7 天」条带 + 日历弹层（可回溯任意历史日期）。历史记录
//      归属**生成当时的**时区（架构 4.4），因此翻到历史日期时会明确说明这一点，而不是
//      让用户以为「今天的记录不见了」。
//   2) **版本管理**：同一天的初稿/核验后各版本连同时间与模型列出，可以对照切换，也可以
//      删除**非当前**版本（当前版本不可删，见下）。
//   3) **真实进度**：六个阶段由编排层回调驱动，必访站**逐站**显示成功/失败/超时/跳过/
//      待获取——界面不自己演一遍动画。
//   4) **可取消**：取消是异步的，按钮进入「正在取消…」并禁用，不假装已经停下。
//   5) **引用可跳转**：RSS 引用跳本机文章，外部来源用系统浏览器打开；正文已被清理的
//      本机文章如实说明「原文已清理，只保留最小摘录」。
//   6) **状态完备**：无结果/材料不足/生成中/失败/取消/中断/等待配置/等待网络各有明确的
//      界面文案（架构第 7 节的每页状态要求）。
//
// 刻意**不做**的事：不把标签画成「可信/不可信」的两色信号（架构 4.4 禁止声称保证真实性），
// 也不隐藏被退回的条目（模型编造引用必须被用户看见）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flux/core/core.dart';
import 'package:flux/core/design/design_tokens.dart';
import 'package:flux/features/articles/application/article_platform_ports.dart';
import 'package:flux/features/articles/presentation/article_detail_page.dart';
import 'package:flux/features/ai/application/ai_task_providers.dart';
import 'package:flux/l10n/l10n.dart';
import 'package:flux/ui/ui.dart';

import '../application/news_run_service.dart';
import '../application/news_today_controller.dart';

/// 今日新闻页。
class NewsTodayPage extends ConsumerStatefulWidget {
  /// 构造页面。
  const NewsTodayPage({super.key});

  @override
  ConsumerState<NewsTodayPage> createState() => _NewsTodayPageState();
}

class _NewsTodayPageState extends ConsumerState<NewsTodayPage> {
  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<NewsTodayState> state = ref.watch(
      newsTodayControllerProvider,
    );
    final NewsTodayState? value = state.value;
    final bool generating = value?.generating ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _header(l10n, value),
        if (value != null && !value.isToday) _historyBanner(l10n, value),
        if (value?.lastError case final AppError error when !generating)
          _errorBanner(l10n, error, value!),
        if (generating) _progress(l10n, value!),
        Expanded(
          child: state.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (Object error, StackTrace stackTrace) => FluxEmptyState(
              title: l10n.newsLoadingFailed(
                error is AppError ? error.kind : '',
              ),
              body: error is AppError ? error.message : '',
              tone: EmptyStateTone.muted,
              icon: FluxIcon.inboxEmpty,
            ),
            data: (NewsTodayState v) => _body(l10n, v),
          ),
        ),
      ],
    );
  }

  Widget _header(AppLocalizations l10n, NewsTodayState? state) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final bool generating = state?.generating ?? false;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: FluxSpacing.lg,
        vertical: FluxSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(bottom: BorderSide(color: colors.outline)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        // 两行而不是一行：桌面窄窗与手机宽度下，「前一天/后一天 + 日历 + 生成」挤在一行
        // 会溢出（只在宽窗下好看），而溢出把按钮画成黄黑条纹——用户看得见，且看不出该点哪里。
        // 第一行只放日期导航与主操作，第二行放日期条带与日历入口。
        children: <Widget>[
          Row(
            children: <Widget>[
              // 左半区用 Expanded + Wrap：窄窗下日期导航换行，而不会把 Row 撑破。
              // 溢出把按钮画成黄黑条纹，用户看得见但看不出该点哪里。
              Expanded(
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: <Widget>[
                    IconButton(
                      tooltip: l10n.todayPreviousDay,
                      icon: const Icon(Icons.chevron_left),
                      onPressed: generating
                          ? null
                          : () => _select(_shiftDate(state?.localDate, -1)),
                    ),
                    Text(
                      state?.localDate ?? '',
                      style: theme.textTheme.titleMedium,
                    ),
                    if (state?.isToday ?? true)
                      Padding(
                        padding: const EdgeInsets.only(left: FluxSpacing.xxs),
                        child: Text(
                          l10n.todayIsToday,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ),
                    IconButton(
                      tooltip: l10n.todayNextDay,
                      icon: const Icon(Icons.chevron_right),
                      onPressed: generating
                          ? null
                          : () => _select(_shiftDate(state?.localDate, 1)),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: FluxSpacing.xs),
              if (generating)
                OutlinedButton(
                  onPressed: (state?.cancelling ?? false)
                      ? null
                      : () => ref
                            .read(newsTodayControllerProvider.notifier)
                            .cancel(),
                  child: Text(
                    (state?.cancelling ?? false)
                        ? l10n.todayCancelling
                        : l10n.todayCancelGenerate,
                  ),
                )
              else
                FilledButton.icon(
                  onPressed: () => _confirmAndGenerate(l10n, state),
                  icon: const Icon(Icons.auto_awesome, size: 18),
                  label: Text(
                    state?.hasSuccessVersion ?? false
                        ? l10n.todayRegenerate
                        : l10n.todayGenerate,
                  ),
                ),
            ],
          ),
          if (state != null) _recentStrip(l10n, state, generating: generating),
        ],
      ),
    );
  }

  /// 近 7 天条带：常用日期一次点击可达，且**标出哪些天有记录**。
  ///
  /// 「有记录」用点的形状表示而不是颜色深浅：颜色在浅深主题与色觉差异下会失真，
  /// 而「有没有生成过」是用户最想知道的一件事。
  Widget _recentStrip(
    AppLocalizations l10n,
    NewsTodayState state, {
    required bool generating,
  }) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final Set<String> withRecords = <String>{
      for (final NewsRunDateRef ref in state.dates) ref.localDate,
    };
    return Padding(
      padding: const EdgeInsets.only(top: FluxSpacing.xxs),
      child: Row(
        children: <Widget>[
          IconButton(
            tooltip: l10n.todayPickDate,
            icon: const Icon(Icons.calendar_month_outlined, size: 18),
            visualDensity: VisualDensity.compact,
            onPressed: generating ? null : () => _pickDate(state.today),
          ),
          Text(
            l10n.todayRecentLabel,
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: FluxSpacing.xs),
          // Expanded + Wrap：条带在窄窗下换行而不是溢出（Row 里放裸 Wrap 会拿到无限宽）。
          Expanded(
            child: Wrap(
              spacing: FluxSpacing.xxs,
              runSpacing: FluxSpacing.xxs,
              children: <Widget>[
                for (final String date in state.recentDates)
                  _recentChip(
                    date: date,
                    selected: date == state.localDate,
                    isToday: date == state.today,
                    hasRecord: withRecords.contains(date),
                    l10n: l10n,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _recentChip({
    required String date,
    required bool selected,
    required bool isToday,
    required bool hasRecord,
    required AppLocalizations l10n,
  }) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final String label = isToday ? l10n.todayTodayChip : date.substring(5);
    return Tooltip(
      message: hasRecord ? date : '$date（没有记录）',
      child: ChoiceChip(
        label: Text(label, style: Theme.of(context).textTheme.labelSmall),
        selected: selected,
        visualDensity: VisualDensity.compact,
        avatar: hasRecord
            ? Icon(Icons.circle, size: 8, color: scheme.primary)
            : null,
        onSelected: (bool _) => _select(date),
      ),
    );
  }

  Widget _historyBanner(AppLocalizations l10n, NewsTodayState state) {
    return StatusBanner(
      severity: StatusBannerSeverity.info,
      message: l10n.todayHistoryBanner(state.localDate),
    );
  }

  void _select(String date) {
    ref.read(newsTodayControllerProvider.notifier).selectDate(date);
  }

  /// 日历弹层：可选任意历史日期（不早于 2000-01-01，且不晚于「今天」）。
  ///
  /// 上限锁到今天：新闻总结只能为**当天**生成（架构 4.4 的输入快照按当日区间取材料），
  /// 允许选未来日期只会让用户点进去看到一片空白并以为它坏了。
  Future<void> _pickDate(String? today) async {
    final DateTime nowLocal = ref.read(aiTaskClockProvider).now();
    final DateTime? todayParsed = today == null
        ? null
        : DateTime.tryParse(today);
    final DateTime last =
        todayParsed ?? DateTime(nowLocal.year, nowLocal.month, nowLocal.day);
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: last,
      firstDate: DateTime(2000),
      lastDate: last,
    );
    if (picked == null || !mounted) {
      return;
    }
    _select(localDateKey(picked));
  }

  Widget _errorBanner(
    AppLocalizations l10n,
    AppError error,
    NewsTodayState state,
  ) {
    final String message = switch (error) {
      ValidationError(field: 'news.input', reason: 'newsMissingInput') =>
        l10n.todayShortfallNoInput,
      ValidationError(field: 'news.input', reason: 'newsGlobalDisabled') =>
        l10n.todayShortfallGlobalDisabled,
      _ => l10n.todayGenerateFailed(error.kind),
    };
    return StatusBanner(
      severity: StatusBannerSeverity.warning,
      message: message,
    );
  }

  /// 六阶段进度 + 必访站逐站状态。
  Widget _progress(AppLocalizations l10n, NewsTodayState state) {
    const List<NewsRunStage> stages = NewsRunStage.values;
    final int active = state.stage == null ? 0 : stages.indexOf(state.stage!);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: FluxSpacing.lg,
        vertical: FluxSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            l10n.todayProgressTitle,
            style: Theme.of(context).textTheme.labelMedium,
          ),
          const SizedBox(height: FluxSpacing.xxs),
          Wrap(
            spacing: FluxSpacing.xs,
            runSpacing: FluxSpacing.xxs,
            children: <Widget>[
              for (int i = 0; i < stages.length; i++)
                _stageChip(
                  label: _stageLabel(l10n, stages[i]),
                  done: i < active,
                  active: i == active,
                ),
            ],
          ),
          if (state.plannedSites.isNotEmpty) ...<Widget>[
            const SizedBox(height: FluxSpacing.xs),
            Text(
              l10n.todaySitesProgressTitle,
              style: Theme.of(context).textTheme.labelSmall,
            ),
            for (final NewsRequiredSite site in state.pendingSites)
              _siteRow(
                icon: Icons.schedule,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                text: '${site.name} — ${l10n.todaySitePending}',
              ),
            for (final NewsSiteFetchResult site in state.sites.reversed)
              _siteRow(
                icon: _siteIcon(site.status),
                color: site.ok
                    ? Theme.of(context).colorScheme.primary
                    : site.status == NewsSiteStatus.skipped
                    ? Theme.of(context).colorScheme.onSurfaceVariant
                    : Theme.of(context).colorScheme.tertiary,
                text: '${site.name} — ${_siteText(l10n, site)}',
              ),
          ],
        ],
      ),
    );
  }

  IconData _siteIcon(NewsSiteStatus status) => switch (status) {
    NewsSiteStatus.ok => Icons.check_circle_outline,
    NewsSiteStatus.timeout => Icons.timer_off_outlined,
    NewsSiteStatus.failed => Icons.error_outline,
    NewsSiteStatus.skipped => Icons.remove_circle_outline,
  };

  Widget _siteRow({
    required IconData icon,
    required Color color,
    required String text,
  }) => Padding(
    padding: const EdgeInsets.only(top: FluxSpacing.xxs),
    child: Row(
      children: <Widget>[
        Icon(icon, size: 16, color: color),
        const SizedBox(width: FluxSpacing.xxs),
        Expanded(
          child: Text(text, style: Theme.of(context).textTheme.bodySmall),
        ),
      ],
    ),
  );

  Widget _stageChip({
    required String label,
    required bool done,
    required bool active,
  }) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: FluxSpacing.xs,
        vertical: FluxSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: active ? scheme.surfaceContainerHigh : scheme.surface,
        borderRadius: BorderRadius.circular(FluxRadius.button),
        border: Border.all(color: active ? scheme.primary : scheme.outline),
      ),
      child: Text(
        '${done ? '✓ ' : ''}$label',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: active ? scheme.primary : scheme.onSurfaceVariant,
        ),
      ),
    );
  }

  String _stageLabel(AppLocalizations l10n, NewsRunStage stage) =>
      switch (stage) {
        NewsRunStage.snapshot => l10n.todayStageSnapshot,
        NewsRunStage.requiredSites => l10n.todayStageRequiredSites,
        NewsRunStage.search => l10n.todayStageSearch,
        NewsRunStage.generate => l10n.todayStageGenerate,
        NewsRunStage.verify => l10n.todayStageVerify,
        NewsRunStage.save => l10n.todayStageSave,
      };

  Widget _body(AppLocalizations l10n, NewsTodayState state) {
    final NewsRunRecord? record = state.current;
    if (record == null) {
      return _noUsableResult(l10n, state);
    }
    return ListView(
      padding: const EdgeInsets.all(FluxSpacing.md),
      children: <Widget>[
        if (state.clearedCitationCount > 0)
          StatusBanner(
            severity: StatusBannerSeverity.info,
            message: l10n.todayCacheClearedNotice(state.clearedCitationCount),
          ),
        if (record.siteResults.isNotEmpty) _siteSection(l10n, record),
        for (final NewsDraftItem item in record.items)
          _itemCard(l10n, state, record, item),
        // 元数据（模型、核验方法、材料数、退回条数）**总是**显示：它是「这份总结是怎么
        // 来的」的唯一线索，只在多版本时才给会让最常见的情形（当天只生成过一次）失去它。
        _metadataSection(l10n, record),
        _versionSection(l10n, state),
        const SizedBox(height: FluxSpacing.sm),
        Text(
          l10n.todayJournalNotice,
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }

  /// 没有可用成功版本时的状态区（无结果/材料不足/失败/取消/中断/等待配置/等待网络）。
  ///
  /// 关键设计：**有记录但没有成功版本**不等于「这一天没有生成过」。此时列出最近一次
  /// 记录的状态与中止阶段，让用户看得到「试过了、失败了、卡在哪一步」。
  Widget _noUsableResult(AppLocalizations l10n, NewsTodayState state) {
    final NewsRunRecord? latest = state.latest;
    if (latest == null) {
      return Center(
        child: FluxEmptyState(
          title: l10n.todayNoVersionTitle,
          body: l10n.todayNoVersionBody,
          tone: EmptyStateTone.neutral,
          secondaryNote: l10n.todayJournalNotice,
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(FluxSpacing.md),
      children: <Widget>[
        FluxCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                l10n.todayStatusTitle,
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: FluxSpacing.xxs),
              Text(_statusText(l10n, latest)),
              if (latest.stage case final NewsRunStage stage) ...<Widget>[
                const SizedBox(height: FluxSpacing.xxs),
                Text(
                  l10n.todayStatusStage(_stageLabel(l10n, stage)),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: FluxSpacing.sm),
        Text(
          l10n.todayNoResultYet,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        _versionSection(l10n, state),
      ],
    );
  }

  /// 记录状态 → 界面文案。九态**逐态**映射，没有落到「其它」的分支。
  String _statusText(AppLocalizations l10n, NewsRunRecord record) =>
      switch (record.status) {
        TaskStatus.succeeded || TaskStatus.partial => l10n.todayNoResultYet,
        TaskStatus.cancelled => l10n.todayStatusCancelled,
        TaskStatus.interrupted => l10n.todayStatusInterrupted,
        TaskStatus.waitingConfiguration => l10n.todayStatusWaitingConfiguration,
        TaskStatus.waitingNetwork => l10n.todayStatusWaitingNetwork,
        TaskStatus.queued || TaskStatus.running => l10n.todayStatusRunning,
        TaskStatus.failed => switch (record.errorKind) {
          'validation' => l10n.todayStatusInsufficient,
          final String? kind => l10n.todayStatusFailed(kind ?? 'failed'),
        },
      };

  Widget _siteSection(AppLocalizations l10n, NewsRunRecord record) {
    return FluxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            l10n.todaySiteFailedTitle,
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: FluxSpacing.xxs),
          for (final NewsSiteFetchResult site in record.siteResults)
            _siteRow(
              icon: _siteIcon(site.status),
              color: site.ok
                  ? Theme.of(context).colorScheme.primary
                  : site.status == NewsSiteStatus.skipped
                  ? Theme.of(context).colorScheme.onSurfaceVariant
                  : Theme.of(context).colorScheme.tertiary,
              text: '${site.name} — ${_siteText(l10n, site)}',
            ),
        ],
      ),
    );
  }

  String _siteText(AppLocalizations l10n, NewsSiteFetchResult site) =>
      switch (site.status) {
        NewsSiteStatus.ok => l10n.todaySiteOk(site.charCount),
        NewsSiteStatus.timeout => l10n.todaySiteTimeout,
        NewsSiteStatus.failed => l10n.todaySiteFailed(site.detailKind ?? ''),
        NewsSiteStatus.skipped => l10n.todaySiteSkipped,
      };

  Widget _itemCard(
    AppLocalizations l10n,
    NewsTodayState state,
    NewsRunRecord record,
    NewsDraftItem item,
  ) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: FluxSpacing.sm),
      child: FluxCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (!item.kept)
              Text(
                l10n.todayUnknownCitation(item.unknownSourceIds.join('、')),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.tertiary,
                ),
              ),
            Text(item.text, style: theme.textTheme.bodyMedium),
            const SizedBox(height: FluxSpacing.xs),
            Wrap(
              spacing: FluxSpacing.xs,
              runSpacing: FluxSpacing.xxs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                for (final NewsEvidenceLabel label in item.labels)
                  _labelBadge(l10n, label),
                for (final String sourceId in item.sourceIds)
                  _citationChip(l10n, state, record, sourceId),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _labelBadge(AppLocalizations l10n, NewsEvidenceLabel label) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final String text = switch (label) {
      NewsEvidenceLabel.singleSource => l10n.todayLabelSingleSource,
      NewsEvidenceLabel.insufficientMaterial => l10n.todayLabelInsufficient,
      NewsEvidenceLabel.sourceConflict => l10n.todayLabelConflict,
      NewsEvidenceLabel.notVerifiedOnline => l10n.todayLabelNotVerified,
    };
    return Tooltip(
      message: l10n.todayLabelLegend,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: FluxSpacing.xs,
          vertical: 2,
        ),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(FluxRadius.button),
          border: Border.all(color: scheme.outline),
        ),
        child: Text(text, style: Theme.of(context).textTheme.labelSmall),
      ),
    );
  }

  Widget _citationChip(
    AppLocalizations l10n,
    NewsTodayState state,
    NewsRunRecord record,
    String sourceId,
  ) {
    final ThemeData theme = Theme.of(context);
    final NewsMaterial? material = findMaterial(record.materials, sourceId);
    if (material == null) {
      return Chip(
        label: Text('$sourceId ?'),
        visualDensity: VisualDensity.compact,
        backgroundColor: theme.colorScheme.errorContainer,
      );
    }
    final String method = switch (material.accessMethod) {
      CitationAccessMethod.rss => l10n.todayCitationRss,
      CitationAccessMethod.fetch => l10n.todayCitationFetch,
      CitationAccessMethod.search => l10n.todayCitationSearch,
    };
    final NewsCitationIssue? issue = citationIssueOf(material);
    final bool cleared =
        material.articleId != null &&
        state.clearedArticleIds.contains(material.articleId);
    return Tooltip(
      message: <String>[
        material.title.isEmpty ? sourceId : material.title,
        if (material.url.isNotEmpty) material.url,
        if (material.excerpt.isEmpty)
          l10n.todayCitationExcerptCleared
        else
          '$method：${citationExcerptOf(material)}',
        if (cleared) l10n.todayCitationContentCleared,
        if (issue != null)
          l10n.todayCitationIncomplete(issue.missingFields.join(', ')),
      ].join('\n'),
      child: ActionChip(
        avatar: Icon(
          material.hasLocalArticle ? Icons.article_outlined : Icons.open_in_new,
          size: 14,
        ),
        label: Text(
          '$method·${material.sourceId}',
          style: theme.textTheme.labelSmall,
        ),
        visualDensity: VisualDensity.compact,
        onPressed: () => _openCitation(l10n, material, cleared),
      ),
    );
  }

  /// 打开一条引用：本机文章走内部跳转，外部来源走系统浏览器（架构 4.4）。
  Future<void> _openCitation(
    AppLocalizations l10n,
    NewsMaterial material,
    bool cleared,
  ) async {
    final int? articleId = material.articleId;
    if (articleId != null) {
      // 本机文章：打开阅读页。内部跳转不经过系统浏览器，因此不存在「外开一个本地 id」
      // 这种无意义动作。跳转目标页由阅读模块提供（跨 feature 依赖是既有做法，见
      // reading_page 对 feeds 的引用）。
      // 正文已被清理时**先**说明再跳：详情页会显示「没有可显示的正文」，不解释的话
      // 用户会以为是跳转坏了。
      if (cleared) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.todayCitationContentCleared)),
        );
      }
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (BuildContext context) => ArticleDetailPage(
            articleId: articleId,
            initialTitle: material.title,
          ),
        ),
      );
      return;
    }
    final Uri? uri = Uri.tryParse(material.url);
    if (uri == null || !uri.hasScheme) {
      return;
    }
    final Result<bool> opened = await ref
        .read(externalLinkOpenerProvider)
        .openExternal(material.url);
    if (!mounted) {
      return;
    }
    if (opened.isErr) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(opened.errorOrNull!.message)));
    }
  }

  /// 产出元数据（模型、核验方法、材料数、被退回的条数）。
  Widget _metadataSection(AppLocalizations l10n, NewsRunRecord record) {
    final ThemeData theme = Theme.of(context);
    final List<String> lines = <String>[
      if (record.providerAlias != null && record.modelId != null)
        l10n.todayModelLabel('${record.providerAlias}/${record.modelId}'),
      if (record.verificationMethod != null)
        l10n.todayVerificationMethod(record.verificationMethod!),
      l10n.todayMaterialCount(record.materials.length),
      if (record.items.any((NewsDraftItem i) => !i.kept))
        l10n.todayRejectedCount(
          record.items.where((NewsDraftItem i) => !i.kept).length,
        ),
    ];
    if (lines.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: FluxSpacing.xs),
      child: Text(lines.join('\n'), style: theme.textTheme.bodySmall),
    );
  }

  /// 同一天的全部版本（含初稿与核验后、时间与模型），可切换、可删除非当前版本。
  Widget _versionSection(AppLocalizations l10n, NewsTodayState state) {
    if (state.versions.length <= 1) {
      return const SizedBox.shrink();
    }
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: FluxSpacing.sm),
      child: FluxCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(l10n.todayVersionsTitle, style: theme.textTheme.labelLarge),
            const SizedBox(height: FluxSpacing.xs),
            for (final NewsRunRecord version in state.versions)
              Padding(
                padding: const EdgeInsets.only(top: FluxSpacing.xxs),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        l10n.todayVersionItemDetail(
                          version.version,
                          _versionStatusLabel(l10n, version),
                          _formatStamp(
                            version.createdAt,
                            version.snapshot.utcOffsetMinutes,
                          ),
                          version.providerAlias != null &&
                                  version.modelId != null
                              ? '${version.providerAlias}/${version.modelId}'
                              : l10n.todayVersionModelUnknown,
                        ),
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                    if (version.isCurrent)
                      Text(
                        l10n.todayVersionCurrent,
                        style: theme.textTheme.labelSmall,
                      )
                    else ...<Widget>[
                      TextButton(
                        onPressed: () => ref
                            .read(newsTodayControllerProvider.notifier)
                            .selectVersion(version.version),
                        child: Text(l10n.todayVersionUse),
                      ),
                      IconButton(
                        tooltip: l10n.todayVersionDeleteTooltip,
                        icon: const Icon(Icons.delete_outline, size: 18),
                        onPressed: () =>
                            _confirmDeleteVersion(l10n, version.version),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 版本状态标签：区分初稿/核验后，且**如实**标出失败/取消/中断的那些版本。
  String _versionStatusLabel(AppLocalizations l10n, NewsRunRecord version) {
    if (!version.status.isCompleted) {
      return switch (version.status) {
        TaskStatus.cancelled => l10n.todayStatusCancelled,
        TaskStatus.interrupted => l10n.todayStatusInterrupted,
        TaskStatus.waitingConfiguration => l10n.todayStatusWaitingConfiguration,
        TaskStatus.waitingNetwork => l10n.todayStatusWaitingNetwork,
        TaskStatus.queued || TaskStatus.running => l10n.todayStatusRunning,
        TaskStatus.succeeded || TaskStatus.partial || TaskStatus.failed =>
          l10n.todayStatusFailed(version.errorKind ?? 'failed'),
      };
    }
    return version.verificationMethod == null
        ? l10n.todayDraftLabel
        : l10n.todayVerifiedLabel;
  }

  /// 版本时间戳（按记录**当时固化的偏移**换算，只到分钟）。
  ///
  /// 用快照里冻结的 UTC 偏移而不是设备当前时区：一条在 UTC+8 生成的记录，用户飞到
  /// UTC-5 之后仍应看到「当时 21:03」，否则同一份内容在两个设备上会显示两个时间。
  /// 偏移就在快照里（无需再查时区数据库），因此这个换算没有失败路径。
  String _formatStamp(DateTime createdAtUtc, int utcOffsetMinutes) {
    final DateTime shifted = createdAtUtc.toUtc().add(
      Duration(minutes: utcOffsetMinutes),
    );
    String two(int v) => v.toString().padLeft(2, '0');
    return '${shifted.year}-${two(shifted.month)}-${two(shifted.day)} '
        '${two(shifted.hour)}:${two(shifted.minute)}';
  }

  Future<void> _confirmDeleteVersion(AppLocalizations l10n, int version) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(l10n.todayVersionDeleteConfirmTitle(version)),
        content: Text(l10n.todayVersionDeleteConfirmBody(version)),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.todayVersionDeleteCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.todayVersionDeleteConfirmOk),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    final Result<void> deleted = await ref
        .read(newsTodayControllerProvider.notifier)
        .deleteVersion(version);
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          deleted.isOk
              ? l10n.todayVersionDeleted(version)
              : l10n.todayVersionDeleteFailed(deleted.errorOrNull!.kind),
        ),
      ),
    );
  }

  /// 费用与数据发送确认（架构 4.4、SET-042/066 的界面落点）。
  Future<void> _confirmAndGenerate(
    AppLocalizations l10n,
    NewsTodayState? state,
  ) async {
    final NewsTaskSettings settings = await NewsTaskSettings.fromSettingsReader(
      ref.read(newsSettingsReaderProvider),
    );
    if (!mounted) {
      return;
    }
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(l10n.todayCostConfirmTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              l10n.todayCostConfirmBody(
                settings.maxArticles,
                settings.maxSites,
                settings.maxQueries,
              ),
            ),
            if (state?.hasSuccessVersion ?? false) ...<Widget>[
              const SizedBox(height: FluxSpacing.xs),
              Text(l10n.todayCostConfirmRegenerate),
            ],
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.todayCostConfirmCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.todayCostConfirmSend),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    final NewsRunOutcome? outcome = await ref
        .read(newsTodayControllerProvider.notifier)
        .generate();
    if (!mounted || outcome == null) {
      return;
    }
    final NewsRunRecord? record = outcome.record;
    if (outcome.ok && record != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.todayGenerateSucceeded(record.version))),
      );
    }
  }

  /// 把日期键按天数偏移（纯字符串到 DateTime 的往返，不读系统时区）。
  String _shiftDate(String? localDate, int days) {
    final DateTime? parsed = localDate == null
        ? null
        : DateTime.tryParse(localDate);
    final DateTime base = parsed ?? ref.read(aiTaskClockProvider).now().toUtc();
    final DateTime shifted = DateTime.utc(
      base.year,
      base.month,
      base.day + days,
    );
    return localDateKey(shifted);
  }
}
