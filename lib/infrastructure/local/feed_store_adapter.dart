// 刷新写入适配器（T013）。
//
// 职责：把 core 定义的两个端口（FeedArticleStore、DiagnosticSink）接到本工程的
// 真实实现上——article_store.dart 的 drift 事务与 diagnostics.dart 的脱敏日志。
//
// 为什么需要适配器而不是让 features 直接用：
//   features 不得 import infrastructure（架构 2.2，测试会拦截）。适配器住在
//   infrastructure，由组合根（lib/app）注入，features 只看到 core 的接口。
library;

import 'package:drift/drift.dart';

import 'package:flux/core/core.dart';

import 'article_store.dart';
import 'database.dart';
import 'diagnostics.dart';
import 'tables/feed_tables.dart';

/// 把 drift 的 ArticleStore 与 feeds 表接到 [FeedArticleStore] 端口。
final class DriftFeedArticleStore implements FeedArticleStore {
  /// 绑定一个已打开的数据库。
  const DriftFeedArticleStore(this._db);

  final AppDatabase _db;

  @override
  Future<Result<ArticleImportOutcome>> upsertArticles(
    List<ArticleImport> imports,
  ) => _db.upsertArticles(imports);

  @override
  Future<Result<void>> recordRefreshOutcome({
    required int feedId,
    required FeedRefreshOutcome outcome,
    required DateTime checkedAt,
    String? errorKind,
    String? etag,
    String? lastModified,
  }) async {
    try {
      await (_db.update(
        _db.feeds,
      )..where((Feeds t) => t.id.equals(feedId))).write(
        FeedsCompanion(
          lastCheckedAt: Value<DateTime?>(checkedAt.toUtc()),
          lastRefreshResult: Value<String?>(outcome.name),
          lastRefreshErrorKind: Value<String?>(errorKind),
          // null 表示「本次响应没有提供这个头」，此时**不覆盖**已有缓存值：
          // 把 null 写进去会让下次请求失去条件，退化成每次全量下载。
          httpEtag: etag == null
              ? const Value<String?>.absent()
              : Value<String?>(etag),
          httpLastModified: lastModified == null
              ? const Value<String?>.absent()
              : Value<String?>(lastModified),
          updatedAt: Value<DateTime>(DateTime.now().toUtc()),
        ),
      );
      return const Ok<void>(null);
    } on AppError catch (error) {
      return Err<void>(error);
    } on Exception catch (error, stackTrace) {
      return Err<void>(
        StorageError(
          operation: 'recordRefreshOutcome',
          detail: error.runtimeType.toString(),
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  @override
  Future<Result<void>> recordDeferredOutcome({
    required int feedId,
    required FeedRefreshOutcome outcome,
    String? errorKind,
  }) async {
    try {
      // 有意**不写** lastCheckedAt：这次没有发出任何请求（离线/计费网络守卫），
      // 推进「上次检查」会让用户在恢复网络后白等一个完整间隔。
      // updatedAt 也不动：这一行并没有被用户操作或新内容改变。
      await (_db.update(
        _db.feeds,
      )..where((Feeds t) => t.id.equals(feedId))).write(
        FeedsCompanion(
          lastRefreshResult: Value<String?>(outcome.name),
          lastRefreshErrorKind: Value<String?>(errorKind),
        ),
      );
      return const Ok<void>(null);
    } on AppError catch (error) {
      return Err<void>(error);
    } on Exception catch (error, stackTrace) {
      return Err<void>(
        StorageError(
          operation: 'recordDeferredOutcome',
          detail: error.runtimeType.toString(),
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }
}

/// 把 T010 的 DiagnosticLog 接到 core 的 [DiagnosticSink] 端口。
final class DiagnosticLogSink implements DiagnosticSink {
  /// 绑定一个诊断日志。
  const DiagnosticLogSink(this._log);

  final DiagnosticLog _log;

  @override
  void record(DiagnosticSeverity severity, String message, {String? tag}) {
    // 映射到日志自己的级别枚举：两套枚举的语义一一对应，这里只是类型适配。
    // 日志实现负责脱敏，因此上层不必（也不该）自己处理秘密。
    _log.record(_levelOf(severity), message, tag: tag);
  }

  @override
  void error(String message, {String? tag}) => _log.error(message, tag: tag);

  @override
  void warning(String message, {String? tag}) =>
      _log.warning(message, tag: tag);

  @override
  void info(String message, {String? tag}) => _log.info(message, tag: tag);

  static DiagnosticLevel _levelOf(DiagnosticSeverity severity) =>
      switch (severity) {
        DiagnosticSeverity.error => DiagnosticLevel.error,
        DiagnosticSeverity.warning => DiagnosticLevel.warning,
        DiagnosticSeverity.info => DiagnosticLevel.info,
      };
}

/// 数据库不可用时的文章写入端口（T014 的降级启动路径）。
///
/// 两个方法都返回类型化存储错误：**没有内容可以假装写成功**。若这里返回 Ok，
/// 「添加订阅」在降级模式下会创建一个内存里的订阅并报告「已导入 N 篇」，
/// 重启后全都不见——这正是架构第 8 节禁止的「用假象代替状态」。
final class DegradedFeedArticleStore implements FeedArticleStore {
  /// 构造降级实现。
  const DegradedFeedArticleStore();

  @override
  Future<Result<ArticleImportOutcome>> upsertArticles(
    List<ArticleImport> imports,
  ) async => Err<ArticleImportOutcome>(
    StorageError(operation: 'upsertArticles', detail: '本次运行数据库不可用，文章不会保存'),
  );

  @override
  Future<Result<void>> recordRefreshOutcome({
    required int feedId,
    required FeedRefreshOutcome outcome,
    required DateTime checkedAt,
    String? errorKind,
    String? etag,
    String? lastModified,
  }) async => Err<void>(
    StorageError(
      operation: 'recordRefreshOutcome',
      detail: '本次运行数据库不可用，抓取结果不会记录',
    ),
  );

  @override
  Future<Result<void>> recordDeferredOutcome({
    required int feedId,
    required FeedRefreshOutcome outcome,
    String? errorKind,
  }) async => Err<void>(
    StorageError(
      operation: 'recordDeferredOutcome',
      detail: '本次运行数据库不可用，调度结果不会记录',
    ),
  );
}
