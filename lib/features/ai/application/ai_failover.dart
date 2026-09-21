// 无响应判定与五次规则（T029；D-09、架构 4.5、手册 6.3）。
//
// 这一层只回答一个问题：**这次失败算不算「无可用响应」**。
// 为什么必须单独成层、而且判断依据是**类型**而不是文案：
//   1) 算错的方向有两个，两个都真实有害。把「认证失败」算成无响应，任务就会拿着同一个
//      坏 Key 连打五次（并可能在别的服务商上再打五次）；把「超时」漏算成不可重试，
//      用户会在一次网络抖动后直接看到失败，而架构明确要求连续五次才换模型；
//   2) 内容拒绝**不得**通过换模型绕过（架构 4.5）。它必须在这一层被识别出来并直接终止，
//      否则「换个服务商再问一遍」就成了一条绕过内容策略的路径；
//   3) 解析/格式错误不与无响应混同（架构 4.5「格式错误最多一次受预算限制的修复，
//      仍失败显示失败，不混同无响应」）。
library;

import 'package:flux/core/core.dart';

/// 一次失败的类别：决定「是否计入五次」「是否换模型」「是否立即终止」。
enum AiFailureClass {
  /// 无可用响应（超时、断流、连接失败、临时 5xx、429 重试后仍限流）。
  ///
  /// 计入连续五次计数；连续五次后按序切下一个启用模型。
  noResponse,

  /// 明确请求被拒、继续做也无意义（认证失败、余额不足、模型不存在、配置非法）。
  ///
  /// **不**计入五次、**不**换模型：换一个服务商并不会修好一个坏 Key，反而会把同一份
  /// 内容发给另一家（架构 4.5「不重复五次：Key 错、余额不足、模型不存在，直接标记
  /// 配置错误」）。
  configuration,

  /// 内容拒绝（服务商按内容策略拒绝）。
  ///
  /// **不**计入五次、**不**换模型（架构 4.5：不能用跨服务商重试规避）。
  contentRefused,

  /// 响应格式不可用（协议解析失败、结构不符）。
  ///
  /// 不与无响应混同：重试同一个模型大概率还是同样的坏格式，而按无响应计数会让
  /// 「格式坏了」伪装成「网络不好」，把五次额度耗在同一个结构缺陷上。
  format,

  /// 用户/上层取消。
  cancelled,

  /// 预算或时限边界（总时限、尝试次数、Token）。
  budget,

  /// 未类型化异常（适配器 bug）。
  internal,
}

/// 判定一个错误的类别。
///
/// 只按**类型**与结构化字段判定，不做消息文案匹配：适配器已经把协议错误体翻译成类型化
/// 错误（T026/T027），这里再按文案猜一次就会把两套语义混起来。
AiFailureClass classifyAiFailure(Object error) {
  return switch (error) {
    CancelledError() => AiFailureClass.cancelled,
    BudgetExhaustedError() => AiFailureClass.budget,
    DeadlineExceededError() => AiFailureClass.noResponse,
    RateLimitError() => AiFailureClass.noResponse,
    // NetworkError 覆盖连接失败、5xx、429 之外的 4xx 与断流。断流（既没有结束标记也
    // 没有结束原因）是典型的「无可用响应」，必须计入五次。
    NetworkError() => AiFailureClass.noResponse,
    ContentFilteredError() => AiFailureClass.contentRefused,
    AuthError() => AiFailureClass.configuration,
    ModelConfigurationError() => AiFailureClass.configuration,
    ValidationError() => AiFailureClass.configuration,
    ParseError() => AiFailureClass.format,
    StorageError() => AiFailureClass.internal,
    // 其余 AppError 子类尚无明确归属（例如将来的 ProviderError）：按「不可重试」处理，
    // 宁可让用户看到一次明确失败，也不要对着未知错误连打五次。
    _ when error is AppError => AiFailureClass.configuration,
    _ => AiFailureClass.internal,
  };
}

/// 一个模型在一次任务内的连续无响应计数（D-09 的「五次规则」）。
///
/// 为什么把计数做成独立对象：它是本轮验收的核心规则（手册 6.3「五次规则」），必须能被
/// 逐条枚举验证——第五次才切、成功清零、到总时限早于第五次则停止。把它埋在队列的
/// 循环变量里，这些规则就只能靠端到端场景间接验证。
final class AiFailoverTracker {
  /// 以「几次算耗尽」构造（默认五次，见 D-09）。
  AiFailoverTracker({this.threshold = 5}) {
    if (threshold < 1) {
      throw ArgumentError.value(threshold, 'threshold', '必须至少为 1');
    }
  }

  /// 连续无响应多少次后切下一个模型。
  final int threshold;

  int _consecutive = 0;

  /// 当前连续无响应次数。
  int get consecutive => _consecutive;

  /// 记录一次无响应；返回是否应该切到下一个模型。
  bool recordNoResponse() {
    _consecutive++;
    return _consecutive >= threshold;
  }

  /// 记录一次成功；连续计数清零。
  ///
  /// D-09「成功则计数清零」指的是**连续**计数：一次有效成功之后，之前攒下的失败不再
  /// 累积——否则一个偶发抖动过的模型会带着旧账进入后面的请求，在第四次正常失败时就
  /// 被切掉。
  void recordSuccess() {
    _consecutive = 0;
  }

  /// 切换模型后重置计数：新模型从零开始算自己的连续无响应。
  void reset() {
    _consecutive = 0;
  }

  @override
  String toString() => 'AiFailoverTracker($_consecutive/$threshold)';
}

/// 保守 Token 估算（SET-063 的「估算上限」）。
///
/// 估算规则与理由：
///   - CJK 字符按 **1 字符 = 1 token**：中文在主流分词器下大致 0.6–1.2 token/字，
///     取 1 是保守方向（宁可高估，不要低估后才发现超预算）；
///   - 非 CJK 按 **4 字符 = 1 token**（英文/代码的常用近似），向上取整。
///
/// 结果一律标记为估算（[AiUsage.totalIsEstimated] 的同一口径）：只知次数不虚构金额，
/// 未知时保守估算并明确标估算（架构 4.5）。
int estimateAiTokens(String text) {
  int cjk = 0;
  int other = 0;
  for (final int rune in text.runes) {
    if (_isCjk(rune)) {
      cjk++;
    } else {
      other++;
    }
  }
  return cjk + ((other + 3) ~/ 4);
}

/// 估算一次请求的输入 token（消息正文 + 每条消息的固定结构开销）。
int estimateRequestTokens(Iterable<String> contents) {
  int total = 0;
  for (final String content in contents) {
    // 每条消息的角色/分隔等结构开销按 4 token 估（主流协议的常见量级），
    // 与正文估算一起取保守方向。
    total += estimateAiTokens(content) + 4;
  }
  return total;
}

bool _isCjk(int rune) =>
    (rune >= 0x3040 && rune <= 0x30FF) || // 日文假名
    (rune >= 0x3400 && rune <= 0x4DBF) || // CJK 扩展 A
    (rune >= 0x4E00 && rune <= 0x9FFF) || // CJK 基本区
    (rune >= 0xAC00 && rune <= 0xD7AF) || // 谚文
    (rune >= 0xF900 && rune <= 0xFAFF) || // CJK 兼容表意
    (rune >= 0x20000 && rune <= 0x2FA1F) || // CJK 扩展 B–F 与兼容补充
    (rune >= 0x3000 && rune <= 0x303F); // CJK 标点
