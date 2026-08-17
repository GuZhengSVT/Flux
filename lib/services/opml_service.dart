import 'package:xml/xml.dart';

import '../models/feed.dart';

class OpmlFeed {
  const OpmlFeed({required this.title, required this.xmlUrl, this.category});

  final String title;
  final String xmlUrl;

  /// 分组名；来自嵌套 outline 的外层容器，顶层 feed 为 null。
  final String? category;
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
            final grouped = <String, List<Feed>>{};
            final ungrouped = <Feed>[];

            for (final feed in feeds) {
              final category = feed.category?.trim();
              if (category == null || category.isEmpty) {
                ungrouped.add(feed);
              } else {
                grouped.putIfAbsent(category, () => []).add(feed);
              }
            }

            final sortedCategories = grouped.keys.toList()
              ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
            for (final category in sortedCategories) {
              builder.element(
                'outline',
                attributes: {'text': category, 'title': category},
                nest: () {
                  for (final feed in grouped[category]!) {
                    _writeFeedOutline(builder, feed);
                  }
                },
              );
            }

            for (final feed in ungrouped) {
              _writeFeedOutline(builder, feed);
            }
          },
        );
      },
    );
    return builder.buildDocument().toXmlString(pretty: true, indent: '  ');
  }

  void _writeFeedOutline(XmlBuilder builder, Feed feed) {
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

  List<OpmlFeed> parse(String xml) {
    final document = XmlDocument.parse(xml);
    final result = <OpmlFeed>[];

    final bodies = document.findAllElements('body').toList();
    final topLevelOutlines = bodies.isNotEmpty
        ? bodies.first.childElements.whereType<XmlElement>()
        : document.rootElement.childElements.whereType<XmlElement>();

    for (final outline in topLevelOutlines) {
      _parseOutline(outline, result, null);
    }
    return result;
  }

  void _parseOutline(XmlElement outline, List<OpmlFeed> result, String? group) {
    final xmlUrl =
        outline.getAttribute('xmlUrl') ??
        outline.getAttribute('xmlurl') ??
        outline.getAttribute('XMLURL');

    if (xmlUrl != null && xmlUrl.trim().isNotEmpty) {
      final title =
          outline.getAttribute('title') ??
          outline.getAttribute('text') ??
          xmlUrl;
      final category = group?.trim();
      result.add(
        OpmlFeed(
          title: title.trim(),
          xmlUrl: xmlUrl.trim(),
          category: (category == null || category.isEmpty) ? null : category,
        ),
      );
      return;
    }

    final ownCategory =
        (outline.getAttribute('text') ?? outline.getAttribute('title'))?.trim();
    final nestedGroup = (ownCategory == null || ownCategory.isEmpty)
        ? group
        : ownCategory;

    for (final child in outline.childElements.whereType<XmlElement>()) {
      if (child.name.local.toLowerCase() == 'outline') {
        _parseOutline(child, result, nestedGroup);
      }
    }
  }
}
