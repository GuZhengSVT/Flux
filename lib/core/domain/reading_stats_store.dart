// 阅读统计的读写端口（T023）。
//
// 与 ArticleCatalogStore 同一口径：实现只做数据操作，产品判断在用例层；所有方法
// 不抛异常，失败翻译为 Result.err。
//
// 为什么写入接受的是**已经拆好的 draft**而不是原始时间区间：时区与午夜拆分的规则
// 全部在 core/domain/reading_session.dart 里，写成纯函数才有确定性测试；存储层再拆
// 一次等于把同一条规则实现两遍，而这条规则正是最容易出错的一处。
library;

import '../result.dart';
import 'reading_session.dart';
import 'reading_stats.dart';

/// 阅读统计的读写端口。
abstract interface class ReadingStatsStore {
  /// 追加若干会话行（同一批在一个事务内完成）。
  ///
  /// 返回实际写入的行数。允许写入 0 行：调用方可能在一次 flush 里没有任何有效
  /// 时间（例如刚打开就失焦），那不是错误。
  Future<Result<int>> appendSessions(List<ReadingSessionDraft> drafts);

  /// 按本地日期聚合 from..to（含两端）的有效秒数。
  ///
  /// 日期是 local_date 文本键（YYYY-MM-DD），因此聚合**不依赖查询时的时区**：
  /// 会话在写入时已按当时的时区归属好，用户旅行后历史归属不会漂移。
  Future<Result<List<ReadingDayTotal>>> dailyTotals({
    required String fromDate,
    required String toDate,
  });

  /// 有阅读记录的年份，倒序（最近的在前）。
  Future<Result<List<int>>> activeYears();

  /// 清空全部会话统计（架构 5.3「可关闭并清空历史」）。
  ///
  /// 这是**统计专属**的清除：不得触碰文章、阅读状态、收藏或设置（SET-015 的值也
  /// 不在这里清——清除历史与关掉开关是两件事）。
  Future<Result<int>> clearAll();
}
