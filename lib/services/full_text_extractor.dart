import 'package:dio/dio.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

/// 简易 Readability 风格全文提取。
///
/// 当 RSS 只提供摘要时，抓取原文页面并提取正文 HTML。
class FullTextExtractor {
  const FullTextExtractor(this._dio);

  final Dio _dio;

  Future<String> extract(String url) async {
    final response = await _dio.get<String>(
      url,
      options: Options(
        responseType: ResponseType.plain,
        sendTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 30),
        followRedirects: true,
        headers: {
          'User-Agent': 'FluxRSS/0.1 (+https://github.com/flux-rss)',
          'Accept': 'text/html,application/xhtml+xml,*/*',
        },
      ),
    );

    final html = response.data;
    if (html == null || html.trim().isEmpty) {
      throw const FormatException('页面内容为空');
    }

    final document = html_parser.parse(html);
    document
        .querySelectorAll('script, style, nav, header, footer, aside, noscript')
        .forEach((element) => element.remove());

    final candidates = <dom.Element>[
      if (document.querySelector('article') != null)
        document.querySelector('article')!,
      if (document.querySelector('main') != null)
        document.querySelector('main')!,
      if (document.querySelector('.post-content') != null)
        document.querySelector('.post-content')!,
      if (document.querySelector('.markdown') != null)
        document.querySelector('.markdown')!,
      if (document.querySelector('.content') != null)
        document.querySelector('.content')!,
      if (document.querySelector('#content') != null)
        document.querySelector('#content')!,
    ];

    final main = candidates.isEmpty ? document.body : candidates.first;
    if (main == null) {
      throw const FormatException('未能定位正文');
    }
    return main.innerHtml.trim();
  }
}
