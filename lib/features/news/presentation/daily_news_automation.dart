// 定时总结的驱动宿主（T040；架构 4.4「后台尽力执行，不要求系统精确定时」）。
//
// 与 T016 的 RefreshAutomationHost 同一做法与同一理由：计时器的归属放进 widget 树，
// Provider 的生命周期由 Riverpod 管理，在里面建计时器很难保证「容器销毁时也停」——
// 一个停不掉的计时器会在测试里跨用例触发任务，而那种失败看起来像被测代码的问题。
//
// 触发规则：
//   - **启动检查只做一次**（`_launched`）：SET-056 的语义是「应用启动时检查一遍」，不是
//     「每次 widget 重建都检查」。启动检查里包含「标中断」与「错过则补跑当天一次」。
//   - **每分钟检查一次当前策略**，而不是按第一次读到的时间定一个一次性计时器：用户改了
//     执行时间或换了时区之后，下一次检查就按新值算，不需要重启应用。
//   - 数据库不可用时**不启动**：读不到设置与版本记录，跑起来只会每次失败并往日志里加噪音。
//
// 写在前面的一句实话：**macOS 没有后台执行的保证**。应用退出后这里的一切都不再运行，
// 因此「20:00 一定会跑」是不成立的；能保证的是「应用在运行时到点会跑」与「应用下次启动时
// 会补跑当天错过的那一次」。被系统终止的任务在数据里留下 `interrupted`，不会伪称完成。
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flux/features/feeds/application/refresh_providers.dart'
    show degradedStartupProvider;

import '../application/daily_news_providers.dart';
import '../application/daily_news_scheduler.dart';

/// 定时总结宿主：不渲染任何东西，只负责在合适的时候触发一次运行。
class DailyNewsAutomationHost extends ConsumerStatefulWidget {
  /// 构造宿主。
  const DailyNewsAutomationHost({required this.child, super.key});

  /// 子树。
  final Widget child;

  @override
  ConsumerState<DailyNewsAutomationHost> createState() =>
      _DailyNewsAutomationHostState();
}

class _DailyNewsAutomationHostState
    extends ConsumerState<DailyNewsAutomationHost> {
  /// 是否已执行过启动检查。
  bool _launched = false;

  @override
  void initState() {
    super.initState();
    // 首帧之后再检查：启动检查要读设置、模型列表、凭据与版本记录（各一次往返），
    // 在首帧之前做会让启动出现一段没有解释的空白。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_launch());
    });
  }

  @override
  Widget build(BuildContext context) {
    // 这一层不渲染任何东西，因此 build 只返回子树。降级判定放在 [_launch] 里：
    // 用 watch 会在降级状态变化时重建整棵子树，而这里没有任何东西需要重建。
    return widget.child;
  }

  Future<void> _launch() async {
    if (_launched || !mounted) {
      return;
    }
    _launched = true;
    // 降级启动（数据库不可用）时不启动定时：没有设置可读、没有版本记录可写，
    // 每分钟的检查只会把失败写进日志。
    if (ref.read(degradedStartupProvider)) {
      return;
    }
    final DailyNewsScheduler scheduler = ref.read(dailyNewsSchedulerProvider);
    scheduler.start();
    await scheduler.onLaunch();
  }
}
