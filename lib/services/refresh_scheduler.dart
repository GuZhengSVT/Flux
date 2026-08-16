import 'dart:async';

import '../data/app_database.dart';
import '../providers/feed_provider.dart';
import '../providers/settings_provider.dart';
import 'notification_service.dart';

/// 应用运行期间的定时刷新调度器。
///
/// 使用 `Timer.periodic` 按 `refreshIntervalMinutes` 定时调用
/// `FeedController.refreshAll()`，并在刷新后统计新增的未读文章数，
/// 触发本地通知。
class RefreshScheduler {
  RefreshScheduler({
    required this.database,
    required this.feedController,
    required this.readIntervalMinutes,
    this.readTextRetentionDays = _defaultTextRetentionDays,
    NotificationService? notificationService,
  }) : _notificationService =
           notificationService ?? NotificationService.instance;

  /// 使用固定的 [SettingsState] 构造调度器（适合在启动时就拿到设置快照）。
  RefreshScheduler.withSettings({
    required AppDatabase database,
    required FeedController feedController,
    required SettingsState settings,
    NotificationService? notificationService,
  }) : this(
         database: database,
         feedController: feedController,
         readIntervalMinutes: () => settings.refreshIntervalMinutes,
         readTextRetentionDays: () => settings.textRetentionDays,
         notificationService: notificationService,
       );

  final AppDatabase database;
  final FeedController feedController;

  /// 读取当前刷新间隔（分钟）的回调。
  final int Function() readIntervalMinutes;

  /// 读取文本保留天数（默认 30 天）。
  final int Function() readTextRetentionDays;

  final NotificationService _notificationService;

  Timer? _timer;
  bool _refreshing = false;
  int? _intervalOverride;

  /// 是否正在运行。
  bool get isRunning => _timer != null;

  /// 当前生效的刷新间隔（分钟）；小于 1 表示已禁用。
  int get currentIntervalMinutes => _intervalOverride ?? readIntervalMinutes();

  /// 启动定时刷新；若当前间隔小于 1 分钟则保持禁用。
  void start() {
    _applyInterval();
  }

  /// 停止定时刷新。
  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// 更新刷新间隔（分钟）；小于 1 时禁用并停止定时器。
  void updateInterval(int minutes) {
    _intervalOverride = minutes;
    _applyInterval();
  }

  void _applyInterval() {
    _timer?.cancel();
    _timer = null;

    final minutes = _intervalOverride ?? readIntervalMinutes();
    if (minutes < 1) {
      return;
    }

    _timer = Timer.periodic(Duration(minutes: minutes), (_) {
      _tick();
    });
  }

  Future<void> _tick() async {
    // 上一轮刷新尚未完成时跳过本轮，避免并发抓取。
    if (_refreshing) {
      return;
    }
    _refreshing = true;
    try {
      final before = database.unreadCount();
      await feedController.refreshAll();
      final after = database.unreadCount();
      final delta = after - before;
      if (delta > 0) {
        await _notificationService.showNewArticlesNotification(delta);
      }
      // 顺带按文本保留天数清理过期文章。
      final retentionDays = readTextRetentionDays();
      if (retentionDays > 0) {
        database.deleteArticlesOlderThan(Duration(days: retentionDays));
      }
    } catch (_) {
      // 单轮刷新失败不影响后续调度。
    } finally {
      _refreshing = false;
    }
  }
}

int _defaultTextRetentionDays() => 30;
