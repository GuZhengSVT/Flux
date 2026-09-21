// 数据库不可用时的提取端口（T024 的降级启动路径）。
//
// 与 DegradedArticleCatalogStore 同一口径：**读返回空 + 写返回类型化失败**。
//
// 为什么读返回空而不是失败：详情页在降级启动时仍要能打开（原文照常显示），只是
// 「获取原站全文」会明确失败——不返回假的成功，理由同其他降级端口。
library;

import 'package:flux/core/core.dart';

/// 降级实现。
final class DegradedArticleExtractionStore implements ArticleExtractionStore {
  /// 构造降级实现。
  const DegradedArticleExtractionStore();

  @override
  Future<Result<ExtractedArticleBody?>> readExtraction(int articleId) async =>
      const Ok<ExtractedArticleBody?>(null);

  @override
  Future<Result<void>> saveExtraction({
    required int articleId,
    required ExtractedArticleBody extraction,
  }) async => Err<void>(
    StorageError(operation: 'saveExtraction', detail: '本次运行数据库不可用，提取的正文不会保存'),
  );

  @override
  Future<Result<void>> clearExtraction(int articleId) async => Err<void>(
    StorageError(operation: 'clearExtraction', detail: '本次运行数据库不可用，无法清除提取的正文'),
  );
}
