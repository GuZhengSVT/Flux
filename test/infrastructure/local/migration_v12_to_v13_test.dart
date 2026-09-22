// T035：v12 → v13 的真实增量迁移（新增分段翻译的两张表）。
//
// 这一步要验四件事：
//   1) **两张表与它们的索引真的建出**（漏建索引时运行时查询照常工作，只有结构校验
//      才会发现——T010 的迁移测试曾这样抓到过一次）；
//   2) **既有数据零丢失**（订阅、文章三态/收藏/源摘要/AI 摘要、模型、任务与搜索服务）；
//   3) **不回填任何东西**：升级前不存在「翻译过这篇文章」这个事实，空表是诚实的默认状态；
//   4) **articles 一列都不多**：译文有自己的归属，因此「原文始终保留」在迁移这一步之后
//      依然是结构性的（没有第二条写入路径会碰源正文）。
library;

import 'package:drift/drift.dart' as drift;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flux/infrastructure/local/database.dart';

import '../../generated/schema.dart';
import '../../generated/schema_v12.dart' as v12;

/// 当前 schema 版本（与应用代码一致）。
const int currentSchemaVersion = 16;

void main() {
  drift.driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('v12 → 当前版本 增量迁移', () {
    test('带旧数据的 v12 库升级：翻译两表就绪、旧数据零丢失、不回填', () async {
      final SchemaVerifier verifier = SchemaVerifier(GeneratedHelper());
      final InitializedSchema schema = await verifier.schemaAt(12);

      // --- 用 v12 视角写入「升级前就存在」的数据 ------------------------------
      final v12.DatabaseAtV12 old = v12.DatabaseAtV12(schema.newConnection());
      final int feedId = await old
          .into(old.feeds)
          .insert(
            v12.FeedsCompanion.insert(
              syncId: 'feed-v12',
              normalizedUrl: 'https://v12.example.com/feed.xml',
              name: '升级前的源',
            ),
          );
      final int articleId = await old
          .into(old.articles)
          .insert(
            v12.ArticlesCompanion.insert(
              feedId: drift.Value<int?>(feedId),
              title: '升级前的文章',
              identityBasis: 'guid',
              favorite: const drift.Value<int>(1),
              readingState: const drift.Value<String>('later'),
              body: const drift.Value<String?>('升级前的正文原文'),
              summary: const drift.Value<String?>('升级前的源摘要'),
              aiSummary: const drift.Value<String?>('升级前的 AI 摘要'),
              // 时间列在快照里是 ISO-8601 文本（build.yaml 的
              // store_date_time_values_as_text），因此这里按文本写入。
              aiSummaryAt: const drift.Value<String?>(
                '2026-09-22T03:00:00.000Z',
              ),
            ),
          );
      await old
          .into(old.aiModelRecords)
          .insert(
            v12.AiModelRecordsCompanion.insert(
              alias: '升级前的模型',
              protocolId: 'openai.chat_completions',
              baseUrl: 'https://api.example.com',
              modelId: 'example-model',
            ),
          );
      await old.close();

      // --- 跑应用的真实迁移策略，并用 drift 的 SchemaVerifier 逐列比对结构 ----
      final AppDatabase migrated = AppDatabase(schema.newConnection());
      await verifier.migrateAndValidate(migrated, currentSchemaVersion);

      final Article article =
          (await migrated.select(migrated.articles).get()).single;
      expect(article.id, articleId);
      expect(article.favorite, isTrue, reason: '收藏不得在升级中丢失');
      expect(article.readingState.name, 'later', reason: '三态不得在升级中丢失');
      expect(article.body, '升级前的正文原文', reason: '原文必须原样保留');
      expect(article.summary, '升级前的源摘要', reason: '源摘要必须保留');
      expect(article.aiSummary, '升级前的 AI 摘要', reason: 'AI 摘要必须保留');
      expect(
        (await migrated.select(migrated.feeds).get()).single.syncId,
        'feed-v12',
      );
      expect(
        (await migrated.select(migrated.aiModelRecords).get()).single.alias,
        '升级前的模型',
      );

      // 不回填：两张表都是空的（升级前没有「翻译过这篇文章」这个事实）。
      expect(
        await migrated.select(migrated.articleTranslationRecords).get(),
        isEmpty,
        reason: '不得回填任何译文',
      );
      expect(
        await migrated.select(migrated.translationSegmentRecords).get(),
        isEmpty,
      );

      await migrated.close();
      schema.close();
    });

    test('新库（v13）直接建出翻译两表，且 articles 不多出翻译列', () async {
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
          'article_translation_records',
          'translation_segment_records',
        ]),
      );
      final List<drift.QueryRow> columns = await db
          .customSelect("PRAGMA table_info('articles')")
          .get();
      final Set<String> articleColumns = columns
          .map((drift.QueryRow r) => r.read<String>('name'))
          .toSet();
      expect(
        articleColumns.where(
          (String name) =>
              name.contains('translat') || name.contains('target_language'),
        ),
        isEmpty,
        reason: '译文不得混进 articles（原文始终保留是结构性的）',
      );
      await db.close();
    });
  });
}
