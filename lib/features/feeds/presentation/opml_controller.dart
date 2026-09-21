// OPML 导入/导出流程控制器（T015）。
//
// 一个**不分步**的状态机：选文件 → 预览 → 导入 → 结果，四步的状态都放在同一个
// 不可变对象里。分步用多个 Provider 会带来「预览存在但选文件状态已清空」这类
// 不可能状态，而它们只在边界时序里出现，最难测。
//
// 重试**不重建**预览：失败项的地址已经在结果里，重试直接复用它们（见
// ImportOpmlUseCase.retryFailed 的说明）。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flux/core/core.dart';

import '../application/add_feed.dart';
import '../application/feed_ports.dart';
import '../application/file_access.dart';
import '../application/opml_import_export.dart';

/// 导入流程所处的阶段。
enum OpmlImportStage {
  /// 还没有选文件。
  idle,

  /// 正在读文件或解析。
  loading,

  /// 已解析出预览，等待用户确认。
  preview,

  /// 正在逐项导入。
  importing,

  /// 导入完成，展示逐项结果。
  result,

  /// 流程失败（选文件或解析失败），带类型化错误。
  failed,
}

/// 导入流程状态。
class OpmlImportState {
  /// 构造状态。
  const OpmlImportState({
    required this.stage,
    required this.strategy,
    this.fileName,
    this.preview,
    this.result,
    this.error,
  });

  /// 初始状态。
  const OpmlImportState.initial()
    : stage = OpmlImportStage.idle,
      strategy = OpmlGroupStrategy.uncategorized,
      fileName = null,
      preview = null,
      result = null,
      error = null;

  /// 当前阶段。
  final OpmlImportStage stage;

  /// 当前分组策略（SET-026）。
  final OpmlGroupStrategy strategy;

  /// 选中的文件名（仅用于显示）。
  final String? fileName;

  /// 预览（preview / importing / result 阶段非空）。
  final OpmlPreview? preview;

  /// 逐项结果（result 阶段非空）。
  final OpmlImportResult? result;

  /// 失败原因（failed 阶段非空）。
  final AppError? error;

  /// 复制并覆盖部分字段。
  OpmlImportState copyWith({
    OpmlImportStage? stage,
    OpmlGroupStrategy? strategy,
    String? fileName,
    OpmlPreview? preview,
    OpmlImportResult? result,
    AppError? error,
    bool clearError = false,
  }) => OpmlImportState(
    stage: stage ?? this.stage,
    strategy: strategy ?? this.strategy,
    fileName: fileName ?? this.fileName,
    preview: preview ?? this.preview,
    result: result ?? this.result,
    error: clearError ? null : (error ?? this.error),
  );

  /// 是否可确认导入（有可导入项且不在忙碌状态）。
  bool get canImport =>
      stage == OpmlImportStage.preview &&
      (preview?.hasNothingToImport == false);

  /// 是否忙碌（界面据此禁用按钮，避免重复触发）。
  bool get isBusy =>
      stage == OpmlImportStage.loading || stage == OpmlImportStage.importing;
}

/// OPML 导入流程控制器。
final class OpmlImportController extends Notifier<OpmlImportState> {
  @override
  OpmlImportState build() => const OpmlImportState.initial();

  /// 导入用例（每次从端口取：端口被替换时行为随之改变）。
  ImportOpmlUseCase get _useCase => ImportOpmlUseCase(
    addFeed: AddFeedUseCase(
      fetcher: ref.read<FeedFetcher>(feedFetcherProvider),
      catalog: ref.read<FeedCatalogStore>(feedCatalogProvider),
      articles: ref.read<FeedArticleStore>(feedArticleStoreProvider),
      diagnostics: ref.read<DiagnosticSink>(diagnosticSinkProvider),
    ),
    catalog: ref.read<FeedCatalogStore>(feedCatalogProvider),
  );

  /// 选文件并解析出预览。
  Future<void> pickAndPreview() async {
    if (state.isBusy) {
      return;
    }
    state = state.copyWith(stage: OpmlImportStage.loading, clearError: true);

    final Result<PickedFile?> picked = await ref
        .read<FileAccessPort>(fileAccessProvider)
        .pickOpmlToRead();
    if (picked.isErr) {
      state = state.copyWith(
        stage: OpmlImportStage.failed,
        error: picked.errorOrNull,
      );
      return;
    }
    final PickedFile? file = picked.valueOrNull;
    if (file == null) {
      // 用户取消：安静回到 idle，不报错（取消不是失败）。
      state = const OpmlImportState.initial();
      return;
    }

    await _previewDocument(file.content, fileName: baseFileName(file.path));
  }

  /// 用一段文档直接预览（供测试与「粘贴文本」类入口使用）。
  Future<void> previewDocument(String document, {String? fileName}) async {
    if (state.isBusy) {
      return;
    }
    state = state.copyWith(stage: OpmlImportStage.loading, clearError: true);
    await _previewDocument(document, fileName: fileName);
  }

  Future<void> _previewDocument(String document, {String? fileName}) async {
    final Result<OpmlPreview> preview = await _useCase.preview(
      document,
      strategy: state.strategy,
    );
    if (preview.isErr) {
      state = OpmlImportState(
        stage: OpmlImportStage.failed,
        strategy: state.strategy,
        fileName: fileName,
        error: preview.errorOrNull,
      );
      return;
    }
    state = OpmlImportState(
      stage: OpmlImportStage.preview,
      strategy: state.strategy,
      fileName: fileName,
      preview: preview.unwrap(),
    );
  }

  /// 切换分组策略（SET-026），并**重新预览**。
  ///
  /// 必须重新预览：策略决定每条明细展示的归属，而预览对象里就带着归属；只改状态
  /// 里的策略字段会让界面显示的归属与将要导入的归属不一致。重新预览不联网（只查
  /// 库匹配），因此代价可以接受。
  Future<void> setStrategy(OpmlGroupStrategy strategy) async {
    final String? document = state.preview?.document;
    state = state.copyWith(strategy: strategy);
    if (document == null) {
      return;
    }
    await _previewDocument(document, fileName: state.fileName);
  }

  /// 执行导入。
  Future<void> runImport() async {
    final OpmlPreview? preview = state.preview;
    if (preview == null || state.isBusy) {
      return;
    }
    state = state.copyWith(stage: OpmlImportStage.importing);

    final Result<OpmlImportResult> result = await _useCase.import(preview);
    if (result.isErr) {
      state = state.copyWith(
        stage: OpmlImportStage.failed,
        error: result.errorOrNull,
      );
      return;
    }
    state = state.copyWith(
      stage: OpmlImportStage.result,
      result: result.unwrap(),
    );
  }

  /// 重试失败项（保持已成功项不变）。
  Future<void> retryFailed() async {
    final OpmlImportResult? previous = state.result;
    if (previous == null || state.isBusy || !previous.hasRetryableFailures) {
      return;
    }
    state = state.copyWith(stage: OpmlImportStage.importing);

    final Result<OpmlImportResult> retried = await _useCase.retryFailed(
      previous,
    );
    if (retried.isErr) {
      state = state.copyWith(
        stage: OpmlImportStage.result,
        error: retried.errorOrNull,
      );
      return;
    }
    state = state.copyWith(
      stage: OpmlImportStage.result,
      result: retried.unwrap(),
    );
  }

  /// 放弃当前文件回到初始状态。
  void reset() => state = const OpmlImportState.initial();
}

/// 取路径的最后一段（不引 path 包：这里只需要一个显示用短名）。
String baseFileName(String path) {
  final int slash = path.lastIndexOf(RegExp(r'[/\\]'));
  return slash < 0 ? path : path.substring(slash + 1);
}

/// 控制器 Provider。
final NotifierProvider<OpmlImportController, OpmlImportState>
opmlImportControllerProvider =
    NotifierProvider<OpmlImportController, OpmlImportState>(
      OpmlImportController.new,
    );
