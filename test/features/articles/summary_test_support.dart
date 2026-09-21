// T034 自动摘要批处理的替身（端口级，全部不联网）。
library;

import 'package:flux/core/core.dart';
import 'package:flux/features/ai/domain/ai_task_record.dart';
import 'package:flux/features/ai/domain/ai_task_store.dart';
import 'package:flux/features/articles/application/auto_summary_batch.dart';

/// 记录写入的文章端口替身。
final class FakeSummaryArticleStore implements ArticleCatalogStore {
  /// 文章 id → 正文。
  final Map<int, String?> bodies = <int, String?>{};

  /// 文章 id → 源摘要（写 AI 摘要**不得**触碰它）。
  final Map<int, String?> sourceSummaries = <int, String?>{};

  /// 本次「缺摘要」候选（由用例显式设置，避免在这里重实现筛选规则）。
  List<int> missing = <int>[];

  /// 已保存的 AI 摘要（按写入顺序）。
  final List<({int articleId, AiSummaryRecord summary})> saved =
      <({int articleId, AiSummaryRecord summary})>[];

  /// 添加一篇文章。
  void add(int id, {String? body, String? sourceSummary}) {
    bodies[id] = body;
    sourceSummaries[id] = sourceSummary;
  }

  /// 读源摘要（断言「没被覆盖」）。
  String? sourceSummaryOf(int id) => sourceSummaries[id];

  @override
  Future<Result<void>> saveAiSummary({
    required int articleId,
    required AiSummaryRecord summary,
  }) async {
    saved.add((articleId: articleId, summary: summary));
    return okUnit();
  }

  @override
  Future<Result<AiSummaryRecord?>> readAiSummary(int articleId) async =>
      const Ok<AiSummaryRecord?>(null);

  @override
  Future<Result<List<int>>> listArticlesMissingSummary({
    required int limit,
    int? feedId,
    int offset = 0,
  }) async =>
      Ok<List<int>>(missing.skip(offset).take(limit).toList(growable: false));

  @override
  Future<Result<String?>> readArticleBody(int articleId) async =>
      Ok<String?>(bodies[articleId]);

  // ---- 以下方法在 T034 的用例里不用；抛错以免被误当成「返回空」而静默通过 ----

  @override
  Future<Result<ArticlePage>> listArticles(ArticleQuery query) async =>
      Err<ArticlePage>(
        StorageError(operation: 'listArticles', detail: 'not used'),
      );

  @override
  Future<Result<int>> countArticles({
    ArticleFilter filter = ArticleFilter.all,
    int? feedId,
  }) async =>
      Err<int>(StorageError(operation: 'countArticles', detail: 'not used'));

  @override
  Future<Result<ArticleListEntry?>> findArticle(int articleId) async =>
      Err<ArticleListEntry?>(
        StorageError(operation: 'findArticle', detail: 'not used'),
      );

  @override
  Future<Result<List<ArticleListEntry>>> findArticles(
    List<int> articleIds,
  ) async => Err<List<ArticleListEntry>>(
    StorageError(operation: 'findArticles', detail: 'not used'),
  );

  @override
  Future<Result<List<int>>> listArticleIds({
    ArticleFilter filter = ArticleFilter.all,
    int? feedId,
  }) async => Err<List<int>>(
    StorageError(operation: 'listArticleIds', detail: 'not used'),
  );

  @override
  Future<Result<int>> setReadingState({
    required List<int> articleIds,
    required ReadingState state,
  }) async =>
      Err<int>(StorageError(operation: 'setReadingState', detail: 'not used'));

  @override
  Future<Result<int>> setFavorite({
    required List<int> articleIds,
    required bool favorite,
  }) async =>
      Err<int>(StorageError(operation: 'setFavorite', detail: 'not used'));

  @override
  Future<Result<int>> markReadIfUnread(int articleId) async =>
      Err<int>(StorageError(operation: 'markReadIfUnread', detail: 'not used'));

  @override
  Future<Result<int>> restoreArticleStates(
    List<ArticleStateSnapshot> snapshots,
  ) async => Err<int>(
    StorageError(operation: 'restoreArticleStates', detail: 'not used'),
  );
}

/// 结果缓存替身：`seed` 之后所有查询都命中（并记下被查的键）。
final class FakeResultCache implements AiResultCache {
  /// 被查询过的键（按顺序）。
  final List<String> queried = <String>[];

  /// 命中时返回的文本；null 表示永不命中。
  String? hitText;

  /// 记下的键（用例用它做「算出来的键是什么」的断言）。
  String get lastKey => queried.isEmpty ? '' : queried.last;

  /// 让所有查询都命中这条记录。
  void seed({
    required String text,
    required String providerAlias,
    required String modelId,
    // 参数保留是为了让调用点在需要时显式说明「键要与批处理一致」，
    // 但本替身按「任意键都命中」工作（更严格的做法是先算键再 seed，
    // 而那会把批处理内部的键算法复制到测试里）。
    String Function()? keyForRequest,
  }) {
    hitText = text;
    _providerAlias = providerAlias;
    _modelId = modelId;
  }

  String _providerAlias = '';
  String _modelId = '';

  @override
  Future<Result<AiResultCacheEntry?>> find(String key) async {
    queried.add(key);
    final String? text = hitText;
    if (text == null) {
      return const Ok<AiResultCacheEntry?>(null);
    }
    return Ok<AiResultCacheEntry?>(
      AiResultCacheEntry(
        key: key,
        text: text,
        providerAlias: _providerAlias,
        modelId: _modelId,
        createdAt: DateTime.utc(2026, 9, 22),
      ),
    );
  }

  @override
  Future<Result<void>> save(AiResultCacheEntry entry) async => okUnit();

  @override
  Future<Result<void>> delete(String key) async => okUnit();

  @override
  Future<Result<void>> clear() async => okUnit();
}

/// 当天计数替身。
///
/// 按**日期键**保存计数（与真实实现同一语义）：跨午夜后新的一天查不到记录就是 0，
/// 因此「跨午夜归零」不需要任何重置逻辑。用一个全局数字会让跨午夜用例看不出区别。
final class FakeDailySummaryCounter implements DailySummaryCounter {
  /// 按日期键保存的计数。
  final Map<String, int> countsByDate = <String, int>{};

  /// 第一次读到某日期时预置的已用数（用例模拟「今天已经用了一些」）。
  int? seedUsed;

  /// 每次写入累加的数量。
  int written = 0;

  /// 读是否失败（验证额度不可确认时 fail-closed）。
  bool failRead = false;

  /// 读过的日期键（按顺序；用于断言跨午夜后的归属）。
  final List<String> readKeys = <String>[];

  /// 设置「今天」的已用数（用例写起来更直白）。
  set used(int value) => seedUsed = value;

  /// 预置生效的日期（第一次读到的那一天）。
  String? seedDate;

  /// 当前已用数（断言用；取最近一次读到的日期）。
  int get usedToday =>
      readKeys.isEmpty ? 0 : (countsByDate[readKeys.last] ?? 0);

  @override
  Future<Result<int>> readUsed(String localDate) async {
    readKeys.add(localDate);
    if (failRead) {
      return Err<int>(StorageError(operation: 'readUsed', detail: 'fixture'));
    }
    // 预置的已用数只作用于**第一次**读到的日期（模拟「今天已经用了一些」），
    // 之后的新日期从 0 开始——否则跨午夜用例会把昨天的额度带到今天。
    final int? seed = seedUsed;
    if (seed != null && seedDate == null) {
      seedDate = localDate;
      countsByDate[localDate] = seed;
    }
    return Ok<int>(countsByDate[localDate] ?? 0);
  }

  @override
  Future<Result<void>> addUsed(String localDate, int count) async {
    countsByDate[localDate] = (countsByDate[localDate] ?? 0) + count;
    written += count;
    return okUnit();
  }
}
