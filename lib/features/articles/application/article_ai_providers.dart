// 选词解释 / 单文摘要 / 自动摘要的 Provider（T034）。
//
// 与 T033 的 vision_ports 同一做法：端口与读设置的窄接口在 features 侧声明（默认安全值），
// 组合根只负责把 infrastructure 的实现接上来。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flux/core/core.dart';

import 'package:flux/features/ai/application/ai_task_providers.dart';
import 'package:flux/features/ai/application/ai_ports.dart';
import 'package:flux/features/ai/domain/ai_message.dart';
import 'package:flux/features/ai/domain/ai_model.dart';
import 'package:flux/features/settings/application/settings_controller.dart';
import 'package:flux/features/settings/application/settings_store.dart';
import 'package:flux/features/articles/application/article_ai_text_tasks.dart';
import 'package:flux/features/articles/application/auto_summary_batch.dart';
import 'package:flux/features/articles/application/article_ports.dart';

/// SET-037（缺摘要自动 AI 摘要）与 SET-064（当天上限）的读值。
///
/// 两个值一起读而不是各自一个 provider：它们在同一次刷新批处理里被一起使用，分开读会让
/// 「开关开着但上限读的是上一次的值」这类错配成为可能。
class AutoSummarySettings {
  /// 构造设置。
  const AutoSummarySettings({required this.enabled, required this.dailyLimit});

  /// SET-037 的开关值（**默认关**）。
  final bool enabled;

  /// SET-064 的当天上限（默认 50）。
  final int dailyLimit;
}

/// 读 SET-037 / SET-064；读不到时用注册表默认值（关 / 50）。
final FutureProvider<AutoSummarySettings> autoSummarySettingsProvider =
    FutureProvider<AutoSummarySettings>((Ref ref) async {
      final SettingsStore settings = ref.watch(settingsStoreProvider);
      const bool fallbackEnabled = false;
      const int fallbackLimit = 50;
      final Result<Object?> enabledRead = await settings.readSetting(
        SettingId.set037,
      );
      final Result<Object?> limitRead = await settings.readSetting(
        SettingId.set064,
      );
      final Object? enabledRaw = enabledRead.isOk
          ? enabledRead.valueOrNull
          : null;
      final Object? limitRaw = limitRead.isOk ? limitRead.valueOrNull : null;
      return AutoSummarySettings(
        enabled: enabledRaw is bool ? enabledRaw : fallbackEnabled,
        dailyLimit: limitRaw is int && limitRaw > 0 ? limitRaw : fallbackLimit,
      );
    });

/// 在一次列表刷新之后跑一遍自动摘要批处理（SET-037/SET-064）。
///
/// **只在刷新批处理里调用**：滚动、渲染、切筛选都不触发它。这条约束是产品规则
/// （手册 T034「滚动不触发计费——只在刷新批处理中做」），因此它由调用点的位置保证，
/// 而不是由本函数内部再判一次「是谁调的我」。
///
/// 依赖以参数传入而不是接收一个 `Ref`：界面侧拿到的是 `WidgetRef`（与 `Ref` 不是同一
/// 类型），而让本函数只依赖「一个设置值 + 一个取模型的回调 + 一个批处理服务」之后，
/// 界面与控制器都能用同一份实现，测试也不必构造整个容器。
Future<AutoSummaryBatchReport> runAutoSummaryAfterRefresh({
  required AutoSummarySettings settings,
  required Future<Result<List<AiModel>>> Function() loadModels,
  required AutoSummaryBatchService service,
  AiCancellation? cancellation,
}) async {
  if (!settings.enabled) {
    // SET-037 关闭：连模型列表都不读，一个请求都不发。
    return const AutoSummaryBatchReport(
      attempted: 0,
      succeeded: 0,
      failed: 0,
      fromCache: 0,
      disabled: true,
    );
  }
  final Result<List<AiModel>> models = await loadModels();
  if (models.isErr || models.valueOrNull!.isEmpty) {
    return const AutoSummaryBatchReport(
      attempted: 0,
      succeeded: 0,
      failed: 0,
      fromCache: 0,
    );
  }
  return service.runBatch(
    enabled: true,
    dailyLimit: settings.dailyLimit,
    models: models.valueOrNull!,
    cancellation: cancellation,
  );
}

/// 当天的自动摘要计数端口（SET-064）。
///
/// 默认实现抛错：额度是费用边界，漏接线必须在使用时立刻暴露（而不是静默按 0 处理）。
final Provider<DailySummaryCounter> dailySummaryCounterProvider =
    Provider<DailySummaryCounter>(
      (Ref ref) => throw StateError(
        'dailySummaryCounterProvider 未被组合根覆盖：见 lib/app/app_providers.dart',
      ),
    );

/// 日期归属使用的时区（设备当地时区；由组合根接上与会话时区同一份快照）。
final Provider<SessionLocalZone> summaryZoneProvider =
    Provider<SessionLocalZone>(
      (Ref ref) => throw StateError(
        'summaryZoneProvider 未被组合根覆盖：见 lib/app/app_providers.dart',
      ),
    );

/// 单材料预算（SET-061）的读值；未接线时用注册表默认值 8000。
final Provider<int> summaryCharBudgetProvider = Provider<int>(
  (Ref ref) => kSingleMaterialCharBudget,
);

/// 单文摘要服务（SET-061 预算由 summaryCharBudgetProvider 提供）。
final Provider<ArticleSummaryService> articleSummaryServiceProvider =
    Provider<ArticleSummaryService>(
      (Ref ref) => ArticleSummaryService(
        runner: ref.watch(aiTaskRunnerProvider),
        clock: ref.watch(aiTaskClockProvider),
        charBudget: ref.watch(summaryCharBudgetProvider),
      ),
    );

/// 选词解释服务。
final Provider<SelectionExplainService> selectionExplainServiceProvider =
    Provider<SelectionExplainService>(
      (Ref ref) => SelectionExplainService(
        runner: ref.watch(aiTaskRunnerProvider),
        clock: ref.watch(aiTaskClockProvider),
      ),
    );

/// 缺摘要自动摘要批处理。
final Provider<AutoSummaryBatchService> autoSummaryBatchServiceProvider =
    Provider<AutoSummaryBatchService>(
      (Ref ref) => AutoSummaryBatchService(
        articles: ref.watch(articleCatalogProvider),
        cache: ref.watch(aiResultCacheProvider),
        summary: ref.watch(articleSummaryServiceProvider),
        counter: ref.watch(dailySummaryCounterProvider),
        zone: ref.watch(summaryZoneProvider),
        clock: ref.watch(aiTaskClockProvider),
        diagnostics: ref.watch(aiDiagnosticSinkProvider),
      ),
    );
