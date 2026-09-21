// Flux 本地数据库（T009）：实体装配、索引、迁移策略与打开封装。
//
// 职责边界（架构 2.2）：本文件只负责**结构与安全打开**，不含网络、业务规则或
// 同步逻辑。查询/事务方法放在同目录的 store/ 下，presentation/application 通过
// 上层接口访问，不直接 import 本文件。
//
// 表结构权威来源：架构说明书 5.1（实体清单）与 4.1（身份与三态规则）。
library;

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

import 'package:flux/core/core.dart';

import 'tables/article_tables.dart';
// database.g.dart 是本文件的 part，只能看到本文件的 import；枚举类型被生成的
// 伴随类与表访问器引用，因此必须在这里直接可见。
import 'tables/enums.dart';
import 'tables/feed_tables.dart';
import 'tables/reading_tables.dart';
import 'tables/summary_tables.dart';

part 'database.g.dart';

/// 应用数据库。
///
/// schema 版本从 1 开始；每次结构变化都必须：
///   1) 提升 [schemaVersion]；
///   2) 在 [migration] 的 `onUpgrade` 里补上**增量**步骤（不允许只改建表语句就当
///      升级完成——旧设备不会重跑 onCreate）；
///   3) 用 `drift_schemas/` 里导出的历史快照补充迁移测试。
@DriftDatabase(
  tables: <Type>[
    Groups,
    Feeds,
    Articles,
    ReadingSessions,
    SummaryVersions,
    Citations,
  ],
)
class AppDatabase extends _$AppDatabase {
  /// 用外部提供的执行器构造（测试注入内存库、生产注入文件库）。
  AppDatabase(super.executor);

  /// 打开（或创建）[file] 指向的数据库文件。
  ///
  /// 只在此处拼装原生执行器；具体数据目录由应用装配层决定（T011），
  /// 本层不依赖 `path_provider`，以免测试被迫引入平台通道。
  factory AppDatabase.openFile(File file) => AppDatabase(NativeDatabase(file));

  /// 内存数据库：单元测试与预览使用，不落盘。
  factory AppDatabase.memory() => AppDatabase(NativeDatabase.memory());

  /// 保留组“未分类”的稳定标识（架构 4.1）。
  ///
  /// 用固定 syncId 而不是固定自增 id：自增 id 在跨设备/导入导出后不保证一致，
  /// 而“未分类”必须能被稳定识别。
  static const String uncategorizedGroupSyncId = 'group.uncategorized';

  /// 保留组显示名（首次启动种子数据；用户可改名，识别依据是 syncId）。
  static const String uncategorizedGroupName = '未分类';

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) async {
      await m.createAll();
      await _seedInitialData();
    },
    onUpgrade: (Migrator m, int from, int to) async {
      // 降级（库比代码新）必须显式失败，绝不用删库重建“修复”。
      // 用户可能用旧版本打开了新版本写过的库；此时原始文件必须保持可回退，
      // 因此这里只报错、不执行任何 DDL（drift 也不会在迁移失败时删除文件）。
      if (from > to) {
        throw StorageError(
          operation: 'openDatabase',
          detail:
              'database schema v$from is newer than supported v$to; '
              'refusing to open (file left untouched, no rebuild)',
        );
      }

      // from < to：版本 1 是首个 schema，尚无增量迁移步骤。
      // 将来新增版本时在这里按 from 逐步补齐，并保留“未知区间直接失败”的兜底，
      // 避免将来误改成静默重建。
      throw StorageError(
        operation: 'openDatabase',
        detail:
            'no migration path from schema v$from to v$to; '
            'refusing to rebuild the database',
      );
    },
    beforeOpen: (OpeningDetails details) async {
      // 外键约束默认关闭；本工程的引用（文章→订阅、会话/引用→文章）依赖它生效。
      // 放在 beforeOpen 而不是连接字符串里，保证所有打开的连接一致。
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  /// 建库种子数据：保留组“未分类”。
  ///
  /// 与业务无关，只保证“未分类”在任何库里都存在且可识别；删除保护属于用例层
  /// 规则（T014）：`isReserved` 为真时仅允许移动其中订阅，不允许删除本组。
  Future<void> _seedInitialData() async {
    await into(groups).insert(
      GroupsCompanion.insert(
        syncId: uncategorizedGroupSyncId,
        name: uncategorizedGroupName,
        isReserved: const Value<bool>(true),
      ),
      mode: InsertMode.insertOrIgnore,
    );
  }
}

/// 以 [Result] 包装的打开操作，供上层在不处理底层异常的情况下分支。
///
/// 打开失败（版本过新、文件损坏、迁移中断）都翻译成 [StorageError]；
/// 编程错误（例如断言）仍会抛出，不被吞掉。
Future<Result<AppDatabase>> openAppDatabase(File file) async {
  AppDatabase? db;
  try {
    db = AppDatabase.openFile(file);
    // 触发一次真实查询，让迁移在这里发生，而不是在第一次业务查询时。
    await db.customStatement('PRAGMA user_version');
    return Ok<AppDatabase>(db);
  } on AppError catch (error, stackTrace) {
    await _closeQuietly(db);
    return Err<AppDatabase>(
      StorageError(
        operation: 'openDatabase',
        detail: error.message,
        cause: error,
        stackTrace: stackTrace,
      ),
    );
  } on Exception catch (error, stackTrace) {
    // sqlite3/drift 自身抛出的异常统一收敛为类型化错误。
    // 只保留异常类型与简短说明，不把可能含路径/内容的原始文本整段透出。
    await _closeQuietly(db);
    return Err<AppDatabase>(
      StorageError(
        operation: 'openDatabase',
        detail: error.runtimeType.toString(),
        cause: error,
        stackTrace: stackTrace,
      ),
    );
  }
}

/// 打开失败时释放底层数据库句柄，避免调用方必须自己关一个“没打开成功”的对象。
///
/// 关闭本身失败不再向上抛：真正的失败原因（版本过新/损坏）更重要，不能被清理
/// 时的次生错误覆盖；此处只保证不把异常泄漏成未处理错误。
Future<void> _closeQuietly(AppDatabase? db) async {
  if (db == null) {
    return;
  }
  try {
    await db.close();
  } on Exception {
    // 忽略：见上方说明。
  }
}
