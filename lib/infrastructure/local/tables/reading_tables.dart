// 阅读会话（T009，架构 5.1 的 ReadingSession）。
//
// 统计语义见架构 5.3：前台可见且活跃时累计，失焦/锁屏/后台暂停，5 分钟无交互
// 暂停，按会话时区跨午夜拆分。首发统计**不跨设备相加**，因此会话 ID 是本机的。
library;

import 'package:drift/drift.dart';

import 'article_tables.dart';

/// 一次阅读会话。
///
/// [id] 为本机会话标识，不外传。
/// [articleId] 是“文章键”的本机表示；跨设备键由共享 Feed syncId + 类型标记 +
/// GUID/规范 URL 指纹构造（架构 5.2），在 T041 落地，这里不预置同步列。
///
/// 索引与查询场景：`ix_reading_sessions_article_start` 用于按文章查看阅读历史与
/// 去重合并会话；`ix_reading_sessions_started` 供热力图/七日柱状图按时间范围聚合。
@TableIndex(
  name: 'ix_reading_sessions_article_start',
  columns: {#articleId, #startedAt},
)
@TableIndex(name: 'ix_reading_sessions_started', columns: {#startedAt})
class ReadingSessions extends Table {
  IntColumn get id => integer().autoIncrement()();

  IntColumn get articleId => integer().references(Articles, #id)();

  /// 会话开始（UTC 存储）。
  DateTimeColumn get startedAt => dateTime()();

  /// 会话结束（UTC）；进行中的会话为 null。
  DateTimeColumn get endedAt => dateTime().nullable()();

  /// 有效秒数：只统计前台可见且活跃的时间，暂停区间不计入。
  IntColumn get effectiveSeconds => integer().withDefault(const Constant(0))();

  /// 统计时区（IANA 名称，如 `Asia/Shanghai`）。跨午夜按此时区拆分会话，
  /// 历史统计在用户旅行后仍按当时时区归属。
  TextColumn get timeZone => text()();

  /// 设备本地日期键（`YYYY-MM-DD`，按 [timeZone] 计算）。
  ///
  /// 冗余存储而非每次由 UTC 现算：热力图与七日柱状图按本地日期分组，
  /// 若只存 UTC 就要在查询里重复时区换算，且历史会话的归属会随查询时区变化。
  TextColumn get localDate => text()();
}
