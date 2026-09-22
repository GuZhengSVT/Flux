// 减少动态效果（T049；SET-014「跟随系统，可强制开启」）。
//
// 为什么把取值与解析放在用例层：
//   「开 / 关 / 跟随系统」与「当前系统的 reduce motion」是两个事实，**合成结果**只应该
//   有一份实现。界面（MediaQuery 覆盖）与控件（过渡时长）都引用它，否则会出现
//   「设置里选了强制减少，但某个动画还在播」这种只在特定控件上出现的偏差。
//
// 为什么解析结果可能是 **null** 而不是 bool：
//   「跟随系统」意味着**不覆盖** MediaQuery.disableAnimations，由系统值决定。用一个
//   bool 兜底会把「没有意见」写死成 false（= 忽视系统设置），而在 macOS 上用户开启
//   「减少动态效果」后我们的动画仍会播放。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flux/core/core.dart';

import 'settings_controller.dart';
import 'settings_store.dart';

/// SET-014 的取值。
enum MotionPreference {
  /// 跟随系统（默认）。
  system('system'),

  /// 强制减少。
  on('on'),

  /// 强制不减少。
  off('off');

  const MotionPreference(this.storageName);

  /// 落库用的稳定名（SET-014 取值）。
  final String storageName;

  /// 按存储值解析；未知/读不到时回退 [system]。
  ///
  /// 回退到 system 而不是某个固定档：读不到时最保守的行为是**尊重系统设置**，
  /// 而不是替用户决定「减少」或「不减少」。
  static MotionPreference fromStorage(Object? value) {
    for (final MotionPreference preference in values) {
      if (preference.storageName == value) {
        return preference;
      }
    }
    return MotionPreference.system;
  }

  /// 把「本设置 + 系统值」合成为是否禁用动画；null 表示不覆盖（交给系统）。
  bool? resolve({required bool systemDisablesAnimations}) => switch (this) {
    MotionPreference.system => null,
    MotionPreference.on => true,
    MotionPreference.off => false,
  };
}

/// 当前 SET-014 取值。
///
/// 读不到时按注册表默认值（system）处理：一次读取失败不应该让整个应用开始或停止播放
/// 动画——那是用户会立刻察觉、却完全无法解释的行为变化。
final FutureProvider<MotionPreference> motionPreferenceProvider =
    FutureProvider<MotionPreference>((Ref ref) async {
      final SettingsStore store = ref.watch(settingsStoreProvider);
      final Result<Object?> read = await store.readSetting(SettingId.set014);
      if (read.isErr) {
        return MotionPreference.system;
      }
      return MotionPreference.fromStorage(read.valueOrNull);
    });
