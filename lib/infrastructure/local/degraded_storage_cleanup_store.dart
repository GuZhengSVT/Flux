// 数据库不可用时的存储清理实现（T047）。
//
// 与其余降级实现同一口径（见 degraded_ai_task_store.dart 的说明）：
//   * **读**返回一个诚实的空结果：本次运行确实没有可读的数据库行，因此分类占用里数据库相关的
//     几类是 0——这是真实的答案，不是「读取失败」；
//   * **写/删**一律返回类型化失败：报成功会让用户以为空间释放了（或以为文章被彻底删除了），
//     而磁盘上什么都没变。这是最危险的一种假成功——用户会据此认为敏感内容已经删除。
library;

import 'package:flux/core/core.dart';
import 'package:flux/features/settings/application/cleanup_ports.dart';

/// 降级实现：读空、删失败。
final class DegradedStorageCleanupStore implements StorageCleanupStore {
  /// 构造降级实现。
  const DegradedStorageCleanupStore();

  @override
  Future<Result<StorageUsageReport>> measureDatabase({
    required DateTime measuredAt,
  }) async => Ok<StorageUsageReport>(
    StorageUsageReport(
      measuredAt: measuredAt,
      // 四类都给 0 并**逐类列出**（而不是返回空列表）：空列表会让界面显示「没有任何分类」，
      // 而真相是「本次运行读不到库」——用户能从「四类都是 0」看出这一点，从「什么都没有」看不出来。
      categories: const <StorageCategoryUsage>[
        StorageCategoryUsage(
          category: StorageCategory.articleBody,
          byteCount: 0,
          itemCount: 0,
        ),
        StorageCategoryUsage(
          category: StorageCategory.newsSummary,
          byteCount: 0,
          itemCount: 0,
        ),
        StorageCategoryUsage(
          category: StorageCategory.otherCache,
          byteCount: 0,
          itemCount: 0,
        ),
        StorageCategoryUsage(
          category: StorageCategory.database,
          byteCount: 0,
          itemCount: 0,
        ),
      ],
    ),
  );

  @override
  Future<Result<({CleanupImpact impact, List<int> articleIds})>>
  planArticleBodyRelease({
    required DateTime cutoffUtc,
    required bool includeFavorite,
    required bool includeLater,
  }) async => const Ok<({CleanupImpact impact, List<int> articleIds})>((
    impact: CleanupImpact(),
    articleIds: <int>[],
  ));

  @override
  Future<Result<({int articles, int bytes})>> releaseArticleBodies({
    required List<int> articleIds,
  }) async => const Ok<({int articles, int bytes})>((articles: 0, bytes: 0));

  @override
  Future<Result<({CleanupImpact impact, List<int> runIds})>>
  planSummaryCleanup({required DateTime cutoffUtc}) async =>
      const Ok<({CleanupImpact impact, List<int> runIds})>((
        impact: CleanupImpact(),
        runIds: <int>[],
      ));

  @override
  Future<Result<({int runs, int bytes})>> deleteSummaryRuns({
    required List<int> runIds,
  }) async => Err<({int runs, int bytes})>(
    StorageError(operation: 'cleanup.deleteSummary', detail: '本次运行数据库不可用'),
  );

  @override
  Future<Result<({int entries, int bytes})>> aiCacheUsage() async =>
      const Ok<({int entries, int bytes})>((entries: 0, bytes: 0));

  @override
  Future<Result<({int entries, int bytes})>> clearAiResultCache() async =>
      Err<({int entries, int bytes})>(
        StorageError(operation: 'cleanup.clearAiCache', detail: '本次运行数据库不可用'),
      );

  @override
  Future<Result<({int entries, int bytes})>> failedTaskDraftUsage() async =>
      const Ok<({int entries, int bytes})>((entries: 0, bytes: 0));

  @override
  Future<Result<({int entries, int bytes})>> clearFailedTaskDrafts() async =>
      Err<({int entries, int bytes})>(
        StorageError(
          operation: 'cleanup.clearFailedDrafts',
          detail: '本次运行数据库不可用',
        ),
      );

  @override
  Future<Result<ArticlePurgeImpact>> articlePurgeImpact(int articleId) async =>
      Err<ArticlePurgeImpact>(
        StorageError(operation: 'cleanup.purgeImpact', detail: '本次运行数据库不可用'),
      );

  @override
  Future<Result<ArticlePurgeImpact>> purgeArticle(int articleId) async =>
      Err<ArticlePurgeImpact>(
        StorageError(operation: 'cleanup.purge', detail: '本次运行数据库不可用'),
      );
}
