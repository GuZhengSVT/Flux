// T013 建立、T014 更新为「v2 → 当前版本」的真实增量迁移。
//
// 与 migration_v1_to_v2_test.dart 分工相同：
//   - 用 drift 从 drift_schemas/ 快照生成的 v2 schema 建一个**带旧数据**的库，
//     跑应用的真实 MigrationStrategy，再由 SchemaVerifier 逐列比对结构；
//   - 旧数据完好性用「迁移后读取」衡量：迁移必然写文件，关键不是字节不变，而是
//     订阅的名称/分组/加精/条件请求缓存与文章的阅读状态、收藏都还在且值未变。
//
// 为什么这一步必须单独测：两次迁移都是**加列**迁移，最容易出的错不是崩溃而是
// 「列加上了但没回填成正确的默认值」。这里两个具体形态：
//   - v2→v3 的抓取诊断列必须保持 null（尚未检查），不得用当前时间伪造检查记录；
//   - v3→v4 的 enabled 列必须回填为 **true**，否则升级后所有订阅的自动刷新会静默
//     停摆，而界面上只是「关」而已，没有任何线索指向这次迁移。
//
// 不写死终点版本：T014 把版本提到 4 之后，停在 3 的用例就不再验证真实路径。
import 'package:drift/drift.dart' as drift;
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flux/infrastructure/local/database.dart';
import 'package:flux/infrastructure/local/tables/enums.dart';
import 'package:flux/infrastructure/local/tables/feed_tables.dart';

import '../../generated/schema.dart';
import '../../generated/schema_v2.dart' as v2;

/// 当前 schema 版本（与应用代码一致）。见本文件顶部关于「不写死终点版本」的说明。
const int currentSchemaVersion = 13;

void main() {
  drift.driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('v2 → 当前版本 增量迁移', () {
    test('带旧数据的 v2 库升级到当前版本：结构正确且旧数据完好', () async {
      final SchemaVerifier verifier = SchemaVerifier(GeneratedHelper());
      final InitializedSchema schema = await verifier.schemaAt(2);

      // --- 用 v2 视角写入「升级前就存在」的数据 ------------------------------
      final v2.DatabaseAtV2 old = v2.DatabaseAtV2(schema.newConnection());

      await old
          .into(old.groups)
          .insert(
            v2.GroupsCompanion.insert(
              syncId: 'group.uncategorized',
              name: '未分类',
              isReserved: const drift.Value<int>(1),
            ),
          );
      final int feedId = await old
          .into(old.feeds)
          .insert(
            v2.FeedsCompanion.insert(
              syncId: 'feed-v2',
              normalizedUrl: 'https://v2.example.com/feed.xml',
              name: '升级前的源',
              sourceName: const drift.Value<String?>('V2 源名'),
              favorite: const drift.Value<int>(1),
              refreshIntervalMinutes: const drift.Value<int?>(30),
              httpEtag: const drift.Value<String?>('"etag-v2"'),
              httpLastModified: const drift.Value<String?>(
                'Mon, 21 Sep 2026 04:00:00 GMT',
              ),
              credentialRef: const drift.Value<String?>('cred-v2'),
            ),
          );
      final int articleId = await old
          .into(old.articles)
          .insert(
            v2.ArticlesCompanion.insert(
              feedId: feedId,
              title: 'v2 时期的文章',
              identityBasis: 'guid',
              guid: const drift.Value<String?>('v2-guid'),
              guidPresent: const drift.Value<int>(1),
              body: const drift.Value<String?>('v2 时期的正文'),
              readingState: const drift.Value<String>('later'),
              favorite: const drift.Value<int>(1),
            ),
          );
      // v2 库里也应有一条设置项（T010 的表）。
      await old
          .into(old.settings)
          .insert(v2.SettingsCompanion.insert(key: 'SET-002', value: '"dark"'));
      await old.close();

      // v2 阶段不应有后续版本新增的列（v3 的抓取诊断、v4 的 enabled）。
      final Set<String> v2FeedColumns = schema.rawDatabase
          .select('PRAGMA table_info(feeds)')
          .map((sqlite.Row row) => row['name']! as String)
          .toSet();
      expect(v2FeedColumns, isNot(contains('last_checked_at')));
      expect(v2FeedColumns, isNot(contains('enabled')));

      // --- 用应用的真实代码打开同一库，触发 v2 → 当前版本 迁移 ----------------
      final AppDatabase migrated = AppDatabase(schema.newConnection());
      await verifier.migrateAndValidate(migrated, currentSchemaVersion);

      // 结构：drift 已逐列比对；这里再确认新列可查询且默认是 null。
      final Feed feed = (await migrated.select(migrated.feeds).get()).single;
      expect(
        feed.lastCheckedAt,
        isNull,
        reason: '新列必须保持 null（尚未检查），不得用当前时间伪造一次检查记录',
      );
      expect(feed.lastRefreshResult, isNull);
      expect(feed.lastRefreshErrorKind, isNull);
      // v3→v4 的 enabled 列必须回填为 true：升级前就存在的订阅要继续参与自动刷新。
      expect(
        feed.enabled,
        isTrue,
        reason: 'enabled 必须回填 true，否则升级会让所有订阅静默停止刷新',
      );

      // 旧数据完好：分组、订阅的全部既有列、文章的状态与收藏、设置项都保持原值。
      final List<Group> groups = await migrated.select(migrated.groups).get();
      expect(groups, hasLength(1));
      expect(groups.single.isReserved, isTrue);

      final List<Feed> feeds = await migrated.select(migrated.feeds).get();
      expect(feeds, hasLength(1));
      expect(feeds.single.id, feedId);
      expect(feeds.single.syncId, 'feed-v2');
      expect(feeds.single.name, '升级前的源');
      expect(feeds.single.sourceName, 'V2 源名');
      expect(feeds.single.favorite, isTrue, reason: '迁移不得改写加精');
      expect(feeds.single.refreshIntervalMinutes, 30);
      expect(feeds.single.httpEtag, '"etag-v2"', reason: '条件请求缓存必须保留');
      expect(feeds.single.httpLastModified, 'Mon, 21 Sep 2026 04:00:00 GMT');
      expect(feeds.single.credentialRef, 'cred-v2');

      final Article article = await migrated
          .select(migrated.articles)
          .getSingle();
      expect(article.id, articleId);
      expect(article.body, 'v2 时期的正文');
      expect(article.readingState, ReadingState.later);
      expect(article.favorite, isTrue);

      final Setting setting = await migrated
          .select(migrated.settings)
          .getSingle();
      expect(setting.key, 'SET-002');
      expect(setting.value, '"dark"');

      await migrated.close();
      schema.close();
    });

    test('迁移后 user_version 推进到当前版本', () async {
      final SchemaVerifier verifier = SchemaVerifier(GeneratedHelper());
      final InitializedSchema schema = await verifier.schemaAt(2);

      final AppDatabase migrated = AppDatabase(schema.newConnection());
      await verifier.migrateAndValidate(migrated, currentSchemaVersion);

      final drift.QueryRow row = await migrated
          .customSelect('PRAGMA user_version')
          .getSingle();
      expect(row.read<int>('user_version'), currentSchemaVersion);

      await migrated.close();
      schema.close();
    });

    test('新列可写可读（抓取诊断真的能落库，而不只是列存在）', () async {
      final AppDatabase db = AppDatabase.memory();
      await db.customSelect('SELECT 1').get();
      final int feedId = await db
          .into(db.feeds)
          .insert(
            FeedsCompanion.insert(
              syncId: 'feed-diag',
              normalizedUrl: 'https://diag.example.com/feed.xml',
              name: '诊断源',
            ),
          );

      await (db.update(
        db.feeds,
      )..where((Feeds t) => t.id.equals(feedId))).write(
        FeedsCompanion(
          lastCheckedAt: drift.Value<DateTime?>(DateTime.utc(2026, 9, 21, 12)),
          lastRefreshResult: const drift.Value<String?>('notModified'),
          lastRefreshErrorKind: const drift.Value<String?>(null),
        ),
      );

      final Feed stored = (await db.select(db.feeds).get()).single;
      expect(stored.lastCheckedAt, DateTime.utc(2026, 9, 21, 12));
      expect(stored.lastRefreshResult, 'notModified');
      expect(stored.lastRefreshErrorKind, isNull);

      await db.close();
    });
  });
}
