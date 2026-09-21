// 当天自动摘要计数的本机实现（T034；SET-064）。
//
// 用 settings 窄表的 device. 命名空间（与引导标记、视觉发送告知同一个做法）：这一项是
// **本机运行计数**，不是 SET 编号（架构第 6 节的 SET 清单是产品设置，计数不是用户偏好），
// 也**不参与同步**（多设备各自计数会互相覆盖，而额度是每台设备各自的费用边界）。
//
// 键里带日期（`device.autoSummaryUsed.YYYY-MM-DD`）而不是「一个数 + 一个日期」：按日期分行
// 之后「跨午夜自动归零」不需要任何重置逻辑——新的一天查不到记录就是 0。用「重置」的写法
// 需要一个可靠的每日调度点，而应用可能整天没启动过。
library;

import 'package:drift/drift.dart';

import 'package:flux/core/core.dart';
import 'package:flux/features/articles/application/auto_summary_batch.dart';

import 'database.dart';

/// 计数的键前缀。
const String kAutoSummaryUsedPrefix = 'device.autoSummaryUsed.';

/// 基于设置窄表的当天计数实现。
final class SettingsDailySummaryCounter implements DailySummaryCounter {
  /// 绑定一个已打开的数据库。
  const SettingsDailySummaryCounter(this._db);

  final AppDatabase _db;

  @override
  Future<Result<int>> readUsed(String localDate) async {
    try {
      final Setting? row =
          await (_db.select(_db.settings)
                ..where(($SettingsTable t) => t.key.equals(_key(localDate))))
              .getSingleOrNull();
      if (row == null) {
        return const Ok<int>(0);
      }
      final Object? decoded = SettingValueCodec.decodeOrNull(row.value);
      // 损坏的值按 0 处理而不是报错：计数读不出来时「今天还没用额度」是保守方向的
      // **错误**答案（会多发），因此这里改用**上限**兜底——见下面的说明。
      if (decoded is! int || decoded < 0) {
        // 读不出合法计数时返回上限本身（= 剩余 0）：宁可不跑，也不要因为一行坏数据
        // 把当天的额度当成无限。
        return const Ok<int>(_corruptedFallback);
      }
      return Ok<int>(decoded);
    } on Exception catch (error, stackTrace) {
      return Err<int>(
        StorageError(
          operation: 'dailySummary.readUsed',
          detail: error.runtimeType.toString(),
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  @override
  Future<Result<void>> addUsed(String localDate, int count) async {
    if (count <= 0) {
      return okUnit();
    }
    final Result<int> current = await readUsed(localDate);
    if (current.isErr) {
      return Err<void>(current.errorOrNull!);
    }
    try {
      await _db
          .into(_db.settings)
          .insertOnConflictUpdate(
            SettingsCompanion.insert(
              key: _key(localDate),
              value: SettingValueCodec.encode(current.valueOrNull! + count),
              updatedAt: Value<DateTime>(DateTime.now().toUtc()),
            ),
          );
      return okUnit();
    } on Exception catch (error, stackTrace) {
      return Err<void>(
        StorageError(
          operation: 'dailySummary.addUsed',
          detail: error.runtimeType.toString(),
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  /// 损坏计数的兜底值。
  ///
  /// 取一个**大于任何合理上限**的数：调用方拿它去算剩余额度会得到 0，因此坏数据的方向
  /// 是「今天不跑」，而不是「今天无限跑」。费用边界上的错误方向必须是保守的那一个。
  static const int _corruptedFallback = 1 << 20;

  static String _key(String localDate) => '$kAutoSummaryUsedPrefix$localDate';
}

/// 数据库不可用时的当天计数（T034 的降级启动路径）。
///
/// 两个方向都**明确失败**而不是静默按 0：读返回 0 会让批处理以为「今天还有全部额度」并
/// 开始计费（而计数根本存不下来，下一次刷新又会再花一遍）；写返回成功会让额度记账看起来
/// 有效而实际没有落盘。费用相关的降级必须是 fail-closed。
final class DegradedDailySummaryCounter implements DailySummaryCounter {
  /// 构造降级实现。
  const DegradedDailySummaryCounter();

  @override
  Future<Result<int>> readUsed(String localDate) async => Err<int>(
    StorageError(operation: 'dailySummary.readUsed', detail: '本次运行数据库不可用'),
  );

  @override
  Future<Result<void>> addUsed(String localDate, int count) async => Err<void>(
    StorageError(operation: 'dailySummary.addUsed', detail: '本次运行数据库不可用'),
  );
}
