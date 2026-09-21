// 删除事件（墓碑）表（T018，schema v5）。
//
// 为什么删除需要一个**独立的记录**而不是只把行删掉：
//   架构 5.2 规定「删除使用墓碑，首发不自动清除」，5.3 规定「用户彻底删除时列出
//   关联摘要/引用/缓存并清理，不能留下隐藏副本」。两句话的组合含义是：删除是一个
//   需要被**记住**的事件——它决定了后续同步不得让这条订阅复活（已删除条目不复活），
//   也决定了 T047 的清理预览要能回答「我删过什么」。只把行删掉会让这三件事都无从
//   回答。
//
// 本表只记**事件**，不记正文与凭据：名称与规范化地址用于让用户认出「删的是哪一个」，
// 正文与凭据不在其中（架构第 8 节：墓碑不是第二条泄露路径）。
library;

import 'package:drift/drift.dart';

/// 被删除实体的类型。
enum DeletionEntityType {
  /// 订阅。
  feed,

  /// 分组。
  group,
}

/// 一次删除操作的墓碑记录。
///
/// 索引与查询场景：`ix_deletion_events_sync_id` 按跨设备标识查「这条订阅是否已被
/// 本机删除」（T045 的同步应用前检查）；`ix_deletion_events_deleted_at` 供后续清理
/// 与统计按时间范围列举。
@TableIndex(name: 'ix_deletion_events_sync_id', columns: {#syncId})
@TableIndex(name: 'ix_deletion_events_deleted_at', columns: {#deletedAt})
class DeletionEvents extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// 实体类型（feed / group）。
  ///
  /// 用文本列而不是 CHECK 约束：与 `feeds.lastRefreshResult` 同一条理由——这是
  /// 运行期记录而非用户数据本体，未来若新增一类可删除实体，加 CHECK 会让旧值在
  /// 新代码下变成非法值而需要迁移；读取侧的未知值回退已能安全处理。
  TextColumn get entityType => text()();

  /// 被删除实体的**跨设备稳定标识**（`Feeds.syncId` / `Groups.syncId`）。
  ///
  /// 存 syncId 而不是本机自增 id：墓碑的意义在于跨设备与跨导入批次可对齐，
  /// 而本机 id 在另一台设备上必然指向别的行（架构 5.2）。
  TextColumn get syncId => text()();

  /// 删除时的显示名（让用户与诊断能认出删的是哪一个）。
  TextColumn get displayName => text()();

  /// 删除时是否选择了「保留收藏」。
  ///
  /// 这是架构 5.2「删除订阅的保留收藏选择进入同步操作元数据」在本机的落点：
  /// 别的设备应用这次删除前必须能知道本机当时选了哪一档，否则它会按自己的默认值
  /// 静默清掉一批用户本意要保留的收藏。为空表示该事件不涉及这个选择（例如分组
  /// 移动分支）。
  BoolColumn get keepFavorites => boolean().nullable()();

  /// 本次删除清理掉的文章数。
  IntColumn get deletedArticleCount =>
      integer().withDefault(const Constant(0))();

  /// 本次删除保留下来的收藏数（脱离源进入资料库）。
  IntColumn get keptFavoriteCount => integer().withDefault(const Constant(0))();

  /// 删除发生的时间（UTC 存储）。
  DateTimeColumn get deletedAt => dateTime()();
}
