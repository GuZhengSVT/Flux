// T034：v11 → v12 的真实增量迁移（文章表补 AI 摘要三列）。
//
// 这一步要验三件事：
//   1) **三列真的加上**（列在不在只有结构校验能发现）；
//   2) **既有数据零丢失**（订阅、文章三态与收藏、源摘要、AI 模型、任务与搜索服务都在）；
//   3) **不回填**：升级前不存在「生成过 AI 摘要」这个事实，三列必须是 NULL。
//
// 另有一条与产品规则直接对应的断言：**源摘要不被覆盖**（架构 4.2「原文始终保留」），
// 因此升级后 summary 列必须仍是升级前写进去的那段文本。
library;

import 'package:drift/drift.dart' as drift;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flux/infrastructure/local/database.dart';

import '../../generated/schema.dart';
import '../../generated/schema_v11.dart' as v11;

/// 当前 schema 版本（与应用代码一致）。
const int currentSchemaVersion = 17;

void main() {
  drift.driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('v11 → 当前版本 增量迁移', () {
    test('带旧数据的 v11 库升级：AI 摘要三列就绪、旧数据零丢失、不回填', () async {
      final SchemaVerifier verifier = SchemaVerifier(GeneratedHelper());
      final InitializedSchema schema = await verifier.schemaAt(11);

      // --- 用 v11 视角写入「升级前就存在」的数据 ------------------------------
      final v11.DatabaseAtV11 old = v11.DatabaseAtV11(schema.newConnection());
      final int feedId = await old
          .into(old.feeds)
          .insert(
            v11.FeedsCompanion.insert(
              syncId: 'feed-v11',
              normalizedUrl: 'https://v11.example.com/feed.xml',
              name: '升级前的源',
            ),
          );
      final int articleId = await old
          .into(old.articles)
          .insert(
            v11.ArticlesCompanion.insert(
              feedId: drift.Value<int?>(feedId),
              title: '升级前的文章',
              identityBasis: 'guid',
              favorite: const drift.Value<int>(1),
              readingState: const drift.Value<String>('later'),
              // 源摘要：这一步之后它**必须**还在（AI 摘要不覆盖它）。
              summary: const drift.Value<String?>('升级前就有的源摘要'),
            ),
          );
      await old
          .into(old.aiModelRecords)
          .insert(
            v11.AiModelRecordsCompanion.insert(
              alias: '升级前的模型',
              protocolId: 'openai.chat_completions',
              baseUrl: 'https://api.example.com',
              modelId: 'example-model',
            ),
          );
      await old
          .into(old.searchServiceRecords)
          .insert(
            v11.SearchServiceRecordsCompanion.insert(
              label: '升级前的搜索服务',
              protocolId: 'tavily',
              baseUrl: 'https://api.tavily.com',
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
      expect(article.summary, '升级前就有的源摘要', reason: '源摘要必须保留（AI 摘要与它分列，不覆盖）');
      // 不回填：三列都是 NULL（升级前没有「生成过 AI 摘要」这个事实）。
      expect(article.aiSummary, isNull, reason: '不得回填 AI 摘要');
      expect(article.aiSummaryAt, isNull, reason: '不得回填生成时间');
      expect(article.aiSummaryModel, isNull, reason: '不得回填模型标识');

      expect(
        (await migrated.select(migrated.feeds).get()).single.syncId,
        'feed-v11',
      );
      expect(
        (await migrated.select(migrated.aiModelRecords).get()).single.alias,
        '升级前的模型',
      );
      expect(
        (await migrated.select(migrated.searchServiceRecords).get())
            .single
            .label,
        '升级前的搜索服务',
      );

      await migrated.close();
      schema.close();
    });

    test('新库（v12）直接建出 AI 摘要三列，且源摘要列仍在', () async {
      final AppDatabase db = AppDatabase.memory();
      await db.customSelect('SELECT 1').get();
      final List<drift.QueryRow> columns = await db
          .customSelect("PRAGMA table_info('articles')")
          .get();
      final Set<String> names = columns
          .map((drift.QueryRow r) => r.read<String>('name'))
          .toSet();
      expect(
        names,
        containsAll(<String>[
          'ai_summary',
          'ai_summary_at',
          'ai_summary_model',
          'summary',
        ]),
      );
      await db.close();
    });
  });
}
