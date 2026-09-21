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

// [GroupDeletionMode] 与 [GroupDeletionOutcome] 自 T018 起定义在
// lib/core/domain/feed_deletion.dart：删除的数据形状同时被用例层、存储层与界面引用，
// 而 features 不得 import infrastructure，因此它必须住在 core。这里不再重复声明，
// 避免出现两份形状接近的定义。

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
    bool keepFavorites = true,
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

    // 「移动到未分类」分支需要一个真实存在的目标组，因此**先确认它存在**再进存储
    // 层：缺失意味着库被破坏，此时应当立刻报错，而不是让事务跑一半再回滚。
    // （删除订阅的分支不需要目标组。）
    if (mode == GroupDeletionMode.moveToUncategorized) {
      final Result<GroupRecord> reserved = await _requireReservedGroup();
      if (reserved.isErr) {
        return Err<GroupDeletionOutcome>(reserved.errorOrNull!);
      }
    }

    // 两个分支都交给存储层在**同一个事务**内完成（架构第 8 节：不允许部分成功）。
    // 用例层不再自己「先移动、再删组」地拼两步：那两步之间失败会留下一个已经动过
    // 订阅、却没删掉分组的状态，而用户只看到「删除分组失败」。
    return catalog.deleteGroupWithFeeds(
      groupId: group.id,
      mode: mode,
      keepFavorites: keepFavorites,
    );
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
