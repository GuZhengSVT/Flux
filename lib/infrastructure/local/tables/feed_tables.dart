// 订阅与分组实体（T009，架构 5.1 的 Feed / Folder）。
//
// 表名由 drift 按类名转 snake_case：Groups → groups，Feeds → feeds。
library;

import 'package:drift/drift.dart';

/// 订阅分组（架构 4.1：创建、重命名、删除、排序、置顶）。
///
/// “未分类”是**保留组**：由 `AppDatabase` 在建库时按固定 syncId 播种，
/// 删除保护在用例层实现（T014），这里只把 [isReserved] 落库，使保护规则
/// 可被查询而不是靠魔法 ID 判断。
///
/// 索引与查询场景：`ux_groups_sync_id` 保证跨设备稳定标识唯一（同步对齐与
/// 重复导入匹配），同时让“未分类”可按 syncId 稳定定位而不依赖本机自增 id。
@TableIndex(name: 'ux_groups_sync_id', columns: {#syncId}, unique: true)
class Groups extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// 跨设备稳定标识（架构 5.1/5.2）。本机自增 [id] 不外传。
  TextColumn get syncId => text()();

  TextColumn get name => text()();

  /// 排序权重；用户拖动/菜单排序后写入。置顶是独立布尔值，不靠负权重表达。
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  BoolColumn get pinned => boolean().withDefault(const Constant(false))();

  /// 是否为保留组（“未分类”）。保留组不允许删除，只能移动其中订阅。
  BoolColumn get isReserved => boolean().withDefault(const Constant(false))();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

/// 订阅源（架构 5.1 的 Feed；功能契约见 4.1）。
///
/// 索引与查询场景：
/// - `ux_feeds_sync_id`：跨设备对齐与文章同步键构造（5.2）。
/// - `ux_feeds_normalized_url`：OPML 往返与重复导入时匹配已有源，不重置状态。
/// - `ix_feeds_group_sort`：订阅管理页按分组展示并保持用户排序。
@TableIndex(name: 'ux_feeds_sync_id', columns: {#syncId}, unique: true)
@TableIndex(
  name: 'ux_feeds_normalized_url',
  columns: {#normalizedUrl},
  unique: true,
)
@TableIndex(name: 'ix_feeds_group_sort', columns: {#groupId, #sortOrder})
class Feeds extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// 跨设备稳定标识；文章同步键用它（而非本机 id）构造确定性摘要。
  TextColumn get syncId => text()();

  /// 规范化 URL：仅用于**匹配与去重**（OPML 往返、重复导入、跨设备对齐），
  /// 不用于请求。带凭据的原始地址见 [credentialRef]，避免秘密进入普通列。
  TextColumn get normalizedUrl => text()();

  /// 显示名称（用户可改）。
  TextColumn get name => text()();

  /// 源自带名称，与显示名分开保存（架构 5.1）；未解析到时为 null。
  TextColumn get sourceName => text().nullable()();

  /// 所属分组；删除分组时由用例层决定移动到未分类或删除订阅，不使用级联。
  IntColumn get groupId => integer().nullable().references(Groups, #id)();

  /// 加精：只影响显示与强调，不参与新闻选材（架构 4.1）。
  BoolColumn get favorite => boolean().withDefault(const Constant(false))();

  /// 刷新间隔覆盖（分钟）；null 表示跟随全局默认（SET-020 区域）。
  IntColumn get refreshIntervalMinutes => integer().nullable()();

  /// 组内排序权重（架构 5.1：Feed 含「分组、排序」）。置顶是分组属性，
  /// 加精是独立布尔 [favorite]，三者互不替代。
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  /// 条件请求缓存：强 ETag（架构 4.1「有条件请求」，区分 304 与新内容）。
  TextColumn get httpEtag => text().nullable()();

  /// 条件请求缓存：Last-Modified 原文（HTTP 规范要求原样回送）。
  TextColumn get httpLastModified => text().nullable()();

  /// 本机安全存储中的凭据引用（T010 落地）；数据库中**不存秘密本身**。
  TextColumn get credentialRef => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}
