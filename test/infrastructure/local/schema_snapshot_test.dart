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
    test('v10 快照新增 AI 任务与结果缓存两张表（T030），且不丢 v9 的任何实体', () {
      final File v10Snapshot = File('drift_schemas/drift_schema_v10.json');
      expect(
        v10Snapshot.existsSync(),
        isTrue,
        reason: '缺少 v10 快照。可用 drift_dev schema dump 重新导出（见本文件顶部说明）。',
      );
      final Map<String, dynamic> v10Decoded =
          jsonDecode(v10Snapshot.readAsStringSync()) as Map<String, dynamic>;
      final List<Map<String, dynamic>> v10Entities =
          (v10Decoded['entities'] as List<dynamic>)
              .cast<Map<String, dynamic>>();
      final Set<String> v10Names = v10Entities
          .map(
            (Map<String, dynamic> e) =>
                (e['data'] as Map<String, dynamic>)['name'] as String,
          )
          .toSet();

      // v9 的全部实体都必须保留：v10 只**新增**两张表与它们的索引。
      final Map<String, dynamic> v9Decoded = jsonDecode(
        File('drift_schemas/drift_schema_v9.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      final Set<String> v9Names = (v9Decoded['entities'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map(
            (Map<String, dynamic> e) =>
                (e['data'] as Map<String, dynamic>)['name'] as String,
          )
          .toSet();
      expect(
        v10Names,
        containsAll(v9Names),
        reason: 'v10 只新增 AI 任务表与结果缓存表，不得删除 v9 的任何实体',
      );
      expect(
        v10Names.difference(v9Names),
        <String>{
          'ai_tasks',
          'ix_ai_tasks_created',
          'ix_ai_tasks_status',
          'ai_result_cache_records',
          'ix_ai_result_cache_created',
        },
        reason:
            'v10 相对 v9 的新增实体应只有两张表与它们的三个索引'
            '（表名由类名派生）；索引是独立 schema 实体，漏建时运行时查询照常工作，'
            '只有结构校验才会发现',
      );

      // 两张表的列必须齐全：缺一列会让「重启后复盘」丢掉一个事实
      // （例如缺 deadline，重启后任务就不受同一总时限约束了）。
      Map<String, dynamic> tableNamed(String name) => v10Entities.firstWhere(
        (Map<String, dynamic> e) =>
            (e['data'] as Map<String, dynamic>)['name'] == name,
      );
      Set<String> columnsOf(String name) =>
          ((tableNamed(name)['data'] as Map<String, dynamic>)['columns']
                  as List<dynamic>)
              .cast<Map<String, dynamic>>()
              .map((Map<String, dynamic> c) => c['name'] as String)
              .toSet();

      List<String> explicitPrimaryKeyOf(String name) =>
          ((tableNamed(name)['data'] as Map<String, dynamic>)['explicit_pk']
                  as List<dynamic>?)
              ?.cast<String>() ??
          const <String>[];

      expect(
        columnsOf('ai_tasks'),
        containsAll(<String>[
          'task_id',
          'kind',
          'input_snapshot',
          'prompt_hash',
          'model_aliases',
          'route_model_ids',
          'status',
          'deadline',
          'consumed_tokens',
          'attempt_count',
          'result_text',
          'finish_reason',
          'error_kind',
          'provider_alias',
          'cache_key',
          'from_cache',
          'created_at',
          'updated_at',
        ]),
      );
      expect(
        columnsOf('ai_result_cache_records'),
        containsAll(<String>[
          'cache_key',
          'result_text',
          'provider_alias',
          'model_id',
          'created_at',
        ]),
      );

      // 与 v9 同一条硬约束：这两张表也**不得**出现凭据列。
      // 输入快照里存的是 prompt 与参数，凭据只住 Keychain（SET-031）。
      for (final String table in <String>[
        'ai_tasks',
        'ai_result_cache_records',
      ]) {
        final Set<String> columns = columnsOf(table);
        for (final String forbidden in <String>[
          'api_key',
          'key',
          'token',
          'secret',
          'credential',
          'password',
        ]) {
          // 两个例外都是**结构性**列名而不是秘密：
          //   - consumed_tokens 是 Token 用量计数；
          //   - cache_key 是缓存键（输入哈希的摘要），不含任何凭据。
          // 之所以逐个放行而不是放宽断言：漏掉一条「真的叫 api_key」的列时，
          // 这条检查仍然会失败。
          final Iterable<String> hit = columns.where(
            (String name) =>
                name.contains(forbidden) &&
                name != 'consumed_tokens' &&
                name != 'cache_key',
          );
          expect(hit, isEmpty, reason: '$table 不得出现凭据列（含「$forbidden」）');
        }
      }

      // 主键必须是 task_id / cache_key：用自增 id 会让「按 taskId 取任务」与
      // 「按缓存键取结果」都需要一次额外的唯一索引，而它们本来就是自然主键。
      // 快照里的主键在 explicit_pk（列名列表）里，不是 primaryKey。
      expect(explicitPrimaryKeyOf('ai_tasks'), <String>[
        'task_id',
      ], reason: 'task_id 必须是主键：任务记录是「当前态」，同 id 只能有一行');
      expect(explicitPrimaryKeyOf('ai_result_cache_records'), <String>[
        'cache_key',
      ]);
    });

    test('v11 快照新增搜索服务表（T031），且不丢 v10 的任何实体', () {
      final File v11Snapshot = File('drift_schemas/drift_schema_v11.json');
      expect(
        v11Snapshot.existsSync(),
        isTrue,
        reason: '缺少 v11 快照。可用 drift_dev schema dump 重新导出（见本文件顶部说明）。',
      );
      final Map<String, dynamic> v11Decoded =
          jsonDecode(v11Snapshot.readAsStringSync()) as Map<String, dynamic>;
      final List<Map<String, dynamic>> v11Entities =
          (v11Decoded['entities'] as List<dynamic>)
              .cast<Map<String, dynamic>>();
      final Set<String> v11Names = v11Entities
          .map(
            (Map<String, dynamic> e) =>
                (e['data'] as Map<String, dynamic>)['name'] as String,
          )
          .toSet();

      // v10 的全部实体都必须保留：v11 只**新增**一张表与它的两个索引。
      final Map<String, dynamic> v10Decoded = jsonDecode(
        File('drift_schemas/drift_schema_v10.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      final Set<String> v10Names = (v10Decoded['entities'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map(
            (Map<String, dynamic> e) =>
                (e['data'] as Map<String, dynamic>)['name'] as String,
          )
          .toSet();
      expect(
        v11Names,
        containsAll(v10Names),
        reason: 'v11 只新增搜索服务表，不得删除 v10 的任何实体',
      );
      expect(v11Names.difference(v10Names), <String>{
        'search_service_records',
        'ux_search_service_label',
        'ix_search_service_sort',
      }, reason: 'v11 相对 v10 的新增实体应只有一张表与它的两个索引');

      final Set<String> columns =
          ((v11Entities.firstWhere(
                        (Map<String, dynamic> e) =>
                            (e['data'] as Map<String, dynamic>)['name'] ==
                            'search_service_records',
                      )['data']
                      as Map<String, dynamic>)['columns']
                  as List<dynamic>)
              .cast<Map<String, dynamic>>()
              .map((Map<String, dynamic> c) => c['name'] as String)
              .toSet();
      expect(
        columns,
        containsAll(<String>[
          'id',
          'label',
          'protocol_id',
          'base_url',
          'enabled',
          'sort_order',
          'max_results',
          'timeout_seconds',
          'allow_private_endpoint',
          'is_default_for_tasks',
          'created_at',
          'updated_at',
        ]),
      );

      // SET-039 的硬约束：这张表也**不得**出现凭据列（Key 只住 Keychain）。
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
    });

    test('v12 快照新增文章的 AI 摘要三列（T034），且不丢 v11 的任何实体', () {
      final File v12Snapshot = File('drift_schemas/drift_schema_v12.json');
      expect(
        v12Snapshot.existsSync(),
        isTrue,
        reason: '缺少 v12 快照。可用 drift_dev schema dump 重新导出（见本文件顶部说明）。',
      );
      final Map<String, dynamic> v12Decoded =
          jsonDecode(v12Snapshot.readAsStringSync()) as Map<String, dynamic>;
      final List<Map<String, dynamic>> v12Entities =
          (v12Decoded['entities'] as List<dynamic>)
              .cast<Map<String, dynamic>>();
      final Set<String> v12Names = v12Entities
          .map(
            (Map<String, dynamic> e) =>
                (e['data'] as Map<String, dynamic>)['name'] as String,
          )
          .toSet();

      // v11 的全部实体都必须保留：v12 **只加列**，不新增也不删除任何表/索引。
      final Map<String, dynamic> v11Decoded = jsonDecode(
        File('drift_schemas/drift_schema_v11.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      final Set<String> v11Names = (v11Decoded['entities'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map(
            (Map<String, dynamic> e) =>
                (e['data'] as Map<String, dynamic>)['name'] as String,
          )
          .toSet();
      expect(
        v12Names,
        v11Names,
        reason: 'v12 只给 articles 加三列，实体集合必须与 v11 完全一致',
      );

      final Map<String, dynamic> articlesEntity = v12Entities.firstWhere(
        (Map<String, dynamic> e) =>
            (e['data'] as Map<String, dynamic>)['name'] == 'articles',
      );
      final List<Map<String, dynamic>> articleColumns =
          ((articlesEntity['data'] as Map<String, dynamic>)['columns']
                  as List<dynamic>)
              .cast<Map<String, dynamic>>();
      final Set<String> columnNames = articleColumns
          .map((Map<String, dynamic> c) => c['name'] as String)
          .toSet();
      expect(
        columnNames,
        containsAll(<String>[
          'ai_summary',
          'ai_summary_at',
          'ai_summary_model',
          // 源摘要必须仍在：AI 摘要**不覆盖**它（架构 4.2「原文始终保留」）。
          'summary',
        ]),
      );

      // 三列都可空且无默认值：历史行没有「生成过 AI 摘要」这个事实，
      // 用源摘要或时间回填会让界面显示一个用户从未生成的摘要。
      for (final String name in <String>[
        'ai_summary',
        'ai_summary_at',
        'ai_summary_model',
      ]) {
        final Map<String, dynamic> column = articleColumns.firstWhere(
          (Map<String, dynamic> c) => c['name'] == name,
        );
        expect(column['nullable'], isTrue, reason: '$name 必须可空');
        expect(
          column['default_dart'] ?? column['default'],
          isNull,
          reason: '$name 不得有默认值（回填会伪装成用户生成过）',
        );
      }
    });

    test('v13 快照新增翻译的两张表（T035），且不丢 v12 的任何实体', () {
      final File v13Snapshot = File('drift_schemas/drift_schema_v13.json');
      expect(
        v13Snapshot.existsSync(),
        isTrue,
        reason: '缺少 v13 快照。可用 drift_dev schema dump 重新导出（见本文件顶部说明）。',
      );
      final Map<String, dynamic> v13Decoded =
          jsonDecode(v13Snapshot.readAsStringSync()) as Map<String, dynamic>;
      final List<Map<String, dynamic>> v13Entities =
          (v13Decoded['entities'] as List<dynamic>)
              .cast<Map<String, dynamic>>();
      final Set<String> v13Names = v13Entities
          .map(
            (Map<String, dynamic> e) =>
                (e['data'] as Map<String, dynamic>)['name'] as String,
          )
          .toSet();

      // v12 的全部实体都必须保留：v13 只**新增**两张表与它们的索引。
      final Map<String, dynamic> v12Decoded = jsonDecode(
        File('drift_schemas/drift_schema_v12.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      final Set<String> v12Names = (v12Decoded['entities'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map(
            (Map<String, dynamic> e) =>
                (e['data'] as Map<String, dynamic>)['name'] as String,
          )
          .toSet();
      expect(
        v13Names,
        containsAll(v12Names),
        reason: 'v13 只新增翻译表，不得删除 v12 的任何实体',
      );
      expect(v13Names.difference(v12Names), <String>{
        'article_translation_records',
        'translation_segment_records',
        'ux_translations_article_language',
        'ux_translation_segments_translation_index',
      }, reason: 'v13 相对 v12 的新增实体应只有两张表与它们的索引');

      Map<String, dynamic> table(String name) => v13Entities.firstWhere(
        (Map<String, dynamic> e) =>
            (e['data'] as Map<String, dynamic>)['name'] == name,
      );
      Set<String> columnsOf(String name) =>
          ((table(name)['data'] as Map<String, dynamic>)['columns']
                  as List<dynamic>)
              .cast<Map<String, dynamic>>()
              .map((Map<String, dynamic> c) => c['name'] as String)
              .toSet();

      expect(
        columnsOf('article_translation_records'),
        containsAll(<String>[
          'id',
          'article_id',
          'target_language',
          'source_digest',
          'source_length',
          'model_label',
          'created_at',
          'updated_at',
        ]),
      );
      expect(
        columnsOf('translation_segment_records'),
        containsAll(<String>[
          'id',
          'translation_id',
          'segment_index',
          'block_kind',
          'level',
          'source_digest',
          'source_text',
          'status',
          'translated_text',
          'source_truncated',
          'updated_at',
        ]),
      );

      // 「原文始终保留」的**结构性**证据：v13 不得给 articles 增加任何列。
      // 译文有自己的归属，源正文因此没有第二条写入路径。
      final Map<String, dynamic> v13Articles = table('articles');
      final Set<String> v13ArticleColumns =
          ((v13Articles['data'] as Map<String, dynamic>)['columns']
                  as List<dynamic>)
              .cast<Map<String, dynamic>>()
              .map((Map<String, dynamic> c) => c['name'] as String)
              .toSet();
      final List<Map<String, dynamic>> v12EntitiesForColumns =
          (v12Decoded['entities'] as List<dynamic>)
              .cast<Map<String, dynamic>>();
      final Map<String, dynamic> v12Articles = v12EntitiesForColumns.firstWhere(
        (Map<String, dynamic> e) =>
            (e['data'] as Map<String, dynamic>)['name'] == 'articles',
      );
      final Set<String> v12ArticleColumns =
          ((v12Articles['data'] as Map<String, dynamic>)['columns']
                  as List<dynamic>)
              .cast<Map<String, dynamic>>()
              .map((Map<String, dynamic> c) => c['name'] as String)
              .toSet();
      expect(
        v13ArticleColumns,
        v12ArticleColumns,
        reason: 'v13 不得改动 articles 的任何列（原文本体、正文与摘要都要原样保留）',
      );
    });

    test('v14 快照新增新闻配置三表与订阅的新闻开关列（T036）', () {
      final File v14Snapshot = File('drift_schemas/drift_schema_v14.json');
      expect(
        v14Snapshot.existsSync(),
        isTrue,
        reason: '缺少 v14 快照。可用 drift_dev schema dump 重新导出（见本文件顶部说明）。',
      );
      final Map<String, dynamic> v14Decoded =
          jsonDecode(v14Snapshot.readAsStringSync()) as Map<String, dynamic>;
      final List<Map<String, dynamic>> v14Entities =
          (v14Decoded['entities'] as List<dynamic>)
              .cast<Map<String, dynamic>>();
      final Set<String> v14Names = v14Entities
          .map(
            (Map<String, dynamic> e) =>
                (e['data'] as Map<String, dynamic>)['name'] as String,
          )
          .toSet();

      final Map<String, dynamic> v13Decoded = jsonDecode(
        File('drift_schemas/drift_schema_v13.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      final Set<String> v13Names = (v13Decoded['entities'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map(
            (Map<String, dynamic> e) =>
                (e['data'] as Map<String, dynamic>)['name'] as String,
          )
          .toSet();
      expect(
        v14Names,
        containsAll(v13Names),
        reason: 'v14 只新增新闻配置，不得删除 v13 的任何实体',
      );
      expect(v14Names.difference(v13Names), <String>{
        'news_required_site_records',
        'news_config_entry_records',
        'news_prompt_version_records',
        'ix_news_required_sites_order',
        'ux_news_config_entries_kind_order',
        'ux_news_prompt_versions_language_version',
      }, reason: 'v14 相对 v13 的新增实体应只有三张表与它们的索引');

      Map<String, dynamic> table(String name) => v14Entities.firstWhere(
        (Map<String, dynamic> e) =>
            (e['data'] as Map<String, dynamic>)['name'] == name,
      );
      Set<String> columnsOf(String name) =>
          ((table(name)['data'] as Map<String, dynamic>)['columns']
                  as List<dynamic>)
              .cast<Map<String, dynamic>>()
              .map((Map<String, dynamic> c) => c['name'] as String)
              .toSet();
      List<Map<String, dynamic>> columns(String name) =>
          ((table(name)['data'] as Map<String, dynamic>)['columns']
                  as List<dynamic>)
              .cast<Map<String, dynamic>>();

      expect(
        columnsOf('news_required_site_records'),
        containsAll(<String>[
          'id',
          'name',
          'url',
          'enabled',
          'sort_order',
          'created_at',
          'updated_at',
        ]),
      );
      expect(
        columnsOf('news_config_entry_records'),
        containsAll(<String>['id', 'kind', 'value', 'sort_order']),
      );
      expect(
        columnsOf('news_prompt_version_records'),
        containsAll(<String>[
          'id',
          'language',
          'version',
          'mode',
          'task_instruction',
          'output_spec',
          'advanced_prompt',
          'note',
          'created_at',
        ]),
      );

      // SET-050 的可空开关：null 表示「跟随订阅启用状态」，因此不得有默认值、不得 NOT NULL。
      final Map<String, dynamic> newsEnabledColumn = columns('feeds')
          .firstWhere((Map<String, dynamic> c) => c['name'] == 'news_enabled');
      expect(newsEnabledColumn['nullable'], isTrue);
      expect(
        newsEnabledColumn['default_dart'] ?? newsEnabledColumn['default'],
        isNull,
        reason: '默认值会让「从未选择过」与「显式选了参与」不可分辨',
      );

      // 既有实体不得被删：订阅表只多了一列。
      final Map<String, dynamic> v13Feeds =
          (v13Decoded['entities'] as List<dynamic>)
              .cast<Map<String, dynamic>>()
              .firstWhere(
                (Map<String, dynamic> e) =>
                    (e['data'] as Map<String, dynamic>)['name'] == 'feeds',
              );
      final Set<String> v13FeedColumns =
          ((v13Feeds['data'] as Map<String, dynamic>)['columns']
                  as List<dynamic>)
              .cast<Map<String, dynamic>>()
              .map((Map<String, dynamic> c) => c['name'] as String)
              .toSet();
      expect(
        columnsOf('feeds'),
        containsAll(v13FeedColumns),
        reason: '订阅表原有列不得消失',
      );
    });

    test('v15 快照新增每日新闻任务版本表（T037）', () {
      final File v15Snapshot = File('drift_schemas/drift_schema_v15.json');
      expect(
        v15Snapshot.existsSync(),
        isTrue,
        reason: '缺少 v15 快照。可用 drift_dev schema dump 重新导出（见本文件顶部说明）。',
      );
      final Map<String, dynamic> v15Decoded =
          jsonDecode(v15Snapshot.readAsStringSync()) as Map<String, dynamic>;
      final List<Map<String, dynamic>> v15Entities =
          (v15Decoded['entities'] as List<dynamic>)
              .cast<Map<String, dynamic>>();
      final Set<String> v15Names = v15Entities
          .map(
            (Map<String, dynamic> e) =>
                (e['data'] as Map<String, dynamic>)['name'] as String,
          )
          .toSet();

      final Map<String, dynamic> v14Decoded = jsonDecode(
        File('drift_schemas/drift_schema_v14.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      final Set<String> v14Names = (v14Decoded['entities'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map(
            (Map<String, dynamic> e) =>
                (e['data'] as Map<String, dynamic>)['name'] as String,
          )
          .toSet();
      expect(
        v15Names,
        containsAll(v14Names),
        reason: 'v15 只新增一张表，不得删除 v14 的任何实体',
      );
      expect(v15Names.difference(v14Names), <String>{
        'news_runs',
        'ux_news_runs_date_tz_version',
        'ix_news_runs_local_date',
        'ix_news_runs_current',
      }, reason: 'v15 相对 v14 的新增实体应只有一张表与三条索引');

      final Map<String, dynamic> newsRuns = v15Entities.firstWhere(
        (Map<String, dynamic> e) =>
            (e['data'] as Map<String, dynamic>)['name'] == 'news_runs',
      );
      final Set<String> runColumns =
          ((newsRuns['data'] as Map<String, dynamic>)['columns']
                  as List<dynamic>)
              .cast<Map<String, dynamic>>()
              .map((Map<String, dynamic> c) => c['name'] as String)
              .toSet();
      expect(
        runColumns,
        containsAll(<String>[
          'id',
          'local_date',
          'time_zone',
          'version',
          'task_status',
          'input_snapshot',
          'snapshot_hash',
          'site_results',
          'materials',
          'items',
          'draft_text',
          'provider_alias',
          'model_id',
          'consumed_tokens',
          'attempt_count',
          'error_kind',
          'stage',
          'verification_method',
          'is_current',
          'created_at',
        ]),
      );

      // **数据库不含秘密**（架构 5.1、第 8 节）：这一张表不得出现任何 Key / 凭据 / 请求头列。
      for (final String column in runColumns) {
        expect(
          column.toLowerCase(),
          isNot(
            anyOf(contains('key'), contains('secret'), contains('token_ref')),
          ),
          reason: 'news_runs 不得持有凭据或 Key（$column）',
        );
      }

      // 只有成功/部分成功的版本才可能是当前展示版本：这条规则必须在 DDL 里。
      // 快照里它落在表级 constraints（drift 对 customConstraints 的导出位置）。
      final List<dynamic> constraints =
          (newsRuns['data'] as Map<String, dynamic>)['constraints']
              as List<dynamic>;
      expect(
        constraints.cast<String>(),
        contains(
          "CHECK (is_current = 0 OR task_status IN ('succeeded', 'partial'))",
        ),
        reason: '失败草稿不得覆盖成功版本，这条约束必须落在 DDL 上',
      );
    });

    test('v16 快照新增同步基线与协议状态四表（T041）', () {
      final File v16Snapshot = File('drift_schemas/drift_schema_v16.json');
      expect(
        v16Snapshot.existsSync(),
        isTrue,
        reason: '缺少 v16 快照。可用 drift_dev schema dump 重新导出（见本文件顶部说明）。',
      );
      final Map<String, dynamic> v16Decoded =
          jsonDecode(v16Snapshot.readAsStringSync()) as Map<String, dynamic>;
      final List<Map<String, dynamic>> v16Entities =
          (v16Decoded['entities'] as List<dynamic>)
              .cast<Map<String, dynamic>>();
      final Set<String> v16Names = v16Entities
          .map(
            (Map<String, dynamic> e) =>
                (e['data'] as Map<String, dynamic>)['name'] as String,
          )
          .toSet();

      final Map<String, dynamic> v15Decoded = jsonDecode(
        File('drift_schemas/drift_schema_v15.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      final Set<String> v15Names = (v15Decoded['entities'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map(
            (Map<String, dynamic> e) =>
                (e['data'] as Map<String, dynamic>)['name'] as String,
          )
          .toSet();
      expect(
        v16Names,
        containsAll(v15Names),
        reason: 'v16 只新增同步四表与它们的索引，不得删除 v15 的任何实体',
      );
      expect(v16Names.difference(v15Names), <String>{
        'sync_state_records',
        'sync_pending_changes',
        'ux_sync_pending_entity_field',
        'ix_sync_pending_revision',
        'sync_tombstones',
        'ux_sync_tombstones_entity',
        'ix_sync_tombstones_at',
        'sync_feed_alias_records',
        'ux_sync_feed_aliases_local',
        'ix_sync_feed_aliases_sync_id',
        'ux_articles_sync_key',
      }, reason: 'v16 相对 v15 的新增实体应只有四张表、六条索引与文章同步键唯一索引');

      // **数据库不含秘密**（架构 5.1、第 8 节）：同步表不得出现 WebDAV 密码、
      // API Key 或任何凭据列——SET-071 只住 Keychain。
      final Map<String, Set<String>> expectedColumns = <String, Set<String>>{
        'sync_state_records': <String>{
          'id',
          'base_version',
          'local_revision',
          'last_synced_at',
          'device_name',
          'supports_conditional_write',
          'capability_probed_at',
        },
        'sync_pending_changes': <String>{
          'id',
          'entity_kind',
          'entity_key',
          'field_name',
          'revision',
          'changed_at',
        },
        'sync_tombstones': <String>{
          'id',
          'entity_kind',
          'entity_key',
          'deleted_at',
          'revision',
          'display_name',
        },
        'sync_feed_alias_records': <String>{
          'id',
          'sync_id',
          'local_feed_id',
          'created_at',
        },
      };
      for (final MapEntry<String, Set<String>> entry
          in expectedColumns.entries) {
        final Map<String, dynamic> table = v16Entities.firstWhere(
          (Map<String, dynamic> e) =>
              (e['data'] as Map<String, dynamic>)['name'] == entry.key,
        );
        final Set<String> columns =
            ((table['data'] as Map<String, dynamic>)['columns']
                    as List<dynamic>)
                .cast<Map<String, dynamic>>()
                .map((Map<String, dynamic> c) => c['name'] as String)
                .toSet();
        expect(
          columns,
          entry.value,
          reason: '${entry.key} 的列清单必须与投影口径一致（不含任何凭据列）',
        );
        for (final String column in columns) {
          expect(
            column.toLowerCase(),
            isNot(
              anyOf(
                contains('password'),
                contains('secret'),
                contains('api_key'),
              ),
            ),
            reason: '$entry.key 不得持有凭据（$column）',
          );
        }
      }
    });
  });
}
