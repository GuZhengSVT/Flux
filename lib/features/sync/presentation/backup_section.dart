// 备份与恢复小节（T046）：导出/恢复两个按钮、风险告知、预检信息与二次确认。
//
// 界面承诺（逐条对应架构 5.3）：
//   1) **风险告知前置**：导出前必须先看到「明文备份包含个人订阅与正文，任何持有者均可读取」，
//      确认后才弹保存对话框——顺序反过来就成了「用户已经选好文件名才被告知风险」；
//   2) **预检信息可读**：恢复先显示备份时间/版本/文章数/订阅数/是否含媒体，用户据此判断
//      「这是不是我要的那一份」；
//   3) **二次确认**：预检之后还要再确认一次，并明说「先写新目录、校验通过才切换，失败不动原库」；
//   4) **失败分类展示**：哈希不符与路径穿越的处置完全不同（前者重新导出，后者是包不可信），
//      因此错误按稳定类别名映射成可区分的说明，而不是一句「恢复失败」。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flux/core/core.dart';
import 'package:flux/core/design/design_tokens.dart';
import 'package:flux/features/feeds/presentation/feed_dialogs.dart';
import 'package:flux/features/settings/application/settings_controller.dart';
import 'package:flux/l10n/l10n.dart';

import '../application/backup_providers.dart';
import '../application/backup_use_case.dart';

/// 备份与恢复小节。
class BackupSection extends ConsumerStatefulWidget {
  /// 构造小节。
  const BackupSection({super.key});

  @override
  ConsumerState<BackupSection> createState() => _BackupSectionState();
}

class _BackupSectionState extends ConsumerState<BackupSection> {
  bool _includeMedia = false;
  bool _busy = false;
  String? _notice;
  String? _savedPath;

  /// 已经预检过、等待用户确认的那一份包（预览 + 当时读到的字节）。
  ///
  /// 恢复时用这一份而不是重新读一遍文件：用户确认的依据是预检时看到的「备份时间/版本/
  /// 文章数」，重新读盘会让他在两次点击之间换掉的那个文件被当成他确认过的那一份。
  BackupInspection? _pending;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final Result<Object?> read = await ref
        .read(settingsStoreProvider)
        .readSetting(SettingId.set076);
    if (!mounted) {
      return;
    }
    final Object? raw = read.valueOrNull;
    setState(() {
      _includeMedia = raw is Map<String, Object?>
          ? raw['includeMedia'] == true
          : false;
    });
  }

  /// 记住含媒体开关（SET-076：下次导出沿用）。
  Future<void> _writeIncludeMedia(bool value) async {
    setState(() => _includeMedia = value);
    await ref.read(settingsStoreProvider).writeSetting(
      SettingId.set076,
      <String, Object?>{'includeMedia': value},
    );
  }

  /// 导出：先风险确认，再弹保存对话框。
  Future<void> _export() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool? acknowledged = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        key: const ValueKey<String>('backup-risk-dialog'),
        title: Text(l10n.settingsBackupRiskConfirmTitle),
        content: SizedBox(
          width: dialogMaxWidth,
          child: Text(l10n.settingsBackupNotice),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.settingsBackupCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.settingsBackupRiskConfirmContinue),
          ),
        ],
      ),
    );
    if (acknowledged != true || !mounted) {
      return;
    }
    setState(() {
      _busy = true;
      _notice = null;
      _savedPath = null;
    });
    final Result<BackupExportResult?> result = await ref
        .read(backupUseCaseProvider)
        .export(
          includeMedia: _includeMedia,
          suggestedName:
              'flux-backup-${DateTime.now().toIso8601String().split('T').first}.zip',
        );
    if (!mounted) {
      return;
    }
    setState(() {
      _busy = false;
      if (result.isErr) {
        _notice = l10n.settingsBackupFailed(_reasonOf(result.errorOrNull!));
      } else if (result.valueOrNull == null) {
        // 用户取消：什么都不说（把它显示成「失败」会让人以为出了错）。
        _notice = null;
      } else {
        final BackupExportResult exported = result.unwrap()!;
        _savedPath = exported.path;
        _notice = l10n.settingsBackupExportDone(
          exported.entryCount,
          (exported.bytes / 1024).round(),
        );
      }
    });
  }

  /// 恢复：选文件 → 预检 → 二次确认 → 恢复到新目录。
  Future<void> _restore() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _notice = null;
      _savedPath = null;
    });
    final BackupUseCase service = ref.read(backupUseCaseProvider);
    final Result<BackupInspection?> picked = await service.inspectBackup();
    if (!mounted) {
      return;
    }
    if (picked.isErr) {
      setState(() {
        _busy = false;
        _notice = l10n.settingsBackupFailed(_reasonOf(picked.errorOrNull!));
      });
      return;
    }
    final BackupInspection? inspection = picked.valueOrNull;
    if (inspection == null) {
      setState(() => _busy = false);
      return;
    }
    final BackupRestorePreview preview = inspection.preview;
    _pending = inspection;
    // 预检已经结束（文件读完、包也校验完了），因此**先收起进度条再弹确认框**：进度条是
    // 不定长动画，它留在屏幕上会让「等待用户确认」看起来像「还在忙」，而用户会一直等一个
    // 实际上在等他做决定的界面。
    setState(() => _busy = false);
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        key: const ValueKey<String>('backup-restore-dialog'),
        title: Text(l10n.settingsBackupRestorePreviewTitle),
        content: SizedBox(
          width: dialogMaxWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                l10n.settingsBackupPreviewLine(
                  preview.createdAt.toLocal().toString(),
                  preview.schemaVersion,
                  preview.articleCount,
                  preview.feedCount,
                  preview.includeMedia
                      ? l10n.settingsBackupWithMedia
                      : l10n.settingsBackupWithoutMedia,
                ),
              ),
              const SizedBox(height: FluxSpacing.sm),
              Text(l10n.settingsBackupRestoreConfirmBody),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.settingsBackupCancel),
          ),
          FilledButton(
            key: const ValueKey<String>('backup-restore-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.settingsBackupRestoreConfirmAction),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      setState(() {
        _busy = false;
        _pending = null;
      });
      return;
    }
    // 用户确认了：恢复（写新目录 + 校验）才是真正的耗时动作，此时再起进度条。
    setState(() => _busy = true);
    // 恢复到**新目录**：与当前数据目录并列，因此既不覆盖当前库，也能在重启后被使用。
    // 恢复到**新目录**：与当前数据目录并列，因此既不覆盖当前库，也能在重启后被使用。
    final String base = ref.read(backupNewDirectoryProvider)(
      DateTime.now().millisecondsSinceEpoch.toString(),
    );
    final Result<BackupRestoreResult> restored = await service.restore(
      preview: preview,
      archiveBytes: _pending!.archiveBytes,
      targetDirectory: base,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _busy = false;
      if (restored.isErr) {
        _notice = l10n.settingsBackupFailed(_reasonOf(restored.errorOrNull!));
      } else {
        _notice = l10n.settingsBackupRestoreDone(
          preview.articleCount,
          preview.includeMedia ? 1 : 0,
        );
        _savedPath = restored.unwrap().directory;
        _pending = null;
      }
    });
  }

  /// 错误 → 稳定类别名（分类展示：哈希不符要重新导出，路径穿越是包不可信）。
  static String _reasonOf(AppError error) => switch (error) {
    ValidationError(:final String reason) => reason,
    _ => error.kind,
  };

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _BackupSectionHeader(title: l10n.settingsBackupSectionTitle),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: FluxSpacing.md),
          child: Text(
            l10n.settingsBackupNotice,
            key: const ValueKey<String>('backup-notice'),
            style: theme.textTheme.bodySmall,
          ),
        ),
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: FluxSpacing.md,
          ),
          value: _includeMedia,
          onChanged: _busy
              ? null
              : (bool value) => unawaited(_writeIncludeMedia(value)),
          title: Text(l10n.settingsBackupIncludeMedia),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: FluxSpacing.md,
            vertical: FluxSpacing.xs,
          ),
          child: Row(
            children: <Widget>[
              FilledButton.icon(
                key: const ValueKey<String>('backup-export'),
                onPressed: _busy ? null : () => unawaited(_export()),
                icon: const Icon(Icons.save_alt),
                label: Text(l10n.settingsBackupExport),
              ),
              const SizedBox(width: FluxSpacing.xs),
              OutlinedButton.icon(
                key: const ValueKey<String>('backup-restore'),
                onPressed: _busy ? null : () => unawaited(_restore()),
                icon: const Icon(Icons.settings_backup_restore),
                label: Text(l10n.settingsBackupRestore),
              ),
            ],
          ),
        ),
        if (_busy)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: FluxSpacing.md),
            child: LinearProgressIndicator(
              key: ValueKey<String>('backup-progress'),
            ),
          ),
        if (_notice case final String notice)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: FluxSpacing.md),
            child: Text(
              notice,
              key: const ValueKey<String>('backup-notice-result'),
              style: theme.textTheme.bodySmall,
            ),
          ),
        if (_savedPath case final String path)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: FluxSpacing.md),
            child: Text(
              l10n.settingsBackupPathNote(path),
              style: theme.textTheme.labelSmall,
            ),
          ),
      ],
    );
  }
}

/// 小节标题（与同步设置页的小节标题同一形状：本文件不 import 那个私有控件）。
class _BackupSectionHeader extends StatelessWidget {
  const _BackupSectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        FluxSpacing.md,
        FluxSpacing.md,
        FluxSpacing.md,
        FluxSpacing.xs,
      ),
      child: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}
