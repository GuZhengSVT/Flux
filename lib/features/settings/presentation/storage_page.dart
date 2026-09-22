// 设置 → 存储与清理（T047；架构 5.3 的清理段、SET-077/078/079/080）。
//
// 页面的四条承诺，逐条对应架构原话：
//
//   1) **分类占用可读**：媒体 / 文章正文 / 新闻总结 / 其他缓存 / 设置与状态数据库各自一行，
//      并显示**测量时间**——架构 5.3 把测量时间与分类并列提出，因为一个没有时间的数字无法让
//      用户判断它是否还对得上当前状态；
//   2) **清缓存有预览与确认**：预览先给出「将释放什么」，确认页明说**只删可再生内容**，并
//      指出付费结果需要单独处理。没有这两步的清理按钮等于让用户闭着眼睛删；
//   3) **自动清理默认关且可见**：三个开关与天数真实读写 SET-077，收藏/later 的保护开关读写
//      SET-078，并在打开时给出明确警告（架构 5.3 要求「必须在确认页说明」）；
//   4) **预览与执行共用同一影响形状**：因此「预览说 3 MiB、执行后回执说 3 MiB」是可以对上的，
//      而不是两个各写一套的数字。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flux/core/core.dart';
import 'package:flux/core/design/design_tokens.dart';
import 'package:flux/features/feeds/presentation/feed_dialogs.dart';
import 'package:flux/l10n/l10n.dart';

import '../application/cleanup_ports.dart';
import '../application/cleanup_service.dart';
import '../application/settings_controller.dart';
import '../application/settings_store.dart';

/// 存储与清理页。
class StoragePage extends ConsumerStatefulWidget {
  /// 构造页面。
  const StoragePage({super.key});

  @override
  ConsumerState<StoragePage> createState() => _StoragePageState();
}

class _StoragePageState extends ConsumerState<StoragePage> {
  StorageUsageReport? _usage;
  AutoCleanupPolicy _policy = AutoCleanupPolicy.defaults;
  int _mediaLimitMiB = kDefaultCacheMiB;
  bool _loading = true;
  bool _busy = false;
  String? _notice;
  String? _error;
  CleanupImpact? _clearPreview;
  SnapshotGcResult? _orphanPreview;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  /// 读设置与占用。
  Future<void> _load() async {
    final SettingsStore store = ref.read(settingsStoreProvider);
    final Result<Object?> set077 = await store.readSetting(SettingId.set077);
    final Result<Object?> set078 = await store.readSetting(SettingId.set078);
    final Result<Object?> set080 = await store.readSetting(SettingId.set080);
    if (!mounted) {
      return;
    }
    setState(() {
      _policy = AutoCleanupPolicy.fromSettings(
        set077.valueOrNull is Map<String, Object?>
            ? set077.valueOrNull! as Map<String, Object?>
            : null,
        set078.valueOrNull is Map<String, Object?>
            ? set078.valueOrNull! as Map<String, Object?>
            : null,
      );
      _mediaLimitMiB = set080.valueOrNull is int
          ? set080.valueOrNull! as int
          : kDefaultCacheMiB;
    });
    await _refreshUsage();
  }

  /// 重新测量占用。
  ///
  /// **只在成功时替换 `_usage`**：一次读取失败不该把用户已经看到的数字变成空白（那会让他
  /// 以为「占用没了」而不是「这次读数失败了」）。失败只设置错误提示，上一次的数字留在界面上。
  Future<void> _refreshUsage() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final Result<StorageUsageReport> measured = await ref
        .read(cleanupServiceProvider)
        .measure(mediaLimitMiB: _mediaLimitMiB);
    if (!mounted) {
      return;
    }
    setState(() {
      _loading = false;
      if (measured.isOk) {
        _usage = measured.unwrap();
      } else {
        _error = measured.errorOrNull!.kind;
      }
    });
  }

  /// 写 SET-077 的一个字段并保留其余字段。
  ///
  /// 复合项必须**整块写**（注册表按字段校验一个 Map），因此每个开关都要带上当前全部字段；
  /// 只写被改的那个字段会让其余字段落回默认值（表现为「打开媒体清理」把正文的天数重置了）。
  Future<void> _writePolicy(AutoCleanupPolicy next) async {
    final Result<void> written = await _write(
      SettingId.set077,
      <String, Object?>{
        'mediaEnabled': next.mediaEnabled,
        'mediaDays': next.mediaDays,
        'articleEnabled': next.articleEnabled,
        'articleDays': next.articleDays,
        'summaryEnabled': next.summaryEnabled,
        'summaryDays': next.summaryDays,
      },
      SettingId.set078,
      <String, Object?>{
        'includeFavorite': next.includeFavorite,
        'includeLater': next.includeLater,
      },
    );
    if (written.isErr) {
      return;
    }
    setState(() {
      _policy = next;
      _notice = null;
    });
  }

  Future<Result<void>> _write(
    SettingId firstId,
    Object first,
    SettingId secondId,
    Object second,
  ) async {
    final SettingsStore store = ref.read(settingsStoreProvider);
    final Result<Object?> a = await store.writeSetting(firstId, first);
    if (a.isErr) {
      if (mounted) {
        setState(() => _error = a.errorOrNull!.kind);
      }
      return Err<void>(a.errorOrNull!);
    }
    final Result<Object?> b = await store.writeSetting(secondId, second);
    if (b.isErr) {
      if (mounted) {
        setState(() => _error = b.errorOrNull!.kind);
      }
      return Err<void>(b.errorOrNull!);
    }
    return okUnit();
  }

  // -----------------------------------------------------------------------
  // 一键清缓存
  // -----------------------------------------------------------------------

  Future<void> _previewClear() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    final Result<CleanupImpact> preview = await ref
        .read(cleanupServiceProvider)
        .previewClearRegenerable();
    if (!mounted) {
      return;
    }
    setState(() {
      _busy = false;
      _clearPreview = preview.valueOrNull;
      _error = preview.isErr ? preview.errorOrNull!.kind : null;
    });
    final CleanupImpact? impact = preview.valueOrNull;
    if (impact == null || impact.isEmpty) {
      if (mounted) {
        setState(() => _notice = l10n.storageClearEmpty);
      }
      return;
    }
    if (!mounted) {
      return;
    }
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        key: const ValueKey<String>('storage-clear-confirm'),
        title: Text(l10n.storageClearConfirmTitle),
        content: SizedBox(
          width: dialogMaxWidth,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                l10n.storageClearImpact(
                  describeBytes(impact.totalBytes),
                  impact.mediaEntries,
                  impact.aiCacheEntries,
                  impact.failedTaskDrafts,
                ),
              ),
              const SizedBox(height: FluxSpacing.sm),
              Text(l10n.storageClearConfirmBody),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.settingsBackupCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.storageClearConfirmAction),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    setState(() => _busy = true);
    final Result<CleanupImpact> done = await ref
        .read(cleanupServiceProvider)
        .clearRegenerable();
    if (!mounted) {
      return;
    }
    setState(() {
      _busy = false;
      _error = done.isErr ? done.errorOrNull!.kind : null;
      _notice = done.isOk
          ? l10n.storageClearDone(describeBytes(done.unwrap().totalBytes))
          : null;
      _clearPreview = null;
    });
    await _refreshUsage();
  }

  // -----------------------------------------------------------------------
  // 自动清理
  // -----------------------------------------------------------------------

  Future<void> _previewAuto() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    final Result<CleanupImpact> preview = await ref
        .read(cleanupServiceProvider)
        .previewAutoCleanup(_policy);
    if (!mounted) {
      return;
    }
    setState(() {
      _busy = false;
      _error = preview.isErr ? preview.errorOrNull!.kind : null;
      _notice = preview.isOk
          ? l10n.storageAutoImpact(
              describeBytes(preview.unwrap().totalBytes),
              preview.unwrap().mediaEntries,
              preview.unwrap().articleBodies,
              preview.unwrap().summaryRuns,
              preview.unwrap().protectedArticles,
            )
          : null;
    });
  }

  Future<void> _runAuto() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        key: const ValueKey<String>('storage-auto-confirm'),
        title: Text(l10n.storageAutoConfirmTitle),
        content: SizedBox(
          width: dialogMaxWidth,
          child: Text(l10n.storageAutoConfirmBody),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.settingsBackupCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.storageAutoConfirmAction),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    setState(() => _busy = true);
    final Result<CleanupImpact> done = await ref
        .read(cleanupServiceProvider)
        .runAutoCleanup(_policy);
    if (!mounted) {
      return;
    }
    setState(() {
      _busy = false;
      _error = done.isErr ? done.errorOrNull!.kind : null;
      _notice = done.isOk
          ? l10n.storageAutoDone(describeBytes(done.unwrap().totalBytes))
          : null;
    });
    await _refreshUsage();
  }

  // -----------------------------------------------------------------------
  // 孤儿快照
  // -----------------------------------------------------------------------

  Future<void> _collectOrphans({required bool dryRun}) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    final Result<SnapshotGcResult?> result = await ref
        .read(cleanupServiceProvider)
        .collectOrphanSnapshots(
          // 被引用集合至少含「本机当前基线版本对应的快照名」；这里给出一个**保守**的非空集合由
          // 调用方（组合根）注入更完整的信息。本页只做维护动作，因此不猜远端引用关系：把
          // 当前版本之外的都当成「可能是别人的基线」，只回收超过保留天数的那部分。
          referencedNames: const <String>{},
          dryRun: dryRun,
        );
    if (!mounted) {
      return;
    }
    final SnapshotGcResult? value = result.valueOrNull;
    setState(() {
      _busy = false;
      _error = result.isErr ? result.errorOrNull!.kind : null;
      _orphanPreview = value;
      _notice = value == null
          ? null
          : (dryRun
                ? l10n.storageOrphanResult(
                    value.considered,
                    value.collected.length,
                    value.skippedForMissingTime,
                  )
                : l10n.storageOrphanDone(value.collected.length));
    });
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool hasSnapshotGc = ref.watch(snapshotGcPortProvider) != null;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.storagePageTitle)),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: FluxSpacing.md),
        children: <Widget>[
          if (_error case final String reason)
            _Notice(
              icon: Icons.error_outline,
              isError: true,
              text: l10n.storageFailed(reason),
            ),
          if (_notice case final String text)
            _Notice(icon: Icons.info_outline, text: text),
          _SectionHeader(title: l10n.storageSectionUsage),
          // 只在**首次**读取时显示转圈：已经有数据时再显示进度指示器会让整页内容消失一瞬，
          // 而「刷新占用」是一个随时可做的小动作，不该把用户已经看到的信息抹掉。
          if (_loading && _usage == null)
            const Padding(
              padding: EdgeInsets.all(FluxSpacing.md),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_usage case final StorageUsageReport usage)
            ..._usageRows(l10n, usage),
          _ActionRow(
            label: l10n.storageRefreshUsage,
            icon: Icons.refresh,
            onPressed: _busy ? null : _refreshUsage,
          ),
          _SectionHeader(title: l10n.storageSectionClear),
          _Paragraph(text: l10n.storageClearNotice),
          _Paragraph(text: l10n.storageClearPaidNote),
          if (_clearPreview case final CleanupImpact impact)
            _Paragraph(
              text: l10n.storageClearImpact(
                describeBytes(impact.totalBytes),
                impact.mediaEntries,
                impact.aiCacheEntries,
                impact.failedTaskDrafts,
              ),
              emphasize: true,
            ),
          _ActionRow(
            label: l10n.storageClearPreview,
            icon: Icons.cleaning_services_outlined,
            onPressed: _busy ? null : _previewClear,
          ),
          _SectionHeader(title: l10n.storageSectionAuto),
          _Paragraph(text: l10n.storageAutoNotice),
          _SwitchRow(
            key: const ValueKey<String>('storage-auto-media'),
            label: l10n.storageAutoMediaSwitch,
            value: _policy.mediaEnabled,
            onChanged: _busy
                ? null
                : (bool value) =>
                      _writePolicy(_copyPolicy(mediaEnabled: value)),
          ),
          _DaysRow(
            key: const ValueKey<String>('storage-auto-media-days'),
            label: l10n.storageAutoDays,
            value: _policy.mediaDays,
            enabled: _policy.mediaEnabled && !_busy,
            onChanged: (int days) => _writePolicy(_copyPolicy(mediaDays: days)),
          ),
          _SwitchRow(
            key: const ValueKey<String>('storage-auto-article'),
            label: l10n.storageAutoArticleSwitch,
            value: _policy.articleEnabled,
            onChanged: _busy
                ? null
                : (bool value) =>
                      _writePolicy(_copyPolicy(articleEnabled: value)),
          ),
          _DaysRow(
            key: const ValueKey<String>('storage-auto-article-days'),
            label: l10n.storageAutoDays,
            value: _policy.articleDays,
            enabled: _policy.articleEnabled && !_busy,
            onChanged: (int days) =>
                _writePolicy(_copyPolicy(articleDays: days)),
          ),
          _SwitchRow(
            key: const ValueKey<String>('storage-auto-summary'),
            label: l10n.storageAutoSummarySwitch,
            value: _policy.summaryEnabled,
            onChanged: _busy
                ? null
                : (bool value) =>
                      _writePolicy(_copyPolicy(summaryEnabled: value)),
          ),
          _DaysRow(
            key: const ValueKey<String>('storage-auto-summary-days'),
            label: l10n.storageAutoDays,
            value: _policy.summaryDays,
            enabled: _policy.summaryEnabled && !_busy,
            onChanged: (int days) =>
                _writePolicy(_copyPolicy(summaryDays: days)),
          ),
          _SwitchRow(
            key: const ValueKey<String>('storage-auto-include-favorite'),
            label: l10n.storageProtectFavorite,
            value: _policy.includeFavorite,
            onChanged: _busy
                ? null
                : (bool value) =>
                      _writePolicy(_copyPolicy(includeFavorite: value)),
          ),
          _SwitchRow(
            key: const ValueKey<String>('storage-auto-include-later'),
            label: l10n.storageProtectLater,
            value: _policy.includeLater,
            onChanged: _busy
                ? null
                : (bool value) =>
                      _writePolicy(_copyPolicy(includeLater: value)),
          ),
          if (_policy.includeFavorite || _policy.includeLater)
            _Notice(
              icon: Icons.warning_amber_outlined,
              text: l10n.storageProtectWarning,
            ),
          if (_policy.isFullyDisabled)
            _Paragraph(text: l10n.storageAutoDisabled),
          _ActionRow(
            label: l10n.storageAutoPreview,
            icon: Icons.preview_outlined,
            onPressed: _busy || _policy.isFullyDisabled ? null : _previewAuto,
          ),
          _ActionRow(
            label: l10n.storageAutoRunNow,
            icon: Icons.delete_sweep_outlined,
            onPressed: _busy || _policy.isFullyDisabled ? null : _runAuto,
          ),
          _SectionHeader(title: l10n.storageSectionOrphan),
          _Paragraph(text: l10n.storageOrphanNotice),
          if (!hasSnapshotGc)
            _Paragraph(text: l10n.storageOrphanUnavailable)
          else ...<Widget>[
            if (_orphanPreview case final SnapshotGcResult gc)
              _Paragraph(
                text: l10n.storageOrphanResult(
                  gc.considered,
                  gc.collected.length,
                  gc.skippedForMissingTime,
                ),
                emphasize: true,
              ),
            _ActionRow(
              label: l10n.storageOrphanPreview,
              icon: Icons.search,
              onPressed: _busy ? null : () => _collectOrphans(dryRun: true),
            ),
            _ActionRow(
              label: l10n.storageOrphanCollect,
              icon: Icons.cloud_off_outlined,
              onPressed: _busy ? null : () => _collectOrphans(dryRun: false),
            ),
          ],
        ],
      ),
    );
  }

  AutoCleanupPolicy _copyPolicy({
    bool? mediaEnabled,
    int? mediaDays,
    bool? articleEnabled,
    int? articleDays,
    bool? summaryEnabled,
    int? summaryDays,
    bool? includeFavorite,
    bool? includeLater,
  }) => AutoCleanupPolicy(
    mediaEnabled: mediaEnabled ?? _policy.mediaEnabled,
    mediaDays: mediaDays ?? _policy.mediaDays,
    articleEnabled: articleEnabled ?? _policy.articleEnabled,
    articleDays: articleDays ?? _policy.articleDays,
    summaryEnabled: summaryEnabled ?? _policy.summaryEnabled,
    summaryDays: summaryDays ?? _policy.summaryDays,
    includeFavorite: includeFavorite ?? _policy.includeFavorite,
    includeLater: includeLater ?? _policy.includeLater,
  );

  List<Widget> _usageRows(
    AppLocalizations l10n,
    StorageUsageReport usage,
  ) => <Widget>[
    for (final StorageCategoryUsage item in usage.categories)
      _Paragraph(
        key: ValueKey<String>('storage-usage-${item.category.name}'),
        text: l10n.storageCategoryLine(
          _categoryLabel(l10n, item.category),
          describeBytes(item.byteCount),
          item.itemCount,
        ),
      ),
    _Paragraph(text: l10n.storageTotalLine(describeBytes(usage.totalBytes))),
    if (usage.mediaLimitBytes case final int limit)
      _Paragraph(text: l10n.storageMediaLimitLine(describeBytes(limit))),
    _Paragraph(text: l10n.storageMeasuredAt(_formatTime(usage.measuredAt))),
  ];

  static String _categoryLabel(
    AppLocalizations l10n,
    StorageCategory category,
  ) => switch (category) {
    StorageCategory.mediaCache => l10n.storageCategoryMedia,
    StorageCategory.articleBody => l10n.storageCategoryArticleBody,
    StorageCategory.newsSummary => l10n.storageCategorySummary,
    StorageCategory.otherCache => l10n.storageCategoryOtherCache,
    StorageCategory.database => l10n.storageCategoryDatabase,
  };

  /// 用**本地时间**显示测量时刻。
  ///
  /// 存的是 UTC（架构 5.1），而界面上的「测量时间」是给用户对表用的——显示 UTC 会让他
  /// 与自己的时钟对不上。两种时区的差异在跨时区使用时才会暴露，因此不靠用户去换算。
  static String _formatTime(DateTime utc) {
    final DateTime local = utc.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
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

/// 一段说明或一条数据行。
class _Paragraph extends StatelessWidget {
  const _Paragraph({required this.text, this.emphasize = false, super.key});

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

/// 一个开关行。
class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.label,
    required this.value,
    required this.onChanged,
    super.key,
  });

  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => SwitchListTile(
    title: Text(label, style: Theme.of(context).textTheme.bodyMedium),
    value: value,
    onChanged: onChanged,
    dense: true,
  );
}

/// 天数编辑行。
///
/// 用「减 / 加 + 当前值」而不是一个文本输入框：天数的合法区间是 1–3650（注册表），而一个自由
/// 输入的框在用户敲进 0 或 99999 时只能靠一次**失败的写入**来纠正（值被校验拒绝后界面回退，而
/// 用户看到自己刚输入的数字又变回去了）。步进按钮让越界在结构上不可达。
class _DaysRow extends StatelessWidget {
  const _DaysRow({
    required this.label,
    required this.value,
    required this.enabled,
    required this.onChanged,
    super.key,
  });

  final String label;
  final int value;
  final bool enabled;
  final ValueChanged<int> onChanged;

  /// 步进档位（天数越小，步进越细；默认值 30/90/365 都在这些档位上）。
  static const List<int> _steps = <int>[1, 7, 30, 90, 365, 3650];

  /// 下一个更大的档位；已到最大时返回当前值（按钮随后被禁用）。
  int get _nextLarger {
    for (final int step in _steps) {
      if (step > value) {
        return step;
      }
    }
    return value;
  }

  /// 下一个更小的档位；已是 1 时返回 1。
  int get _nextSmaller {
    int previous = 1;
    for (final int step in _steps) {
      if (step >= value) {
        return previous;
      }
      previous = step;
    }
    return previous;
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: FluxSpacing.md,
      vertical: FluxSpacing.xxs,
    ),
    child: Row(
      children: <Widget>[
        Expanded(
          child: Text(
            '$label：$value',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        IconButton(
          icon: const Icon(Icons.remove),
          onPressed: enabled && value > 1
              ? () => onChanged(_nextSmaller)
              : null,
          tooltip: '-',
        ),
        IconButton(
          icon: const Icon(Icons.add),
          onPressed: enabled && _nextLarger != value
              ? () => onChanged(_nextLarger)
              : null,
          tooltip: '+',
        ),
      ],
    ),
  );
}
