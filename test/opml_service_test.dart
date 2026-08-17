import 'package:test/test.dart';

import 'package:flux/models/feed.dart';
import 'package:flux/services/opml_service.dart';

void main() {
  test('OPML export preserves groups and parse round-trips', () {
    const service = OpmlService();
    final feeds = [
      const Feed(title: 'A', url: 'https://a/feed', category: 'Tech'),
      const Feed(title: 'B', url: 'https://b/feed', category: 'Tech'),
      const Feed(title: 'C', url: 'https://c/feed'),
    ];
    final xml = service.export(feeds);
    final parsed = service.parse(xml);
    expect(parsed, hasLength(3));
    expect(parsed.where((f) => f.category == 'Tech'), hasLength(2));
    expect(parsed.where((f) => f.category == null), hasLength(1));
  });

  test('OPML parse handles legacy flat outline', () {
    const xml = '''
    <opml version="2.0">
      <body>
        <outline text="Flat" title="Flat" type="rss" xmlUrl="https://flat/feed"/>
      </body>
    </opml>
    ''';
    final parsed = const OpmlService().parse(xml);
    expect(parsed, hasLength(1));
    expect(parsed.first.category, isNull);
  });
}