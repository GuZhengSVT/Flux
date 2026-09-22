// 每日新闻任务的 SQLite 实现（T037；端口在 core/domain/news_run.dart）。
//
// 四条实现纪律：
//   * **追加而不覆盖**：每次保存插入新行，版本号由用例层给出（唯一约束是并发两次生成的
//     保险）；
//   * **当前版本的迁移在一个事务里完成**：先把同日期同时区其它行的 is_current 清掉、
//     再插入新版。分成两次会留下「没有任何行是当前版本」的窗口，而界面在那个窗口里会
//     显示「今天还没有新闻」——用户以为自己丢了当天的总结；
//   * **失败版本不动 is_current**：失败/取消/中断的追加不会改任何既有行（架构 4.4
//     「保留上一次成功总结」）；数据库的 CHECK 也会拒绝把失败行标成当前版本；
//   * **JSON 解析失败按「快照损坏」处理**：findById/loadVersions 跳过该行并记录一条
//     结构性诊断（只记 id/日期/失败类别），而不是让整个历史列表打不开（与 T030 的
//     ai_task_store 同一做法）。
library;

import 'dart:convert';

import 'package:drift/drift.dart';

import 'package:flux/core/core.dart';

import 'database.dart';
import 'tables/news_run_tables.dart';

/// 新闻任务版本的 drift 实现。
final class DriftNewsRunStore implements NewsRunStore {
  /// 绑定一个已打开的数据库。
  const DriftNewsRunStore(this._db, {this.diagnostics});

  final AppDatabase _db;

  /// 诊断端口（跳过损坏行时留痕；可空，理由同 T030 的同类实现）。
  final DiagnosticSink? diagnostics;

  @override
  Future<Result<NewsRunRecord>> append(NewsRunRecord record) async {
    try {
      await _db.transaction(() async {
        if (record.isCurrent) {
          await (_db.update(_db.newsRuns)..where(
                (NewsRuns t) =>
                    t.localDate.equals(record.localDate) &
                    t.timeZone.equals(record.timeZone) &
                    t.isCurrent.equals(true),
              ))
              .write(const NewsRunsCompanion(isCurrent: Value<bool>(false)));
        }
        await _db.into(_db.newsRuns).insert(_toCompanion(record));
      });
      final List<NewsRun> rows =
          await (_db.select(_db.newsRuns)..where(
                (NewsRuns t) =>
                    t.localDate.equals(record.localDate) &
                    t.timeZone.equals(record.timeZone) &
                    t.version.equals(record.version),
              ))
              .get();
      final NewsRunRecord? saved = rows.isEmpty ? null : _toDomain(rows.single);
      if (saved == null) {
        return Err<NewsRunRecord>(
          StorageError(operation: 'newsRun.append', detail: '写入后读取失败'),
        );
      }
      return Ok<NewsRunRecord>(saved);
    } on Exception catch (error, stackTrace) {
      return Err<NewsRunRecord>(_storage('newsRun.append', error, stackTrace));
    }
  }

  @override
  Future<Result<List<NewsRunRecord>>> loadVersions({
    required String localDate,
    required String timeZone,
  }) async {
    try {
      final List<NewsRun> rows =
          await (_db.select(_db.newsRuns)
                ..where(
                  (NewsRuns t) =>
                      t.localDate.equals(localDate) &
                      t.timeZone.equals(timeZone),
                )
                ..orderBy(<OrderClauseGenerator<NewsRuns>>[
                  (NewsRuns t) => OrderingTerm.desc(t.version),
                ]))
              .get();
      return Ok<List<NewsRunRecord>>(_decodeAll(rows));
    } on Exception catch (error, stackTrace) {
      return Err<List<NewsRunRecord>>(
        _storage('newsRun.loadVersions', error, stackTrace),
      );
    }
  }

  @override
  Future<Result<NewsRunRecord?>> loadCurrent({
    required String localDate,
    required String timeZone,
  }) async {
    try {
      final NewsRun? row =
          await (_db.select(_db.newsRuns)
                ..where(
                  (NewsRuns t) =>
                      t.localDate.equals(localDate) &
                      t.timeZone.equals(timeZone) &
                      t.isCurrent.equals(true),
                )
                ..limit(1))
              .getSingleOrNull();
      if (row == null) {
        return const Ok<NewsRunRecord?>(null);
      }
      final NewsRunRecord? record = _toDomain(row);
      if (record == null) {
        _logSkipped(row);
      }
      return Ok<NewsRunRecord?>(record);
    } on Exception catch (error, stackTrace) {
      return Err<NewsRunRecord?>(
        _storage('newsRun.loadCurrent', error, stackTrace),
      );
    }
  }

  @override
  Future<Result<void>> setCurrentVersion({
    required String localDate,
    required String timeZone,
    required int version,
  }) async {
    try {
      final NewsRun? target =
          await (_db.select(_db.newsRuns)
                ..where(
                  (NewsRuns t) =>
                      t.localDate.equals(localDate) &
                      t.timeZone.equals(timeZone) &
                      t.version.equals(version),
                )
                ..limit(1))
              .getSingleOrNull();
      if (target == null) {
        return Err<void>(
          StorageError(
            operation: 'newsRun.setCurrentVersion',
            detail: '目标版本不存在',
            isMissing: true,
          ),
        );
      }
      // 非成功版本不允许成为当前版本：与 DDL 的 CHECK 同一个口径，但在这里先拒绝可以
      // 给出一条**说得清楚**的错误（而不是一句约束冲突），同时避免事务被回滚。
      final TaskStatus status = target.taskStatus;
      if (status != TaskStatus.succeeded && status != TaskStatus.partial) {
        return Err<void>(
          ValidationError(
            field: 'newsRun.version',
            reason: '只有成功或部分成功的版本可以设为当前版本（状态 ${status.name}）',
          ),
        );
      }
      await _db.transaction(() async {
        await (_db.update(_db.newsRuns)..where(
              (NewsRuns t) =>
                  t.localDate.equals(localDate) &
                  t.timeZone.equals(timeZone) &
                  t.isCurrent.equals(true),
            ))
            .write(const NewsRunsCompanion(isCurrent: Value<bool>(false)));
        await (_db.update(_db.newsRuns)..where(
              (NewsRuns t) =>
                  t.localDate.equals(localDate) &
                  t.timeZone.equals(timeZone) &
                  t.version.equals(version),
            ))
            .write(const NewsRunsCompanion(isCurrent: Value<bool>(true)));
      });
      return okUnit();
    } on Exception catch (error, stackTrace) {
      return Err<void>(
        _storage('newsRun.setCurrentVersion', error, stackTrace),
      );
    }
  }

  @override
  Future<Result<List<String>>> listDates() async {
    try {
      final List<NewsRun> rows = await _db.select(_db.newsRuns).get();
      final Set<String> dates = <String>{
        for (final NewsRun row in rows) row.localDate,
      };
      final List<String> sorted = dates.toList()
        ..sort((String a, String b) => b.compareTo(a));
      return Ok<List<String>>(List<String>.unmodifiable(sorted));
    } on Exception catch (error, stackTrace) {
      return Err<List<String>>(
        _storage('newsRun.listDates', error, stackTrace),
      );
    }
  }

  @override
  Future<Result<List<NewsRunDateRef>>> listDateRefs() async {
    try {
      final List<NewsRun> rows = await _db.select(_db.newsRuns).get();
      final Map<String, NewsRunDateRef> seen = <String, NewsRunDateRef>{};
      for (final NewsRun row in rows) {
        seen['${row.localDate}\u0000${row.timeZone}'] = NewsRunDateRef(
          localDate: row.localDate,
          timeZone: row.timeZone,
        );
      }
      final List<NewsRunDateRef> refs = seen.values.toList()
        ..sort(
          (NewsRunDateRef a, NewsRunDateRef b) =>
              b.localDate.compareTo(a.localDate),
        );
      return Ok<List<NewsRunDateRef>>(List<NewsRunDateRef>.unmodifiable(refs));
    } on Exception catch (error, stackTrace) {
      return Err<List<NewsRunDateRef>>(
        _storage('newsRun.listDateRefs', error, stackTrace),
      );
    }
  }

  List<NewsRunRecord> _decodeAll(List<NewsRun> rows) {
    final List<NewsRunRecord> out = <NewsRunRecord>[];
    for (final NewsRun row in rows) {
      final NewsRunRecord? record = _toDomain(row);
      if (record == null) {
        _logSkipped(row);
        continue;
      }
      out.add(record);
    }
    return List<NewsRunRecord>.unmodifiable(out);
  }

  void _logSkipped(NewsRun row) {
    // 只记结构事实（日期、版本、状态），不记快照正文与模型输出。
    diagnostics?.warning(
      '新闻任务记录无法解析 date=${row.localDate} tz=${row.timeZone} '
      'v=${row.version} status=${row.taskStatus.name}',
      tag: 'news.store',
    );
  }

  static NewsRunRecord? _toDomain(NewsRun row) {
    final Map<Object?, Object?>? snapshot = _map(row.inputSnapshot);
    if (snapshot == null) {
      return null;
    }
    final NewsInputSnapshot? parsed = NewsInputSnapshot.fromJson(snapshot);
    if (parsed == null) {
      return null;
    }
    final List<NewsSiteFetchResult> siteResults = <NewsSiteFetchResult>[];
    for (final Object? item in _list(row.siteResults)) {
      if (item is! Map<Object?, Object?>) {
        continue;
      }
      final NewsSiteFetchResult? site = NewsSiteFetchResult.fromJson(item);
      if (site != null) {
        siteResults.add(site);
      }
    }
    final List<NewsMaterial> materials = <NewsMaterial>[];
    for (final Object? item in _list(row.materials)) {
      if (item is! Map<Object?, Object?>) {
        continue;
      }
      final NewsMaterial? material = NewsMaterial.fromJson(item);
      if (material != null) {
        materials.add(material);
      }
    }
    final List<NewsDraftItem> items = <NewsDraftItem>[];
    for (final Object? item in _list(row.items)) {
      if (item is! Map<Object?, Object?>) {
        continue;
      }
      final NewsDraftItem? parsedItem = NewsDraftItem.fromJson(item);
      if (parsedItem != null) {
        items.add(parsedItem);
      }
    }
    return NewsRunRecord(
      id: row.id,
      localDate: row.localDate,
      timeZone: row.timeZone,
      version: row.version,
      status: row.taskStatus,
      snapshot: parsed,
      siteResults: siteResults,
      materials: materials,
      items: items,
      createdAt: row.createdAt,
      isCurrent: row.isCurrent,
      draftText: row.draftText,
      providerAlias: row.providerAlias,
      modelId: row.modelId,
      consumedTokens: row.consumedTokens,
      attemptCount: row.attemptCount,
      errorKind: row.errorKind,
      verificationMethod: row.verificationMethod,
      stage: _stage(row.stage),
    );
  }

  static NewsRunsCompanion _toCompanion(
    NewsRunRecord record,
  ) => NewsRunsCompanion.insert(
    localDate: record.localDate,
    timeZone: record.timeZone,
    version: record.version,
    taskStatus: record.status,
    inputSnapshot: jsonEncode(record.snapshot.toJson()),
    snapshotHash: record.snapshot.hash,
    siteResults: jsonEncode(<Object?>[
      for (final NewsSiteFetchResult site in record.siteResults) site.toJson(),
    ]),
    materials: jsonEncode(<Object?>[
      for (final NewsMaterial material in record.materials) material.toJson(),
    ]),
    items: jsonEncode(<Object?>[
      for (final NewsDraftItem item in record.items) item.toJson(),
    ]),
    draftText: Value<String?>(record.draftText),
    providerAlias: Value<String?>(record.providerAlias),
    modelId: Value<String?>(record.modelId),
    consumedTokens: Value<int>(record.consumedTokens),
    attemptCount: Value<int>(record.attemptCount),
    errorKind: Value<String?>(record.errorKind),
    verificationMethod: Value<String?>(record.verificationMethod),
    stage: Value<String?>(record.stage?.name),
    isCurrent: Value<bool>(record.isCurrent),
    createdAt: record.createdAt,
  );

  static NewsRunStage? _stage(String? raw) {
    for (final NewsRunStage value in NewsRunStage.values) {
      if (value.name == raw) {
        return value;
      }
    }
    return null;
  }

  static Map<Object?, Object?>? _map(String raw) {
    try {
      final Object? decoded = jsonDecode(raw);
      return decoded is Map<Object?, Object?> ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  static List<Object?> _list(String raw) {
    try {
      final Object? decoded = jsonDecode(raw);
      return decoded is List<Object?> ? decoded : const <Object?>[];
    } on FormatException {
      return const <Object?>[];
    }
  }

  static StorageError _storage(
    String operation,
    Object error,
    StackTrace stackTrace,
  ) => StorageError(
    operation: operation,
    detail: error.runtimeType.toString(),
    cause: error,
    stackTrace: stackTrace,
  );
}

/// 选材候选的 drift 实现（T037 的 RSS 选材查询）。
///
/// 三条与产品规则对应的实现选择：
///   * **时间窗口按有效时间判断**（发布时间优先，缺失时用抓取时间）：与列表排序同一口径
///     （架构 4.1），否则「列表里看到今天的文章、总结里没有」会成为一个查不出原因的分歧；
///   * **只取参与新闻的源**（SET-050 的逐源开关）：SQL 里用
///     `COALESCE(feeds.news_enabled, feeds.enabled)`，与 core 的 newsIncludesFeed 同一个
///     判据（三态：null 跟随 enabled）；
///   * **多取一些再截断**：去重会减少条数，只取上限条会让「同源重复稿」把额度吃掉一半。
final class DriftNewsCandidateStore implements NewsCandidateStore {
  /// 绑定一个已打开的数据库。
  const DriftNewsCandidateStore(this._db);

  final AppDatabase _db;

  /// 去重前多取的比例（上限的 2 倍，至少 20 条）。
  static const int _overFetchFloor = 20;

  @override
  Future<Result<List<NewsCandidateArticle>>> loadCandidates({
    required DateTime startUtc,
    required DateTime endUtc,
    required int limit,
  }) async {
    try {
      final int cap = limit < 0 ? 0 : limit;
      final int fetch = cap * 2 < _overFetchFloor ? _overFetchFloor : cap * 2;
      final List<QueryRow> rows = await _db
          .customSelect(
            '''
SELECT a.id AS article_id, a.feed_id AS feed_id, a.title AS title,
       a.summary AS summary, a.body AS body, a.guid AS guid,
       a.normalized_link AS normalized_link, a.source_url AS source_url,
       a.published_at AS published_at, a.fetched_at AS fetched_at,
       a.favorite AS favorite, f.name AS feed_name
FROM articles AS a
JOIN feeds AS f ON f.id = a.feed_id
WHERE COALESCE(a.published_at, a.fetched_at) >= ?
  AND COALESCE(a.published_at, a.fetched_at) < ?
  AND COALESCE(f.news_enabled, f.enabled) = 1
ORDER BY COALESCE(a.published_at, a.fetched_at) DESC, a.id DESC
LIMIT ?
''',
            variables: <Variable<Object>>[
              Variable<DateTime>(startUtc),
              Variable<DateTime>(endUtc),
              Variable<int>(fetch),
            ],
          )
          .get();
      final List<NewsCandidateArticle> out = <NewsCandidateArticle>[];
      for (final QueryRow row in rows) {
        final int? articleId = row.readNullable<int>('article_id');
        final int? feedId = row.readNullable<int>('feed_id');
        final String? title = row.readNullable<String>('title');
        if (articleId == null || feedId == null || title == null) {
          continue;
        }
        out.add(
          NewsCandidateArticle(
            articleId: articleId,
            feedId: feedId,
            feedName: row.readNullable<String>('feed_name') ?? '',
            title: title,
            summary: row.readNullable<String>('summary'),
            body: row.readNullable<String>('body'),
            publishedAt: row.readNullable<DateTime>('published_at')?.toUtc(),
            fetchedAt:
                row.readNullable<DateTime>('fetched_at')?.toUtc() ?? startUtc,
            sourceUrl: row.readNullable<String>('source_url'),
            guid: row.readNullable<String>('guid'),
            normalizedLink: row.readNullable<String>('normalized_link'),
            favorite: (row.readNullable<int>('favorite') ?? 0) != 0,
          ),
        );
      }
      return Ok<List<NewsCandidateArticle>>(
        List<NewsCandidateArticle>.unmodifiable(out),
      );
    } on Exception catch (error, stackTrace) {
      return Err<List<NewsCandidateArticle>>(
        StorageError(
          operation: 'news.loadCandidates',
          detail: error.runtimeType.toString(),
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }
}

/// 数据库不可用时的新闻任务端口（T037 的降级启动路径）。
///
/// 读返回空（本次运行确实没有任何可读记录：这是真实答案，界面显示「还没有生成过」），
/// 写明确失败（不假装保存成功）。与 T036 的降级实现同一口径。
final class DegradedNewsRunStore implements NewsRunStore {
  /// 构造降级实现。
  const DegradedNewsRunStore();

  @override
  Future<Result<NewsRunRecord>> append(NewsRunRecord record) async =>
      Err<NewsRunRecord>(
        StorageError(operation: 'newsRun.append', detail: '本次运行数据库不可用'),
      );

  @override
  Future<Result<List<NewsRunRecord>>> loadVersions({
    required String localDate,
    required String timeZone,
  }) async => const Ok<List<NewsRunRecord>>(<NewsRunRecord>[]);

  @override
  Future<Result<NewsRunRecord?>> loadCurrent({
    required String localDate,
    required String timeZone,
  }) async => const Ok<NewsRunRecord?>(null);

  @override
  Future<Result<void>> setCurrentVersion({
    required String localDate,
    required String timeZone,
    required int version,
  }) async => Err<void>(
    StorageError(operation: 'newsRun.setCurrentVersion', detail: '本次运行数据库不可用'),
  );

  @override
  Future<Result<List<String>>> listDates() async =>
      const Ok<List<String>>(<String>[]);

  @override
  Future<Result<List<NewsRunDateRef>>> listDateRefs() async =>
      const Ok<List<NewsRunDateRef>>(<NewsRunDateRef>[]);
}

/// 数据库不可用时的选材端口（读返回空 = 本次运行确实没有可读文章）。
final class DegradedNewsCandidateStore implements NewsCandidateStore {
  /// 构造降级实现。
  const DegradedNewsCandidateStore();

  @override
  Future<Result<List<NewsCandidateArticle>>> loadCandidates({
    required DateTime startUtc,
    required DateTime endUtc,
    required int limit,
  }) async => const Ok<List<NewsCandidateArticle>>(<NewsCandidateArticle>[]);
}
