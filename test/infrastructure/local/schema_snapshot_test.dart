// T009：时间存储约定 + v1 schema 快照一致性。
//
// 为什么单独测时间存储：drift 默认把 DateTime 存成 Unix 秒并读回本地时间，
// 会同时丢失原始时区与亚秒精度，与架构 5.1「UTC 存储，保留原始时间」冲突。
// 本工程在 build.yaml 里改为 ISO-8601 文本存储；这里用往返测试把它钉住，
// 避免将来有人无意中改回默认值而静默降低数据质量。
import 'dart:convert';
import 'dart:io';

// drift 也导出 `isNull`，与本文件用到的 matcher 同名，显式隐藏以避免歧义。
import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';

import 'package:flux/infrastructure/local/database.dart';
import 'package:flux/infrastructure/local/tables/enums.dart';

void main() {
  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  group('DateTime 存储约定（架构 5.1：UTC 存储、保留原始时间）', () {
    late AppDatabase db;
    late int feedId;

    setUp(() async {
      db = AppDatabase.memory();
      await db.customSelect('SELECT 1').get();
      feedId = await db
          .into(db.feeds)
          .insert(
            FeedsCompanion.insert(
              syncId: 'f-dt',
              normalizedUrl: 'https://dt.example.com/feed.xml',
              name: '时间测试',
            ),
          );
    });

    tearDown(() async {
      await db.close();
    });

    test('UTC 时刻往返无损：时区标记与亚秒精度都保留', () async {
      final DateTime original = DateTime.utc(2026, 9, 21, 12, 34, 56, 789);
      await db
          .into(db.articles)
          .insert(
            ArticlesCompanion.insert(
              feedId: Value<int?>(feedId),
              title: '时间往返',
              identityBasis: IdentityBasis.guid,
              publishedAt: Value<DateTime?>(original),
            ),
          );

      final Article read = (await db.select(db.articles).get()).single;
      expect(read.publishedAt!.isUtc, isTrue, reason: '必须仍是 UTC');
      expect(read.publishedAt, original, reason: '时刻与亚秒精度都必须无损往返');
    });

    test('时间以 ISO-8601 文本落库，明文备份可直接阅读', () async {
      await db
          .into(db.articles)
          .insert(
            ArticlesCompanion.insert(
              feedId: Value<int?>(feedId),
              title: '文本存储',
              identityBasis: IdentityBasis.guid,
              publishedAt: Value<DateTime?>(DateTime.utc(2026, 9, 21, 1, 2, 3)),
            ),
          );

      final String raw =
          (await db
                  .customSelect('SELECT published_at AS p FROM articles')
                  .getSingle())
              .read<String>('p');
      // UTC 文本以 Z 结尾，字典序排序即时间序。
      expect(raw, startsWith('2026-09-21T01:02:03'));
      expect(raw, endsWith('Z'));
    });

    test('UTC 文本的字典序与时间序一致（便于按时间排序）', () async {
      final List<DateTime> times = <DateTime>[
        DateTime.utc(2026, 1, 5),
        DateTime.utc(2025, 12, 31),
        DateTime.utc(2026, 1, 5, 0, 0, 1),
      ];
      for (final DateTime t in times) {
        await db
            .into(db.articles)
            .insert(
              ArticlesCompanion.insert(
                feedId: Value<int?>(feedId),
                title: t.toIso8601String(),
                identityBasis: IdentityBasis.guid,
                publishedAt: Value<DateTime?>(t),
              ),
            );
      }

      final List<String> sortedBySql =
          (await db
                  .customSelect(
                    'SELECT published_at AS p FROM articles ORDER BY published_at',
                  )
                  .get())
              .map((QueryRow r) => r.read<String>('p'))
              .toList();

      final List<DateTime> sorted = times.toList()..sort();
      expect(
        sortedBySql,
        sorted.map((DateTime d) => d.toIso8601String()).toList(),
      );
    });

    test('会话的本地日期键与时区可落库（跨午夜统计基础）', () async {
      final int articleId = await db
          .into(db.articles)
          .insert(
            ArticlesCompanion.insert(
              feedId: Value<int?>(feedId),
              title: '会话',
              identityBasis: IdentityBasis.guid,
            ),
          );

      await db
          .into(db.readingSessions)
          .insert(
            ReadingSessionsCompanion.insert(
              articleId: articleId,
              startedAt: DateTime.utc(2026, 9, 21, 15, 30),
              timeZone: 'Asia/Shanghai',
              localDate: '2026-09-21',
            ),
          );

      final ReadingSession session =
          (await db.select(db.readingSessions).get()).single;
      expect(session.timeZone, 'Asia/Shanghai');
      expect(session.localDate, '2026-09-21');
      expect(session.effectiveSeconds, 0, reason: '默认有效时长为 0');
      expect(session.endedAt, isNull, reason: '进行中的会话没有结束时间');
    });
  });

  group('schema 快照', () {
    test('v1 与 v2 快照都已导出，供迁移测试使用', () {
      final File snapshot = File('drift_schemas/drift_schema_v1.json');
      expect(
        snapshot.existsSync(),
        isTrue,
        reason:
            '缺少 v1 快照。可用 `dart run drift_dev schema dump '
            'lib/infrastructure/local/database.dart drift_schemas/` 重新导出，'
            '它是后续版本验证迁移正确性的基线。',
      );

      final Map<String, dynamic> decoded =
          jsonDecode(snapshot.readAsStringSync()) as Map<String, dynamic>;
      expect(
        decoded['options'],
        containsPair('store_date_time_values_as_text', true),
        reason: '快照必须记录时间存储方式，否则未来迁移测试会按错误的映射比对',
      );

      final Set<String> names = (decoded['entities'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map(
            (Map<String, dynamic> e) =>
                (e['data'] as Map<String, dynamic>)['name'] as String,
          )
          .toSet();
      expect(
        names,
        containsAll(<String>[
          'groups',
          'feeds',
          'articles',
          'reading_sessions',
          'summary_versions',
          'citations',
        ]),
      );

      // v2 快照是 T010 的真实增量迁移基线：它必须存在，且包含 settings 表。
      final File v2Snapshot = File('drift_schemas/drift_schema_v2.json');
      expect(
        v2Snapshot.existsSync(),
        isTrue,
        reason: 'schemaVersion 提到 2 后必须导出 v2 快照，否则无法验证 v1→v2 迁移。',
      );
      final Map<String, dynamic> v2Decoded =
          jsonDecode(v2Snapshot.readAsStringSync()) as Map<String, dynamic>;
      final Set<String> v2Names = (v2Decoded['entities'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map(
            (Map<String, dynamic> e) =>
                (e['data'] as Map<String, dynamic>)['name'] as String,
          )
          .toSet();
      expect(v2Names, contains('settings'));
      expect(
        v2Names,
        containsAll(<String>[
          'groups',
          'feeds',
          'articles',
          'reading_sessions',
          'summary_versions',
          'citations',
        ]),
        reason: 'v2 只新增 settings，不得删除 v1 已有实体',
      );

      // v3 快照是 T013 的真实增量迁移基线（订阅表补抓取诊断列）。它同样必须在
      // 版本提升后立刻导出，否则无法用 drift 校验 v2→v3 的迁移正确性。
      final File v3Snapshot = File('drift_schemas/drift_schema_v3.json');
      expect(
        v3Snapshot.existsSync(),
        isTrue,
        reason:
            '缺少 v3 快照。可用 `dart run drift_dev schema dump '
            'lib/infrastructure/local/database.dart drift_schemas/` 重新导出。',
      );
      final Map<String, dynamic> v3Decoded =
          jsonDecode(v3Snapshot.readAsStringSync()) as Map<String, dynamic>;
      final List<Map<String, dynamic>> v3Entities =
          (v3Decoded['entities'] as List<dynamic>).cast<Map<String, dynamic>>();
      final Set<String> v3Names = v3Entities
          .map(
            (Map<String, dynamic> e) =>
                (e['data'] as Map<String, dynamic>)['name'] as String,
          )
          .toSet();
      // v3 只加列、不增删表：实体集合应与 v2 完全一致。
      expect(v3Names, v2Names, reason: 'v3 只给 feeds 加列，不得新增或删除实体');

      // feeds 表必须真的带上三个新列（只是「有快照」不等于列进去了）。
      final Map<String, dynamic> feedsEntity = v3Entities.firstWhere(
        (Map<String, dynamic> e) =>
            (e['data'] as Map<String, dynamic>)['name'] == 'feeds',
      );
      final Set<String> feedColumns =
          ((feedsEntity['data'] as Map<String, dynamic>)['columns']
                  as List<dynamic>)
              .cast<Map<String, dynamic>>()
              .map((Map<String, dynamic> c) => c['name'] as String)
              .toSet();
      expect(
        feedColumns,
        containsAll(<String>[
          'last_checked_at',
          'last_refresh_result',
          'last_refresh_error_kind',
        ]),
      );
      // v4 快照是 T014 的真实增量迁移基线（订阅表补 enabled 列）。同样必须在版本
      // 提升后立刻导出，否则无法用 drift 校验 v3→v4 的迁移正确性。
      final File v4Snapshot = File('drift_schemas/drift_schema_v4.json');
      expect(
        v4Snapshot.existsSync(),
        isTrue,
        reason: '缺少 v4 快照。可用 drift_dev schema dump 重新导出（见本文件顶部说明）。',
      );
      final Map<String, dynamic> v4Decoded =
          jsonDecode(v4Snapshot.readAsStringSync()) as Map<String, dynamic>;
      final List<Map<String, dynamic>> v4Entities =
          (v4Decoded['entities'] as List<dynamic>).cast<Map<String, dynamic>>();
      final Set<String> v4Names = v4Entities
          .map(
            (Map<String, dynamic> e) =>
                (e['data'] as Map<String, dynamic>)['name'] as String,
          )
          .toSet();
      // v4 同样只加列、不增删表：实体集合应与 v3 完全一致。
      expect(v4Names, v3Names, reason: 'v4 只给 feeds 加 enabled，不得新增或删除实体');

      final Map<String, dynamic> v4FeedsEntity = v4Entities.firstWhere(
        (Map<String, dynamic> e) =>
            (e['data'] as Map<String, dynamic>)['name'] == 'feeds',
      );
      final Set<String> v4FeedColumns =
          ((v4FeedsEntity['data'] as Map<String, dynamic>)['columns']
                  as List<dynamic>)
              .cast<Map<String, dynamic>>()
              .map((Map<String, dynamic> c) => c['name'] as String)
              .toSet();
      expect(v4FeedColumns, contains('enabled'));
      // v4 必须保留 v3 已有的三列：只加列不等于可以丢列。
      expect(
        v4FeedColumns,
        containsAll(<String>[
          'last_checked_at',
          'last_refresh_result',
          'last_refresh_error_kind',
        ]),
      );

      // v6 快照是 T019+ 的真实增量迁移基线（文章表补卡片图片地址）。必须在版本
      // 提升后立刻导出，否则无法用 drift 校验 v5→v6 的迁移正确性。
      final File v6Snapshot = File('drift_schemas/drift_schema_v6.json');
      expect(
        v6Snapshot.existsSync(),
        isTrue,
        reason: '缺少 v6 快照。可用 drift_dev schema dump 重新导出（见本文件顶部说明）。',
      );
      final Map<String, dynamic> v6Decoded =
          jsonDecode(v6Snapshot.readAsStringSync()) as Map<String, dynamic>;
      final List<Map<String, dynamic>> v6Entities =
          (v6Decoded['entities'] as List<dynamic>).cast<Map<String, dynamic>>();
      final Set<String> v6Names = v6Entities
          .map(
            (Map<String, dynamic> e) =>
                (e['data'] as Map<String, dynamic>)['name'] as String,
          )
          .toSet();
      // v6 只加列、不增删表：实体集合（含索引）应与 v5 完全一致。用 v5 快照比而不是
      // v4：v4 还没有 deletion_events 表与它的两个索引，拿它做基线会把 v5 的合法新增
      // 误判成 v6 的问题。
      final Map<String, dynamic> v5Decoded = jsonDecode(
        File('drift_schemas/drift_schema_v5.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      final Set<String> v5Names = (v5Decoded['entities'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map(
            (Map<String, dynamic> e) =>
                (e['data'] as Map<String, dynamic>)['name'] as String,
          )
          .toSet();
      expect(
        v6Names,
        v5Names,
        reason: 'v6 只给 articles 加 image_url，不得新增或删除实体或索引',
      );

      final Map<String, dynamic> v6ArticlesEntity = v6Entities.firstWhere(
        (Map<String, dynamic> e) =>
            (e['data'] as Map<String, dynamic>)['name'] == 'articles',
      );
      final Set<String> v6ArticleColumns =
          ((v6ArticlesEntity['data'] as Map<String, dynamic>)['columns']
                  as List<dynamic>)
              .cast<Map<String, dynamic>>()
              .map((Map<String, dynamic> c) => c['name'] as String)
              .toSet();
      expect(v6ArticleColumns, contains('image_url'));
      // v6 必须保留 v5 已有的来源快照两列：只加列不等于可以丢列。
      expect(v6ArticleColumns, containsAll(<String>['feed_title', 'feed_url']));
    });

    test('v7 快照包含全文检索对象（T022 的 FTS5 虚拟表与触发器）', () {
      final File v7Snapshot = File('drift_schemas/drift_schema_v7.json');
      expect(
        v7Snapshot.existsSync(),
        isTrue,
        reason: '缺少 v7 快照。可用 drift_dev schema dump 重新导出（见本文件顶部说明）。',
      );
      final Map<String, dynamic> decoded =
          jsonDecode(v7Snapshot.readAsStringSync()) as Map<String, dynamic>;
      final List<Map<String, dynamic>> entities =
          (decoded['entities'] as List<dynamic>).cast<Map<String, dynamic>>();
      final Map<String, String> byName = <String, String>{
        for (final Map<String, dynamic> e in entities)
          (e['data'] as Map<String, dynamic>)['name'] as String: jsonEncode(
            e['data'],
          ),
      };

      expect(byName.keys, contains('articles_fts'));
      expect(byName.keys, contains('articles_fts_ai'));
      expect(byName.keys, contains('articles_fts_ad'));
      expect(byName.keys, contains('articles_fts_au'));
      // 检索列的 tokenizer 与 external content 参数必须写进快照：它们是中文检索语义的
      // 全部依据，快照里没有的话后续迁移测试就验证不到「有没有被改掉」。
      expect(byName['articles_fts'], contains('trigram'));
      expect(byName['articles_fts'], contains('content_rowid'));
    });

    test('v8 快照包含提取正文五列（T024），且不丢 v7 的检索对象', () {
      final File v8Snapshot = File('drift_schemas/drift_schema_v8.json');
      expect(
        v8Snapshot.existsSync(),
        isTrue,
        reason: '缺少 v8 快照。可用 drift_dev schema dump 重新导出（见本文件顶部说明）。',
      );
      final Map<String, dynamic> v8Decoded =
          jsonDecode(v8Snapshot.readAsStringSync()) as Map<String, dynamic>;
      final List<Map<String, dynamic>> v8Entities =
          (v8Decoded['entities'] as List<dynamic>).cast<Map<String, dynamic>>();
      final Set<String> v8Names = v8Entities
          .map(
            (Map<String, dynamic> e) =>
                (e['data'] as Map<String, dynamic>)['name'] as String,
          )
          .toSet();

      // v8 只给 articles 加列：v7 的全部实体（含检索对象）都必须保留。
      final Map<String, dynamic> v7Decoded = jsonDecode(
        File('drift_schemas/drift_schema_v7.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      final Set<String> v7Names = (v7Decoded['entities'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map(
            (Map<String, dynamic> e) =>
                (e['data'] as Map<String, dynamic>)['name'] as String,
          )
          .toSet();
      expect(v8Names, v7Names, reason: 'v8 只给 articles 加列，不得新增或删除实体');

      final Map<String, dynamic> v8Articles = v8Entities.firstWhere(
        (Map<String, dynamic> e) =>
            (e['data'] as Map<String, dynamic>)['name'] == 'articles',
      );
      final Set<String> v8ArticleColumns =
          ((v8Articles['data'] as Map<String, dynamic>)['columns']
                  as List<dynamic>)
              .cast<Map<String, dynamic>>()
              .map((Map<String, dynamic> c) => c['name'] as String)
              .toSet();
      expect(
        v8ArticleColumns,
        containsAll(<String>[
          'extracted_body',
          'extracted_body_hash',
          'extracted_at',
          'extracted_title',
          'extracted_image_urls',
        ]),
      );
      // v8 必须保留 v7 已有的列（含 v6 的 image_url 与 v5 的来源快照）。
      expect(
        v8ArticleColumns,
        containsAll(<String>['body', 'body_hash', 'image_url', 'feed_title']),
      );
    });

    test('v9 快照新增 AI 模型表（T025），且不丢 v8 的任何实体', () {
      final File v9Snapshot = File('drift_schemas/drift_schema_v9.json');
      expect(
        v9Snapshot.existsSync(),
        isTrue,
        reason: '缺少 v9 快照。可用 drift_dev schema dump 重新导出（见本文件顶部说明）。',
      );
      final Map<String, dynamic> v9Decoded =
          jsonDecode(v9Snapshot.readAsStringSync()) as Map<String, dynamic>;
      final List<Map<String, dynamic>> v9Entities =
          (v9Decoded['entities'] as List<dynamic>).cast<Map<String, dynamic>>();
      final Set<String> v9Names = v9Entities
          .map(
            (Map<String, dynamic> e) =>
                (e['data'] as Map<String, dynamic>)['name'] as String,
          )
          .toSet();

      // v8 的全部实体（含 fts5 检索对象）都必须保留：v9 只新增一张表。
      final Map<String, dynamic> v8Decoded = jsonDecode(
        File('drift_schemas/drift_schema_v8.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      final Set<String> v8Names = (v8Decoded['entities'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map(
            (Map<String, dynamic> e) =>
                (e['data'] as Map<String, dynamic>)['name'] as String,
          )
          .toSet();
      expect(
        v9Names,
        containsAll(v8Names),
        reason: 'v9 只新增 AI 模型表，不得删除 v8 的任何实体',
      );
      expect(
        v9Names.difference(v8Names),
        <String>{'ai_model_records', 'ux_ai_models_alias', 'ix_ai_models_sort'},
        reason:
            'v9 相对 v8 的新增实体应只有 AI 模型表与它的两个索引'
            '（表名由类名派生）；索引是独立 schema 实体，必须显式建出',
      );

      // 表里**不能有任何凭据列**：SET-031 只住 Keychain（架构 5.1「数据库不含秘密」）。
      // 这条断言把该约束钉在 schema 层面，而不是靠「记得不要加」。
      final Map<String, dynamic> aiTable = v9Entities.firstWhere(
        (Map<String, dynamic> e) =>
            (e['data'] as Map<String, dynamic>)['name'] == 'ai_model_records',
      );
      final Set<String> aiColumns =
          ((aiTable['data'] as Map<String, dynamic>)['columns']
                  as List<dynamic>)
              .cast<Map<String, dynamic>>()
              .map((Map<String, dynamic> c) => c['name'] as String)
              .toSet();
      expect(
        aiColumns,
        containsAll(<String>[
          'alias',
          'preset',
          'protocol_id',
          'base_url',
          'model_id',
          'enabled',
          'sort_order',
          'capability_text',
          'capability_vision',
          'capability_streaming',
          'capability_tools',
          'capability_structured',
          'context_window',
          'output_budget',
          'is_default_for_tasks',
        ]),
      );
      for (final String forbidden in <String>[
        'api_key',
        'key',
        'token',
        'secret',
        'credential',
        'password',
      ]) {
        expect(
          aiColumns.where((String name) => name.contains(forbidden)),
          isEmpty,
          reason: 'AI 模型表不得出现凭据列（含「$forbidden」）',
        );
      }
    });
  });
}
