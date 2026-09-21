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
