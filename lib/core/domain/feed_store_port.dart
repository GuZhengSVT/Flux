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

  /// 记录一次**未联网就跳过**的调度结果（T016：离线 / 计费网络守卫）。
  ///
  /// 与 [recordRefreshOutcome] 的唯一区别是：**不推进** lastCheckedAt。
  ///
  /// 为什么要单独一个方法而不是加一个 bool 参数：
  ///   「推进检查时间」在 [recordRefreshOutcome] 里是一条有理由的规则（一次真实
  ///   请求发生过，无论成败都算检查过），而这里的情况恰好相反——一个字节都没发出去。
  ///   用参数切换含义会让两个语义共用一个名字，调用点看起来一模一样却行为不同；
  ///   分成两个方法后，「这次没联网」在类型上就是另一件事。
  ///
  /// 为什么不干脆什么都不写：结果类别与错误类别仍要如实记录，否则界面上没有任何
  /// 痕迹表明调度跑过并因网络守卫停下，用户会以为刷新坏了。
  Future<Result<void>> recordDeferredOutcome({
    required int feedId,
    required FeedRefreshOutcome outcome,
    String? errorKind,
  });
}
