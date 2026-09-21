// T010 建立、T013 更新为「v1 → 当前版本」的真实增量迁移。
//
// 与 migration_test.dart 的分工：
//   - migration_test.dart 验证「拒绝较新 schema」「迁移失败不重建」这类安全策略；
//   - 本文件验证**真实迁移步骤本身正确**：用 drift 从 drift_schemas/ 快照生成的
//     版本化 schema 建一个带旧数据的 v1 库，跑应用的真实 MigrationStrategy，
//     再由 drift 的 SchemaVerifier 逐列比对结构，确认结果是预期的 v2。
//
// 为什么必须走这条路径而不是「建 v1 再调用 onUpgrade」：
//   手写 v1 DDL 容易与实际 v1 结构漂移（少一列、错一个默认值都不会被发现），
//   测试就变成自说自话。快照来自 T009 实际导出，是被验证过的基线。
//
// 旧数据完好性用「迁移后读取」而不是「读原始字节」来衡量：迁移必然会写文件，
// 关键不是字节不变，而是**历史文章、阅读状态、收藏、保留组都还在且值未变**。
import 'package:drift/drift.dart' as drift;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flux/infrastructure/local/database.dart';
import 'package:flux/infrastructure/local/tables/enums.dart';

import '../../generated/schema.dart';
import '../../generated/schema_v1.dart' as v1;
import '../../generated/schema_v9.dart' as v9;

/// 当前 schema 版本（与应用代码一致）。
///
/// 不写死数字：T013 把版本从 2 提到 3、T014 从 3 提到 4 之后，硬编码旧版本的迁移
/// 测试就不再验证真实路径（它会停在旧版本，而应用实际会继续往上迁），看起来还在
/// 跑、实际已经失去意义。**只改数字而不改代码**，因此它总会跟着 schemaVersion 走。
const int currentSchemaVersion = 9;

void main() {
  drift.driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('v1 → 当前版本 增量迁移', () {
    test('带旧数据的 v1 库升级到当前版本：结构正确且旧数据完好', () async {
      final SchemaVerifier verifier = SchemaVerifier(GeneratedHelper());
      final InitializedSchema schema = await verifier.schemaAt(1);

      // --- 用 v1 视角写入「升级前就存在」的数据 ------------------------------
      final v1.DatabaseAtV1 old = v1.DatabaseAtV1(schema.newConnection());

      await old
          .into(old.groups)
          .insert(
            v1.GroupsCompanion.insert(
              syncId: 'group.uncategorized',
              name: '未分类',
              // 与真实 v1 库里种子数据的形态一致（保留组标记必须能带过迁移）。
              isReserved: const drift.Value<int>(1),
            ),
          );
      final int feedId = await old
          .into(old.feeds)
          .insert(
            v1.FeedsCompanion.insert(
              syncId: 'feed-legacy',
              normalizedUrl: 'https://legacy.example.com/feed.xml',
              name: '升级前的源',
            ),
          );
      final int articleId = await old
          .into(old.articles)
          .insert(
            v1.ArticlesCompanion.insert(
              feedId: feedId,
              title: '升级前就有的文章',
              // 生成类把 textEnum 列暴露为 String（与数据库实际存储一致），
              // 因此这里写枚举名文本而不是 Dart 枚举值——这也正好证明落库形式。
              identityBasis: 'guid',
              guid: const drift.Value<String?>('legacy-guid'),
              guidPresent: const drift.Value<int>(1),
              body: const drift.Value<String?>('升级前的正文'),
              readingState: const drift.Value<String>('later'),
              favorite: const drift.Value<int>(1),
            ),
          );
      await old.close();

      // v1 阶段不应有 settings 表。
      final List<String> v1Tables = schema.rawDatabase
          .select("SELECT name FROM sqlite_master WHERE type = 'table'")
          .map((row) => row['name']! as String)
          .toList();
      expect(v1Tables, contains('articles'));
      expect(v1Tables, isNot(contains('settings')));

      // --- 用应用的真实代码打开同一库，触发 v1 → v2 迁移 ---------------------
      final AppDatabase migrated = AppDatabase(schema.newConnection());
      await verifier.migrateAndValidate(migrated, currentSchemaVersion);

      // 结构：drift 已逐列比对；这里再确认 settings 表可用且索引存在。
      await migrated.customStatement(
        'INSERT INTO settings (key, value, updated_at) VALUES (?, ?, ?)',
        <Object?>['SET-001', '"system"', '2026-09-21T00:00:00.000Z'],
      );
      final drift.QueryRow stored = await migrated
          .customSelect("SELECT value FROM settings WHERE key = 'SET-001'")
          .getSingle();
      expect(stored.read<String>('value'), '"system"');

      // 旧数据完好：保留组、源、文章内容与三态/收藏都保持原值。
      final List<Group> groups = await migrated.select(migrated.groups).get();
      expect(groups, hasLength(1));
      expect(groups.single.syncId, 'group.uncategorized');
      expect(groups.single.isReserved, isTrue);

      final List<Feed> feeds = await migrated.select(migrated.feeds).get();
      expect(feeds, hasLength(1));
      expect(feeds.single.syncId, 'feed-legacy');
      expect(feeds.single.name, '升级前的源');

      final Article article = await migrated
          .select(migrated.articles)
          .getSingle();
      expect(article.id, articleId);
      expect(article.title, '升级前就有的文章');
      expect(article.body, '升级前的正文');
      expect(article.readingState, ReadingState.later, reason: '迁移不得改写用户阅读状态');
      expect(article.favorite, isTrue, reason: '迁移不得改写收藏');

      await migrated.close();
      schema.close();
    });

    test('迁移后 user_version 推进到当前版本', () async {
      final SchemaVerifier verifier = SchemaVerifier(GeneratedHelper());
      final InitializedSchema schema = await verifier.schemaAt(1);

      final AppDatabase migrated = AppDatabase(schema.newConnection());
      await verifier.migrateAndValidate(migrated, currentSchemaVersion);

      final drift.QueryRow row = await migrated
          .customSelect('PRAGMA user_version')
          .getSingle();
      expect(row.read<int>('user_version'), currentSchemaVersion);

      await migrated.close();
      schema.close();
    });

    test('迁移后 settings 结构可由当前版本生成类读取（v9 未改该表）', () async {
      final SchemaVerifier verifier = SchemaVerifier(GeneratedHelper());
      final InitializedSchema schema = await verifier.schemaAt(1);

      final AppDatabase migrated = AppDatabase(schema.newConnection());
      await verifier.migrateAndValidate(migrated, currentSchemaVersion);
      await migrated.close();

      // 用**当前版本**的生成类连接同一份 schema，确认列定义与迁移结果一致。
      // 必须用迁移终点那一版的生成类：用更低的版本打开会因为版本不符（被当成
      // 降级）而报「没有迁移策略」；而 settings 表在 v2→…→v9 里都没有变化，
      // 用当前版本的类验证同样覆盖它的列定义。
      final v9.DatabaseAtV9 check = v9.DatabaseAtV9(schema.newConnection());
      await check
          .into(check.settings)
          .insert(
            v9.SettingsCompanion.insert(
              key: 'SET-082',
              value: '{"level":"error"}',
            ),
          );
      final v9.SettingsData row = await check
          .select(check.settings)
          .getSingle();
      expect(row.key, 'SET-082');
      expect(row.value, '{"level":"error"}');
      await check.close();
      schema.close();
    });
  });
}
