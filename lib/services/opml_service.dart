import 'package:xml/xml.dart';

import '../models/feed.dart';

class OpmlFeed {
  const OpmlFeed({required this.title, required this.xmlUrl});

  final String title;
  final String xmlUrl;
}

/// OPML 2.0 导入 / 导出。
class OpmlService {
  const OpmlService();

  String export(List<Feed> feeds) {
    final builder = XmlBuilder();
    builder.processing('xml', 'version="1.0" encoding="UTF-8"');
    builder.element(
      'opml',
      attributes: {'version': '2.0'},
      nest: () {
        builder.element(
          'head',
          nest: () {
            builder.element(
              'title',
              nest: () {
                builder.text('Flux Feeds');
              },
            );
          },
        );
        builder.element(
          'body',
          nest: () {
            for (final feed in feeds) {
              builder.element(
                'outline',
                attributes: {
                  'text': feed.title,
                  'title': feed.title,
                  'type': 'rss',
                  'xmlUrl': feed.url,
                },
              );
            }
          },
        );
      },
    );
    return builder.buildDocument().toXmlString(pretty: true, indent: '  ');
  }

  List<OpmlFeed> parse(String xml) {
    final document = XmlDocument.parse(xml);
    final result = <OpmlFeed>[];
    for (final outline in document.findAllElements('outline')) {
      final xmlUrl =
          outline.getAttribute('xmlUrl') ?? outline.getAttribute('xmlurl');
      if (xmlUrl == null || xmlUrl.trim().isEmpty) {
        continue;
      }
      final title =
          outline.getAttribute('title') ??
          outline.getAttribute('text') ??
          xmlUrl;
      result.add(OpmlFeed(title: title.trim(), xmlUrl: xmlUrl.trim()));
    }
    return result;
  }
}
