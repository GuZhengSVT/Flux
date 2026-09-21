// T022：v6 → v7 的真实增量迁移（新增全文检索索引与同步触发器）。
//
// 这一步要验的不是「表建出来了」，而是三件容易出错的事：
//   1) **历史文章必须被灌进索引**。触发器只对**此后**的写入生效，升级前库里已有的
//      文章不会自己出现在索引里——漏掉那一步 rebuild，用户升级后搜自己的历史文章会是
//      零结果，而界面上完全没有线索指向这次迁移；
//   2) **既有数据一个都不能丢**（正文、三态、收藏、来源快照）；
//   3) **触发器此后真的在工作**（新增/改标题/删除都能反映到索引）。
//
// 中文检索的行为由 article_search_store_test 与 article_search_test 覆盖；这里只钉住
// 「迁移」这条路径。
library;

import 'package:drift/drift.dart' as drift;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flux/infrastructure/local/database.dart';
import 'package:flux/infrastructure/local/tables/enums.dart';

import '../../generated/schema.dart';
import '../../generated/schema_v6.dart' as v6;

/// 当前 schema 版本（与应用代码一致）。
const int currentSchemaVersion = 14;

void main() {
  drift.driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('v6 → 当前版本 增量迁移', () {
    test('带旧数据的 v6 库升级到 v7：检索索引就绪、旧数据零丢失', () async {
      final SchemaVerifier verifier = SchemaVerifier(GeneratedHelper());
      final InitializedSchema schema = await verifier.schemaAt(6);

      final v6.DatabaseAtV6 old = v6.DatabaseAtV6(schema.newConnection());
      final int feedId = await old
          .into(old.feeds)
          .insert(
            v6.FeedsCompanion.insert(
              syncId: 'feed-v6',
              normalizedUrl: 'https://v6.example.com/feed.xml',
              name: '升级前的源',
            ),
          );
      final int unreadId = await old
          .into(old.articles)
          .insert(
            v6.ArticlesCompanion.insert(
              feedId: drift.Value<int?>(feedId),
              title: '升级前的离线阅读文章',
              identityBasis: 'guid',
              guid: const drift.Value<String?>('g-unread'),
              guidPresent: const drift.Value<int>(1),
              body: const drift.Value<String?>('正文讲离线阅读的实现细节。'),
              summary: const drift.Value<String?>('摘要提到离线'),
            ),
          );
      final int favoriteId = await old
          .into(old.articles)
          .insert(
            v6.ArticlesCompanion.insert(
              feedId: drift.Value<int?>(feedId),
              title: '升级前的另一篇',
              identityBasis: 'guid',
              guid: const drift.Value<String?>('g-fav'),
              guidPresent: const drift.Value<int>(1),
              favorite: const drift.Value<int>(1),
              readingState: const drift.Value<String>('later'),
            ),
          );
      await old.close();

      final AppDatabase migrated = AppDatabase(schema.newConnection());
      await verifier.migrateAndValidate(migrated, currentSchemaVersion);

      // 1) 索引就绪：历史文章已经可以被搜到（rebuild 生效）。
      final List<drift.QueryRow> hit = await migrated
          .customSelect(
            // fts5 的短语用**单引号**包裹在 SQL 字符串里（双引号在 SQL 里是标识符，
            // 不是字符串）。外层因此用双引号 Dart 字符串。
            // ignore: prefer_single_quotes
            "SELECT COUNT(*) AS c FROM articles_fts "
            "WHERE articles_fts MATCH '\"离线阅\"'",
          )
          .get();
      expect(hit.single.read<int>('c'), 1, reason: '历史文章必须已被灌入索引');

      // 两字中文沿 LIKE 路径（trigram 的语义，见 domain 说明）。
      final List<drift.QueryRow> shortHit = await migrated
          .customSelect(
            "SELECT COUNT(*) AS c FROM articles_fts WHERE body LIKE '%离线%'",
          )
          .get();
      expect(shortHit.single.read<int>('c'), 1);

      // 2) 旧数据零丢失。
      final List<Article> rows = await migrated.select(migrated.articles).get();
      expect(rows, hasLength(2));
      final Article unread = rows.firstWhere((Article a) => a.id == unreadId);
      expect(unread.title, '升级前的离线阅读文章');
      expect(unread.body, '正文讲离线阅读的实现细节。');
      expect(unread.readingState, ReadingState.unread);
      expect(unread.favorite, isFalse);
      final Article fav = rows.firstWhere((Article a) => a.id == favoriteId);
      expect(fav.favorite, isTrue, reason: '收藏不得被迁移改写');
      expect(fav.readingState, ReadingState.later, reason: 'later 不得被迁移改写');

      await migrated.close();
    });

    test('升级后触发器开始工作（新增/改标题/删除都反映到索引）', () async {
      final SchemaVerifier verifier = SchemaVerifier(GeneratedHelper());
      final InitializedSchema schema = await verifier.schemaAt(6);
      final v6.DatabaseAtV6 old = v6.DatabaseAtV6(schema.newConnection());
      final int feedId = await old
          .into(old.feeds)
          .insert(
            v6.FeedsCompanion.insert(
              syncId: 'feed-v6b',
              normalizedUrl: 'https://v6b.example.com/feed.xml',
              name: '源',
            ),
          );
      await old.close();

      final AppDatabase db = AppDatabase(schema.newConnection());
      await verifier.migrateAndValidate(db, currentSchemaVersion);

      Future<int> count(String phrase) async {
        final List<drift.QueryRow> rows = await db
            .customSelect(
              'SELECT COUNT(*) AS c FROM articles_fts WHERE articles_fts MATCH ?',
              variables: <drift.Variable<Object>>[
                drift.Variable<Object>('"$phrase"'),
              ],
            )
            .get();
        return rows.single.read<int>('c');
      }

      // 新增：升级后写入的文章必须立即入索引。
      final int id = await db
          .into(db.articles)
          .insert(
            ArticlesCompanion.insert(
              feedId: drift.Value<int?>(feedId),
              title: '升级后的新文章',
              identityBasis: IdentityBasis.guid,
              guid: const drift.Value<String?>('g-new'),
              guidPresent: const drift.Value<bool>(true),
              body: const drift.Value<String?>('正文提到离线缓存策略。'),
            ),
          );
      expect(await count('离线缓存'), 1);

      // 改标题：旧词消失、新词出现。
      await (db.update(
        db.articles,
      )..where(($ArticlesTable a) => a.id.equals(id))).write(
        const ArticlesCompanion(title: drift.Value<String>('替换后的标题文本')),
      );
      expect(await count('升级后的新'), 0, reason: '旧标题必须从索引里消失');
      expect(await count('替换后的标'), 1);

      // 删除：索引项一并删除。
      await (db.delete(
        db.articles,
      )..where(($ArticlesTable a) => a.id.equals(id))).go();
      expect(await count('替换后的标'), 0);

      // 完整性自洽（因触发器写入不一致时会抛异常）。
      await db.customStatement(
        "INSERT INTO articles_fts(articles_fts) VALUES('integrity-check')",
      );

      await db.close();
    });

    test('空库升级同样成功（没有历史文章也要建出索引结构）', () async {
      final SchemaVerifier verifier = SchemaVerifier(GeneratedHelper());
      final AppDatabase db = AppDatabase.memory();
      await verifier.migrateAndValidate(db, currentSchemaVersion);
      final List<drift.QueryRow> rows = await db
          .customSelect('SELECT COUNT(*) AS c FROM articles_fts')
          .get();
      expect(rows.single.read<int>('c'), 0);
      await db.close();
    });
  });
}
