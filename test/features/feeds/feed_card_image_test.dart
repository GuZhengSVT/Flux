// 卡片图片地址的来源与安全口径（T019+，配合架构第 7 节的三种卡片形态）。
//
// 这一列的值会被卡片直接交给图片加载器，因此它是**边界**而不是展示细节。断言三件事：
//
//   1) 源内 enclosure 优先于正文首图（enclosure 是源显式声明的封面）；
//   2) 两种来源都必须通过 isSafeDocUrl——enclosure 走的是与正文图片不同的代码路径，
//      因此在这里再判一次是收口，不是重复；
//   3) 没有图时返回 null（**不是**空串或占位地址）：架构第 7 节要求缺图不占位，
//      「没有图」与「有图地址」必须是两种可区分的事实。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:flux/core/core.dart';
import 'package:flux/features/feeds/domain/content_sanitizer.dart';
import 'package:flux/features/feeds/domain/feed_import_builder.dart';
import 'package:flux/features/feeds/domain/feed_parser.dart';

/// 造一个只有图片相关字段有意义的解析条目。
ParsedFeedEntry _entry({
  String? enclosureImageUrl,
  String? summary = '摘要',
  List<String> bodyImages = const <String>[],
}) => ParsedFeedEntry(
  title: '标题',
  summary: summary,
  enclosureImageUrl: enclosureImageUrl,
  contentHtml: bodyImages.isEmpty
      ? null
      : bodyImages
            .map((String url) => '<p><img src="$url" alt="图"></p>')
            .join(),
);

/// 把一段 HTML 跑真实清洗器，得到正文文档（与导入路径同一个函数）。
DocDocument _documentOf(ParsedFeedEntry entry) {
  return sanitizeHtmlToDocument(entry.contentHtml).document;
}

void main() {
  group('卡片图片地址（enclosure 优先，均需通过安全判定）', () {
    test('源内 enclosure 被采用', () {
      final ParsedFeedEntry entry = _entry(
        enclosureImageUrl: 'https://cdn.example.com/enclosure.png',
      );
      expect(
        feedEntryImageUrl(entry, _documentOf(entry)),
        'https://cdn.example.com/enclosure.png',
      );
    });

    test('没有 enclosure 时用正文第一张图', () {
      final ParsedFeedEntry entry = _entry(
        bodyImages: <String>[
          'https://cdn.example.com/first.png',
          'https://cdn.example.com/second.png',
        ],
      );
      expect(
        feedEntryImageUrl(entry, _documentOf(entry)),
        'https://cdn.example.com/first.png',
        reason: '正文里有多张图时取第一张',
      );
    });

    test('enclosure 优先于正文首图（源声明过的封面胜过正文配图）', () {
      final ParsedFeedEntry entry = _entry(
        enclosureImageUrl: 'https://cdn.example.com/enclosure.png',
        bodyImages: <String>['https://cdn.example.com/body.png'],
      );
      expect(
        feedEntryImageUrl(entry, _documentOf(entry)),
        'https://cdn.example.com/enclosure.png',
      );
    });

    test('危险的 enclosure 地址被拒绝，退到正文首图', () {
      final ParsedFeedEntry entry = _entry(
        // enclosure 走的是源文件属性那条路径，清洗器管不到它。
        enclosureImageUrl: 'javascript:alert(1)',
        bodyImages: <String>['https://cdn.example.com/body.png'],
      );
      expect(
        feedEntryImageUrl(entry, _documentOf(entry)),
        'https://cdn.example.com/body.png',
        reason: '危险协议不得进入卡片图片列，但正文里的安全图片仍可用',
      );
    });

    test('两边都不安全时返回 null（缺图不占位）', () {
      final ParsedFeedEntry entry = _entry(
        enclosureImageUrl: 'file:///etc/passwd',
        bodyImages: <String>['data:image/png;base64,AAAA'],
      );
      expect(feedEntryImageUrl(entry, _documentOf(entry)), isNull);
    });

    test('完全没有图时返回 null', () {
      final ParsedFeedEntry entry = _entry();
      expect(feedEntryImageUrl(entry, _documentOf(entry)), isNull);
    });
  });
}
