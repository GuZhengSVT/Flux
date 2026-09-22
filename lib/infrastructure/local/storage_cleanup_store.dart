// 存储清理的 SQLite 实现（T047；端口在 features/settings/application/cleanup_ports.dart）。
//
// 五条实现纪律，逐条对应一条产品规则：
//
//   1) **只释放正文时不动身份与状态**。[releaseArticleBodies] 的 UPDATE 只写
//      `body` / `body_hash` / `extracted_*` 几个**正文列**，不碰 reading_state、favorite、
//      guid、normalized_link、fallback_fingerprint、sync_key、feed_id、时间戳。因此下一次
//      刷新仍按同一套身份规则匹配到**这一行**，而不是为同一篇文章插一行新的未读——架构 5.3
//      的「防止刷新把文章复活成未读」是这条语句的**形状**保证的，不是靠调用方记得。
//   2) **正文完整性改回 summaryOnly**：正文被释放后若仍标着 `sourceBody`，界面会把它显示成
//      「原文已清理」（T039 的判据正是「本应存在正文而正文为空」）——那是**真实**的描述。但若
//      继续标 `extracted`（主动提取过的），同一篇也可能不再符合该判据。因此释放后统一改成
//      `summaryOnly`（「源只给了摘要」），这是它与当前数据一致的状态：库里现在确实只有标题与
//      摘要。用 `unknown` 会让它既不显示「已清理」也不显示「只有摘要」，信息更少。
//   3) **媒体缓存按地址哈希回收**：文章彻底删除时，它的卡片图缓存文件（SHA-256(url)+.img/.meta）
//      一并删除，否则「彻底删除」会留下一份用户以为已经删掉的图片副本。
//   4) **失败任务草稿与成功产出分开**：清草稿只删终态为 failed/cancelled/interrupted 的任务行；
//      succeeded/partial（付费结果）与 queued/running（可能还在跑）一行都不动。
//   5) **一切都在事务里**：彻底删除涉及多张表，中途失败留下「会话删了、文章还在」这种半成品
//      状态，而用户已经看到「已删除」。
library;

import 'package:drift/drift.dart';

import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:flux/core/core.dart';
import 'package:flux/features/settings/application/cleanup_ports.dart';

import 'ai_task_store.dart';
import 'database.dart';
import 'tables/article_tables.dart';
import 'tables/news_run_tables.dart';
import 'tables/reading_tables.dart';
import 'tables/summary_tables.dart';
import 'tables/translation_tables.dart';

/// 失败/取消/中断三类终态（「失败任务草稿」的判据）。
///
/// 显式列出而不是用「非 succeeded 的都算」：将来新增一个终态时，那种写法会把新终态误判成
/// 草稿并删掉（与 T030 的 markActiveAsInterrupted 同一个理由）。
const List<String> _draftTaskStatuses = <String>[
  'failed',
  'cancelled',
  'interrupted',
];

/// 存储清理的 drift 实现。
final class DriftStorageCleanupStore implements StorageCleanupStore {
  /// 绑定一个已打开的数据库。
  ///
  /// [databaseFiles] 是数据库在磁盘上的文件（主库 + `-wal` + `-shm`），用于「设置/状态数据库」
  /// 这一类的占用显示。为空时该类报 0——统计是**展示**用的，拿不到磁盘大小不该让整页失败。
  const DriftStorageCleanupStore(
    this._db, {
    this.databaseFiles = const <String>[],
    this.mediaDirectoryPath,
    this.clock = const SystemClock(),
  });

  final AppDatabase _db;

  /// 数据库在磁盘上的文件路径（主库 + WAL + SHM）。
  final List<String> databaseFiles;

  /// 媒体缓存目录路径（彻底删除时回收该文章的图片缓存）；未装配时为 null。
  final String? mediaDirectoryPath;

  /// 时钟（任务草稿判定的时间来源；不参与任何清理判定）。
  final Clock clock;

  // -------------------------------------------------------------------------
  // 分类占用
  // -------------------------------------------------------------------------

  @override
  Future<Result<StorageUsageReport>> measureDatabase({
    required DateTime measuredAt,
  }) async {
    try {
      // 正文占用：**只统计非空正文**。空字符串与 NULL 都不算——把「本来就没有正文」的行
      // 计进去，会让「文章正文」这一类的字节数里混进一堆 0 字节的行，用户无法解释它为什么
      // 有 3000 篇却只占 12 MiB。
      final QueryRow bodies = await _db
          .customSelect(
            'SELECT COUNT(*) AS c, '
            'COALESCE(SUM(COALESCE(length(CAST(body AS BLOB)), 0) + '
            'COALESCE(length(CAST(extracted_body AS BLOB)), 0)), 0) AS b '
            'FROM articles '
            "WHERE (body IS NOT NULL AND body <> '') "
            "   OR (extracted_body IS NOT NULL AND extracted_body <> '')",
          )
          .getSingle();

      // 新闻总结占用：一张宽表，几列大文本都算进去（它们都是这次生成的组成部分，只报一列
      // 会让这一类偏小得没有参考价值）。
      final QueryRow summaries = await _db
          .customSelect(
            'SELECT COUNT(*) AS c, '
            'COALESCE(SUM(COALESCE(length(CAST(input_snapshot AS BLOB)), 0) + '
            'COALESCE(length(CAST(site_results AS BLOB)), 0) + '
            'COALESCE(length(CAST(materials AS BLOB)), 0) + '
            'COALESCE(length(CAST(items AS BLOB)), 0) + '
            'COALESCE(length(CAST(draft_text AS BLOB)), 0)), 0) AS b '
            'FROM news_runs',
          )
          .getSingle();

      final Result<({int entries, int bytes})> aiCache = await _aiCache.usage();
      final Result<({int entries, int bytes})> drafts =
          await failedTaskDraftUsage();
      if (aiCache.isErr) {
        return Err<StorageUsageReport>(aiCache.errorOrNull!);
      }
      if (drafts.isErr) {
        return Err<StorageUsageReport>(drafts.errorOrNull!);
      }

      final Set<String> tables = await _tableNames();
      final int databaseBytes = _databaseBytesOnDisk();
      return Ok<StorageUsageReport>(
        StorageUsageReport(
          measuredAt: measuredAt,
          categories: <StorageCategoryUsage>[
            StorageCategoryUsage(
              category: StorageCategory.articleBody,
              byteCount: bodies.read<int>('b'),
              itemCount: bodies.read<int>('c'),
            ),
            StorageCategoryUsage(
              category: StorageCategory.newsSummary,
              byteCount: summaries.read<int>('b'),
              itemCount: summaries.read<int>('c'),
            ),
            StorageCategoryUsage(
              category: StorageCategory.otherCache,
              byteCount: aiCache.unwrap().bytes + drafts.unwrap().bytes,
              itemCount: aiCache.unwrap().entries + drafts.unwrap().entries,
            ),
            StorageCategoryUsage(
              category: StorageCategory.database,
              byteCount: databaseBytes,
              // 「一个数据库文件 + WAL/SHM」与「实际有哪些表」是两件事，但界面只需要一个数字，
              // 因此这里给出**表数**（它比「文件数」更能说明这一项是什么）。
              itemCount: tables.length,
            ),
          ],
        ),
      );
    } on Exception catch (error, stackTrace) {
      return Err<StorageUsageReport>(
        _storage('cleanup.measure', error, stackTrace),
      );
    }
  }

  // -------------------------------------------------------------------------
  // 正文释放
  // -------------------------------------------------------------------------

  @override
  Future<Result<({CleanupImpact impact, List<int> articleIds})>>
  planArticleBodyRelease({
    required DateTime cutoffUtc,
    required bool includeFavorite,
    required bool includeLater,
  }) async {
    try {
      final QueryRow row = await _db
          .customSelect(
            'SELECT '
            'COALESCE(SUM(CASE WHEN protected = 0 THEN 1 ELSE 0 END), 0) AS n, '
            'COALESCE(SUM(CASE WHEN protected = 0 THEN bytes ELSE 0 END), 0) AS b, '
            'COALESCE(SUM(CASE WHEN protected = 1 THEN 1 ELSE 0 END), 0) AS p '
            'FROM ('
            '  SELECT '
            '    COALESCE(length(CAST(body AS BLOB)), 0) + '
            '    COALESCE(length(CAST(extracted_body AS BLOB)), 0) AS bytes, '
            "    CASE WHEN (favorite = 1 AND ? = 0) OR (reading_state = 'later' AND ? = 0) "
            '         THEN 1 ELSE 0 END AS protected '
            '  FROM articles '
            "  WHERE ((body IS NOT NULL AND body <> '') "
            "      OR (extracted_body IS NOT NULL AND extracted_body <> '')) "
            '    AND COALESCE(published_at, fetched_at) < ?'
            ')',
            variables: <Variable<Object>>[
              Variable<int>(includeFavorite ? 1 : 0),
              Variable<int>(includeLater ? 1 : 0),
              Variable<String>(_isoUtc(cutoffUtc)),
            ],
          )
          .getSingle();

      final List<QueryRow> ids = await _db
          .customSelect(
            'SELECT id FROM articles '
            "WHERE ((body IS NOT NULL AND body <> '') "
            "    OR (extracted_body IS NOT NULL AND extracted_body <> '')) "
            '  AND COALESCE(published_at, fetched_at) < ? '
            '  AND NOT ((favorite = 1 AND ? = 0) '
            "        OR (reading_state = 'later' AND ? = 0))",
            variables: <Variable<Object>>[
              Variable<String>(_isoUtc(cutoffUtc)),
              Variable<int>(includeFavorite ? 1 : 0),
              Variable<int>(includeLater ? 1 : 0),
            ],
          )
          .get();
      return Ok<({CleanupImpact impact, List<int> articleIds})>((
        impact: CleanupImpact(
          articleBodies: row.read<int>('n'),
          articleBodyBytes: row.read<int>('b'),
          protectedArticles: row.read<int>('p'),
        ),
        articleIds: ids
            .map((QueryRow r) => r.read<int>('id'))
            .toList(growable: false),
      ));
    } on Exception catch (error, stackTrace) {
      return Err<({CleanupImpact impact, List<int> articleIds})>(
        _storage('cleanup.planArticleRelease', error, stackTrace),
      );
    }
  }

  @override
  Future<Result<({int articles, int bytes})>> releaseArticleBodies({
    required List<int> articleIds,
  }) async {
    try {
      if (articleIds.isEmpty) {
        return const Ok<({int articles, int bytes})>((articles: 0, bytes: 0));
      }
      return Ok<({int articles, int bytes})>(
        await _db.transaction(() async {
          final QueryRow before = await _freedBytesOf(articleIds);
          final int freed = before.read<int>('b');
          // 只写正文列与完整性。**刻意不出现在这条 UPDATE 里的列**：reading_state、favorite、
          // guid、guid_present、normalized_link、source_url、fallback_fingerprint、
          // fingerprint_reliability、identity_basis、sync_key、feed_id、feed_title、feed_url、
          // published_at、fetched_at、created_at。身份与状态全部留在原处，因此刷新按同一套规则
          // 匹配到这一行（架构 5.3 的「防止刷新把文章复活成未读」）。
          final int changed =
              await (_db.update(
                _db.articles,
              )..where((Articles t) => t.id.isIn(articleIds))).write(
                const ArticlesCompanion(
                  body: Value<String?>(null),
                  bodyHash: Value<String?>(null),
                  extractedBody: Value<String?>(null),
                  extractedBodyHash: Value<String?>(null),
                  extractedAt: Value<DateTime?>(null),
                  extractedTitle: Value<String?>(null),
                  extractedImageUrls: Value<String?>(null),
                  // 释放后「本应有正文而正文为空」必须能被如实说明（T039 的判据），而只有
                  // sourceBody/extracted 会落进那个判据；库里现在确实只剩标题与摘要，因此改成
                  // summaryOnly —— 这是与当前数据一致的取值，不是粉饰。
                  bodyCompleteness: Value<BodyCompleteness>(
                    BodyCompleteness.summaryOnly,
                  ),
                ),
              );
          return (articles: changed, bytes: freed);
        }),
      );
    } on Exception catch (error, stackTrace) {
      return Err<({int articles, int bytes})>(
        _storage('cleanup.releaseArticleBodies', error, stackTrace),
      );
    }
  }

  // -------------------------------------------------------------------------
  // 总结清理
  // -------------------------------------------------------------------------

  @override
  Future<Result<({CleanupImpact impact, List<int> runIds})>>
  planSummaryCleanup({required DateTime cutoffUtc}) async {
    try {
      final List<QueryRow> rows = await _db
          .customSelect(
            'SELECT id, '
            'COALESCE(length(CAST(input_snapshot AS BLOB)), 0) + '
            'COALESCE(length(CAST(site_results AS BLOB)), 0) + '
            'COALESCE(length(CAST(materials AS BLOB)), 0) + '
            'COALESCE(length(CAST(items AS BLOB)), 0) + '
            'COALESCE(length(CAST(draft_text AS BLOB)), 0) AS b '
            'FROM news_runs WHERE created_at < ?',
            variables: <Variable<Object>>[Variable<String>(_isoUtc(cutoffUtc))],
          )
          .get();
      int bytes = 0;
      final List<int> ids = <int>[];
      for (final QueryRow row in rows) {
        ids.add(row.read<int>('id'));
        bytes += row.read<int>('b');
      }
      return Ok<({CleanupImpact impact, List<int> runIds})>((
        impact: CleanupImpact(summaryRuns: ids.length, summaryBytes: bytes),
        runIds: ids,
      ));
    } on Exception catch (error, stackTrace) {
      return Err<({CleanupImpact impact, List<int> runIds})>(
        _storage('cleanup.planSummary', error, stackTrace),
      );
    }
  }

  @override
  Future<Result<({int runs, int bytes})>> deleteSummaryRuns({
    required List<int> runIds,
  }) async {
    try {
      if (runIds.isEmpty) {
        return const Ok<({int runs, int bytes})>((runs: 0, bytes: 0));
      }
      return Ok<({int runs, int bytes})>(
        await _db.transaction(() async {
          // 先把将被释放的字节读出来（删掉之后就只能是 0，而回执里的「释放了 X」是用户要看的
          // 数字）。
          final List<Variable<Object>> variables = <Variable<Object>>[
            for (final int id in runIds) Variable<int>(id),
          ];
          final QueryRow before = await _db
              .customSelect(
                'SELECT COALESCE(SUM(COALESCE(length(CAST(input_snapshot AS BLOB)), 0) + '
                'COALESCE(length(CAST(site_results AS BLOB)), 0) + '
                'COALESCE(length(CAST(materials AS BLOB)), 0) + '
                'COALESCE(length(CAST(items AS BLOB)), 0) + '
                'COALESCE(length(CAST(draft_text AS BLOB)), 0)), 0) AS b '
                'FROM news_runs WHERE id IN (${_placeholders(runIds.length)})',
                variables: variables,
              )
              .getSingle();
          final int freed = before.read<int>('b');
          final int removed = await (_db.delete(
            _db.newsRuns,
          )..where((NewsRuns t) => t.id.isIn(runIds))).go();
          return (runs: removed, bytes: freed);
        }),
      );
    } on Exception catch (error, stackTrace) {
      return Err<({int runs, int bytes})>(
        _storage('cleanup.deleteSummary', error, stackTrace),
      );
    }
  }

  // -------------------------------------------------------------------------
  // AI 结果缓存与失败草稿
  // -------------------------------------------------------------------------

  /// 结果缓存的维护句柄（与 AI 任务路径共用同一份实现与同一份数据）。
  DriftAiResultCache get _aiCache => DriftAiResultCache(_db, clock: clock);

  @override
  Future<Result<({int entries, int bytes})>> aiCacheUsage() => _aiCache.usage();

  @override
  Future<Result<({int entries, int bytes})>> clearAiResultCache() async {
    final Result<({int entries, int bytes})> before = await _aiCache.usage();
    if (before.isErr) {
      return before;
    }
    final Result<void> cleared = await _aiCache.clear();
    if (cleared.isErr) {
      return Err<({int entries, int bytes})>(cleared.errorOrNull!);
    }
    // 返回**删除前**的读数：调用方要显示「释放了多少」，而删除之后统计只能是 0。
    return before;
  }

  @override
  Future<Result<({int entries, int bytes})>> failedTaskDraftUsage() async {
    try {
      final QueryRow row = await _db
          .customSelect(
            'SELECT COUNT(*) AS c, '
            'COALESCE(SUM(COALESCE(length(CAST(input_snapshot AS BLOB)), 0) + '
            'COALESCE(length(CAST(result_text AS BLOB)), 0)), 0) AS b '
            "FROM ai_tasks WHERE status IN ('failed', 'cancelled', 'interrupted')",
          )
          .getSingle();
      return Ok<({int entries, int bytes})>((
        entries: row.read<int>('c'),
        bytes: row.read<int>('b'),
      ));
    } on Exception catch (error, stackTrace) {
      return Err<({int entries, int bytes})>(
        _storage('cleanup.failedDraftUsage', error, stackTrace),
      );
    }
  }

  @override
  Future<Result<({int entries, int bytes})>> clearFailedTaskDrafts() async {
    try {
      final Result<({int entries, int bytes})> before =
          await failedTaskDraftUsage();
      if (before.isErr) {
        return before;
      }
      await (_db.delete(
        _db.aiTasks,
      )..where((t) => t.status.isIn(_draftTaskStatuses))).go();
      return before;
    } on Exception catch (error, stackTrace) {
      return Err<({int entries, int bytes})>(
        _storage('cleanup.clearFailedDrafts', error, stackTrace),
      );
    }
  }

  // -------------------------------------------------------------------------
  // 彻底删除
  // -------------------------------------------------------------------------

  @override
  Future<Result<ArticlePurgeImpact>> articlePurgeImpact(int articleId) async {
    try {
      final QueryRow? article = await _db
          .customSelect(
            'SELECT id, title, image_url AS img, '
            "CASE WHEN ai_summary IS NOT NULL AND ai_summary <> '' THEN 1 ELSE 0 END AS ai "
            'FROM articles WHERE id = ?',
            variables: <Variable<Object>>[Variable<int>(articleId)],
          )
          .getSingleOrNull();
      if (article == null) {
        return Err<ArticlePurgeImpact>(
          StorageError(
            operation: 'cleanup.purgeImpact',
            detail: '文章不存在',
            isMissing: true,
          ),
        );
      }
      return Ok<ArticlePurgeImpact>(
        ArticlePurgeImpact(
          articleId: articleId,
          title: article.read<String>('title'),
          citations: await _countWhere('citations', 'article_id', articleId),
          aiSummaries: article.read<int>('ai'),
          translations: await _countWhere(
            'article_translation_records',
            'article_id',
            articleId,
          ),
          readingSessions: await _countWhere(
            'reading_sessions',
            'article_id',
            articleId,
          ),
          cachedMedia: _cachedMediaFilesFor(article.read<String?>('img'))
              .length,
          // 新闻引用（news_runs.materials 里的 articleId）需要解析 JSON 才能计数，而那是
          // 用例层的数据形状（core 的 NewsMaterial）。这里用一条**保守的** LIKE 计数：
          // 它的用途只是让确认页说「还被 N 条新闻引用」提示用户，漏报不造成数据损失，
          // 而错报会让用户在删除后去找一条并不存在的引用。因此只数明确的形状。
          newsReferences: await _countNewsReferences(articleId),
        ),
      );
    } on Exception catch (error, stackTrace) {
      return Err<ArticlePurgeImpact>(
        _storage('cleanup.purgeImpact', error, stackTrace),
      );
    }
  }

  @override
  Future<Result<ArticlePurgeImpact>> purgeArticle(int articleId) async {
    try {
      final Result<ArticlePurgeImpact> impact = await articlePurgeImpact(
        articleId,
      );
      if (impact.isErr) {
        return impact;
      }
      final String? imageUrl = await _imageUrlOf(articleId);
      await _db.transaction(() async {
        // 顺序由外键决定：readings_sessions 与 article_translation_records 都指向 articles
        // 且**没有**级联动作（前者）或有级联（后者）。会话必须先删——外键开启时直接删文章
        // 会被拒绝，而那种失败会让「彻底删除」变成一次无法完成的动作。
        await (_db.delete(
          _db.readingSessions,
        )..where((ReadingSessions t) => t.articleId.equals(articleId))).go();
        // 译文有 CASCADE，但显式删除一段更清楚：这里删的是**译文头**，段落随之级联。
        await (_db.delete(_db.articleTranslationRecords)..where(
              (ArticleTranslationRecords t) => t.articleId.equals(articleId),
            ))
            .go();
        // 引用**不删只断链**（架构 4.4：引用保留最小快照作为历史总结的出处）。
        // 表定义里已经是 ON DELETE SET NULL，但这里显式置空，reason 与译文相同：不依赖一个
        // 只在建表时生效的约束（旧库可能是在该约束存在之前建的）。
        await (_db.update(_db.citations)
              ..where((Citations t) => t.articleId.equals(articleId)))
            .write(const CitationsCompanion(articleId: Value<int?>(null)));
        await (_db.delete(
          _db.articles,
        )..where((Articles t) => t.id.equals(articleId))).go();
      });
      // 媒体缓存（文件系统）在事务**之外**删：文件删除没有事务语义，混进事务只会让一个
      // 「文件被占用」的错误把已经成功的数据库删除回滚掉。删不掉的文件在下一次
      // 「一键清缓存」或到期清理里回收，不会留下永久副本。
      for (final String file in _cachedMediaFilesFor(imageUrl)) {
        try {
          final File target = File(file);
          if (target.existsSync()) {
            target.deleteSync();
          }
        } on Exception {
          // 见上：删不掉不阻断。
        }
      }
      return impact;
    } on Exception catch (error, stackTrace) {
      return Err<ArticlePurgeImpact>(
        _storage('cleanup.purge', error, stackTrace),
      );
    }
  }

  // -------------------------------------------------------------------------
  // 内部工具
  // -------------------------------------------------------------------------

  /// 取指定文章正文列的总字节（事务内先读后写）。
  Future<QueryRow> _freedBytesOf(List<int> ids) => _db
      .customSelect(
        'SELECT COALESCE(SUM(COALESCE(length(CAST(body AS BLOB)), 0) + '
        'COALESCE(length(CAST(extracted_body AS BLOB)), 0)), 0) AS b '
        'FROM articles WHERE id IN (${_placeholders(ids.length)})',
        variables: <Variable<Object>>[
          for (final int id in ids) Variable<int>(id),
        ],
      )
      .getSingle();

  Future<int> _countWhere(String table, String column, int value) async {
    final QueryRow row = await _db
        .customSelect(
          'SELECT COUNT(*) AS c FROM $table WHERE $column = ?',
          variables: <Variable<Object>>[Variable<int>(value)],
        )
        .getSingle();
    return row.read<int>('c');
  }

  /// `IN (...)` 的占位符串。
  ///
  /// 自己拼是因为 drift 的表达式 API 不接受「已知长度的一组整数」之外的形状，而这里需要的
  /// 只是一个**数量正确**的问号序列；值仍走变量绑定，不参与任何字符串拼接。
  static String _placeholders(int count) =>
      List<String>.filled(count, '?').join(', ');

  /// 该文章引用里，指向它的新闻运行数（保守计数，见调用点说明）。
  Future<int> _countNewsReferences(int articleId) async {
    // materials 是 JSON 数组，每项形如 {"articleId":12,...}（核心层的编码器用 jsonEncode 的
    // 紧凑形式，因此不含空格）。
    //
    // 三条边界规则，缺一条就会数错：
    //   1) **模式必须以 `%` 开头**。LIKE 是整串匹配，写成 `"articleId":1,%` 时 SQLite 会去比
    //      字符串的**开头**，而 JSON 开头是 `[{`，于是永远零命中（实测：同一条数据
    //      `LIKE '"articleId":1,%'` 返回 0，`LIKE '%"articleId":1,%'` 返回 1）。这个特征的表现
    //      是「确认页说没有被引用、删完却发现引用断了」，而中间没有任何报错；
    //   2) **数字后面必须有边界**（`,` 或 `}`）。只写 `%"articleId":1%` 会把 articleId=12、13、
    //      100 全都算成 1（实测：id 1 与 12 并存时返回 2）；
    //   3) 带空格与不带空格两种编码都匹配（历史数据或别的写入路径可能用带空格的 jsonEncode）。
    //
    // 结果只用于确认页上的一句提示（「还被 N 条新闻引用」）：漏报不造成数据损失，因此宁可保守。
    final List<String> patterns = <String>[
      for (final String separator in <String>[':', ': ']) ...<String>[
        '%"articleId"$separator$articleId,%',
        '%"articleId"$separator$articleId}%',
      ],
    ];
    final QueryRow row = await _db
        .customSelect(
          'SELECT COUNT(*) AS c FROM news_runs '
          'WHERE ${List<String>.filled(patterns.length, 'materials LIKE ?').join(' OR ')}',
          variables: <Variable<Object>>[
            for (final String pattern in patterns) Variable<String>(pattern),
          ],
        )
        .getSingle();
    return row.read<int>('c');
  }

  Future<String?> _imageUrlOf(int articleId) async {
    final QueryRow? row = await _db
        .customSelect(
          'SELECT image_url AS img FROM articles WHERE id = ?',
          variables: <Variable<Object>>[Variable<int>(articleId)],
        )
        .getSingleOrNull();
    return row?.read<String?>('img');
  }

  /// 一张卡片图在媒体缓存目录里的两个文件（数据 + 元数据）；无目录或地址为空时返回空。
  List<String> _cachedMediaFilesFor(String? imageUrl) {
    final String? dir = mediaDirectoryPath;
    if (dir == null || imageUrl == null || imageUrl.isEmpty) {
      return const <String>[];
    }
    // 缓存文件名是**地址的 SHA-256**（T021 的 cacheKeyFor），因此这里能确定性地算出它，
    // 而不需要遍历缓存目录去猜「哪一个文件属于这篇文章」。
    final String key = sha256HexOfString(imageUrl);
    return <String>[p.join(dir, '$key.img'), p.join(dir, '$key.meta')];
  }

  /// 数据库在磁盘上的总字节（主库 + WAL + SHM）；取不到时为 0。
  int _databaseBytesOnDisk() {
    int total = 0;
    for (final String path in databaseFiles) {
      try {
        final File file = File(path);
        if (file.existsSync()) {
          total += file.statSync().size;
        }
      } on Exception {
        // 单个文件取不到（权限/竞态）不影响其余：统计是展示用的。
      }
    }
    return total;
  }

  Future<Set<String>> _tableNames() async {
    final List<QueryRow> rows = await _db
        .customSelect("SELECT name FROM sqlite_master WHERE type = 'table'")
        .get();
    return rows.map((QueryRow r) => r.read<String>('name')).toSet();
  }

  /// ISO-8601（UTC）文本，与 build.yaml 的 `store_date_time_values_as_text` 口径一致。
  ///
  /// 用它做字符串比较而不是把时间交给 SQLite：drift 把 DateTime 存成 ISO 文本（带 `Z`），
  /// 而同一格式的 UTC 文本**字典序即时间序**（更早的时刻字符串更小），因此直接比较是正确的，
  /// 也不需要 SQLite 的日期函数（那些对带 `Z` 的文本依赖版本行为）。
  static String _isoUtc(DateTime at) => at.toUtc().toIso8601String();

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
