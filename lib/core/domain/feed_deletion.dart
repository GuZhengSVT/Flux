// 删除订阅/分组的规则与结果类型（T018；架构 4.1「删除订阅」段、5.3 清理规则）。
//
// 放在 core 而不是 features：删除的**数据形状**（影响预览、删除结果、墓碑事件）同时被
// 用例层、存储层与界面引用，而 features 不得 import infrastructure。与
// article_catalog.dart 同一条理由。
//
// 为什么把「保留收藏」做成显式参数而不是读设置：SET-081 的默认值是「每次询问、默认选
// 保留」，也就是**每次都由用户当次决定**。若删除路径自己去读一个设置，用户勾掉复选框
// 的意图就会被一个更早写入的偏好覆盖——那是一类很难察觉的错误删除。设置只影响对话框的
// 初始勾选状态（界面层），不参与本文件的判定。
library;

/// 删除分组时对其订阅的处理方式（架构 4.1）。
enum GroupDeletionMode {
  /// 把订阅移动到保留组「未分类」：订阅与文章都保留，只改归属。
  moveToUncategorized,

  /// 删除其中全部订阅：复用删除订阅的「保留收藏」规则。
  deleteFeeds,
}

/// 一次删除订阅的**影响预览**（架构 4.1、D-11：清理范围必须在操作前可见）。
///
/// 三个数字分开给出而不是只给一个总数：用户要回答的是「要不要保留收藏」，因此他
/// 必须同时看到「保留会留下几篇」「其余有多少会被清掉」，以及 later 是否在其中。
/// 架构明确写了「所有非收藏文章（**包括 later**）清理」——把 later 藏进总数里，
/// 用户就无从判断自己那些「稍后再读」会不会一起消失。
class FeedDeletionPreview {
  /// 构造预览。
  const FeedDeletionPreview({
    required this.feedId,
    required this.feedSyncId,
    required this.feedName,
    required this.favoriteCount,
    required this.otherCount,
    required this.laterCount,
  });

  /// 订阅本机 id。
  final int feedId;

  /// 订阅跨设备稳定标识（墓碑事件用它）。
  final String feedSyncId;

  /// 订阅显示名（快照与提示文案用）。
  final String feedName;

  /// 收藏文章数（勾选「保留收藏」时会被保留并脱离源）。
  final int favoriteCount;

  /// 其余文章数：**含 later**，无论勾选与否都会被清理。
  final int otherCount;

  /// 其余文章中处于 later 的数量（单独给出，因为它是「非收藏但用户明确标记过」的一类）。
  final int laterCount;

  /// 该源下的文章总数。
  int get totalCount => favoriteCount + otherCount;

  /// 删除后（保留收藏分支）最终留下的文章数。
  int get keptWhenPreservingFavorites => favoriteCount;

  /// 删除后（不保留分支）最终留下的文章数。
  int get keptWhenDeletingAll => 0;

  /// 该源是否根本没有文章（界面据此说明「这个源没有文章」而不是显示一堆 0）。
  bool get hasNoArticles => totalCount == 0;
}

/// 一次删除订阅的结果（架构 4.1 的两个分支）。
class FeedDeletionOutcome {
  /// 构造结果。
  const FeedDeletionOutcome({
    required this.feedId,
    required this.feedSyncId,
    required this.feedName,
    required this.keepFavorites,
    required this.deletedArticles,
    required this.keptFavorites,
  });

  /// 订阅本机 id（已不存在，仅用于日志与界面回执）。
  final int feedId;

  /// 订阅跨设备稳定标识。
  final String feedSyncId;

  /// 订阅显示名（快照）。
  final String feedName;

  /// 本次是否选择了「保留收藏」。
  final bool keepFavorites;

  /// 实际被清理的文章数。
  final int deletedArticles;

  /// 保留下来的收藏数（已脱离源）。
  final int keptFavorites;
}

/// 一次删除分组的结果。
class GroupDeletionOutcome {
  /// 构造结果。
  const GroupDeletionOutcome({
    required this.mode,
    required this.movedFeedCount,
    required this.deletedFeedCount,
    required this.deletedArticles,
    required this.keptFavorites,
  });

  /// 实际采用的处理方式。
  final GroupDeletionMode mode;

  /// 被移动到未分类的订阅数（[GroupDeletionMode.moveToUncategorized] 分支）。
  final int movedFeedCount;

  /// 被真正删除的订阅数（[GroupDeletionMode.deleteFeeds] 分支）。
  final int deletedFeedCount;

  /// 被清理的文章数（两个分支都为 0，除非删除了订阅）。
  final int deletedArticles;

  /// 保留下来的收藏数（脱离源）。
  final int keptFavorites;
}

/// 一次**分组**删除的影响预览。
///
/// 为什么不复用 [FeedDeletionPreview]：那个类型带 feedId / feedSyncId，是**一条订阅**
/// 的身份；分组不是订阅，把组 id 塞进 feedId 会让两年后的读者（与同步代码）分不清
/// 「这个 id 到底指哪张表」。数字部分语义相同，但身份部分必须各归各。
class GroupDeletionPreview {
  /// 构造预览。
  const GroupDeletionPreview({
    required this.groupId,
    required this.groupName,
    required this.feedCount,
    required this.favoriteCount,
    required this.otherCount,
    required this.laterCount,
  });

  /// 分组本机 id。
  final int groupId;

  /// 分组显示名。
  final String groupName;

  /// 组内订阅数。
  final int feedCount;

  /// 组内全部订阅的收藏文章数（保留分支下会留下并脱离源）。
  final int favoriteCount;

  /// 组内全部订阅的其余文章数（**含 later**）。
  final int otherCount;

  /// 其余文章中处于 later 的数量。
  final int laterCount;

  /// 该分组下文章总数。
  int get totalCount => favoriteCount + otherCount;
}

/// 判定「保留收藏」是否真的会留下东西。
///
/// 界面对一个没有任何收藏的源不必强调这个选项，但**仍然要显示**它并给出一致的含义：
/// 藏起来会让用户怀疑选项本身是否可靠（「上次有的，这次怎么没有」）。因此这个函数只
/// 用来选择文案，不用来决定是否跳过确认。
bool keepFavoritesIsMeaningful(int favoriteCount) => favoriteCount > 0;
