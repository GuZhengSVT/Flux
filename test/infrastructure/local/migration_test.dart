// T009（T010 改为 v2 基线，T013 改为 v3 基线，T014 改为 v4 基线，
// T018 改为 v5 基线）：迁移安全。
//
// 三条硬要求（架构 5.3「旧版本不能写较新 schema」、手册 6.3「恢复」）：
//   1) 正常按当前 schemaVersion 建库成功；
//   2) 库声明的 schemaVersion 比代码新时，打开必须**失败**，且不得删除/重建原库；
//   3) 迁移步骤自身失败时同样不得重建，原有数据必须保持可回退。
//
// T010 把 schemaVersion 提到 2（新增 settings 表）、T013 提到 3（订阅表补抓取
// 诊断列）、T014 提到 4（订阅表补启用列）、T018 提到 5（文章表支持收藏脱离源 +
// 删除事件表）后，本文件里的「当前版本」相应改为 5，而「代码比库新但迁移写坏」的
// 场景用**比当前版本再高一级**的坏实现模拟（现为 v6）；真正的增量迁移正确性由
// migration_v1_to_v2_test.dart、migration_v2_to_current_test.dart 与
// migration_v4_to_v5_test.dart 用 drift 快照校验。
//
// 测试策略：优先使用内存库与共享的原始 sqlite3 句柄，避免磁盘残留；
// 另有一条真实文件用例，用于直接证明“磁盘上的文件在失败后未被改动”。
import 'dart:io';

// drift 也会导出 `isNull`，与 matcher 的同名匹配器冲突；本文件只用少量 drift
// 类型（NativeDatabase、QueryRow、MigrationStrategy、OpeningDetails），因此加前缀。
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import 'package:flux/core/core.dart';
import 'package:flux/infrastructure/local/database.dart';

/// 模拟“代码已升级到更高版本但迁移步骤写错/失败”的数据库，用于验证失败不重建。
///
/// 版本号必须**严格高于** [AppDatabase.schemaVersion]：等于当前版本时 drift 不会
/// 触发 onUpgrade，测试就变成「什么都没发生也算过」，失去验证力（T013 提到 v3 时
/// 正是被这里暴露出来）。
class _FailingUpgradeDatabase extends AppDatabase {
  _FailingUpgradeDatabase(super.executor);

  @override
  int get schemaVersion => 6;

  @override
  drift.MigrationStrategy get migration => drift.MigrationStrategy(
    onUpgrade: (drift.Migrator m, int from, int to) async {
      // 真实项目里这可能是一条写错的 ALTER、磁盘写满或约束冲突。
      throw StorageError(
        operation: 'onUpgrade',
        detail: 'simulated broken migration step',
      );
    },
    beforeOpen: (drift.OpeningDetails details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}

/// 用原始连接读取 user_version，用于确认失败后没有被重置。
int _userVersion(sqlite.Database raw) => raw.userVersion;

/// 读取某张表的行数；表不存在时返回 null（区分“被删了”与“空表”）。
int? _rowCount(sqlite.Database raw, String table) {
  final sqlite.ResultSet exists = raw.select(
    "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
    <Object?>[table],
  );
  if (exists.isEmpty) {
    return null;
  }
  return raw.select('SELECT COUNT(*) AS c FROM $table').single['c']! as int;
}

void main() {
  setUpAll(() {
    drift.driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  group('正常建库与升级路径', () {
    test('空库首次打开：建表并写入 user_version = 当前版本', () async {
      final AppDatabase db = AppDatabase.memory();
      await db.customSelect('SELECT 1').get();

      final drift.QueryRow row = await db
          .customSelect('PRAGMA user_version')
          .getSingle();
      expect(row.read<int>('user_version'), db.schemaVersion);

      await db.close();
    });

    test('库再次打开不重复播种保留组（种子是幂等的）', () async {
      final sqlite.Database raw = sqlite.sqlite3.openInMemory();
      addTearDown(raw.close);

      // 第一次打开建库并播种。
      final AppDatabase first = AppDatabase(
        NativeDatabase.opened(raw, closeUnderlyingOnClose: false),
      );
      await first.customSelect('SELECT 1').get();
      await first.close();

      // 第二次打开：不触发 onCreate，种子不会重复插入。
      final AppDatabase second = AppDatabase(
        NativeDatabase.opened(raw, closeUnderlyingOnClose: false),
      );
      final List<Group> groups = await second.select(second.groups).get();
      expect(groups, hasLength(1));
      await second.close();

      expect(_rowCount(raw, 'groups'), 1);
      expect(_userVersion(raw), 5);
    });
  });

  group('拒绝比代码新的 schema', () {
    test('库声称 v99：打开失败，且不删除/重建原库', () async {
      final sqlite.Database raw = sqlite.sqlite3.openInMemory();
      addTearDown(raw.close);

      // 手工构造一个“未来版本”的库：有业务数据、user_version 远高于代码。
      raw.execute(
        'CREATE TABLE articles (id INTEGER PRIMARY KEY, title TEXT);',
      );
      raw.execute("INSERT INTO articles (title) VALUES ('未来版本的正文');");
      raw.userVersion = 99;

      final AppDatabase db = AppDatabase(
        NativeDatabase.opened(raw, closeUnderlyingOnClose: false),
      );

      // 迁移被拒绝，错误类型化，不是裸字符串异常。
      await expectLater(
        db.customSelect('SELECT 1').get(),
        throwsA(
          isA<StorageError>().having(
            (StorageError e) => e.operation,
            'operation',
            'openDatabase',
          ),
        ),
      );

      // 原库必须完好：版本号未被改写，原有数据未被清理，也没有被重建成本项目表。
      expect(_userVersion(raw), 99, reason: '失败不得改写 user_version');
      expect(_rowCount(raw, 'articles'), 1, reason: '失败不得删除原有数据');
      expect(_rowCount(raw, 'feeds'), isNull, reason: '失败不得把原库重建成本项目的 schema');

      await db.close();
    });

    test('openAppDatabase 把“版本过新”翻译为 Err(StorageError)', () async {
      final Directory dir = Directory.systemTemp.createTempSync('flux_t009_');
      addTearDown(() {
        if (dir.existsSync()) {
          dir.deleteSync(recursive: true);
        }
      });

      final File file = File('${dir.path}/flux.sqlite');

      // 先写一个 v99 的库文件。
      final sqlite.Database seed = sqlite.sqlite3.open(file.path);
      seed.execute('CREATE TABLE marker (id INTEGER PRIMARY KEY, note TEXT);');
      seed.execute("INSERT INTO marker (note) VALUES ('keep-me');");
      seed.userVersion = 99;
      seed.close();

      final List<int> bytesBefore = file.readAsBytesSync();

      final Result<AppDatabase> opened = await openAppDatabase(file);
      expect(opened.isErr, isTrue);
      expect(opened.errorOrNull, isA<StorageError>());

      // 文件必须仍然存在、内容未被重写；marker 数据与版本号保持原样。
      expect(file.existsSync(), isTrue, reason: '失败不得删除数据库文件');
      expect(file.readAsBytesSync(), bytesBefore, reason: '打开失败不得改动磁盘上的原文件');

      final sqlite.Database reopened = sqlite.sqlite3.open(file.path);
      addTearDown(reopened.close);
      expect(reopened.userVersion, 99);
      expect(_rowCount(reopened, 'marker'), 1);
      expect(_rowCount(reopened, 'feeds'), isNull);
    });

    test('失败后同一连接再次打开仍然失败（不因重试而绕过版本检查）', () async {
      final sqlite.Database raw = sqlite.sqlite3.openInMemory();
      addTearDown(raw.close);
      raw.userVersion = 42;

      final AppDatabase db = AppDatabase(
        NativeDatabase.opened(raw, closeUnderlyingOnClose: false),
      );

      await expectLater(
        db.customSelect('SELECT 1').get(),
        throwsA(isA<StorageError>()),
      );
      await expectLater(
        db.customSelect('SELECT 1').get(),
        throwsA(isA<StorageError>()),
      );
      expect(_userVersion(raw), 42);

      await db.close();
    });
  });

  group('迁移失败不重建数据库', () {
    test('升级步骤抛错：打开失败，原数据与版本号保持可回退', () async {
      final sqlite.Database raw = sqlite.sqlite3.openInMemory();
      addTearDown(raw.close);

      // 先用正常代码建当前版本的库并写入数据（相当于用户升级前的状态）。
      final AppDatabase before = AppDatabase(
        NativeDatabase.opened(raw, closeUnderlyingOnClose: false),
      );
      await before
          .into(before.feeds)
          .insert(
            FeedsCompanion.insert(
              syncId: 'existing-feed',
              normalizedUrl: 'https://a.example.com/feed.xml',
              name: '升级前就有的源',
            ),
          );
      await before.close();
      expect(_userVersion(raw), 5);

      // 用“代码已是 v5 但迁移写坏”的版本打开同一库。
      final _FailingUpgradeDatabase broken = _FailingUpgradeDatabase(
        NativeDatabase.opened(raw, closeUnderlyingOnClose: false),
      );
      await expectLater(
        broken.customSelect('SELECT 1').get(),
        throwsA(isA<StorageError>()),
      );

      // 关键断言：不重建。版本号不变，原数据仍在，schema 未被替换成 v6。
      expect(_userVersion(raw), 5, reason: '迁移失败不得推进版本号');
      expect(
        raw.select('SELECT name FROM feeds').single['name'],
        '升级前就有的源',
        reason: '迁移失败不得清空原数据',
      );
      expect(_rowCount(raw, 'articles'), 0, reason: '原表结构保持不变');

      await broken.close();

      // 失败后仍能用当前代码正常打开：原库保持可回退。
      final AppDatabase recovered = AppDatabase(
        NativeDatabase.opened(raw, closeUnderlyingOnClose: false),
      );
      final List<Feed> feeds = await recovered.select(recovered.feeds).get();
      expect(feeds, hasLength(1));
      expect(feeds.single.syncId, 'existing-feed');
      await recovered.close();
    });

    test('迁移失败后文件仍在磁盘上，可再次读取', () async {
      final Directory dir = Directory.systemTemp.createTempSync(
        'flux_t009_up_',
      );
      addTearDown(() {
        if (dir.existsSync()) {
          dir.deleteSync(recursive: true);
        }
      });

      final File file = File('${dir.path}/flux.sqlite');

      final AppDatabase before = AppDatabase.openFile(file);
      await before
          .into(before.feeds)
          .insert(
            FeedsCompanion.insert(
              syncId: 'file-feed',
              normalizedUrl: 'https://file.example.com/feed.xml',
              name: '文件源',
            ),
          );
      await before.close();

      final List<int> bytesBefore = file.readAsBytesSync();

      final _FailingUpgradeDatabase broken = _FailingUpgradeDatabase(
        NativeDatabase(file),
      );
      await expectLater(
        broken.customSelect('SELECT 1').get(),
        throwsA(isA<StorageError>()),
      );
      await broken.close();

      expect(file.existsSync(), isTrue);
      expect(file.readAsBytesSync(), bytesBefore, reason: '失败不得重写原文件');

      final AppDatabase recovered = AppDatabase.openFile(file);
      final List<Feed> feeds = await recovered.select(recovered.feeds).get();
      expect(feeds, hasLength(1));
      await recovered.close();
    });
  });
}
