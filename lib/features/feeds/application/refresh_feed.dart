// 订阅刷新用例（T013；架构 4.1 的完整刷新契约）。
//
// 本文件把四个步骤串成一条有明确失败语义的流水线：
//   取字节（FeedFetcher）→ 解析（parseFeed）→ 清洗正文（sanitizeHtmlToDocument）
//   → 去重入库（FeedArticleStore.upsertArticles）
//
// 为什么放在 features/feeds 而不是 infrastructure：这里做的是**业务决策**——
// 什么算「有新内容」、304 时该做什么、解析失败时保留什么、正文变了要不要更新。
// infrastructure 只提供能力，不替业务做判断。
//
// 架构 4.1 要求「区分 304、没有新文章、部分解析失败和网络失败；保留旧内容」。这四种结果
// 在本文件里分别是：
//   - 304           → FeedRefreshOutcome.notModified，**完全不写文章**，只记录检查时间；
//   - 没有新文章     → FeedRefreshOutcome.unchanged（全部条目已存在且无变化）；
//   - 部分解析失败   → FeedRefreshOutcome.partial（成功条目照常入库，保留旧内容）；
//   - 网络失败       → FeedRefreshOutcome.networkFailed（不写任何文章，返回类型化错误）。
// 关键设计：**失败路径上没有任何可供写入的数据**。这不是靠「记得别写」实现的，而是因为
// 网络/解析失败时根本没有产出 ArticleImport 列表。
library;

import 'package:flux/core/core.dart';

import '../domain/article_identity.dart';
import '../domain/content_sanitizer.dart';
import '../domain/feed_parser.dart';

/// 刷新一个源所需的一切外部依赖（显式传入，便于测试替换）。
class FeedRefreshRequest {
  /// 构造请求。
  const FeedRefreshRequest({
    required this.feedId,
    required this.url,
    this.feedName,
    this.etag,
    this.lastModified,
    this.now,
  });

  /// 本机 feed id。
  final int feedId;

  /// 要抓取的地址。
  final Uri url;

  /// 源显示名（仅用于日志与诊断，不参与身份判定）。
  final String? feedName;

  /// 已缓存的 ETag（来自 feeds 表）。
  final String? etag;

  /// 已缓存的 Last-Modified。
  final String? lastModified;

  /// 「现在」；为空时用 [Clock]（测试注入固定时间）。
  final DateTime? now;
}

/// 一次刷新的结果摘要。
class FeedRefreshResult {
  /// 构造结果。
  const FeedRefreshResult({
    required this.outcome,
    this.fetchedEntries = 0,
    this.imported,
    this.rejectedEntries = 0,
    this.error,
    this.finalUri,
  });

  /// 结果类别（对应 feeds.lastRefreshResult）。
  final FeedRefreshOutcome outcome;

  /// 源里解析出的条目数（含被跳过的）。
  final int fetchedEntries;

  /// 入库计数；未发生写入时为 null（304 / 网络失败）。
  final ArticleImportOutcome? imported;

  /// 因缺少最小必需字段被跳过的条目数。
  final int rejectedEntries;

  /// 失败时的类型化错误；成功时为 null。
  final AppError? error;

  /// 最终地址（跟随重定向后；诊断用）。
  final String? finalUri;

  /// 是否发生了写入。
  bool get didWrite => imported != null;

  /// 新增文章数。
  int get inserted => imported?.inserted ?? 0;

  /// 正文被替换的文章数。
  int get bodyUpdated => imported?.bodyUpdated ?? 0;
}

/// 订阅刷新用例。
class RefreshFeedUseCase {
  /// 构造用例。
  ///
  /// [sanitizerLimits] 与 [parserLimits] 可覆盖，便于测试构造「正文过大」「深度超限」等
  /// 场景；生产用默认值。
  const RefreshFeedUseCase({
    required this.fetcher,
    required this.store,
    this.diagnostics = const NoopDiagnosticSink(),
    this.clock = const SystemClock(),
    this.parserLimits = const FeedParserLimits(),
    this.sanitizerLimits = const SanitizerLimits(),
  });

  /// 取字节能力。
  final FeedFetcher fetcher;

  /// 写库能力。
  final FeedArticleStore store;

  /// 诊断记录。
  final DiagnosticSink diagnostics;

  /// 时钟（提供「抓取时间」，供无日期的条目使用）。
  final Clock clock;

  /// 解析限制。
  final FeedParserLimits parserLimits;

  /// 清洗限制。
  final SanitizerLimits sanitizerLimits;

  /// 刷新一个源。
  ///
  /// **永不抛异常**（除编程错误）：所有可预期失败都成为 [FeedRefreshResult.error]，
  /// 使调用方可以无差别地处理「一个源失败」而不中断整批刷新。
  Future<FeedRefreshResult> call(FeedRefreshRequest request) async {
    final DateTime now = (request.now ?? clock.now()).toUtc();

    // ---- 1. 取字节 ---------------------------------------------------------
    final Result<FeedFetchResult> fetched = await fetcher.fetch(
      request.url,
      validator: FeedCacheValidator(
        etag: request.etag,
        lastModified: request.lastModified,
      ),
    );

    if (fetched.isErr) {
      final AppError error = fetched.errorOrNull!;
      diagnostics.error(
        '订阅抓取失败：${_describe(request)} — ${error.message}',
        tag: 'feed.fetch',
      );
      // 失败时仍然记录「检查过」，否则界面会一直显示很久以前的时间，看起来像没在刷新。
      await _recordOutcome(
        request: request,
        outcome: FeedRefreshOutcome.networkFailed,
        checkedAt: now,
        errorKind: error.kind,
      );
      return FeedRefreshResult(
        outcome: FeedRefreshOutcome.networkFailed,
        error: error,
      );
    }

    final FeedFetchResult response = fetched.unwrap();

    // ---- 2. 304：不更新任何文章，只记录检查时间 -----------------------------
    if (response.isNotModified) {
      diagnostics.info('订阅未修改（304）：${_describe(request)}', tag: 'feed.fetch');
      await _recordOutcome(
        request: request,
        outcome: FeedRefreshOutcome.notModified,
        checkedAt: now,
        // 304 不带新的校验值，但沿用旧值（不改动）。
        etag: response.etag ?? request.etag,
        lastModified: response.lastModified ?? request.lastModified,
      );
      return FeedRefreshResult(
        outcome: FeedRefreshOutcome.notModified,
        finalUri: response.finalUri,
      );
    }

    // ---- 3. 解析 ------------------------------------------------------------
    final String body = response.body ?? '';
    final Result<ParsedFeed> parsed = parseFeed(
      body,
      source: 'feed:${request.feedId}',
      limits: parserLimits,
    );

    if (parsed.isErr) {
      final AppError error = parsed.errorOrNull!;
      diagnostics.error(
        '订阅解析失败：${_describe(request)} — ${error.message}',
        tag: 'feed.parse',
      );
      // 解析失败**保留旧内容**：不写任何文章，只记录结果与错误类别。
      // 注意这里不覆盖 ETag/Last-Modified：源内容坏了不代表缓存失效，保留条件请求
      // 可以在源恢复正常后立刻命中 304 而不是重下全文。
      await _recordOutcome(
        request: request,
        outcome: FeedRefreshOutcome.parseFailed,
        checkedAt: now,
        errorKind: error.kind,
      );
      return FeedRefreshResult(
        outcome: FeedRefreshOutcome.parseFailed,
        error: error,
        finalUri: response.finalUri,
      );
    }

    final ParsedFeed feed = parsed.unwrap();

    // ---- 4. 规范化身份 + 清洗正文 -------------------------------------------
    final String feedIdentity =
        normalizeLink(request.url.toString()) ?? request.url.toString();
    final List<NormalizedEntry> normalized = normalizeEntries(
      entries: feed.entries,
      feedIdentity: feedIdentity,
    );

    final List<ArticleImport> imports = <ArticleImport>[];
    int sanitizerLosses = 0;
    for (final NormalizedEntry entry in normalized) {
      final SanitizerReport report = sanitizeHtmlToDocument(
        entry.entry.contentHtml,
        limits: sanitizerLimits,
      );
      if (report.isLossy) {
        sanitizerLosses++;
      }
      imports.add(
        _toImport(
          feedId: request.feedId,
          entry: entry,
          report: report,
          fetchedAt: now,
        ),
      );
    }
    if (sanitizerLosses > 0) {
      // 记录数量而不是内容：正文属于用户数据，日志只留可核对的计数。
      diagnostics.warning(
        '正文清洗丢弃了部分内容：${_describe(request)} — $sanitizerLosses 条',
        tag: 'feed.sanitize',
      );
    }

    // ---- 5. 入库（幂等 + 事务） ---------------------------------------------
    Result<ArticleImportOutcome> stored = const Ok<ArticleImportOutcome>(
      ArticleImportOutcome(
        inserted: 0,
        updated: 0,
        bodyUpdated: 0,
        unchanged: 0,
      ),
    );
    if (imports.isNotEmpty) {
      stored = await store.upsertArticles(imports);
      if (stored.isErr) {
        final AppError error = stored.errorOrNull!;
        diagnostics.error(
          '订阅入库失败：${_describe(request)} — ${error.message}',
          tag: 'feed.store',
        );
        // 入库失败不覆盖 ETag：本次并没有成功保存内容，若记下新 ETag，下次会 304 而
        // 永远拿不到这批文章（数据静默丢失）。
        await _recordOutcome(
          request: request,
          outcome: FeedRefreshOutcome.networkFailed,
          checkedAt: now,
          errorKind: error.kind,
        );
        return FeedRefreshResult(
          outcome: FeedRefreshOutcome.networkFailed,
          error: error,
          fetchedEntries: feed.entries.length,
          rejectedEntries: feed.rejectedEntries,
          finalUri: response.finalUri,
        );
      }
    }

    final ArticleImportOutcome outcome = stored.unwrap();
    final bool hasNew =
        outcome.inserted > 0 || outcome.updated > 0 || outcome.bodyUpdated > 0;
    // 「部分解析失败」的判定：源里有条目被跳过，但也有成功条目。若全部条目都被跳过，
    // 那更接近「源的格式变了」，对用户而言与解析失败同级。
    final bool partial =
        feed.rejectedEntries > 0 && (hasNew || outcome.unchanged > 0);
    final FeedRefreshOutcome refreshOutcome = partial
        ? FeedRefreshOutcome.partial
        : hasNew
        ? FeedRefreshOutcome.updated
        : FeedRefreshOutcome.unchanged;

    await _recordOutcome(
      request: request,
      outcome: refreshOutcome,
      checkedAt: now,
      etag: response.etag ?? request.etag,
      lastModified: response.lastModified ?? request.lastModified,
    );

    return FeedRefreshResult(
      outcome: refreshOutcome,
      fetchedEntries: feed.entries.length,
      imported: outcome,
      rejectedEntries: feed.rejectedEntries,
      finalUri: response.finalUri,
    );
  }

  /// 把规范化条目 + 清洗结果组装成待入库项。
  ArticleImport _toImport({
    required int feedId,
    required NormalizedEntry entry,
    required SanitizerReport report,
    required DateTime fetchedAt,
  }) {
    final ParsedFeedEntry raw = entry.entry;
    // 正文 = 清洗后的受控文档的纯文本导出。用纯文本而不是 HTML 落库的原因：
    //   1) 「正文哈希变化 → 更新正文」需要一个**稳定**的修订判据，而未清洗的 HTML 里
    //      标签属性/空白/跟踪参数的微小变化会产生大量假修订；
    //   2) 受控文档树由渲染层按节点重建，落库只需要文本内容；
    //   3) 清洗已经把受控节点白名单化，不存在把原始 HTML 当权威的问题。
    final String? body = report.document.isEmpty
        ? null
        : docDocumentPlainText(report.document.children).trim();

    final bool hasSourceBody = body != null && body.isNotEmpty;
    // 完整性判定：有正文按「来源正文」，只有摘要按「摘要」。unknown 留给提取失败等
    // 尚未判定的情况（T024 的静态提取会产出 extracted）。
    final BodyCompleteness completeness = hasSourceBody
        ? BodyCompleteness.sourceBody
        : BodyCompleteness.summaryOnly;

    return ArticleImport(
      feedId: feedId,
      title: raw.title.isEmpty ? _fallbackTitle(raw) : raw.title,
      identityBasis: entry.identityBasis,
      guid: entry.guid,
      guidPresent: entry.guidPresent,
      normalizedLink: entry.normalizedLink,
      sourceUrl: entry.sourceUrl,
      fallbackFingerprint: entry.fallbackFingerprint,
      fingerprintReliability: entry.fingerprintReliability,
      author: raw.author,
      // 无日期用抓取时间：架构 4.1 要求「发布时间未知则使用抓取时间排序并注明」。
      // 注明的方式是把 publishedAt 置为 null、由界面对比 fetchedAt 判断，因此这里
      // **不**伪造 publishedAt——那会让「未知」变成「源声明的时刻」。
      publishedAt: raw.publishedAt,
      fetchedAt: fetchedAt,
      body: hasSourceBody ? body : null,
      bodyCompleteness: completeness,
      bodyHash: hasSourceBody ? bodyHashOf(body) : null,
      summary: _summaryOf(raw),
    );
  }

  /// 无标题条目的兜底标题：用链接或日期构造，绝不留空。
  ///
  /// 空标题在列表里会变成一行空白，用户无法判断那是什么；用链接至少可以识别。
  static String _fallbackTitle(ParsedFeedEntry entry) {
    final String? link = entry.link ?? entry.guid;
    if (link != null && link.isNotEmpty) {
      return link;
    }
    return '(无标题)';
  }

  /// 摘要：优先源内摘要，缺失时截取正文（架构 4.1：摘要优先源内摘要）。
  static String? _summaryOf(ParsedFeedEntry entry) {
    final String? summary = entry.summary;
    if (summary == null || summary.isEmpty) {
      return null;
    }
    // 源内摘要可能是 HTML：清洗成纯文本，避免列表里出现尖括号标签。
    final String plain = sanitizeHtmlToPlainText(summary);
    return plain.isEmpty ? null : plain;
  }

  /// 记录抓取结果（诊断列 + 条件请求缓存）。
  Future<void> _recordOutcome({
    required FeedRefreshRequest request,
    required FeedRefreshOutcome outcome,
    required DateTime checkedAt,
    String? errorKind,
    String? etag,
    String? lastModified,
  }) async {
    final Result<void> recorded = await store.recordRefreshOutcome(
      feedId: request.feedId,
      outcome: outcome,
      checkedAt: checkedAt,
      errorKind: errorKind,
      etag: etag,
      lastModified: lastModified,
    );
    if (recorded.isErr) {
      // 记录失败不影响刷新本身的结果（文章已经写好了），但必须留痕。
      diagnostics.warning(
        '记录抓取结果失败：${_describe(request)} — ${recorded.errorOrNull?.message}',
        tag: 'feed.store',
      );
    }
  }

  /// 日志里使用的源描述：名称（若有）+ 已脱敏地址。
  static String _describe(FeedRefreshRequest request) {
    final String url = SecretRedaction.sanitizeUrlString(
      request.url.toString(),
    );
    final String? name = request.feedName;
    return name == null || name.isEmpty ? url : '$name ($url)';
  }
}
