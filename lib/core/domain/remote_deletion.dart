// 远端破坏性删除的**应用**规则（T045；架构 5.2「未批准不自动清除本地内容，保留待处理
// 冲突」、4.1「删除订阅」段与 5.3 清理规则）。
//
// T043 只把远端提出的删除**登记**成 pendingRemoteDeletions（合并结果里也不含那条实体，
// 因此本机不会用一次上传推翻远端的删除）。本文件补上另一半：当用户看过影响范围并确认之后，
// 「按 T018 的规则真的删掉本机数据」这件事应当由一套**纯规则**描述，而不是散在界面代码里。
//
// 三条刻意的设计：
//
//   1) **登记 ≠ 应用**。这里没有任何「先删了再说」的路径：没有确认就没有
//      [RemoteDeletionApplication]。界面拿到的数据形状也只有「影响范围」与「一次应用的结果」，
//      因此「未确认不清数据」是结构性的，而不是靠调用方记得别提前调用。
//   2) **保留收藏的选择随删除事实传播**。远端删除时选了哪一档（SyncDeletion.keepFavorites）
//      是本机展示影响范围与设置默认勾选状态的依据；本机确认时又要把**本机这次的选择**写回
//      操作元数据（deletion_events 的 keepFavorites），别的设备才不必按自己的默认值猜测。
//   3) **不认识的目标不被猜着删**。远端送来一条本机无法解析的删除（未知类别、或本机没有
//      对应的订阅/分组）时，影响范围如实标成「不可应用」。猜一个目标去删是不可撤销的错误，
//      而它的表现是「另一条订阅消失了」。
library;

import 'feed_deletion.dart';
import '../result.dart';

import 'sync_projection.dart';
import 'sync_snapshot.dart';
import 'sync_store.dart';

/// 一条远端删除对应的本机目标类别。
enum RemoteDeletionTarget {
  /// 订阅（按 syncId 对齐到本机 feed）。
  feed,

  /// 分组（按 syncId 对齐到本机 group）。
  group,

  /// 本机不认识这条删除（未知类别，或本机没有对应实体）。
  unsupported,
}

/// 由快照里的实体类别判断删除目标。
RemoteDeletionTarget remoteDeletionTargetOf(String entityKind) =>
    switch (entityKind) {
      SyncEntityKind.feed => RemoteDeletionTarget.feed,
      SyncEntityKind.group => RemoteDeletionTarget.group,
      _ => RemoteDeletionTarget.unsupported,
    };

/// 一条远端删除在本机的**影响范围**（用户确认前必须看到的数字）。
///
/// 为什么复用 T018 的 [FeedDeletionPreview] 而不是另算一套数字：单源删除与远端删除在
/// 用户眼里是同一件事（「这个源要没了，我会失去什么」），两套实现迟早会在 later 这一类上
/// 分歧，而那时用户会看到两个互相矛盾的数字。
final class RemoteDeletionImpact {
  /// 构造影响范围。
  const RemoteDeletionImpact({
    required this.deletion,
    required this.target,
    required this.displayName,
    required this.favoriteCount,
    required this.otherCount,
    required this.laterCount,
    this.localTargetId,
    this.blockedReason,
  });

  /// 本机不认识这条删除：影响范围不可计算，**不可应用**。
  ///
  /// [reason] 是稳定的英文类别名（进诊断与状态，不进界面文案）。
  factory RemoteDeletionImpact.unsupported({
    required SyncDeletion deletion,
    required String reason,
  }) => RemoteDeletionImpact(
    deletion: deletion,
    target: RemoteDeletionTarget.unsupported,
    displayName: deletion.displayName ?? deletion.key,
    favoriteCount: 0,
    otherCount: 0,
    laterCount: 0,
    blockedReason: reason,
  );

  /// 由单源删除预览构造（订阅删除）。
  factory RemoteDeletionImpact.forFeed({
    required SyncDeletion deletion,
    required FeedDeletionPreview preview,
  }) => RemoteDeletionImpact(
    deletion: deletion,
    target: RemoteDeletionTarget.feed,
    displayName: preview.feedName,
    localTargetId: preview.feedId,
    favoriteCount: preview.favoriteCount,
    otherCount: preview.otherCount,
    laterCount: preview.laterCount,
  );

  /// 由分组删除预览构造（分组内的订阅按同一套规则处理）。
  factory RemoteDeletionImpact.forGroup({
    required SyncDeletion deletion,
    required GroupDeletionPreview preview,
  }) => RemoteDeletionImpact(
    deletion: deletion,
    target: RemoteDeletionTarget.group,
    displayName: preview.groupName,
    localTargetId: preview.groupId,
    favoriteCount: preview.favoriteCount,
    otherCount: preview.otherCount,
    laterCount: preview.laterCount,
  );

  /// 远端提出的那条删除事实（含它带来的 keepFavorites 操作元数据）。
  final SyncDeletion deletion;

  /// 目标类别。
  final RemoteDeletionTarget target;

  /// 显示名（订阅名/分组名；不可解析时退回远端给的显示名或键）。
  final String displayName;

  /// 本机目标 id（订阅 id 或分组 id）；不可解析时为 null。
  final int? localTargetId;

  /// 收藏文章数（勾选「保留收藏」时会保留并脱离源）。
  final int favoriteCount;

  /// 其余文章数（**含 later**），无论勾选与否都会被清理。
  final int otherCount;

  /// 其余文章中处于 later 的数量。
  final int laterCount;

  /// 不可应用的原因（稳定类别名）；可应用时为 null。
  final String? blockedReason;

  /// 该源下的文章总数。
  int get totalCount => favoriteCount + otherCount;

  /// 是否可应用（本机认出了目标，且算出了影响范围）。
  bool get applicable =>
      target != RemoteDeletionTarget.unsupported && blockedReason == null;

  /// 远端删除时选择保留收藏；null 表示远端没有报告这个选择。
  bool? get remoteKeepFavorites => deletion.keepFavorites;

  /// 确认对话框的默认勾选状态（SET-081：默认选保留）。
  ///
  /// 远端报告过选择时沿用**远端当时的选择**：那是做这次删除的人明确做过的决定，
  /// 用一个本机默认值覆盖它会让「远端说有 3 篇收藏留下」与「本机删完只剩 0 篇」对不上。
  bool get defaultKeepFavorites => deletion.keepFavorites ?? true;

  /// 保留收藏是否有意义（没有收藏时界面不必强调这个选项，但仍要显示）。
  bool get keepFavoritesIsMeaningful => favoriteCount > 0;
}

/// 一次远端删除的应用结果。
final class RemoteDeletionApplication {
  /// 构造结果。
  const RemoteDeletionApplication({
    required this.deletion,
    required this.target,
    required this.displayName,
    required this.keepFavorites,
    required this.deletedArticles,
    required this.keptFavorites,
  });

  /// 被应用的那条删除事实。
  final SyncDeletion deletion;

  /// 目标类别。
  final RemoteDeletionTarget target;

  /// 目标显示名（快照）。
  final String displayName;

  /// 本机这次选择的是否保留收藏。
  final bool keepFavorites;

  /// 实际清理掉的文章数。
  final int deletedArticles;

  /// 保留下来的收藏数（已脱离源）。
  final int keptFavorites;
}

/// 判定一条墓碑是否让某个订阅**跳过抓取**（T045「已删除条目不复活」的调度侧）。
///
/// 为什么抓取也要看墓碑：删除是长期事实（架构 5.2「首发不自动清除」），而「源还在
/// 远端、本机已删」这件事意味着**下一次刷新会把整条订阅连文章一起重新拉回来**。
/// 只靠同步层的墓碑优先挡不住它——刷新的入口根本不经过合并。
bool isFeedTombstoned({
  required String feedSyncId,
  required Iterable<SyncTombstone> tombstones,
}) {
  for (final SyncTombstone tombstone in tombstones) {
    if (tombstone.entityKind == SyncEntityKind.feed &&
        tombstone.entityKey == feedSyncId) {
      return true;
    }
  }
  return false;
}

/// 该订阅是否应当因墓碑而跳过刷新。
///
/// 与 [isFeedTombstoned] 分开是为了让「查墓碑失败」与「查到了墓碑」在调用方**可分辨**：
/// 查询失败时按「没有墓碑」放行（刷新是只读的，放行不会造成数据损失），而不是静默跳过
/// 用户的全部刷新。
bool shouldSkipRefreshForTombstone({
  required String feedSyncId,
  required Iterable<SyncTombstone> tombstones,
}) => isFeedTombstoned(feedSyncId: feedSyncId, tombstones: tombstones);

/// 订阅墓碑的只读端口（T045 的「已删除条目不复活」在**刷新**侧的判据）。
///
/// 为什么是一个独立窄端口而不是让刷新直接读同步端口：刷新只回答「这个源被删过吗」，而
/// 同步端口还带着基线、待同步变更与占位行写入。收窄之后调度层在类型上就无法顺手写同步
/// 状态，两者的唯一交点是这一条只读查询；同步端口将来增删方法也不会波及刷新路径。
abstract interface class FeedTombstoneReader {
  /// 读全部订阅墓碑的 syncId 集合。
  ///
  /// 返回集合而不是 `bool isDeleted(syncId)`：一次刷新要为此前过滤**全部**候选源，逐源
  /// 查询会把 N 次数据库往返叠在派发之前，而它本来只是一次全表扫描。
  Future<Result<Set<String>>> readFeedTombstoneSyncIds();
}

/// 不提供墓碑信息的实现（默认装配与降级启动）。
///
/// 返回**空集合**而不是失败：刷新是只读的后台行为，一个漏接线的墓碑端口应当退化成「照常
/// 刷新」，而不是让用户的全部刷新因为一个与刷新无关的接线疏忽而停摆。这与「查到墓碑」在
/// 数据上可分辨——前者什么都不写，后者会跳过并如实记进报告。
final class NoopFeedTombstoneReader implements FeedTombstoneReader {
  /// 构造空实现。
  const NoopFeedTombstoneReader();

  @override
  Future<Result<Set<String>>> readFeedTombstoneSyncIds() async =>
      const Ok<Set<String>>(<String>{});
}
