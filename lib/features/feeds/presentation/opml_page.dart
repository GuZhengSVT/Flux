// OPML 导入/导出页（T015）。
//
// 页面按流程阶段渲染同一张页面，而不是弹多个对话框：导入预览是一张需要用户逐条
// 核对的清单（可能几十条），塞进 AlertDialog 会让滚动与对比都很难受。
//
// 页面只做三件事：把控制器状态画出来、把动作转发给控制器、把失败如实显示。所有
// 判断（哪些是重复、哪些无效、重试范围）都在用例层，页面不重复实现。
//
// 秘密提示（SET-027）：导出完成后若确实剥离过秘密参数，页面**必须**说出来，并说
// 明这些订阅需要在目标设备补填凭据。否则用户会以为导出＝完整迁移。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flux/core/core.dart';
import 'package:flux/core/design/design_tokens.dart';
import 'package:flux/l10n/l10n.dart';
import 'package:flux/ui/ui.dart';

import '../application/file_access.dart';
import '../application/feed_ports.dart';
import '../application/opml_import_export.dart';
import 'opml_controller.dart';

/// OPML 导入/导出页。
class OpmlPage extends ConsumerWidget {
  /// 构造页面。
  const OpmlPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final OpmlImportState state = ref.watch(opmlImportControllerProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.opmlPageTitle)),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: FluxSpacing.sm),
        children: <Widget>[
          const _PageNotice(),
          _ImportSection(state: state),
          if (state.preview case final OpmlPreview preview)
            _PreviewSection(preview: preview, state: state),
          if (state.result case final OpmlImportResult result)
            _ResultSection(result: result),
          if (state.error case final AppError error)
            _ErrorSection(error: error),
          const _ExportSection(),
        ],
      ),
    );
  }
}

/// 错误区。
class _ErrorSection extends StatelessWidget {
  const _ErrorSection({required this.error});

  final AppError error;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      FluxSpacing.md,
      0,
      FluxSpacing.md,
      FluxSpacing.sm,
    ),
    child: StatusBanner(
      severity: StatusBannerSeverity.error,
      // 只显示类型化错误的**消息**，不显示底层异常：消息已由 AppError 脱敏。
      message: AppLocalizations.of(context).opmlImportError(error.message),
    ),
  );
}

/// 导出区。
class _ExportSection extends ConsumerStatefulWidget {
  const _ExportSection();

  @override
  ConsumerState<_ExportSection> createState() => _ExportSectionState();
}

class _ExportSectionState extends ConsumerState<_ExportSection> {
  bool _busy = false;
  String? _message;
  int _strippedCount = 0;
  List<String> _strippedNames = const <String>[];

  Future<void> _export() async {
    setState(() {
      _busy = true;
      _message = null;
      _strippedCount = 0;
      _strippedNames = const <String>[];
    });

    final ExportOpmlUseCase useCase = ExportOpmlUseCase(
      catalog: ref.read<FeedCatalogStore>(feedCatalogProvider),
    );
    final Result<OpmlExportResult> exported = await useCase.export();
    if (!mounted) {
      return;
    }
    if (exported.isErr) {
      setState(() {
        _busy = false;
        _message = AppLocalizations.of(context)
            .opmlExportError(exported.errorOrNull!.message);
      });
      return;
    }

    final OpmlExportResult result = exported.unwrap();
    final Result<String?> saved = await ref
        .read<FileAccessPort>(fileAccessProvider)
        .saveOpml('flux-subscriptions.opml', result.document);
    if (!mounted) {
      return;
    }
    final AppLocalizations l10n = AppLocalizations.of(context);
    if (saved.isErr) {
      setState(() {
        _busy = false;
        _message = l10n.opmlExportError(saved.errorOrNull!.message);
      });
      return;
    }
    final String? path = saved.valueOrNull;
    setState(() {
      _busy = false;
      // 用户取消保存对话框：保持安静（取消不是失败）。
      if (path == null) {
        _message = null;
        return;
      }
      _message = result.entries == 0
          ? l10n.opmlExportEmpty
          : l10n.opmlExportDone(result.entries, path);
      _strippedCount = result.strippedSecretParams.length;
      _strippedNames = result.strippedSecretParams;
    });
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);

    return _SectionCard(
      title: l10n.opmlExportTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(l10n.opmlExportBody, style: theme.textTheme.bodySmall),
          const SizedBox(height: FluxSpacing.xs),
          // 秘密排除的说明**在导出之前**给出（SET-027）：用户应当在做决定前知道
          // 文件里不会有凭据。
          StatusBanner(
            severity: StatusBannerSeverity.info,
            message: l10n.opmlExportSecretNote,
          ),
          const SizedBox(height: FluxSpacing.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: _busy ? null : _export,
              icon: const Icon(Icons.save_alt, size: 18),
              label: Text(l10n.opmlExportAction),
            ),
          ),
          if (_message case final String message) ...<Widget>[
            const SizedBox(height: FluxSpacing.sm),
            StatusBanner(severity: StatusBannerSeverity.info, message: message),
          ],
          if (_strippedCount > 0) ...<Widget>[
            const SizedBox(height: FluxSpacing.xs),
            // 剥离过秘密参数时必须明说：用户需要知道哪些订阅在别的设备上要补凭据。
            StatusBanner(
              severity: StatusBannerSeverity.warning,
              message: l10n.opmlExportSecretRemoved(
                _strippedCount,
                _strippedNames.join(', '),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 小节卡片（统一的标题 + 卡片容器）。
class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      FluxSpacing.md,
      0,
      FluxSpacing.md,
      FluxSpacing.sm,
    ),
    child: FluxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(bottom: FluxSpacing.xs),
            child: Text(title, style: Theme.of(context).textTheme.titleSmall),
          ),
          child,
        ],
      ),
    ),
  );
}

/// 小徽标（状态标记）。
class _Tag extends StatelessWidget {
  const _Tag({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: FluxSpacing.xs,
        vertical: FluxSpacing.xxs,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(FluxRadius.button),
        border: Border.all(color: color),
      ),
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }
}

/// 页面范围说明。
class _PageNotice extends StatelessWidget {
  const _PageNotice();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      FluxSpacing.md,
      FluxSpacing.xs,
      FluxSpacing.md,
      FluxSpacing.sm,
    ),
    child: StatusBanner(message: AppLocalizations.of(context).opmlPageNotice),
  );
}

/// 导入区：选文件、分组策略、开始导入。
class _ImportSection extends ConsumerWidget {
  const _ImportSection({required this.state});

  final OpmlImportState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final OpmlImportController controller = ref.read(
      opmlImportControllerProvider.notifier,
    );

    return _SectionCard(
      title: l10n.opmlPreviewTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (state.fileName case final String name)
            Padding(
              padding: const EdgeInsets.only(bottom: FluxSpacing.xs),
              child: Text(
                l10n.opmlFileName(name),
                style: theme.textTheme.bodySmall,
              ),
            ),
          Row(
            children: <Widget>[
              FilledButton.icon(
                onPressed: state.isBusy ? null : controller.pickAndPreview,
                icon: const Icon(Icons.folder_open_outlined, size: 18),
                label: Text(
                  state.fileName == null ? l10n.opmlPickFile : l10n.opmlRepick,
                ),
              ),
              const SizedBox(width: FluxSpacing.xs),
              if (state.stage == OpmlImportStage.preview)
                TextButton(
                  onPressed: controller.reset,
                  child: Text(l10n.opmlCancel),
                ),
            ],
          ),
          const SizedBox(height: FluxSpacing.sm),
          // 分组策略（SET-026）。两个选项用分段控件表达「二选一」，而不是开关：
          // 「不保留」不是一个关闭状态，它是一条明确的替代策略。
          Text(l10n.opmlStrategyLabel, style: theme.textTheme.titleSmall),
          const SizedBox(height: FluxSpacing.xxs),
          Text(l10n.opmlStrategyHint, style: theme.textTheme.bodySmall),
          const SizedBox(height: FluxSpacing.xs),
          Align(
            alignment: Alignment.centerLeft,
            child: SegmentedButton<OpmlGroupStrategy>(
              segments: <ButtonSegment<OpmlGroupStrategy>>[
                ButtonSegment<OpmlGroupStrategy>(
                  value: OpmlGroupStrategy.uncategorized,
                  label: Text(l10n.opmlStrategyUncategorized),
                ),
                ButtonSegment<OpmlGroupStrategy>(
                  value: OpmlGroupStrategy.keepFileGroups,
                  label: Text(l10n.opmlStrategyKeepGroups),
                ),
              ],
              selected: <OpmlGroupStrategy>{state.strategy},
              showSelectedIcon: false,
              onSelectionChanged: state.isBusy
                  ? null
                  : (Set<OpmlGroupStrategy> selection) =>
                        controller.setStrategy(selection.first),
            ),
          ),
          if (state.stage == OpmlImportStage.loading) ...<Widget>[
            const SizedBox(height: FluxSpacing.sm),
            const LinearProgressIndicator(),
          ],
          if (state.stage == OpmlImportStage.importing) ...<Widget>[
            const SizedBox(height: FluxSpacing.sm),
            Row(
              children: <Widget>[
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: FluxSpacing.xs),
                Text(l10n.opmlImporting, style: theme.textTheme.bodySmall),
              ],
            ),
          ],
          // 没有任何可导入项时不给「开始导入」按钮：一个点了什么都不会发生的
          // 按钮比一个说明更让人困惑。
          if (state.stage == OpmlImportStage.preview) ...<Widget>[
            const SizedBox(height: FluxSpacing.sm),
            if (state.canImport)
              FilledButton(
                onPressed: controller.runImport,
                child: Text(l10n.opmlStartImport),
              )
            else
              StatusBanner(
                severity: StatusBannerSeverity.info,
                message: l10n.opmlNothingToImport,
              ),
          ],
        ],
      ),
    );
  }
}

/// 预览区：逐项明细 + 统计 + 重复/无效说明。
class _PreviewSection extends StatelessWidget {
  const _PreviewSection({required this.preview, required this.state});

  final OpmlPreview preview;
  final OpmlImportState state;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);

    return _SectionCard(
      title: l10n.opmlPreviewTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // 文件标题（若有）：帮用户确认选对了文件。
          if (preview.fileTitle case final String fileTitle)
            Padding(
              padding: const EdgeInsets.only(bottom: FluxSpacing.xxs),
              child: Text(fileTitle, style: theme.textTheme.bodySmall),
            ),
          Text(
            l10n.opmlPreviewSummary(
              preview.items.length,
              preview.addedCount,
              preview.duplicateCount,
              preview.invalidCount,
            ),
            style: theme.textTheme.bodyMedium,
          ),
          if (preview.duplicateCount > 0) ...<Widget>[
            const SizedBox(height: FluxSpacing.xs),
            StatusBanner(
              severity: StatusBannerSeverity.info,
              message: l10n.opmlDuplicatesNote,
            ),
          ],
          if (preview.invalidCount > 0) ...<Widget>[
            const SizedBox(height: FluxSpacing.xs),
            StatusBanner(
              severity: StatusBannerSeverity.warning,
              message: l10n.opmlInvalidNote,
            ),
          ],
          const SizedBox(height: FluxSpacing.sm),
          for (final OpmlPreviewItem item in preview.items)
            _PreviewRow(item: item),
        ],
      ),
    );
  }
}

/// 预览里的一行明细。
class _PreviewRow extends StatelessWidget {
  const _PreviewRow({required this.item});

  final OpmlPreviewItem item;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    // 状态色只用于**徽标**，正文用 onSurface：强调色对普通文字的对比度不足
    // （架构第 7 节要求正文 4.5:1）。
    final (String label, Color color) = switch (item.status) {
      OpmlPreviewStatus.added => (l10n.opmlStatusAdded, scheme.primary),
      OpmlPreviewStatus.duplicate => (
        l10n.opmlStatusDuplicate,
        scheme.onSurfaceVariant,
      ),
      OpmlPreviewStatus.invalid => (l10n.opmlStatusInvalid, scheme.error),
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: FluxSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // 序号：用户在文件里能按它定位（解析层的序号与文件里的 outline 顺序一致）。
          SizedBox(
            width: 56,
            child: Text(
              l10n.opmlEntryIndex(item.index),
              style: theme.textTheme.labelSmall,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  item.title.isEmpty ? item.url : item.title,
                  style: theme.textTheme.bodyMedium,
                  overflow: TextOverflow.ellipsis,
                ),
                if (item.url.isNotEmpty)
                  SelectableText(item.url, style: theme.textTheme.labelSmall),
                if (item.groupPath.isNotEmpty)
                  Text(
                    l10n.opmlEntryGroup(item.groupPath.join(' / ')),
                    style: theme.textTheme.labelSmall,
                  ),
                if (item.reason case final String reason)
                  Text(
                    reason,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.error,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: FluxSpacing.xs),
          _Tag(text: label, color: color),
        ],
      ),
    );
  }
}

/// 结果区：统计 + 逐项结果 + 重试按钮。
class _ResultSection extends ConsumerWidget {
  const _ResultSection({required this.result});

  final OpmlImportResult result;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final OpmlImportController controller = ref.read(
      opmlImportControllerProvider.notifier,
    );
    final List<OpmlImportItemResult> retryable = result.retryableFailures;

    return _SectionCard(
      title: l10n.opmlResultTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            l10n.opmlResultSummary(
              result.importedCount,
              result.duplicateCount,
              result.failedCount,
              result.invalidCount,
              result.importedArticleCount,
            ),
            style: theme.textTheme.bodyMedium,
          ),
          if (retryable.isNotEmpty) ...<Widget>[
            const SizedBox(height: FluxSpacing.sm),
            Text(l10n.opmlRetryHint, style: theme.textTheme.bodySmall),
            const SizedBox(height: FluxSpacing.xs),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: controller.retryFailed,
                icon: const Icon(Icons.refresh, size: 18),
                label: Text(l10n.opmlRetryFailed(retryable.length)),
              ),
            ),
          ] else ...<Widget>[
            const SizedBox(height: FluxSpacing.xs),
            Text(l10n.opmlRetryNone, style: theme.textTheme.bodySmall),
          ],
          const SizedBox(height: FluxSpacing.sm),
          for (final OpmlImportItemResult item in result.items)
            Padding(
              padding: const EdgeInsets.only(bottom: FluxSpacing.xxs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SizedBox(
                    width: 56,
                    child: Text(
                      l10n.opmlEntryIndex(item.index),
                      style: theme.textTheme.labelSmall,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      item.title.isEmpty ? item.url : item.title,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  Text(
                    _outcomeLabel(l10n, item),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: item.outcome == OpmlItemOutcome.failed
                          ? scheme.error
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// 结果状态文案（已导入时带上文章数，便于核对）。
  static String _outcomeLabel(
    AppLocalizations l10n,
    OpmlImportItemResult item,
  ) => switch (item.outcome) {
    OpmlItemOutcome.imported =>
      item.importedArticles == 0
          ? l10n.opmlStatusImported
          : '${l10n.opmlStatusImported}（+${item.importedArticles}）',
    OpmlItemOutcome.duplicate => l10n.opmlStatusDuplicate,
    OpmlItemOutcome.failed => l10n.opmlStatusFailed,
    OpmlItemOutcome.invalid => l10n.opmlStatusInvalid,
  };
}
