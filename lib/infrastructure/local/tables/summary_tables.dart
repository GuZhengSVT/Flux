// 每日总结与引用（T009，架构 5.1 的 Summary / Citation；功能契约见 4.4）。
//
// 本表只落**结构性事实**：按哪个设备时区、基于哪份输入快照、由哪个模型、处于
// 什么任务状态产出，以及每条引用的材料与获取方式。生成流程、预算、故障转移和
// 引用校验属于 T036–T040，不在此实现。
library;

import 'package:drift/drift.dart';

import 'package:flux/core/core.dart';

import 'article_tables.dart';

/// 每日总结的一个版本。
///
/// “成功版本不被草稿覆盖”体现在 [isCurrent] 与 [taskStatus] 的组合上：只有
/// succeeded/partial 才允许把 [isCurrent] 置为真，失败/取消的尝试保留为历史行，
/// 便于排查与“保留上一次成功总结”。
///
/// 索引与查询场景：`ix_summary_versions_local_date` 按“设备本地日期 + 当时时区”
/// 取当日版本与历史记录（D-07：日期归属不随时区变化重写）。
@TableIndex(
  name: 'ix_summary_versions_local_date',
  columns: {#localDate, #timeZone},
)
class SummaryVersions extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// 设备本地日期键（`YYYY-MM-DD`）。日期与 [timeZone] 在任务开始时固化，
  /// 之后即使设备时区变化也不重写历史归属（D-07、架构 4.4）。
  TextColumn get localDate => text()();

  /// 任务开始时的统计时区（IANA 名称）。
  TextColumn get timeZone => text()();

  /// 输入快照引用：指向当次固定下来的文章集合（T037 落地具体快照表）。
  /// 这里只保存不透明引用与内容哈希，避免 T009 提前实现 AI 输入模型。
  TextColumn get inputSnapshotRef => text().nullable()();

  /// 输入快照内容哈希：同一输入重复生成时可据此判定缓存是否失效。
  TextColumn get inputSnapshotHash => text().nullable()();

  /// 模型元数据：提供商别名与模型 ID 分开，避免把端点/凭据写进这一层。
  TextColumn get providerAlias => text().nullable()();
  TextColumn get modelId => text().nullable()();

  /// 任务状态引用，复用 core 的任务状态机枚举（9 态，架构 4.5）。
  TextColumn get taskStatus => textEnum<TaskStatus>()();

  /// 是否为当前对外展示的版本。
  BoolColumn get isCurrent => boolean().withDefault(const Constant(false))();

  /// 总结正文（校验通过后的最终文本）。
  TextColumn get content => text().nullable()();

  /// 生成/保存时间（UTC）。
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  /// 只有成功/部分成功的版本才可能是“当前展示版本”。
  ///
  /// 这条规则放在数据库层而不是只靠业务代码：失败、取消或中断的尝试即使被误
  /// 标成当前版本，也必须被数据库拒绝，从而保证“上次成功总结不被草稿覆盖”
  /// （架构 4.4/4.5）。取值域必须与 core 的 [TaskStatus] 名称保持一致。
  @override
  List<String> get customConstraints => <String>[
    "CHECK (is_current = 0 OR task_status IN ('succeeded', 'partial'))",
  ];
}

/// 总结条目引用的材料（架构 4.4：只可使用真实获取的 sourceId）。
///
/// 保存标题、URL、时间、最小摘录与材料哈希；[accessMethod] 区分 RSS/抓取/搜索，
/// 使“只读 RSS 未联网核验”与真实联网证据在数据上可分辨。
///
/// 索引与查询场景：`ix_citations_summary` 载入某版本的全部引用做展示与校验；
/// `ix_citations_source` 反向查询某材料被哪些总结引用（来源冲突/转载聚类排查）。
@TableIndex(name: 'ix_citations_summary', columns: {#summaryVersionId})
@TableIndex(name: 'ix_citations_source', columns: {#sourceId})
class Citations extends Table {
  IntColumn get id => integer().autoIncrement()();

  IntColumn get summaryVersionId =>
      integer().references(SummaryVersions, #id)();

  /// 材料来源标识；必须是真实获取过的材料，不允许模型编造的地址。
  TextColumn get sourceId => text()();

  TextColumn get title => text().nullable()();
  TextColumn get url => text().nullable()();

  /// 材料发布时间（源声明，UTC）；未知为 null。
  DateTimeColumn get publishedAt => dateTime().nullable()();

  /// 本机实际获取该材料的时刻（UTC）；用于区分“材料时间”与“访问时间”。
  DateTimeColumn get accessedAt => dateTime().nullable()();

  /// 最小摘录（只保留支撑结论所需的片段，不为引用长期保留整篇正文）。
  TextColumn get excerpt => text()();

  /// 材料哈希：引用校验用，避免只凭标题/URL 判断同一材料。
  TextColumn get materialHash => text().nullable()();

  /// 获取方式（rss / fetch / search）。
  TextColumn get accessMethod => textEnum<CitationAccessMethod>()();

  /// 本地文章引用：引用指向本机文章时为该文章 ID（可空），外部来源则为 null。
  /// 用 SET NULL：文章被彻底删除时不留下指向不存在行的悬空引用，但引用记录
  /// 本身仍保留（材料哈希与摘录可继续支撑历史总结的说明性）。
  IntColumn get articleId => integer().nullable().references(
    Articles,
    #id,
    onDelete: KeyAction.setNull,
  )();
}
