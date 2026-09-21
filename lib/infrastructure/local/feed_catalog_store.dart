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
import 'tables/article_tables.dart';
import 'tables/feed_tables.dart';
import 'tables/reading_tables.dart';

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
  Future<Result<void>> setFeedNewsEnabled({
    required int feedId,
    required bool? newsEnabled,
  }) => _patchFeed(
    feedId,
    // null 是「跟随 enabled」，必须真的写 NULL（而不是写一个布尔值）：Value(null) 是
    // drift 表达「把这一列设为 NULL」的方式，Value.absent() 则会变成「不改这一列」。
    FeedsCompanion(newsEnabled: Value<bool?>(newsEnabled)),
  );

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
    // T014 的预留接口在 T018 保持「不删数据」的形状：真正的删除只能经 [deleteFeed]
    // 发生，因为它要求调用方先给出「保留收藏」这一次选择（架构 4.1、D-11）。这里
    // 继续只确认存在性，使「谁在删、有没有经过确认」在排查时可分辨——若把它改成
    // 真删，任何拿着这条旧签名的调用点都会绕过确认页。
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

  // -------------------------------------------------------------------
  // T018：删除订阅/分组与保留收藏
  // -------------------------------------------------------------------

  @override
  Future<Result<FeedDeletionPreview>> previewFeedDeletion(int feedId) async {
    try {
      final Feed? feed =
          await (_db.select(_db.feeds)
                ..where((Feeds t) => t.id.equals(feedId))
                ..limit(1))
              .getSingleOrNull();
      if (feed == null) {
        return Err<FeedDeletionPreview>(
          StorageError(
            operation: 'previewFeedDeletion',
            detail: 'feed $feedId 不存在',
            isMissing: true,
          ),
        );
      }
      return Ok<FeedDeletionPreview>(
        FeedDeletionPreview(
          feedId: feed.id,
          feedSyncId: feed.syncId,
          feedName: feed.name,
          favoriteCount: await _countArticles(feedId: feedId, favorites: true),
          otherCount: await _countArticles(feedId: feedId, favorites: false),
          laterCount: await _countArticles(
            feedId: feedId,
            favorites: false,
            laterOnly: true,
          ),
        ),
      );
    } on Exception catch (error, stackTrace) {
      return Err<FeedDeletionPreview>(
        _storage('previewFeedDeletion', error, stackTrace),
      );
    }
  }

  @override
  Future<Result<FeedDeletionOutcome>> deleteFeed({
    required int feedId,
    required bool keepFavorites,
  }) => _translate(
    'deleteFeed',
    () => _db.transaction<FeedDeletionOutcome>(
      () => _deleteFeedWithinTransaction(
        feedId: feedId,
        keepFavorites: keepFavorites,
      ),
    ),
  );

  @override
  Future<Result<GroupDeletionOutcome>> deleteGroupWithFeeds({
    required int groupId,
    required GroupDeletionMode mode,
    required bool keepFavorites,
  }) => _translate(
    'deleteGroupWithFeeds',
    () => _db.transaction<GroupDeletionOutcome>(
      () => _deleteGroupWithinTransaction(
        groupId: groupId,
        mode: mode,
        keepFavorites: keepFavorites,
      ),
    ),
  );

  /// 事务内删除一个分组。
  ///
  /// 两个分支都**先处理订阅、再删分组行**：反过来的话，「分组已删但订阅仍指向它」
  /// 的那一瞬是一个已经违反「订阅必须有归属」的中间状态（外键会直接拒绝，而若关了
  /// 外键则留下悬空引用）。
  Future<GroupDeletionOutcome> _deleteGroupWithinTransaction({
    required int groupId,
    required GroupDeletionMode mode,
    required bool keepFavorites,
  }) async {
    final Group? group =
        await (_db.select(_db.groups)
              ..where((Groups t) => t.id.equals(groupId))
              ..limit(1))
            .getSingleOrNull();
    if (group == null) {
      throw StorageError(
        operation: 'deleteGroupWithFeeds',
        detail: 'group $groupId 不存在',
        isMissing: true,
      );
    }
    // 保留组不可删除：它是「订阅总有归属」的唯一保证，也是移动分支的目标。用例层
    // 已经拒绝过一次，这里再拒一次——存储层是最后一道，不能假设所有调用方都记得。
    if (group.isReserved || group.syncId == groupUncategorizedSyncId) {
      throw StorageError(
        operation: 'deleteGroupWithFeeds',
        detail: '「${group.name}」是保留分组，不能删除',
      );
    }

    final List<Feed> members = await (_db.select(
      _db.feeds,
    )..where((Feeds t) => t.groupId.equals(groupId))).get();

    switch (mode) {
      case GroupDeletionMode.moveToUncategorized:
        final int? reservedId = await _reservedGroupId();
        if (reservedId == null) {
          throw StorageError(
            operation: 'deleteGroupWithFeeds',
            detail: '保留组「未分类」不存在',
            isMissing: true,
          );
        }
        for (final Feed member in members) {
          await (_db.update(
            _db.feeds,
          )..where((Feeds t) => t.id.equals(member.id))).write(
            FeedsCompanion(
              groupId: Value<int?>(reservedId),
              updatedAt: Value<DateTime>(DateTime.now().toUtc()),
            ),
          );
        }
        await (_db.delete(
          _db.groups,
        )..where((Groups t) => t.id.equals(groupId))).go();
        await _insertDeletionEvent(
          entityType: 'group',
          syncId: group.syncId,
          displayName: group.name,
          keepFavorites: null,
          deletedArticles: 0,
          keptFavorites: 0,
        );
        return GroupDeletionOutcome(
          mode: mode,
          movedFeedCount: members.length,
          deletedFeedCount: 0,
          deletedArticles: 0,
          keptFavorites: 0,
        );

      case GroupDeletionMode.deleteFeeds:
        // 复用删除订阅的**同一段**实现（含保留收藏、来源快照、逐条墓碑）。
        int deletedArticles = 0;
        int keptFavorites = 0;
        for (final Feed member in members) {
          final FeedDeletionOutcome perFeed =
              await _deleteFeedWithinTransaction(
                feedId: member.id,
                keepFavorites: keepFavorites,
              );
          deletedArticles += perFeed.deletedArticles;
          keptFavorites += perFeed.keptFavorites;
        }
        await (_db.delete(
          _db.groups,
        )..where((Groups t) => t.id.equals(groupId))).go();
        await _insertDeletionEvent(
          entityType: 'group',
          syncId: group.syncId,
          displayName: group.name,
          keepFavorites: keepFavorites,
          deletedArticles: deletedArticles,
          keptFavorites: keptFavorites,
        );
        return GroupDeletionOutcome(
          mode: mode,
          movedFeedCount: 0,
          deletedFeedCount: members.length,
          deletedArticles: deletedArticles,
          keptFavorites: keptFavorites,
        );
    }
  }

  /// 事务内删除一条订阅。
  ///
  /// 抛出的错误由调用方翻译成 [Result]；在事务内抛出会让 drift **回滚整个事务**，
  /// 这正是「部分删除不允许存在」所需要的——一个「源没了但文章还在」或「收藏脱离了
  /// 但非收藏没删干净」的状态，用户既无法理解也无法修复，比整批失败更糟。
  Future<FeedDeletionOutcome> _deleteFeedWithinTransaction({
    required int feedId,
    required bool keepFavorites,
  }) async {
    final Feed? feed =
        await (_db.select(_db.feeds)
              ..where((Feeds t) => t.id.equals(feedId))
              ..limit(1))
            .getSingleOrNull();
    if (feed == null) {
      throw StorageError(
        operation: 'deleteFeed',
        detail: 'feed $feedId 不存在',
        isMissing: true,
      );
    }

    int keptFavorites = 0;
    if (keepFavorites) {
      // 收藏文章：脱离源 + 冻结来源快照（架构 4.1）。
      //
      // 快照用**规范化地址**而不是请求地址：库里本来就只有规范地址这一列，带凭据的
      // 原始地址以 credentialRef 引用存在 Keychain。快照不得把凭据复制进普通列——
      // 那是架构第 8 节禁止的第二条泄露路径，而且这份快照将来会随同步包离开本机。
      keptFavorites =
          await (_db.update(_db.articles)..where(
                (Articles t) =>
                    t.feedId.equals(feedId) & t.favorite.equals(true),
              ))
              .write(
                ArticlesCompanion(
                  feedId: const Value<int?>(null),
                  feedTitle: Value<String?>(feed.name),
                  feedUrl: Value<String?>(feed.normalizedUrl),
                  // readingState 与 favorite 有意不出现：脱离源不改变用户的阅读状态，
                  // 也不改变收藏值（它本来就是靠 favorite 才被留下来的）。
                  updatedAt: Value<DateTime>(DateTime.now().toUtc()),
                ),
              );
    }

    // 其余文章（**含 later**）一律清理。条件是「仍属于该源」而不是「非收藏」：保留
    // 分支上一步已把保留的收藏置空 feed_id，用归属作条件能保证不漏删——即使某行是
    // 收藏但上一步没覆盖到（例如并发新增），它也会落进这里被删掉，而不会成为一条
    // 「源已不存在却仍指向它」的悬空行。
    final int deletedArticles = await _deleteArticlesOfFeed(feedId);

    await (_db.delete(_db.feeds)..where((Feeds t) => t.id.equals(feedId))).go();

    await _insertDeletionEvent(
      entityType: 'feed',
      syncId: feed.syncId,
      displayName: feed.name,
      keepFavorites: keepFavorites,
      deletedArticles: deletedArticles,
      keptFavorites: keptFavorites,
    );

    return FeedDeletionOutcome(
      feedId: feed.id,
      feedSyncId: feed.syncId,
      feedName: feed.name,
      keepFavorites: keepFavorites,
      deletedArticles: deletedArticles,
      keptFavorites: keptFavorites,
    );
  }

  /// 删除某源的全部剩余文章，并清掉它们的本机会话行。
  ///
  /// 为什么顺带删会话：`reading_sessions.article_id` 是指向文章的外键且没有级联动作，
  /// 文章被删后这些行要么让删除**直接失败**（外键拒绝），要么成为指向不存在文章的
  /// 悬空统计（架构 5.3：不能留下隐藏副本）。「这篇文章被读了多久」在文章不存在时
  /// 没有任何意义，因此随文章一起清理。
  ///
  /// 引用（Citations）**不删**：它的外键是 SET NULL，且架构 4.4 明确要求引用保留
  /// 标题/URL/摘录等最小快照——删掉它会让历史总结的出处凭空消失。
  Future<int> _deleteArticlesOfFeed(int feedId) async {
    // read() 的静态返回类型是可空的（drift 没法从表达式的类型推出列的非空约束），
    // 因此用 whereType 过滤而不是写成 `!`：id 是主键、不可能为空，whereType 把同一个
    // 事实表达在类型层面，也不依赖一个会在运行时才炸的断言。
    final List<int> ids =
        (await (_db.selectOnly(_db.articles)
                  ..addColumns(<Expression<Object>>[_db.articles.id])
                  ..where(_db.articles.feedId.equals(feedId)))
                .map((TypedResult row) => row.read(_db.articles.id))
                .get())
            .whereType<int>()
            .toList(growable: false);
    if (ids.isEmpty) {
      return 0;
    }
    await (_db.delete(
      _db.readingSessions,
    )..where((ReadingSessions t) => t.articleId.isIn(ids))).go();
    return (_db.delete(
      _db.articles,
    )..where((Articles t) => t.feedId.equals(feedId))).go();
  }

  /// 统计某源下的文章数。
  ///
  /// [favorites] 选收藏或非收藏；[laterOnly] 进一步限定阅读状态为 later。三个数字
  /// （收藏 / 其余 / 其余中的 later）必须分开取，因为用户要回答的是「保留会留下几篇、
  /// 其余有多少会被清掉，我的稍后再读在不在里面」（架构 4.1 明写 later 属于清理范围）。
  Future<int> _countArticles({
    required int feedId,
    required bool favorites,
    bool laterOnly = false,
  }) async {
    final JoinedSelectStatement<$ArticlesTable, Article> select =
        _db.selectOnly(_db.articles)
          ..addColumns(<Expression<Object>>[countAll()])
          ..where(_db.articles.feedId.equals(feedId))
          ..where(_db.articles.favorite.equals(favorites));
    if (laterOnly) {
      select.where(_db.articles.readingState.equalsValue(ReadingState.later));
    }
    final TypedResult row = await select.getSingle();
    return row.read(countAll()) ?? 0;
  }

  /// 保留组「未分类」的本机 id；缺失时为 null（调用方报错，不静默新建）。
  Future<int?> _reservedGroupId() async {
    final Group? row =
        await (_db.select(_db.groups)
              ..where((Groups t) => t.syncId.equals(groupUncategorizedSyncId))
              ..limit(1))
            .getSingleOrNull();
    return row?.id;
  }

  /// 写一条墓碑事件（架构 5.2「删除使用墓碑，首发不自动清除」）。
  Future<void> _insertDeletionEvent({
    required String entityType,
    required String syncId,
    required String displayName,
    required bool? keepFavorites,
    required int deletedArticles,
    required int keptFavorites,
  }) async {
    await _db
        .into(_db.deletionEvents)
        .insert(
          DeletionEventsCompanion.insert(
            entityType: entityType,
            syncId: syncId,
            displayName: displayName,
            keepFavorites: Value<bool?>(keepFavorites),
            deletedArticleCount: Value<int>(deletedArticles),
            keptFavoriteCount: Value<int>(keptFavorites),
            deletedAt: DateTime.now().toUtc(),
          ),
        );
  }

  /// 把一次可能抛异常的存储操作翻译成 [Result]。
  static Future<Result<T>> _translate<T>(
    String operation,
    Future<T> Function() action,
  ) async {
    try {
      return Ok<T>(await action());
    } on AppError catch (error, stackTrace) {
      return Err<T>(
        error is StorageError
            ? error
            : StorageError(
                operation: operation,
                detail: error.message,
                cause: error,
                stackTrace: stackTrace,
              ),
      );
    } on Exception catch (error, stackTrace) {
      return Err<T>(_storage(operation, error, stackTrace));
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
    newsEnabled: row.newsEnabled,
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
  Future<Result<void>> setFeedNewsEnabled({
    required int feedId,
    required bool? newsEnabled,
  }) async => Err<void>(_degraded('setFeedNewsEnabled'));

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

  @override
  Future<Result<FeedDeletionPreview>> previewFeedDeletion(int feedId) async =>
      Err<FeedDeletionPreview>(_degraded('previewFeedDeletion'));

  @override
  Future<Result<FeedDeletionOutcome>> deleteFeed({
    required int feedId,
    required bool keepFavorites,
  }) async => Err<FeedDeletionOutcome>(_degraded('deleteFeed'));

  @override
  Future<Result<GroupDeletionOutcome>> deleteGroupWithFeeds({
    required int groupId,
    required GroupDeletionMode mode,
    required bool keepFavorites,
  }) async => Err<GroupDeletionOutcome>(_degraded('deleteGroupWithFeeds'));

  static StorageError _degraded(String operation) =>
      StorageError(operation: operation, detail: '本次运行数据库不可用，订阅与分组不会保存');
}
