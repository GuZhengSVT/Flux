// T019+：v5 → v6 的真实增量迁移（文章表补卡片图片地址）。
//
// 这一次迁移是最简单的一类：加一条可空列。但正因为它简单，两件事必须真的验证，
// 而不是「列加上了就算过」：
//
//   1) **历史行不得被回填**。新列存的是「这张卡片的封面地址」，而历史行并没有这个
//      事实。用正文里可能存在的首图回填需要把全部正文重新解析一遍（T021 的范围），
//      而在这条迁移里做这件事会让一次升级变成一次全库解析。断言它为 null，就是在
//      钉住「缺失与空是两件事」——升级后旧文章回到「缺图不占位」的形态（架构第 7 节），
//      而不是显示一个空图框。
//
//   2) **既有列一个都不能丢**。加列迁移的典型事故不是崩溃，而是搬数据时漏了一列；
//      正文、三态、收藏、来源快照都在库里，丢了它们等于静默清空用户的阅读历史。
import 'package:drift/drift.dart' as drift;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flux/infrastructure/local/database.dart';
import 'package:flux/infrastructure/local/tables/article_tables.dart';
import 'package:flux/infrastructure/local/tables/enums.dart';

import '../../generated/schema.dart';
import '../../generated/schema_v5.dart' as v5;

/// 当前 schema 版本（与应用代码一致）。
const int currentSchemaVersion = 11;

void main() {
  drift.driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('v5 → 当前版本 增量迁移', () {
    test('带旧数据的 v5 库升级到 v6：图片列可空且为 null，其余列零丢失', () async {
      final SchemaVerifier verifier = SchemaVerifier(GeneratedHelper());
      final InitializedSchema schema = await verifier.schemaAt(5);

      final v5.DatabaseAtV5 old = v5.DatabaseAtV5(schema.newConnection());
      await old
          .into(old.groups)
          .insert(
            v5.GroupsCompanion.insert(
              syncId: 'group.uncategorized',
              name: '未分类',
              isReserved: const drift.Value<int>(1),
            ),
          );
      final int feedId = await old
          .into(old.feeds)
          .insert(
            v5.FeedsCompanion.insert(
              syncId: 'feed-v5',
              normalizedUrl: 'https://v5.example.com/feed.xml',
              name: '升级前的源',
            ),
          );
      final int unreadId = await old
          .into(old.articles)
          .insert(
            v5.ArticlesCompanion.insert(
              feedId: drift.Value<int?>(feedId),
              title: 'v5 未读文章',
              identityBasis: 'guid',
              guid: const drift.Value<String?>('v5-guid-1'),
              guidPresent: const drift.Value<int>(1),
              body: const drift.Value<String?>('v5 的正文'),
              bodyCompleteness: const drift.Value<String>('sourceBody'),
              bodyHash: const drift.Value<String?>('hash-v5'),
              summary: const drift.Value<String?>('v5 的摘要'),
              author: const drift.Value<String?>('作者'),
              publishedAt: const drift.Value<String?>(
                '2026-09-01T08:30:00.000Z',
              ),
            ),
          );
      final int detachedId = await old
          .into(old.articles)
          .insert(
            v5.ArticlesCompanion.insert(
              // feed_id 为 null：v5 起「保留收藏脱离源」的行就是这样。
              feedId: const drift.Value<int?>(null),
              feedTitle: const drift.Value<String?>('已删除的源'),
              feedUrl: const drift.Value<String?>(
                'https://gone.example.com/feed.xml',
              ),
              title: 'v5 脱离源的收藏',
              identityBasis: 'normalizedLink',
              normalizedLink: const drift.Value<String?>(
                'https://v5.example.com/a/2',
              ),
              readingState: const drift.Value<String>('later'),
              favorite: const drift.Value<int>(1),
            ),
          );
      await old.close();

      // v5 阶段不应有 v6 的新列。
      expect(
        schema.rawDatabase
            .select('PRAGMA table_info(articles)')
            .map((row) => row['name']! as String)
            .toSet(),
        isNot(contains('image_url')),
      );

      // --- 用应用的真实代码打开同一库，触发 v5 → v6 迁移 ----------------------
      final AppDatabase migrated = AppDatabase(schema.newConnection());
      await verifier.migrateAndValidate(migrated, currentSchemaVersion);

      // 1) 每一行都在，且每个既有列的值不变。
      final List<Article> articles = await migrated
          .select(migrated.articles)
          .get();
      expect(articles, hasLength(2), reason: '加列迁移不得丢行');
      final Article unread = articles.firstWhere(
        (Article a) => a.id == unreadId,
      );
      expect(unread.title, 'v5 未读文章');
      expect(unread.guid, 'v5-guid-1');
      expect(unread.body, 'v5 的正文');
      expect(unread.bodyCompleteness, BodyCompleteness.sourceBody);
      expect(unread.bodyHash, 'hash-v5');
      expect(unread.summary, 'v5 的摘要');
      expect(unread.author, '作者');
      expect(unread.publishedAt, DateTime.utc(2026, 9, 1, 8, 30));
      expect(unread.readingState, ReadingState.unread);

      final Article detached = articles.firstWhere(
        (Article a) => a.id == detachedId,
      );
      expect(detached.feedId, isNull, reason: '脱离源的行不得被重新绑回某个订阅');
      expect(detached.feedTitle, '已删除的源', reason: '来源快照必须保留');
      expect(detached.feedUrl, 'https://gone.example.com/feed.xml');
      expect(detached.readingState, ReadingState.later, reason: '三态不得被迁移改写');
      expect(detached.favorite, isTrue, reason: '收藏不得被迁移改写');

      // 2) 新列必须为 null：历史行没有「卡片封面」这个事实。
      for (final Article article in articles) {
        expect(article.imageUrl, isNull, reason: '不得回填历史行的图片地址（缺失与空是两件事）');
      }

      // 3) 新列可写可读：升级后新导入的文章要能真的把封面落库。
      await (migrated.update(
        migrated.articles,
      )..where((Articles t) => t.id.equals(unreadId))).write(
        const ArticlesCompanion(
          imageUrl: drift.Value<String?>('https://cdn.example.com/a.png'),
        ),
      );
      expect(
        (await (migrated.select(
          migrated.articles,
        )..where((Articles t) => t.id.equals(unreadId))).getSingle()).imageUrl,
        'https://cdn.example.com/a.png',
      );

      // 4) 既有实体不受影响。
      final Feed feed = (await migrated.select(migrated.feeds).get()).single;
      expect(feed.name, '升级前的源');

      await migrated.close();
      schema.close();
    });

    test('迁移后 user_version 推进到当前版本', () async {
      final SchemaVerifier verifier = SchemaVerifier(GeneratedHelper());
      final InitializedSchema schema = await verifier.schemaAt(5);

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
