// 本机运行状态存储（T011）。
//
// 与 settings 表的关系：settings 表按 T010 的口径只存**注册表里存在的 SET 编号**，
// 未注册键会被仓储明确拒绝（避免拼错键名产生永远读不到的幽灵配置）。但有一类
// 状态既不是 SET 项，也不属于业务数据，例如「首次引导是否已完成」。
//
// 为什么不是新加一个 SET 编号：架构第 6 节的 SET 表是文档里的权威清单，测试会
// 逐条比对 70 个编号与文档一致。为了让一个内部标记而扩张产品设置清单，会让
// 「文档 = 实现」这条不变量失效；而它也确实不是用户可配置的偏好。
//
// 因此这里复用同一张窄表，但用**带命名空间的键**区分来源：
//   - 键前缀 `device.`，例如 `device.onboardingCompleted`；
//   - 命名空间保证不会与 SET-编号形态的键冲突；
//   - 这些键**不进入** T041 的同步投影与 T046 的明文备份投影——两者的入口
//     （SettingsRepository.readEffective / readSyncableCommon）都只遍历注册表编号，
//     因此本机状态天然被排除，不需要在同步层再写一条「记得排除」的规则。
library;

import 'package:drift/drift.dart';

import 'package:flux/core/core.dart';

import 'database.dart';
// 表类 Settings 在 tables/ 下定义，database.dart 只 import 不 export，
// 因此这里显式引用；与 settings_repository.dart 的做法一致。
import 'tables/settings_tables.dart';

/// 本机状态键。
abstract final class DeviceStateKey {
  /// 命名空间前缀（与 SET 编号形态互不冲突）。
  static const String namespace = 'device.';

  /// 首次引导是否已完成（T011）。
  static const String onboardingCompleted = 'device.onboardingCompleted';

  /// 定时总结的首次费用与数据发送告知是否已确认（T040）。
  ///
  /// 为什么必须持久化、且必须是**本机**项：定时任务没有任何对话框，用户点不到任何确认；
  /// 没有这条记录就等于「未经告知地后台付费运行」。同步到另一台设备更不行——那台设备会
  /// 因为一条从别处来的记录而自动开跑并自己付费（架构 4.4「执行开关是本机项」）。
  static const String newsCostNoticeAcknowledged =
      'device.newsCostNoticeAcknowledged';

  /// 全部本机状态键。
  static const List<String> all = <String>[
    onboardingCompleted,
    newsCostNoticeAcknowledged,
  ];
}

/// 本机运行状态的类型化读写。
///
/// 只放「不属于 SET、不属于业务实体」的本机状态；一旦某个键需要跨设备同步或成为
/// 用户可配置项，它就应该回到 SET 注册表，而不是继续留在这里。
final class DeviceStateRepository {
  /// 绑定到一个已打开的 [AppDatabase]。
  const DeviceStateRepository(this._db);

  final AppDatabase _db;

  /// 读取布尔状态；未写过的键返回 [fallback]（默认 false）。
  ///
  /// 与设置仓储一致：读不到不算失败，调用方总能拿到一个可用值。
  Future<Result<bool>> readBool(String key, {bool fallback = false}) async {
    final Setting? row;
    try {
      row = await (_db.select(
        _db.settings,
      )..where((Settings t) => t.key.equals(key))).getSingleOrNull();
    } on Exception catch (error, stackTrace) {
      return Err<bool>(
        StorageError(
          operation: 'deviceState.readBool',
          detail: key,
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
    if (row == null) {
      return Ok<bool>(fallback);
    }
    final Object? decoded = SettingValueCodec.decodeOrNull(row.value);
    if (decoded is! bool) {
      // 损坏的行不静默当成 false：读不出合法值时报错，由调用方决定回退策略，
      // 否则一个被写坏的行会表现成「引导没做过」，反复弹出向导。
      return Err<bool>(
        StorageError(
          operation: 'deviceState.readBool',
          detail: key,
          isMissing: false,
        ),
      );
    }
    return Ok<bool>(decoded);
  }

  /// 写入布尔状态（幂等）。
  Future<Result<void>> writeBool(String key, bool value) async {
    try {
      await _db
          .into(_db.settings)
          .insertOnConflictUpdate(
            SettingsCompanion.insert(
              key: key,
              value: SettingValueCodec.encode(value),
              updatedAt: Value<DateTime>(DateTime.now().toUtc()),
            ),
          );
    } on Exception catch (error, stackTrace) {
      return Err<void>(
        StorageError(
          operation: 'deviceState.writeBool',
          detail: key,
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
    return okUnit();
  }
}
