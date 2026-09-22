// 同步初始状态的**本机**读取结果（T044；设置页与冲突页的数据来源）。
//
// 为什么单独一个类型而不是直接给界面一个 [SyncStatusSnapshot]：那个快照里的冲突列表与首次
// 合并预览是**一次合并的结论**，本机存储里没有它们（冲突不是持久数据——它是「两份内容在
// 同一个字段上都被改过」这个当时的事实）。存储层能诚实回答的只有基线、能力、上次成功与
// 待同步计数，因此它返回这个类型；界面状态由同步管理器在内存里补全。
library;

import 'webdav.dart';

/// 本机同步状态（存储层能诚实回答的那部分）。
final class SyncStatusBaseline {
  /// 构造状态。
  const SyncStatusBaseline({
    required this.capability,
    required this.pendingChangeCount,
    this.lastSyncedAt,
    this.baseVersion,
  });

  /// 服务器能力（三态：未探测 / 支持条件写 / 降级只读）。
  final WebDavWriteCapability capability;

  /// 待同步的本机变更数。
  final int pendingChangeCount;

  /// 上次成功同步的时刻（UTC）；从未成功为 null。
  final DateTime? lastSyncedAt;

  /// 共同基线版本；从未同步为 null。
  final String? baseVersion;

  /// 是否已经建立过共同基线（决定首次合并是否还需要预览）。
  bool get hasBaseline => baseVersion != null;
}
