// 同步状态与墓碑（T041，schema v16；架构 5.1 的 SyncState 实体、架构 5.2 的条件发布协议）。
//
// 四张表各自回答一个不同的问题，拆开而不是塞进一张宽表：
//   * `sync_state`（**单行**）：本机同步到哪了——共同基线版本、本地修订号、上次成功时间；
//   * `sync_pending_changes`：**哪些本地改动还没上传**（每条一行，同一实体可有多行）；
//   * `sync_tombstones`：删除了什么（跨设备不得复活，架构 5.2）；
//   * `sync_feed_aliases`：同一订阅在两台设备上的 syncId 对应关系（架构 5.2「保存别名」）。
//
// 为什么不合并成一张「变更表」（用一个 kind 列区分 pending/tombstone/alias）：
//   - 三者的**生命周期不同**——待同步变更在上传确认后要删掉，墓碑要长期保留（架构 5.2
//     「首发不自动清除」），别名是长期映射；塞一起会让「确认成功后清哪些行」变成一条
//     需要按 kind 分支的删除语句，而漏写一个分支就会把墓碑删掉（于是已删除的订阅复活）；
//   - 三者的**唯一键形态不同**（变更按实体+字段、墓碑按实体、别名按 syncId），
//     合表的唯一约束只能取最宽的那个，等于放弃约束。
//
// 本文件**没有凭据列**：SET-071 的 WebDAV 密码与 SET-027 的秘密只住 Keychain，
// 因此明文备份与 flux.sqlite 都不会携带它们。设备名（SET-070 的「设备名」）是
// 标识而非秘密，可以落库。
library;

import 'package:drift/drift.dart';

import 'feed_tables.dart';

/// 同步基线状态（**单行表**，用固定主键 [SyncStateRecords.singletonId] 保证只有一行）。
///
/// 为什么是单行而不是「每台设备一行」：本机只知道**自己**的同步进度与共同基线，
/// 远端每个设备的进度是它们各自的事（架构 5.2 没有要求设备间互相汇报进度）。
/// 多行会立刻引入「哪一行是我」这个只有本机能回答的问题。
class SyncStateRecords extends Table {
  /// 固定主键值（与 database.dart 的种子写入一致）。
  static const int singletonId = 1;

  IntColumn get id => integer()();

  /// 共同基线版本（上一次成功同步后的 manifest 版本；未同步过时为 null）。
  ///
  /// 三方合并（T043）要拿它当 merge base：没有它就只能二选一，而「二选一」在
  /// 「两台设备各改一个字段」时会丢掉一边的改动（架构 5.2 明确要求不同字段可合并）。
  TextColumn get baseVersion => text().nullable()();

  /// 本地修订号（单调递增；每批本地改动 +1）。
  ///
  /// 架构 5.2「同步开始时固定本地修订号和待上传变更集合」与「提交结果仅确认已包含的
  /// 修订」都建立在它之上：上传期间产生的新改动会写入更大的修订号，因此确认时按
  /// 「≤ 本次快照修订」删除待同步行，而不是把整表 dirty 标记清空。
  IntColumn get localRevision => integer().withDefault(const Constant(0))();

  /// 上次成功同步的时刻（UTC）；从未同步成功为 null。
  DateTimeColumn get lastSyncedAt => dateTime().nullable()();

  /// 本机设备名（SET-070「设备名可改」；用户可见，仅作标识）。
  TextColumn get deviceName => text().nullable()();

  /// 服务器是否支持强 ETag/If-Match 条件写（T042 的能力探测结果）。
  ///
  /// 三态（null = 尚未探测）：架构 5.2 要求「不具备可靠条件发布的服务器降级为只读拉取
  /// ……不开启不安全多端自动覆盖」。用 null 表示「还不知道」而不是默认 false，否则
  /// 首次配置成功的设备会被当成「服务器不支持」而白白降级。
  BoolColumn get supportsConditionalWrite => boolean().nullable()();

  /// 上次能力探测的时刻（UTC）。
  DateTimeColumn get capabilityProbedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

/// 一条待同步的本地变更（架构 5.2「固定待上传变更集合」）。
///
/// 字段级粒度（[fieldName] 可为空表示整行变更）：架构 5.2 要求「不同字段独立变更可合并；
/// 同字段并发显示冲突」，因此「哪一列变了」必须能表达。只记「这一行变过」会让 T043 无法
/// 区分「你改了名称、我改了分组」（可自动合并）与「你我都改了名称」（必须选版）。
@TableIndex(
  name: 'ux_sync_pending_entity_field',
  columns: {#entityKind, #entityKey, #fieldName},
  unique: true,
)
@TableIndex(name: 'ix_sync_pending_revision', columns: {#revision})
class SyncPendingChanges extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// 实体类别（取值见 core 的 SyncEntityKind）。
  TextColumn get entityKind => text()();

  /// 实体键（SET 编号 / 订阅 syncId / 分组 syncId / 文章同步键）。
  TextColumn get entityKey => text()();

  /// 字段名；空串表示「整行」（例如新插入的订阅）。
  ///
  /// 用空串而不是 NULL 参与唯一索引：SQLite 的唯一索引里 NULL 之间**互不冲突**，
  /// 于是同一条订阅可以被插入任意多行「整行变更」，唯一的约束形同虚设。空串是普通值，
  /// 因此「同一实体+同一字段只有一行待同步变更」这条不变量能被数据库真正保证。
  TextColumn get fieldName => text().withDefault(const Constant(''))();

  /// 该变更所属的本地修订号（同步开始时取最大值作为本次快照修订）。
  IntColumn get revision => integer()();

  /// 记录时刻（UTC）。
  DateTimeColumn get changedAt => dateTime()();
}

/// 墓碑（架构 5.2「删除使用墓碑，首发不自动清除」）。
///
/// 与 T018 的 `deletion_events` 分工：那张表记的是**用户做过一次删除操作**（含影响
/// 范围与「是否保留收藏」这份操作元数据，供界面与 T045 展示）；本表记的是**同步协议
/// 需要的最小事实**——「这个键被删了」。两者不能合并：deletion_events 有业务语义
/// （保留收藏的选择），而墓碑要覆盖文章状态这类没有「删除操作」的实体。
@TableIndex(
  name: 'ux_sync_tombstones_entity',
  columns: {#entityKind, #entityKey},
  unique: true,
)
@TableIndex(name: 'ix_sync_tombstones_at', columns: {#deletedAt})
///
/// 数据类名显式指定为 SyncTombstoneRecord（表名仍是 sync_tombstones）：drift 默认按
/// 「去掉末尾 s」派生数据类名，那样会生成 SyncTombstone，与 core 领域类型同名，让每个
/// 使用点都必须在两个 import 之间消歧。用 @DataClassName 只改数据类名、不改表名，
/// 因此快照与索引里的表名保持自然形态（与 AiModelRecords 用类名绕开的做法等价）。
@DataClassName('SyncTombstoneRecord')
class SyncTombstones extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// 实体类别（取值见 core 的 SyncEntityKind）。
  TextColumn get entityKind => text()();

  /// 实体键（跨设备稳定；**绝不用本机自增 id**，架构 5.2）。
  TextColumn get entityKey => text()();

  /// 删除时刻（UTC；本机时钟，仅作参考）。
  ///
  /// 为什么不能只靠它判先后：架构 5.2 明确「不得……仅比较设备墙钟」。它在这里只是
  /// 诊断与展示（「什么时候删的」），真正的先后由墓碑所属的 [revision]、共同基线版本
  /// 与条件写冲突（412）共同决定，不靠这个时间戳做决策。
  DateTimeColumn get deletedAt => dateTime()();

  /// 记录这次删除的本地修订号。
  IntColumn get revision => integer()();

  /// 删除时的显示名快照（让用户与诊断能认出删的是什么；不含正文与凭据）。
  TextColumn get displayName => text().nullable()();
}

/// 订阅对齐别名（架构 5.2「两台独立导入同一源时先按规范 URL 对齐 Feed 并保存别名」）。
///
/// 语义：本机 [localFeedId] 这条订阅在别的设备上叫 [syncId]。保存别名的意义是让
/// **下一次**同步不必再重跑 URL 匹配——源改了地址之后 URL 就再也对不上了，而别名还在。
///
/// 类名用 SyncFeedAliasRecords（表名 sync_feed_alias_records）而不是 SyncFeedAliases：
/// drift 按「去掉末尾 s」派生数据类名，后者会生成一个与 core 领域类型同名的
/// `SyncFeedAliase`（去掉 s 只掉一个字符），既难读又容易与领域类型混淆（与
/// AiModelRecords / NewsRequiredSiteRecords 同一个理由）。
@TableIndex(
  name: 'ux_sync_feed_aliases_local',
  columns: {#localFeedId, #syncId},
  unique: true,
)
@TableIndex(name: 'ix_sync_feed_aliases_sync_id', columns: {#syncId})
class SyncFeedAliasRecords extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// 远端使用的 syncId。
  TextColumn get syncId => text()();

  /// 本机订阅 id（外键；订阅被彻底删除时该行随之消失——别名指向一条不存在的订阅
  /// 只会让下次同步把它当成「需要新建的远端订阅」）。
  IntColumn get localFeedId =>
      integer().references(Feeds, #id, onDelete: KeyAction.cascade)();

  /// 记录时刻（UTC）。
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}
