// 每日新闻任务的输入快照、逐站状态、材料清单、条目与版本（T037；架构 4.4/5.1、SET-050–063）。
//
// 为什么是**一张宽表**而不是把快照/材料/条目各拆一张：这三组数据在写入时是**同一次**
// 事实（「这次任务基于什么输入、跑出了什么」），拆开之后就会出现「版本行写了、材料还没写」
// 的中间状态，而读取端没有任何查询需要单独读材料行（界面总是要整版一起显示）。与 T030 的
// ai_tasks 同一个判断。
//
// 三列刻意的设计：
//   1) **任务状态用九态文本 + is_current 的 CHECK**：只有 succeeded/partial 才允许成为
//      当前展示版本。这条规则放在 DDL 里而不是只靠应用层，是为了让「失败草稿覆盖成功版本」
//      在数据层也不可能——那正是架构 4.4「保留上一次成功总结」的最后一层保险；
//   2) **没有凭据列、没有 Key、没有请求头**（架构 5.1「数据库不含秘密」、第 8 节）：
//      错误只存结构性类别（error_kind），不存响应体（可能回显请求内容）；
//   3) **快照与材料存 JSON 文本**：它们的字段集合会随任务演进（T038 加证据标签、将来加
//      图片材料），拆成固定列会让每加一项都要一次 schema 迁移，而它们的查询方式始终是
//      「按版本整块读」。
library;

import 'package:drift/drift.dart';

// core 的转出口：`textEnum<TaskStatus>()` 需要 core 的任务状态枚举可见（与
// summary_tables.dart 的 `textEnum<TaskStatus>()` 同一做法）。
import 'package:flux/core/core.dart';

/// 一次新闻任务的一个版本。
///
/// 索引与查询场景：
///   - `ux_news_runs_date_tz_version`：同一日期 + 时区下版本号唯一（版本号由用例层按
///     当前最大值 +1 给出，唯一约束是「并发两次生成不会写出两个 v2」的保险）；
///   - `ix_news_runs_local_date`：按日期取版本列表与历史（界面日期切换）；
///   - `ix_news_runs_current`：按 (日期, 时区, is_current) 取当前展示版本。
@TableIndex(
  name: 'ux_news_runs_date_tz_version',
  columns: {#localDate, #timeZone, #version},
  unique: true,
)
@TableIndex(name: 'ix_news_runs_local_date', columns: {#localDate})
@TableIndex(
  name: 'ix_news_runs_current',
  columns: {#localDate, #timeZone, #isCurrent},
)
class NewsRuns extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// 设备本地日期键（YYYY-MM-DD）。任务开始时固化，之后不随时区变化重写（D-07）。
  TextColumn get localDate => text()();

  /// 任务开始时的设备时区（IANA 名称）。
  TextColumn get timeZone => text()();

  /// 版本号（同一日期 + 时区下从 1 开始单调递增）。
  IntColumn get version => integer()();

  /// 任务状态九态（与 core 的 TaskStatus 名称一致）。
  TextColumn get taskStatus => textEnum<TaskStatus>()();

  /// 输入快照 JSON（时区、日期区间、选材、必访站、关键词、prompt 版本引用与文本）。
  TextColumn get inputSnapshot => text()();

  /// 快照哈希（同一输入重复生成时的判定依据）。
  TextColumn get snapshotHash => text()();

  /// 必访站逐站结果 JSON（成功/失败/超时/未执行，SET-051「记录逐站获取结果」）。
  TextColumn get siteResults => text()();

  /// 材料清单 JSON（含 accessMethod 与最小摘录）。
  TextColumn get materials => text()();

  /// 条目 JSON（含引用列表、处理结果与 T038 的证据标签）。
  TextColumn get items => text()();

  /// 初稿全文（保留模型的原始输出，便于核对「条目拆分有没有丢内容」）。
  TextColumn get draftText => text().nullable()();

  /// 产出它的提供商别名与模型 ID。
  TextColumn get providerAlias => text().nullable()();
  TextColumn get modelId => text().nullable()();

  /// 累计消耗 token 与 HTTP 尝试次数。
  IntColumn get consumedTokens => integer().withDefault(const Constant(0))();
  IntColumn get attemptCount => integer().withDefault(const Constant(0))();

  /// 失败类别（结构性标识）；成功为 null。**不存错误正文**（架构第 8 节）。
  TextColumn get errorKind => text().nullable()();

  /// 中断/失败时所在的阶段（界面说明「卡在哪一步」）。
  TextColumn get stage => text().nullable()();

  /// 本次版本的来源核验方法记录（T038：派生查询、相似度阈值、聚类规则）。
  ///
  /// 为什么把「怎么核验的」也存下来：架构 4.4 要求标签是**启发式的**结果，用户需要能
  /// 核对判定依据。只存标签（「来源单一」）会让人以为那是一个客观事实，而它其实是
  /// 「按这套阈值没找到第二条独立来源」——两种含义的差别正是这款产品会不会被误信的关键。
  /// 未核验时为 null（T037 的初稿版本都是 null）。
  TextColumn get verificationMethod => text().nullable()();

  /// 是否为当前展示版本。
  BoolColumn get isCurrent => boolean().withDefault(const Constant(false))();

  DateTimeColumn get createdAt => dateTime()();

  /// 只有成功/部分成功的版本才可能是当前展示版本（架构 4.4/4.5）。
  ///
  /// 取值域必须与 core 的 [TaskStatus] 名称保持一致；写成 DDL 而不是只靠应用层，是因为
  /// 「失败草稿覆盖成功版本」会让用户丢失当天唯一一份可用总结，而它在界面上表现为「今天的
  /// 新闻变成了错误页」——没有任何线索指向一次错误的状态标记。
  @override
  List<String> get customConstraints => <String>[
    "CHECK (is_current = 0 OR task_status IN ('succeeded', 'partial'))",
  ];
}
