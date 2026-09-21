// T030：v9 → v10 的真实增量迁移（新增 AI 任务表与结果缓存表）。
//
// 这一步要验三件事：
//   1) **两张表与三个索引真的建出**（漏建索引时运行时查询照常工作，只有结构校验
//      才会发现——T010 的迁移测试曾这样抓到过一次）；
//   2) **既有数据零丢失**（AI 模型记录、订阅、文章与三态都还在）；
//   3) **不回填任何东西**：升级前不存在「跑过的 AI 任务」这个事实，空表是诚实的默认
//      状态（这与 v2→v9 各步同一口径：不用看起来合理的值伪造历史）。
library;

import 'package:drift/drift.dart' as drift;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flux/infrastructure/local/database.dart';

import '../../generated/schema.dart';
import '../../generated/schema_v9.dart' as v9;

/// 当前 schema 版本（与应用代码一致）。
const int currentSchemaVersion = 14;

void main() {
  drift.driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('v9 → 当前版本 增量迁移', () {
    test('带旧数据的 v9 库升级：两张新表就绪、旧数据零丢失、不回填', () async {
      final SchemaVerifier verifier = SchemaVerifier(GeneratedHelper());
      final InitializedSchema schema = await verifier.schemaAt(9);

      // --- 用 v9 视角写入「升级前就存在」的数据 ------------------------------
      final v9.DatabaseAtV9 old = v9.DatabaseAtV9(schema.newConnection());

      final int feedId = await old
          .into(old.feeds)
          .insert(
            v9.FeedsCompanion.insert(
              syncId: 'feed-v9',
              normalizedUrl: 'https://v9.example.com/feed.xml',
              name: '升级前的源',
            ),
          );
      final int articleId = await old
          .into(old.articles)
          .insert(
            v9.ArticlesCompanion.insert(
              feedId: drift.Value<int?>(feedId),
              title: '升级前的文章',
              identityBasis: 'guid',
              favorite: const drift.Value<int>(1),
              readingState: const drift.Value<String>('later'),
            ),
          );
      await old
          .into(old.aiModelRecords)
          .insert(
            v9.AiModelRecordsCompanion.insert(
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

      // 1) 旧数据完好：订阅、文章三态与收藏、AI 模型记录都还在且值未变。
      final Feed feed = (await migrated.select(migrated.feeds).get()).single;
      expect(feed.syncId, 'feed-v9');
      expect(feed.name, '升级前的源');

      final Article article =
          (await migrated.select(migrated.articles).get()).single;
      expect(article.id, articleId);
      expect(article.favorite, isTrue, reason: '收藏不得在升级中丢失');
      expect(article.readingState.name, 'later', reason: '三态不得在升级中丢失');

      final AiModelRecord model =
          (await migrated.select(migrated.aiModelRecords).get()).single;
      expect(model.alias, '升级前的模型');

      // 2) 新表为空：不回填、不伪造「跑过的任务」。
      expect(await migrated.select(migrated.aiTasks).get(), isEmpty);
      expect(
        await migrated.select(migrated.aiResultCacheRecords).get(),
        isEmpty,
      );

      // 3) 三个索引真的建出（索引是独立 schema 实体，createTable 不会顺带建）。
      final List<drift.QueryRow> indexes = await migrated
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'index' AND name LIKE 'i%_ai_%'",
          )
          .get();
      final Set<String> names = indexes
          .map((drift.QueryRow r) => r.read<String>('name'))
          .toSet();
      expect(
        names,
        containsAll(<String>[
          'ix_ai_tasks_created',
          'ix_ai_tasks_status',
          'ix_ai_result_cache_created',
        ]),
      );

      await migrated.close();
    });

    test('新库（v10）直接建出两张表：主键是 task_id / cache_key', () async {
      final AppDatabase db = AppDatabase.memory();
      await db.customSelect('SELECT 1').get();

      final List<drift.QueryRow> tables = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'table' AND name LIKE 'ai_%'",
          )
          .get();
      final Set<String> names = tables
          .map((drift.QueryRow r) => r.read<String>('name'))
          .toSet();
      expect(
        names,
        containsAll(<String>[
          'ai_model_records',
          'ai_tasks',
          'ai_result_cache_records',
        ]),
      );

      // 同一 task_id 写入两次必须**替换**而不是插入第二条：
      // 任务记录是「当前态」，重复插入会让任务列表出现两条同 id 的行。
      await db.customStatement(
        'INSERT INTO ai_tasks (task_id, kind, input_snapshot, prompt_hash, '
        'model_aliases, route_model_ids, status, created_at, updated_at) '
        "VALUES ('t1', 'summary', '{}', 'h', '[]', '[]', 'queued', 'x', 'x')",
      );
      await expectLater(
        db.customStatement(
          'INSERT INTO ai_tasks (task_id, kind, input_snapshot, prompt_hash, '
          'model_aliases, route_model_ids, status, created_at, updated_at) '
          "VALUES ('t1', 'summary', '{}', 'h', '[]', '[]', 'running', 'x', 'x')",
        ),
        throwsA(isA<Exception>()),
        reason: 'task_id 是主键：重复插入必须被拒绝（写入走 upsert）',
      );

      await db.close();
    });
  });
}
