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

  /// 是否参与自动刷新（SET-022 的「启用」；T014，schema v4）。
  ///
  /// 为什么不复用 [refreshIntervalMinutes] 的空值或 0 来表达「禁用」：
  /// SET-022 把「启用」与「刷新间隔」列为**两个独立**的可配置项，语义也不同——
  /// 禁用是「这个源我现在不想看它联网」，间隔是「多久检查一次」。用同一个字段
  /// 表达两者会让「禁用期间保留的间隔设置」无处存放：用户重新启用后，之前设的
  /// 30 分钟会被抹成默认值。因此单列一个布尔列。
  ///
  /// 默认 true：升级前就存在的订阅在用户显式关闭之前照常刷新，不因迁移静默改变行为。
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();

  /// 刷新间隔覆盖（分钟）；null 表示跟随全局默认（SET-020 区域）。
  ///
  /// 0 表示「手动」：该源不参与定时刷新（SET-022 的 refreshInterval 取值之一），
  /// 与 [enabled] 的区别是——禁用同时挡住手动刷新入口，手动只是不自动跑。
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

  /// 最近一次**尝试**抓取的时间（UTC；T013）。
  ///
  /// 与 [updatedAt] 分工不同，不能互相替代：
  ///   - [updatedAt] 是「这一行（含名称/分组等用户改动）最后写入时间」；
  ///   - 本列是「最后一次联网检查这个源的时间」，无论结果是 304、没有新文章
  ///     还是网络失败都会更新。
  /// 架构 4.1 要求区分「304」「没有新文章」「部分解析失败」「网络失败」四种结果
  /// 并保留旧内容，界面需要如实显示「上次检查：多久之前」——因此这一列必须在
  /// 失败时也推进；否则一个长期失败的源会一直显示很久以前的时间，看起来像
  /// 没在刷新。
  DateTimeColumn get lastCheckedAt => dateTime().nullable()();

  /// 最近一次抓取的**结果类别**（T013），用于诊断与界面说明。
  ///
  /// 刻意保存枚举名文本而不是布尔「成功/失败」：架构 4.1 明确要求区分四种结果，
  /// 用布尔会把「304 没有变化」和「网络失败」压成同一类。
  ///
  /// 不为此加 CHECK 约束：这是**运行时诊断**，不是用户数据本体。若某天新增一种
  /// 结果类别，加 CHECK 会让旧值在新代码下变成非法值而需要迁移；而读取侧的
  /// 未知值回退（见 FeedRefreshResult.fromName）已经能安全处理。
  TextColumn get lastRefreshResult => text().nullable()();

  /// 最近一次失败的类型化类别（T013）；成功时为 null。
  ///
  /// 只存**类别名**（如 network/parse/tooLarge），不存错误消息：消息可能含 URL
  /// 里的秘密参数，脱敏是日志层的职责，普通列不应成为第二条泄露路径。
  TextColumn get lastRefreshErrorKind => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}
