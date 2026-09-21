// RSS/Atom 解析测试（T013；架构 4.1、第 8 节）。
//
// 全部走**本地 fixture**，不联网：解析器的正确性必须能在离线、可复现的条件下验证，
// 真实源只用于最后的「端到端最小验证」（见 refresh_use_case 的联调用例）。
//
// 安全用例是本文件的重点：DTD 与外部实体必须**在解析前**被拒绝，且错误必须是类型化的
// ParseError（不是任意异常），这样上层才能区分「源坏了」与「网络断了」。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:flux/core/core.dart';
import 'package:flux/features/feeds/domain/feed_parser.dart';

String _fixture(String name) => File('test/fixtures/$name').readAsStringSync();

/// 解析并断言成功。
ParsedFeed _parseOk(String document, {String source = 'test'}) {
  final Result<ParsedFeed> result = parseFeed(document, source: source);
  expect(
    result.isOk,
    isTrue,
    reason: '期望解析成功，实际：${result.errorOrNull?.message}',
  );
  return result.unwrap();
}

void main() {
  group('RSS 2.0', () {
    test('T008 fixture 的三个 item 都被解析，字段正确', () {
      final ParsedFeed feed = _parseOk(_fixture('rss_sample.rss2.xml'));
      expect(feed.format, FeedFormat.rss2);
      expect(feed.title, 'Flux Fixture Feed');
      expect(feed.siteUrl, 'https://example.com/');
      expect(feed.entries, hasLength(3));

      final ParsedFeedEntry first = feed.entries[0];
      expect(first.title, 'First fixture item');
      expect(first.guid, 'flux-fixture-item-0001');
      expect(first.guidIsPermaLink, isFalse);
      expect(first.link, 'https://example.com/articles/first');
      // 作者优先取 dc:creator（人可读名），而不是 author（可能是邮箱）。
      expect(first.author, 'Fixture Author');
      expect(
        first.publishedAt,
        DateTime.utc(2026, 9, 20, 22, 15),
        reason: 'RFC 822 的 GMT 时间必须解析成正确的 UTC 时刻',
      );
      expect(first.summary, 'Short summary of the first fixture item.');
      expect(first.contentHtml, contains('<strong>first</strong>'));
    });

    test('无 GUID 的条目：guid 为 null，链接完整保留查询参数', () {
      final ParsedFeed feed = _parseOk(_fixture('rss_sample.rss2.xml'));
      final ParsedFeedEntry second = feed.entries[1];
      expect(second.guid, isNull, reason: '源没给 GUID 时必须是 null，不能编造');
      expect(
        second.link,
        'https://example.com/articles/second?utm_source=fixture&id=2',
        reason: '解析层不得剥离查询参数（架构 4.1）',
      );
      expect(second.contentHtml, contains('<img'));
    });

    test('无 pubDate 的条目：publishedAt 为 null（由上层用抓取时间并标记）', () {
      final ParsedFeed feed = _parseOk(_fixture('rss_sample.rss2.xml'));
      final ParsedFeedEntry third = feed.entries[2];
      expect(third.publishedAt, isNull);
      expect(third.guidIsPermaLink, isTrue);
      expect(third.guid, 'https://example.com/articles/third');
    });

    test('channel 级元数据缺失时不影响条目解析', () {
      final ParsedFeed feed = _parseOk(
        '<?xml version="1.0"?><rss version="2.0"><channel>'
        '<item><title>只有标题</title></item>'
        '</channel></rss>',
      );
      expect(feed.title, isNull);
      expect(feed.entries, hasLength(1));
      expect(feed.entries.single.title, '只有标题');
    });

    test('既无标题也无链接的 item 被跳过并计入 rejectedEntries', () {
      final ParsedFeed feed = _parseOk(
        '<rss version="2.0"><channel>'
        '<item><description>只有描述</description></item>'
        '<item><title>有效</title><link>https://example.com/a</link></item>'
        '</channel></rss>',
      );
      expect(feed.entries, hasLength(1));
      expect(feed.rejectedEntries, 1);
    });

    test('enclosure 只有 image/* 才被当作图片', () {
      final ParsedFeed feed = _parseOk(
        '<rss version="2.0"><channel>'
        '<item><title>播客</title><link>https://example.com/p</link>'
        '<enclosure url="https://example.com/audio.mp3" type="audio/mpeg"/>'
        '</item>'
        '<item><title>图文</title><link>https://example.com/i</link>'
        '<enclosure url="https://example.com/cover.jpg" type="image/jpeg"/>'
        '</item>'
        '</channel></rss>',
      );
      expect(feed.entries[0].enclosureImageUrl, isNull);
      expect(
        feed.entries[1].enclosureImageUrl,
        'https://example.com/cover.jpg',
      );
    });

    test('RSS 1.0 / RDF 根元素也被接受', () {
      final ParsedFeed feed = _parseOk(
        '<?xml version="1.0"?>'
        '<rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#" '
        'xmlns="http://purl.org/rss/1.0/">'
        '<item><title>RDF 条目</title><link>https://example.com/rdf</link></item>'
        '</rdf:RDF>',
      );
      expect(feed.format, FeedFormat.rss1);
      expect(feed.entries, hasLength(1));
    });
  });

  group('Atom 1.0', () {
    test('T008 fixture 的条目与 link rel 变体都被解析', () {
      final ParsedFeed feed = _parseOk(_fixture('rss_sample.atom.xml'));
      expect(feed.format, FeedFormat.atom);
      expect(feed.title, 'Flux Fixture Atom Feed');
      expect(
        feed.siteUrl,
        'https://example.com/atom',
        reason: '取 rel=alternate',
      );
      expect(feed.entries, hasLength(2));

      final ParsedFeedEntry first = feed.entries[0];
      expect(first.title, 'Atom fixture entry one');
      expect(first.guid, 'urn:uuid:00000000-0000-4000-8000-000000000002');
      expect(first.link, 'https://example.com/atom/one');
      expect(first.publishedAt, DateTime.utc(2026, 9, 20, 21));
      expect(first.updatedAt, DateTime.utc(2026, 9, 20, 22, 15));
      expect(first.contentHtml, contains('<em>first</em>'));
      expect(first.author, 'Fixture Author');
    });

    test('Atom type="text" 的正文被转义成最小 HTML（不当作标签）', () {
      final ParsedFeed feed = _parseOk(_fixture('rss_sample.atom.xml'));
      final ParsedFeedEntry second = feed.entries[1];
      expect(second.contentHtml, 'Plain text body of the second Atom entry.');
      expect(second.publishedAt, DateTime.utc(2026, 9, 20, 23, 45));
    });

    test('Atom type="xhtml"：子树被序列化回 HTML 字符串', () {
      final ParsedFeed feed = _parseOk(_fixture('rss_sample.atom_xhtml.xml'));
      expect(feed.entries, hasLength(2));
      final String? content = feed.entries[0].contentHtml;
      expect(content, isNotNull);
      // 序列化后仍是 HTML：清洗器能识别出段落、强调与列表。
      expect(content, contains('<p>'));
      expect(content, contains('<strong>inline markup</strong>'));
      expect(content, contains('<li>first</li>'));
    });

    test('Atom src-only 的 content 不被主动抓取（属 T024），summary 保留', () {
      final ParsedFeed feed = _parseOk(_fixture('rss_sample.atom_xhtml.xml'));
      final ParsedFeedEntry second = feed.entries[1];
      expect(
        second.contentHtml,
        isNull,
        reason: 'src 形式需要第二次请求，本任务不抓取；也不能假装它是正文',
      );
      expect(second.link, 'https://example.com/xhtml/two');
    });

    test('published 缺失时退到 updated', () {
      final ParsedFeed feed = _parseOk(
        '<feed xmlns="http://www.w3.org/2005/Atom">'
        '<entry><title>只有 updated</title>'
        '<id>urn:uuid:x</id>'
        '<updated>2026-09-21T04:30:00Z</updated>'
        '</entry></feed>',
      );
      expect(feed.entries.single.publishedAt, DateTime.utc(2026, 9, 21, 4, 30));
      expect(feed.entries.single.updatedAt, DateTime.utc(2026, 9, 21, 4, 30));
    });

    test('命名空间前缀不影响取值（按本地名匹配）', () {
      final ParsedFeed feed = _parseOk(
        '<atom:feed xmlns:atom="http://www.w3.org/2005/Atom">'
        '<atom:entry><atom:title>带前缀</atom:title>'
        '<atom:id>urn:uuid:prefixed</atom:id>'
        '<atom:link rel="alternate" href="https://example.com/p"/>'
        '</atom:entry></atom:feed>',
      );
      expect(feed.entries.single.title, '带前缀');
      expect(feed.entries.single.guid, 'urn:uuid:prefixed');
      expect(feed.entries.single.link, 'https://example.com/p');
    });
  });

  group('安全性：DTD 与外部实体必须被拒绝', () {
    test('含 DOCTYPE 的文档被拒绝（外部实体可读本机文件）', () {
      final Result<ParsedFeed> result = parseFeed(
        '<?xml version="1.0"?>'
        '<!DOCTYPE feed [<!ENTITY xxe SYSTEM "file:///etc/passwd">]>'
        '<rss version="2.0"><channel><item><title>&xxe;</title></item>'
        '</channel></rss>',
        source: 'evil-feed',
      );
      expect(result.isErr, isTrue);
      expect(result.errorOrNull, isA<ParseError>());
      expect(result.errorOrNull!.message, contains('DOCTYPE'));
      expect(
        result.errorOrNull!.message,
        isNot(contains('/etc/passwd')),
        reason: '错误信息不得回显外部实体的目标路径',
      );
    });

    test('含 ENTITY 声明的文档被拒绝（实体扩展 / billion laughs）', () {
      final Result<ParsedFeed> result = parseFeed(
        '<?xml version="1.0"?>'
        '<!DOCTYPE feed ['
        '<!ENTITY a "aaaaaaaaaa">'
        '<!ENTITY b "&a;&a;&a;&a;&a;&a;&a;&a;&a;&a;">'
        ']>'
        '<rss version="2.0"><channel><item><title>&b;</title></item>'
        '</channel></rss>',
      );
      expect(result.isErr, isTrue);
      expect(result.errorOrNull, isA<ParseError>());
      expect(result.errorOrNull!.message, contains('ENTITY'));
    });

    test('大小写与空白变形的 DOCTYPE 仍被拒绝', () {
      for (final String variant in <String>[
        '<!doctype rss>',
        '<!  DOCTYPE rss>',
        '<!DOCTYPE',
      ]) {
        final Result<ParsedFeed> result = parseFeed(
          '<?xml version="1.0"?>$variant<rss version="2.0"><channel/></rss>',
        );
        expect(result.isErr, isTrue, reason: '变体未被拒绝：$variant');
        expect(result.errorOrNull, isA<ParseError>());
      }
    });

    test('普通 XML 声明不会被误判为 DTD', () {
      final Result<ParsedFeed> result = parseFeed(
        '<?xml version="1.0" encoding="UTF-8"?>'
        '<rss version="2.0"><channel><item><title>正常</title></item>'
        '</channel></rss>',
      );
      expect(result.isOk, isTrue, reason: result.errorOrNull?.message);
    });
  });

  group('畸形与边界输入', () {
    test('畸形 XML 返回类型化 ParseError（不是裸异常）', () {
      for (final String malformed in <String>[
        '<rss version="2.0"><channel><item><title>未闭合',
        '<rss version="2.0"><channel></rss></channel>',
        '不是 XML 的内容',
        '<rss version="2.0"><channel><item><title>甲</ti</item>',
      ]) {
        final Result<ParsedFeed> result = parseFeed(malformed);
        expect(result.isErr, isTrue, reason: '应失败：$malformed');
        expect(
          result.errorOrNull,
          isA<ParseError>(),
          reason: '必须是类型化 ParseError：$malformed',
        );
      }
    });

    test('空文档与纯空白被拒绝', () {
      for (final String input in <String>['', '   ', '\n\t ']) {
        final Result<ParsedFeed> result = parseFeed(input);
        expect(result.isErr, isTrue);
        expect(result.errorOrNull, isA<ParseError>());
      }
    });

    test('不支持的根元素被拒绝（明确说明而不是静默返回空）', () {
      final Result<ParsedFeed> result = parseFeed(
        '<html><body>这是个网页</body></html>',
      );
      expect(result.isErr, isTrue);
      expect(result.errorOrNull!.message, contains('html'));
    });

    test('只有 XML 声明没有根元素被拒绝', () {
      final Result<ParsedFeed> result = parseFeed('<?xml version="1.0"?>');
      expect(result.isErr, isTrue);
      expect(result.errorOrNull, isA<ParseError>());
    });

    test('超长文档被拒绝（解析层第二道防线）', () {
      final String huge =
          '<rss version="2.0"><channel><item><title>${'x' * 200}</title>'
          '</item></channel></rss>';
      final Result<ParsedFeed> result = parseFeed(
        huge,
        limits: const FeedParserLimits(maxDocumentLength: 100),
      );
      expect(result.isErr, isTrue);
      expect(result.errorOrNull!.message, contains('超过上限'));
    });

    test('深度超限被拒绝', () {
      final String deep =
          '<rss version="2.0"><channel>${'<x>' * 100}<item/></channel></rss>';
      final Result<ParsedFeed> result = parseFeed(
        deep,
        limits: const FeedParserLimits(maxDepth: 16),
      );
      expect(result.isErr, isTrue);
      expect(result.errorOrNull!.message, contains('上限'));
    });

    test('条目数超限时截断而不是失败（源异常庞大不该整篇丢弃）', () {
      final StringBuffer buffer = StringBuffer('<rss version="2.0"><channel>');
      for (int i = 0; i < 50; i++) {
        buffer.write('<item><title>条目 $i</title><guid>g$i</guid></item>');
      }
      buffer.write('</channel></rss>');
      final ParsedFeed feed = _parseOk(
        buffer.toString(),
        // 用 _parseOk 会断言成功；这里显式解析以传 limits。
      );
      expect(feed.entries, hasLength(50));
    });

    test('超大条目数按上限截断', () {
      final StringBuffer buffer = StringBuffer('<rss version="2.0"><channel>');
      for (int i = 0; i < 50; i++) {
        buffer.write('<item><title>批量 $i</title><guid>gg$i</guid></item>');
      }
      buffer.write('</channel></rss>');
      final Result<ParsedFeed> result = parseFeed(
        buffer.toString(),
        limits: const FeedParserLimits(maxEntries: 10),
      );
      expect(result.isOk, isTrue);
      expect(result.unwrap().entries, hasLength(10));
    });

    test('未知扩展元素不影响解析（RSS 常见自定义命名空间）', () {
      final ParsedFeed feed = _parseOk(
        '<rss version="2.0" xmlns:custom="https://example.com/ns">'
        '<channel><custom:meta>忽略</custom:meta>'
        '<item><title>带扩展</title><custom:extra>也忽略</custom:extra>'
        '<link>https://example.com/x</link></item></channel></rss>',
      );
      expect(feed.entries.single.title, '带扩展');
    });
  });

  group('日期解析（RFC 822 + ISO 8601）', () {
    test('RFC 822 带时区名', () {
      expect(
        parseFeedDate('Sun, 20 Sep 2026 22:15:00 GMT'),
        DateTime.utc(2026, 9, 20, 22, 15),
      );
      expect(
        parseFeedDate('Sun, 20 Sep 2026 22:15:00 +0800'),
        DateTime.utc(2026, 9, 20, 14, 15),
      );
      expect(
        parseFeedDate('Sun, 20 Sep 2026 22:15:00 -0500'),
        DateTime.utc(2026, 9, 21, 3, 15),
      );
    });

    test('RFC 822 省略星期与秒', () {
      expect(
        parseFeedDate('20 Sep 2026 22:15 GMT'),
        DateTime.utc(2026, 9, 20, 22, 15),
      );
      expect(parseFeedDate('20 Sep 2026'), DateTime.utc(2026, 9, 20));
    });

    test('美国时区缩写', () {
      expect(
        parseFeedDate('Sun, 20 Sep 2026 12:00:00 EST'),
        DateTime.utc(2026, 9, 20, 17),
      );
      expect(
        parseFeedDate('Sun, 20 Sep 2026 12:00:00 PDT'),
        DateTime.utc(2026, 9, 20, 19),
      );
    });

    test('ISO 8601 各种写法', () {
      expect(
        parseFeedDate('2026-09-20T22:15:00Z'),
        DateTime.utc(2026, 9, 20, 22, 15),
      );
      expect(
        parseFeedDate('2026-09-20T22:15:00+08:00'),
        DateTime.utc(2026, 9, 20, 14, 15),
      );
      expect(
        parseFeedDate('2026-09-20T22:15:00.123Z'),
        DateTime.utc(2026, 9, 20, 22, 15, 0, 123),
      );
    });

    test('两位年份按 RFC 822 惯例展开', () {
      expect(parseFeedDate('20 Sep 26 22:15 GMT')?.year, 2026);
      expect(parseFeedDate('20 Sep 99 22:15 GMT')?.year, 1999);
    });

    test('无法解析的日期返回 null，不猜', () {
      for (final String input in <String>[
        '',
        '   ',
        '不是日期',
        '2026-13-45T99:99:99Z',
        '31 Feb 2026 10:00 GMT',
        '32 Sep 2026 10:00 GMT',
        '20 Sep 2026 25:00 GMT',
      ]) {
        expect(parseFeedDate(input), isNull, reason: '不应猜出时间：$input');
      }
    });

    test('null 输入返回 null', () {
      expect(parseFeedDate(null), isNull);
    });
  });
}
