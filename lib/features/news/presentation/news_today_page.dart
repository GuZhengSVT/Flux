// 今日新闻页（T038 的最小可用形态；架构 4.4「日期/历史/生成进度/来源跳转」的界面落点）。
//
// 这一页只做**如实呈现**，四个承诺与架构 4.4 一一对应：
//
//   1) **生成前弹费用与数据发送确认**。一次生成会发多次检索与模型调用；没有这个确认，
//      「点一下按钮」与「一次真实付费调用」在界面上无法区分（SET-042/066 的同一口径）。
//   2) **进度显示真实阶段**（快照 → 必访 → 检索 → 生成 → 核验 → 保存），阶段由编排层回调
//      驱动，不是界面自己演一遍动画。
//   3) **必访失败逐站可见**（SET-051）。失败的站点连同原因类别列出来，而不是笼统一句
//      「部分站点失败」。
//   4) **引用可跳转**：RSS 引用跳本机文章，外部来源用系统浏览器打开。引用缺字段时明说
//      缺什么（架构 4.4 的「引用只可使用真实获取的 sourceId，保存标题、URL、时间、最小摘录」）。
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _header(l10n, state.value),
        if (state.value?.lastError case final AppError error)
          _errorBanner(l10n, error, state.value!),
        if (state.value?.generating ?? false) _progress(l10n, state.value!),
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
            data: (NewsTodayState value) => _body(l10n, value),
          ),
        ),
      ],
    );
  }

  Widget _header(AppLocalizations l10n, NewsTodayState? state) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = Theme.of(context).colorScheme;
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
      child: Row(
        children: <Widget>[
          IconButton(
            tooltip: l10n.todayPreviousDay,
            icon: const Icon(Icons.chevron_left),
            onPressed: generating
                ? null
                : () => ref
                      .read(newsTodayControllerProvider.notifier)
                      .selectDate(_shiftDate(state?.localDate, -1)),
          ),
          Text(state?.localDate ?? '', style: theme.textTheme.titleMedium),
          IconButton(
            tooltip: l10n.todayNextDay,
            icon: const Icon(Icons.chevron_right),
            onPressed: generating
                ? null
                : () => ref
                      .read(newsTodayControllerProvider.notifier)
                      .selectDate(_shiftDate(state?.localDate, 1)),
          ),
          const SizedBox(width: FluxSpacing.sm),
          if (state != null && state.dates.isNotEmpty)
            _historyPicker(l10n, state),
          const Spacer(),
          if (generating)
            OutlinedButton(
              onPressed: () =>
                  ref.read(newsTodayControllerProvider.notifier).cancel(),
              child: Text(l10n.todayCancelGenerate),
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
    );
  }

  Widget _historyPicker(AppLocalizations l10n, NewsTodayState state) {
    final List<String> dates = <String>[
      for (final NewsRunDateRef ref in state.dates) ref.localDate,
    ];
    final List<String> unique = <String>[
      for (final String date in dates)
        if (!dates.sublist(0, dates.indexOf(date)).contains(date)) date,
    ];
    if (unique.length <= 1) {
      return const SizedBox.shrink();
    }
    return DropdownButton<String>(
      value: unique.contains(state.localDate) ? state.localDate : null,
      hint: Text(l10n.todayDateLabel),
      items: <DropdownMenuItem<String>>[
        for (final String date in unique)
          DropdownMenuItem<String>(value: date, child: Text(date)),
      ],
      onChanged: (String? value) {
        if (value == null) {
          return;
        }
        ref.read(newsTodayControllerProvider.notifier).selectDate(value);
      },
    );
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
        ],
      ),
    );
  }

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
        if (record.siteResults.isNotEmpty) _siteSection(l10n, record),
        for (final NewsDraftItem item in record.items)
          _itemCard(l10n, record, item),
        // 元数据（模型、核验方法、材料数、退回条数）**总是**显示：它是「这份总结是怎么
        // 来的」的唯一线索，只在多版本时才给会让最常见的情形（当天只生成过一次）失去它。
        _metadataSection(l10n, record),
        if (state.hasMultipleVersions) _versionSection(l10n, state),
        const SizedBox(height: FluxSpacing.sm),
        Text(
          l10n.todayJournalNotice,
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }

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
            Padding(
              padding: const EdgeInsets.only(top: FluxSpacing.xxs),
              child: Row(
                children: <Widget>[
                  Icon(
                    site.ok ? Icons.check_circle_outline : Icons.error_outline,
                    size: 16,
                    color: site.ok
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.tertiary,
                  ),
                  const SizedBox(width: FluxSpacing.xxs),
                  Expanded(
                    child: Text('${site.name} — ${_siteText(l10n, site)}'),
                  ),
                ],
              ),
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
                  _citationChip(l10n, record, sourceId),
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
    return Tooltip(
      message: <String>[
        material.title.isEmpty ? sourceId : material.title,
        if (material.url.isNotEmpty) material.url,
        '$method：${citationExcerptOf(material)}',
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
        onPressed: () => _openCitation(l10n, material),
      ),
    );
  }

  /// 打开一条引用：本机文章走内部跳转，外部来源走系统浏览器（架构 4.4）。
  Future<void> _openCitation(
    AppLocalizations l10n,
    NewsMaterial material,
  ) async {
    final int? articleId = material.articleId;
    if (articleId != null) {
      // 本机文章：打开阅读页。内部跳转不经过系统浏览器，因此不存在「外开一个本地 id」
      // 这种无意义动作。跳转目标页由阅读模块提供（跨 feature 依赖是既有做法，见
      // reading_page 对 feeds 的引用）。
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

  Widget _versionSection(AppLocalizations l10n, NewsTodayState state) {
    final ThemeData theme = Theme.of(context);
    return FluxCard(
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
                      l10n.todayVersionItem(
                        version.version,
                        version.verificationMethod == null
                            ? l10n.todayDraftLabel
                            : l10n.todayVerifiedLabel,
                      ),
                    ),
                  ),
                  if (version.isCurrent)
                    Text(
                      l10n.todayVersionCurrent,
                      style: theme.textTheme.labelSmall,
                    )
                  else
                    TextButton(
                      onPressed: () => ref
                          .read(newsTodayControllerProvider.notifier)
                          .selectVersion(version.version),
                      child: Text(l10n.todayVersionUse),
                    ),
                ],
              ),
            ),
        ],
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
