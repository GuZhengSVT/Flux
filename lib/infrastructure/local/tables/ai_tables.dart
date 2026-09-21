// AI 模型实体（T025；架构 5.1 的 AIProvider / Model 实体）。
//
// 「数据库不含秘密」（架构 5.1、第 8 节）在这张表上体现为**没有任何 Key 列**：
// 凭据只以「提供商别名」为标识住在 Keychain 里（SET-031），本表最多知道别名。
// 这样即使有人拿到 flux.sqlite 明文文件，也拿不到任何 API Key。
//
// 索引与查询场景：
//   - `ux_ai_models_alias`：别名是 Keychain 条目的定位键与故障转移列表的展示名，
//     必须唯一，否则「按别名取凭据」会取到别人的 Key；
//   - `ix_ai_models_sort`：按故障转移顺序（SET-032 的排序）取启用列表。
library;

import 'package:drift/drift.dart';

/// 一个模型记录（一个协议的端点 + 模型 ID + 能力声明）。
///
/// 为什么不把「提供商」和「模型」拆成两张表：本工程的用法里，一个「提供商」
/// （OpenAI 兼容端点）与它下面唯一要用的模型 ID 是一体的——用户配置的是
/// 「用 DeepSeek 的 deepseek-chat 做摘要」，不是「维护一个 DeepSeek 账号下的模型库」。
/// 拆表会引入一个只为了满足范式而存在的中间实体，以及「删提供商时模型怎么办」这类
/// 需要额外规则的空问题。
///
/// 类名用 `AiModelRecords`（表名 `ai_model_records`）而不是 `AiModels`：drift 按
/// 「去掉末尾 s」派生数据类名，`AiModels` 会生成一个与本工程领域类型同名的
/// `AiModel`，两处同名会让每个使用点都必须加前缀，很容易在某处用错。
@TableIndex(name: 'ux_ai_models_alias', columns: {#alias}, unique: true)
@TableIndex(name: 'ix_ai_models_sort', columns: {#sortOrder})
class AiModelRecords extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// 提供商别名（用户可见，唯一）。
  TextColumn get alias => text()();

  /// 预设名（`deepseek`、`openai` 等）；自定义为 null。
  TextColumn get preset => text().nullable()();

  /// 协议稳定标识（`openai.chat_completions` 等；见 AiProtocol.id）。
  ///
  /// 存字符串而不是枚举序号：序号会在枚举里插一项之后整体错位，把一个真实用户的
  /// 配置从 Chat Completions 静默变成别的协议。
  TextColumn get protocolId => text()();

  /// Base URL（不含协议路径）。
  TextColumn get baseUrl => text()();

  /// 服务商侧模型 ID。
  TextColumn get modelId => text()();

  /// 是否启用（SET-032）。
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();

  /// 故障转移顺序（SET-032 的排序，升序优先）。
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  // ---- SET-033：五项独立能力 + 上下文/输出上限 --------------------------
  // 逐项落列而不是打包成一个 JSON：能力会被**查询**（「挑一个支持视觉的模型」），
  // 放进 JSON 就只能全表读出来在内存里过滤，也让「哪一项能力」这件事在 schema 上
  // 不可见（迁移校验、备份审阅都看不到）。

  /// 文本生成能力（默认 true：添加模型的主要意图）。
  BoolColumn get capabilityText =>
      boolean().withDefault(const Constant(true))();

  /// 视觉能力（默认 false：改变数据去向的能力不默认开启）。
  BoolColumn get capabilityVision =>
      boolean().withDefault(const Constant(false))();

  /// 流式能力。
  BoolColumn get capabilityStreaming =>
      boolean().withDefault(const Constant(false))();

  /// 工具调用能力。
  BoolColumn get capabilityTools =>
      boolean().withDefault(const Constant(false))();

  /// 结构化输出能力。
  BoolColumn get capabilityStructured =>
      boolean().withDefault(const Constant(false))();

  /// 上下文窗口（token）；null = 未声明（按 SET-033 的保守 8192 使用）。
  IntColumn get contextWindow => integer().nullable()();

  /// 单次输出上限（token）；null = 未声明（按 SET-033 的保守 2048 使用）。
  IntColumn get outputBudget => integer().nullable()();

  /// 是否为任务默认模型。
  BoolColumn get isDefaultForTasks =>
      boolean().withDefault(const Constant(false))();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

/// AI 任务的持久记录（T030；架构 5.1 的 AITask / Attempt / Result）。
///
/// 为什么把「任务状态、输入快照、累计消耗、结果、错误类别」放在**一张**表里：
/// 这些字段的写入时机是**同一次状态迁移**（见 AiTaskRepository 的说明），分成
/// 三张表（task/attempt/result）会引入「迁移到一半、只写了 task 没写 result」的
/// 中间状态，而本工程没有任何查询需要单独读 attempt 行。将来若 T037/T040 需要
/// 逐次尝试明细，再按需拆出 attempts 表并保留本表为当前态。
///
/// 三条刻意的列设计：
///   1) 输入快照与模型列表存 **JSON 文本**而不是拆列：它们是「当时发出去的东西」的
///      完整记录，字段集合会随任务类型变化（T034/T035 的参数不同），拆成固定列会让
///      每加一种任务类型就要一次迁移；
///   2) 结果文本与错误类别**分列**：错误只存 AppError.kind（结构性类别），
///      绝不存错误正文——响应体可能回显请求内容（架构第 8 节）；
///   3) deadline 一旦写入**只允许不变或提前**（应用层规则）：SQLite 没有「不可推后」
///      这种约束，因此这条规则由 TaskTransition + 仓储层共同保证，见 R030。
@TableIndex(name: 'ix_ai_tasks_created', columns: {#createdAt})
@TableIndex(name: 'ix_ai_tasks_status', columns: {#status})
class AiTasks extends Table {
  /// 任务标识（本机唯一；不是自增 id，因为它是跨表引用与界面展示用的稳定键）。
  TextColumn get taskId => text()();

  /// 任务类型稳定标识（summary/explain/translate/...，见 AiTaskKind.id）。
  TextColumn get kind => text()();

  /// 输入快照 JSON（消息、模型 ID、语言与参数）。
  TextColumn get inputSnapshot => text()();

  /// 输入提示哈希（缓存键的组成项之一，单独落列便于排查与统计）。
  TextColumn get promptHash => text()();

  /// 参与故障转移的模型别名列表（JSON 数组，含顺序）。
  TextColumn get modelAliases => text()();

  /// 路由用的模型 ID 列表（JSON 数组，含顺序；缓存键的组成项）。
  TextColumn get routeModelIds => text()();

  /// 状态九态（与 core 的 [TaskStatus] 名称一致）。
  TextColumn get status => text()();

  /// 任务总时限的绝对时刻（UTC）；一旦设定不重置。
  DateTimeColumn get deadline => dateTime().nullable()();

  /// 累计消耗 token。
  IntColumn get consumedTokens => integer().withDefault(const Constant(0))();

  /// 已发生的 HTTP 尝试次数。
  IntColumn get attemptCount => integer().withDefault(const Constant(0))();

  /// 成功（或部分成功）的产出文本；无产出时为 null。
  TextColumn get resultText => text().nullable()();

  /// 服务商给出的结束原因。
  TextColumn get finishReason => text().nullable()();

  /// 失败错误的类别（AppError.kind）；不存错误正文。
  TextColumn get errorKind => text().nullable()();

  /// 产出结果的提供商别名。
  TextColumn get providerAlias => text().nullable()();

  /// 结果缓存键。
  TextColumn get cacheKey => text().nullable()();

  /// 结果是否直接来自缓存（未发出请求）。
  BoolColumn get fromCache => boolean().withDefault(const Constant(false))();

  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  /// 主键即 taskId。
  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{taskId};
}

/// 成功结果缓存（T030；架构 4.5「缓存键包括任务类型、输入哈希/版本、目标语言、
/// 模板版本、模型和参数」）。
///
/// 缓存键是**全部组成项的摘要**（SHA-256），因此「输入/模型/语言任一变化即失效」
/// 在数据上就是「查不到那一行」，不依赖任何调用点记得清缓存。
///
/// 只写入成功产出：failed/cancelled/interrupted 的尝试不会在此留下记录，避免一次
/// 网络抖动被固化（架构 4.5）。
/// 类名用 AiResultCacheRecords（表名 ai_result_cache_records）而不是
/// AiResultCacheEntries：drift 按「去掉末尾 s」派生数据类名，后者会生成一个与
/// features 层领域类型同名（AiResultCacheEntry）的数据类，两处同名会让每个使用点
/// 都必须加前缀——这正是 AiModelRecords 当初取名时同一个理由（T025）。
@TableIndex(name: 'ix_ai_result_cache_created', columns: {#createdAt})
class AiResultCacheRecords extends Table {
  /// 缓存键（SHA-256 摘要，主键）。
  TextColumn get cacheKey => text()();

  /// 成功产出的文本。
  TextColumn get text_ => text().named('result_text')();

  /// 产出它的提供商别名与模型 ID（排查「这份缓存是谁产的」）。
  TextColumn get providerAlias => text()();
  TextColumn get modelId => text()();

  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{cacheKey};
}

/// 搜索服务记录（T031；架构 5.1 的 SearchConfig 实体、SET-038/039/040/041）。
///
/// 「数据库不含秘密」（架构 5.1、第 8 节）在这张表上同样体现为**没有任何 Key 列**：
/// 凭据只以「服务名」为标识住在 Keychain 里（SET-039），本表最多知道名字。
/// 这样即使有人拿到 flux.sqlite 明文文件，也拿不到任何搜索服务的 Key。
///
/// 命名与 AiModelRecords 同一口径（用 Records 后缀而不是 Services）：drift 按
/// 「去掉末尾 s」派生数据类名，SearchServices 会生成一个与领域类型同名的
/// SearchService 数据类，两处同名会让每个使用点都必须加前缀。
///
/// 索引与查询场景：
///   - ux_search_service_label：名字是 Keychain 条目的定位键与界面展示名，
///     必须唯一，否则「按名字取凭据」会取到另一个服务的 Key；
///   - ix_search_service_sort：按工具执行器的服务选择顺序取值。
@TableIndex(name: 'ux_search_service_label', columns: {#label}, unique: true)
@TableIndex(name: 'ix_search_service_sort', columns: {#sortOrder})
class SearchServiceRecords extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// 服务名（用户可见，唯一）。
  TextColumn get label => text()();

  /// 协议稳定标识（tavily/brave/searxng；见 SearchProtocol.id）。
  ///
  /// 存字符串而不是枚举序号：序号会在枚举里插一项之后整体错位，把一个真实用户的
  /// 配置从 Tavily 静默变成别的协议（与 ai_model_records.protocol_id 同一理由）。
  TextColumn get protocolId => text()();

  /// Base URL（不含协议路径；SearXNG 为自建实例地址）。
  TextColumn get baseUrl => text()();

  /// 是否启用（SET-038）。
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();

  /// 排序（SET-038；升序即服务选择顺序）。
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  /// 每次检索的结果数（SET-040；默认 10，范围 1–20）。
  IntColumn get maxResults => integer().withDefault(const Constant(10))();

  /// 单次检索超时秒数（SET-040；默认 20，范围 5–60）。
  IntColumn get timeoutSeconds => integer().withDefault(const Constant(20))();

  /// 是否已显式批准该端点指向内网/明文 HTTP（SET-041）。
  ///
  /// 默认 false：私网端点必须由用户逐条批准（见 SearchService 的说明）。
  BoolColumn get allowPrivateEndpoint =>
      boolean().withDefault(const Constant(false))();

  /// 是否为任务默认搜索服务（本机唯一）。
  BoolColumn get isDefaultForTasks =>
      boolean().withDefault(const Constant(false))();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}
