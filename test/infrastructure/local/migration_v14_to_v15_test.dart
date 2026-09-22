// T037：v14 → v15 的真实增量迁移（新增每日新闻任务版本表）。
//
// 这一步要验四件事：
//   1) **news_runs 与它的三条索引真的建出**（漏建索引只有结构校验能发现）；
//   2) **既有数据零丢失**（订阅、文章三态/收藏/正文、新闻来源配置）；
//   3) **既有的新闻配置表不被改动**（本步只加表，不碰 v14 的三张配置表）；
//   4) **DDL 层的「成功版本才可能是当前版本」约束真的生效**（失败草稿写不进去）。
library;

import 'package:drift/drift.dart' as drift;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flux/infrastructure/local/database.dart';

import '../../generated/schema.dart';
import '../../generated/schema_v14.dart' as v14;

/// 当前 schema 版本（与应用代码一致）。
const int currentSchemaVersion = 16;

/// 一次写入用的固定创建时刻。
final DateTime _createdAt = DateTime.utc(2026, 9, 22, 13);

void main() {
  drift.driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('v14 → 当前版本 增量迁移', () {
    test('带旧数据的 v14 库升级：news_runs 就绪、旧数据零丢失', () async {
      final SchemaVerifier verifier = SchemaVerifier(GeneratedHelper());
      final InitializedSchema schema = await verifier.schemaAt(14);

      final v14.DatabaseAtV14 old = v14.DatabaseAtV14(schema.newConnection());
      final int feedId = await old
          .into(old.feeds)
          .insert(
            v14.FeedsCompanion.insert(
              syncId: 'feed-v14',
              normalizedUrl: 'https://v14.example.com/feed.xml',
              name: '升级前的源',
              newsEnabled: const drift.Value<int?>(0),
            ),
          );
      await old
          .into(old.articles)
          .insert(
            v14.ArticlesCompanion.insert(
              feedId: drift.Value<int?>(feedId),
              title: '升级前的文章',
              identityBasis: 'guid',
              favorite: const drift.Value<int>(1),
              readingState: const drift.Value<String>('later'),
              body: const drift.Value<String?>('升级前的正文'),
            ),
          );
      await old
          .into(old.newsPromptVersionRecords)
          .insert(
            v14.NewsPromptVersionRecordsCompanion.insert(
              language: 'zh-Hans',
              version: 1,
              mode: 'composed',
              taskInstruction: '升级前的任务说明',
              outputSpec: '升级前的输出规范',
              advancedPrompt: '',
            ),
          );
      await old.close();

      final AppDatabase migrated = AppDatabase(schema.newConnection());
      await verifier.migrateAndValidate(migrated, currentSchemaVersion);

      final Feed feed = (await migrated.select(migrated.feeds).get()).single;
      expect(feed.syncId, 'feed-v14');
      expect(feed.newsEnabled, isFalse, reason: 'v14 的用户选择必须原样保留');

      final Article article =
          (await migrated.select(migrated.articles).get()).single;
      expect(article.title, '升级前的文章');
      expect(article.favorite, isTrue);
      expect(article.readingState.name, 'later');
      expect(article.body, '升级前的正文');

      final NewsPromptVersionRecord prompt =
          (await migrated.select(migrated.newsPromptVersionRecords).get())
              .single;
      expect(prompt.version, 1);
      expect(prompt.taskInstruction, '升级前的任务说明');

      // 新表是空的：升级前不存在「已经生成过今日总结」这个事实。
      expect(await migrated.select(migrated.newsRuns).get(), isEmpty);

      await migrated.close();
      schema.close();
    });

    test('新库（v15）直接建出 news_runs 与三条索引', () async {
      final AppDatabase db = AppDatabase.memory();
      await db.customSelect('SELECT 1').get();
      final List<drift.QueryRow> objects = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type IN ('table', 'index')",
          )
          .get();
      final Set<String> names = objects
          .map((drift.QueryRow r) => r.read<String>('name'))
          .toSet();
      expect(
        names,
        containsAll(<String>[
          'news_runs',
          'ux_news_runs_date_tz_version',
          'ix_news_runs_local_date',
          'ix_news_runs_current',
        ]),
      );
      await db.close();
    });
  });

  group('news_runs 的 DDL 约束', () {
    test('失败草稿**不能**被标成当前版本（架构 4.4「保留上一次成功总结」）', () async {
      final AppDatabase db = AppDatabase.memory();
      await db.customSelect('SELECT 1').get();
      addTearDown(db.close);

      Future<void> insert({
        required int version,
        required String status,
        required bool current,
      }) async {
        await db
            .customSelect(
              '''
INSERT INTO news_runs (
  local_date, time_zone, version, task_status, input_snapshot, snapshot_hash,
  site_results, materials, items, consumed_tokens, attempt_count, is_current, created_at
) VALUES (?, ?, ?, ?, '{}', 'h', '[]', '[]', '[]', 0, 0, ?, ?)
''',
              variables: <drift.Variable<Object>>[
                const drift.Variable<String>('2026-09-22'),
                const drift.Variable<String>('Asia/Shanghai'),
                drift.Variable<int>(version),
                drift.Variable<String>(status),
                drift.Variable<int>(current ? 1 : 0),
                drift.Variable<DateTime>(_createdAt),
              ],
            )
            .get();
      }

      await insert(version: 1, status: 'succeeded', current: true);
      await insert(version: 2, status: 'failed', current: false);
      await expectLater(
        insert(version: 3, status: 'cancelled', current: true),
        throwsA(isA<Exception>()),
        reason: '取消/失败的版本不允许成为当前展示版本',
      );

      // 同一日期 + 时区下版本号唯一（并发两次生成不会写出两个 v1）。
      await expectLater(
        insert(version: 1, status: 'partial', current: false),
        throwsA(isA<Exception>()),
        reason: '同一日期与时区下版本号必须唯一',
      );
    });
  });
}
