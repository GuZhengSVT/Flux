// T043：本机内容快照的读写与写回纪律（端口在 core/domain/sync_local_store.dart）。
//
// 五组用例，每一组对应一条实现纪律：
//   1) **投影决定字段清单**：读出去的字段与 T041 的投影一致，凭据/正文/设备项不出现；
//   2) **快照带着墓碑**：删除是长期事实，必须能随快照离机；
//   3) **上传期间的新改动必须留下**：更大的修订号 > 本轮上界时该字段不被写回；
//   4) **占位行不虚构正文**：远端状态落到本机没有的文章上时正文为空、身份依据 remote；
//   5) **写回不删业务行**：合并结果里没有的实体不会让本机删掉它（跨设备删除应用属 T045）。
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';

import 'package:flux/core/core.dart';
import 'package:flux/infrastructure/local/database.dart';
import 'package:flux/infrastructure/local/sync_local_store.dart';
import 'package:flux/infrastructure/local/tables/feed_tables.dart';
import 'package:flux/infrastructure/local/tables/news_tables.dart';

void main() {
  late AppDatabase db;
  late DriftSyncLocalStore store;

  setUp(() async {
    db = AppDatabase.memory();
    await db.customSelect('SELECT 1').get();
    store = DriftSyncLocalStore(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> seedFeed({
    required String syncId,
    required String name,
    bool favorite = false,
    bool enabled = true,
    String? url,
  }) => db
      .into(db.feeds)
      .insert(
        FeedsCompanion.insert(
          syncId: syncId,
          normalizedUrl: url ?? 'https://example.com/$syncId.xml',
          name: name,
          favorite: Value<bool>(favorite),
          enabled: Value<bool>(enabled),
        ),
      )
      .then((int _) {});

  group('读取：投影决定字段清单', () {
    test('订阅/分组/文章状态/新闻规则都被读进快照，且没有凭据与正文', () async {
      await seedFeed(syncId: 'feed.a', name: 'A', favorite: true);
      await db
          .into(db.articles)
          .insert(
            ArticlesCompanion.insert(
              title: '标题',
              identityBasis: IdentityBasis.guid,
              readingState: const Value<ReadingState>(ReadingState.later),
              favorite: const Value<bool>(true),
              syncKey: const Value<String?>('key-1'),
              body: const Value<String?>('正文不该进快照'),
              guid: const Value<String?>('guid-1'),
            ),
          );
      await db
          .into(db.newsRequiredSiteRecords)
          .insert(
            NewsRequiredSiteRecordsCompanion.insert(
              name: '必访站',
              url: 'https://must.example.com',
            ),
          );
      await db
          .into(db.newsConfigEntryRecords)
          .insert(
            NewsConfigEntryRecordsCompanion.insert(
              kind: NewsListCategory.keywords,
              value: '关键词',
              sortOrder: 0,
            ),
          );
      await db
          .into(db.settings)
          .insert(SettingsCompanion.insert(key: 'SET-010', value: 'true'));

      final SyncSnapshot snapshot = (await store.readLocalSnapshot()).unwrap();
      final String text = snapshot.encode();

      expect(snapshot.hasEntity(SyncEntityKind.feed, 'feed.a'), isTrue);
      expect(snapshot.entityCountOfKind(SyncEntityKind.group), greaterThan(0));
      expect(snapshot.hasEntity(SyncEntityKind.articleState, 'key-1'), isTrue);
      expect(
        snapshot.hasEntity(
          SyncEntityKind.newsRequiredSite,
          DriftSyncLocalStore.requiredSitesKey,
        ),
        isTrue,
      );
      expect(
        snapshot.hasEntity(
          SyncEntityKind.newsListEntry,
          NewsListCategory.keywords,
        ),
        isTrue,
      );
      expect(snapshot.hasEntity(SyncEntityKind.setting, 'SET-010'), isTrue);

      // 出境边界：正文、GUID、凭据、设备项都不在快照里。
      expect(text.contains('正文不该进快照'), isFalse);
      expect(text.contains('guid-1'), isFalse);
      expect(text.toLowerCase().contains('credentialref'), isFalse);
      expect(text.toLowerCase().contains('password'), isFalse);
      expect(text.contains('SET-070'), isFalse, reason: 'D 类设备项不纳入');
    });

    test('未存过的设置编号不进快照（不写 null 冒充「改成了 null」）', () async {
      final SyncSnapshot snapshot = (await store.readLocalSnapshot()).unwrap();
      expect(
        snapshot.hasEntity(SyncEntityKind.setting, SettingId.set001.code),
        isFalse,
      );
    });

    test('没有同步键的文章不参与状态同步', () async {
      await db
          .into(db.articles)
          .insert(
            ArticlesCompanion.insert(
              title: '无身份',
              identityBasis: IdentityBasis.fingerprint,
            ),
          );
      final SyncSnapshot snapshot = (await store.readLocalSnapshot()).unwrap();
      expect(snapshot.entityCountOfKind(SyncEntityKind.articleState), 0);
    });

    test('墓碑随快照出境（删除是长期事实）', () async {
      await db
          .into(db.syncTombstones)
          .insert(
            SyncTombstonesCompanion.insert(
              entityKind: SyncEntityKind.feed,
              entityKey: 'feed.gone',
              deletedAt: DateTime.utc(2026, 9, 22),
              revision: 3,
              displayName: const Value<String?>('删掉的源'),
            ),
          );
      final SyncSnapshot snapshot = (await store.readLocalSnapshot()).unwrap();
      expect(snapshot.hasDeletion(SyncEntityKind.feed, 'feed.gone'), isTrue);
      expect(snapshot.deletion(SyncEntityKind.feed, 'feed.gone')!.revision, 3);
    });
  });

  group('写回：合并结果落库', () {
    test('远端新增的订阅被写入，且与本地订阅共存', () async {
      final SyncSnapshot merged = SyncSnapshot.of(
        entities: <SyncEntity>[
          const SyncEntity(
            kind: SyncEntityKind.feed,
            key: 'feed.remote',
            fields: <String, Object?>{
              'syncId': 'feed.remote',
              'name': '远端源',
              'normalizedUrl': 'https://remote.example.com/feed.xml',
              'enabled': true,
              'favorite': true,
              'sortOrder': 0,
            },
          ),
        ],
      );
      final SyncApplyOutcome outcome = (await store.applyMergedSnapshot(
        merged: merged,
        confirmedRevision: 0,
        baseVersion: 'v-1',
        syncedAt: DateTime.utc(2026, 9, 22),
      )).unwrap();

      expect(outcome.appliedCount, greaterThan(0));
      final Feed row = (await db.select(db.feeds).get()).single;
      expect(row.syncId, 'feed.remote');
      expect(row.name, '远端源');
      expect(row.favorite, isTrue);
      // 基线推进。
      expect(
        (await db.select(db.syncStateRecords).get()).single.baseVersion,
        'v-1',
      );
    });

    test('远端内容里没有的实体**不会**被删除（未确认不清数据）', () async {
      await seedFeed(syncId: 'feed.local', name: '本机源');
      // 合并结果只含另一条订阅：本机这条不在其中（远端没报告它）。
      final SyncSnapshot merged = SyncSnapshot.of(
        entities: <SyncEntity>[
          const SyncEntity(
            kind: SyncEntityKind.feed,
            key: 'feed.other',
            fields: <String, Object?>{
              'syncId': 'feed.other',
              'name': '另一条',
              'normalizedUrl': 'https://other.example.com/feed.xml',
            },
          ),
        ],
      );
      await store.applyMergedSnapshot(
        merged: merged,
        confirmedRevision: 0,
        baseVersion: 'v-1',
        syncedAt: DateTime.utc(2026, 9, 22),
      );
      final List<Feed> feeds = await db.select(db.feeds).get();
      expect(feeds, hasLength(2), reason: '「没有报告」不是「删除」');
      expect(
        feeds.map((Feed f) => f.syncId),
        containsAll(<String>['feed.local', 'feed.other']),
      );
    });

    test('本机已有另一条订阅占着同一规范化地址时跳过（不整批回滚）', () async {
      await seedFeed(
        syncId: 'feed.mine',
        name: '本机的',
        url: 'https://same.example.com/feed.xml',
      );
      final SyncSnapshot merged = SyncSnapshot.of(
        entities: <SyncEntity>[
          const SyncEntity(
            kind: SyncEntityKind.feed,
            key: 'feed.theirs',
            fields: <String, Object?>{
              'syncId': 'feed.theirs',
              'name': '远端的同一个源',
              'normalizedUrl': 'https://same.example.com/feed.xml',
            },
          ),
          SyncEntity(
            kind: SyncEntityKind.setting,
            key: SettingId.set010.code,
            fields: <String, Object?>{'value': true},
          ),
        ],
      );
      final SyncApplyOutcome outcome = (await store.applyMergedSnapshot(
        merged: merged,
        confirmedRevision: 0,
        baseVersion: 'v-1',
        syncedAt: DateTime.utc(2026, 9, 22),
      )).unwrap();

      expect(outcome.skippedRemoteOnlyCount, 1);
      // 位置重复的那条被跳过，但**同一批**里的设置照常写入（事务没有整批回滚）。
      expect(await db.select(db.feeds).get(), hasLength(1));
      final List<Setting> settings = await db.select(db.settings).get();
      expect(settings, hasLength(1));
      expect(settings.single.key, SettingId.set010.code);
    });

    test('文章状态应用到本机已有文章：只改状态，不动正文与身份', () async {
      await db
          .into(db.articles)
          .insert(
            ArticlesCompanion.insert(
              title: '本机标题',
              identityBasis: IdentityBasis.guid,
              syncKey: const Value<String?>('key-1'),
              body: const Value<String?>('本机已抓到的正文'),
              guid: const Value<String?>('guid-1'),
            ),
          );
      final SyncSnapshot merged = SyncSnapshot.of(
        entities: <SyncEntity>[
          const SyncEntity(
            kind: SyncEntityKind.articleState,
            key: 'key-1',
            fields: <String, Object?>{
              'readingState': 'later',
              'favorite': true,
            },
          ),
        ],
      );
      await store.applyMergedSnapshot(
        merged: merged,
        confirmedRevision: 0,
        baseVersion: 'v-1',
        syncedAt: DateTime.utc(2026, 9, 22),
      );

      final Article row = (await db.select(db.articles).get()).single;
      expect(row.readingState, ReadingState.later);
      expect(row.favorite, isTrue);
      expect(row.body, '本机已抓到的正文', reason: '远端没有正文，不得清空本机全文');
      expect(row.title, '本机标题');
      expect(row.identityBasis, IdentityBasis.guid);
      expect(row.guid, 'guid-1');
    });

    test('本机没有那篇文章时落**占位行**：状态落库、正文为空、身份依据 remote', () async {
      final SyncSnapshot merged = SyncSnapshot.of(
        entities: <SyncEntity>[
          const SyncEntity(
            kind: SyncEntityKind.articleState,
            key: 'key.placeholder',
            fields: <String, Object?>{
              'readingState': 'read',
              'favorite': false,
            },
          ),
        ],
      );
      await store.applyMergedSnapshot(
        merged: merged,
        confirmedRevision: 0,
        baseVersion: 'v-1',
        syncedAt: DateTime.utc(2026, 9, 22),
      );

      final Article row = (await db.select(db.articles).get()).single;
      expect(row.syncKey, 'key.placeholder');
      expect(row.identityBasis, IdentityBasis.remote);
      expect(row.readingState, ReadingState.read);
      expect(row.body, isNull, reason: '不把不存在的文章虚构成全文');
      expect(row.title, isEmpty);
    });
  });

  group('上传期间的新改动必须留下（架构 5.2「仅确认已包含的修订」）', () {
    test('更大的修订号 > 本轮上界时，该字段不被写回且待同步行保留', () async {
      final int feedId = await db
          .into(db.feeds)
          .insert(
            FeedsCompanion.insert(
              syncId: 'feed.a',
              normalizedUrl: 'https://example.com/a.xml',
              name: '上传期间改的名字',
            ),
          );
      // 本轮固定的上界是 1。
      await db
          .into(db.syncPendingChanges)
          .insert(
            SyncPendingChangesCompanion.insert(
              entityKind: SyncEntityKind.feed,
              entityKey: 'feed.a',
              fieldName: const Value<String>('name'),
              revision: 5,
              changedAt: DateTime.utc(2026, 9, 22),
            ),
          );
      final SyncSnapshot merged = SyncSnapshot.of(
        entities: <SyncEntity>[
          const SyncEntity(
            kind: SyncEntityKind.feed,
            key: 'feed.a',
            fields: <String, Object?>{
              'syncId': 'feed.a',
              'name': '上传的旧名字',
              'normalizedUrl': 'https://example.com/a.xml',
            },
          ),
        ],
      );
      final SyncApplyOutcome outcome = (await store.applyMergedSnapshot(
        merged: merged,
        confirmedRevision: 1,
        baseVersion: 'v-1',
        syncedAt: DateTime.utc(2026, 9, 22),
      )).unwrap();

      final Feed row = await (db.select(
        db.feeds,
      )..where((Feeds t) => t.id.equals(feedId))).getSingle();
      expect(row.name, '上传期间改的名字', reason: '上传期间的新修改不得被旧值覆盖');
      expect(
        outcome.preservedLocalFields,
        contains('${SyncEntityKind.feed}\u0000feed.a\u0000name'),
      );
      // 待同步行仍然在（修订 5 > 1）。
      expect(await db.select(db.syncPendingChanges).get(), hasLength(1));
    });

    test('≤ 上界的待同步行被确认清除（不会留下已同步的脏行）', () async {
      await seedFeed(syncId: 'feed.a', name: 'A');
      await db
          .into(db.syncPendingChanges)
          .insert(
            SyncPendingChangesCompanion.insert(
              entityKind: SyncEntityKind.feed,
              entityKey: 'feed.a',
              fieldName: const Value<String>('name'),
              revision: 3,
              changedAt: DateTime.utc(2026, 9, 22),
            ),
          );
      final SyncApplyOutcome outcome = (await store.applyMergedSnapshot(
        merged: SyncSnapshot.empty,
        confirmedRevision: 3,
        baseVersion: 'v-1',
        syncedAt: DateTime.utc(2026, 9, 22),
      )).unwrap();

      expect(outcome.confirmedPendingCount, 1);
      expect(await db.select(db.syncPendingChanges).get(), isEmpty);
    });
  });

  group('新闻规则与设置写回', () {
    test('必访站列表整体替换（顺序即内容）', () async {
      final SyncSnapshot merged = SyncSnapshot.of(
        entities: <SyncEntity>[
          const SyncEntity(
            kind: SyncEntityKind.newsRequiredSite,
            key: DriftSyncLocalStore.requiredSitesKey,
            fields: <String, Object?>{
              'sites': <Object?>[
                <String, Object?>{
                  'name': '一',
                  'url': 'https://one.example.com',
                  'enabled': true,
                },
                <String, Object?>{
                  'name': '二',
                  'url': 'https://two.example.com',
                  'enabled': false,
                },
              ],
            },
          ),
        ],
      );
      await store.applyMergedSnapshot(
        merged: merged,
        confirmedRevision: 0,
        baseVersion: 'v-1',
        syncedAt: DateTime.utc(2026, 9, 22),
      );
      final List<NewsRequiredSiteRecord> rows =
          await (db.select(db.newsRequiredSiteRecords)
                ..orderBy(<OrderClauseGenerator<NewsRequiredSiteRecords>>[
                  (NewsRequiredSiteRecords t) => OrderingTerm.asc(t.sortOrder),
                ]))
              .get();
      expect(rows.map((NewsRequiredSiteRecord r) => r.name), <String>[
        '一',
        '二',
      ]);
      expect(rows.last.enabled, isFalse);
    });

    test('未注册编号的设置不写入（不造幽灵配置）', () async {
      final SyncSnapshot merged = SyncSnapshot.of(
        entities: <SyncEntity>[
          const SyncEntity(
            kind: SyncEntityKind.setting,
            key: 'SET-999',
            fields: <String, Object?>{'value': true},
          ),
          SyncEntity(
            kind: SyncEntityKind.setting,
            key: SettingId.set070.code,
            fields: <String, Object?>{'deviceName': 'x'},
          ),
        ],
      );
      await store.applyMergedSnapshot(
        merged: merged,
        confirmedRevision: 0,
        baseVersion: 'v-1',
        syncedAt: DateTime.utc(2026, 9, 22),
      );
      expect(await db.select(db.settings).get(), isEmpty);
    });
  });
}
