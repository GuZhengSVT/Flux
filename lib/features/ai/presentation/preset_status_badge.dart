// 预设验证状态徽章（T028）。
//
// 这一小段界面存在的理由只有一个：让「这家服务商现在到底验证到哪一步」在用户
// 选中预设的**当场**可见（而不是等用户点一次会产生费用的测试才发现）。
//
// 三档颜色按语义分工，而不是随手取色：
//   - 实测 → 主色/强调色（accent 映射到 colorScheme.primary）；
//   - fixture 通过 → 次要文字色（中性，表示「有证据但没真跑」）；
//   - 待验证 → 警告色（tertiary，与 SET 的 warning 同槽位）——它是唯一需要用户
//     采取动作（先自测）的一档，因此值得占用一个显眼的颜色。
//
// 只读 ColorScheme：features 层不得 import lib/app（架构 2.2 的依赖方向守卫会拦），
// 而 token 已经在 ColorScheme 上有对应槽位（见 flux_theme.dart 的映射）。
library;

import 'package:flutter/material.dart';

import 'package:flux/core/design/design_tokens.dart';
import 'package:flux/l10n/l10n.dart';

import '../domain/provider_preset.dart';

/// 预设状态徽章。
class PresetStatusBadge extends StatelessWidget {
  /// 构造徽章。
  const PresetStatusBadge({super.key, required this.status});

  /// 状态。
  final PresetVerificationStatus status;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ColorScheme colors = Theme.of(context).colorScheme;
    final (String label, String hint, Color color) = switch (status) {
      PresetVerificationStatus.liveVerified => (
        l10n.aiPresetStatusLive,
        l10n.aiPresetStatusLiveHint,
        colors.primary,
      ),
      PresetVerificationStatus.fixtureVerified => (
        l10n.aiPresetStatusFixture,
        l10n.aiPresetStatusFixtureHint,
        colors.onSurfaceVariant,
      ),
      PresetVerificationStatus.unverified => (
        l10n.aiPresetStatusUnverified,
        l10n.aiPresetStatusUnverifiedHint,
        colors.tertiary,
      ),
    };
    return Tooltip(
      message: hint,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: FluxSpacing.xs,
          vertical: 2,
        ),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(FluxRadius.button),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
        ),
      ),
    );
  }
}
