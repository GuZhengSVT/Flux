// 媒体缓存上限的读取与应用（T021；SET-080「媒体缓存上限 512 MiB，允许 128–4096」）。
//
// 为什么要一个独立的 Provider + 宿主：上限来自**异步**的设置读取，而图片加载器必须
// 在装配时就能同步返回（否则首帧绘制要等一次数据库往返）。因此采用与刷新调度同一套
// 模式——装配时给默认值，读到设置后显式套用（见 RefreshAutomationHost 的说明）。
//
// 读不到设置时回退**注册表默认值**而不是报错：缓存上限是资源约束，一个读不出设置的
// 应用应该按 512 MiB 继续工作，而不是变成「图片全都加载不出来」。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flux/core/core.dart';
import 'package:flux/features/settings/application/settings_controller.dart';
import 'package:flux/features/settings/application/settings_store.dart';

/// 读取 SET-080 的媒体缓存上限（MiB）。
Future<int> readMediaCacheLimitMiB(SettingsStore settings) async {
  final SettingDefinition? definition = SettingRegistry.findById(
    SettingId.set080,
  );
  final int fallback = definition?.defaultValue is int
      ? definition!.defaultValue! as int
      : kDefaultCacheMiB;
  final Result<Object?> value = await settings.readSetting(SettingId.set080);
  if (value.isErr) {
    return fallback;
  }
  final Object? raw = value.valueOrNull;
  if (raw is! int) {
    return fallback;
  }
  // 夹紧也在读的一侧做一次：把「越界值」挡在进入加载器之前，界面若将来要显示当前
  // 生效值，看到的就已经是夹紧后的结果。
  return clampCacheMiB(raw);
}

/// 当前生效的媒体缓存上限（MiB）。
final FutureProvider<int> mediaCacheLimitProvider = FutureProvider<int>(
  (Ref ref) async => readMediaCacheLimitMiB(ref.watch(settingsStoreProvider)),
);
