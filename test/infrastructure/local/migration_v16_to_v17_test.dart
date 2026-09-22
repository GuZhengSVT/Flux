// T047：v16 → v17 的真实增量迁移（AI 结果缓存补容量与淘汰所需的两列）。
//
// 这一步要验四件事：
//   1) **两列真的加上且可读**（byte_length / last_used_at）；
//   2) **byte_length 对既有行回填**且口径是**字节**（中文按 UTF-8 计，不是字符数）；
//   3) **last_used_at 不回填**（历史行没有「曾经被读过」这个事实，用 created_at 顶上等于
//      伪造一次命中）；
//   4) **既有数据零丢失**（文章三态/收藏/正文、订阅、任务记录）。
import 'package:drift/drift.dart' as drift;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flux/infrastructure/local/database.dart';

import '../../generated/schema.dart';
import '../../generated/schema_v16.dart' as v16;

/// 当前 schema 版本（与应用代码一致）。
const int currentSchemaVersion = 17;

void main() {
  drift.driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('v16 → 当前版本 增量迁移', () {
    test('带旧数据的 v16 库升级：缓存两列就绪、字节数回填、时间不回填', () async {
      final SchemaVerifier verifier = SchemaVerifier(GeneratedHelper());
      final InitializedSchema schema = await verifier.schemaAt(16);

      final v16.DatabaseAtV16 old = v16.DatabaseAtV16(schema.newConnection());
      final int feedId = await old
          .into(old.feeds)
          .insert(
            v16.FeedsCompanion.insert(
              syncId: 'feed-v16',
              normalizedUrl: 'https://v16.example.com/feed.xml',
              name: '升级前的源',
            ),
          );
      await old
          .into(old.articles)
          .insert(
            v16.ArticlesCompanion.insert(
              feedId: drift.Value<int?>(feedId),
              title: '升级前的文章',
              identityBasis: 'guid',
              favorite: const drift.Value<int>(1),
              readingState: const drift.Value<String>('later'),
              body: const drift.Value<String?>('升级前的正文'),
            ),
          );
      // 一条**中文**缓存结果：UTF-8 下每个汉字 3 字节，因此「字节数 = 字符数 × 3」这件事
      // 正是回填语句（CAST AS BLOB）与 Dart 侧 utf8ByteLength 必须一致的地方。
      await old
          .into(old.aiResultCacheRecords)
          .insert(
            v16.AiResultCacheRecordsCompanion.insert(
              cacheKey: 'cache-zh',
              resultText: '你好世界',
              providerAlias: 'main',
              modelId: 'm1',
              createdAt: '2026-09-20T08:00:00.000Z',
            ),
          );
      // 一条空结果：回填语句带 `length(result_text) > 0` 条件，空串的字节数保持 0。
      await old
          .into(old.aiResultCacheRecords)
          .insert(
            v16.AiResultCacheRecordsCompanion.insert(
              cacheKey: 'cache-empty',
              resultText: '',
              providerAlias: 'main',
              modelId: 'm1',
              createdAt: '2026-09-20T09:00:00.000Z',
            ),
          );
      await old.close();

      final AppDatabase migrated = AppDatabase(schema.newConnection());
      await verifier.migrateAndValidate(migrated, currentSchemaVersion);

      // 既有业务数据零丢失。
      final Article article =
          (await migrated.select(migrated.articles).get()).single;
      expect(article.title, '升级前的文章');
      expect(article.readingState.name, 'later');
      expect(article.favorite, isTrue);
      expect(article.body, '升级前的正文');

      final List<AiResultCacheRecord> caches = await migrated
          .select(migrated.aiResultCacheRecords)
          .get();
      expect(caches.length, 2);
      final AiResultCacheRecord zh = caches.firstWhere(
        (AiResultCacheRecord r) => r.cacheKey == 'cache-zh',
      );
      expect(
        zh.byteLength,
        12,
        reason:
            '「你好世界」是 4 个汉字 = 12 个 UTF-8 字节；'
            'SQLite 的 length(text) 是字符数（4），CAST AS BLOB 后才是字节数',
      );
      expect(
        zh.lastUsedAt,
        isNull,
        reason: '历史行没有「曾经被读过」这个事实，迁移不得用 created_at 伪造一次命中',
      );
      final AiResultCacheRecord empty = caches.firstWhere(
        (AiResultCacheRecord r) => r.cacheKey == 'cache-empty',
      );
      expect(empty.byteLength, 0, reason: '空结果的字节数是 0（回填带 length > 0 条件）');

      await migrated.close();
      schema.close();
    });

    test('新库（v17）直接建出缓存表的全部列', () async {
      final AppDatabase db = AppDatabase.memory();
      await db.customSelect('SELECT 1').get();
      final List<drift.QueryRow> columns = await db
          .customSelect('PRAGMA table_info(ai_result_cache_records)')
          .get();
      final Set<String> names = columns
          .map((drift.QueryRow r) => r.read<String>('name'))
          .toSet();
      expect(
        names,
        containsAll(<String>[
          'cache_key',
          'result_text',
          'provider_alias',
          'model_id',
          'created_at',
          'byte_length',
          'last_used_at',
        ]),
      );
      await db.close();
    });
  });
}
