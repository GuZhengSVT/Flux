// 分段全文翻译的结果面板与状态（T035）。
//
// 三条界面诚实性要求：
//   * **进度是段级的**（已完成 x/y），用户能看到还剩多少、钱花在哪；
//   * **取消与部分成功都要能继续**：失败段给「重试失败段」，不要求重跑全部；
//   * **保存失败不谎报成功**：落库失败时明确说本次没能保存。
//
// 面板**不持有**译文记录本身：渲染正文用的是详情页持有的 ArticleTranslation（回填由核心的
// applyTranslation 完成），面板只表达「进行到哪、能不能重试、现在显示的是哪一份」。
library;

import 'package:flutter/material.dart';

import 'package:flux/core/core.dart';
import 'package:flux/core/design/design_tokens.dart';
import 'package:flux/features/ai/domain/ai_message.dart';
import 'package:flux/l10n/l10n.dart';
import 'package:flux/ui/ui.dart';

/// 翻译面板的状态。
sealed class TranslationPanelState {
  /// 构造状态。
  const TranslationPanelState();
}

/// 正在翻译（携带取消信号与已完成段数）。
final class TranslationRunning extends TranslationPanelState {
  /// 构造状态。
  const TranslationRunning({
    required this.cancellation,
    required this.translated,
    required this.failed,
    required this.total,
  });

  /// 取消信号。
  final AiCancellation cancellation;

  /// 已完成段数。
  final int translated;

  /// 失败段数。
  final int failed;

  /// 段落总数（尚未开始时为 0，此时不显示分母）。
  final int total;
}

/// 翻译结束（含部分成功与取消两种收尾）。
final class TranslationFinished extends TranslationPanelState {
  /// 构造状态。
  const TranslationFinished({
    required this.translated,
    required this.failed,
    required this.total,
    this.cancelled = false,
    this.saveFailed = false,
  });

  /// 已完成段数。
  final int translated;

  /// 失败段数（可单独重试）。
  final int failed;

  /// 段落总数。
  final int total;

  /// 是否被用户取消。
  final bool cancelled;

  /// 译文是否**没有**落库成功。
  final bool saveFailed;
}

/// 翻译失败（任务级；单段失败在译文结构里）。
final class TranslationFailed extends TranslationPanelState {
  /// 构造状态。
  const TranslationFailed({required this.error});

  /// 失败原因。
  final AppError error;
}

/// 跳过（仅摘要 / 没有正文 / 没有可翻译块 / 目标语言无效）。
final class TranslationSkipped extends TranslationPanelState {
  /// 构造状态。
  const TranslationSkipped({required this.reason});

  /// 跳过原因（见 TranslationSkipReason）。
  final String reason;
}

/// 翻译面板。
class ArticleTranslationPanelView extends StatelessWidget {
  /// 构造面板。
  const ArticleTranslationPanelView({
    super.key,
    required this.state,
    required this.onCancel,
    required this.onRetryFailed,
    required this.onToggle,
    required this.showingTranslation,
    required this.targetLanguageLabel,
    required this.generatedAtLabel,
    this.modelLabel,
    this.stale = false,
    this.truncated = false,
    this.hasTranslation = false,
    this.onClose,
  });

  /// 面板状态。
  final TranslationPanelState state;

  /// 取消进行中的翻译。
  final VoidCallback onCancel;

  /// 只重试失败段。
  final VoidCallback onRetryFailed;

  /// 切换原文/译文。
  final VoidCallback onToggle;

  /// 当前是否显示译文。
  final bool showingTranslation;

  /// 目标语言显示名（SET-011）。
  final String targetLanguageLabel;

  /// 译文的生成时间显示文本（无译文时为空串）。
  final String generatedAtLabel;

  /// 译文来源模型标识（可空）。
  final String? modelLabel;

  /// 译文是否对应上一版正文。
  final bool stale;

  /// 是否有段落被截断。
  final bool truncated;

  /// 是否存在可显示的译文（决定是否显示切换按钮）。
  final bool hasTranslation;

  /// 关闭面板（不改原文，也不删译文）。
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final bool running = state is TranslationRunning;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(
        FluxSpacing.md,
        FluxSpacing.sm,
        FluxSpacing.md,
        0,
      ),
      padding: const EdgeInsets.all(FluxSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(FluxRadius.card),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                l10n.readingTranslateTitle,
                style: theme.textTheme.titleSmall,
              ),
              const Spacer(),
              if (running)
                TextButton(
                  onPressed: onCancel,
                  child: Text(l10n.readingTranslateCancelAction),
                ),
              if (onClose case final VoidCallback close)
                IconButton(
                  tooltip: l10n.visionAnalysisClose,
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: close,
                ),
            ],
          ),
          Text(
            l10n.readingTranslateLanguage(targetLanguageLabel),
            style: theme.textTheme.labelSmall,
          ),
          const SizedBox(height: FluxSpacing.xs),
          _body(l10n, theme),
        ],
      ),
    );
  }

  Widget _body(AppLocalizations l10n, ThemeData theme) => switch (state) {
    TranslationRunning(:final int translated, :final int total) => Row(
      children: <Widget>[
        const FluxLoadingIndicator(size: 16),
        const SizedBox(width: FluxSpacing.sm),
        Expanded(child: Text(l10n.readingTranslateRunning(translated, total))),
      ],
    ),
    TranslationFinished(
      :final int translated,
      :final int failed,
      :final int total,
      :final bool cancelled,
      :final bool saveFailed,
    ) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            cancelled
                ? l10n.readingTranslateCancelled
                : (failed > 0
                      ? l10n.readingTranslatePartial(translated, total, failed)
                      : l10n.readingTranslateDone(translated, total)),
            style: theme.textTheme.bodyMedium,
          ),
          if (saveFailed)
            Padding(
              padding: const EdgeInsets.only(top: FluxSpacing.xxs),
              child: Text(
                l10n.readingTranslateFailed('storage'),
                style: theme.textTheme.labelSmall,
              ),
            ),
          if (hasTranslation) ...<Widget>[
            const SizedBox(height: FluxSpacing.xs),
            OutlinedButton.icon(
              onPressed: onToggle,
              icon: const Icon(Icons.compare_arrows, size: 18),
              label: Text(
                showingTranslation
                    ? l10n.readingTranslateShowOriginal
                    : l10n.readingTranslateShowTranslation,
              ),
            ),
          ],
          if (failed > 0) ...<Widget>[
            const SizedBox(height: FluxSpacing.xs),
            FilledButton.tonalIcon(
              onPressed: onRetryFailed,
              icon: const Icon(Icons.refresh, size: 18),
              label: Text(l10n.readingTranslateRetryFailed(failed)),
            ),
            Padding(
              padding: const EdgeInsets.only(top: FluxSpacing.xxs),
              child: Text(
                l10n.readingTranslateRetryHint,
                style: theme.textTheme.labelSmall,
              ),
            ),
          ],
          if (hasTranslation)
            Padding(
              padding: const EdgeInsets.only(top: FluxSpacing.xxs),
              child: Text(
                l10n.readingTranslateSourceKept,
                style: theme.textTheme.labelSmall,
              ),
            ),
          if (truncated)
            Padding(
              padding: const EdgeInsets.only(top: FluxSpacing.xxs),
              child: Text(
                l10n.readingTranslateTruncatedNotice,
                style: theme.textTheme.labelSmall,
              ),
            ),
          if (stale)
            Padding(
              padding: const EdgeInsets.only(top: FluxSpacing.xxs),
              child: Text(
                l10n.readingTranslateStale,
                style: theme.textTheme.labelSmall,
              ),
            ),
          if (modelLabel case final String label)
            Padding(
              padding: const EdgeInsets.only(top: FluxSpacing.xxs),
              child: SelectableText(
                l10n.readingTranslateSavedLabel(label, generatedAtLabel),
                style: theme.textTheme.labelSmall,
              ),
            ),
        ],
      ),
    TranslationFailed(:final AppError error) => Text(
      l10n.readingTranslateFailed(error.kind),
      style: theme.textTheme.bodyMedium?.copyWith(
        color: theme.colorScheme.error,
      ),
    ),
    TranslationSkipped(:final String reason) => Text(switch (reason) {
      TranslationSkipReason.summaryOnly => l10n.readingTranslateSummaryOnly,
      TranslationSkipReason.noModel => l10n.readingTranslateNoModelBody,
      TranslationSkipReason.noTranslatableText => l10n.readingTranslateNoText,
      _ => l10n.readingTranslateNoBody,
    }, style: theme.textTheme.bodyMedium),
  };
}
