// 订阅与分组的读写端口（T014；架构 4.1 的分组/排序/置顶/加精与 SET-022–025）。
//
// 为什么端口与 DTO 放在 core 而不是 infrastructure（与 T013 的 feed_store_port.dart
// 同一条理由）：订阅管理用例住在 lib/features/feeds，它必须读写分组与订阅，而
// features 层不得 import infrastructure（test/core/architecture_layering_test.dart
// 会实际拦截）。把「接口 + 纯数据结构」放 core，infrastructure 实现它、features
// 消费它，双方都只依赖 core。
//
// 本文件不含任何 I/O 实现，也不依赖 Flutter 或 drift：drift 的实现住在
// lib/infrastructure/local/feed_catalog_adapter.dart。
library;

import '../result.dart';

import 'feed_fetch.dart';

/// 一个订阅分组（架构 5.1 的 Folder）。
class GroupRecord {
  /// 构造分组记录。
  const GroupRecord({
    required this.id,
    required this.syncId,
    required this.name,
    required this.sortOrder,
    required this.pinned,
    required this.isReserved,
  });

  /// 本机自增 id（不外传；同步用 [syncId]）。
  final int id;

  /// 跨设备稳定标识。
  final String syncId;

  /// 显示名称。
  final String name;

  /// 排序权重（越小越靠前）。
  final int sortOrder;

  /// 是否置顶（架构 4.1：置顶是分组属性，与订阅加精不同）。
  final bool pinned;

  /// 是否为保留组（「未分类」）：不可删除、不可改名。
  final bool isReserved;

  /// 复制并覆盖部分字段。
  GroupRecord copyWith({String? name, int? sortOrder, bool? pinned}) =>
      GroupRecord(
        id: id,
        syncId: syncId,
        name: name ?? this.name,
        sortOrder: sortOrder ?? this.sortOrder,
        pinned: pinned ?? this.pinned,
        isReserved: isReserved,
      );
}

/// 一个订阅源（架构 5.1 的 Feed）。
class FeedRecord {
  /// 构造订阅记录。
  const FeedRecord({
    required this.id,
    required this.syncId,
    required this.normalizedUrl,
    required this.name,
    required this.favorite,
    required this.enabled,
    required this.sortOrder,
    this.sourceName,
    this.groupId,
    this.refreshIntervalMinutes,
    this.lastCheckedAt,
    this.lastRefreshResult,
    this.lastRefreshErrorKind,
    this.httpEtag,
    this.httpLastModified,
  });

  /// 本机自增 id。
  final int id;

  /// 跨设备稳定标识（文章同步键用它构造，架构 5.2）。
  final String syncId;

  /// 规范化 URL（仅用于匹配与去重，不用于请求）。
  final String normalizedUrl;

  /// 显示名称（用户可改）。
  final String name;

  /// 源自带名称；未解析到时为 null。
  final String? sourceName;

  /// 所属分组；null 表示尚未归组（界面按保留组「未分类」展示）。
  final int? groupId;

  /// 加精（SET-023）：只影响显示，不影响新闻选材。
  final bool favorite;

  /// 是否参与自动刷新（SET-022）。
  final bool enabled;

  /// 刷新间隔覆盖（分钟）；null 表示继承全局（SET-020）。
  final int? refreshIntervalMinutes;

  /// 组内排序权重。
  final int sortOrder;

  /// 最后一次检查时间（UTC）；尚未检查为 null。
  final DateTime? lastCheckedAt;

  /// 最后一次抓取结果类别（Feeds.lastRefreshResult 的文本）。
  final String? lastRefreshResult;

  /// 最后一次失败类别。
  final String? lastRefreshErrorKind;

  /// 条件请求缓存：ETag（T016 的调度必须把它交给抓取层）。
  ///
  /// 为什么必须有这两个字段：架构 4.1 要求刷新使用条件请求。若调度只拿到
  /// normalizedUrl 而没有校验值，每次刷新都会退化成全量下载——「304 不更新任何
  /// 文章」那条规则就永远不可能在真实调度路径上发生，只在抓取层的测试里成立。
  final String? httpEtag;

  /// 条件请求缓存：Last-Modified 原文（HTTP 规范要求原样回送）。
  final String? httpLastModified;

  /// 该源本次可用的条件请求校验值。
  FeedCacheValidator get cacheValidator =>
      FeedCacheValidator(etag: httpEtag, lastModified: httpLastModified);

  /// 复制并覆盖部分字段。
  FeedRecord copyWith({
    String? name,
    String? sourceName,
    int? groupId,
    bool clearGroup = false,
    bool? favorite,
    bool? enabled,
    int? refreshIntervalMinutes,
    bool clearRefreshInterval = false,
    int? sortOrder,
  }) => FeedRecord(
    id: id,
    syncId: syncId,
    normalizedUrl: normalizedUrl,
    name: name ?? this.name,
    sourceName: sourceName ?? this.sourceName,
    groupId: clearGroup ? null : (groupId ?? this.groupId),
    favorite: favorite ?? this.favorite,
    enabled: enabled ?? this.enabled,
    refreshIntervalMinutes: clearRefreshInterval
        ? null
        : (refreshIntervalMinutes ?? this.refreshIntervalMinutes),
    sortOrder: sortOrder ?? this.sortOrder,
    lastCheckedAt: lastCheckedAt,
    lastRefreshResult: lastRefreshResult,
    lastRefreshErrorKind: lastRefreshErrorKind,
    httpEtag: httpEtag,
    httpLastModified: httpLastModified,
  );
}

/// 新建订阅所需的字段。
///
/// 刻意不含 [FeedRecord.id]（由数据库分配）与抓取诊断列（新源尚未抓取过，
/// 用「尚未检查」表达，而不是写一个当前时间假装检查过）。
class FeedInsert {
  /// 构造待插入订阅。
  const FeedInsert({
    required this.syncId,
    required this.normalizedUrl,
    required this.name,
    this.sourceName,
    this.groupId,
    this.sortOrder = 0,
  });

  /// 跨设备稳定标识。
  final String syncId;

  /// 规范化 URL。
  final String normalizedUrl;

  /// 显示名称。
  final String name;

  /// 源自带名称。
  final String? sourceName;

  /// 所属分组。
  final int? groupId;

  /// 组内排序权重。
  final int sortOrder;
}

/// 订阅与分组的读写端口。
///
/// 实现约定：
///   - 所有方法**不抛异常**（除编程错误），失败翻译为 [AppError]；
///   - [markFeedDeleted] 在 T014 是**保留接口**：当前实现不得删除任何订阅或文章
///     （「保留收藏 + 清理其余」的完整规则属 T018），它只记录一次待处理状态；
///   - 排序写入必须是**整段重排**（见 [reorderGroups] / [reorderFeedsInGroup]），
///     避免「只改一行 sortOrder」产生重复权重、拖动后顺序不稳定。
abstract interface class FeedCatalogStore {
  /// 读取全部分组。
  Future<Result<List<GroupRecord>>> listGroups();

  /// 读取全部订阅。
  Future<Result<List<FeedRecord>>> listFeeds();

  /// 每个订阅的未读数（键为 feed id）。
  ///
  /// 单独一个方法而不是塞进 [listFeeds]：未读数是文章表的聚合，与订阅行本身的
  /// 写入无关；分开后订阅管理以外的调用方（T017 的未读筛选）可以复用同一条查询。
  Future<Result<Map<int, int>>> unreadCounts();

  /// 按规范化 URL 查找订阅（OPML 往返与重复添加的匹配依据）。
  Future<Result<FeedRecord?>> findFeedByNormalizedUrl(String normalizedUrl);

  /// 按本机 id 查找订阅。
  Future<Result<FeedRecord?>> findFeedById(int feedId);

  /// 按 syncId 查找分组（保留组「未分类」按固定 syncId 定位）。
  Future<Result<GroupRecord?>> findGroupBySyncId(String syncId);

  /// 新建分组，返回落库后的记录（含数据库分配的 id）。
  Future<Result<GroupRecord>> createGroup({
    required String syncId,
    required String name,
    int sortOrder = 0,
  });

  /// 新建订阅，返回落库后的记录。
  Future<Result<FeedRecord>> createFeed(FeedInsert insert);

  /// 改分组名。
  Future<Result<void>> renameGroup({
    required int groupId,
    required String name,
  });

  /// 改分组置顶。
  Future<Result<void>> setGroupPinned({
    required int groupId,
    required bool pinned,
  });

  /// 删除分组行本身（其中订阅的归属由用例先处理，端口不做级联）。
  Future<Result<void>> deleteGroup(int groupId);

  /// 整段重排分组：按给定顺序写 sortOrder = 下标。
  Future<Result<void>> reorderGroups(List<int> groupIdsInOrder);

  /// 改订阅显示名。
  Future<Result<void>> renameFeed({required int feedId, required String name});

  /// 改订阅所属分组；[groupId] 为 null 表示取消归组（界面按未分类展示）。
  Future<Result<void>> moveFeedToGroup({required int feedId, int? groupId});

  /// 改订阅启用状态（SET-022：禁用后自动刷新跳过）。
  Future<Result<void>> setFeedEnabled({
    required int feedId,
    required bool enabled,
  });

  /// 改订阅加精（SET-023：只影响显示）。
  Future<Result<void>> setFeedFavorite({
    required int feedId,
    required bool favorite,
  });

  /// 改订阅刷新间隔覆盖；null 表示继承全局（SET-020）。
  Future<Result<void>> setFeedRefreshInterval({
    required int feedId,
    int? minutes,
  });

  /// 整段重排某个分组内的订阅：按给定顺序写 sortOrder = 下标。
  Future<Result<void>> reorderFeedsInGroup({
    required int groupId,
    required List<int> feedIdsInOrder,
  });

  /// 把某分组的全部订阅改挂到 [targetGroupId]（删除分组时的「移动到未分类」分支）。
  Future<Result<int>> moveAllFeedsToGroup({
    required int fromGroupId,
    required int targetGroupId,
  });

  /// 删除订阅的**保留接口**（T014 预留，T018 实现保留收藏的完整规则）。
  ///
  /// T014 的实现必须是「不删除任何数据 + 留下可核对的痕迹」，因为按架构 4.1 与
  /// D-11，彻底删除需要用户对「保留收藏」的显式选择与影响预览。一个在 T014 就
  /// 真删数据、却声称遵守保留规则的实现，比不实现更糟。
  Future<Result<void>> markFeedDeleted(int feedId);
}
