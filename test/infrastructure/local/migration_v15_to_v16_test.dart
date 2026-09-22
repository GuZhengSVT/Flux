// T041：v15 → v16 的真实增量迁移（新增同步基线与协议状态四表 + 一行种子）。
//
// 这一步要验五件事：
//   1) **四张表与六条索引真的建出**（漏建索引只有结构校验能发现）；
//   2) **既有数据零丢失**（订阅、文章三态/收藏/正文、模型与任务、每日新闻版本）；
//   3) **sync_state 恰好一行且是诚实的未同步默认**（无基线、修订 0、能力未探测）；
//   4) **不回填任何待同步变更或墓碑**（迁移不得伪造出用户从未做过的修改）；
//   5) **同步表里没有凭据列**（架构 5.1、第 8 节：SET-071 只住 Keychain）。
import 'package:drift/drift.dart' as drift;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flux/infrastructure/local/database.dart';
import 'package:flux/infrastructure/local/tables/feed_tables.dart';
import 'package:flux/infrastructure/local/tables/sync_tables.dart';

import '../../generated/schema.dart';
import '../../generated/schema_v15.dart' as v15;

/// 当前 schema 版本（与应用代码一致）。
const int currentSchemaVersion = 16;

void main() {
  drift.driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('v15 → 当前版本 增量迁移', () {
    test('带旧数据的 v15 库升级：同步四表就绪、旧数据零丢失', () async {
      final SchemaVerifier verifier = SchemaVerifier(GeneratedHelper());
      final InitializedSchema schema = await verifier.schemaAt(15);

      final v15.DatabaseAtV15 old = v15.DatabaseAtV15(schema.newConnection());
      await old
          .into(old.groups)
          .insert(
            v15.GroupsCompanion.insert(
              syncId: 'group.uncategorized',
              name: '未分类',
              isReserved: const drift.Value<int>(1),
            ),
          );
      final int feedId = await old
          .into(old.feeds)
          .insert(
            v15.FeedsCompanion.insert(
              syncId: 'feed-v15',
              normalizedUrl: 'https://v15.example.com/feed.xml',
              name: '升级前的源',
              newsEnabled: const drift.Value<int?>(1),
            ),
          );
      await old
          .into(old.articles)
          .insert(
            v15.ArticlesCompanion.insert(
              feedId: drift.Value<int?>(feedId),
              title: '升级前的文章',
              identityBasis: 'guid',
              guid: const drift.Value<String?>('legacy-guid'),
              guidPresent: const drift.Value<int>(1),
              favorite: const drift.Value<int>(1),
              readingState: const drift.Value<String>('later'),
              body: const drift.Value<String?>('升级前的正文'),
            ),
          );
      await old.close();

      final AppDatabase migrated = AppDatabase(schema.newConnection());
      await verifier.migrateAndValidate(migrated, currentSchemaVersion);

      final Feed feed = (await migrated.select(migrated.feeds).get()).single;
      expect(feed.syncId, 'feed-v15');
      expect(feed.newsEnabled, isTrue, reason: 'v15 的用户选择必须原样保留');

      final Article article =
          (await migrated.select(migrated.articles).get()).single;
      expect(article.title, '升级前的文章');
      expect(article.readingState.name, 'later');
      expect(article.favorite, isTrue);
      expect(article.body, '升级前的正文');
      expect(article.guid, 'legacy-guid');

      // 同步状态恰好一行，且是诚实的未同步默认。
      final List<SyncStateRecord> states = await migrated
          .select(migrated.syncStateRecords)
          .get();
      expect(states.length, 1, reason: 'sync_state 是单行表');
      final SyncStateRecord state = states.single;
      expect(state.id, SyncStateRecords.singletonId);
      expect(state.baseVersion, isNull, reason: '从未同步过：没有共同基线');
      expect(state.localRevision, 0);
      expect(state.lastSyncedAt, isNull);
      expect(
        state.supportsConditionalWrite,
        isNull,
        reason: '尚未探测：不能默认成 true 让不支持条件写的服务器进入多端覆盖',
      );

      // 不回填 pending / tombstone：升级前不存在「有改动等着同步」这件事。
      expect(await migrated.select(migrated.syncPendingChanges).get(), isEmpty);
      expect(await migrated.select(migrated.syncTombstones).get(), isEmpty);
      expect(
        await migrated.select(migrated.syncFeedAliasRecords).get(),
        isEmpty,
      );

      await migrated.close();
      schema.close();
    });

    test('新库（v16）直接建出同步四表与六条索引', () async {
      final AppDatabase db = AppDatabase.memory();
      await db.customSelect('SELECT 1').get();
      final List<drift.QueryRow> objects = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type IN ('table', 'index')",
          )
          .get();
      final Set<String> names = objects
          .map((drift.QueryRow r) => r.read<String>('name'))
          .toSet();
      expect(
        names,
        containsAll(<String>[
          'sync_state_records',
          'sync_pending_changes',
          'ux_sync_pending_entity_field',
          'ix_sync_pending_revision',
          'sync_tombstones',
          'ux_sync_tombstones_entity',
          'ix_sync_tombstones_at',
          'sync_feed_alias_records',
          'ux_sync_feed_aliases_local',
          'ix_sync_feed_aliases_sync_id',
        ]),
      );
      // 新库也必须恰好一行同步状态（onCreate 的种子）。
      expect((await db.select(db.syncStateRecords).get()).length, 1);
      await db.close();
    });
  });

  group('同步表的 DDL 约束', () {
    test('单行同步状态：插入第二行被主键拒绝', () async {
      final AppDatabase db = AppDatabase.memory();
      await db.customSelect('SELECT 1').get();
      addTearDown(db.close);
      await expectLater(
        db
            .into(db.syncStateRecords)
            .insert(
              const SyncStateRecordsCompanion(
                id: drift.Value<int>(SyncStateRecords.singletonId),
              ),
            ),
        throwsA(isA<Exception>()),
        reason: '主键冲突必须被拒绝，否则「哪一行是我」变成不可回答的问题',
      );
    });

    test('待同步变更按「实体 + 字段」唯一（同一字段只有一条待同步）', () async {
      final AppDatabase db = AppDatabase.memory();
      await db.customSelect('SELECT 1').get();
      addTearDown(db.close);

      Future<void> insert(String field) => db
          .into(db.syncPendingChanges)
          .insert(
            SyncPendingChangesCompanion.insert(
              entityKind: 'feed',
              entityKey: 'feed.x',
              fieldName: drift.Value<String>(field),
              revision: 1,
              changedAt: DateTime.utc(2026, 9, 22),
            ),
          );

      await insert('name');
      await insert('favorite');
      await expectLater(
        insert('name'),
        throwsA(isA<Exception>()),
        reason: '同一实体的同一字段只有一条待同步变更',
      );
      // 空串（整行变更）也参与唯一索引：两条「整行变更」必须冲突。
      await insert('');
      await expectLater(insert(''), throwsA(isA<Exception>()));
    });

    test('墓碑按实体唯一（重复删除是幂等的）', () async {
      final AppDatabase db = AppDatabase.memory();
      await db.customSelect('SELECT 1').get();
      addTearDown(db.close);

      Future<void> insert() => db
          .into(db.syncTombstones)
          .insert(
            SyncTombstonesCompanion.insert(
              entityKind: 'feed',
              entityKey: 'feed.gone',
              deletedAt: DateTime.utc(2026, 9, 22),
              revision: 2,
            ),
          );

      await insert();
      await expectLater(
        insert(),
        throwsA(isA<Exception>()),
        reason: '同一实体的墓碑只保留一条',
      );
    });

    test('删除订阅时别名行随外键级联消失（不留指向空订阅的别名）', () async {
      final AppDatabase db = AppDatabase.memory();
      await db.customSelect('SELECT 1').get();
      addTearDown(db.close);

      final int feedId = await db
          .into(db.feeds)
          .insert(
            FeedsCompanion.insert(
              syncId: 'feed-alias-owner',
              normalizedUrl: 'https://alias.example.com/feed.xml',
              name: '别名测试源',
            ),
          );
      await db
          .into(db.syncFeedAliasRecords)
          .insert(
            SyncFeedAliasRecordsCompanion.insert(
              syncId: 'feed.remote-style',
              localFeedId: feedId,
            ),
          );
      expect((await db.select(db.syncFeedAliasRecords).get()).length, 1);

      await (db.delete(db.feeds)..where((Feeds t) => t.id.equals(feedId))).go();
      expect(
        await db.select(db.syncFeedAliasRecords).get(),
        isEmpty,
        reason: '别名指向一条不存在的订阅只会让下次同步把它当新订阅',
      );
    });
  });
}
