// 同步状态的 SQLite 实现（T041；端口在 core/domain/sync_store.dart）。
//
// 三条实现纪律：
//   1) **确认按修订号上界**：confirmPendingUpTo 只删 ≤ revision 的行。写成「清空整表」
//      会让上传期间产生的新本地修改一起被标记为已同步，于是那些改动永远不上传
//      （架构 5.2 明确禁止）；
//   2) **占位行不写正文**：applyRemoteArticleState 新建行时 body 一律 null、
//      identityBasis = remote、syncKey 由远端键派生。这里**没有任何**写 body 的语句，
//      因此「把不存在的文章虚构成全文」在这条路径上不可表达（架构 5.2）；
//   3) **凭据不经过本文件**：本文件不 import Keychain、不接受秘密参数、不写日志。
library;

import 'package:drift/drift.dart';

import 'package:flux/core/core.dart';

import 'database.dart';
import 'tables/article_tables.dart';
import 'tables/feed_tables.dart';
import 'tables/sync_tables.dart';

/// drift 实现。
final class DriftSyncStore implements SyncStore {
  /// 绑定一个已打开的数据库。
  const DriftSyncStore(this._db);

  final AppDatabase _db;

  @override
  Future<Result<SyncBaseline>> readBaseline() async {
    try {
      final SyncStateRecord? row =
          await (_db.select(_db.syncStateRecords)..where(
                (SyncStateRecords t) =>
                    t.id.equals(SyncStateRecords.singletonId),
              ))
              .getSingleOrNull();
      return Ok<SyncBaseline>(_toBaseline(row));
    } on Exception catch (error, stackTrace) {
      return Err<SyncBaseline>(
        StorageError(
          operation: 'sync.readBaseline',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  @override
  Future<Result<void>> writeDeviceName(String deviceName) async => _updateState(
    'sync.writeDeviceName',
    () => SyncStateRecordsCompanion(deviceName: Value<String?>(deviceName)),
  );

  @override
  Future<Result<void>> writeCapability({
    required bool supportsConditionalWrite,
    required DateTime probedAt,
  }) => _updateState(
    'sync.writeCapability',
    () => SyncStateRecordsCompanion(
      supportsConditionalWrite: Value<bool?>(supportsConditionalWrite),
      capabilityProbedAt: Value<DateTime?>(probedAt),
    ),
  );

  @override
  Future<Result<int>> bumpRevision() async {
    try {
      final SyncStateRecord row = await _requireState();
      final int next = row.localRevision + 1;
      await (_db.update(_db.syncStateRecords)..where(
            (SyncStateRecords t) => t.id.equals(SyncStateRecords.singletonId),
          ))
          .write(SyncStateRecordsCompanion(localRevision: Value<int>(next)));
      return Ok<int>(next);
    } on AppError catch (error) {
      return Err<int>(error);
    } on Exception catch (error, stackTrace) {
      return Err<int>(
        StorageError(
          operation: 'sync.bumpRevision',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  @override
  Future<Result<void>> recordPendingChanges(List<PendingChange> changes) async {
    if (changes.isEmpty) {
      return okUnit();
    }
    try {
      await _db.transaction(() async {
        for (final PendingChange change in changes) {
          // 同实体同字段只有一行：新改动覆盖旧行（含修订号），因此「这一列被改过」
          // 永远只有一条待上传记录，不会随着用户反复修改而堆积。
          await _db
              .into(_db.syncPendingChanges)
              .insert(
                SyncPendingChangesCompanion.insert(
                  entityKind: change.entityKind,
                  entityKey: change.entityKey,
                  fieldName: Value<String>(change.fieldName),
                  revision: change.revision,
                  changedAt: change.changedAt,
                ),
                // 冲突目标是那条**唯一索引**（实体+字段），不是主键 id：
                // drift 的 insertOnConflictUpdate 默认按主键更新，而这里每次记录都是
                // 一条新行（id 自增），因此它永远不冲突，实际会撞上唯一索引并抛错
                // ——一次「用户又改了同一个字段」就会变成写库失败。显式给出 target
                // 之后，同一个字段反复修改只保留一行（修订号推进到最新）。
                onConflict:
                    DoUpdate<$SyncPendingChangesTable, SyncPendingChange>(
                      (SyncPendingChanges old) => SyncPendingChangesCompanion(
                        revision: Value<int>(change.revision),
                        changedAt: Value<DateTime>(change.changedAt),
                      ),
                      target: <Column<Object>>[
                        _db.syncPendingChanges.entityKind,
                        _db.syncPendingChanges.entityKey,
                        _db.syncPendingChanges.fieldName,
                      ],
                    ),
              );
        }
      });
      return okUnit();
    } on Exception catch (error, stackTrace) {
      return Err<void>(
        StorageError(
          operation: 'sync.recordPendingChanges',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  @override
  Future<Result<List<PendingChange>>> pendingChangesUpTo(int revision) async {
    try {
      final List<SyncPendingChange> rows =
          await (_db.select(_db.syncPendingChanges)
                ..where(
                  (SyncPendingChanges t) =>
                      t.revision.isSmallerOrEqualValue(revision),
                )
                ..orderBy(<OrderClauseGenerator<SyncPendingChanges>>[
                  (SyncPendingChanges t) => OrderingTerm.asc(t.revision),
                  (SyncPendingChanges t) => OrderingTerm.asc(t.id),
                ]))
              .get();
      return Ok<List<PendingChange>>(
        rows.map(_toPendingChange).toList(growable: false),
      );
    } on Exception catch (error, stackTrace) {
      return Err<List<PendingChange>>(
        StorageError(
          operation: 'sync.pendingChangesUpTo',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  @override
  Future<Result<int>> confirmPendingUpTo(int revision) async {
    try {
      final int removed =
          await (_db.delete(_db.syncPendingChanges)..where(
                (SyncPendingChanges t) =>
                    t.revision.isSmallerOrEqualValue(revision),
              ))
              .go();
      return Ok<int>(removed);
    } on Exception catch (error, stackTrace) {
      return Err<int>(
        StorageError(
          operation: 'sync.confirmPendingUpTo',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  @override
  Future<Result<void>> recordTombstone(SyncTombstone tombstone) async {
    try {
      // insertOrIgnore：同一实体的墓碑只保留第一条（重复删除是幂等的，且**不**刷新
      // 删除时间——刷新会让「什么时候删的」随着每次重复操作漂移）。
      await _db
          .into(_db.syncTombstones)
          .insert(
            SyncTombstonesCompanion.insert(
              entityKind: tombstone.entityKind,
              entityKey: tombstone.entityKey,
              deletedAt: tombstone.deletedAt,
              revision: tombstone.revision,
              displayName: Value<String?>(tombstone.displayName),
            ),
            mode: InsertMode.insertOrIgnore,
          );
      return okUnit();
    } on Exception catch (error, stackTrace) {
      return Err<void>(
        StorageError(
          operation: 'sync.recordTombstone',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  @override
  Future<Result<List<SyncTombstone>>> listTombstones({
    String? entityKind,
  }) async {
    try {
      final SimpleSelectStatement<SyncTombstones, SyncTombstoneRecord> query =
          _db.select(_db.syncTombstones);
      if (entityKind != null) {
        query.where((SyncTombstones t) => t.entityKind.equals(entityKind));
      }
      query.orderBy(<OrderClauseGenerator<SyncTombstones>>[
        (SyncTombstones t) => OrderingTerm.asc(t.deletedAt),
        (SyncTombstones t) => OrderingTerm.asc(t.id),
      ]);
      final List<SyncTombstoneRecord> rows = await query.get();
      return Ok<List<SyncTombstone>>(
        rows.map(_toTombstone).toList(growable: false),
      );
    } on Exception catch (error, stackTrace) {
      return Err<List<SyncTombstone>>(
        StorageError(
          operation: 'sync.listTombstones',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  @override
  Future<Result<bool>> hasTombstone({
    required String entityKind,
    required String entityKey,
  }) async {
    try {
      final SyncTombstoneRecord? row =
          await (_db.select(_db.syncTombstones)
                ..where(
                  (SyncTombstones t) =>
                      t.entityKind.equals(entityKind) &
                      t.entityKey.equals(entityKey),
                )
                ..limit(1))
              .getSingleOrNull();
      return Ok<bool>(row != null);
    } on Exception catch (error, stackTrace) {
      return Err<bool>(
        StorageError(
          operation: 'sync.hasTombstone',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  @override
  Future<Result<void>> recordSyncSuccess({
    required String baseVersion,
    required int confirmedRevision,
    required DateTime syncedAt,
  }) async {
    try {
      // 先清待同步行、再推进基线，整个过程在**一个事务**里：
      //   - 分开做的话，「清了待同步行但基线没推进」会让下次同步把已经上传过的改动
      //     再上传一遍（幂等由服务端保证，但本地多做一次无意义的工作）；
      //   - 顺序不能反：基线先推进而待同步行还在时，若此刻崩溃就会留下「基线说已同步、
      //     待同步表说还没上传」的矛盾状态，而重试路径会按基线判断「无事可做」。
      await _db.transaction(() async {
        await (_db.delete(_db.syncPendingChanges)..where(
              (SyncPendingChanges t) =>
                  t.revision.isSmallerOrEqualValue(confirmedRevision),
            ))
            .go();
        final SyncStateRecord row = await _requireState();
        await (_db.update(_db.syncStateRecords)..where(
              (SyncStateRecords t) => t.id.equals(SyncStateRecords.singletonId),
            ))
            .write(
              SyncStateRecordsCompanion(
                baseVersion: Value<String?>(baseVersion),
                lastSyncedAt: Value<DateTime?>(syncedAt),
                // 修订号只增（不回退到 confirmedRevision）：上传期间可能又产生了新改动，
                // 把修订号改小会让那些新改动落在一个已被确认的区间里，从此不再上传。
                localRevision: Value<int>(
                  row.localRevision > confirmedRevision
                      ? row.localRevision
                      : confirmedRevision,
                ),
              ),
            );
      });
      return okUnit();
    } on AppError catch (error) {
      return Err<void>(error);
    } on Exception catch (error, stackTrace) {
      return Err<void>(
        StorageError(
          operation: 'sync.recordSyncSuccess',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  @override
  Future<Result<void>> saveFeedAlias({
    required String syncId,
    required int localFeedId,
  }) async {
    try {
      await _db
          .into(_db.syncFeedAliasRecords)
          .insert(
            SyncFeedAliasRecordsCompanion.insert(
              syncId: syncId,
              localFeedId: localFeedId,
            ),
            // 已存在同名别名时忽略：两条远端 syncId 指向同一本机订阅这件事由 T044 的
            // 冲突呈现处理，存储层不替用户选择（覆盖会让前一条别名凭空消失）。
            mode: InsertMode.insertOrIgnore,
          );
      return okUnit();
    } on Exception catch (error, stackTrace) {
      return Err<void>(
        StorageError(
          operation: 'sync.saveFeedAlias',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  @override
  Future<Result<List<SyncFeedAlias>>> loadFeedAliases() async {
    try {
      final List<SyncFeedAliasRecord> rows = await _db
          .select(_db.syncFeedAliasRecords)
          .get();
      return Ok<List<SyncFeedAlias>>(
        rows
            .map(
              (SyncFeedAliasRecord r) =>
                  SyncFeedAlias(syncId: r.syncId, localFeedId: r.localFeedId),
            )
            .toList(growable: false),
      );
    } on Exception catch (error, stackTrace) {
      return Err<List<SyncFeedAlias>>(
        StorageError(
          operation: 'sync.loadFeedAliases',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  @override
  Future<Result<RemoteStateOutcome>> applyRemoteArticleState(
    RemoteArticleState state,
  ) async {
    try {
      final int localFeedId = await _localFeedIdFor(state.feedSyncId);
      final String placeholderKey = syncPlaceholderKey(
        feedSyncId: state.feedSyncId,
        remoteKey: state.remoteKey,
      );

      // 本机已有这一行吗？三种可能，顺序有意义：
      //   1) 本机自己算过同一个键（两台设备都抓到了同一篇文章）；
      //   2) 本机已有同源同 GUID/链接的文章（远端带了证据，而本机抓到了同一篇）；
      //   3) 本机有一行占位（此前同步过状态，后来抓取仍未补上）。
      final Article? existing = await _findLocalArticle(
        localFeedId: localFeedId,
        state: state,
      );

      if (existing == null) {
        // **占位行**：状态落库、正文为空、身份依据是 remote。
        // 没有对齐到本机订阅时写 **null**（不是 0）：0 是一个不存在的外键值，
        // 会被外键约束直接拒绝，于是「远端送来一条还没对齐的订阅」会让整批状态失败；
        // null 表示「暂时没有归属」，行为与「订阅被删除后保留下来的收藏」一致。
        final int? owningFeedId = localFeedId == 0 ? null : localFeedId;
        final int id = await _db
            .into(_db.articles)
            .insert(
              ArticlesCompanion.insert(
                feedId: Value<int?>(owningFeedId),
                title: state.title ?? '',
                identityBasis: IdentityBasis.remote,
                readingState: Value<ReadingState>(state.readingState),
                favorite: Value<bool>(state.favorite),
                publishedAt: Value<DateTime?>(state.publishedAt),
                syncKey: Value<String?>(placeholderKey),
                // body / bodyHash / summary / imageUrl 一律不写：
                // 远端首发不同步正文（架构 5.2），因此这里没有可写的内容；
                // 伪造一段占位正文会让后续抓取无法判断「本机是否已有正文」。
              ),
            );
        return Ok<RemoteStateOutcome>(
          RemoteStateOutcome(
            action: SyncRemoteStateAction.createPlaceholder,
            localArticleId: id,
            identityBasis: IdentityBasis.remote,
          ),
        );
      }

      // 已有本机行：**只应用状态**。正文、标题、身份依据、GUID/链接一律不动
      // （远端可能不知道本机已抓到的正文；用远端的空值覆盖等于清空已抓取的全文）。
      await (_db.update(
        _db.articles,
      )..where((Articles t) => t.id.equals(existing.id))).write(
        ArticlesCompanion(
          readingState: Value<ReadingState>(state.readingState),
          favorite: Value<bool>(state.favorite),
          updatedAt: Value<DateTime>(DateTime.now().toUtc()),
          // 顺手补上同步键（本机此前还没算过）：它是后续同步的匹配依据，
          // 补上不改变任何用户可见内容。已有值时不覆盖（空值才补）。
          syncKey: existing.syncKey == null
              ? Value<String?>(placeholderKey)
              : const Value<String?>.absent(),
        ),
      );
      return Ok<RemoteStateOutcome>(
        RemoteStateOutcome(
          action: SyncRemoteStateAction.applyStateOnly,
          localArticleId: existing.id,
          identityBasis: existing.identityBasis,
        ),
      );
    } on Exception catch (error, stackTrace) {
      return Err<RemoteStateOutcome>(
        StorageError(
          operation: 'sync.applyRemoteArticleState',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  /// 找到这一远端状态对应的本机行；没有则 null。
  Future<Article?> _findLocalArticle({
    required int localFeedId,
    required RemoteArticleState state,
  }) async {
    // 1) 本机自己算出的同步键（同源同证据）。
    final String? ownKey = syncArticleKey(
      feedSyncId: state.feedSyncId,
      guid: state.guid,
      normalizedLink: state.normalizedLink,
      fallbackFingerprint: state.fallbackFingerprint,
    );
    final String placeholderKey = syncPlaceholderKey(
      feedSyncId: state.feedSyncId,
      remoteKey: state.remoteKey,
    );
    for (final String key in <String>[
      ?ownKey,
      placeholderKey,
      state.remoteKey,
    ]) {
      final Article? byKey =
          await (_db.select(_db.articles)
                ..where((Articles t) => t.syncKey.equals(key))
                ..limit(1))
              .getSingleOrNull();
      if (byKey != null) {
        return byKey;
      }
    }

    // 2) 远端带了证据时按本机既有的身份规则找（文章可能还没算过同步键）。
    final String? guid = state.guid;
    if (guid != null && guid.trim().isNotEmpty && localFeedId != 0) {
      final Article? byGuid =
          await (_db.select(_db.articles)
                ..where(
                  (Articles t) =>
                      t.feedId.equals(localFeedId) & t.guid.equals(guid.trim()),
                )
                ..limit(1))
              .getSingleOrNull();
      if (byGuid != null) {
        return byGuid;
      }
    }
    final String? link = state.normalizedLink;
    if (link != null && link.trim().isNotEmpty && localFeedId != 0) {
      final Article? byLink =
          await (_db.select(_db.articles)
                ..where(
                  (Articles t) =>
                      t.feedId.equals(localFeedId) &
                      t.normalizedLink.equals(link.trim()),
                )
                ..limit(1))
              .getSingleOrNull();
      if (byLink != null) {
        return byLink;
      }
    }
    return null;
  }

  /// 由订阅 syncId（或别名）得到本机 feed id；找不到时返回 0（表示没有归属）。
  ///
  /// 返回 0 而不是抛错：远端可能送来一条本机还没对齐的订阅（对齐由 T044 的首次合并
  /// 呈现给用户决定），此时落一条**无归属的占位行**比整个应用失败更有用——用户能在
  /// 「稍后再读」里看到它，而失败会让这一批状态全部丢掉。
  Future<int> _localFeedIdFor(String feedSyncId) async {
    final Feed? direct =
        await (_db.select(_db.feeds)
              ..where((Feeds t) => t.syncId.equals(feedSyncId))
              ..limit(1))
            .getSingleOrNull();
    if (direct != null) {
      return direct.id;
    }
    final SyncFeedAliasRecord? alias =
        await (_db.select(_db.syncFeedAliasRecords)
              ..where((SyncFeedAliasRecords t) => t.syncId.equals(feedSyncId))
              ..limit(1))
            .getSingleOrNull();
    return alias?.localFeedId ?? 0;
  }

  Future<SyncStateRecord> _requireState() async {
    final SyncStateRecord? row =
        await (_db.select(_db.syncStateRecords)..where(
              (SyncStateRecords t) => t.id.equals(SyncStateRecords.singletonId),
            ))
            .getSingleOrNull();
    if (row == null) {
      throw StorageError(
        operation: 'sync.readBaseline',
        detail: '缺少单行同步状态（建库与迁移都应写入它）',
        isMissing: true,
      );
    }
    return row;
  }

  Future<Result<void>> _updateState(
    String operation,
    SyncStateRecordsCompanion Function() build,
  ) async {
    try {
      final SyncStateRecord row = await _requireState();
      await (_db.update(
        _db.syncStateRecords,
      )..where((SyncStateRecords t) => t.id.equals(row.id))).write(build());
      return okUnit();
    } on AppError catch (error) {
      return Err<void>(error);
    } on Exception catch (error, stackTrace) {
      return Err<void>(
        StorageError(
          operation: operation,
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  static SyncBaseline _toBaseline(SyncStateRecord? row) => SyncBaseline(
    baseVersion: row?.baseVersion,
    localRevision: row?.localRevision ?? 0,
    lastSyncedAt: row?.lastSyncedAt,
    deviceName: row?.deviceName,
    supportsConditionalWrite: row?.supportsConditionalWrite,
    capabilityProbedAt: row?.capabilityProbedAt,
  );

  static SyncTombstone _toTombstone(SyncTombstoneRecord row) => SyncTombstone(
    entityKind: row.entityKind,
    entityKey: row.entityKey,
    deletedAt: row.deletedAt,
    revision: row.revision,
    displayName: row.displayName,
  );

  static PendingChange _toPendingChange(SyncPendingChange row) => PendingChange(
    entityKind: row.entityKind,
    entityKey: row.entityKey,
    fieldName: row.fieldName,
    revision: row.revision,
    changedAt: row.changedAt,
  );
}
