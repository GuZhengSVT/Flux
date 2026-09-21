// 主动获取原站全文（T024；架构 4.2 的 F-READ 与手册 6.3）。
//
// 一条最要紧的产品规则：**只有用户显式点击才抓取**。
// 「无自动/后台/批量」不是实现细节，而是本用例形状上的事实：它没有「监听文章变化」
// 的入口、没有定时器、不接收集合，只有一个「取哪一篇」的参数。任何自动批量抓取都无法
// 通过这个接口表达出来，因此它在结构上不可能发生（而不是靠调用方记得别这么做）。
//
// 结果的呈现要求（架构 4.2「失败保留原内容并给外部浏览器入口」）：
//   * 成功 → 保存到提取列（**不覆盖**源正文），界面可切换显示原文/提取正文；
//   * 失败 → 不改动任何已存正文，返回类型化失败让界面显示原因 + 外开入口。
//     「付费墙迹象 / 正文过短」也走这条路径，但它们是**提示**不是拒绝：抓到的东西仍然
//     会保存下来（用户自己的订阅内容有权获取），只是提示他可能不完整。
//
// 缓存与修订：成功后按哈希判断是否变化，内容未变则不重写大字段（存储层实现）。
library;

import 'package:flux/core/core.dart';

import 'package:flux/features/articles/domain/static_article_extractor.dart';
import 'package:flux/features/feeds/domain/article_identity.dart';

/// 静态网页抓取端口（由 infrastructure 实现）。
///
/// 只被这一条用例使用，而 core 是稳定的跨模块基础件；等第二条调用方出现时再考虑上移。
abstract interface class StaticPageFetcherPort {
  /// 取回 [uri] 指向的网页。
  Future<Result<StaticPageDocument>> fetch(Uri uri);
}

/// 一次网页抓取的结果（不解析）。
final class StaticPageDocument {
  /// 构造结果。
  const StaticPageDocument({
    required this.html,
    required this.finalUri,
    required this.contentType,
  });

  /// HTML 文本。
  final String html;

  /// 最终地址（已脱敏；跟随重定向之后）。
  final String finalUri;

  /// Content-Type。
  final String? contentType;
}

/// 一次主动获取的结果类别。
enum FetchOriginalOutcome {
  /// 成功取到可用的正文并已保存。
  ok,

  /// 取到了网页但没有可用正文（空 / 纯 JS 渲染）。
  noContent,

  /// 抓取或保存失败。
  failed,
}

/// 一次主动获取的结果。
final class FetchOriginalResult {
  /// 构造结果。
  const FetchOriginalResult({
    required this.outcome,
    required this.articleId,
    required this.usedSourceUrl,
    this.extraction,
    this.error,
    this.saved = false,
  });

  /// 结果类别。
  final FetchOriginalOutcome outcome;

  /// 文章 id。
  final int articleId;

  /// 实际抓取的地址（来自文章的 sourceUrl）。
  final String usedSourceUrl;

  /// 抽取结果（成功或「取到但没正文」时提供）。
  final StaticExtraction? extraction;

  /// 失败原因。
  final AppError? error;

  /// 是否已保存到库。
  final bool saved;

  /// 是否需要提示付费墙/登录墙。
  bool get paywallHint => extraction?.hasPaywallSignal ?? false;

  /// 是否需要提示「正文过短，可能纯 JS 渲染」。
  bool get shortBodyHint =>
      extraction?.outcome == StaticExtractionOutcome.empty;
}

/// 主动获取原站全文。
final class FetchOriginalArticleUseCase {
  /// 构造用例。
  const FetchOriginalArticleUseCase({
    required this.fetcher,
    required this.extractions,
    this.limits = const StaticExtractionLimits(),
    this.diagnostics = const NoopDiagnosticSink(),
  });

  /// 网页抓取端口。
  final StaticPageFetcherPort fetcher;

  /// 提取结果读写端口。
  final ArticleExtractionStore extractions;

  /// 抽取上限。
  final StaticExtractionLimits limits;

  /// 诊断记录。
  final DiagnosticSink diagnostics;

  /// 为一篇文章获取原站正文。
  ///
  /// [sourceUrl] 来自文章行（原始链接，保留查询参数）。地址非法或缺失时**不抓取**，
  /// 直接返回失败——把决定权留给界面（显示「这篇文章没有可访问的原站地址」）。
  Future<Result<FetchOriginalResult>> call({
    required int articleId,
    required String? sourceUrl,
  }) async {
    final Uri? uri = sourceUrl == null ? null : Uri.tryParse(sourceUrl.trim());
    if (uri == null || !uri.isAbsolute) {
      return Ok<FetchOriginalResult>(
        FetchOriginalResult(
          outcome: FetchOriginalOutcome.failed,
          articleId: articleId,
          usedSourceUrl: sourceUrl ?? '',
          error: NetworkError(
            uri: sourceUrl ?? '',
            reason: '文章没有可用的原站地址',
            isRetryable: false,
          ),
        ),
      );
    }

    final Result<StaticPageDocument> fetched = await fetcher.fetch(uri);
    if (fetched.isErr) {
      // 失败**不动**已存正文：这是架构 4.2 的明确要求，因此这条路径上没有任何写操作。
      return Ok<FetchOriginalResult>(
        FetchOriginalResult(
          outcome: FetchOriginalOutcome.failed,
          articleId: articleId,
          usedSourceUrl: uri.toString(),
          error: fetched.errorOrNull,
        ),
      );
    }
    final StaticPageDocument page = fetched.unwrap();
    final StaticExtraction extraction = extractStaticArticle(
      page.html,
      limits: limits,
    );
    if (!extraction.isUsable) {
      // 取到了网页但没有可用正文：如实报告「没抽到」，不当成成功。
      diagnostics.info(
        '原站正文抽取为空（文章 $articleId，区域 ${extraction.usedRegion}）',
        tag: 'article.extract',
      );
      return Ok<FetchOriginalResult>(
        FetchOriginalResult(
          outcome: FetchOriginalOutcome.noContent,
          articleId: articleId,
          usedSourceUrl: page.finalUri,
          extraction: extraction,
        ),
      );
    }

    final Result<void> saved = await extractions.saveExtraction(
      articleId: articleId,
      extraction: ExtractedArticleBody(
        body: extraction.text,
        bodyHash: bodyHashOf(extraction.text),
        title: extraction.title,
        imageUrls: extraction.imageUrls,
        extractedAt: DateTime.now().toUtc(),
      ),
    );
    if (saved.isErr) {
      return Ok<FetchOriginalResult>(
        FetchOriginalResult(
          outcome: FetchOriginalOutcome.failed,
          articleId: articleId,
          usedSourceUrl: page.finalUri,
          extraction: extraction,
          error: saved.errorOrNull,
        ),
      );
    }
    diagnostics.info(
      '已提取原站正文 ${extraction.text.length} 字（文章 $articleId）',
      tag: 'article.extract',
    );
    return Ok<FetchOriginalResult>(
      FetchOriginalResult(
        outcome: FetchOriginalOutcome.ok,
        articleId: articleId,
        usedSourceUrl: page.finalUri,
        extraction: extraction,
        saved: true,
      ),
    );
  }
}
