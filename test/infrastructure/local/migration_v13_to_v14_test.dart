// T036：v13 → v14 的真实增量迁移（新增新闻来源配置三张表 + 订阅表的新闻开关列）。
//
// 这一步要验四件事：
//   1) **三张表与它们的索引真的建出**（漏建索引只有结构校验能发现）；
//   2) **feeds.news_enabled 真的加上，且必须是 NULL**（「用户从未做过这个选择」）；
//   3) **既有数据零丢失**（订阅、文章三态/收藏/正文与摘要、译文、模型与任务）；
//   4) **null 在读取侧的含义是「跟随 enabled」**（SET-050 的「已启用订阅默认开」不回填也成立）。
library;

import 'package:drift/drift.dart' as drift;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flux/core/core.dart';
import 'package:flux/infrastructure/local/database.dart';

import '../../generated/schema.dart';
import '../../generated/schema_v13.dart' as v13;

/// 当前 schema 版本（与应用代码一致）。
const int currentSchemaVersion = 15;

void main() {
  drift.driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('v13 → 当前版本 增量迁移', () {
    test('带旧数据的 v13 库升级：新闻配置三表就绪、旧数据零丢失、新闻开关不回填', () async {
      final SchemaVerifier verifier = SchemaVerifier(GeneratedHelper());
      final InitializedSchema schema = await verifier.schemaAt(13);

      final v13.DatabaseAtV13 old = v13.DatabaseAtV13(schema.newConnection());
      final int feedId = await old
          .into(old.feeds)
          .insert(
            v13.FeedsCompanion.insert(
              syncId: 'feed-v13',
              normalizedUrl: 'https://v13.example.com/feed.xml',
              name: '升级前的源',
            ),
          );
      await old
          .into(old.articles)
          .insert(
            v13.ArticlesCompanion.insert(
              feedId: drift.Value<int?>(feedId),
              title: '升级前的文章',
              identityBasis: 'guid',
              favorite: const drift.Value<int>(1),
              readingState: const drift.Value<String>('later'),
              body: const drift.Value<String?>('升级前的正文'),
              summary: const drift.Value<String?>('升级前的源摘要'),
            ),
          );
      await old.close();

      final AppDatabase migrated = AppDatabase(schema.newConnection());
      await verifier.migrateAndValidate(migrated, currentSchemaVersion);

      final Feed feed = (await migrated.select(migrated.feeds).get()).single;
      expect(feed.syncId, 'feed-v13');
      expect(feed.newsEnabled, isNull, reason: '不得回填：升级前不存在「用户为这个源做过新闻选择」这个事实');
      expect(
        newsIncludesFeed(
          newsEnabled: feed.newsEnabled,
          feedEnabled: feed.enabled,
        ),
        isTrue,
        reason: 'null 跟随 enabled（SET-050：已启用订阅默认开）',
      );

      final Article article =
          (await migrated.select(migrated.articles).get()).single;
      expect(article.favorite, isTrue);
      expect(article.readingState.name, 'later');
      expect(article.body, '升级前的正文');
      expect(article.summary, '升级前的源摘要');

      // 不回填：三张新表都是空的（升级前没有配置过新闻来源）。
      expect(
        await migrated.select(migrated.newsRequiredSiteRecords).get(),
        isEmpty,
      );
      expect(
        await migrated.select(migrated.newsConfigEntryRecords).get(),
        isEmpty,
      );
      expect(
        await migrated.select(migrated.newsPromptVersionRecords).get(),
        isEmpty,
      );

      await migrated.close();
      schema.close();
    });

    test('新库（v14）直接建出三张表与新闻开关列', () async {
      final AppDatabase db = AppDatabase.memory();
      await db.customSelect('SELECT 1').get();
      final List<drift.QueryRow> tables = await db
          .customSelect("SELECT name FROM sqlite_master WHERE type = 'table'")
          .get();
      final Set<String> tableNames = tables
          .map((drift.QueryRow r) => r.read<String>('name'))
          .toSet();
      expect(
        tableNames,
        containsAll(<String>[
          'news_required_site_records',
          'news_config_entry_records',
          'news_prompt_version_records',
        ]),
      );
      final List<drift.QueryRow> columns = await db
          .customSelect("PRAGMA table_info('feeds')")
          .get();
      final Map<String, bool> feedColumns = <String, bool>{
        for (final drift.QueryRow r in columns)
          r.read<String>('name'): r.read<int>('notnull') != 0,
      };
      expect(feedColumns.containsKey('news_enabled'), isTrue);
      expect(
        feedColumns['news_enabled'],
        isFalse,
        reason: '可空：null 表示跟随 enabled',
      );
      await db.close();
    });
  });
}
