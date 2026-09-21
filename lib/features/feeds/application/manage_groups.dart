// 分组管理用例（T014；架构 4.1 分组规则、SET-024 名称/排序/置顶、SET-025 展开折叠）。
//
// 本文件实现架构 4.1 对分组的四条要求：
//   - 创建、重命名、删除、拖动/菜单排序、置顶及展开；
//   - **未分类为保留组**：不可删除、不可改名（[ManageGroupsUseCase.rename] 直接拒绝，
//     不依赖界面禁用）；
//   - 删除分组时由用户选择「移动到未分类」或「删除其中订阅」，后者复用删除订阅的
//     收藏保留规则（属 T018；本期只实现「移动到未分类」分支，另一分支调用预留接口）；
//   - 置顶是独立布尔值，不靠负权重表达。
//
// 展开/折叠（SET-025）**不在这里**：它是本机展示状态（D 类），按架构 5.2 不同步，
// 也不属于「分组」这个同步实体。它由 presentation 层的本机记忆承担（见
// presentation/feed_group_collapse.dart），写进 device. 命名空间的键。
library;

import 'package:flux/core/core.dart';

/// 删除分组时对其订阅的处理方式（架构 4.1 的两种分支）。
enum GroupDeletionMode {
  /// 把订阅移动到保留组「未分类」（本期实现的唯一分支）。
  moveToUncategorized,

  /// 删除其中全部订阅。
  ///
  /// 本期**不真正删除**：它复用 T018 的「保留收藏」规则，因此这里调用订阅删除的
  /// 预留接口（[FeedCatalogStore.markFeedDeleted]）并在结果里如实报告「尚未删除」，
  /// 而不是静默当作已完成。
  deleteFeeds,
}

/// 一次分组删除的结果。
class GroupDeletionOutcome {
  /// 构造结果。
  const GroupDeletionOutcome({
    required this.mode,
    required this.movedFeedCount,
    required this.pendingFeedDeletionCount,
  });

  /// 实际采用的处理方式。
  final GroupDeletionMode mode;

  /// 被移动到未分类的订阅数。
  final int movedFeedCount;

  /// 因 T018 未实现而**尚未真正删除**的订阅数。
  ///
  /// 非零时界面必须明确说明（「保留收藏在 T018 生效」），否则用户会以为自己
  /// 已经删掉了那些订阅。
  final int pendingFeedDeletionCount;
}

/// 分组管理用例。
class ManageGroupsUseCase {
  /// 构造用例。
  const ManageGroupsUseCase({required this.catalog});

  /// 订阅/分组端口。
  final FeedCatalogStore catalog;

  /// 新建分组。
  ///
  /// 新组排在末尾：sortOrder 取现有最大值 + 1。取「+1」而不是「数量」，
  /// 是因为删除中间某个组后，数量会比最大权重小，于是新建的组会插到既有组中间，
  /// 与「按创建顺序」的口径不符。
  Future<Result<GroupRecord>> create({
    required String name,
    DateTime? now,
  }) async {
    if (!isValidGroupName(name)) {
      return Err<GroupRecord>(
        ValidationError(field: 'groupName', reason: '分组名称不能为空'),
      );
    }
    final Result<List<GroupRecord>> groups = await catalog.listGroups();
    if (groups.isErr) {
      return Err<GroupRecord>(groups.errorOrNull!);
    }
    final List<GroupRecord> existing = groups.valueOrNull!;
    final int nextOrder = existing.isEmpty
        ? 0
        : existing
                  .map((GroupRecord group) => group.sortOrder)
                  .reduce((int a, int b) => a > b ? a : b) +
              1;

    // syncId 由稳定标识生成器产出；它掺入时间与随机数，因此同一秒内连续建组
    // 也不会撞（sequence 参与材料，见 stable_id.dart）。
    final String syncId = newGroupSyncId(now: now, sequence: existing.length);
    return catalog.createGroup(
      syncId: syncId,
      name: name.trim(),
      sortOrder: nextOrder,
    );
  }

  /// 重命名分组。
  ///
  /// 保留组「未分类」**直接拒绝**改名。为什么不在界面上禁用输入框就够了：
  /// 名称是用户可见的稳定标识（界面按名称显示归属），而「未分类」是架构 4.1 的
  /// 术语；允许改名会让它退化成一个普通分组名，用户再建一个同名的组后两者无法
  /// 区分。用例层拒绝使这条规则不依赖界面实现。
  Future<Result<GroupRecord>> rename({
    required int groupId,
    required String name,
  }) async {
    if (!isValidGroupName(name)) {
      return Err<GroupRecord>(
        ValidationError(field: 'groupName', reason: '分组名称不能为空'),
      );
    }
    final Result<GroupRecord> loaded = await _requireGroup(groupId);
    if (loaded.isErr) {
      return Err<GroupRecord>(loaded.errorOrNull!);
    }
    final GroupRecord group = loaded.unwrap();
    if (isReservedGroup(group)) {
      return Err<GroupRecord>(
        ValidationError(field: 'groupId', reason: '「${group.name}」是保留分组，不能改名'),
      );
    }
    final Result<void> written = await catalog.renameGroup(
      groupId: group.id,
      name: name.trim(),
    );
    return written.isErr
        ? Err<GroupRecord>(written.errorOrNull!)
        : Ok<GroupRecord>(group.copyWith(name: name.trim()));
  }

  /// 置顶/取消置顶。
  ///
  /// 保留组**允许**置顶：架构 4.1 只把「删除」与「改名」列为保留组的限制，
  /// 置顶是纯展示偏好；禁止它会让用户无法把「未分类」固定在最上方，而那是最常用的
  /// 用法。置顶用独立布尔列而不是负权重（架构 4.1 明写），因此取消置顶能回到
  /// 原来的相对位置。
  Future<Result<GroupRecord>> setPinned({
    required int groupId,
    required bool pinned,
  }) async {
    final Result<GroupRecord> loaded = await _requireGroup(groupId);
    if (loaded.isErr) {
      return Err<GroupRecord>(loaded.errorOrNull!);
    }
    final GroupRecord group = loaded.unwrap();
    final Result<void> written = await catalog.setGroupPinned(
      groupId: group.id,
      pinned: pinned,
    );
    return written.isErr
        ? Err<GroupRecord>(written.errorOrNull!)
        : Ok<GroupRecord>(group.copyWith(pinned: pinned));
  }

  /// 整段重排分组（拖动或菜单排序的结果）。
  ///
  /// [orderedIds] 必须是**当前全部分组**的 id 集合（顺序即目标顺序）。不允许只给
  /// 一部分：局部重排会产生重复权重，而重复权重下「看起来保存了」的顺序会在下次
  /// 读取时变样（[sortGroupsForDisplay] 的兜底比较虽然能稳定输出，但那不是用户
  /// 拖出来的顺序）。
  Future<Result<List<GroupRecord>>> reorder(List<int> orderedIds) async {
    final Result<List<GroupRecord>> groups = await catalog.listGroups();
    if (groups.isErr) {
      return Err<List<GroupRecord>>(groups.errorOrNull!);
    }
    final List<GroupRecord> current = groups.valueOrNull!;
    final Set<int> currentIds = current
        .map((GroupRecord group) => group.id)
        .toSet();
    if (orderedIds.length != currentIds.length ||
        !orderedIds.toSet().containsAll(currentIds)) {
      return Err<List<GroupRecord>>(
        ValidationError(
          field: 'groupOrder',
          reason:
              '排序必须包含全部分组（当前 ${currentIds.length} 个，'
              '收到 ${orderedIds.length} 个）',
        ),
      );
    }
    final Result<void> written = await catalog.reorderGroups(orderedIds);
    if (written.isErr) {
      return Err<List<GroupRecord>>(written.errorOrNull!);
    }
    final Map<int, int> order = <int, int>{
      for (int index = 0; index < orderedIds.length; index++)
        orderedIds[index]: index,
    };
    return Ok<List<GroupRecord>>(
      current
          .map(
            (GroupRecord group) =>
                group.copyWith(sortOrder: order[group.id] ?? group.sortOrder),
          )
          .toList(growable: false),
    );
  }

  /// 删除分组。
  ///
  /// 保留组「未分类」不可删除：它是**唯一**保证「订阅总有归属」的组，也是删除其他
  /// 分组时「移动到未分类」分支的目标。删掉它会让那条分支无处可去。
  Future<Result<GroupDeletionOutcome>> delete(
    int groupId, {
    GroupDeletionMode mode = GroupDeletionMode.moveToUncategorized,
  }) async {
    final Result<GroupRecord> loaded = await _requireGroup(groupId);
    if (loaded.isErr) {
      return Err<GroupDeletionOutcome>(loaded.errorOrNull!);
    }
    final GroupRecord group = loaded.unwrap();
    if (isReservedGroup(group)) {
      return Err<GroupDeletionOutcome>(
        ValidationError(field: 'groupId', reason: '「${group.name}」是保留分组，不能删除'),
      );
    }

    final Result<List<FeedRecord>> feeds = await catalog.listFeeds();
    if (feeds.isErr) {
      return Err<GroupDeletionOutcome>(feeds.errorOrNull!);
    }
    final List<FeedRecord> members = feeds.valueOrNull!
        .where((FeedRecord feed) => feed.groupId == group.id)
        .toList(growable: false);

    switch (mode) {
      case GroupDeletionMode.moveToUncategorized:
        final Result<GroupRecord> reserved = await _requireReservedGroup();
        if (reserved.isErr) {
          return Err<GroupDeletionOutcome>(reserved.errorOrNull!);
        }
        if (members.isNotEmpty) {
          final Result<int> moved = await catalog.moveAllFeedsToGroup(
            fromGroupId: group.id,
            targetGroupId: reserved.unwrap().id,
          );
          if (moved.isErr) {
            return Err<GroupDeletionOutcome>(moved.errorOrNull!);
          }
        }
        // 先移动订阅、再删除分组行：反过来的话，外键仍指向已删分组的那一瞬是
        // 一个**已经违反**「订阅必须有归属」的中间状态。
        final Result<void> removed = await catalog.deleteGroup(group.id);
        if (removed.isErr) {
          return Err<GroupDeletionOutcome>(removed.errorOrNull!);
        }
        return Ok<GroupDeletionOutcome>(
          GroupDeletionOutcome(
            mode: mode,
            movedFeedCount: members.length,
            pendingFeedDeletionCount: 0,
          ),
        );

      case GroupDeletionMode.deleteFeeds:
        // 本期**不删除**：按架构 4.1 与 D-11，「删除订阅」必须先让用户看见影响
        // 范围（收藏 vs 其他、含 later）并选择是否保留收藏。因此这里逐个调用预留
        // 接口把它们标记为「待 T018 处理」，并**保留分组与订阅本身**——一个此刻
        // 就真删数据、却声称遵守保留规则的实现，比不实现更糟。
        for (final FeedRecord feed in members) {
          final Result<void> marked = await catalog.markFeedDeleted(feed.id);
          if (marked.isErr) {
            return Err<GroupDeletionOutcome>(marked.errorOrNull!);
          }
        }
        return Ok<GroupDeletionOutcome>(
          GroupDeletionOutcome(
            mode: mode,
            movedFeedCount: 0,
            pendingFeedDeletionCount: members.length,
          ),
        );
    }
  }

  /// 读取一个必须存在的分组。
  Future<Result<GroupRecord>> _requireGroup(int groupId) async {
    final Result<List<GroupRecord>> groups = await catalog.listGroups();
    if (groups.isErr) {
      return Err<GroupRecord>(groups.errorOrNull!);
    }
    for (final GroupRecord group in groups.valueOrNull!) {
      if (group.id == groupId) {
        return Ok<GroupRecord>(group);
      }
    }
    return Err<GroupRecord>(
      StorageError(
        operation: 'manageGroups',
        detail: 'group $groupId 不存在',
        isMissing: true,
      ),
    );
  }

  /// 读取保留组「未分类」。
  ///
  /// 按固定 syncId 定位（不按名称、也不取「第一个组」）：名称可以被用户改，而
  /// syncId 是建库种子写入的稳定标识。找不到时**报错而不是新建**：缺失意味着库
  /// 被破坏，静默补一个会让「保留组」的语义不可信。
  Future<Result<GroupRecord>> _requireReservedGroup() async {
    final Result<GroupRecord?> found = await catalog.findGroupBySyncId(
      groupUncategorizedSyncId,
    );
    if (found.isErr) {
      return Err<GroupRecord>(found.errorOrNull!);
    }
    if (found.valueOrNull == null) {
      return Err<GroupRecord>(
        StorageError(
          operation: 'manageGroups',
          detail: '保留组「未分类」不存在',
          isMissing: true,
        ),
      );
    }
    return Ok<GroupRecord>(found.valueOrNull!);
  }
}
