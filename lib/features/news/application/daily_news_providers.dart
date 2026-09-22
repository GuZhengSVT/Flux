// 每日定时总结的 Provider（T040）。
//
// 与 T036/T037 同一做法：端口与装配分开，端口默认抛错（漏接线立刻暴露），组合根负责把
// infrastructure 的实现接上来。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'daily_news_scheduler.dart';

/// 每日定时总结调度器（长期存活；组合根提供实现）。
///
/// 默认实现**抛错**：漏接线时「定时从来没跑过」必须是一个立刻可见的装配错误，而不是一个
/// 安静的「这台设备恰好没有定时」。
final Provider<DailyNewsScheduler> dailyNewsSchedulerProvider =
    Provider<DailyNewsScheduler>(
      (Ref ref) => throw StateError(
        'dailyNewsSchedulerProvider 未被组合根覆盖：见 lib/app/app_providers.dart',
      ),
    );

/// 费用与数据发送告知的确认记录（实现住 infrastructure/local）。
///
/// 默认实现**抛错**而不是「当作已确认」：默认放行会让一次后台付费运行在用户从没被告知的
/// 情况下发生，而这个方向的错误没有任何补救余地（钱已经花了）。漏接线必须是噪音，不是账单。
final Provider<NewsCostNoticeStore> newsCostNoticeStoreProvider =
    Provider<NewsCostNoticeStore>(
      (Ref ref) => throw StateError(
        'newsCostNoticeStoreProvider 未被组合根覆盖：见 lib/app/app_providers.dart',
      ),
    );

/// 定时总结的**运行状态**（设备侧，不持久化）。
///
/// 与「版本记录」分开：它是「这台设备现在打算什么时候跑、为什么还没跑」这个运行时问题的
/// 答案，而版本记录回答「跑出来过什么」。合成一个来源会让界面在还没跑过任何一次时
/// 显示不出「下次 20:00」——而那正是默认开启后用户最需要看到的一句话。
final NotifierProvider<DailyNewsStatusController, DailyNewsStatus?>
dailyNewsStatusProvider =
    NotifierProvider<DailyNewsStatusController, DailyNewsStatus?>(
      DailyNewsStatusController.new,
    );

/// 定时状态控制器。
final class DailyNewsStatusController extends Notifier<DailyNewsStatus?> {
  @override
  DailyNewsStatus? build() => null;

  /// 由调度器回调写入（调度器是唯一的写入方，因此状态里的时间永远与实际评估一致）。
  void publish(DailyNewsStatus status) => state = status;
}
