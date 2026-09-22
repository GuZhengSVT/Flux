// 本机内容快照读写（T043；端口在 core/domain/sync_local_store.dart）。
//
// 这一层是「本机当前内容」与「合并结果」的**唯一翻译点**：往上是三份同形态快照的纯合并，
// 往下是 drift 表。因此三件事只在这里发生一次：
//
//   1) **投影决定字段清单**。读出去哪些字段、写回哪些字段，都按 T041 的 [SyncProjection]
//      走（C 类设置、订阅/分组、三态与收藏、T036 的新闻规则）。本文件里**没有**第二份
//      「哪些字段敏感」的判断，因此不会与投影漂移。
//   2) **列表型内容是单个实体**。必访站列表与三个有序列表各是一个实体，整个列表是一个字段
//      （sites / values）。这样「两边都改了同一个列表」在合并里就是一次真实的同字段冲突
//      （用户选版），而不是逐条并集成一个谁都没选过的混合列表。
//   3) **写回不删任何业务行**。远端破坏性删除的应用属 T045；「未确认不清数据」在这里表现为
//      「这条路径根本不具备删除订阅/文章的能力」。
//
// 另一条纪律：**上传期间的新本地改动必须留下**。写回每个字段前先查「这项字段是不是在
// 本轮修订之后又被改过」（sync_pending_changes.revision > confirmedRevision），是则跳过
// 并记入 [SyncApplyOutcome.preservedLocalFields]——那份改动属于下一轮待同步内容，而用一轮
// 已经发布的旧值把它盖掉，正是架构 5.2 禁止的「把所有 dirty 标记一并清空」。
library;

import 'package:drift/drift.dart';

import 'package:flux/core/core.dart';

import 'database.dart';
import 'tables/article_tables.dart';
import 'tables/feed_tables.dart';
import 'tables/news_tables.dart';
import 'tables/sync_tables.dart';

/// drift 实现。
final class DriftSyncLocalStore implements SyncLocalStore {
  /// 绑定一个已打开的数据库。
  const DriftSyncLocalStore(this._db);

  final AppDatabase _db;

  /// 必访站列表实体的键（整表一个实体，见文件头第 2 条）。
  static const String requiredSitesKey = 'requiredSites';

  @override
  Future<Result<SyncSnapshot>> readLocalSnapshot() async {
    try {
      final Map<String, Map<String, SyncEntity>> entities =
          <String, Map<String, SyncEntity>>{};
      final Map<String, SyncDeletion> deletions = <String, SyncDeletion>{};

      // ---- 共通设置（C 类且可持久化；清单派生自投影） ------------------------
      final Map<String, Object?> storedSettings = <String, Object?>{};
      final List<Setting> settingRows = await _db.select(_db.settings).get();
      for (final Setting row in settingRows) {
        storedSettings[row.key] = SettingValueCodec.decodeOrNull(row.value);
      }
      for (final String code in SyncProjection.settingCodes) {
        // 未存过的编号**不写入快照**（而不是写一个 null）：写入 null 会被对端读成
        // 「这台设备把这个设置改成了 null」，而事实是「这台设备没改过它」。
        if (!storedSettings.containsKey(code)) {
          continue;
        }
        _put(entities, SyncEntityKind.setting, code, <String, Object?>{
          'value': storedSettings[code],
        });
      }

      // ---- 分组 --------------------------------------------------------------
      final List<Group> groups = await _db.select(_db.groups).get();
      final Map<int, String> groupSyncIdById = <int, String>{};
      for (final Group group in groups) {
        groupSyncIdById[group.id] = group.syncId;
        _put(entities, SyncEntityKind.group, group.syncId, <String, Object?>{
          'syncId': group.syncId,
          'name': group.name,
          'sortOrder': group.sortOrder,
          'pinned': group.pinned,
          'isReserved': group.isReserved,
        });
      }

      // ---- 订阅 --------------------------------------------------------------
      final List<Feed> feeds = await _db.select(_db.feeds).get();
      for (final Feed feed in feeds) {
        _put(entities, SyncEntityKind.feed, feed.syncId, <String, Object?>{
          'syncId': feed.syncId,
          'normalizedUrl': feed.normalizedUrl,
          'name': feed.name,
          if (feed.sourceName != null) 'sourceName': feed.sourceName,
          if (feed.groupId != null)
            'groupSyncId': groupSyncIdById[feed.groupId],
          'favorite': feed.favorite,
          'enabled': feed.enabled,
          if (feed.newsEnabled != null) 'newsEnabled': feed.newsEnabled,
          if (feed.refreshIntervalMinutes != null)
            'refreshIntervalMinutes': feed.refreshIntervalMinutes,
          'sortOrder': feed.sortOrder,
        });
      }

      // ---- 文章状态（只有状态，没有正文） ------------------------------------
      final List<Article> articles = await _db.select(_db.articles).get();
      for (final Article article in articles) {
        final String? syncKey = article.syncKey;
        if (syncKey == null || syncKey.isEmpty) {
          // 没有同步键的文章（身份证据全缺）不参与状态同步：给它编一个键会让两台设备上
          // 的无关文章互相覆盖状态（T041）。
          continue;
        }
        _put(entities, SyncEntityKind.articleState, syncKey, <String, Object?>{
          'readingState': article.readingState.name,
          'favorite': article.favorite,
        });
      }

      // ---- T036 的新闻规则 ---------------------------------------------------
      final List<NewsRequiredSiteRecord> sites =
          await (_db.select(_db.newsRequiredSiteRecords)
                ..orderBy(<OrderClauseGenerator<NewsRequiredSiteRecords>>[
                  (NewsRequiredSiteRecords t) => OrderingTerm.asc(t.sortOrder),
                  (NewsRequiredSiteRecords t) => OrderingTerm.asc(t.id),
                ]))
              .get();
      _put(
        entities,
        SyncEntityKind.newsRequiredSite,
        requiredSitesKey,
        <String, Object?>{
          'sites': <Object?>[
            for (final NewsRequiredSiteRecord site in sites)
              <String, Object?>{
                'name': site.name,
                'url': site.url,
                'enabled': site.enabled,
              },
          ],
        },
      );

      for (final String kind in NewsListCategory.all) {
        final List<NewsConfigEntryRecord> rows =
            await (_db.select(_db.newsConfigEntryRecords)
                  ..where((NewsConfigEntryRecords t) => t.kind.equals(kind))
                  ..orderBy(<OrderClauseGenerator<NewsConfigEntryRecords>>[
                    (NewsConfigEntryRecords t) => OrderingTerm.asc(t.sortOrder),
                    (NewsConfigEntryRecords t) => OrderingTerm.asc(t.id),
                  ]))
                .get();
        _put(entities, SyncEntityKind.newsListEntry, kind, <String, Object?>{
          'values': <Object?>[
            for (final NewsConfigEntryRecord row in rows) row.value,
          ],
        });
      }

      final List<NewsPromptVersionRecord> prompts =
          await (_db.select(_db.newsPromptVersionRecords)
                ..orderBy(<OrderClauseGenerator<NewsPromptVersionRecords>>[
                  (NewsPromptVersionRecords t) => OrderingTerm.asc(t.language),
                  (NewsPromptVersionRecords t) => OrderingTerm.asc(t.version),
                ]))
              .get();
      for (final NewsPromptVersionRecord prompt in prompts) {
        if (!SyncProjection.newsPromptLanguages.contains(prompt.language)) {
          continue;
        }
        _put(
          entities,
          SyncEntityKind.newsPromptVersion,
          '${prompt.language}#${prompt.version}',
          <String, Object?>{
            'language': prompt.language,
            'version': prompt.version,
            'mode': prompt.mode,
            'taskInstruction': prompt.taskInstruction,
            'outputSpec': prompt.outputSpec,
            'advancedPrompt': prompt.advancedPrompt,
            if (prompt.note != null) 'note': prompt.note,
          },
        );
      }

      // ---- 墓碑（删除是长期事实，必须随快照传播） ----------------------------
      final List<SyncTombstoneRecord> tombstones = await _db
          .select(_db.syncTombstones)
          .get();
      // 「保留收藏」这份**操作元数据**（架构 5.2「删除订阅的保留收藏选择进入同步操作
      // 元数据」）住在 T018 的 deletion_events：墓碑表只记「这个键被删了」，而别的设备
      // 在应用这次删除**之前**必须能展示它的破坏性影响，因此这里按 syncId 关联它。
      final Map<String, bool?> keepFavoritesByKey = <String, bool?>{};
      for (final DeletionEvent event
          in await _db.select(_db.deletionEvents).get()) {
        keepFavoritesByKey['${event.entityType}\u0000${event.syncId}'] =
            event.keepFavorites;
      }
      for (final SyncTombstoneRecord row in tombstones) {
        final bool? keepFavorites =
            keepFavoritesByKey['${row.entityKind}\u0000${row.entityKey}'];
        deletions[deletionKey(
          kind: row.entityKind,
          key: row.entityKey,
        )] = SyncDeletion(
          kind: row.entityKind,
          key: row.entityKey,
          displayName: row.displayName,
          revision: row.revision,
          keepFavorites: keepFavorites,
        );
      }

      return Ok<SyncSnapshot>(
        SyncSnapshot(
          entities: entities,
          deletions: Map<String, SyncDeletion>.unmodifiable(deletions),
        ),
      );
    } on Exception catch (error, stackTrace) {
      return Err<SyncSnapshot>(
        StorageError(
          operation: 'sync.readLocalSnapshot',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  @override
  Future<Result<SyncApplyOutcome>> applyMergedSnapshot({
    required SyncSnapshot merged,
    required int confirmedRevision,
    required String baseVersion,
    required DateTime syncedAt,
  }) async {
    try {
      int applied = 0;
      int skipped = 0;
      int confirmed = 0;
      final List<String> preserved = <String>[];

      await _db.transaction(() async {
        // 上传期间又改过的字段（修订号 > 本轮上界）：这些字段属于**下一轮**待同步内容，
        // 因此本轮写回必须跳过它们。查询与写回在同一个事务里，因此不存在「查完之后
        // 用户又改了一次」的窗口。
        final List<SyncPendingChange> newer =
            await (_db.select(_db.syncPendingChanges)..where(
                  (SyncPendingChanges t) =>
                      t.revision.isBiggerThanValue(confirmedRevision),
                ))
                .get();
        final Set<String> dirtyDuringUpload = <String>{
          for (final SyncPendingChange row in newer)
            '${row.entityKind}\u0000${row.entityKey}\u0000${row.fieldName}',
        };

        // 订阅的 groupSyncId 要能解析到本机 id，否则跳过该字段（宁可少写一个分组归属，
        // 也不能把引用指向一行不存在的分组）。
        final Map<String, int> groupIdBySyncId = <String, int>{};
        for (final Group group in await _db.select(_db.groups).get()) {
          groupIdBySyncId[group.syncId] = group.id;
        }

        // 先分组后订阅：让本轮新建的分组可以被本轮新建的订阅引用。
        final List<SyncEntity> ordered =
            merged.allEntities.toList(growable: false)
              ..sort((SyncEntity a, SyncEntity b) {
                final int order = _kindOrder(a.kind)
                    .compareTo(_kindOrder(b.kind));
                if (order != 0) {
                  return order;
                }
                return a.key.compareTo(b.key);
              });

        for (final SyncEntity entity in ordered) {
          switch (entity.kind) {
            case SyncEntityKind.group:
              applied += await _applyGroup(
                entity: entity,
                groupIdBySyncId: groupIdBySyncId,
                dirtyDuringUpload: dirtyDuringUpload,
                preserved: preserved,
              );
            case SyncEntityKind.feed:
              final int result = await _applyFeed(
                entity: entity,
                groupIdBySyncId: groupIdBySyncId,
                dirtyDuringUpload: dirtyDuringUpload,
                preserved: preserved,
              );
              if (result == -1) {
                skipped++;
              } else {
                applied += result;
              }
            case SyncEntityKind.articleState:
              applied += await _applyArticleState(
                entity: entity,
                dirtyDuringUpload: dirtyDuringUpload,
                preserved: preserved,
              );
            case SyncEntityKind.setting:
              applied += await _applySetting(
                entity: entity,
                dirtyDuringUpload: dirtyDuringUpload,
                preserved: preserved,
              );
            case SyncEntityKind.newsRequiredSite:
              applied += await _applyRequiredSites(
                entity: entity,
                dirtyDuringUpload: dirtyDuringUpload,
                preserved: preserved,
              );
            case SyncEntityKind.newsListEntry:
              applied += await _applyNewsList(
                entity: entity,
                dirtyDuringUpload: dirtyDuringUpload,
                preserved: preserved,
              );
            case SyncEntityKind.newsPromptVersion:
              applied += await _applyPromptVersion(
                entity: entity,
                dirtyDuringUpload: dirtyDuringUpload,
                preserved: preserved,
              );
            default:
              // 未知类别：跳过而不是猜（将来新增实体时旧客户端不会误写）。
              skipped++;
          }
        }

        // 确认：只清 ≤ confirmedRevision 的待同步变更（架构 5.2）。
        confirmed =
            await (_db.delete(_db.syncPendingChanges)..where(
                  (SyncPendingChanges t) =>
                      t.revision.isSmallerOrEqualValue(confirmedRevision),
                ))
                .go();

        // 推进共同基线与成功时刻。修订号只增不回退：上传期间的新改动拿到的修订号更大，
        // 把它改小会让那些改动落在一个「已确认」的区间里，从此不再上传。
        final SyncStateRecord state = await _requireState();
        await (_db.update(_db.syncStateRecords)..where(
              (SyncStateRecords t) => t.id.equals(SyncStateRecords.singletonId),
            ))
            .write(
              SyncStateRecordsCompanion(
                baseVersion: Value<String?>(baseVersion),
                lastSyncedAt: Value<DateTime?>(syncedAt),
                localRevision: Value<int>(
                  state.localRevision > confirmedRevision
                      ? state.localRevision
                      : confirmedRevision,
                ),
              ),
            );
      });

      return Ok<SyncApplyOutcome>(
        SyncApplyOutcome(
          appliedCount: applied,
          preservedLocalFields: List<String>.unmodifiable(preserved),
          confirmedPendingCount: confirmed,
          skippedRemoteOnlyCount: skipped,
        ),
      );
    } on Exception catch (error, stackTrace) {
      return Err<SyncApplyOutcome>(
        StorageError(
          operation: 'sync.applyMergedSnapshot',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  // -------------------------------------------------------------------------
  // 类别写回
  // -------------------------------------------------------------------------

  Future<int> _applyGroup({
    required SyncEntity entity,
    required Map<String, int> groupIdBySyncId,
    required Set<String> dirtyDuringUpload,
    required List<String> preserved,
  }) async {
    final String? name = _string(entity, 'name');
    final int? sortOrder = _int(entity, 'sortOrder');
    final bool? pinned = _boolean(entity, 'pinned');
    final int? existing = groupIdBySyncId[entity.key];
    if (existing == null) {
      if (name == null) {
        return 0;
      }
      final int id = await _db
          .into(_db.groups)
          .insert(
            GroupsCompanion.insert(
              syncId: entity.key,
              name: name,
              sortOrder: Value<int>(sortOrder ?? 0),
              pinned: Value<bool>(pinned ?? false),
            ),
          );
      groupIdBySyncId[entity.key] = id;
      return 1;
    }
    final bool nameDirty = _dirty(entity, 'name', dirtyDuringUpload, preserved);
    final bool sortDirty = _dirty(
      entity,
      'sortOrder',
      dirtyDuringUpload,
      preserved,
    );
    final bool pinnedDirty = _dirty(
      entity,
      'pinned',
      dirtyDuringUpload,
      preserved,
    );
    final GroupsCompanion companion = GroupsCompanion(
      name: nameDirty || name == null
          ? const Value<String>.absent()
          : Value<String>(name),
      sortOrder: sortDirty || sortOrder == null
          ? const Value<int>.absent()
          : Value<int>(sortOrder),
      pinned: pinnedDirty || pinned == null
          ? const Value<bool>.absent()
          : Value<bool>(pinned),
    );
    if (companion.name.present ||
        companion.sortOrder.present ||
        companion.pinned.present) {
      await (_db.update(
        _db.groups,
      )..where((Groups t) => t.id.equals(existing))).write(companion);
      return 1;
    }
    return 0;
  }

  Future<int> _applyFeed({
    required SyncEntity entity,
    required Map<String, int> groupIdBySyncId,
    required Set<String> dirtyDuringUpload,
    required List<String> preserved,
  }) async {
    final Feed? existing =
        await (_db.select(_db.feeds)
              ..where((Feeds t) => t.syncId.equals(entity.key))
              ..limit(1))
            .getSingleOrNull();
    final String? name = _string(entity, 'name');
    final String? normalizedUrl = _string(entity, 'normalizedUrl');
    final String? groupSyncId = _string(entity, 'groupSyncId');
    // 远端带来一条本机没有的分组时**跳过整条订阅**（而不是编一个 groupId）：分组归属
    // 指向一行不存在的分组会让订阅在界面上凭空消失。skipped 计数让这件事可见。
    if (groupSyncId != null && !groupIdBySyncId.containsKey(groupSyncId)) {
      return -1;
    }
    if (existing == null) {
      if (name == null || normalizedUrl == null) {
        return -1;
      }
      // 本机已经有另一条订阅占着这个规范化地址（两台设备各自独立添加过同一个源、
      // 因而不是同一个 syncId）：**跳过**而不是硬插。
      //
      // 为什么必须是跳过：normalizedUrl 上有唯一索引（T013 的去重依据），硬插会抛约束
      // 错误，而错误发生在写回事务里，于是**整批**合并结果全部回滚——一条位置重复的订阅
      // 会让这轮同步连文章状态都写不进去。跳过的代价只是这一条等用户人工合并（T045 的
      // 对齐范围），skipped 计数让它在诊断里可见。
      final Feed? sameUrl =
          await (_db.select(_db.feeds)
                ..where((Feeds t) => t.normalizedUrl.equals(normalizedUrl))
                ..limit(1))
              .getSingleOrNull();
      if (sameUrl != null) {
        return -1;
      }
      await _db
          .into(_db.feeds)
          .insert(
            FeedsCompanion.insert(
              syncId: entity.key,
              normalizedUrl: normalizedUrl,
              name: name,
              sourceName: Value<String?>(_string(entity, 'sourceName')),
              groupId: Value<int?>(groupIdBySyncId[groupSyncId]),
              favorite: Value<bool>(_boolean(entity, 'favorite') ?? false),
              enabled: Value<bool>(_boolean(entity, 'enabled') ?? true),
              newsEnabled: Value<bool?>(_boolean(entity, 'newsEnabled')),
              refreshIntervalMinutes: Value<int?>(
                _int(entity, 'refreshIntervalMinutes'),
              ),
              sortOrder: Value<int>(_int(entity, 'sortOrder') ?? 0),
            ),
          );
      return 1;
    }

    final bool nameDirty = _dirty(entity, 'name', dirtyDuringUpload, preserved);
    final bool favoriteDirty = _dirty(
      entity,
      'favorite',
      dirtyDuringUpload,
      preserved,
    );
    final bool enabledDirty = _dirty(
      entity,
      'enabled',
      dirtyDuringUpload,
      preserved,
    );
    final bool newsEnabledDirty = _dirty(
      entity,
      'newsEnabled',
      dirtyDuringUpload,
      preserved,
    );
    final bool intervalDirty = _dirty(
      entity,
      'refreshIntervalMinutes',
      dirtyDuringUpload,
      preserved,
    );
    final bool sortDirty = _dirty(
      entity,
      'sortOrder',
      dirtyDuringUpload,
      preserved,
    );
    final bool groupDirty = _dirty(
      entity,
      'groupSyncId',
      dirtyDuringUpload,
      preserved,
    );
    await (_db.update(
      _db.feeds,
    )..where((Feeds t) => t.id.equals(existing.id))).write(
      FeedsCompanion(
        name: nameDirty || name == null
            ? const Value<String>.absent()
            : Value<String>(name),
        sourceName: Value<String?>(_string(entity, 'sourceName')),
        groupId: groupDirty
            ? const Value<int?>.absent()
            : Value<int?>(groupIdBySyncId[groupSyncId]),
        favorite: favoriteDirty
            ? const Value<bool>.absent()
            : Value<bool>(_boolean(entity, 'favorite') ?? existing.favorite),
        enabled: enabledDirty
            ? const Value<bool>.absent()
            : Value<bool>(_boolean(entity, 'enabled') ?? existing.enabled),
        newsEnabled: newsEnabledDirty
            ? const Value<bool?>.absent()
            : Value<bool?>(_boolean(entity, 'newsEnabled')),
        refreshIntervalMinutes: intervalDirty
            ? const Value<int?>.absent()
            : Value<int?>(_int(entity, 'refreshIntervalMinutes')),
        sortOrder: sortDirty
            ? const Value<int>.absent()
            : Value<int>(_int(entity, 'sortOrder') ?? existing.sortOrder),
        updatedAt: Value<DateTime>(DateTime.now().toUtc()),
      ),
    );
    return 1;
  }

  Future<int> _applyArticleState({
    required SyncEntity entity,
    required Set<String> dirtyDuringUpload,
    required List<String> preserved,
  }) async {
    final ReadingState? readingState = _readingStateOf(
      _string(entity, 'readingState'),
    );
    final bool? favorite = _boolean(entity, 'favorite');
    final Article? existing =
        await (_db.select(_db.articles)
              ..where((Articles t) => t.syncKey.equals(entity.key))
              ..limit(1))
            .getSingleOrNull();
    if (existing == null) {
      // **占位行**：状态落库、正文为空、身份依据 remote（T041 的语义）。
      if (readingState == null) {
        return 0;
      }
      await _db
          .into(_db.articles)
          .insert(
            ArticlesCompanion.insert(
              feedId: const Value<int?>(null),
              title: '',
              identityBasis: IdentityBasis.remote,
              readingState: Value<ReadingState>(readingState),
              favorite: Value<bool>(favorite ?? false),
              syncKey: Value<String?>(entity.key),
            ),
          );
      return 1;
    }
    final bool stateDirty = _dirty(
      entity,
      'readingState',
      dirtyDuringUpload,
      preserved,
    );
    final bool favoriteDirty = _dirty(
      entity,
      'favorite',
      dirtyDuringUpload,
      preserved,
    );
    // **只应用状态**：正文、标题、身份依据一律不动（远端没有正文，照搬会清空已抓取的全文）。
    await (_db.update(
      _db.articles,
    )..where((Articles t) => t.id.equals(existing.id))).write(
      ArticlesCompanion(
        readingState: stateDirty || readingState == null
            ? const Value<ReadingState>.absent()
            : Value<ReadingState>(readingState),
        favorite: favoriteDirty
            ? const Value<bool>.absent()
            : Value<bool>(favorite ?? existing.favorite),
        syncKey: existing.syncKey == null
            ? Value<String?>(entity.key)
            : const Value<String?>.absent(),
        updatedAt: Value<DateTime>(DateTime.now().toUtc()),
      ),
    );
    return 1;
  }

  Future<int> _applySetting({
    required SyncEntity entity,
    required Set<String> dirtyDuringUpload,
    required List<String> preserved,
  }) async {
    // 只写投影里确实纳入的编号：远端送来一个未注册或本机不纳入的编号时，写进去会造出
    // 一条设置页读不到、却参与下次同步的幽灵配置。
    if (!SyncProjection.includesSetting(entity.key)) {
      return 0;
    }
    if (_dirty(entity, 'value', dirtyDuringUpload, preserved)) {
      return 0;
    }
    if (!entity.hasField('value')) {
      return 0;
    }
    final Object? value = entity.fields['value'];
    final Result<void> valid = SettingsValidator.validate(
      SettingId(entity.key),
      value,
    );
    if (valid.isErr) {
      return 0;
    }
    await _db
        .into(_db.settings)
        .insertOnConflictUpdate(
          SettingsCompanion.insert(
            key: entity.key,
            value: SettingValueCodec.encode(value),
            updatedAt: Value<DateTime>(DateTime.now().toUtc()),
          ),
        );
    return 1;
  }

  Future<int> _applyRequiredSites({
    required SyncEntity entity,
    required Set<String> dirtyDuringUpload,
    required List<String> preserved,
  }) async {
    final Object? raw = entity.fields['sites'];
    if (raw is! List) {
      return 0;
    }
    if (_dirty(entity, 'sites', dirtyDuringUpload, preserved)) {
      return 0;
    }
    // 整体替换（有序列表按用户顺序整体写回，见 T036 的端口约定）。
    await _db.delete(_db.newsRequiredSiteRecords).go();
    int index = 0;
    for (final Object? item in raw) {
      if (item is! Map) {
        continue;
      }
      final Object? name = item['name'];
      final Object? url = item['url'];
      if (name is! String || url is! String) {
        continue;
      }
      await _db
          .into(_db.newsRequiredSiteRecords)
          .insert(
            NewsRequiredSiteRecordsCompanion.insert(
              name: name,
              url: url,
              enabled: Value<bool>(item['enabled'] == true),
              sortOrder: Value<int>(index++),
            ),
          );
    }
    return 1;
  }

  Future<int> _applyNewsList({
    required SyncEntity entity,
    required Set<String> dirtyDuringUpload,
    required List<String> preserved,
  }) async {
    if (!NewsListCategory.isKnown(entity.key)) {
      return 0;
    }
    final Object? raw = entity.fields['values'];
    if (raw is! List) {
      return 0;
    }
    if (_dirty(entity, 'values', dirtyDuringUpload, preserved)) {
      return 0;
    }
    await (_db.delete(
      _db.newsConfigEntryRecords,
    )..where((NewsConfigEntryRecords t) => t.kind.equals(entity.key))).go();
    int index = 0;
    for (final Object? item in raw) {
      if (item is! String) {
        continue;
      }
      await _db
          .into(_db.newsConfigEntryRecords)
          .insert(
            NewsConfigEntryRecordsCompanion.insert(
              kind: entity.key,
              value: item,
              sortOrder: index++,
            ),
          );
    }
    return 1;
  }

  Future<int> _applyPromptVersion({
    required SyncEntity entity,
    required Set<String> dirtyDuringUpload,
    required List<String> preserved,
  }) async {
    final String? language = _string(entity, 'language');
    final int? version = _int(entity, 'version');
    final String? mode = _string(entity, 'mode');
    final String? taskInstruction = _string(entity, 'taskInstruction');
    final String? outputSpec = _string(entity, 'outputSpec');
    final String? advancedPrompt = _string(entity, 'advancedPrompt');
    if (language == null ||
        version == null ||
        mode == null ||
        taskInstruction == null ||
        outputSpec == null ||
        advancedPrompt == null) {
      return 0;
    }
    if (!SyncProjection.newsPromptLanguages.contains(language)) {
      return 0;
    }
    if (_dirty(entity, 'taskInstruction', dirtyDuringUpload, preserved)) {
      return 0;
    }
    // prompt 版本**只增不改**（T036）：同一 (language, version) 已存在时不动它，
    // 否则一次同步会覆盖用户本机的历史版本。
    final NewsPromptVersionRecord? existing =
        await (_db.select(_db.newsPromptVersionRecords)
              ..where(
                (NewsPromptVersionRecords t) =>
                    t.language.equals(language) & t.version.equals(version),
              )
              ..limit(1))
            .getSingleOrNull();
    if (existing != null) {
      return 0;
    }
    await _db
        .into(_db.newsPromptVersionRecords)
        .insert(
          NewsPromptVersionRecordsCompanion.insert(
            language: language,
            version: version,
            mode: mode,
            taskInstruction: taskInstruction,
            outputSpec: outputSpec,
            advancedPrompt: advancedPrompt,
            note: Value<String?>(_string(entity, 'note')),
          ),
        );
    return 1;
  }

  // -------------------------------------------------------------------------
  // 内部工具
  // -------------------------------------------------------------------------

  Future<SyncStateRecord> _requireState() async {
    final SyncStateRecord? row =
        await (_db.select(_db.syncStateRecords)..where(
              (SyncStateRecords t) => t.id.equals(SyncStateRecords.singletonId),
            ))
            .getSingleOrNull();
    if (row == null) {
      throw StorageError(
        operation: 'sync.applyMergedSnapshot',
        detail: '缺少单行同步状态',
        isMissing: true,
      );
    }
    return row;
  }

  /// 写回顺序：分组 → 订阅 → 文章状态 → 设置 → 新闻规则。
  ///
  /// 顺序有意义：本轮新建的分组必须先落库，本轮新建的订阅才能引用到它。
  static int _kindOrder(String kind) => switch (kind) {
    SyncEntityKind.group => 0,
    SyncEntityKind.feed => 1,
    SyncEntityKind.articleState => 2,
    SyncEntityKind.setting => 3,
    SyncEntityKind.newsRequiredSite => 4,
    SyncEntityKind.newsListEntry => 5,
    SyncEntityKind.newsPromptVersion => 6,
    _ => 7,
  };

  /// 该字段是否被「上传期间的新改动」占着；是则记入 preserved 并返回 true。
  static bool _dirty(
    SyncEntity entity,
    String field,
    Set<String> dirtyDuringUpload,
    List<String> preserved,
  ) {
    final bool dirty = dirtyDuringUpload.contains(
      '${entity.kind}\u0000${entity.key}\u0000$field',
    );
    if (dirty) {
      preserved.add('${entity.kind}\u0000${entity.key}\u0000$field');
    }
    return dirty;
  }

  static void _put(
    Map<String, Map<String, SyncEntity>> entities,
    String kind,
    String key,
    Map<String, Object?> fields,
  ) {
    (entities[kind] ??= <String, SyncEntity>{})[key] = SyncEntity(
      kind: kind,
      key: key,
      fields: fields,
    );
  }

  static String? _string(SyncEntity entity, String field) {
    final Object? value = entity.fields[field];
    if (value is String && value.trim().isNotEmpty) {
      return value;
    }
    return null;
  }

  static int? _int(SyncEntity entity, String field) {
    final Object? value = entity.fields[field];
    return value is int ? value : null;
  }

  static bool? _boolean(SyncEntity entity, String field) {
    final Object? value = entity.fields[field];
    return value is bool ? value : null;
  }

  static ReadingState? _readingStateOf(String? name) {
    if (name == null) {
      return null;
    }
    for (final ReadingState state in ReadingState.values) {
      if (state.name == name) {
        return state;
      }
    }
    return null;
  }
}
