// 分组的保留规则与展示顺序（T014；架构 4.1「未分类为保留组」与 SET-024/025）。
//
// 为什么这些必须是**可执行规则**而不是散落在页面里：
//   - 「未分类不可删、不可改名」是架构 4.1 的硬约束，而它的实现位置在删除/改名
//     两条路径上各一处；写两次就迟早只改一处，出现「界面禁用但用例仍允许」的漏洞；
//   - 置顶组在前、组内按 sortOrder、同权重按稳定次序——这条决定**列表看起来是否
//     稳定**。若把「同权重的顺序」交给 SQLite 的返回次序，同一份数据两次查询可能
//     给出不同顺序，用户会以为拖动没保存。
//
// 本文件是纯函数与常量，不依赖 Flutter/drift，可被用例、存储适配器与测试共用。
library;

import 'feed_catalog.dart';

/// 保留组「未分类」的稳定标识（架构 4.1）。
///
/// 用固定 syncId 而不是固定自增 id：自增 id 在跨设备、导入导出后都不保证一致，
/// 而「未分类」必须能在任何库里被稳定识别。数据库建库种子用同一个常量（见
/// lib/infrastructure/local/database.dart），避免两处各写一份字符串。
const String groupUncategorizedSyncId = 'group.uncategorized';

/// 保留组的默认显示名（首次建库的种子文案；用户改名后以用户的为准）。
const String groupUncategorizedDefaultName = '未分类';

/// 一个分组是否为保留组。
///
/// 同时看 [GroupRecord.isReserved] 与固定 syncId：前者是落库的事实，后者是常量
/// 兜底。只认其中一条会有风险——落库列可能因为旧版本迁移或手工改库而缺失，
/// 而允许删除「未分类」会直接破坏「订阅必须有归属」这条不变量。
bool isReservedGroup(GroupRecord group) =>
    group.isReserved || group.syncId == groupUncategorizedSyncId;

/// 分组名是否合法（非空、去空白后非空、不含换行）。
///
/// 只做「能落库、能显示」的最低校验，不限制长度以外的风格：分组名由用户决定，
/// 我们只拒绝那些会让列表排版崩坏或让键名歧义的输入。
bool isValidGroupName(String name) {
  final String trimmed = name.trim();
  return trimmed.isNotEmpty && !trimmed.contains(RegExp(r'[\r\n]'));
}

/// 订阅显示名是否合法。空名不允许：列表里一行空白无法辨认，也没法搜索。
bool isValidFeedName(String name) => name.trim().isNotEmpty;

/// 按展示顺序排列分组：置顶在前，其次 sortOrder，最后按名称与 id 保证稳定。
///
/// 「置顶是独立布尔值，不靠负权重表达」（架构 4.1）：因此这里先按 pinned 分组，
/// 而不是把所有置顶组的 sortOrder 改成负数——后者会让「取消置顶」无法恢复原来的
/// 位置。
List<GroupRecord> sortGroupsForDisplay(Iterable<GroupRecord> groups) {
  final List<GroupRecord> sorted = groups.toList(growable: false);
  return List<GroupRecord>.of(sorted)..sort((GroupRecord a, GroupRecord b) {
    if (a.pinned != b.pinned) {
      return a.pinned ? -1 : 1;
    }
    final int byOrder = a.sortOrder.compareTo(b.sortOrder);
    if (byOrder != 0) {
      return byOrder;
    }
    final int byName = a.name.compareTo(b.name);
    return byName != 0 ? byName : a.id.compareTo(b.id);
  });
}

/// 按展示顺序排列某个分组内的订阅。
///
/// 加精**不参与**排序（架构 4.1：「加精显示加精标识与强调，但不影响排序之外的
/// 选材权重」；把加精订阅提到最前会让加精变成一种排序操作，与分组置顶混淆）。
List<FeedRecord> sortFeedsForDisplay(Iterable<FeedRecord> feeds) {
  final List<FeedRecord> sorted = feeds.toList(growable: false);
  return List<FeedRecord>.of(sorted)..sort((FeedRecord a, FeedRecord b) {
    final int byOrder = a.sortOrder.compareTo(b.sortOrder);
    if (byOrder != 0) {
      return byOrder;
    }
    final int byName = a.name.compareTo(b.name);
    return byName != 0 ? byName : a.id.compareTo(b.id);
  });
}

/// 把订阅按分组 id 归堆（null 键代表尚未归组，界面按保留组展示）。
Map<int?, List<FeedRecord>> groupFeedsByGroupId(Iterable<FeedRecord> feeds) {
  final Map<int?, List<FeedRecord>> grouped = <int?, List<FeedRecord>>{};
  for (final FeedRecord feed in feeds) {
    grouped.putIfAbsent(feed.groupId, () => <FeedRecord>[]).add(feed);
  }
  return grouped;
}
