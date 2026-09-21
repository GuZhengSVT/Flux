// T018：v4 → v5 的真实增量迁移（文章表支持「收藏脱离源」+ 删除事件表）。
//
// 这一次迁移与 T010/T013/T014 的加列迁移不同：它必须把 articles.feed_id 从 NOT NULL
// 改成可空，而 sqlite 改不了单列的约束。因此这里用 drift 的 alterTable
// （sqlite 官方推荐的 12 步重建：建临时表 → 搬数据 → 删旧表 → 改名 → 重建索引）。
//
// 于是本文件要证明的不是「列加上了」，而是更要紧的一件事：
//   重建流程没有丢数据。搬数据时任何一个忘记写 columnTransformer 的新列、或任何一次
//   「先 DROP 再 CREATE」的偷懒，都会在这些断言上暴露——而那种丢失的表现是用户升级后
//   发现文章、阅读状态与收藏全没了。
//
// 另一条与产品规则直接对应的断言：新列必须为 null，不得用**当前**源名回填。历史行
// 并没有「源已被删除」这个事实，回填会让 T047 的清理预览把没脱离源的文章也算进去。
import 'package:drift/drift.dart' as drift;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flux/infrastructure/local/database.dart';
import 'package:flux/infrastructure/local/tables/article_tables.dart';
import 'package:flux/infrastructure/local/tables/enums.dart';

import '../../generated/schema.dart';
import '../../generated/schema_v4.dart' as v4;

/// 当前 schema 版本（与应用代码一致）。
///
/// 本文件验证的是「v4 的库能升到**当前**版本」，因此终点跟着 [AppDatabase.schemaVersion]
/// 走（T019+ 起为 6），而不是停在 v5：一次从 v4 出发的升级实际会一路走到最新版本。
const int currentSchemaVersion = 7;

void main() {
  drift.driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('v4 → 当前版本 增量迁移', () {
    test('带旧数据的 v4 库升级到 v5：文章与状态零丢失、新列可空、删除表可用', () async {
      final SchemaVerifier verifier = SchemaVerifier(GeneratedHelper());
      final InitializedSchema schema = await verifier.schemaAt(4);

      final v4.DatabaseAtV4 old = v4.DatabaseAtV4(schema.newConnection());
      await old
          .into(old.groups)
          .insert(
            v4.GroupsCompanion.insert(
              syncId: 'group.uncategorized',
              name: '未分类',
              isReserved: const drift.Value<int>(1),
            ),
          );
      final int feedId = await old
          .into(old.feeds)
          .insert(
            v4.FeedsCompanion.insert(
              syncId: 'feed-v4',
              normalizedUrl: 'https://v4.example.com/feed.xml',
              name: '升级前的源',
              favorite: const drift.Value<int>(1),
              enabled: const drift.Value<int>(1),
            ),
          );
      final int unreadId = await old
          .into(old.articles)
          .insert(
            v4.ArticlesCompanion.insert(
              feedId: feedId,
              title: 'v4 未读文章',
              identityBasis: 'guid',
              guid: const drift.Value<String?>('v4-guid-1'),
              guidPresent: const drift.Value<int>(1),
              body: const drift.Value<String?>('v4 的正文'),
              bodyCompleteness: const drift.Value<String>('sourceBody'),
              bodyHash: const drift.Value<String?>('hash-v4'),
              summary: const drift.Value<String?>('v4 的摘要'),
              author: const drift.Value<String?>('作者'),
              // 生成的 v4 数据类按 build.yaml 的约定把时间存成 ISO-8601 文本。
              publishedAt: const drift.Value<String?>(
                '2026-09-01T08:30:00.000Z',
              ),
            ),
          );
      final int laterId = await old
          .into(old.articles)
          .insert(
            v4.ArticlesCompanion.insert(
              feedId: feedId,
              title: 'v4 稍后再读',
              identityBasis: 'normalizedLink',
              normalizedLink: const drift.Value<String?>(
                'https://v4.example.com/a/2',
              ),
              readingState: const drift.Value<String>('later'),
              favorite: const drift.Value<int>(1),
            ),
          );
      await old.close();

      // v4 阶段不应有 v5 的新列与新表。
      expect(
        schema.rawDatabase
            .select('PRAGMA table_info(articles)')
            .map((row) => row['name']! as String)
            .toSet(),
        isNot(contains('feed_title')),
      );
      expect(
        schema.rawDatabase
            .select(
              "SELECT name FROM sqlite_master WHERE type='table' "
              "AND name='deletion_events'",
            )
            .isEmpty,
        isTrue,
      );

      // --- 用应用的真实代码打开同一库，触发 v4 → v5 迁移 ----------------------
      final AppDatabase migrated = AppDatabase(schema.newConnection());
      await verifier.migrateAndValidate(migrated, currentSchemaVersion);

      // 1) 重建流程必须把每一行都搬过来，且每个既有列的值不变。
      final List<Article> articles = await migrated
          .select(migrated.articles)
          .get();
      expect(
        articles,
        hasLength(2),
        reason: 'alterTable 搬数据时不得丢行（这是本次迁移最危险的地方）',
      );
      final Article unread = articles.firstWhere(
        (Article a) => a.id == unreadId,
      );
      expect(unread.title, 'v4 未读文章');
      expect(unread.guid, 'v4-guid-1');
      expect(unread.body, 'v4 的正文');
      expect(unread.bodyCompleteness, BodyCompleteness.sourceBody);
      expect(unread.bodyHash, 'hash-v4');
      expect(unread.summary, 'v4 的摘要');
      expect(unread.author, '作者');
      expect(unread.publishedAt, DateTime.utc(2026, 9, 1, 8, 30));
      expect(unread.feedId, feedId, reason: '未脱离源的行仍指向原订阅');
      expect(unread.readingState, ReadingState.unread);

      final Article later = articles.firstWhere((Article a) => a.id == laterId);
      expect(later.readingState, ReadingState.later, reason: '三态不得被迁移改写');
      expect(later.favorite, isTrue, reason: '收藏不得被迁移改写');
      expect(later.identityBasis, IdentityBasis.normalizedLink);
      expect(later.normalizedLink, 'https://v4.example.com/a/2');

      // 2) 新列必须为 null：历史行没有「源已被删除」这个事实，回填等于伪造快照。
      for (final Article article in articles) {
        expect(
          article.feedTitle,
          isNull,
          reason: '不得用当前源名回填历史行（那会让清理预览误判已脱离源）',
        );
        expect(article.feedUrl, isNull);
      }

      // 3) feed_id 现在确实可空（这是本迁移唯一改约束的地方，必须真验证）。
      await (migrated.update(migrated.articles)
            ..where((Articles t) => t.id.equals(unreadId)))
          .write(const ArticlesCompanion(feedId: drift.Value<int?>(null)));
      expect(
        (await (migrated.select(
          migrated.articles,
        )..where((Articles t) => t.id.equals(unreadId))).getSingle()).feedId,
        isNull,
      );

      // 4) 删除事件表与它的索引都真的建出来了（createTable 不会顺带建索引）。
      await migrated
          .into(migrated.deletionEvents)
          .insert(
            DeletionEventsCompanion.insert(
              entityType: 'feed',
              syncId: 'feed-v4',
              displayName: '升级前的源',
              keepFavorites: const drift.Value<bool?>(true),
              deletedArticleCount: const drift.Value<int>(3),
              keptFavoriteCount: const drift.Value<int>(1),
              deletedAt: DateTime.utc(2026, 9, 21, 12),
            ),
          );
      final List<DeletionEvent> stored = await migrated
          .select(migrated.deletionEvents)
          .get();
      expect(stored, hasLength(1));
      expect(stored.single.syncId, 'feed-v4');
      expect(stored.single.keepFavorites, isTrue);
      expect(stored.single.deletedArticleCount, 3);
      expect(stored.single.keptFavoriteCount, 1);
      expect(
        schema.rawDatabase
            .select(
              "SELECT name FROM sqlite_master WHERE type='index' "
              "AND name IN ('ix_deletion_events_sync_id', "
              "'ix_deletion_events_deleted_at')",
            )
            .length,
        2,
      );

      // 5) 既有实体（分组/订阅）不受影响。
      final Feed feed = (await migrated.select(migrated.feeds).get()).single;
      expect(feed.name, '升级前的源');
      expect(feed.favorite, isTrue);
      expect(feed.enabled, isTrue);

      await migrated.close();
      schema.close();
    });

    test('迁移后 user_version 推进到当前版本', () async {
      final SchemaVerifier verifier = SchemaVerifier(GeneratedHelper());
      final InitializedSchema schema = await verifier.schemaAt(4);

      final AppDatabase migrated = AppDatabase(schema.newConnection());
      await verifier.migrateAndValidate(migrated, currentSchemaVersion);

      final drift.QueryRow row = await migrated
          .customSelect('PRAGMA user_version')
          .getSingle();
      expect(row.read<int>('user_version'), currentSchemaVersion);

      await migrated.close();
      schema.close();
    });
  });
}
