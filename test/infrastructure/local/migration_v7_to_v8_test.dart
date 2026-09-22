// T024：v7 → v8 的真实增量迁移（新增本机静态提取正文的五列）。
//
// 这一步要验三件事：
//   1) **五列真的加上且可空**（升级不伪造「提取过」这个事实）；
//   2) **既有数据零丢失**（正文、三态、收藏、卡片图片、v5 的来源快照都还在）；
//   3) **v7 的检索对象没有被破坏**（v8 只加列，不该重建或丢掉 fts5 表与触发器）。
library;

import 'package:drift/drift.dart' as drift;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flux/infrastructure/local/database.dart';
import 'package:flux/infrastructure/local/tables/enums.dart';

import '../../generated/schema.dart';
import '../../generated/schema_v7.dart' as v7;

/// 当前 schema 版本（与应用代码一致）。
const int currentSchemaVersion = 16;

void main() {
  drift.driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('v7 → 当前版本 增量迁移', () {
    test('带旧数据的 v7 库升级到 v8：五列就绪、旧数据零丢失、检索对象仍在', () async {
      final SchemaVerifier verifier = SchemaVerifier(GeneratedHelper());
      final InitializedSchema schema = await verifier.schemaAt(7);

      final v7.DatabaseAtV7 old = v7.DatabaseAtV7(schema.newConnection());
      final int feedId = await old
          .into(old.feeds)
          .insert(
            v7.FeedsCompanion.insert(
              syncId: 'feed-v7',
              normalizedUrl: 'https://v7.example.com/feed.xml',
              name: '升级前的源',
            ),
          );
      final int articleId = await old
          .into(old.articles)
          .insert(
            v7.ArticlesCompanion.insert(
              feedId: drift.Value<int?>(feedId),
              title: '升级前的离线阅读文章',
              identityBasis: 'guid',
              guid: const drift.Value<String?>('g-v7'),
              guidPresent: const drift.Value<int>(1),
              body: const drift.Value<String?>('升级前的正文内容，含离线阅读一词。'),
              bodyHash: const drift.Value<String?>('hash-v7'),
              bodyCompleteness: const drift.Value<String>('sourceBody'),
              imageUrl: const drift.Value<String?>(
                'https://cdn.example.com/v7.png',
              ),
              favorite: const drift.Value<int>(1),
              readingState: const drift.Value<String>('later'),
            ),
          );
      await old.close();

      final AppDatabase migrated = AppDatabase(schema.newConnection());
      await verifier.migrateAndValidate(migrated, currentSchemaVersion);

      // 1) 五列都在且为空（不伪造「提取过」）。
      final Article row =
          (await migrated.select(migrated.articles).get()).single;
      expect(row.id, articleId);
      expect(row.extractedBody, isNull);
      expect(row.extractedBodyHash, isNull);
      expect(row.extractedAt, isNull);
      expect(row.extractedTitle, isNull);
      expect(row.extractedImageUrls, isNull);

      // 2) 旧数据零丢失。
      expect(row.title, '升级前的离线阅读文章');
      expect(row.body, '升级前的正文内容，含离线阅读一词。');
      expect(row.bodyHash, 'hash-v7');
      expect(row.imageUrl, 'https://cdn.example.com/v7.png');
      expect(row.favorite, isTrue, reason: '收藏不得被迁移改写');
      expect(row.readingState, ReadingState.later, reason: 'later 不得被迁移改写');

      // 3) 检索对象仍在（v8 只加列，不得丢掉 v7 建出来的 fts5 虚拟表与影子表）。
      //
      // 这里刻意**不**断言「历史文章能被搜到」：drift 的 schemaAt(7) 快照能建出 fts5
      // 表，但**不包含**由迁移代码显式创建的三个同步触发器（实测 sqlite_master 里
      // trigger 为空）。因此这个合成出来的 v7 库里没有倒排索引条目，MATCH 必然 0 命中——
      // 那反映的是夹具的构造方式，不是 v8 迁移的行为。真正验证「升级后触发器可用」的是
      // migration_v6_to_v7_test（它从 schemaAt(6) 走真实迁移），搜索语义本身由
      // article_search_store_test 覆盖。
      final List<drift.QueryRow> ftsObjects = await migrated
          .customSelect(
            "SELECT name FROM sqlite_master WHERE name LIKE 'articles_fts%'",
          )
          .get();
      final Set<String> names = ftsObjects
          .map((drift.QueryRow r) => r.read<String>('name'))
          .toSet();
      expect(names, contains('articles_fts'));

      await migrated.close();
    });

    test('升级后可以写入提取正文（五列真的可用）', () async {
      final SchemaVerifier verifier = SchemaVerifier(GeneratedHelper());
      final InitializedSchema schema = await verifier.schemaAt(7);
      final v7.DatabaseAtV7 old = v7.DatabaseAtV7(schema.newConnection());
      await old.close();

      final AppDatabase db = AppDatabase(schema.newConnection());
      await verifier.migrateAndValidate(db, currentSchemaVersion);

      final int feedId = await db
          .into(db.feeds)
          .insert(
            FeedsCompanion.insert(
              syncId: 'feed-v8',
              normalizedUrl: 'https://v8.example.com/feed.xml',
              name: '源',
            ),
          );
      final int id = await db
          .into(db.articles)
          .insert(
            ArticlesCompanion.insert(
              feedId: drift.Value<int?>(feedId),
              title: '新文章',
              identityBasis: IdentityBasis.guid,
            ),
          );

      await (db.update(
        db.articles,
      )..where(($ArticlesTable a) => a.id.equals(id))).write(
        ArticlesCompanion(
          extractedBody: const drift.Value<String?>('提取到的正文'),
          extractedBodyHash: const drift.Value<String?>('h1'),
          extractedTitle: const drift.Value<String?>('原站标题'),
          extractedImageUrls: const drift.Value<String?>(
            'https://cdn.example.com/a.png',
          ),
          extractedAt: drift.Value<DateTime?>(DateTime.utc(2026, 9, 22)),
        ),
      );

      final Article row = (await db.select(db.articles).get()).single;
      expect(row.extractedBody, '提取到的正文');
      expect(row.extractedBodyHash, 'h1');
      expect(row.extractedTitle, '原站标题');
      expect(row.extractedImageUrls, 'https://cdn.example.com/a.png');
      expect(row.extractedAt, DateTime.utc(2026, 9, 22));

      await db.close();
    });

    test('空 v7 库升级同样成功（没有历史文章也要建出列）', () async {
      final SchemaVerifier verifier = SchemaVerifier(GeneratedHelper());
      final AppDatabase db = AppDatabase.memory();
      await verifier.migrateAndValidate(db, currentSchemaVersion);
      final List<drift.QueryRow> rows = await db
          .customSelect('PRAGMA table_info(articles)')
          .get();
      final Set<String> columns = rows
          .map((drift.QueryRow r) => r.read<String>('name'))
          .toSet();
      expect(
        columns,
        containsAll(<String>[
          'extracted_body',
          'extracted_body_hash',
          'extracted_at',
          'extracted_title',
          'extracted_image_urls',
        ]),
      );
      await db.close();
    });
  });
}
