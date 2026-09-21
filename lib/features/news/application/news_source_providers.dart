// 新闻来源配置的 Provider（T036）。
//
// 与 T031/T034 同一做法：端口与装配分开，端口默认抛错（漏接线立刻暴露），组合根负责把
// infrastructure 的实现接上来。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flux/core/core.dart';
import 'package:flux/features/ai/application/ai_task_providers.dart';
import 'package:flux/features/settings/application/settings_controller.dart';

import 'news_source_config.dart';

/// 新闻来源配置的存储端口（实现住在 infrastructure/local）。
final Provider<NewsSourceConfigStore> newsSourceConfigProvider =
    Provider<NewsSourceConfigStore>(
      (Ref ref) => throw StateError(
        'newsSourceConfigProvider 未被组合根覆盖：见 lib/app/app_providers.dart',
      ),
    );

/// 新闻来源配置用例。
final Provider<NewsSourceConfigService> newsSourceConfigServiceProvider =
    Provider<NewsSourceConfigService>(
      (Ref ref) => NewsSourceConfigService(
        store: ref.watch(newsSourceConfigProvider),
        clock: ref.watch(aiTaskClockProvider),
      ),
    );

/// 当前状态下拉需要的「新闻生成语言」（SET-011 的 generationLanguage）。
///
/// 读不到时用注册表默认值：与 SET-011 的默认（zh-Hans）一致，不在界面里另写一个常量。
final FutureProvider<NewsPromptLanguage> newsPromptLanguageProvider =
    FutureProvider<NewsPromptLanguage>((Ref ref) async {
      final Result<Object?> read = await ref
          .watch(settingsStoreProvider)
          .readSetting(SettingId.set011);
      final Object? raw = read.isOk ? read.valueOrNull : null;
      final Object? generation = raw is Map<Object?, Object?>
          ? raw['generationLanguage']
          : null;
      final NewsPromptLanguage? parsed = NewsPromptLanguage.fromCode(
        generation is String ? generation : null,
      );
      if (parsed != null) {
        return parsed;
      }
      final SettingDefinition? definition = SettingRegistry.findById(
        SettingId.set011,
      );
      final Object? value = definition?.defaultValue;
      final Object? fallback = value is Map<Object?, Object?>
          ? value['generationLanguage']
          : null;
      return NewsPromptLanguage.fromCode(
            fallback is String ? fallback : null,
          ) ??
          NewsPromptLanguage.chinese;
    });

/// SET-050 的总开关（RSS 内容总开关）。
///
/// 读不到时按注册表默认（开）：与 SET-050 的文档口径一致（「总开」），而不是在界面里另定
/// 一个默认值。
final FutureProvider<bool> newsGlobalEnabledProvider = FutureProvider<bool>((
  Ref ref,
) async {
  final Result<Object?> read = await ref
      .watch(settingsStoreProvider)
      .readSetting(SettingId.set050);
  final Object? raw = read.isOk ? read.valueOrNull : null;
  final Object? value = raw is Map<Object?, Object?>
      ? raw['globalEnabled']
      : null;
  if (value is bool) {
    return value;
  }
  final Object? fallback = SettingRegistry.findById(SettingId.set050)
      ?.defaultValue;
  final Object? fallbackValue = fallback is Map<Object?, Object?>
      ? fallback['globalEnabled']
      : null;
  return fallbackValue is bool ? fallbackValue : true;
});
