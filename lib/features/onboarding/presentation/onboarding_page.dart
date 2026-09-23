// 首次引导向导（T011，架构第 3 节「首次启动」）。
//
// 三步与架构第 3 节逐条对应：
//   1) 欢迎 / 语言与主题 / 离线使用说明；
//   2) 添加订阅（占位，注明 T013–T016）——**不创建任何订阅**；
//   3) 可选 AI 与搜索设置（占位，注明 T025/T031），并明确「未配置 AI 可跳过」。
//
// 为什么第 2、3 步不提供「示例数据」或「稍后配置」的假完成态：
//   架构第 8 节与手册都要求不以 mock 代替正式功能。一个能点但什么都不做的
//   「添加订阅」按钮会让用户以为订阅已生效，也会掩盖 T013–T016 尚未开始这一事实。
//   因此这两步只给出**可跳过的说明**，唯一的真实动作是跳过/下一步/开始使用。
//
// 完成标记写入本机状态（device.onboardingCompleted），见 lib/app/app_bootstrap.dart。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flux/core/design/design_tokens.dart';
import 'package:flux/l10n/l10n.dart';

import '../../settings/application/settings_controller.dart';
import '../application/onboarding_state.dart';

/// 首次引导向导。
class OnboardingPage extends ConsumerStatefulWidget {
  /// 构造向导。
  const OnboardingPage({super.key});

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  /// 三步总数。
  static const int totalSteps = 3;

  /// 当前步骤（0 起）。
  int _step = 0;

  /// 完成标记是否正在写入（避免重复点击造成多次写入）。
  bool _finishing = false;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          // 向导面板最大宽度对齐正文最大宽（720），窄窗下自适应。
          constraints: const BoxConstraints(
            maxWidth: FluxBreakpoints.maxBodyWidth,
          ),
          child: Padding(
            padding: const EdgeInsets.all(FluxSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  l10n.onboardingStepIndicator(_step + 1, totalSteps),
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                const SizedBox(height: FluxSpacing.xs),
                Expanded(child: SingleChildScrollView(child: _stepBody(l10n))),
                const SizedBox(height: FluxSpacing.md),
                _wizardActions(l10n),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 当前步骤的内容。
  Widget _stepBody(AppLocalizations l10n) {
    return switch (_step) {
      0 => _StepBlock(
        icon: Icons.waving_hand_outlined,
        title: l10n.onboardingWelcomeTitle,
        paragraphs: <String>[
          l10n.onboardingWelcomeBody,
          l10n.onboardingOfflineNote,
          l10n.onboardingAppearanceNote,
        ],
        footer: const _AppearanceQuickSetup(),
      ),
      1 => _StepBlock(
        icon: Icons.rss_feed_outlined,
        title: l10n.onboardingFeedsTitle,
        paragraphs: <String>[
          l10n.onboardingFeedsBody,
          l10n.onboardingFeedsSkipNote,
        ],
      ),
      _ => _StepBlock(
        icon: Icons.hub_outlined,
        title: l10n.onboardingAiTitle,
        paragraphs: <String>[l10n.onboardingAiBody, l10n.onboardingAiSkipNote],
      ),
    };
  }

  /// 底部动作区。
  Widget _wizardActions(AppLocalizations l10n) {
    final bool isLast = _step == totalSteps - 1;
    return Row(
      children: <Widget>[
        // 跳过始终可用：架构第 3 节把第 3 步定义为「可选」，
        // 且第 1 步已给出离线说明，没有必须留在向导里的理由。
        TextButton(
          onPressed: _finishing ? null : _finish,
          child: Text(l10n.onboardingSkip),
        ),
        const Spacer(),
        if (_step > 0) ...<Widget>[
          OutlinedButton(
            onPressed: _finishing
                ? null
                : () => setState(() => _step = _step - 1),
            child: Text(l10n.onboardingBack),
          ),
          const SizedBox(width: FluxSpacing.xs),
        ],
        FilledButton(
          onPressed: _finishing
              ? null
              : (isLast ? _finish : () => setState(() => _step = _step + 1)),
          child: Text(isLast ? l10n.onboardingStart : l10n.onboardingNext),
        ),
      ],
    );
  }

  /// 结束向导：写完成标记，由上层切换到主页。
  Future<void> _finish() async {
    setState(() => _finishing = true);
    await ref.read(onboardingStoreProvider).markCompleted();
    ref.invalidate(onboardingCompletedProvider);
    if (mounted) {
      setState(() => _finishing = false);
    }
  }
}

/// 第 1 步里的外观快速设置（真正生效，复用同一份设置存储）。
///
/// 放在向导中是因为架构第 3 节把「语言/主题」明确列为首次启动的第一项内容；
/// 它只写同一个设置控制器，因此与设置页不会产生两个状态源。
class _AppearanceQuickSetup extends ConsumerWidget {
  /// 构造快速设置。
  const _AppearanceQuickSetup();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<SettingsState> state = ref.watch(
      settingsControllerProvider,
    );
    final SettingsState? current = state.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SizedBox(height: FluxSpacing.sm),
        Text(
          l10n.settingsLanguageLabel,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: FluxSpacing.xxs),
        SegmentedButton<String>(
          segments: <ButtonSegment<String>>[
            ButtonSegment<String>(
              value: AppLanguageSetting.system,
              label: Text(l10n.settingsOptionFollowSystem),
            ),
            ButtonSegment<String>(
              value: AppLanguageSetting.chinese,
              label: Text(l10n.settingsOptionChinese),
            ),
            ButtonSegment<String>(
              value: AppLanguageSetting.english,
              label: Text(l10n.settingsOptionEnglish),
            ),
          ],
          selected: <String>{current?.language ?? AppLanguageSetting.system},
          showSelectedIcon: false,
          onSelectionChanged: (Set<String> selection) => ref
              .read(settingsControllerProvider.notifier)
              .setLanguage(selection.first),
        ),
        const SizedBox(height: FluxSpacing.sm),
        Text(
          l10n.settingsThemeLabel,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: FluxSpacing.xxs),
        SegmentedButton<String>(
          segments: <ButtonSegment<String>>[
            ButtonSegment<String>(
              value: 'system',
              label: Text(l10n.settingsOptionFollowSystem),
            ),
            ButtonSegment<String>(
              value: 'light',
              label: Text(l10n.settingsOptionLight),
            ),
            ButtonSegment<String>(
              value: 'dark',
              label: Text(l10n.settingsOptionDark),
            ),
          ],
          selected: <String>{current?.theme ?? 'system'},
          showSelectedIcon: false,
          onSelectionChanged: (Set<String> selection) => ref
              .read(settingsControllerProvider.notifier)
              .setTheme(selection.first),
        ),
      ],
    );
  }
}

/// 一步的内容块：图标 + 标题 + 段落 + 可选底部扩展。
class _StepBlock extends StatelessWidget {
  const _StepBlock({
    required this.icon,
    required this.title,
    required this.paragraphs,
    this.footer,
  });

  final IconData icon;
  final String title;
  final List<String> paragraphs;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(icon, size: 28),
        const SizedBox(height: FluxSpacing.sm),
        Text(title, style: theme.textTheme.headlineMedium),
        const SizedBox(height: FluxSpacing.md),
        for (final String paragraph in paragraphs) ...<Widget>[
          Text(paragraph, style: theme.textTheme.bodyLarge),
          // 段间距 0.8em（架构第 7 节）。常量表达式，可以 const。
          const SizedBox(height: FluxTypography.paragraphSpacing),
        ],
        ?footer,
      ],
    );
  }
}
