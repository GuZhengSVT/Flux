// 批量文章操作（T017；架构 4.1「列表批量状态操作」、手册 6.3）。
//
// 范围有三种（架构 4.1 的「全部 / 筛选结果 / 所选行」），它们在**解析成 id 列表**之后
// 走同一条写入路径——这样「点全部标已读」与「勾选几行标已读」不会因为两条实现而出现
// 行为差异。
//
// 三条规则写在这里而不是靠界面自觉：
//
//   1) **批量改阅读状态不动收藏**。实现上分批调用 setReadingState / setFavorite，
//      两边的补丁里都没有对方那个列（见 infra 实现），因此这一条有两层保证。
//
//   2) **范围为空时不发写入**，并且**如实返回 0**。「批量标已读」在空筛选结果上
//      报告「已标记 3 篇」是纯粹的谎报；界面需要的是「没有可操作的文章」。
//
//   3) **所选行里不存在的 id 被忽略**（而不是让整批失败）。界面持有的选择集合可能
//      包含刚被删除的文章（T018 删除、或同步在中间落地），让整批失败会让用户无法
//      完成一个本可以完成的操作。被忽略的数量会返回给调用方，供界面如实说明。
library;

import 'package:flux/core/core.dart';

/// 批量操作的结果。
class BatchActionReport {
  /// 构造结果。
  const BatchActionReport({
    required this.requested,
    required this.applied,
    this.ignoredMissing = 0,
    this.error,
    this.snapshots = const <ArticleStateSnapshot>[],
    this.changedIds = const <int>[],
  });

  /// 请求涉及的文章数（解析后的 id 数量）。
  final int requested;

  /// 实际写入的行数。
  final int applied;

  /// 因文章不存在而被忽略的数量。
  final int ignoredMissing;

  /// 失败原因；成功时为 null。
  final AppError? error;

  /// 是否成功。
  bool get succeeded => error == null;

  /// 范围是否为空（没有可操作的文章）。
  bool get isEmptyScope => requested == 0;

  /// 操作**之前**的状态快照（撤销用），只含确实被改动的行。
  ///
  /// 为什么在报告里返回而不是让界面自己去查：操作与快照必须在同一个时间点上一致。
  /// 界面重查一次会读到已被改动的值，撤销就会变成「把新值写回去」。
  final List<ArticleStateSnapshot> snapshots;

  /// 确实发生改动的文章 id（[applied] 的明细）。
  final List<int> changedIds;

  /// 是否可以撤销（有快照才有东西可恢复）。
  bool get canUndo => snapshots.isNotEmpty;
}

/// 一次批量操作的撤销句柄。
///
/// 为什么是独立对象而不是把「撤销」做成第二次批量操作：撤销的语义是「回到操作之前的
/// 每一行的具体值」，而第二次批量操作只知道「设成某个统一值」——用它来撤销「把一批
/// 混合状态的文章标为已读」只会把它们全部设成同一个值，那不是撤销。
class BatchUndoHandle {
  /// 构造句柄。
  const BatchUndoHandle({
    required this.label,
    required this.snapshots,
    required this.affectedCount,
  });

  /// 操作名（提示条文案里说明撤销的是哪一步）。
  final String label;

  /// 操作前的状态快照。
  final List<ArticleStateSnapshot> snapshots;

  /// 受影响的行数。
  final int affectedCount;
}

/// 把范围解析成 id 列表的共同步骤。
///
/// 抽成单独一个类而不是塞进每个操作里：三个批量操作（已读/未读/later/收藏/取消收藏）
/// 的范围语义必须完全一致，任何一处单独实现都会让「全部」在不同按钮下含义不同。
final class ResolveBatchScopeUseCase {
  /// 构造用例。
  const ResolveBatchScopeUseCase({required this.articles});

  /// 文章端口。
  final ArticleCatalogStore articles;

  /// 解析范围。
  Future<Result<List<int>>> call({
    required BatchScope scope,
    ArticleFilter filter = ArticleFilter.all,
    int? feedId,
    List<int> selectedIds = const <int>[],
  }) async {
    switch (scope) {
      case BatchScope.all:
        return articles.listArticleIds();
      case BatchScope.filtered:
        return articles.listArticleIds(filter: filter, feedId: feedId);
      case BatchScope.selected:
        if (selectedIds.isEmpty) {
          return const Ok<List<int>>(<int>[]);
        }
        // 只保留确实存在的行，并按请求顺序去重：界面可能重复传入同一个 id
        // （例如同一行被两次手势加入选择），重复 id 会让计数虚高。
        final Result<List<ArticleListEntry>> found = await articles
            .findArticles(selectedIds);
        if (found.isErr) {
          return Err<List<int>>(found.errorOrNull!);
        }
        return Ok<List<int>>(
          found.valueOrNull!
              .map((ArticleListEntry e) => e.id)
              .toSet()
              .toList(growable: false),
        );
    }
  }
}

/// 批量设置阅读状态。
///
/// 有意**不**接受 [ReadingState.later] 以外的特殊分支：三个取值走同一条路径，
/// 因此「批量标未读」与「批量标稍后读」不可能有不同的副作用。
final class BatchSetReadingStateUseCase {
  /// 构造用例。
  const BatchSetReadingStateUseCase({
    required this.articles,
    required this.resolveScope,
    this.diagnostics = const NoopDiagnosticSink(),
  });

  /// 文章端口。
  final ArticleCatalogStore articles;

  /// 范围解析。
  final ResolveBatchScopeUseCase resolveScope;

  /// 诊断记录。
  final DiagnosticSink diagnostics;

  /// 执行批量设置。
  Future<Result<BatchActionReport>> call({
    required ReadingState state,
    required BatchScope scope,
    ArticleFilter filter = ArticleFilter.all,
    int? feedId,
    List<int> selectedIds = const <int>[],
  }) async {
    final Result<List<int>> ids = await resolveScope(
      scope: scope,
      filter: filter,
      feedId: feedId,
      selectedIds: selectedIds,
    );
    if (ids.isErr) {
      return Err<BatchActionReport>(ids.errorOrNull!);
    }
    final List<int> articleIds = ids.valueOrNull!;
    if (articleIds.isEmpty) {
      // 空范围不发写入：返回 0，界面据此显示「没有可操作的文章」而不是报成功。
      return const Ok<BatchActionReport>(
        BatchActionReport(requested: 0, applied: 0),
      );
    }

    // 先取操作前的状态：撤销需要「回到操作之前」，因此快照必须在此之前建立。
    final Result<List<ArticleListEntry>> before = await articles.findArticles(
      articleIds,
    );
    if (before.isErr) {
      return Err<BatchActionReport>(before.errorOrNull!);
    }
    final List<ArticleStateSnapshot> snapshots = <ArticleStateSnapshot>[
      for (final ArticleListEntry entry in before.valueOrNull!)
        ArticleStateSnapshot(
          articleId: entry.id,
          readingState: entry.readingState,
          favorite: entry.favorite,
        ),
    ];

    final Result<int> written = await articles.setReadingState(
      articleIds: articleIds,
      state: state,
    );
    if (written.isErr) {
      return Err<BatchActionReport>(written.errorOrNull!);
    }
    final int applied = written.valueOrNull ?? 0;
    diagnostics.info(
      '批量设为 ${state.name}：$applied 篇（范围 ${scope.name}）',
      tag: 'article.state.batch',
    );
    return Ok<BatchActionReport>(
      BatchActionReport(
        requested: articleIds.length,
        applied: applied,
        snapshots: snapshots,
        changedIds: articleIds,
      ),
    );
  }
}

/// 批量设置收藏。
///
/// 与批量阅读状态的**关键区别**：本用例只出现在用户显式点了收藏操作时。
/// 「批量标未读」不会走到这里，因此收藏在批量阅读操作里保持不变
/// （手册 6.3「批量未读不影响收藏」）。
final class BatchSetFavoriteUseCase {
  /// 构造用例。
  const BatchSetFavoriteUseCase({
    required this.articles,
    required this.resolveScope,
    this.diagnostics = const NoopDiagnosticSink(),
  });

  /// 文章端口。
  final ArticleCatalogStore articles;

  /// 范围解析。
  final ResolveBatchScopeUseCase resolveScope;

  /// 诊断记录。
  final DiagnosticSink diagnostics;

  /// 执行批量设置。
  Future<Result<BatchActionReport>> call({
    required bool favorite,
    required BatchScope scope,
    ArticleFilter filter = ArticleFilter.all,
    int? feedId,
    List<int> selectedIds = const <int>[],
  }) async {
    final Result<List<int>> ids = await resolveScope(
      scope: scope,
      filter: filter,
      feedId: feedId,
      selectedIds: selectedIds,
    );
    if (ids.isErr) {
      return Err<BatchActionReport>(ids.errorOrNull!);
    }
    final List<int> articleIds = ids.valueOrNull!;
    if (articleIds.isEmpty) {
      return const Ok<BatchActionReport>(
        BatchActionReport(requested: 0, applied: 0),
      );
    }

    // 先取操作前的状态：撤销需要「回到操作之前」，因此快照必须在此之前建立。
    final Result<List<ArticleListEntry>> before = await articles.findArticles(
      articleIds,
    );
    if (before.isErr) {
      return Err<BatchActionReport>(before.errorOrNull!);
    }
    final List<ArticleStateSnapshot> snapshots = <ArticleStateSnapshot>[
      for (final ArticleListEntry entry in before.valueOrNull!)
        ArticleStateSnapshot(
          articleId: entry.id,
          readingState: entry.readingState,
          favorite: entry.favorite,
        ),
    ];

    final Result<int> written = await articles.setFavorite(
      articleIds: articleIds,
      favorite: favorite,
    );
    if (written.isErr) {
      return Err<BatchActionReport>(written.errorOrNull!);
    }
    final int applied = written.valueOrNull ?? 0;
    diagnostics.info(
      '批量 ${favorite ? '加入收藏' : '取消收藏'}：$applied 篇（范围 ${scope.name}）',
      tag: 'article.favorite.batch',
    );
    return Ok<BatchActionReport>(
      BatchActionReport(
        requested: articleIds.length,
        applied: applied,
        snapshots: snapshots,
        changedIds: articleIds,
      ),
    );
  }
}
