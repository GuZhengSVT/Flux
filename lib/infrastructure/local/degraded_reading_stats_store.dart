// 数据库不可用时的统计端口（T023 的降级启动路径）。
//
// 与 DegradedArticleCatalogStore 同一口径：**读返回空集合 + 写返回类型化失败**。
//
// 为什么读返回空而不是失败：统计页是「我的」下的一个栏目，数据库打不开时它应当像
// 其他页面一样显示空态 + 顶部降级横幅，而不是红屏；而清空（一个破坏性动作）必须
// 明确失败，绝不能假装成功——用户会以为历史已经删干净了。
library;

import 'package:flux/core/core.dart';

/// 降级实现。
final class DegradedReadingStatsStore implements ReadingStatsStore {
  /// 构造降级实现。
  const DegradedReadingStatsStore();

  @override
  Future<Result<int>> appendSessions(List<ReadingSessionDraft> drafts) async =>
      Err<int>(
        StorageError(
          operation: 'appendSessions',
          detail: '本次运行数据库不可用，阅读时间不会保存',
        ),
      );

  @override
  Future<Result<List<ReadingDayTotal>>> dailyTotals({
    required String fromDate,
    required String toDate,
  }) async => const Ok<List<ReadingDayTotal>>(<ReadingDayTotal>[]);

  @override
  Future<Result<List<int>>> activeYears() async => const Ok<List<int>>(<int>[]);

  @override
  Future<Result<int>> clearAll() async => Err<int>(
    StorageError(operation: 'clearReadingStats', detail: '本次运行数据库不可用，无法清空统计'),
  );
}
