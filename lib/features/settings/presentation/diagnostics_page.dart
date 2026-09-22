// 设置 → 诊断与恢复（T048；SET-082、架构 5.3 的恢复段与第 8 节）。
//
// 页面的两条承诺：
//
//   1) **导出前明说包内有什么、不含什么**，确认后才弹保存面板。诊断包会被贴进 Issue 或发给
//      别人，「用户知道自己在分享什么」不是可选项；
//   2) **恢复编排的状态如实展示**：待重启 / 已切换（待清理旧目录）/ 失败回退三种，各自说明
//      「当前数据在哪」，并只提供该阶段真正可用的动作。一个在任何阶段都能点的「删除旧目录」
//      按钮是这里最危险的假功能。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flux/core/core.dart';
import 'package:flux/core/design/design_tokens.dart';
import 'package:flux/features/feeds/presentation/feed_dialogs.dart';
import 'package:flux/l10n/l10n.dart';

import '../application/maintenance_ports.dart';

/// 诊断与恢复页。
class DiagnosticsPage extends ConsumerStatefulWidget {
  /// 构造页面。
  const DiagnosticsPage({super.key});

  @override
  ConsumerState<DiagnosticsPage> createState() => _DiagnosticsPageState();
}

class _DiagnosticsPageState extends ConsumerState<DiagnosticsPage> {
  bool _busy = false;
  String? _notice;
  String? _error;
  String? _savedPath;

  @override
  void initState() {
    super.initState();
    // 读一次编排状态（只读，不发任何变更）。
    unawaited(_loadState());
  }

  Future<void> _loadState() async {
    final Result<RestoreOrchestrationState> state = await ref
        .read(restoreOrchestratorProvider)
        .readState();
    if (!mounted) {
      return;
    }
    if (state.isOk) {
      ref.read(restoreActionProvider.notifier).publish(state.unwrap());
    } else {
      setState(() => _error = state.errorOrNull!.kind);
    }
  }

  /// 导出：先说明再确认，然后才弹保存面板。
  Future<void> _export() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        key: const ValueKey<String>('diagnostics-export-confirm'),
        title: Text(l10n.diagnosticsExportConfirmTitle),
        content: SizedBox(
          width: dialogMaxWidth,
          child: Text(l10n.diagnosticsExportConfirmBody),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.settingsBackupCancel),
          ),
          FilledButton(
            key: const ValueKey<String>('diagnostics-export-go'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.diagnosticsExportConfirmAction),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    setState(() {
      _busy = true;
      _notice = null;
      _error = null;
      _savedPath = null;
    });
    final Result<DiagnosticsExportResult?> result = await ref
        .read(diagnosticsExportServiceProvider)
        .export();
    if (!mounted) {
      return;
    }
    setState(() {
      _busy = false;
      if (result.isErr) {
        _error = result.errorOrNull!.kind;
      } else if (result.valueOrNull case final DiagnosticsExportResult done) {
        _notice = l10n.diagnosticsExportDone(
          done.fieldCount,
          done.logEntryCount,
          describeBytes(done.byteCount),
        );
        _savedPath = done.path;
      }
      // 返回 Ok(null) = 用户在保存面板里取消：不是错误，也不是「导出成功」。
    });
  }

  /// 删除被顶替的旧数据目录（只在 switched 阶段可用）。
  Future<void> _cleanup() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        key: const ValueKey<String>('diagnostics-cleanup-confirm'),
        title: Text(l10n.diagnosticsRestoreCleanupConfirmTitle),
        content: SizedBox(
          width: dialogMaxWidth,
          child: Text(l10n.diagnosticsRestoreCleanupConfirmBody),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.settingsBackupCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.diagnosticsRestoreCleanupAction),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    setState(() => _busy = true);
    final Result<String?> done = await ref
        .read(restoreOrchestratorProvider)
        .completeCleanup();
    if (!mounted) {
      return;
    }
    setState(() {
      _busy = false;
      if (done.isErr) {
        _error = done.errorOrNull!.kind;
      } else {
        _notice = l10n.diagnosticsRestoreCleanupDone;
      }
    });
    await _loadState();
  }

  /// 放弃这次恢复（只清标记，不删恢复出来的目录）。
  Future<void> _abandon() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    final Result<void> done = await ref
        .read(restoreOrchestratorProvider)
        .abandon();
    if (!mounted) {
      return;
    }
    setState(() {
      _busy = false;
      if (done.isErr) {
        _error = done.errorOrNull!.kind;
      } else {
        _notice = l10n.diagnosticsRestoreAbandonDone;
      }
    });
    await _loadState();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final RestoreOrchestrationState state = ref.watch(restoreActionProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.diagnosticsPageTitle)),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: FluxSpacing.md),
        children: <Widget>[
          if (_error case final String reason)
            _Notice(
              icon: Icons.error_outline,
              isError: true,
              text: l10n.diagnosticsFailed(reason),
            ),
          if (_notice case final String text)
            _Notice(icon: Icons.info_outline, text: text),
          if (_savedPath case final String path)
            _Notice(
              icon: Icons.folder_outlined,
              text: l10n.diagnosticsExportPath(path),
            ),
          _SectionHeader(title: l10n.diagnosticsSectionExport),
          _Paragraph(text: l10n.diagnosticsExportNotice),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: FluxSpacing.md,
              vertical: FluxSpacing.xs,
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                key: const ValueKey<String>('diagnostics-export'),
                onPressed: _busy ? null : () => unawaited(_export()),
                icon: const Icon(Icons.description_outlined),
                label: Text(l10n.diagnosticsExportAction),
              ),
            ),
          ),
          _SectionHeader(title: l10n.diagnosticsSectionRestore),
          ..._restoreRows(l10n, state),
        ],
      ),
    );
  }

  List<Widget> _restoreRows(
    AppLocalizations l10n,
    RestoreOrchestrationState state,
  ) {
    final List<Widget> rows = <Widget>[];
    if (state.failureKind case final String reason) {
      rows.add(
        _Notice(
          icon: Icons.warning_amber_outlined,
          isError: true,
          text: l10n.diagnosticsRestoreFailure(reason),
        ),
      );
    }
    switch (state.phase) {
      case null:
        rows.add(_Paragraph(text: l10n.diagnosticsRestoreIdle));
      case RestorePhase.pendingRestart:
        rows.add(
          _Paragraph(text: l10n.diagnosticsRestorePending, emphasize: true),
        );
        if (state.restoredDirectory case final String dir) {
          rows.add(_Paragraph(text: l10n.diagnosticsRestoreRestored(dir)));
        }
        rows.add(
          _ActionRow(
            key: const ValueKey<String>('diagnostics-abandon'),
            label: l10n.diagnosticsRestoreAbandonAction,
            icon: Icons.undo,
            onPressed: _busy ? null : () => unawaited(_abandon()),
          ),
        );
      case RestorePhase.switched:
        rows.add(
          _Paragraph(text: l10n.diagnosticsRestoreSwitched, emphasize: true),
        );
        if (state.restoredDirectory case final String dir) {
          rows.add(_Paragraph(text: l10n.diagnosticsRestoreRestored(dir)));
        }
        if (state.supersededDirectory case final String superseded) {
          rows.add(
            _Paragraph(text: l10n.diagnosticsRestoreSuperseded(superseded)),
          );
          rows.add(
            _ActionRow(
              key: const ValueKey<String>('diagnostics-cleanup'),
              label: l10n.diagnosticsRestoreCleanupAction,
              icon: Icons.delete_outline,
              onPressed: _busy ? null : () => unawaited(_cleanup()),
            ),
          );
        }
      case RestorePhase.cleaned:
        // cleaned 阶段不该停留（标记会被清掉），但标记损坏或并发情况下可能读到：按「已完成」
        // 显示而不是崩掉。
        rows.add(_Paragraph(text: l10n.diagnosticsRestoreIdle));
    }
    return rows;
  }
}

/// 分段标题。
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      FluxSpacing.md,
      FluxSpacing.md,
      FluxSpacing.md,
      FluxSpacing.xs,
    ),
    child: Text(title, style: Theme.of(context).textTheme.titleSmall),
  );
}

/// 一段说明。
class _Paragraph extends StatelessWidget {
  const _Paragraph({required this.text, this.emphasize = false});

  final String text;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: FluxSpacing.md,
        vertical: FluxSpacing.xxs,
      ),
      child: Text(
        text,
        style: emphasize
            ? theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.primary,
              )
            : theme.textTheme.bodySmall,
      ),
    );
  }
}

/// 提示条。
class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text, this.isError = false});

  final IconData icon;
  final String text;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final Color color = isError ? colors.error : colors.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: FluxSpacing.md,
        vertical: FluxSpacing.xs,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 18, color: color),
          const SizedBox(width: FluxSpacing.xs),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}

/// 一个动作行。
class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.label,
    required this.icon,
    required this.onPressed,
    super.key,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon),
    title: Text(label),
    enabled: onPressed != null,
    onTap: onPressed,
    dense: true,
  );
}
