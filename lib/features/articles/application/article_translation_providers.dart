// 分段翻译的端口与 Provider（T035）。
//
// 与 T033 的 vision_ports / T034 的 article_ai_providers 同一做法：端口与读设置的窄接口在
// features 侧声明（默认安全值/抛错），组合根只负责把 infrastructure 的实现接上来。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flux/core/core.dart';

import 'package:flux/features/ai/application/ai_ports.dart';
import 'package:flux/features/ai/application/ai_task_providers.dart';
import 'package:flux/features/settings/application/settings_controller.dart';
import 'package:flux/features/settings/application/settings_store.dart';

import 'article_translation_tasks.dart';

/// 译文的读写端口（实现住在 infrastructure/local）。
///
/// 默认抛错：漏接线必须在使用时立刻暴露，而不是退化成一个静默的空实现，把「译文已保存」
/// 演得像真的一样。
final Provider<ArticleTranslationStore> articleTranslationStoreProvider =
    Provider<ArticleTranslationStore>(
      (Ref ref) => throw StateError(
        'articleTranslationStoreProvider 未被组合根覆盖：见 lib/app/app_providers.dart',
      ),
    );

/// 翻译服务的三个设置值（SET-011 的目标语言、SET-061 的单段预算）。
///
/// 两个值一起读而不是各自一个 provider：它们在同一次翻译里被一起使用，分开读会让
/// 「目标语言读到了但预算读的是上一次的值」这类错配成为可能。
class TranslationSettings {
  /// 构造设置。
  const TranslationSettings({
    required this.targetLanguage,
    required this.segmentBudget,
  });

  /// SET-011 的翻译目标语言（`zh-Hans` / `en`）。
  final String targetLanguage;

  /// SET-061 的单段预算（默认 8000 字符）。
  final int segmentBudget;
}

/// 读 SET-011 / SET-061；读不到时用注册表默认值。
///
/// 目标语言读不到时的兜底是**中英各自默认**：SET-011 的默认值是 zh-Hans，因此这里跟着
/// 走注册表而不是另写一个常量。
final FutureProvider<TranslationSettings> translationSettingsProvider =
    FutureProvider<TranslationSettings>((Ref ref) async {
      final SettingsStore settings = ref.watch(settingsStoreProvider);
      final Result<Object?> target = await settings.readSetting(
        SettingId.set011,
      );
      final Result<Object?> budget = await settings.readSetting(
        SettingId.set061,
      );
      final Object? rawTarget = target.isOk ? target.valueOrNull : null;
      final String language = rawTarget is Map<Object?, Object?>
          ? (rawTarget['translationTarget'] is String
                ? rawTarget['translationTarget']! as String
                : _registryDefaultLanguage())
          : _registryDefaultLanguage();
      final Object? rawBudget = budget.isOk ? budget.valueOrNull : null;
      return TranslationSettings(
        targetLanguage: language,
        segmentBudget: rawBudget is int && rawBudget > 0
            ? rawBudget
            : kTranslationSegmentCharBudget,
      );
    });

/// SET-011 的注册表默认目标语言。
String _registryDefaultLanguage() {
  final SettingDefinition? definition = SettingRegistry.findById(
    SettingId.set011,
  );
  final Object? value = definition?.defaultValue;
  if (value is Map<Object?, Object?> && value['translationTarget'] is String) {
    return value['translationTarget']! as String;
  }
  return TranslationLanguage.chinese.code;
}

/// 分段翻译服务。
final Provider<TranslationService> translationServiceProvider =
    Provider<TranslationService>(
      (Ref ref) => TranslationService(
        runner: ref.watch(aiTaskRunnerProvider),
        cache: ref.watch(aiResultCacheProvider),
        clock: ref.watch(aiTaskClockProvider),
        diagnostics: ref.watch(aiDiagnosticSinkProvider),
      ),
    );
