import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/refresh_scheduler.dart';
import 'core_providers.dart';
import 'feed_provider.dart';
import 'settings_provider.dart';

/// 全局后台刷新调度器。
///
/// 首次被 watch 时启动，应用销毁时自动停止。
final refreshSchedulerProvider = Provider<RefreshScheduler>((ref) {
  final scheduler = RefreshScheduler(
    database: ref.watch(databaseProvider),
    feedController: ref.watch(feedControllerProvider.notifier),
    readIntervalMinutes: () =>
        ref.read(settingsProvider).refreshIntervalMinutes,
    readTextRetentionDays: () =>
        ref.read(settingsProvider).textRetentionDays,
  );
  ref.onDispose(scheduler.stop);
  // 设置页修改刷新间隔后立即重排定时器，无需重启应用。
  ref.listen<int>(
    settingsProvider.select((s) => s.refreshIntervalMinutes),
    (previous, next) => scheduler.updateInterval(next),
  );
  scheduler.start();
  return scheduler;
});