// 文章列表控制器（T017）。
//
// 职责：把筛选/分页状态与用例接起来，持有页面级的**选择集合**与**批量模式**开关。
//
// 三条与产品规则对应的选择：
//
//   1) **写入后重读**而不是在内存里打补丁。三态与收藏都在同一个列表行上，打补丁会
//      在「批量操作只影响了部分行」时显示一个库里不存在的状态。重读一次列表的代价
//      远小于显示假数据。
//
//   2) **选择集合在换筛选后清空**。用户勾选的是「当前看到的这些行」，换筛选后那些
//      行已经不在视野里，继续保留选择会让「批量标已读」作用到用户看不见的文章上。
//
//   3) **批量操作使用范围枚举**（全部/筛选结果/所选行），因此「全部」即使当前筛选是
//      未读也在全库生效——这正是范围选择存在的意义（架构 4.1 的「全部/筛选结果/所选行」）。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flux/core/core.dart';
import 'package:flux/features/settings/application/settings_controller.dart';
import 'package:flux/features/settings/application/settings_store.dart';

import '../application/article_list_state.dart';
import '../application/article_ports.dart';
import '../application/article_state.dart';
import '../application/batch_article_actions.dart';
import '../application/undo_batch_action.dart';

/// 来源筛选下拉用的一个选项。
class FeedFilterOption {
  /// 构造选项。
  const FeedFilterOption({required this.feedId, required this.name});

  /// 订阅 id。
  final int feedId;

  /// 显示名。
  final String name;
}

/// 文章列表页面的完整状态。
class ArticleListPageState {
  /// 构造状态。
  const ArticleListPageState({
    required this.page,
    required this.entries,
    required this.total,
    required this.selectedIds,
    required this.batchMode,
    this.pageError,
    this.actionError,
    this.scope,
    this.undoHandle,
  });

  /// 筛选与分页。
  final ArticleListState page;

  /// 本页条目。
  final List<ArticleListEntry> entries;

  /// 满足筛选的总数。
  final int total;

  /// 已勾选的文章 id（批量模式用）。
  final Set<int> selectedIds;

  /// 是否处于批量模式。
  final bool batchMode;

  /// 读列表失败的原因。
  final AppError? pageError;

  /// 最近一次写入失败的原因。
  final AppError? actionError;

  /// 批量范围（用户显式选择的「全部 / 当前筛选结果 / 所选行」）；null 表示尚未选，
  /// 由界面按「有勾选就用勾选」推导。
  final BatchScope? scope;

  /// 最近一次批量操作的撤销句柄；null 表示没有可撤销的操作。
  ///
  /// 只保留**最近一次**：撤销栈会让界面出现「撤销上一步 / 再上一步」的层级，
  /// 而本任务的危险操作是单步的（改一批状态），多层历史只会让用户不确定自己
  /// 退到了哪一步。
  final BatchUndoHandle? undoHandle;

  /// 复制并覆盖部分字段。
  ArticleListPageState copyWith({
    ArticleListState? page,
    List<ArticleListEntry>? entries,
    int? total,
    Set<int>? selectedIds,
    bool? batchMode,
    AppError? pageError,
    AppError? actionError,
    BatchScope? scope,
    BatchUndoHandle? undoHandle,
    bool clearErrors = false,
    bool clearScope = false,
    bool clearUndo = false,
  }) => ArticleListPageState(
    page: page ?? this.page,
    entries: entries ?? this.entries,
    total: total ?? this.total,
    selectedIds: selectedIds ?? this.selectedIds,
    batchMode: batchMode ?? this.batchMode,
    pageError: clearErrors ? null : (pageError ?? this.pageError),
    actionError: clearErrors ? null : (actionError ?? this.actionError),
    scope: clearScope ? null : (scope ?? this.scope),
    undoHandle: clearUndo ? null : (undoHandle ?? this.undoHandle),
  );

  /// 是否整页都已被勾选（「全选」指示用）。
  bool get allPageSelected =>
      entries.isNotEmpty &&
      entries.every((ArticleListEntry e) => selectedIds.contains(e.id));
}

/// SET-010 的自动标已读开关（默认开）。
///
/// 单独一个 provider 而不是让详情页自己读设置：详情页与列表控制器都要用它，两处
/// 各读一遍设置会让「值不一致」成为可能（一个读到了新值、一个还在旧值）。
final FutureProvider<bool> autoMarkReadProvider = FutureProvider<bool>((
  Ref ref,
) async {
  final SettingsStore settings = ref.watch(settingsStoreProvider);
  final Result<Object?> value = await settings.readSetting(SettingId.set010);
  final SettingDefinition? definition = SettingRegistry.findById(
    SettingId.set010,
  );
  if (value.isErr) {
    // 读不到时按注册表默认值（开）：SET-010 的默认值是「成功显示正文自动标已读」。
    return definition?.defaultValue == true;
  }
  final Object? raw = value.valueOrNull;
  return raw is bool ? raw : definition?.defaultValue == true;
});

/// 文章列表控制器。
final class ArticleListController extends AsyncNotifier<ArticleListPageState> {
  /// 文章端口。
  ArticleCatalogStore get _store => ref.read(articleCatalogProvider);

  /// 单个状态写入用例。
  SetReadingStateUseCase get _setState =>
      SetReadingStateUseCase(articles: _store);

  /// 收藏用例。
  ToggleFavoriteUseCase get _toggleFavorite =>
      ToggleFavoriteUseCase(articles: _store);

  /// 范围解析。
  ResolveBatchScopeUseCase get _resolveScope =>
      ResolveBatchScopeUseCase(articles: _store);

  /// 批量三态。
  BatchSetReadingStateUseCase get _batchState => BatchSetReadingStateUseCase(
    articles: _store,
    resolveScope: _resolveScope,
  );

  /// 批量收藏。
  BatchSetFavoriteUseCase get _batchFavorite =>
      BatchSetFavoriteUseCase(articles: _store, resolveScope: _resolveScope);

  /// 当前批量模式（重读时保持）。
  bool _currentBatchMode = false;

  /// 当前批量范围（重读时保持；换筛选时清空，因为「所选行」在换筛选后已不在视野）。
  BatchScope? _currentScope;

  @override
  Future<ArticleListPageState> build() async {
    // 端口被替换时重建（组合根注入、测试替换）。
    ref.watch(articleCatalogProvider);
    return _read(const ArticleListState());
  }

  /// 读取一页（不改变筛选，供写入后重读）。
  Future<ArticleListPageState> _read(
    ArticleListState page, {
    Set<int>? selectedIds,
    bool? batchMode,
  }) async {
    final Result<ArticlePage> result = await _store.listArticles(page.query);
    if (result.isErr) {
      return ArticleListPageState(
        page: page,
        entries: const <ArticleListEntry>[],
        total: 0,
        selectedIds: selectedIds ?? const <int>{},
        batchMode: batchMode ?? _currentBatchMode,
        pageError: result.errorOrNull,
        scope: _currentScope,
      );
    }
    final ArticlePage loaded = result.unwrap();
    return ArticleListPageState(
      page: page,
      entries: loaded.entries,
      total: loaded.total,
      selectedIds: selectedIds ?? const <int>{},
      batchMode: batchMode ?? _currentBatchMode,
      scope: _currentScope,
    );
  }

  /// 更改筛选（清空选择与页码）。
  Future<void> setFilter(ArticleFilter filter) async {
    final ArticleListPageState current = state.value ?? await future;
    _currentScope = null;
    state = AsyncData<ArticleListPageState>(
      (await _read(current.page.withFilter(filter))).copyWith(clearScope: true),
    );
  }

  /// 更改来源限定（清空选择与页码）。
  Future<void> setFeedFilter(int? feedId) async {
    final ArticleListPageState current = state.value ?? await future;
    _currentScope = null;
    state = AsyncData<ArticleListPageState>(
      (await _read(current.page.withFeed(feedId))).copyWith(clearScope: true),
    );
  }

  /// 选择批量范围（用户显式指定作用范围）。
  void setScope(BatchScope scope) {
    final ArticleListPageState? current = state.value;
    if (current == null) {
      return;
    }
    _currentScope = scope;
    state = AsyncData<ArticleListPageState>(
      current.copyWith(scope: scope, clearErrors: true),
    );
  }

  /// 翻页。
  Future<void> goToPage(int page) async {
    final ArticleListPageState current = state.value ?? await future;
    state = AsyncData<ArticleListPageState>(
      await _read(
        current.page.atPage(page, total: current.total),
        selectedIds: current.selectedIds,
      ),
    );
  }

  /// 重读当前页（写入后调用）。
  Future<void> reload() async {
    final ArticleListPageState current = state.value ?? await future;
    state = AsyncData<ArticleListPageState>(
      await _read(
        current.page,
        selectedIds: current.selectedIds,
        batchMode: current.batchMode,
      ),
    );
  }

  /// 进入/退出批量模式。
  ///
  /// 退出时清空选择：留下的选择集合在下次进入批量模式时会变成一批用户已经忘记的
  /// 勾选，那比没有选择更危险。
  void setBatchMode(bool enabled) {
    final ArticleListPageState? current = state.value;
    if (current == null) {
      return;
    }
    _currentBatchMode = enabled;
    if (!enabled) {
      // 退出批量模式时范围也清空：留着一个「全部文章」的范围，下次进入时用户
      // 会在没有意识到的情况下对一个更宽的范围操作。
      _currentScope = null;
    }
    state = AsyncData<ArticleListPageState>(
      current.copyWith(
        batchMode: enabled,
        selectedIds: enabled ? current.selectedIds : const <int>{},
        clearErrors: true,
        clearScope: !enabled,
      ),
    );
  }

  /// 勾选/取消勾选一行。
  void toggleSelected(int articleId) {
    final ArticleListPageState? current = state.value;
    if (current == null) {
      return;
    }
    final Set<int> next = Set<int>.of(current.selectedIds);
    if (!next.remove(articleId)) {
      next.add(articleId);
    }
    state = AsyncData<ArticleListPageState>(
      current.copyWith(selectedIds: next),
    );
  }

  /// 勾选/取消勾选本页全部。
  void toggleSelectPage() {
    final ArticleListPageState? current = state.value;
    if (current == null) {
      return;
    }
    final Set<int> next = Set<int>.of(current.selectedIds);
    if (current.allPageSelected) {
      for (final ArticleListEntry entry in current.entries) {
        next.remove(entry.id);
      }
    } else {
      for (final ArticleListEntry entry in current.entries) {
        next.add(entry.id);
      }
    }
    state = AsyncData<ArticleListPageState>(
      current.copyWith(selectedIds: next),
    );
  }

  /// 单行设置三态。
  Future<void> setReadingState(int articleId, ReadingState value) async {
    final Result<ArticleStateChange> result = await _setState(
      articleId: articleId,
      state: value,
    );
    await _afterWrite(result.isErr ? result.errorOrNull : null);
  }

  /// 单行切换收藏。
  Future<void> toggleFavorite(int articleId) async {
    final Result<ArticleStateChange> result = await _toggleFavorite.toggle(
      articleId,
    );
    await _afterWrite(result.isErr ? result.errorOrNull : null);
  }

  /// 批量设置三态（按范围）。
  Future<BatchActionReport?> batchSetReadingState({
    required BatchScope scope,
    required ReadingState value,
  }) async {
    final ArticleListPageState current = state.value ?? await future;
    final Result<BatchActionReport> result = await _batchState(
      state: value,
      scope: scope,
      filter: current.page.filter,
      feedId: current.page.feedId,
      selectedIds: current.selectedIds.toList(growable: false),
    );
    return _afterBatch(
      result: result,
      label: _readingStateLabel(value),
      clearUndoOnFailure: true,
    );
  }

  /// 批量设置收藏（按范围）。
  ///
  /// 只在用户**显式**点了收藏操作时被调用：批量改阅读状态走的是另一个方法，
  /// 因此收藏不受影响（手册 6.3「批量未读不影响收藏」）。
  Future<BatchActionReport?> batchSetFavorite({
    required BatchScope scope,
    required bool favorite,
  }) async {
    final ArticleListPageState current = state.value ?? await future;
    final Result<BatchActionReport> result = await _batchFavorite(
      favorite: favorite,
      scope: scope,
      filter: current.page.filter,
      feedId: current.page.feedId,
      selectedIds: current.selectedIds.toList(growable: false),
    );
    return _afterBatch(
      result: result,
      label: favorite ? 'favorite' : 'unfavorite',
      clearUndoOnFailure: true,
    );
  }

  /// 批量操作后的统一处理：重读 + 记录撤销句柄（或失败）。
  ///
  /// 失败时**清掉**上一个撤销句柄：留着它会让用户以为「撤销上一次」能处理这次的
  /// 失败，而它实际撤的是更早的一次成功操作——那是会改错数据的误导。
  Future<BatchActionReport?> _afterBatch({
    required Result<BatchActionReport> result,
    required String label,
    required bool clearUndoOnFailure,
  }) async {
    if (result.isErr) {
      await _afterWrite(result.errorOrNull);
      final ArticleListPageState? current = state.value;
      if (current != null && clearUndoOnFailure) {
        state = AsyncData<ArticleListPageState>(
          current.copyWith(actionError: result.errorOrNull, clearUndo: true),
        );
      }
      return null;
    }
    final BatchActionReport report = result.unwrap();
    await _afterWrite(null);
    final ArticleListPageState? current = state.value;
    if (current == null) {
      return report;
    }
    // 只有确实改动了行才提供撤销：空范围操作没有可恢复的东西，给一个「撤销」
    // 按钮却什么都不做，会让用户怀疑撤销功能坏了。
    final BatchUndoHandle? handle = report.canUndo && report.applied > 0
        ? BatchUndoHandle(
            label: label,
            snapshots: report.snapshots,
            affectedCount: report.applied,
          )
        : null;
    state = AsyncData<ArticleListPageState>(
      current.copyWith(
        undoHandle: handle,
        clearUndo: handle == null,
        clearErrors: true,
      ),
    );
    return report;
  }

  /// 撤销最近一次批量操作。
  Future<Result<int>> undoLastBatchAction() async {
    final BatchUndoHandle? handle = state.value?.undoHandle;
    if (handle == null) {
      // 没有可撤销的操作：返回 0 而不是错误（调用方的按钮此时应当是禁用的）。
      return const Ok<int>(0);
    }
    final Result<int> restored = await UndoBatchActionUseCase(articles: _store)(
      handle,
    );
    await _afterWrite(restored.errorOrNull);
    final ArticleListPageState? current = state.value;
    if (current != null) {
      state = AsyncData<ArticleListPageState>(
        current.copyWith(
          // 撤销之后句柄失效（再撤一次只会把同样的值再写一遍）。
          clearUndo: true,
          actionError: restored.errorOrNull,
        ),
      );
    }
    return restored;
  }

  /// 清掉撤销句柄（用户主动忽略提示条时）。
  void clearUndoHandle() {
    final ArticleListPageState? current = state.value;
    if (current == null || current.undoHandle == null) {
      return;
    }
    state = AsyncData<ArticleListPageState>(current.copyWith(clearUndo: true));
  }

  /// 阅读状态的操作名（撤销提示条文案用）。
  static String _readingStateLabel(ReadingState value) => switch (value) {
    ReadingState.unread => 'markUnread',
    ReadingState.read => 'markRead',
    ReadingState.later => 'markLater',
  };

  /// 写入后的统一处理：重读列表并把失败保留在状态里。
  Future<void> _afterWrite(AppError? error) async {
    await reload();
    if (error == null) {
      return;
    }
    final ArticleListPageState? current = state.value;
    if (current != null) {
      state = AsyncData<ArticleListPageState>(
        current.copyWith(actionError: error),
      );
    }
  }

  /// 清掉写入失败提示。
  void clearActionError() {
    final ArticleListPageState? current = state.value;
    if (current == null || current.actionError == null) {
      return;
    }
    state = AsyncData<ArticleListPageState>(
      current.copyWith(clearErrors: true),
    );
  }
}

/// 文章列表控制器 Provider。
final AsyncNotifierProvider<ArticleListController, ArticleListPageState>
articleListControllerProvider =
    AsyncNotifierProvider<ArticleListController, ArticleListPageState>(
      ArticleListController.new,
    );
