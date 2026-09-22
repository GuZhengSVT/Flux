// 今日新闻页的控制器（T038 的最小可用界面；架构 4.4 的日期/进度/结果/版本）。
//
// 职责：把「日期 → 版本列表 → 当前版本」与「一次生成的阶段进度」拼成界面可直接渲染的状态，
// 并把「生成」需要的两次异步读取（配置、上限）收拢在这里。
//
// 四条刻意的设计：
//
//   1) **阶段进度来自编排层的真实回调**（[NewsRunStage]）。界面不自己编造阶段顺序：进度条
//      上显示的顺序就是实际执行顺序，不会出现「界面说正在核验、实际还在抓网页」。
//   2) **历史归属「日期 + 当时的时区」**，不是「日期」。用户旅行后旧记录仍按当时的本地日期
//      可查（架构 4.4「历史结果保存日期+时区，旅行后可查旧记录而不重写日期」）；拿现在的
//      设备时区去查一条在别处生成的记录会查不到，而界面只能显示「这一天没有记录」。
//   3) **生成前必须确认费用**由界面负责（控制器只执行）：一次生成会发多次检索与模型调用，
//      当天已有成功版本时确认框额外说明「这是再一次生成」。
//   4) **失败不清空已有版本**。生成失败时页面保留上一次成功版本与它的条目，只在顶部显示
//      失败原因（架构 4.4「取消/失败保留上次成功版本」）。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flux/core/core.dart';
import 'package:flux/features/ai/application/ai_task_providers.dart';
import 'package:flux/features/ai/application/model_manager.dart'
    show SettingsReader;
import 'package:flux/features/ai/domain/ai_message.dart';
import 'package:flux/features/articles/application/article_ai_providers.dart'
    show summaryZoneProvider;

import 'news_run_providers.dart';
import 'news_run_service.dart';
import 'news_source_config.dart';
import 'news_source_providers.dart';

/// 今日页的状态。
final class NewsTodayState {
  /// 构造状态。
  const NewsTodayState({
    required this.localDate,
    this.current,
    this.versions = const <NewsRunRecord>[],
    this.dates = const <NewsRunDateRef>[],
    this.stage,
    this.generating = false,
    this.lastError,
  });

  /// 当前展示的本地日期。
  final String localDate;

  /// 当前展示版本（没有成功版本时为 null）。
  final NewsRunRecord? current;

  /// 该日期该时区的全部版本（版本号倒序）。
  final List<NewsRunRecord> versions;

  /// 有记录的「日期 + 时区」组合（日期倒序）。
  final List<NewsRunDateRef> dates;

  /// 生成中的当前阶段；不在生成时为 null。
  final NewsRunStage? stage;

  /// 是否正在生成。
  final bool generating;

  /// 最近一次失败原因。
  final AppError? lastError;

  /// 当天是否已经有成功版本（决定确认框的措辞与「再次生成」提示）。
  bool get hasSuccessVersion => current != null;

  /// 可切换的历史版本数（多于一个时才显示版本切换）。
  bool get hasMultipleVersions => versions.length > 1;

  /// 当前版本所属时区（历史查询用它，避免用现在的设备时区）。
  String? get activeTimeZone =>
      current?.timeZone ?? (versions.isEmpty ? null : versions.first.timeZone);

  /// 复制并覆盖部分字段。
  NewsTodayState copyWith({
    String? localDate,
    NewsRunRecord? current,
    List<NewsRunRecord>? versions,
    List<NewsRunDateRef>? dates,
    NewsRunStage? stage,
    bool clearStage = false,
    bool? generating,
    AppError? lastError,
    bool clearError = false,
  }) => NewsTodayState(
    localDate: localDate ?? this.localDate,
    current: current ?? this.current,
    versions: versions ?? this.versions,
    dates: dates ?? this.dates,
    stage: clearStage ? null : (stage ?? this.stage),
    generating: generating ?? this.generating,
    lastError: clearError ? null : (lastError ?? this.lastError),
  );
}

/// 今日页控制器。
final class NewsTodayController extends AsyncNotifier<NewsTodayState> {
  /// 生成用的取消信号（用户点「取消」时触发）。
  AiCancellation? _cancellation;

  @override
  Future<NewsTodayState> build() async {
    final SessionLocalZone zone = ref.watch(summaryZoneProvider);
    final String today = localDateKey(
      zone.toLocal(ref.watch(aiTaskClockProvider).now()),
    );
    return _load(localDate: today, timeZone: zone.ianaName);
  }

  /// 切换展示日期（默认查「当前设备时区」下的记录，并在必要时回退到该日期的其它时区）。
  Future<void> selectDate(String localDate) async {
    final NewsTodayState? current = state.value;
    state = AsyncData<NewsTodayState>(
      (current ?? NewsTodayState(localDate: localDate)).copyWith(
        localDate: localDate,
        clearError: true,
      ),
    );
    state = AsyncData<NewsTodayState>(
      await _load(
        localDate: localDate,
        timeZone: ref.read(summaryZoneProvider).ianaName,
      ),
    );
  }

  /// 把某个历史版本切为当前展示版本（用户手动回退，架构 4.4 的版本切换）。
  Future<void> selectVersion(int version) async {
    final NewsTodayState? current = state.value;
    final String? timeZone = current?.activeTimeZone;
    if (current == null || timeZone == null) {
      return;
    }
    final Result<void> result = await ref
        .read(newsRunStoreProvider)
        .setCurrentVersion(
          localDate: current.localDate,
          timeZone: timeZone,
          version: version,
        );
    if (result.isErr) {
      state = AsyncData<NewsTodayState>(
        current.copyWith(lastError: result.errorOrNull),
      );
      return;
    }
    state = AsyncData<NewsTodayState>(
      await _load(localDate: current.localDate, timeZone: timeZone),
    );
  }

  /// 取消正在进行的生成。
  void cancel() => _cancellation?.cancel();

  /// 生成当天（或当前所选日期）的新闻。
  Future<NewsRunOutcome?> generate() async {
    final NewsTodayState? existing = state.value;
    final SessionLocalZone zone = ref.read(summaryZoneProvider);
    final String date =
        existing?.localDate ??
        localDateKey(zone.toLocal(ref.read(aiTaskClockProvider).now()));
    state = AsyncData<NewsTodayState>(
      (existing ?? NewsTodayState(localDate: date)).copyWith(
        generating: true,
        clearStage: true,
        clearError: true,
      ),
    );
    final AiCancellation cancellation = AiCancellation();
    _cancellation = cancellation;

    // 配置与总开关：与 T036 的设置页读同一份来源（组合 prompt、必访站、关键词、禁词）。
    final bool globalEnabled = await ref.read(newsGlobalEnabledProvider.future);
    final NewsPromptLanguage language = await ref.read(
      newsPromptLanguageProvider.future,
    );
    final Result<NewsConfigState> config = await ref
        .read(newsSourceConfigServiceProvider)
        .load(globalEnabled: globalEnabled, language: language);
    if (config.isErr) {
      _cancellation = null;
      state = AsyncData<NewsTodayState>(
        (state.value ?? NewsTodayState(localDate: date)).copyWith(
          generating: false,
          lastError: config.errorOrNull,
        ),
      );
      return null;
    }

    final NewsRunService service = await ref.read(
      newsRunServiceBuilderProvider,
    )(zone: zone, onStage: _onStage);
    final NewsRunOutcome outcome = await service.run(
      NewsRunInput(
        taskId:
            'news-$date-${ref.read(aiTaskClockProvider).now().microsecondsSinceEpoch}',
        config: config.valueOrNull!,
        globalEnabled: globalEnabled,
        cancellation: cancellation,
        regenerate: existing?.hasSuccessVersion ?? false,
      ),
    );
    _cancellation = null;
    final NewsTodayState reloaded = await _load(
      localDate: outcome.snapshot.localDate,
      timeZone: outcome.snapshot.deviceTimeZone,
    );
    state = AsyncData<NewsTodayState>(
      reloaded.copyWith(
        generating: false,
        clearStage: true,
        lastError: outcome.ok ? null : outcome.error,
        clearError: outcome.ok,
      ),
    );
    return outcome;
  }

  void _onStage(NewsRunStage stage) {
    final NewsTodayState? current = state.value;
    if (current == null) {
      return;
    }
    state = AsyncData<NewsTodayState>(current.copyWith(stage: stage));
  }

  /// 读某一天某时区的版本。
  ///
  /// [timeZone] 为 null 时表示「先用当前设备时区问一次，没记录再按日期索引找当时那个时区」
  /// （见 [NewsRunStore.listDateRefs] 的说明）。
  Future<NewsTodayState> _load({
    required String localDate,
    required String? timeZone,
  }) async {
    final NewsRunStore store = ref.read(newsRunStoreProvider);
    final Result<List<NewsRunDateRef>> refs = await store.listDateRefs();
    final List<NewsRunDateRef> dates = refs.isOk
        ? refs.valueOrNull!
        : const <NewsRunDateRef>[];
    String? zone = timeZone;
    if (zone == null) {
      // 该日期在历史里的实际时区（可能不止一个；取最新的那条）。
      for (final NewsRunDateRef ref in dates) {
        if (ref.localDate == localDate) {
          zone = ref.timeZone;
          break;
        }
      }
    }
    zone ??= ref.read(summaryZoneProvider).ianaName;
    final Result<List<NewsRunRecord>> versions = await store.loadVersions(
      localDate: localDate,
      timeZone: zone,
    );
    if (versions.isErr) {
      return NewsTodayState(
        localDate: localDate,
        dates: dates,
        lastError: versions.errorOrNull,
      );
    }
    final Result<NewsRunRecord?> current = await store.loadCurrent(
      localDate: localDate,
      timeZone: zone,
    );
    return NewsTodayState(
      localDate: localDate,
      current: current.isOk ? current.valueOrNull : null,
      versions: versions.valueOrNull!,
      dates: dates,
    );
  }
}

/// 今日页状态 Provider。
final AsyncNotifierProvider<NewsTodayController, NewsTodayState>
newsTodayControllerProvider =
    AsyncNotifierProvider<NewsTodayController, NewsTodayState>(
      NewsTodayController.new,
    );

/// 今日页的费用确认需要读上限（SET-060）：用只读的设置端口，不给界面写入口。
final Provider<SettingsReader> newsSettingsReaderProvider =
    Provider<SettingsReader>(
      (Ref ref) => throw StateError(
        'newsSettingsReaderProvider 未被组合根覆盖：见 lib/app/app_providers.dart',
      ),
    );
