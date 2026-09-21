// 模型能力声明（T025；架构 4.3「业务以能力路由，不凭模型名猜能力」）。
//
// 设计要点：五项能力是**各自独立**的布尔值，不是一个等级、也不是一个字符串标签。
// 刻意避免的写法：
//   - 用 `isAdvanced` 之类的等级推断能力——「高级模型」不等于「支持工具」；
//   - 从模型名里匹配 `-vl`、`-vision` 猜视觉能力——名字是服务商的营销字段，
//     改一个后缀就可能让路由静默失效（架构 4.3 明确禁止）。
//
// 上下文与输出上限使用**保守默认值**（SET-033：未知上下文 8192、输出 2048）：
// 宁可少发一点上下文，也不要在用户没声明的情况下按「大模型」的额度发请求——
// 后者会真实产生费用与超长报错。
library;

import 'package:flux/core/core.dart';

/// 一个模型的能力声明（对应 SET-030/032/033 的字段）。
final class ModelCapability {
  /// 构造能力声明。
  const ModelCapability({
    this.text = true,
    this.vision = false,
    this.streaming = false,
    this.tools = false,
    this.structured = false,
    this.contextWindow,
    this.maxOutput,
  });

  /// 是否可用于文本生成。
  ///
  /// 默认 true：用户添加一个模型时的意图几乎必然是「用它做文本任务」。这条默认
  /// **不**外推到视觉/工具——那两项默认 false，因为它们改变数据的去向与权限。
  final bool text;

  /// 是否可理解图片。
  final bool vision;

  /// 是否支持流式输出。
  final bool streaming;

  /// 是否支持原生工具调用（function calling）。
  final bool tools;

  /// 是否支持结构化输出（JSON Schema / JSON mode）。
  final bool structured;

  /// 上下文窗口（token）；null 表示用户未声明。
  final int? contextWindow;

  /// 单次输出上限（token）；null 表示用户未声明。
  final int? maxOutput;

  /// SET-033 的保守上下文预算（未知上下文时使用）。
  static const int conservativeContextBudget = 8192;

  /// SET-033 的保守输出预算（未知输出上限时使用）。
  static const int conservativeOutputBudget = 2048;

  /// 实际可用的上下文预算：声明值优先，未声明时退回保守值。
  int get effectiveContextBudget => contextWindow == null || contextWindow! <= 0
      ? conservativeContextBudget
      : contextWindow!;

  /// 实际可用的输出预算：声明值优先，未声明时退回保守值。
  int get effectiveOutputBudget => maxOutput == null || maxOutput! <= 0
      ? conservativeOutputBudget
      : maxOutput!;

  /// 上下文预算是否为保守回退值（UI 与诊断据此提示「这不是真实能力声明」）。
  bool get contextIsConservative =>
      contextWindow == null || contextWindow! <= 0;

  /// 输出预算是否为保守回退值。
  bool get outputIsConservative => maxOutput == null || maxOutput! <= 0;

  /// 是否满足一项能力要求。
  bool satisfies(CapabilityRequirement requirement) => switch (requirement) {
    CapabilityRequirement.text => text,
    CapabilityRequirement.vision => vision,
    CapabilityRequirement.streaming => streaming,
    CapabilityRequirement.tools => tools,
    CapabilityRequirement.structured => structured,
  };

  /// 复制并覆盖部分字段。
  ModelCapability copyWith({
    bool? text,
    bool? vision,
    bool? streaming,
    bool? tools,
    bool? structured,
    int? contextWindow,
    int? maxOutput,
    bool clearContextWindow = false,
    bool clearMaxOutput = false,
  }) => ModelCapability(
    text: text ?? this.text,
    vision: vision ?? this.vision,
    streaming: streaming ?? this.streaming,
    tools: tools ?? this.tools,
    structured: structured ?? this.structured,
    contextWindow: clearContextWindow
        ? null
        : (contextWindow ?? this.contextWindow),
    maxOutput: clearMaxOutput ? null : (maxOutput ?? this.maxOutput),
  );

  @override
  bool operator ==(Object other) =>
      other is ModelCapability &&
      other.text == text &&
      other.vision == vision &&
      other.streaming == streaming &&
      other.tools == tools &&
      other.structured == structured &&
      other.contextWindow == contextWindow &&
      other.maxOutput == maxOutput;

  @override
  int get hashCode => Object.hash(
    text,
    vision,
    streaming,
    tools,
    structured,
    contextWindow,
    maxOutput,
  );

  @override
  String toString() =>
      'ModelCapability(text=$text, vision=$vision, '
      'streaming=$streaming, tools=$tools, '
      'structured=$structured, context=$contextWindow, '
      'output=$maxOutput)';
}

/// 一次任务对能力的要求（路由与故障转移候选筛选用它，T029/T033）。
enum CapabilityRequirement {
  /// 纯文本生成。
  text,

  /// 需要理解图片（架构 4.3 的视觉链路）。
  vision,

  /// 需要流式输出。
  streaming,

  /// 需要原生工具调用。
  tools,

  /// 需要结构化输出。
  structured,
}

/// 校验一个能力声明是否**自洽**。
///
/// 目前只有一条规则：输出上限不得大于上下文窗口。它值得单独校验，因为
/// 「输出 8192 但上下文 4096」这种配置在服务商侧会直接报错，而报错信息通常
/// 与「哪个字段填错了」无关，用户很难自己定位。
Result<void> validateCapability(String field, ModelCapability capability) {
  final int? context = capability.contextWindow;
  final int? output = capability.maxOutput;
  if (context != null && context <= 0) {
    return Err<void>(
      ValidationError(field: field, reason: '上下文窗口必须为正数', value: '$context'),
    );
  }
  if (output != null && output <= 0) {
    return Err<void>(
      ValidationError(field: field, reason: '输出上限必须为正数', value: '$output'),
    );
  }
  if (context != null && output != null && output > context) {
    return Err<void>(
      ValidationError(
        field: field,
        reason: '输出上限不能大于上下文窗口',
        value: '$output > $context',
      ),
    );
  }
  return okUnit();
}
