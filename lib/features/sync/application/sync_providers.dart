// 同步的 Provider 装配（T044）。
//
// 与 T036/T040 同一做法：端口定义在 features，默认实现**抛错**（漏接线立刻暴露），
// 组合根负责把 infrastructure 的实现接上来。默认抛错而不是给一个空实现，是因为同步
// 一旦拿到一个「什么都不做的假管理器」，用户会在界面上看到一个永远成功的按钮。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'sync_manager.dart';
import 'sync_settings.dart';

/// 同步管理器（长期存活；组合根提供实现）。
final Provider<SyncManager> syncManagerProvider = Provider<SyncManager>(
  (Ref ref) => throw StateError(
    'syncManagerProvider 未被组合根覆盖：见 lib/app/app_providers.dart',
  ),
);

/// SET-071 的密码端口（实现住 infrastructure/platform）。
final Provider<SyncSecretStore> syncSecretStoreProvider =
    Provider<SyncSecretStore>(
      (Ref ref) => throw StateError(
        'syncSecretStoreProvider 未被组合根覆盖：见 lib/app/app_providers.dart',
      ),
    );

/// 只读连接探测端口（实现住 infrastructure/network）。
///
/// 单独一个端口而不是复用管理器：探测是**配置期**的动作（用户在填地址时点一下），而管理器
/// 是**运行期**的编排。合成一个会让「测试连接」在实现上可能顺手走到同步路径上。
final Provider<SyncConnectionProber> syncConnectionProberProvider =
    Provider<SyncConnectionProber>(
      (Ref ref) => throw StateError(
        'syncConnectionProberProvider 未被组合根覆盖：见 lib/app/app_providers.dart',
      ),
    );

/// 同步管理器当前状态的**运行时**发布点（与 T040 的 dailyNewsStatusProvider 同一做法）。
///
/// 为什么单独一份而不是让界面直接读 manager.status：管理器是长生命周期对象，而 Riverpod
/// 需要一次显式的状态变更通知才会重建界面。让界面读 manager.status 会得到「值变了但界面
/// 没刷新」的假象——那正是最难查的一类问题（数据对、显示旧）。
final NotifierProvider<SyncStatusController, SyncStatusSnapshot>
syncStatusProvider = NotifierProvider<SyncStatusController, SyncStatusSnapshot>(
  SyncStatusController.new,
);

/// 同步状态控制器。
final class SyncStatusController extends Notifier<SyncStatusSnapshot> {
  @override
  SyncStatusSnapshot build() => const SyncStatusSnapshot();

  /// 由管理器回调写入（管理器是唯一写入方，因此状态永远与实际一致）。
  void publish(SyncStatusSnapshot status) => state = status;
}
