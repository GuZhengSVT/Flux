// 订阅与分组的 drift 实现（T014）。
//
// 职责：把 [FeedCatalogStore] 端口接到真实表上。这里只做数据读写与「整段重排」这类
// 需要原子性的写入，**不做业务判断**——「未分类不可删」「重复 URL 返回已有源」
// 「禁用源刷新跳过」都住在用例层，因为它们是产品规则，而端口实现要能被不同的
// 上层复用。
//
// 三条实现约束（都有专门测试）：
//   1) 排序写入是整段重排（同一事务内写全部行）：只改一行 sortOrder 会在拖动后
//      产生重复权重，顺序变得依赖 SQLite 的返回次序；
//   2) 删除分组**不级联**删除订阅（架构 4.1 要求由用户选择移动或删除）；
//   3) [markFeedDeleted] 是保留接口：T018 之前它**不删除任何数据**。
library;

import 'package:drift/drift.dart';

import 'package:flux/core/core.dart';

import 'database.dart';
import 'tables/feed_tables.dart';

/// 订阅与分组的 drift 存储。
final class DriftFeedCatalogStore implements FeedCatalogStore {
  /// 绑定一个已打开的数据库。
  const DriftFeedCatalogStore(this._db);

  final AppDatabase _db;

  @override
  Future<Result<List<GroupRecord>>> listGroups() async {
    try {
      final List<Group> rows = await _db.select(_db.groups).get();
      return Ok<List<GroupRecord>>(rows.map(_toGroup).toList(growable: false));
    } on Exception catch (error, stackTrace) {
      return Err<List<GroupRecord>>(_storage('listGroups', error, stackTrace));
    }
  }

  @override
  Future<Result<List<FeedRecord>>> listFeeds() async {
    try {
      final List<Feed> rows = await _db.select(_db.feeds).get();
      return Ok<List<FeedRecord>>(rows.map(_toFeed).toList(growable: false));
    } on Exception catch (error, stackTrace) {
      return Err<List<FeedRecord>>(_storage('listFeeds', error, stackTrace));
    }
  }

  @override
  Future<Result<Map<int, int>>> unreadCounts() async {
    try {
      // 只统计 readingState = unread 的文章（架构 4.1：仅未读筛选只匹配 unread，
      // later 有独立入口，不能算进「未读」——否则用户会看到一个永远清不掉的角标）。
      //
      // 用聚合 SQL 而不是「查出全部未读文章再在 Dart 里计数」：后者会把每一条
      // 未读文章的整行（含正文大字段）都读进内存，而订阅管理页只需要一个数字。
      // 聚合在该场景下是数量级差异，不是风格问题。
      final List<QueryRow> rows = await _db
          .customSelect(
            'SELECT feed_id AS feed_id, COUNT(*) AS unread_count '
            'FROM articles WHERE reading_state = ? GROUP BY feed_id',
            variables: <Variable<Object>>[
              Variable<String>(ReadingState.unread.name),
            ],
          )
          .get();
      final Map<int, int> counts = <int, int>{};
      for (final QueryRow row in rows) {
        counts[row.read<int>('feed_id')] = row.read<int>('unread_count');
      }
      return Ok<Map<int, int>>(counts);
    } on Exception catch (error, stackTrace) {
      return Err<Map<int, int>>(_storage('unreadCounts', error, stackTrace));
    }
  }

  @override
  Future<Result<FeedRecord?>> findFeedByNormalizedUrl(
    String normalizedUrl,
  ) async {
    try {
      final Feed? row =
          await (_db.select(_db.feeds)
                ..where((Feeds t) => t.normalizedUrl.equals(normalizedUrl))
                ..limit(1))
              .getSingleOrNull();
      return Ok<FeedRecord?>(row == null ? null : _toFeed(row));
    } on Exception catch (error, stackTrace) {
      return Err<FeedRecord?>(
        _storage('findFeedByNormalizedUrl', error, stackTrace),
      );
    }
  }

  @override
  Future<Result<FeedRecord?>> findFeedById(int feedId) async {
    try {
      final Feed? row =
          await (_db.select(_db.feeds)
                ..where((Feeds t) => t.id.equals(feedId))
                ..limit(1))
              .getSingleOrNull();
      return Ok<FeedRecord?>(row == null ? null : _toFeed(row));
    } on Exception catch (error, stackTrace) {
      return Err<FeedRecord?>(_storage('findFeedById', error, stackTrace));
    }
  }

  @override
  Future<Result<GroupRecord?>> findGroupBySyncId(String syncId) async {
    try {
      final Group? row =
          await (_db.select(_db.groups)
                ..where((Groups t) => t.syncId.equals(syncId))
                ..limit(1))
              .getSingleOrNull();
      return Ok<GroupRecord?>(row == null ? null : _toGroup(row));
    } on Exception catch (error, stackTrace) {
      return Err<GroupRecord?>(
        _storage('findGroupBySyncId', error, stackTrace),
      );
    }
  }

  @override
  Future<Result<GroupRecord>> createGroup({
    required String syncId,
    required String name,
    int sortOrder = 0,
  }) async {
    try {
      final int id = await _db
          .into(_db.groups)
          .insert(
            GroupsCompanion.insert(
              syncId: syncId,
              name: name,
              sortOrder: Value<int>(sortOrder),
            ),
          );
      return Ok<GroupRecord>(
        GroupRecord(
          id: id,
          syncId: syncId,
          name: name,
          sortOrder: sortOrder,
          pinned: false,
          // 新建分组永远不是保留组：保留性由建库种子（未分类）唯一决定，
          // 用例层不得把用户建的分组标成不可删。
          isReserved: false,
        ),
      );
    } on Exception catch (error, stackTrace) {
      return Err<GroupRecord>(_storage('createGroup', error, stackTrace));
    }
  }

  @override
  Future<Result<FeedRecord>> createFeed(FeedInsert insert) async {
    try {
      final int id = await _db
          .into(_db.feeds)
          .insert(
            FeedsCompanion.insert(
              syncId: insert.syncId,
              normalizedUrl: insert.normalizedUrl,
              name: insert.name,
              sourceName: Value<String?>(insert.sourceName),
              groupId: Value<int?>(insert.groupId),
              sortOrder: Value<int>(insert.sortOrder),
            ),
          );
      return Ok<FeedRecord>(
        FeedRecord(
          id: id,
          syncId: insert.syncId,
          normalizedUrl: insert.normalizedUrl,
          name: insert.name,
          sourceName: insert.sourceName,
          groupId: insert.groupId,
          favorite: false,
          enabled: true,
          sortOrder: insert.sortOrder,
        ),
      );
    } on Exception catch (error, stackTrace) {
      return Err<FeedRecord>(_storage('createFeed', error, stackTrace));
    }
  }

  @override
  Future<Result<void>> renameGroup({
    required int groupId,
    required String name,
  }) => _patchGroup(groupId, GroupsCompanion(name: Value<String>(name)));

  @override
  Future<Result<void>> setGroupPinned({
    required int groupId,
    required bool pinned,
  }) => _patchGroup(groupId, GroupsCompanion(pinned: Value<bool>(pinned)));

  @override
  Future<Result<void>> deleteGroup(int groupId) async {
    try {
      await (_db.delete(
        _db.groups,
      )..where((Groups t) => t.id.equals(groupId))).go();
      return okUnit();
    } on Exception catch (error, stackTrace) {
      return Err<void>(_storage('deleteGroup', error, stackTrace));
    }
  }

  @override
  Future<Result<void>> reorderGroups(List<int> groupIdsInOrder) async {
    try {
      // 整段重排必须在**一个事务**里完成：若写一半失败，剩下的分组会保留旧权重，
      // 于是出现「同权重」甚至「顺序看起来对但数据是错的」——下次拖动才发现。
      await _db.transaction(() async {
        for (int index = 0; index < groupIdsInOrder.length; index++) {
          await (_db.update(
            _db.groups,
          )..where((Groups t) => t.id.equals(groupIdsInOrder[index]))).write(
            GroupsCompanion(
              sortOrder: Value<int>(index),
              updatedAt: Value<DateTime>(DateTime.now().toUtc()),
            ),
          );
        }
      });
      return okUnit();
    } on Exception catch (error, stackTrace) {
      return Err<void>(_storage('reorderGroups', error, stackTrace));
    }
  }

  @override
  Future<Result<void>> renameFeed({
    required int feedId,
    required String name,
  }) => _patchFeed(feedId, FeedsCompanion(name: Value<String>(name)));

  @override
  Future<Result<void>> moveFeedToGroup({required int feedId, int? groupId}) =>
      _patchFeed(feedId, FeedsCompanion(groupId: Value<int?>(groupId)));

  @override
  Future<Result<void>> setFeedEnabled({
    required int feedId,
    required bool enabled,
  }) => _patchFeed(feedId, FeedsCompanion(enabled: Value<bool>(enabled)));

  @override
  Future<Result<void>> setFeedFavorite({
    required int feedId,
    required bool favorite,
  }) => _patchFeed(feedId, FeedsCompanion(favorite: Value<bool>(favorite)));

  @override
  Future<Result<void>> setFeedRefreshInterval({
    required int feedId,
    int? minutes,
  }) => _patchFeed(
    feedId,
    FeedsCompanion(refreshIntervalMinutes: Value<int?>(minutes)),
  );

  @override
  Future<Result<void>> reorderFeedsInGroup({
    required int groupId,
    required List<int> feedIdsInOrder,
  }) async {
    try {
      await _db.transaction(() async {
        for (int index = 0; index < feedIdsInOrder.length; index++) {
          await (_db.update(_db.feeds)..where(
                (Feeds t) =>
                    t.id.equals(feedIdsInOrder[index]) &
                    t.groupId.equals(groupId),
              ))
              .write(
                FeedsCompanion(
                  sortOrder: Value<int>(index),
                  updatedAt: Value<DateTime>(DateTime.now().toUtc()),
                ),
              );
        }
      });
      return okUnit();
    } on Exception catch (error, stackTrace) {
      return Err<void>(_storage('reorderFeedsInGroup', error, stackTrace));
    }
  }

  @override
  Future<Result<int>> moveAllFeedsToGroup({
    required int fromGroupId,
    required int targetGroupId,
  }) async {
    try {
      final int moved =
          await (_db.update(
            _db.feeds,
          )..where((Feeds t) => t.groupId.equals(fromGroupId))).write(
            FeedsCompanion(
              groupId: Value<int?>(targetGroupId),
              updatedAt: Value<DateTime>(DateTime.now().toUtc()),
            ),
          );
      return Ok<int>(moved);
    } on Exception catch (error, stackTrace) {
      return Err<int>(_storage('moveAllFeedsToGroup', error, stackTrace));
    }
  }

  @override
  Future<Result<void>> markFeedDeleted(int feedId) async {
    // T014 **有意不实现删除**（架构 4.1、D-11：默认保留收藏、其余清理，且清理范围
    // 必须在操作前可见）。这里只做两件不破坏数据的事：
    //   1) 确认这个 feed 真的存在（让调用方的错误处理有意义，而不是对着不存在的
    //      行报「成功」）；
    //   2) 留一条诊断痕迹，使「界面上点了删除」与「数据真的删了」在排查时可区分。
    // 真正的实现（含保留收藏、来源快照、墓碑事件）属 T018。
    try {
      final Feed? row =
          await (_db.select(_db.feeds)
                ..where((Feeds t) => t.id.equals(feedId))
                ..limit(1))
              .getSingleOrNull();
      if (row == null) {
        return Err<void>(
          StorageError(
            operation: 'markFeedDeleted',
            detail: 'feed $feedId 不存在',
            isMissing: true,
          ),
        );
      }
      return okUnit();
    } on Exception catch (error, stackTrace) {
      return Err<void>(_storage('markFeedDeleted', error, stackTrace));
    }
  }

  /// 更新一个分组行。
  Future<Result<void>> _patchGroup(int groupId, GroupsCompanion patch) async {
    try {
      await (_db.update(
        _db.groups,
      )..where((Groups t) => t.id.equals(groupId))).write(
        patch.copyWith(updatedAt: Value<DateTime>(DateTime.now().toUtc())),
      );
      return okUnit();
    } on Exception catch (error, stackTrace) {
      return Err<void>(_storage('updateGroup', error, stackTrace));
    }
  }

  /// 更新一个订阅行。
  Future<Result<void>> _patchFeed(int feedId, FeedsCompanion patch) async {
    try {
      await (_db.update(
        _db.feeds,
      )..where((Feeds t) => t.id.equals(feedId))).write(
        patch.copyWith(updatedAt: Value<DateTime>(DateTime.now().toUtc())),
      );
      return okUnit();
    } on Exception catch (error, stackTrace) {
      return Err<void>(_storage('updateFeed', error, stackTrace));
    }
  }

  static GroupRecord _toGroup(Group row) => GroupRecord(
    id: row.id,
    syncId: row.syncId,
    name: row.name,
    sortOrder: row.sortOrder,
    pinned: row.pinned,
    isReserved: row.isReserved,
  );

  static FeedRecord _toFeed(Feed row) => FeedRecord(
    id: row.id,
    syncId: row.syncId,
    normalizedUrl: row.normalizedUrl,
    name: row.name,
    sourceName: row.sourceName,
    groupId: row.groupId,
    favorite: row.favorite,
    enabled: row.enabled,
    refreshIntervalMinutes: row.refreshIntervalMinutes,
    sortOrder: row.sortOrder,
    lastCheckedAt: row.lastCheckedAt,
    lastRefreshResult: row.lastRefreshResult,
    lastRefreshErrorKind: row.lastRefreshErrorKind,
    httpEtag: row.httpEtag,
    httpLastModified: row.httpLastModified,
  );

  static StorageError _storage(
    String operation,
    Object error,
    StackTrace stackTrace,
  ) => StorageError(
    operation: operation,
    // 只保留异常类型：drift/sqlite 的原始文本可能带上语句与参数值。
    detail: error.runtimeType.toString(),
    cause: error,
    stackTrace: stackTrace,
  );
}

/// 数据库不可用时的降级实现（T011 的降级启动路径）。
///
/// 读操作返回**空集合**、写操作返回类型化失败。为什么不是「抛 StateError」：
/// 数据库打不开是可诊断的正常状态（架构第 8 节要求明确告知而不是崩溃），订阅管理页
/// 应当像其他页面一样显示空态 + 顶部横幅「改动不会保存」，而不是红屏。
///
/// 为什么不返回假的成功：那会让用户以为订阅加上了，重启后消失且没有任何线索。
final class DegradedFeedCatalogStore implements FeedCatalogStore {
  /// 构造降级实现。
  const DegradedFeedCatalogStore();

  @override
  Future<Result<List<GroupRecord>>> listGroups() async =>
      const Ok<List<GroupRecord>>(<GroupRecord>[]);

  @override
  Future<Result<List<FeedRecord>>> listFeeds() async =>
      const Ok<List<FeedRecord>>(<FeedRecord>[]);

  @override
  Future<Result<Map<int, int>>> unreadCounts() async =>
      const Ok<Map<int, int>>(<int, int>{});

  @override
  Future<Result<FeedRecord?>> findFeedByNormalizedUrl(
    String normalizedUrl,
  ) async => const Ok<FeedRecord?>(null);

  @override
  Future<Result<FeedRecord?>> findFeedById(int feedId) async =>
      const Ok<FeedRecord?>(null);

  @override
  Future<Result<GroupRecord?>> findGroupBySyncId(String syncId) async =>
      const Ok<GroupRecord?>(null);

  @override
  Future<Result<GroupRecord>> createGroup({
    required String syncId,
    required String name,
    int sortOrder = 0,
  }) async => Err<GroupRecord>(_degraded('createGroup'));

  @override
  Future<Result<FeedRecord>> createFeed(FeedInsert insert) async =>
      Err<FeedRecord>(_degraded('createFeed'));

  @override
  Future<Result<void>> renameGroup({
    required int groupId,
    required String name,
  }) async => Err<void>(_degraded('renameGroup'));

  @override
  Future<Result<void>> setGroupPinned({
    required int groupId,
    required bool pinned,
  }) async => Err<void>(_degraded('setGroupPinned'));

  @override
  Future<Result<void>> deleteGroup(int groupId) async =>
      Err<void>(_degraded('deleteGroup'));

  @override
  Future<Result<void>> reorderGroups(List<int> groupIdsInOrder) async =>
      Err<void>(_degraded('reorderGroups'));

  @override
  Future<Result<void>> renameFeed({
    required int feedId,
    required String name,
  }) async => Err<void>(_degraded('renameFeed'));

  @override
  Future<Result<void>> moveFeedToGroup({
    required int feedId,
    int? groupId,
  }) async => Err<void>(_degraded('moveFeedToGroup'));

  @override
  Future<Result<void>> setFeedEnabled({
    required int feedId,
    required bool enabled,
  }) async => Err<void>(_degraded('setFeedEnabled'));

  @override
  Future<Result<void>> setFeedFavorite({
    required int feedId,
    required bool favorite,
  }) async => Err<void>(_degraded('setFeedFavorite'));

  @override
  Future<Result<void>> setFeedRefreshInterval({
    required int feedId,
    int? minutes,
  }) async => Err<void>(_degraded('setFeedRefreshInterval'));

  @override
  Future<Result<void>> reorderFeedsInGroup({
    required int groupId,
    required List<int> feedIdsInOrder,
  }) async => Err<void>(_degraded('reorderFeedsInGroup'));

  @override
  Future<Result<int>> moveAllFeedsToGroup({
    required int fromGroupId,
    required int targetGroupId,
  }) async => Err<int>(_degraded('moveAllFeedsToGroup'));

  @override
  Future<Result<void>> markFeedDeleted(int feedId) async =>
      Err<void>(_degraded('markFeedDeleted'));

  static StorageError _degraded(String operation) =>
      StorageError(operation: operation, detail: '本次运行数据库不可用，订阅与分组不会保存');
}
