// 同步结果的文案映射与值渲染（T044）。
//
// 为什么把映射抽成独立文件：设置页、冲突卡片与用例都要回答同一个问题——「这次同步到底
// 怎么样了」。三处各写一套 switch 会让「新增一种结论」在某一处漏掉，而症状是界面显示
// 上一次的结论（看起来像成功）。
//
// 两条渲染纪律：
//   * **缺失与 null 不同**：字段在本机或远端「没有值」用「（无）」表示，值为 null 用「—」。
//     合成同一个符号会让「对端没报告这个字段」与「对端把它清空了」在界面上不可分辨，
//     而这两者的语义完全不同（见 three_way_merge 的说明）。
//   * **只渲染，不解释**：这里不拼「建议怎么做」这类话（那是 l10n 的职责），只把结构化的
//     值变成可读文本。
library;

import 'package:flux/core/core.dart';
import 'package:flux/l10n/l10n.dart';

import '../application/sync_engine.dart';

/// 把一次同步的结论翻译成一句可读的话。
String describeSyncRun(SyncRunResult result, AppLocalizations l10n) =>
    switch (result.status) {
      SyncRunStatus.succeeded =>
        result.recoveredWithoutUpload
            ? l10n.syncResultAlreadyPublished
            : l10n.syncResultSucceeded(result.appliedCount),
      SyncRunStatus.waitingConflictChoice => l10n.syncResultConflicts(
        result.conflicts.length,
      ),
      SyncRunStatus.waitingRetry => l10n.syncResultRetry,
      SyncRunStatus.readonlyPull => l10n.syncResultReadonly,
      SyncRunStatus.failed => l10n.syncResultFailed(result.reason ?? 'unknown'),
    };

/// 渲染一个冲突候选值。
///
/// 「字段缺失」（[syncFieldAbsent]）与「值为 null」刻意用两个不同的符号：前者是**没有信息**，
/// 后者是**明确被清空**，它们在合并规则里的含义不同（见 three_way_merge 的文件说明）。
String describeSyncValue(Object? value) {
  if (identical(value, syncFieldAbsent)) {
    return '（无）';
  }
  if (value == null) {
    return '—';
  }
  return '$value';
}

/// 渲染一条冲突的定位信息（类别 · 键 · 字段）。
String describeConflictField(SyncMergeConflict conflict) =>
    '${conflict.kind} · ${conflict.key} · ${conflict.field}';

/// 渲染一条待确认的远端删除。
String describeRemoteDeletion(SyncDeletion deletion) {
  final String name = deletion.displayName ?? deletion.key;
  final String policy = switch (deletion.keepFavorites) {
    true => '（远端删除时选择保留收藏）',
    false => '（远端删除时未保留收藏）',
    null => '',
  };
  return '· $name$policy';
}

/// 渲染「上次同步」那一行（从未同步时给出一句明确的话，而不是空白）。
String describeLastSynced(DateTime? lastSyncedAt, AppLocalizations l10n) =>
    lastSyncedAt == null
    ? l10n.syncNeverSynced
    : l10n.syncLastSynced(lastSyncedAt.toLocal().toString());
