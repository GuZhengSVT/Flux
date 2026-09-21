// 「去设置」的导航请求（T020）。
//
// 为什么用「请求 + 壳层监听」而不是让详情页直接切去向：切换去向的状态住在 lib/app，
// 而 features 不得 import lib/app（架构 2.2 的回归守卫会拦）。
//
// 为什么不是一条注入的回调端口：回调要能在装配函数里接到真正的去向切换上，那需要在
// 装配时拿到 ProviderContainer——一个纯函数拿不到。把方向反过来（features 置一个请求，
// app 的壳层 watch 它并落实导航）既不需要容器，也让依赖方向保持单向：app → features。
//
// 完成语义：壳层消费后**清空**请求（见 app_shell）。留着它会让用户之后每次手动点别的
// 去向都被拉回设置——一个只该发生一次的意图变成了持续状态。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 请求导航到设置页。
final class SettingsNavigationRequest extends Notifier<bool> {
  @override
  bool build() => false;

  /// 请求一次导航。
  void request() => state = true;

  /// 壳层消费后清空。
  void consume() {
    if (state) {
      state = false;
    }
  }
}

/// 导航请求 Provider。
final NotifierProvider<SettingsNavigationRequest, bool>
settingsNavigationRequestProvider =
    NotifierProvider<SettingsNavigationRequest, bool>(
      SettingsNavigationRequest.new,
    );
