// 启动与定时刷新的驱动（T016；SET-020 定时间隔、SET-021 启动时刷新）。
//
// 为什么要一个 widget 来驱动，而不是在 Provider 里创建 Timer：
//   Provider 的生命周期由 Riverpod 管理，在里面创建计时器很难保证「容器销毁时计时器
//   也停」。一个停不掉的计时器会在测试里跨用例触发刷新（向 MockClient 发本不该有的
//   请求），而那种失败看起来像被测代码的问题。放在 widget 里，计时器的归属与树一致。
//
// 触发规则：
//   - 启动触发（SET-021）：**只在挂载后执行一次**。SET-021 的语义是「应用启动时检查
//     一遍」，不是「每次 widget 重建都检查」；
//   - 定时触发（SET-020）：按**当前策略的间隔**周期性检查到期源。用「每次 tick 重新
//     读策略」而不是「按第一次的间隔定一个周期」：用户改了间隔之后，下一次 tick 就按
//     新间隔算，不需要重启应用。
//
// 两者都**不**在数据库不可用时执行：降级启动下没有源可刷新（读订阅清单会失败），
// 而刷新会写在失败日志里制造噪音。
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flux/features/feeds/application/refresh_providers.dart';
import 'package:flux/features/feeds/application/refresh_scheduler.dart';

/// 刷新自动化宿主：不渲染任何东西，只负责在合适的时候触发刷新。
///
/// 放在应用壳里（[AppShell] 之外包一层），因此它对「当前在哪个去向」无感——刷新是
/// 后台行为，不应依赖用户是否正看着阅读页。
class RefreshAutomationHost extends ConsumerStatefulWidget {
  /// 构造宿主。
  const RefreshAutomationHost({required this.child, super.key});

  /// 子树。
  final Widget child;

  @override
  ConsumerState<RefreshAutomationHost> createState() =>
      _RefreshAutomationHostState();
}

class _RefreshAutomationHostState extends ConsumerState<RefreshAutomationHost> {
  /// 定时触发的计时器；策略为「手动」时为空。
  Timer? _timer;

  /// 已经调度过的间隔（避免每次重建都重置计时器）。
  Duration? _scheduledInterval;

  /// 是否已执行过启动触发。
  bool _launched = false;

  @override
  void initState() {
    super.initState();
    // 挂载后触发一次启动刷新。用 addPostFrameCallback 而不是直接在 initState 里
    // 执行：启动触发会读设置与订阅清单（各一次数据库往返），在首帧之前做会让启动
    // 出现一段没有解释的空白。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_maybeLaunchRefresh());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 降级启动（数据库不可用）时不做任何自动刷新：没有源可读，刷新只会失败。
    if (ref.watch(degradedStartupProvider)) {
      return widget.child;
    }

    final AsyncValue<RefreshSchedulePolicy> policy = ref.watch(
      refreshPolicyProvider,
    );
    // 在 build 里同步调度计时器：whenData 的回调在 build 期间执行，且只对数据态
    // 调用。用 _scheduledInterval 记住已调度的间隔，避免同一策略下每次重建都重建
    // 计时器（那会让 tick 永远等不到）。
    policy.whenData(_scheduleTimer);
    return widget.child;
  }

  /// 按策略调度定时器。
  void _scheduleTimer(RefreshSchedulePolicy policy) {
    final Duration? interval = policy.autoRefreshEnabled
        ? policy.globalInterval
        : null;
    if (interval == _scheduledInterval) {
      return;
    }
    _scheduledInterval = interval;
    _timer?.cancel();
    _timer = null;
    if (interval == null) {
      // SET-020 关闭或取值为「手动」：没有定时刷新，如实表现为不设计时器。
      return;
    }
    _timer = Timer.periodic(interval, (Timer timer) {
      unawaited(_runScheduled());
    });
  }

  /// 启动触发（SET-021）。
  Future<void> _maybeLaunchRefresh() async {
    if (_launched) {
      return;
    }
    _launched = true;
    final RefreshSchedulePolicy policy = await ref.read(
      refreshPolicyProvider.future,
    );
    if (!mounted || !policy.refreshOnLaunch) {
      // SET-021 关闭：不触发。这里**不**把「关闭」显示成「已经刷新过」——
      // 界面上的「上次检查」保持不动。
      return;
    }
    ref.read(refreshSchedulerProvider).applyPolicy(policy);
    await ref.read(refreshControllerProvider.notifier).refreshOnLaunch();
  }

  /// 定时触发（SET-020）。
  Future<void> _runScheduled() async {
    if (!mounted) {
      return;
    }
    final RefreshSchedulePolicy policy = await ref.read(
      refreshPolicyProvider.future,
    );
    if (!mounted || !policy.autoRefreshEnabled) {
      return;
    }
    ref.read(refreshSchedulerProvider).applyPolicy(policy);
    await ref.read(refreshControllerProvider.notifier).refreshDue();
  }
}
