// 静态网页抓取端口的实现（T024）。
//
// 只是把 infrastructure 的 [HttpStaticPageFetcher] 的结果适配到 features 侧的端口形状。
// 为什么要这一层：features 不得 import infrastructure（架构 2.2，且有守卫测试），
// 而用例需要「取回 HTML」这个能力。适配层住在这里（infrastructure），由组合根注入。
//
// 这里**不**做任何判定：地址守卫、DNS 复检、体积上限全在 fetcher 内部（同一条判据链
// 与订阅/图片抓取共用）；本层只翻译结果类型。
library;

import 'package:flux/core/core.dart';
import 'package:flux/features/articles/application/fetch_original_article.dart';

import 'static_page_fetcher.dart';

/// [StaticPageFetcherPort] 的 HTTP 实现。
final class HttpStaticPageFetcherAdapter implements StaticPageFetcherPort {
  /// 构造适配器。
  HttpStaticPageFetcherAdapter({HttpStaticPageFetcher? fetcher})
    : _fetcher = fetcher ?? HttpStaticPageFetcher();

  final HttpStaticPageFetcher _fetcher;

  @override
  Future<Result<StaticPageDocument>> fetch(Uri uri) async {
    final Result<StaticPageFetchResult> result = await _fetcher.fetch(uri);
    if (result.isErr) {
      return Err<StaticPageDocument>(result.errorOrNull!);
    }
    final StaticPageFetchResult page = result.unwrap();
    return Ok<StaticPageDocument>(
      StaticPageDocument(
        html: page.html,
        finalUri: page.finalUri,
        contentType: page.contentType,
      ),
    );
  }
}
