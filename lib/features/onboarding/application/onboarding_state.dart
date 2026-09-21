// 首次引导的状态与端口（T011）。
//
// 端口在这里（features 层）而不是 app 层，理由与 settings 的端口一致：架构第
// 2.2 节要求展示/用例层依赖接口，基础设施实现接口，组合根负责注入。引导标记的
// 具体存储（本机 settings 窄表）属于 infrastructure，因此这里只声明端口。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 首次引导完成标记的读写端口。
abstract interface class OnboardingStore {
  /// 是否已完成首次引导。
  ///
  /// 读取失败时返回 false 是**安全的默认**：宁可让用户重看一次说明，也不要在
  /// 读不到状态时假装已完成（后者会让新用户直接落到空主页，没有任何解释）。
  Future<bool> isCompleted();

  /// 标记首次引导完成（幂等）。
  Future<void> markCompleted();
}

/// 端口的 Provider；未覆盖时抛错（漏接线必须立刻暴露，而不是静默不持久化）。
final Provider<OnboardingStore> onboardingStoreProvider =
    Provider<OnboardingStore>(
      (Ref ref) => throw StateError(
        'onboardingStoreProvider 未被组合根覆盖：见 lib/app/app_bootstrap.dart',
      ),
    );

/// 首次引导是否已完成（异步读取本机标记）。
final FutureProvider<bool> onboardingCompletedProvider = FutureProvider<bool>((
  Ref ref,
) async {
  final OnboardingStore store = ref.watch(onboardingStoreProvider);
  return store.isCompleted();
});
