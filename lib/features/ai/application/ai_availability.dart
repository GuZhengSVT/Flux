// AI 可用性探针（T020 建立的缝；真正的提供商/模型配置属 T025/T030）。
//
// 为什么现在就要有这一层：T020 的「选词解释」入口需要回答一个问题——**能不能解释**。
// 没有配置 AI 时应当提示并引导去设置，配置了才给出「本轮只做入口」的说明。这个问题在
// T034 接上真实调用之后仍然存在，因此它的答案不该由详情页自己写一遍（那会与 T025 的
// 提供商配置判断漂移成两套）。
//
// 端口只回答「至少有一条可用于解释的 AI 凭据」。完整的模型能力路由属 T025/T030：那是
// 「用哪个模型」，而这里是「有没有」。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 是否已有可用的 AI 配置（凭据 + 提供商）。
abstract interface class AiAvailability {
  /// 是否已配置到「可以发起一次解释请求」的程度。
  ///
  /// 实现只查本机安全存储里的凭据引用，**不发起任何网络请求**：判断可用性不该先花一次
  /// 调用，也不该在用户只是选中一段文字时产生流量。
  Future<bool> isConfigured();
}

/// AI 可用性端口（由组合根注入）。
///
/// 默认实现返回 false，而不是抛错：报告「还没有配置」是一个**正确**的默认答案（首次
/// 启动时确实没有配置），而抛错会让详情页在未接线的宿主上直接崩掉——一个提示框不值得
/// 让整页失败。
final Provider<AiAvailability> aiAvailabilityProvider =
    Provider<AiAvailability>((Ref ref) => const _UnconfiguredAi());

/// 未配置的实现。
final class _UnconfiguredAi implements AiAvailability {
  const _UnconfiguredAi();

  @override
  Future<bool> isConfigured() async => false;
}
