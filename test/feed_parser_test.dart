import 'package:test/test.dart';

import 'package:flux/services/feed_parser.dart';

void main() {
  test('FeedParser parses RSS 2.0', () {
    const xml = '''
    <rss version="2.0">
      <channel>
        <title>Example Feed</title>
        <link>https://example.com</link>
        <description>Example Description</description>
        <item>
          <title>Hello Flux</title>
          <link>https://example.com/hello</link>
          <description><![CDATA[<p>Hello <b>world</b></p>]]></description>
          <pubDate>Wed, 02 Oct 2024 08:00:00 GMT</pubDate>
          <category>Tech</category>
        </item>
      </channel>
    </rss>
    ''';

    final parsed = const FeedParser().parse(
      xml,
      'https://example.com/feed.xml',
    );

    expect(parsed.title, 'Example Feed');
    expect(parsed.articles, hasLength(1));
    expect(parsed.articles.first.title, 'Hello Flux');
    expect(parsed.articles.first.link, 'https://example.com/hello');
    expect(parsed.articles.first.categories, ['Tech']);
    expect(parsed.articles.first.publishedAt, isNotNull);
  });

  test('FeedParser parses Atom CDATA without leaking ]]>', () {
    const xml = '''
    <feed xmlns="http://www.w3.org/2005/Atom">
      <title>Example Atom</title>
      <entry>
        <title>Atom Entry</title>
        <link href="https://example.com/atom-entry"/>
        <content type="html"><![CDATA[<p>Hello</p>]]>
        <![CDATA[<p>World</p>]]></content>
      </entry>
    </feed>
    ''';

    final parsed = const FeedParser().parse(
      xml,
      'https://example.com/atom.xml',
    );

    expect(parsed.articles, hasLength(1));
    final content = parsed.articles.first.contentHtml ?? '';
    expect(content, isNot(contains(']]>')));
    expect(content, contains('<p>Hello</p>'));
    expect(content, contains('<p>World</p>'));
  });
}