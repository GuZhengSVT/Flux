// 「我的 / 设置」页（T011）。
//
// 本页的分工写得很清楚，因为这是最容易做成「假功能」的地方：
//
//   A. 阅读与外观（真正生效）：SET-001 界面语言、SET-002 主题。
//      两项都真实读写设置存储，写入失败会显示提示（不静默）。
//   B. 尚未实现的设置项：只显示名称 + 编号 + 分类 + 计划任务，
//      以禁用态呈现，**没有任何开关**。架构第 6 节还有 68 个编号，逐个做假开关
//      会让 T051 的「设置审计」无法区分「已实现」与「看起来能用」。
//   C. 关于：版本（常量由测试对 pubspec 钉住）、MIT、仓库与 Issue 地址
//      （2026-09-21 经 GitHub 公开接口核实；地址为空时显示「未配置」）。
//
// 语言与主题的「即时生效」由 app 层监听设置状态完成：本页只写存储，不自己
// 重建 MaterialApp，避免出现两处状态源。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flux/core/app_metadata.dart';
import 'package:flux/core/core.dart';
import 'package:flux/core/design/design_tokens.dart';
import 'package:flux/features/ai/presentation/ai_services_page.dart';
import 'package:flux/features/ai/presentation/ai_task_list_page.dart';
import 'package:flux/features/ai/presentation/search_services_page.dart';
import 'package:flux/features/feeds/presentation/subscription_manager_page.dart';
import 'package:flux/features/statistics/presentation/reading_stats_page.dart';
import 'package:flux/l10n/l10n.dart';

import '../application/settings_controller.dart';

/// 设置页。
class SettingsPage extends ConsumerWidget {
  /// 构建设置页。
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<SettingsState> state = ref.watch(
      settingsControllerProvider,
    );

    return state.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      // 读取失败不是空白页：用注册表默认值渲染，并在顶部说明当前是默认值。
      error: (Object error, StackTrace stackTrace) => _SettingsBody(
        state: SettingsState.initial().copyWith(loadErrorCode: 'read'),
        title: l10n.settingsTitle,
      ),
      data: (SettingsState value) =>
          _SettingsBody(state: value, title: l10n.settingsTitle),
    );
  }
}

/// 设置页正文。
class _SettingsBody extends ConsumerWidget {
  const _SettingsBody({required this.state, required this.title});

  final SettingsState state;
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: FluxSpacing.md),
      children: <Widget>[
        _PageTitle(title: title),
        if (state.loadErrorCode != null)
          _InlineNotice(
            icon: Icons.error_outline,
            text: l10n.settingsWriteFailed,
          ),
        if (state.lastWriteFailed)
          _InlineNotice(
            icon: Icons.error_outline,
            text: l10n.settingsWriteFailed,
          ),
        _SectionHeader(title: l10n.settingsSectionShell),
        _ChoiceRow(
          title: l10n.settingsLanguageLabel,
          idLabel: l10n.settingsLanguageId,
          hint: l10n.settingsLanguageHint,
          value: state.language,
          options: <String, String>{
            AppLanguageSetting.system: l10n.settingsOptionFollowSystem,
            AppLanguageSetting.chinese: l10n.settingsOptionChinese,
            AppLanguageSetting.english: l10n.settingsOptionEnglish,
          },
          onChanged: (String value) =>
              ref.read(settingsControllerProvider.notifier).setLanguage(value),
        ),
        _ChoiceRow(
          title: l10n.settingsThemeLabel,
          idLabel: l10n.settingsThemeId,
          hint: l10n.settingsThemeHint,
          value: state.theme,
          options: <String, String>{
            'system': l10n.settingsOptionFollowSystem,
            'light': l10n.settingsOptionLight,
            'dark': l10n.settingsOptionDark,
          },
          onChanged: (String value) =>
              ref.read(settingsControllerProvider.notifier).setTheme(value),
        ),
        _SectionHeader(title: l10n.subscriptionManagerTitle),
        // T025：AI 服务（提供商/模型/能力/凭据）。SET-030–033 在本页真实生效，
        // 因此它从「即将推出」占位里移除，改成这个入口——留一个禁用的占位项而功能
        // 其实可用，会让 T051 的设置审计无法区分「已实现」与「看起来能用」。
        _NavigationRow(
          title: l10n.settingsAiEntryTitle,
          subtitle: l10n.settingsAiEntrySubtitle,
          icon: Icons.smart_toy_outlined,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (BuildContext context) => const AiServicesPage(),
            ),
          ),
        ),
        // T030：AI 任务记录（含中断恢复）。与上面那条分开的理由是它们管的事不同：
        // 上面管**配置**（哪些模型可用），这条管**历史**（跑过什么、有没有中断）。
        // 中断只有在用户能看到并能手动重新开始时才有意义，因此这条入口是 T030 验收
        // 「进程重启显示 interrupted」的界面落点。
        _NavigationRow(
          title: l10n.settingsAiTasksEntryTitle,
          subtitle: l10n.settingsAiTasksEntrySubtitle,
          icon: Icons.history,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (BuildContext context) => const AiTaskListPage(),
            ),
          ),
        ),
        // T031：搜索服务（Tavily / Brave / 自建 SearXNG）。与上面两条分开的理由：
        // 它们管 AI 提供商与任务历史，这条管**出网检索**——是另一类数据去向
        // （查询词会发给搜索服务），因此入口、凭据与告知提示都独立。
        _NavigationRow(
          title: l10n.settingsSearchEntryTitle,
          subtitle: l10n.settingsSearchEntrySubtitle,
          icon: Icons.travel_explore_outlined,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (BuildContext context) => const SearchServicesPage(),
            ),
          ),
        ),
        _NavigationRow(
          title: l10n.subscriptionManagerTitle,
          subtitle: l10n.subscriptionManagerNotice,
          icon: Icons.rss_feed,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (BuildContext context) =>
                  const SubscriptionManagerPage(),
            ),
          ),
        ),
        // T023：阅读统计。SET-015 已在统计页内真正生效（开关 + 空闲暂停），
        // 因此它从「即将推出」占位列表里移除，改成这个入口——留一个禁用的占位项
        // 而功能其实可用，会让 T051 的设置审计无法区分「已实现」与「看起来能用」。
        _NavigationRow(
          title: l10n.settingsStatsEntryTitle,
          subtitle: l10n.settingsStatsEntrySubtitle,
          icon: Icons.insights_outlined,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (BuildContext context) => const ReadingStatsPage(),
            ),
          ),
        ),
        _SectionHeader(title: l10n.settingsSectionAppearancePlanned),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            FluxSpacing.md,
            FluxSpacing.xs,
            FluxSpacing.md,
            FluxSpacing.sm,
          ),
          child: Text(
            l10n.settingsPlannedNotice,
            style: theme.textTheme.bodySmall,
          ),
        ),
        for (final _PlannedSetting planned in _plannedSettings)
          _PlannedSettingRow(item: planned, badge: l10n.settingsPlannedBadge),
        _SectionHeader(title: l10n.settingsSectionAbout),
        _AboutBlock(l10n: l10n),
      ],
    );
  }
}

/// 页面标题。
class _PageTitle extends StatelessWidget {
  const _PageTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      FluxSpacing.md,
      0,
      FluxSpacing.md,
      FluxSpacing.xs,
    ),
    child: Text(title, style: Theme.of(context).textTheme.headlineMedium),
  );
}

/// 分段标题。
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        FluxSpacing.md,
        FluxSpacing.md,
        FluxSpacing.md,
        FluxSpacing.xs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: Theme.of(context).textTheme.titleSmall
                ?.copyWith(color: colors.onSurface),
          ),
          const SizedBox(height: FluxSpacing.xxs),
          Divider(color: colors.outline),
        ],
      ),
    );
  }
}

/// 行内提示（加载失败 / 写入失败）。
class _InlineNotice extends StatelessWidget {
  const _InlineNotice({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: FluxSpacing.md,
        vertical: FluxSpacing.xs,
      ),
      child: Container(
        padding: const EdgeInsets.all(FluxSpacing.sm),
        decoration: BoxDecoration(
          color: colors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(FluxRadius.card),
          border: Border.all(color: colors.error),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(icon, size: 18, color: colors.error),
            const SizedBox(width: FluxSpacing.xs),
            Expanded(
              child: Text(
                text,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: colors.onSurface),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 真正的可交互设置行：标题 + SET 编号 + 说明 + 单选组。
class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({
    required this.title,
    required this.idLabel,
    required this.hint,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String title;
  final String idLabel;
  final String hint;
  final String value;
  final Map<String, String> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: FluxSpacing.md,
        vertical: FluxSpacing.xs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
              Text(
                idLabel,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: FluxSpacing.xxs),
          Text(hint, style: theme.textTheme.bodySmall),
          const SizedBox(height: FluxSpacing.sm),
          // 用 SegmentedButton 而不是 Switch：这是三选一策略，不是开关；
          // 开关形态会暗示存在「开/关」两个状态，与实际语义不符。
          Align(
            alignment: Alignment.centerLeft,
            child: SegmentedButton<String>(
              segments: <ButtonSegment<String>>[
                for (final MapEntry<String, String> entry in options.entries)
                  ButtonSegment<String>(
                    value: entry.key,
                    label: Text(entry.value),
                  ),
              ],
              selected: <String>{value},
              showSelectedIcon: false,
              onSelectionChanged: (Set<String> selection) =>
                  onChanged(selection.first),
            ),
          ),
        ],
      ),
    );
  }
}

/// 一个尚未实现的设置项（只有名称、编号、分类、计划任务）。
final class _PlannedSetting {
  const _PlannedSetting({
    required this.id,
    required this.titleBuilder,
    required this.classification,
    required this.tasks,
  });

  final SettingId id;
  final String Function(AppLocalizations l10n) titleBuilder;
  final SettingClassification classification;
  final String tasks;
}

/// T011 期间展示为「即将推出」的阅读与外观项（SET-003–016，排除已生效的 001/002）。
///
/// 这里逐项列出而不是遍历注册表：注册表包含全部 70 个编号（含 AI、同步、备份），
/// 把它们全列在「我的」页会让本页看起来像功能总览；更重要的是，哪些项属于
/// 「阅读与外观」是产品分组决策，不该由代码从分类字段推断。
final List<_PlannedSetting> _plannedSettings = <_PlannedSetting>[
  _PlannedSetting(
    id: SettingId.set003,
    titleBuilder: (AppLocalizations l10n) => l10n.settingsItemSet003,
    classification: SettingClassification.device,
    tasks: 'T012/T051',
  ),
  _PlannedSetting(
    id: SettingId.set004,
    titleBuilder: (AppLocalizations l10n) => l10n.settingsItemSet004,
    classification: SettingClassification.device,
    tasks: 'T012/T051',
  ),
  _PlannedSetting(
    id: SettingId.set005,
    titleBuilder: (AppLocalizations l10n) => l10n.settingsItemSet005,
    classification: SettingClassification.device,
    tasks: 'T012/T051',
  ),
  _PlannedSetting(
    id: SettingId.set006,
    titleBuilder: (AppLocalizations l10n) => l10n.settingsItemSet006,
    classification: SettingClassification.device,
    tasks: 'T012/T051',
  ),
  _PlannedSetting(
    id: SettingId.set007,
    titleBuilder: (AppLocalizations l10n) => l10n.settingsItemSet007,
    classification: SettingClassification.device,
    tasks: 'T019/T051',
  ),
  _PlannedSetting(
    id: SettingId.set008,
    titleBuilder: (AppLocalizations l10n) => l10n.settingsItemSet008,
    classification: SettingClassification.device,
    tasks: 'T019/T051',
  ),
  _PlannedSetting(
    id: SettingId.set009,
    titleBuilder: (AppLocalizations l10n) => l10n.settingsItemSet009,
    classification: SettingClassification.device,
    tasks: 'T019/T051',
  ),
  _PlannedSetting(
    id: SettingId.set010,
    titleBuilder: (AppLocalizations l10n) => l10n.settingsItemSet010,
    classification: SettingClassification.common,
    tasks: 'T017',
  ),
  _PlannedSetting(
    id: SettingId.set011,
    titleBuilder: (AppLocalizations l10n) => l10n.settingsItemSet011,
    classification: SettingClassification.common,
    tasks: 'T035',
  ),
  _PlannedSetting(
    id: SettingId.set012,
    titleBuilder: (AppLocalizations l10n) => l10n.settingsItemSet012,
    classification: SettingClassification.device,
    tasks: 'T021',
  ),
  _PlannedSetting(
    id: SettingId.set013,
    titleBuilder: (AppLocalizations l10n) => l10n.settingsItemSet013,
    classification: SettingClassification.device,
    tasks: 'T016/T021',
  ),
  _PlannedSetting(
    id: SettingId.set014,
    titleBuilder: (AppLocalizations l10n) => l10n.settingsItemSet014,
    classification: SettingClassification.device,
    tasks: 'T012/T051',
  ),
  _PlannedSetting(
    id: SettingId.set016,
    titleBuilder: (AppLocalizations l10n) => l10n.settingsItemSet016,
    classification: SettingClassification.device,
    tasks: 'T019/T058',
  ),
];

/// 尚未实现的设置项：禁用态展示，没有可操作控件。
class _PlannedSettingRow extends StatelessWidget {
  const _PlannedSettingRow({required this.item, required this.badge});

  final _PlannedSetting item;
  final String badge;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = Theme.of(context).colorScheme;
    final String classification = switch (item.classification) {
      SettingClassification.common => l10n.settingsClassificationCommon,
      SettingClassification.device => l10n.settingsClassificationDevice,
      SettingClassification.secret => l10n.settingsClassificationSecret,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: FluxSpacing.md,
        vertical: FluxSpacing.xxs,
      ),
      child: Semantics(
        // 明确告诉读屏：这一项当前不可操作，避免用户反复尝试点击。
        enabled: false,
        child: Container(
          padding: const EdgeInsets.all(FluxSpacing.sm),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(FluxRadius.card),
            border: Border.all(color: colors.outline),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      item.titleBuilder(l10n),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: FluxSpacing.xxs),
                    Text(
                      '${item.id.code} · $classification · '
                      '${l10n.settingsItemPlannedTask(item.tasks)}',
                      style: theme.textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: FluxSpacing.xs),
              Text(
                badge,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colors.tertiary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 关于区。
class _AboutBlock extends StatelessWidget {
  const _AboutBlock({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: FluxSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _AboutRow(
            label: l10n.aboutVersionLabel,
            value: l10n.aboutVersionValue(fluxAppVersion),
            note: '$fluxVersionSource；检查更新由 T053/T083 交付',
          ),
          _AboutRow(
            label: l10n.aboutLicenseLabel,
            value: fluxLicenseName,
            note: l10n.aboutLicenseNote,
          ),
          _AboutRow(
            label: l10n.aboutRepositoryLabel,
            value: _orNotConfigured(fluxRepositoryUrl, l10n),
          ),
          _AboutRow(
            label: l10n.aboutIssueLabel,
            value: _orNotConfigured(fluxIssueUrl, l10n),
          ),
          _AboutRow(label: l10n.aboutDeveloperLabel, value: fluxDeveloperName),
          const SizedBox(height: FluxSpacing.xs),
          Text(
            '${l10n.aboutReadOnlyNote} ${l10n.aboutUnverifiedNote}'
            ' 核实日期：$fluxMetadataVerifiedOn',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: FluxSpacing.lg),
        ],
      ),
    );
  }

  /// 空地址显示「未配置」，绝不拼一个看起来合理的地址（SET-084）。
  static String _orNotConfigured(String url, AppLocalizations l10n) =>
      url.isEmpty ? l10n.aboutNotConfigured : url;
}

/// 关于区的一行。
class _AboutRow extends StatelessWidget {
  const _AboutRow({required this.label, required this.value, this.note});

  final String label;
  final String value;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: FluxSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label, style: theme.textTheme.bodySmall),
          const SizedBox(height: FluxSpacing.xxs),
          SelectableText(value, style: theme.textTheme.bodyMedium),
          if (note != null) ...<Widget>[
            const SizedBox(height: FluxSpacing.xxs),
            Text(note!, style: theme.textTheme.labelSmall),
          ],
        ],
      ),
    );
  }
}

/// 一个可导航的设置入口行（T014：订阅管理）。
///
/// 与 _ChoiceRow 分开：那是「就地改值」的控件，这是「进入另一个页面」。两者混用
/// 会让用户无法判断点下去会发生什么。
class _NavigationRow extends StatelessWidget {
  const _NavigationRow({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: FluxSpacing.md,
        vertical: FluxSpacing.xxs,
      ),
      child: Material(
        color: colors.surface,
        borderRadius: BorderRadius.circular(FluxRadius.card),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(FluxRadius.card),
          child: Container(
            padding: const EdgeInsets.all(FluxSpacing.sm),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(FluxRadius.card),
              border: Border.all(color: colors.outline),
            ),
            child: Row(
              children: <Widget>[
                Icon(icon, size: 20, color: colors.primary),
                const SizedBox(width: FluxSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(title, style: theme.textTheme.bodyMedium),
                      const SizedBox(height: FluxSpacing.xxs),
                      Text(subtitle, style: theme.textTheme.labelSmall),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: colors.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
