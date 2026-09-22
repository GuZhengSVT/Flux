// 刷新调度在应用里的装配与运行时状态（T016）。
//
// 分层：本文件把「策略（来自设置）」+「端口（来自组合根）」+「调度器」接起来，
// 并把「本轮触发是否在进行、结果如何」暴露成可观察状态。调度规则本身在
// refresh_scheduler.dart，页面只读这里的状态、只调这里的方法。
//
// 三条刻意的选择：
//
//   1) **策略是可观察的**（FutureProvider）。用户在设置页改了 SET-020/021 之后，
//      定时器与守卫必须跟着变；把策略塞进一个只读一次的变量会让「改了间隔不生效」
//      成为一个只有重启才能发现的问题。
//
//   2) **调度器是长期存活对象**（Provider）。触发合并与在途计数都保存在调度器实例里，
//      每次触发重新构造会让合并彻底失效（每次都是「新队列」，同一源会被重复入队）。
//
//   3) **启动触发与定时触发由界面层驱动**（[RefreshAutomationHost]），而不是在
//      Provider 里创建计时器：Provider 的生命周期由 Riverpod 管理，在它里面创建
//      Timer 很难保证「容器销毁时计时器也停」，而一个停不掉的计时器会在测试里
//      制造跨用例的干扰。放进 widget 后，计时器的归属与 widget 树一致。
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flux/core/core.dart';
import 'package:flux/features/settings/application/settings_controller.dart';
import 'package:flux/features/settings/application/settings_store.dart';

import 'feed_manager_state.dart';
import 'feed_ports.dart';
import 'refresh_feed.dart';
import 'refresh_scheduler.dart';

/// 网络状况端口（由组合根注入具体实现）。
final Provider<NetworkConditionPort> networkConditionsProvider =
    Provider<NetworkConditionPort>(
      (Ref ref) => const PermissiveNetworkConditions(),
    );

/// 本次运行是否处于降级启动（数据库不可用）。
///
/// 为什么在这里再声明一个「降级」Provider，而不是直接用 lib/app 的
/// appBootstrapStatusProvider：features 层**不得** import lib/app
/// （test/core/architecture_layering_test.dart 实际拦截，且 lib/app 会渲染 features，
/// 反向依赖会成环）。组合根把这个 Provider 覆盖成真实状态，features 只看到「一个布尔」。
///
/// 默认 false（未降级）：默认值必须让功能**尽可能工作**。若默认 true，任何漏接线都会
/// 静默关掉自动刷新，而那种失败在界面上没有任何痕迹。
final Provider<bool> degradedStartupProvider = Provider<bool>(
  (Ref ref) => false,
);

/// 当前生效的调度策略（SET-020/021/013）。
///
/// 读取失败时回退到注册表默认值：调度是后台行为，一个读不到设置的应用应该按
/// **默认值**继续，而不是完全不刷新。这不影响「设置页写入失败必须可见」那条规则
/// ——那里是用户在明确表达意图，这里是后台行为。
final FutureProvider<RefreshSchedulePolicy> refreshPolicyProvider =
    FutureProvider<RefreshSchedulePolicy>((Ref ref) async {
      final SettingsStore settings = ref.watch(settingsStoreProvider);
      final (RefreshPolicy policy, bool failed) = await readRefreshPolicy(
        settings,
      );
      final bool meteredAllowed = failed
          ? false
          : await readMeteredAllowed(settings);
      return RefreshSchedulePolicy(
        autoRefreshEnabled: policy.autoRefreshEnabled,
        intervalSetting: policy.intervalSetting,
        refreshOnLaunch: policy.refreshOnLaunch,
        allowMeteredNetwork: meteredAllowed,
      );
    });

/// 读取 SET-013（允许计费网络）；默认值为 false。
Future<bool> readMeteredAllowed(SettingsStore settings) async {
  final SettingDefinition? definition = SettingRegistry.findById(
    SettingId.set013,
  );
  final Result<Object?> value = await settings.readSetting(SettingId.set013);
  if (value.isErr) {
    return definition?.defaultValue == true;
  }
  final Object? raw = value.valueOrNull;
  return raw is bool ? raw : definition?.defaultValue == true;
}

/// SET-013 的媒体下载守卫（T021）。
///
/// 与刷新调度的守卫**共用**同一条设置与同一套判断顺序，但入口不同：
///   - 调度守卫在触发一次刷新之前问「能不能联网」；
///   - 这里在真正要为一**张图**发请求之前问同一件事。
///
/// 为什么要一个独立的实现而不是复用调度里的那个：那个守卫是「一次刷新」级别的一次性
/// 判断（含日程与离线语义），而图片是逐张发生的——把它塞进调度会得到一条「每张图都
/// 检查一遍日程」的奇怪路径。两处共用的是**判据**（SET-013 + isMetered），不是流程。
final class SettingsMediaDownloadPolicy implements MediaDownloadPolicy {
  /// 构造策略。
  const SettingsMediaDownloadPolicy({
    required this.settings,
    required this.networkConditions,
  });

  /// 设置读取端口。
  final SettingsStore settings;

  /// 网络状况探测。
  final NetworkConditionPort networkConditions;

  @override
  Future<bool> allowsImageDownload() async {
    final bool metered = await networkConditions.isMetered();
    if (!metered) {
      // 非计费网络不放行是「没有证据表明受限」的正常情形，直接允许。
      return true;
    }
    // 计费网络下才需要看 SET-013：未允许时**不发出请求**。
    return readMeteredAllowed(settings);
  }
}

/// 刷新调度器（长期存活）。
final Provider<RefreshScheduler> refreshSchedulerProvider =
    Provider<RefreshScheduler>((Ref ref) {
      // 策略不在构造时套用：策略来自异步的设置读取，而这里必须能同步返回调度器。
      // 套用策略的时机是「界面观察到策略后立刻套用」（见 RefreshAutomationHost），
      // 因此不会出现「第一次触发用的是构造默认值」。
      final RefreshScheduler scheduler = RefreshScheduler(
        listFeeds: () => ref.read(feedCatalogProvider).listFeeds(),
        refreshFeed: RefreshFeedUseCase(
          fetcher: ref.read(feedFetcherProvider),
          store: ref.read(feedArticleStoreProvider),
          diagnostics: ref.read(diagnosticSinkProvider),
        ),
        recordDeferral:
            ({
              required int feedId,
              required FeedRefreshOutcome outcome,
              String? errorKind,
            }) => ref
                .read(feedArticleStoreProvider)
                .recordDeferredOutcome(
                  feedId: feedId,
                  outcome: outcome,
                  errorKind: errorKind,
                ),
        // T045：已删除的源不复活。墓碑读取走**窄端口**（只读、只回答「哪些订阅被删过」）；
        // 未接线时默认实现返回空集合，刷新照常进行而不是静默停摆。
        listFeedTombstoneSyncIds: () =>
            ref.read(feedTombstoneReaderProvider).readFeedTombstoneSyncIds(),
        networkConditions: ref.read(networkConditionsProvider),
        diagnostics: ref.read(diagnosticSinkProvider),
      );
      ref.onDispose(scheduler.dispose);
      return scheduler;
    });

/// 本轮刷新的运行状态（设备侧，不持久化）。
class RefreshStatus {
  /// 构造状态。
  const RefreshStatus({required this.running, this.lastReport, this.lastError});

  /// 初始状态。
  const RefreshStatus.idle() : this(running: false);

  /// 是否有触发在进行。
  final bool running;

  /// 最近一次完成的汇总。
  final RefreshRunReport? lastReport;

  /// 最近一次失败原因。
  final AppError? lastError;
}

/// 刷新控制器。
///
/// 只暴露「现在刷新」与「到期刷新」两个动作：启动刷新的开关判断在界面层
/// （它要读 SET-021），而这里不重复判断一遍开关——同一个规则在两处实现，
/// 迟早在其中一处漂移。
final class RefreshController extends AsyncNotifier<RefreshStatus> {
  @override
  Future<RefreshStatus> build() async {
    // 依赖策略与调度器：任一被替换（组合根注入、测试替换）都重新构建。
    ref.watch(refreshPolicyProvider);
    ref.watch(refreshSchedulerProvider);
    return const RefreshStatus.idle();
  }

  /// 手动全量刷新（用户点「刷新」）。
  Future<RefreshStatus> refreshNow() =>
      _run((RefreshScheduler scheduler) => scheduler.refreshAll());

  /// 启动触发（SET-021）。
  Future<RefreshStatus> refreshOnLaunch() =>
      _run((RefreshScheduler scheduler) => scheduler.refreshOnLaunch());

  /// 定时触发（SET-020）。
  Future<RefreshStatus> refreshDue() =>
      _run((RefreshScheduler scheduler) => scheduler.refreshDueScheduled());

  /// 执行一次触发并更新状态。
  Future<RefreshStatus> _run(
    Future<RefreshRunReport> Function(RefreshScheduler scheduler) action,
  ) async {
    final RefreshScheduler scheduler = ref.read(refreshSchedulerProvider);
    final RefreshStatus previous = state.value ?? const RefreshStatus.idle();
    // 正在进行时**不**再发起：调度器自己也会合并重复触发，但界面状态需要立刻
    // 反映「正在刷新」，而不是等一个可能很长的触发结束。
    if (previous.running) {
      return previous;
    }
    state = AsyncData<RefreshStatus>(
      RefreshStatus(running: true, lastReport: previous.lastReport),
    );
    try {
      final RefreshRunReport report = await action(scheduler);
      final RefreshStatus next = RefreshStatus(
        running: false,
        lastReport: report,
      );
      state = AsyncData<RefreshStatus>(next);
      return next;
    } on AppError catch (error) {
      // 调度器内部把每个源的失败都收进 report，因此这里只兜「调度本身」的失败。
      final RefreshStatus next = RefreshStatus(
        running: false,
        lastReport: previous.lastReport,
        lastError: error,
      );
      state = AsyncData<RefreshStatus>(next);
      return next;
    }
  }
}

/// 刷新控制器 Provider。
final AsyncNotifierProvider<RefreshController, RefreshStatus>
refreshControllerProvider =
    AsyncNotifierProvider<RefreshController, RefreshStatus>(
      RefreshController.new,
    );
