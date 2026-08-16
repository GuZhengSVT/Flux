import 'dart:io';

import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;
import 'package:xml/xml.dart';

import '../models/article.dart';

class ParsedArticle {
  const ParsedArticle({
    required this.title,
    this.link,
    this.author,
    this.publishedAt,
    this.contentHtml,
    this.summary,
    this.imageUrl,
    this.categories,
  });

  final String title;
  final String? link;
  final String? author;
  final DateTime? publishedAt;
  final String? contentHtml;
  final String? summary;
  final String? imageUrl;
  final List<String>? categories;

  Article toArticle(int feedId, {DateTime? fetchedAt}) {
    return Article(
      feedId: feedId,
      title: title,
      link: link,
      author: author,
      publishedAt: publishedAt,
      contentHtml: contentHtml,
      summary: summary,
      imageUrl: imageUrl,
      categories: categories,
      fetchedAt: fetchedAt ?? DateTime.now(),
    );
  }
}

class ParsedFeed {
  const ParsedFeed({
    required this.title,
    required this.sourceUrl,
    this.siteUrl,
    this.description,
    this.iconUrl,
    required this.articles,
  });

  final String title;
  final String sourceUrl;
  final String? siteUrl;
  final String? description;
  final String? iconUrl;
  final List<ParsedArticle> articles;
}

/// 轻量 RSS 2.0 / Atom 解析器。
///
/// 解析过程是纯 Dart，后续可放进 Isolate 执行，
/// 避免 XML 解析阻塞 UI 线程。
class FeedParser {
  const FeedParser();

  ParsedFeed parse(String xml, String sourceUrl) {
    final document = XmlDocument.parse(xml);
    final root = document.rootElement;
    final rootName = root.name.local.toLowerCase();

    if (rootName == 'feed') {
      return _parseAtom(root, sourceUrl);
    }
    return _parseRss(root, sourceUrl);
  }

  // ---------- RSS 2.0 ----------

  ParsedFeed _parseRss(XmlElement root, String sourceUrl) {
    final channel = _children(root).firstWhere(
      (e) => e.name.local.toLowerCase() == 'channel',
      orElse: () => root,
    );

    final title = _text(channel, 'title')?.trim() ?? sourceUrl;
    final description = _text(channel, 'description')?.trim();
    final siteUrl = _text(channel, 'link')?.trim();
    final iconUrl = _imageFromElement(channel, '');

    final articles = <ParsedArticle>[];
    for (final item in _children(
      channel,
    ).where((e) => e.name.local.toLowerCase() == 'item')) {
      final parsed = _parseRssItem(item);
      if (parsed != null) {
        articles.add(parsed);
      }
    }

    return ParsedFeed(
      title: title,
      sourceUrl: sourceUrl,
      siteUrl: siteUrl,
      description: description,
      iconUrl: iconUrl,
      articles: articles,
    );
  }

  ParsedArticle? _parseRssItem(XmlElement item) {
    final title = _text(item, 'title')?.trim();
    if (title == null || title.isEmpty) {
      return null;
    }

    final link = _text(item, 'link')?.trim();
    final description = _innerHtml(item, 'description');
    final encoded = _innerHtml(item, 'encoded');
    final content = encoded.isNotEmpty ? encoded : description;
    final imageUrl = _imageFromElement(item, content);

    return ParsedArticle(
      title: title,
      link: link,
      author: _text(item, 'author')?.trim() ?? _text(item, 'creator')?.trim(),
      publishedAt: _dateFrom([_text(item, 'pubDate'), _text(item, 'date')]),
      contentHtml: content.isEmpty ? null : content,
      summary: _plainText(content).trim().isEmpty
          ? _text(item, 'description')?.trim()
          : _plainText(content).trim(),
      imageUrl: imageUrl,
      categories: _categories(item),
    );
  }

  List<String>? _categories(XmlElement parent) {
    final result = <String>[];
    for (final child in _children(parent)) {
      if (child.name.local.toLowerCase() == 'category') {
        final value = child.innerText.trim();
        if (value.isNotEmpty) {
          result.add(value);
        }
      }
    }
    return result.isEmpty ? null : result;
  }

  // ---------- Atom ----------

  ParsedFeed _parseAtom(XmlElement root, String sourceUrl) {
    final title = _text(root, 'title')?.trim() ?? sourceUrl;
    final subtitle = _text(root, 'subtitle')?.trim();
    final siteUrl = _atomAlternateLink(root);

    final articles = <ParsedArticle>[];
    for (final entry in _children(
      root,
    ).where((e) => e.name.local.toLowerCase() == 'entry')) {
      final parsed = _parseAtomEntry(entry);
      if (parsed != null) {
        articles.add(parsed);
      }
    }

    return ParsedFeed(
      title: title,
      sourceUrl: sourceUrl,
      siteUrl: siteUrl,
      description: subtitle,
      articles: articles,
    );
  }

  ParsedArticle? _parseAtomEntry(XmlElement entry) {
    final title = _text(entry, 'title')?.trim();
    if (title == null || title.isEmpty) {
      return null;
    }

    final link = _atomAlternateLink(entry);
    final contentElement = _child(entry, 'content');
    final contentHtml = contentElement != null
        ? _innerXml(contentElement)
        : null;

    final summaryElement = _child(entry, 'summary');
    final summaryHtml = summaryElement != null
        ? _innerXml(summaryElement)
        : null;

    final imageUrl = _imageFromElement(entry, contentHtml ?? summaryHtml ?? '');

    final author = _children(entry)
        .where((e) => e.name.local.toLowerCase() == 'author')
        .map((e) => _text(e, 'name')?.trim())
        .whereType<String>()
        .firstOrNull;

    return ParsedArticle(
      title: title,
      link: link,
      author: author,
      publishedAt: _dateFrom([
        _text(entry, 'published'),
        _text(entry, 'updated'),
      ]),
      contentHtml: contentHtml,
      summary: _plainText(summaryHtml ?? contentHtml ?? '').trim().isEmpty
          ? null
          : _plainText(summaryHtml ?? contentHtml ?? '').trim(),
      imageUrl: imageUrl,
      categories: _categories(entry),
    );
  }

  // ---------- Helpers ----------

  Iterable<XmlElement> _children(XmlElement parent) =>
      parent.childElements.whereType<XmlElement>();

  XmlElement? _child(XmlElement parent, String localName) {
    for (final child in _children(parent)) {
      if (child.name.local.toLowerCase() == localName.toLowerCase()) {
        return child;
      }
    }
    return null;
  }

  String? _text(XmlElement parent, String localName) {
    final child = _child(parent, localName);
    return child?.innerText;
  }

  String _innerHtml(XmlElement parent, String localName) {
    final child = _child(parent, localName);
    if (child == null) {
      return '';
    }
    return _innerXml(child);
  }

  String _innerXml(XmlElement element) {
    return element.children
        .map((node) {
          // CDATA 节点不能直接 toXmlString，否则会把 <![CDATA[ ... ]]> 原样带出。
          if (node is XmlCDATA) {
            return node.value;
          }
          if (node is XmlText) {
            return node.value;
          }
          return node.toXmlString();
        })
        .join()
        .trim();
  }

  String? _atomAlternateLink(XmlElement parent) {
    for (final child in _children(parent)) {
      if (child.name.local.toLowerCase() != 'link') {
        continue;
      }
      final rel = child.getAttribute('rel') ?? 'alternate';
      if (rel.toLowerCase() == 'alternate' || rel.toLowerCase() == 'self') {
        final href = child.getAttribute('href');
        if (href != null && href.isNotEmpty) {
          return href;
        }
      }
    }
    return null;
  }

  DateTime? _dateFrom(List<String?> values) {
    for (final value in values) {
      if (value == null || value.trim().isEmpty) {
        continue;
      }
      final parsed = DateTime.tryParse(value.trim());
      if (parsed != null) {
        return parsed;
      }
      try {
        return HttpDate.parse(value.trim());
      } catch (_) {
        // 继续尝试下一个字段。
      }
    }
    return null;
  }

  String? _imageFromElement(XmlElement element, String htmlContent) {
    // media:thumbnail / media:content
    for (final descendant in element.descendants.whereType<XmlElement>()) {
      final localName = descendant.name.local.toLowerCase();
      final url = descendant.getAttribute('url');
      final type = descendant.getAttribute('type') ?? '';
      if (url != null && url.isNotEmpty) {
        if (localName == 'thumbnail' ||
            (localName == 'content' &&
                type.toLowerCase().startsWith('image'))) {
          return url;
        }
      }
    }

    // RSS enclosure image
    for (final child in _children(element)) {
      if (child.name.local.toLowerCase() == 'enclosure') {
        final url = child.getAttribute('url');
        final type = child.getAttribute('type') ?? '';
        if (url != null &&
            url.isNotEmpty &&
            type.toLowerCase().startsWith('image')) {
          return url;
        }
      }
    }

    // HTML 内容中的第一张图片
    final htmlDoc = html_parser.parse(htmlContent);
    final img = htmlDoc.querySelector('img');
    final src = img?.attributes['src'] ?? img?.attributes['data-src'];
    if (src != null && src.isNotEmpty) {
      return _absoluteUrl(src, element);
    }

    return null;
  }

  String? _absoluteUrl(String url, XmlElement context) {
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return url;
    }
    if (url.startsWith('//')) {
      return 'https:$url';
    }
    final base =
        _text(context, 'link')?.trim() ?? _text(context, 'url')?.trim();
    if (base != null) {
      final uri = Uri.tryParse(base);
      if (uri != null) {
        return uri.resolve(url).toString();
      }
    }
    return url;
  }

  String _plainText(String html) {
    if (html.isEmpty) {
      return '';
    }
    final document = html_parser.parse(html);
    final buffer = StringBuffer();

    void walk(html_dom.Node node) {
      if (node is html_dom.Element) {
        if (node.localName == 'script' || node.localName == 'style') {
          return;
        }
        if (node.localName == 'br' ||
            node.localName == 'p' ||
            node.localName == 'div') {
          buffer.write('\n');
        }
      }
      if (node is html_dom.Text) {
        buffer.write(node.text);
      }
      node.nodes.forEach(walk);
    }

    document.nodes.forEach(walk);
    return buffer.toString().replaceAll(RegExp(r'\n{3,}'), '\n\n');
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
