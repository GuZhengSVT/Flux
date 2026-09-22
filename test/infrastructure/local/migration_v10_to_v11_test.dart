// T031：v10 → v11 的真实增量迁移（新增搜索服务记录表）。
//
// 这一步要验三件事：
//   1) **表与两个索引真的建出**（漏建索引时运行时查询照常工作，只有结构校验才会
//      发现——T010 的迁移测试曾这样抓到过一次）；
//   2) **既有数据零丢失**（AI 模型记录、AI 任务与缓存、订阅、文章与三态都还在）；
//   3) **不回填任何东西**：升级前不存在「配好的搜索服务」这个事实，空表是诚实的
//      默认状态（与 v2→v10 各步同一口径）。
//
// 另有一条硬约束在这里核验：搜索服务表**没有任何凭据列**（SET-039：Key 只住
// Keychain）。这条是结构性的，因此可以在快照层面证明，而不必靠「读代码时注意」。
library;

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' as drift;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flux/infrastructure/local/database.dart';

import '../../generated/schema.dart';
import '../../generated/schema_v10.dart' as v10;

/// 当前 schema 版本（与应用代码一致）。
const int currentSchemaVersion = 17;

void main() {
  drift.driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('v10 → 当前版本 增量迁移', () {
    test('带旧数据的 v10 库升级：搜索服务表就绪、旧数据零丢失、不回填', () async {
      final SchemaVerifier verifier = SchemaVerifier(GeneratedHelper());
      final InitializedSchema schema = await verifier.schemaAt(10);

      // --- 用 v10 视角写入「升级前就存在」的数据 ------------------------------
      final v10.DatabaseAtV10 old = v10.DatabaseAtV10(schema.newConnection());

      final int feedId = await old
          .into(old.feeds)
          .insert(
            v10.FeedsCompanion.insert(
              syncId: 'feed-v10',
              normalizedUrl: 'https://v10.example.com/feed.xml',
              name: '升级前的源',
            ),
          );
      await old
          .into(old.articles)
          .insert(
            v10.ArticlesCompanion.insert(
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
            v10.AiModelRecordsCompanion.insert(
              alias: '升级前的模型',
              protocolId: 'openai.chat_completions',
              baseUrl: 'https://api.example.com',
              modelId: 'example-model',
            ),
          );
      await old
          .into(old.aiTasks)
          .insert(
            v10.AiTasksCompanion.insert(
              taskId: 'task-v10',
              kind: 'summary',
              inputSnapshot: '{}',
              promptHash: 'hash-v10',
              modelAliases: '[]',
              routeModelIds: '[]',
              status: 'succeeded',
              // v10 的生成代码把 DateTime 落成 ISO-8601 文本（见 build.yaml），
              // 因此这里按**升级前那版代码**的形态写文本值。
              createdAt: '2026-09-20T00:00:00.000Z',
              updatedAt: '2026-09-20T00:00:00.000Z',
            ),
          );
      await old.close();

      // --- 跑应用的真实迁移策略，并用 drift 的 SchemaVerifier 逐列比对结构 ----
      final AppDatabase migrated = AppDatabase(schema.newConnection());
      await verifier.migrateAndValidate(migrated, currentSchemaVersion);

      // 1) 旧数据完好：订阅、文章三态与收藏、AI 模型记录、AI 任务都还在且值未变。
      expect(
        (await migrated.select(migrated.feeds).get()).single.syncId,
        'feed-v10',
      );
      final Article article =
          (await migrated.select(migrated.articles).get()).single;
      expect(article.favorite, isTrue, reason: '收藏不得在升级中丢失');
      expect(article.readingState.name, 'later', reason: '三态不得在升级中丢失');
      expect(
        (await migrated.select(migrated.aiModelRecords).get()).single.alias,
        '升级前的模型',
      );
      final AiTask task =
          (await migrated.select(migrated.aiTasks).get()).single;
      expect(task.taskId, 'task-v10');
      expect(task.status, 'succeeded', reason: '任务结论不得在升级中丢失');

      // 2) 新表为空：不回填、不伪造「配好的搜索服务」。
      expect(
        await migrated.select(migrated.searchServiceRecords).get(),
        isEmpty,
      );

      // 3) 两个索引真的建出（索引是独立 schema 实体，createTable 不会顺带建）。
      final List<drift.QueryRow> indexes = await migrated
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'index' "
            "AND name LIKE '%search_service%'",
          )
          .get();
      final Set<String> names = indexes
          .map((drift.QueryRow r) => r.read<String>('name'))
          .toSet();
      expect(
        names,
        containsAll(<String>[
          'ux_search_service_label',
          'ix_search_service_sort',
        ]),
      );

      await migrated.close();
    });

    test('新库（v11）直接建出搜索服务表，且快照里没有任何凭据列', () async {
      final AppDatabase db = AppDatabase.memory();
      await db.customSelect('SELECT 1').get();

      final List<String> columns =
          (await db
                  .customSelect('PRAGMA table_info(search_service_records)')
                  .get())
              .map((drift.QueryRow r) => r.read<String>('name'))
              .toList();
      expect(columns, isNotEmpty, reason: '新库必须直接建出搜索服务表');
      expect(
        columns,
        contains('allow_private_endpoint'),
        reason: 'SET-041 的显式批准列',
      );
      // 结构性证明：表里没有任何 Key 列（SET-039 只住 Keychain）。
      for (final String forbidden in <String>[
        'api_key',
        'key',
        'token',
        'secret',
        'credential',
        'password',
      ]) {
        expect(
          columns.where((String name) => name.contains(forbidden)),
          isEmpty,
          reason: '搜索服务表不得出现凭据列（含「$forbidden」）',
        );
      }

      await db.close();
    });

    test('快照实体集合：v11 相对 v10 只新增一张表与两个索引', () {
      final Map<String, dynamic> v11 = jsonDecode(
        File('drift_schemas/drift_schema_v11.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      final Set<String> v11Names = (v11['entities'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map(
            (Map<String, dynamic> e) =>
                (e['data'] as Map<String, dynamic>)['name'] as String,
          )
          .toSet();
      final Map<String, dynamic> v10Snapshot = jsonDecode(
        File('drift_schemas/drift_schema_v10.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      final Set<String> v10Names = (v10Snapshot['entities'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map(
            (Map<String, dynamic> e) =>
                (e['data'] as Map<String, dynamic>)['name'] as String,
          )
          .toSet();
      expect(
        v11Names,
        containsAll(v10Names),
        reason: 'v11 只新增搜索服务表与它的两个索引，不得删除 v10 的任何实体',
      );
      expect(v11Names.difference(v10Names), <String>{
        'search_service_records',
        'ux_search_service_label',
        'ix_search_service_sort',
      });
    });
  });
}
