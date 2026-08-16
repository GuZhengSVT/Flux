import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// 本地通知封装。
///
/// 封装 `FlutterLocalNotificationsPlugin`，负责各平台初始化参数与
/// 「有新文章」通知的展示。使用单例访问，避免重复初始化插件。
class NotificationService {
  NotificationService._(this._plugin);

  /// 全局单例。
  static final NotificationService instance =
      NotificationService._(FlutterLocalNotificationsPlugin());

  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialized = false;

  /// 初始化各平台通知。
  ///
  /// 必须在 `main()` 中 `runApp` 之前调用（桌面平台尤其需要），
  /// 返回是否初始化成功。
  Future<bool> initialize() async {
    if (_initialized) {
      return true;
    }

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');

    final darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestSoundPermission: true,
      requestBadgePermission: true,
    );

    final linuxSettings = LinuxInitializationSettings(
      defaultActionName: 'Open Flux',
    );

    // Windows 需要这些值才能正确注册 Toast 通知回调，
    // 取值与 `windows/runner` 中的 AppUserModelID / GUID 约定一致即可。
    const windowsSettings = WindowsInitializationSettings(
      appName: 'Flux',
      appUserModelId: 'dev.flux.flux',
      guid: 'd9f0d862-2d2e-4e2e-9e88-6a4e5f8a8b7c',
    );

    final initializationSettings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
      macOS: darwinSettings,
      linux: linuxSettings,
      windows: windowsSettings,
    );

    try {
      final result = await _plugin.initialize(settings: initializationSettings);
      _initialized = result ?? true;
    } catch (e) {
      // 通知不可用不应导致应用崩溃（例如平台不支持通知服务时）。
      debugPrint('Flux: notification initialize failed: $e');
      _initialized = false;
    }
    return _initialized;
  }

  /// 展示「Flux 有新文章」通知。
  ///
  /// [count] 为新增文章数量。未初始化或 count <= 0 时静默跳过。
  Future<void> showNewArticlesNotification(int count) async {
    if (count <= 0) {
      return;
    }
    if (!_initialized && !await initialize()) {
      return;
    }

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'flux_new_articles',
        '新文章',
        channelDescription: '当订阅源有新文章时提醒',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
      ),
      iOS: DarwinNotificationDetails(),
      macOS: DarwinNotificationDetails(),
      linux: LinuxNotificationDetails(),
      windows: WindowsNotificationDetails(),
    );

    try {
      await _plugin.show(
        id: 1,
        title: 'Flux 有新文章',
        body: '新增 $count 篇文章',
        notificationDetails: details,
      );
    } catch (e) {
      debugPrint('Flux: show notification failed: $e');
    }
  }
}

/// 顶层便捷函数：展示「Flux 有新文章」通知。
Future<void> showNewArticlesNotification(int count) =>
    NotificationService.instance.showNewArticlesNotification(count);
