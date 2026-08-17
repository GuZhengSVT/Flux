import 'package:dio/dio.dart';

import 'feed_parser.dart';

class FeedFetchException implements Exception {
  const FeedFetchException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 抓取远程 Feed 并解析为 [ParsedFeed]。
class FeedFetcher {
  const FeedFetcher(this._dio);

  final Dio _dio;

  Future<ParsedFeed> fetchAndParse(String url) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null ||
        !uri.hasScheme ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      throw const FeedFetchException('请输入有效的 http/https 地址');
    }

    try {
      final response = await _dio.get<String>(
        uri.toString(),
        options: Options(
          responseType: ResponseType.plain,
          sendTimeout: const Duration(seconds: 20),
          receiveTimeout: const Duration(seconds: 30),
          followRedirects: true,
          headers: {
            'User-Agent': 'FluxRSS/0.1 (+https://github.com/flux-rss)',
            'Accept': 'application/rss+xml, application/atom+xml, application/xml, text/xml, */*',
          },
        ),
      );

      if (response.statusCode == null ||
          response.statusCode! < 200 ||
          response.statusCode! >= 300) {
        throw FeedFetchException('HTTP ${response.statusCode}');
      }

      final xml = response.data;
      if (xml == null || xml.trim().isEmpty) {
        throw const FeedFetchException('Feed 内容为空');
      }

      return const FeedParser().parse(xml, uri.toString());
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      final String message;
      if (status == 403) {
        message = 'HTTP 403：服务器拒绝访问，可能是 RSSHub 实例不可用，请更换实例';
      } else if (status == 404) {
        message = 'HTTP 404：地址或路由不存在，请检查 RSSHub 路由是否正确';
      } else if (status == 429) {
        message = 'HTTP 429：请求过于频繁，请稍后重试';
      } else if (status != null && status >= 500) {
        message = 'HTTP $status：服务器错误，实例可能暂时不可用';
      } else if (status != null) {
        message = 'HTTP $status：请求失败';
      } else {
        message = '网络请求失败：${e.message ?? e.type}';
      }
      throw FeedFetchException(message);
    } on FormatException {
      throw const FeedFetchException('不是有效的 RSS/Atom XML');
    }
  }
}
