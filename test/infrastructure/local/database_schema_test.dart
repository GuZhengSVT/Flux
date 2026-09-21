// T009：v1 建库、表/索引落库、CHECK 与唯一约束、外键实际生效。
//
// 全部使用内存库（sqlite3 原生库在本机 flutter test 下可用，已由本文件实际
// 执行验证），不产生磁盘残留。
import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flux/infrastructure/local/database.dart';

/// 读取 sqlite_master 里的对象名集合。
Future<Set<String>> _schemaObjects(AppDatabase db) async {
  final List<QueryRow> rows = await db
      .customSelect('SELECT name FROM sqlite_master')
      .get();
  return rows.map((QueryRow r) => r.read<String>('name')).toSet();
}

/// 读取某个对象的建表/建索引 SQL。
Future<String> _objectSql(AppDatabase db, String name) async {
  final QueryRow row = await db
      .customSelect(
        'SELECT sql FROM sqlite_master WHERE name = ?',
        variables: <Variable<Object>>[Variable<String>(name)],
      )
      .getSingle();
  return row.read<String>('sql');
}

Future<int> _articleCount(AppDatabase db) async {
  final QueryRow row = await db
      .customSelect('SELECT COUNT(*) AS c FROM articles')
      .getSingle();
  return row.read<int>('c');
}

void main() {
  // 测试会创建多个数据库实例；抑制 drift 的多实例告警（它只在 debug 打印，
  // 但会把测试输出弄得很吵）。
  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  group('v1 建库', () {
    late AppDatabase db;

    setUp(() async {
      db = AppDatabase.memory();
      // 触发真实打开，使 onCreate 与 beforeOpen 都执行过。
      await db.customSelect('SELECT 1').get();
    });

    tearDown(() async {
      await db.close();
    });

    test('schemaVersion 为当前版本（T025 起为 9）', () {
      expect(db.schemaVersion, 9);
    });

    test('架构 5.1 的核心表全部建出', () async {
      final Set<String> objects = await _schemaObjects(db);
      expect(
        objects,
        containsAll(<String>[
          'groups',
          'feeds',
          'articles',
          'reading_sessions',
          'summary_versions',
          'citations',
          'settings',
        ]),
      );
    });

    test('索引按查询场景建出，且条件唯一索引带 WHERE 子句', () async {
      final Set<String> objects = await _schemaObjects(db);
      expect(
        objects,
        containsAll(<String>[
          'ux_feeds_sync_id',
          'ux_feeds_normalized_url',
          'ix_feeds_group_sort',
          'ix_articles_feed_published',
          'ix_articles_reading_state',
          'ix_articles_favorite',
          'ix_articles_body_hash',
          'ix_reading_sessions_article_start',
          'ix_reading_sessions_started',
          'ix_summary_versions_local_date',
          'ix_citations_summary',
          'ix_citations_source',
        ]),
      );

      // 身份索引必须是**条件唯一**：GUID/链接/指纹都可能为 null，多行 null
      // 不能互相冲突，否则“无 GUID 的文章”只能存一条。
      final String guidIndex = await _objectSql(db, 'ux_articles_feed_guid');
      expect(guidIndex.toUpperCase(), contains('UNIQUE'));
      expect(guidIndex.toUpperCase(), contains('WHERE GUID IS NOT NULL'));

      final String linkIndex = await _objectSql(
        db,
        'ux_articles_feed_normalized_link',
      );
      expect(
        linkIndex.toUpperCase(),
        contains('WHERE NORMALIZED_LINK IS NOT NULL'),
      );

      final String fpIndex = await _objectSql(
        db,
        'ux_articles_feed_fingerprint',
      );
      expect(
        fpIndex.toUpperCase(),
        contains('WHERE FALLBACK_FINGERPRINT IS NOT NULL'),
      );
    });

    test('全文检索对象建出（T022：fts5 虚拟表 + 同步触发器）', () async {
      final Set<String> objects = await _schemaObjects(db);
      expect(
        objects,
        containsAll(<String>[
          'articles_fts',
          'articles_fts_ai',
          'articles_fts_ad',
          'articles_fts_au',
        ]),
        reason: '索引表与三个同步触发器都必须落库',
      );

      // 虚拟表的建表语句必须带 tokenizer 与 external content 参数——它们是本任务
      // 中文检索语义的全部依据，被改掉就等于换了一套检索行为。
      final String fts = await _objectSql(db, 'articles_fts');
      expect(fts.toUpperCase(), contains('VIRTUAL TABLE'));
      expect(fts.toLowerCase(), contains('fts5'));
      expect(fts.toLowerCase(), contains("tokenize='trigram'"));
      expect(fts.toLowerCase(), contains("content='articles'"));
      expect(fts.toLowerCase(), contains("content_rowid='id'"));
      // 索引列必须是 articles 里逐字存在的列（rebuild 与触发器两条路径才一致）。
      expect(fts, isNot(contains('feed_title')));
    });

    test('全文索引初始为空（新建库没有文章，也没有多余索引项）', () async {
      final QueryRow row = await db
          .customSelect('SELECT COUNT(*) AS c FROM articles_fts')
          .getSingle();
      expect(row.read<int>('c'), 0);
    });

    test('reading_state 落库为 CHECK 约束，而不是只靠 Dart 类型', () async {
      final String ddl = await _objectSql(db, 'articles');
      expect(ddl, contains('reading_state'));
      expect(ddl.toUpperCase(), contains('CHECK'));
      expect(ddl, contains("'unread'"));
      expect(ddl, contains("'read'"));
      expect(ddl, contains("'later'"));
      // favorite 是独立布尔列，drift 为它附加 0/1 CHECK。
      expect(ddl.toUpperCase(), contains('FAVORITE'));
    });

    test('summary_versions 只允许 succeeded/partial 成为当前版本', () async {
      final String ddl = await _objectSql(db, 'summary_versions');
      expect(ddl, contains('is_current'));
      expect(ddl, contains("'succeeded'"));
      expect(ddl, contains("'partial'"));
    });

    test('“未分类”保留组被播种且可稳定识别', () async {
      final List<Group> groups = await db.select(db.groups).get();
      expect(groups, hasLength(1));
      expect(groups.single.syncId, AppDatabase.uncategorizedGroupSyncId);
      expect(groups.single.isReserved, isTrue);
    });

    test('外键约束实际生效（PRAGMA foreign_keys = ON）', () async {
      final QueryRow row = await db
          .customSelect('PRAGMA foreign_keys')
          .getSingle();
      expect(row.read<int>('foreign_keys'), 1);

      // 不存在的 feed_id 必须被拒绝，避免产生孤儿文章。
      await expectLater(
        db.customStatement(
          'INSERT INTO articles (feed_id, identity_basis, title) '
          "VALUES (9999, 'guid', 'orphan')",
        ),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('约束拒绝非法值', () {
    late AppDatabase db;
    late int feedId;

    setUp(() async {
      db = AppDatabase.memory();
      feedId = await db
          .into(db.feeds)
          .insert(
            FeedsCompanion.insert(
              syncId: 'feed-1',
              normalizedUrl: 'https://example.com/feed.xml',
              name: '示例源',
            ),
          );
    });

    tearDown(() async {
      await db.close();
    });

    test('readingState 非法值插入必须失败', () async {
      // 绕过 Dart 枚举类型，直接用 SQL 写入非法值：这才能证明**数据库层**
      // 而不是编译期类型在拒绝它。
      await expectLater(
        db.customStatement(
          'INSERT INTO articles (feed_id, identity_basis, title, reading_state) '
          "VALUES ($feedId, 'guid', 'bad state', 'archived')",
        ),
        throwsA(isA<Exception>()),
      );
      expect(await _articleCount(db), 0);
    });

    test('三态枚举的三个合法值都能写入，且默认值为 unread', () async {
      for (final String state in <String>['unread', 'read', 'later']) {
        await db.customStatement(
          'INSERT INTO articles (feed_id, identity_basis, title, reading_state) '
          "VALUES ($feedId, 'guid', 'title-$state', '$state')",
        );
      }

      // 不指定 reading_state 时使用默认值。
      await db.customStatement(
        'INSERT INTO articles (feed_id, identity_basis, title) '
        "VALUES ($feedId, 'guid', 'defaulted')",
      );

      final List<String> states =
          (await db
                  .customSelect(
                    'SELECT reading_state FROM articles ORDER BY title',
                  )
                  .get())
              .map((QueryRow r) => r.read<String>('reading_state'))
              .toList();
      expect(states, containsAll(<String>['unread', 'read', 'later']));
      // 按标题排序后首行是 'defaulted'（未指定 reading_state），应为默认值 unread。
      expect(states.first, 'unread');
      expect(await _articleCount(db), 4);
    });

    test('正文完整性四态可写入，未知值被拒绝', () async {
      for (final String completeness in <String>[
        'sourceBody',
        'summaryOnly',
        'extracted',
        'unknown',
      ]) {
        await db.customStatement(
          'INSERT INTO articles (feed_id, identity_basis, title, body_completeness) '
          "VALUES ($feedId, 'guid', 'c-$completeness', '$completeness')",
        );
      }

      await expectLater(
        db.customStatement(
          'INSERT INTO articles (feed_id, identity_basis, title, body_completeness) '
          "VALUES ($feedId, 'guid', 'c-bad', 'fullText')",
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('同一 Feed 内相同 GUID 唯一，不同 Feed 可各自持有同一 GUID', () async {
      final int otherFeed = await db
          .into(db.feeds)
          .insert(
            FeedsCompanion.insert(
              syncId: 'feed-2',
              normalizedUrl: 'https://other.example.com/feed.xml',
              name: '另一个源',
            ),
          );

      await db.customStatement(
        'INSERT INTO articles (feed_id, identity_basis, title, guid, guid_present) '
        "VALUES ($feedId, 'guid', 'first', 'guid-shared', 1)",
      );

      // 同一 Feed 内重复 GUID：拒绝。
      await expectLater(
        db.customStatement(
          'INSERT INTO articles (feed_id, identity_basis, title, guid, guid_present) '
          "VALUES ($feedId, 'guid', 'duplicate', 'guid-shared', 1)",
        ),
        throwsA(isA<Exception>()),
      );

      // 不同 Feed 用同一 GUID：GUID 只在 Feed 范围内识别，必须允许。
      await db.customStatement(
        'INSERT INTO articles (feed_id, identity_basis, title, guid, guid_present) '
        "VALUES ($otherFeed, 'guid', 'same guid other feed', 'guid-shared', 1)",
      );
      expect(await _articleCount(db), 2);
    });

    test('无 GUID 的多篇文章不因 null 互相冲突（条件唯一索引要点）', () async {
      for (int i = 0; i < 3; i++) {
        await db.customStatement(
          'INSERT INTO articles (feed_id, identity_basis, title, guid_present) '
          "VALUES ($feedId, 'normalizedLink', 'no-guid-$i', 0)",
        );
      }
      expect(await _articleCount(db), 3);
    });

    test('summary_versions 的“草稿不得成为当前版本”约束生效', () async {
      // 失败状态不允许标为当前版本。
      await expectLater(
        db.customStatement(
          'INSERT INTO summary_versions '
          '(local_date, time_zone, task_status, is_current) '
          "VALUES ('2026-09-21', 'Asia/Shanghai', 'failed', 1)",
        ),
        throwsA(isA<Exception>()),
      );

      // 成功状态可以。
      await db.customStatement(
        'INSERT INTO summary_versions '
        '(local_date, time_zone, task_status, is_current) '
        "VALUES ('2026-09-21', 'Asia/Shanghai', 'succeeded', 1)",
      );

      // 非当前版本的历史行不受该约束影响（等待配置态也会被记录）。
      await db.customStatement(
        'INSERT INTO summary_versions '
        '(local_date, time_zone, task_status, is_current) '
        "VALUES ('2026-09-22', 'Asia/Shanghai', 'waitingConfiguration', 0)",
      );

      final QueryRow row = await db
          .customSelect('SELECT COUNT(*) AS c FROM summary_versions')
          .getSingle();
      expect(row.read<int>('c'), 2);
    });
  });
}
