// 文章写入端口（T013）。
//
// 为什么需要这一层：T013 的刷新流程在 features/feeds，而真正写库的实现是
// infrastructure/local 的 ArticleStore（drift 扩展方法）。features 不得 import
// infrastructure，因此这里定义 features 依赖的**最小写入接口**，由基础设施适配。
//
// 接口故意保持很窄（只有「批量幂等写入」与「按内容更新抓取诊断」），因为上层不该拿到
// 整张表的读写权：刷新流程只需要把解析结果交出去，以及记录「本次检查的结果」。
library;

import '../result.dart';

import 'article_import.dart';
import 'feed_refresh.dart';

/// 文章与订阅的写入端口。
abstract interface class FeedArticleStore {
  /// 幂等批量写入文章；返回新增/更新/未变的计数。
  ///
  /// 实现必须保证（这些是架构 4.1 的硬要求）：
  ///   - 整批在**单个事务**内完成，任一条失败则整批回滚；
  ///   - 身份按 GUID → 规范化链接 → 指纹，**仅在同一 feed 内**匹配；
  ///   - 正文只在正文哈希变化时替换；
  ///   - readingState 与 favorite 永不被导入覆盖。
  Future<Result<ArticleImportOutcome>> upsertArticles(
    List<ArticleImport> imports,
  );

  /// 记录一次抓取的结果（更新 lastChecked / 结果类别 / 错误类别与条件请求缓存）。
  ///
  /// [etag] / [lastModified] 为 null 时**不覆盖**已有值：很多源只在首次或内容变化时给
  /// ETag，把 null 写成 null 会让下次请求失去条件，退化成每次都全量下载。
  Future<Result<void>> recordRefreshOutcome({
    required int feedId,
    required FeedRefreshOutcome outcome,
    required DateTime checkedAt,
    String? errorKind,
    String? etag,
    String? lastModified,
  });
}
