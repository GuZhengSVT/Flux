// 分组折叠状态的本机存储（T014；SET-025）。
//
// 与 DeviceStateRepository 共用同一张 settings 窄表与同一个 device. 命名空间前缀，
// 理由也相同：
//   - 折叠状态不是 SET 编号（注册表的 70 个编号是文档权威清单，测试逐条比对），
//     硬塞一个编号会让「文档 = 实现」这条不变量失效；
//   - device. 前缀保证它不会被同步（T041）与明文备份（T046）带走——两者的入口
//     都只遍历注册表编号，本机键天然被排除。
//
// 每个分组一个键（device.feedGroupCollapsed.<groupId>），而不是把所有折叠状态
// 塞进一个 JSON 值：单键写入不会与其他分组的写入互相覆盖，而一个 JSON blob 在
// 「两个分组几乎同时折叠」时会出现后写覆盖先写（读-改-写）的丢失更新。
library;

import 'package:drift/drift.dart';

import 'package:flux/core/core.dart';

import 'database.dart';
import 'tables/settings_tables.dart';

/// 折叠状态键的前缀。
const String groupCollapseKeyPrefix = 'device.feedGroupCollapsed.';

/// 用 settings 窄表保存分组折叠状态。
final class GroupCollapseRepository implements GroupCollapseStore {
  /// 绑定一个已打开的数据库。
  const GroupCollapseRepository(this._db);

  final AppDatabase _db;

  /// 组装一个分组对应的键。
  static String keyFor(int groupId) => '$groupCollapseKeyPrefix$groupId';

  @override
  Future<Result<Map<String, bool>>> readAll() async {
    final List<Setting> rows;
    try {
      // 用 LIKE 前缀过滤而不是把整张表读回来：settings 表里还有 70 个 SET 项与
      // 其他本机键，全读回来再筛只是把工作从 SQLite 搬到了 Dart。
      rows = await (_db.select(
        _db.settings,
      )..where((Settings t) => t.key.like('$groupCollapseKeyPrefix%'))).get();
    } on Exception catch (error, stackTrace) {
      return Err<Map<String, bool>>(
        StorageError(
          operation: 'groupCollapse.readAll',
          detail: error.runtimeType.toString(),
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }

    final Map<String, bool> values = <String, bool>{};
    for (final Setting row in rows) {
      final Object? decoded = SettingValueCodec.decodeOrNull(row.value);
      // 损坏的行**跳过而不是报错**：一个折叠偏好读不出来，不该让整个订阅管理页
      // 变成错误页；跳过等价于「这个分组用默认的展开状态」。
      if (decoded is! bool) {
        continue;
      }
      values[row.key.substring(groupCollapseKeyPrefix.length)] = decoded;
    }
    return Ok<Map<String, bool>>(values);
  }

  @override
  Future<Result<void>> write({
    required int groupId,
    required bool collapsed,
  }) async {
    try {
      await _db
          .into(_db.settings)
          .insertOnConflictUpdate(
            SettingsCompanion.insert(
              key: keyFor(groupId),
              value: SettingValueCodec.encode(collapsed),
              updatedAt: Value<DateTime>(DateTime.now().toUtc()),
            ),
          );
      return okUnit();
    } on Exception catch (error, stackTrace) {
      return Err<void>(
        StorageError(
          operation: 'groupCollapse.write',
          detail: error.runtimeType.toString(),
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }
}
