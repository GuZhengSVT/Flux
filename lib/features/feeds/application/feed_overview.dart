// 订阅管理页的读模型（T014）。
//
// 为什么需要一个读模型而不是让页面自己查两次（分组 + 订阅 + 未读计数）：
//   - 「未归组的订阅按保留组展示」「置顶组在前」「组内按 sortOrder」这三条规则要
//     与写入侧（[sortGroupsForDisplay]）用的是**同一份**实现，否则界面显示的顺序
//     与拖动保存的顺序可能不一致；
//   - 页面拿到裸列表后自己拼装，会让「某条订阅的 groupId 指向一个刚被删掉的组」
//     这种数据状态在每个页面各表现一次。这里集中处理成一种表现（归入未分类并
//     记一条诊断），而不是让界面猜。
//
// 与用例的区别：这里没有写入，只有读与组织，因此也不叫 use case；但同样住在
// application 层，因为它需要 catalog 端口。
library;

import 'package:flux/core/core.dart';

/// 订阅管理页的一行订阅。
class FeedListEntry {
  /// 构造行。
  const FeedListEntry({required this.feed, required this.unreadCount});

  /// 订阅记录。
  final FeedRecord feed;

  /// 未读数。
  ///
  /// 未读计数来自文章表；本轮界面把它作为**占位信息**展示（T017 才交付文章列表），
  /// 但数值本身是真实统计，不是写死的 0：写死会让 T017 误以为链路已通。
  final int unreadCount;
}

/// 订阅管理页的一个分组区块。
class FeedGroupSection {
  /// 构造区块。
  const FeedGroupSection({
    required this.group,
    required this.entries,
    required this.isReserved,
    required this.orphanCount,
  });

  /// 分组记录；[group] 为 null 表示这是「未分类」的**兜底区块**（库里没有保留组，
  /// 或订阅未归组）——此时界面仍需一个可展示的归属，不能把这些订阅丢掉。
  final GroupRecord? group;

  /// 组内订阅（已按展示顺序排列）。
  final List<FeedListEntry> entries;

  /// 是否为保留组（不可删、不可改名）。
  final bool isReserved;

  /// 因 groupId 指向不存在的分组而被归入本区块的订阅数（诊断用）。
  final int orphanCount;

  /// 展示用名称。
  String get displayName => group?.name ?? groupUncategorizedDefaultName;

  /// 分组本机 id；兜底区块为 null。
  int? get groupId => group?.id;
}

/// 一次读操作的结果。
class FeedOverview {
  /// 构造读模型。
  const FeedOverview({required this.sections, required this.totalFeeds});

  /// 分组区块（已按置顶 + sortOrder 排序）。
  final List<FeedGroupSection> sections;

  /// 订阅总数（含孤儿）。
  final int totalFeeds;

  /// 是否还没有任何订阅。
  bool get isEmpty => totalFeeds == 0;
}

/// 订阅管理页读模型。
class FeedOverviewReader {
  /// 构造读模型。
  const FeedOverviewReader({
    required this.catalog,
    this.diagnostics = const NoopDiagnosticSink(),
  });

  /// 订阅读写端口。
  final FeedCatalogStore catalog;

  /// 诊断记录。
  final DiagnosticSink diagnostics;

  /// 读取并组织订阅管理页的全部数据。
  Future<Result<FeedOverview>> read() async {
    final Result<List<GroupRecord>> groups = await catalog.listGroups();
    if (groups.isErr) {
      return Err<FeedOverview>(groups.errorOrNull!);
    }
    final Result<List<FeedRecord>> feeds = await catalog.listFeeds();
    if (feeds.isErr) {
      return Err<FeedOverview>(feeds.errorOrNull!);
    }
    final Result<Map<int, int>> unread = await catalog.unreadCounts();
    if (unread.isErr) {
      return Err<FeedOverview>(unread.errorOrNull!);
    }
    return Ok<FeedOverview>(
      buildOverview(
        groups: groups.valueOrNull!,
        feeds: feeds.valueOrNull!,
        unreadCounts: unread.valueOrNull!,
        diagnostics: diagnostics,
      ),
    );
  }

  /// 纯函数形式的组织逻辑（测试与界面可脱离端口直接验证）。
  static FeedOverview buildOverview({
    required List<GroupRecord> groups,
    required List<FeedRecord> feeds,
    required Map<int, int> unreadCounts,
    DiagnosticSink diagnostics = const NoopDiagnosticSink(),
  }) {
    final List<GroupRecord> sortedGroups = sortGroupsForDisplay(groups);
    final Set<int> knownGroupIds = groups
        .map((GroupRecord group) => group.id)
        .toSet();

    // ---- 订阅按分组归堆，并统计「指向不存在分组」的孤儿 ------------------------
    // 孤儿在这里**不丢弃**：安静地少显示几条订阅是用户最难发现的一类错误。它们
    // 归入未分类区块（有归属的展示），同时记一条计数型诊断供排查。
    final Map<int, List<FeedRecord>> byGroup = <int, List<FeedRecord>>{};
    final List<FeedRecord> orphans = <FeedRecord>[];
    for (final FeedRecord feed in feeds) {
      final int? groupId = feed.groupId;
      if (groupId == null) {
        orphans.add(feed);
        continue;
      }
      if (!knownGroupIds.contains(groupId)) {
        orphans.add(feed);
        continue;
      }
      byGroup.putIfAbsent(groupId, () => <FeedRecord>[]).add(feed);
    }
    if (orphans.isNotEmpty) {
      final int dangling = orphans
          .where((FeedRecord feed) => feed.groupId != null)
          .length;
      if (dangling > 0) {
        diagnostics.warning(
          '有 $dangling 条订阅的分组已不存在，已按未分类展示',
          tag: 'feed.overview',
        );
      }
    }

    FeedListEntry entryOf(FeedRecord feed) =>
        FeedListEntry(feed: feed, unreadCount: unreadCounts[feed.id] ?? 0);

    final List<FeedGroupSection> sections = <FeedGroupSection>[];
    for (final GroupRecord group in sortedGroups) {
      final List<FeedListEntry> entries = sortFeedsForDisplay(
        byGroup[group.id] ?? const <FeedRecord>[],
      ).map(entryOf).toList(growable: false);
      sections.add(
        FeedGroupSection(
          group: group,
          entries: entries,
          isReserved: isReservedGroup(group),
          orphanCount: 0,
        ),
      );
    }

    // ---- 未归组 / 孤儿订阅：挂到「未分类」区块 ---------------------------------
    if (orphans.isNotEmpty) {
      final List<FeedListEntry> orphanEntries = sortFeedsForDisplay(orphans)
          .map(entryOf)
          .toList(growable: false);
      final int index = sections.indexWhere(
        (FeedGroupSection section) => section.isReserved,
      );
      if (index >= 0) {
        final FeedGroupSection reserved = sections[index];
        sections[index] = FeedGroupSection(
          group: reserved.group,
          entries: <FeedListEntry>[...reserved.entries, ...orphanEntries],
          isReserved: true,
          orphanCount: orphans.length,
        );
      } else {
        // 库里没有保留组（被破坏或被旧数据影响）：仍然给出一个可展示的兜底区块，
        // 但 [FeedGroupSection.group] 为 null，界面据此禁用「改名/删除」。
        sections.add(
          FeedGroupSection(
            group: null,
            entries: orphanEntries,
            isReserved: true,
            orphanCount: orphans.length,
          ),
        );
      }
    }

    return FeedOverview(sections: sections, totalFeeds: feeds.length);
  }
}
