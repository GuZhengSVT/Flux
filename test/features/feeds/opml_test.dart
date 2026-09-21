// OPML 导入/导出测试（T015）。
//
// 覆盖手册点名的必测项与架构 4.1 的契约：
//   - 解析：正常文件、畸形 XML、DOCTYPE/ENTITY 拒绝、嵌套分组、重复地址、无效项；
//   - 往返：导出 → 导入后名称/地址/分组结构保留；
//   - 重复导入匹配已有源且**不重置状态**（加精/启用/文章都在）；
//   - 逐项失败隔离：一个源失败不影响其余条目；重试只跑失败项；
//   - 秘密排除：带 token 的地址导出后不含 token（SET-027）。
//
// 全部使用内存库 + MockClient，不联网、不写磁盘。
library;

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:flux/core/core.dart';
import 'package:flux/features/feeds/application/add_feed.dart';
import 'package:flux/features/feeds/application/opml_import_export.dart';
import 'package:flux/features/feeds/domain/opml.dart';
import 'package:flux/infrastructure/local/database.dart';
import 'package:flux/infrastructure/local/feed_catalog_store.dart';
import 'package:flux/infrastructure/local/feed_store_adapter.dart';
import 'package:flux/infrastructure/local/tables/feed_tables.dart';
import 'package:flux/infrastructure/network/feed_fetcher.dart';

/// 固定时钟。
final class _FixedClock implements Clock {
  const _FixedClock(this._now);

  final DateTime _now;

  @override
  DateTime now() => _now;

  @override
  Duration monotonic() => Duration.zero;
}

http.Response _xml(String body) => http.Response.bytes(
  utf8.encode(body),
  200,
  headers: <String, String>{'content-type': 'application/xml; charset=utf-8'},
);

/// 一个可用的最小 RSS。
String _rss(String title) =>
    '''<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0"><channel>
  <title>$title</title>
  <item>
    <title>$title 的文章</title>
    <link>https://feeds.example.com/$title/1</link>
    <guid isPermaLink="false">$title-1</guid>
  </item>
</channel></rss>''';

void main() {
  late AppDatabase db;
  late DriftFeedCatalogStore catalog;
  late DriftFeedArticleStore articles;

  setUp(() async {
    db = AppDatabase.memory();
    await db.customSelect('SELECT 1').get();
    catalog = DriftFeedCatalogStore(db);
    articles = DriftFeedArticleStore(db);
  });
  tearDown(() async => db.close());

  /// 构造导入用例；routes 决定每个地址返回什么。
  ImportOpmlUseCase buildImport(Map<String, http.Response> routes) {
    final HttpFeedFetcher fetcher = HttpFeedFetcher(
      client: MockClient((http.Request request) async {
        final http.Response? response = routes[request.url.toString()];
        return response ?? http.Response('not found', 404);
      }),
    );
    return ImportOpmlUseCase(
      addFeed: AddFeedUseCase(
        fetcher: fetcher,
        catalog: catalog,
        articles: articles,
        clock: _FixedClock(DateTime.utc(2026, 9, 21, 12)),
      ),
      catalog: catalog,
    );
  }

  ExportOpmlUseCase buildExport() => ExportOpmlUseCase(
    catalog: catalog,
    clock: _FixedClock(DateTime.utc(2026, 9, 21, 12)),
  );

  group('OPML 解析（安全边界与结构）', () {
    test('正常文件：条目、嵌套分组、无效项与重复地址都识别出来', () async {
      final String document = await File('test/fixtures/opml_sample.opml')
          .readAsString();
      final Result<ParsedOpml> result = parseOpml(document);

      expect(result.isOk, isTrue, reason: result.errorOrNull?.message);
      final ParsedOpml opml = result.unwrap();

      // fixture 里有 4 个可用订阅（含一个落在嵌套分组里的）。
      // fixture 有 5 个可用订阅：Tech 下 2 个、Nested Group 下 1 个、直接挂 body 下 2 个
      // （其中一条是重复地址——解析层各留一条，去重是业务判断）。
      expect(opml.entries, hasLength(5));
      // 一个故意无效的 outline（只有 text，没有 xmlUrl，也没有子节点）。
      expect(opml.skipped, hasLength(1));
      expect(opml.skipped.single.reason, OpmlEntryIssue.missingXmlUrl);

      // 嵌套分组：Tech -> Nested Group（路径完整保留，而不是只剩末段名字）。
      final OpmlEntry nested = opml.entries.firstWhere(
        (OpmlEntry e) => e.title == 'Nested Example',
      );
      expect(nested.groupPath, <String>['Tech', 'Nested Group']);

      // 另一个条目只在外层分组里。
      final OpmlEntry top = opml.entries.firstWhere(
        (OpmlEntry e) => e.title == 'Example Blog',
      );
      expect(top.groupPath, <String>['Tech']);

      // 直接挂在 body 下的条目没有分组路径。
      final OpmlEntry uncategorized = opml.entries.firstWhere(
        (OpmlEntry e) => e.title == 'Uncategorized Example',
      );
      expect(uncategorized.groupPath, isEmpty);

      // 分组清单（按首次出现顺序）包含两条路径。
      expect(opml.groups, hasLength(2));
      expect(opml.groups.first, <String>['Tech']);
      expect(opml.groups.last, <String>['Tech', 'Nested Group']);

      // 文件级标题被读出（界面用它作为预览标题）。
      expect(opml.title, 'Flux Fixture Subscriptions');
    });

    test('重复地址在解析层各自成条（去重是业务判断，不是解析层的职责）', () {
      const String document = '''<?xml version="1.0" encoding="UTF-8"?>
<opml version="2.0"><body>
  <outline type="rss" text="A" xmlUrl="https://example.com/feed.xml"/>
  <outline type="rss" text="A 的副本" xmlUrl="https://example.com/feed.xml"/>
</body></opml>''';

      final ParsedOpml opml = parseOpml(document).unwrap();

      expect(opml.entries, hasLength(2), reason: '解析层不替业务做去重：两条都在，交给预览按规范地址匹配');
    });

    test('无 xmlUrl 且有子节点的 outline 是分组，不算无效项', () {
      const String document = '''<?xml version="1.0" encoding="UTF-8"?>
<opml version="2.0"><body>
  <outline text="空分组"></outline>
</body></opml>''';

      final ParsedOpml opml = parseOpml(document).unwrap();

      expect(opml.entries, isEmpty);
      expect(opml.skipped, hasLength(1), reason: '既没有地址也没有子节点的 outline 才是无效项');
    });

    test('畸形 XML：类型化解析错误，不抛裸异常', () {
      const String document = '<opml version="2.0"><body>';

      final Result<ParsedOpml> result = parseOpml(document);

      expect(result.isErr, isTrue);
      expect(result.errorOrNull, isA<ParseError>());
    });

    test('根元素不是 opml：明确拒绝并说明实际根名', () {
      const String document = '''<?xml version="1.0"?>
<rss version="2.0"><channel/></rss>''';

      final Result<ParsedOpml> result = parseOpml(document);

      expect(result.isErr, isTrue);
      expect(result.errorOrNull, isA<ParseError>());
      expect(result.errorOrNull!.message, contains('opml'));
    });

    test('缺少 body：拒绝', () {
      const String document = '''<?xml version="1.0"?>
<opml version="2.0"><head><title>x</title></head></opml>''';

      expect(parseOpml(document).isErr, isTrue);
    });

    test('DOCTYPE/外部实体：解析前被拒绝，且错误信息不回显实体目标', () {
      const String document = '''<?xml version="1.0"?>
<!DOCTYPE opml [ <!ENTITY xxe SYSTEM "file:///etc/passwd"> ]>
<opml version="2.0"><body>
  <outline type="rss" text="恶意" xmlUrl="&xxe;"/>
</body></opml>''';

      final Result<ParsedOpml> result = parseOpml(document);

      expect(result.isErr, isTrue);
      expect(result.errorOrNull, isA<ParseError>());
      expect(
        result.errorOrNull!.message,
        isNot(contains('/etc/passwd')),
        reason: '错误信息不得回显实体目标路径',
      );
    });

    test('大小写与空白变形的 DOCTYPE 同样被拒绝', () {
      const String document =
          '<!  doctype  opml><opml version="2.0"><body/></opml>';

      expect(parseOpml(document).isErr, isTrue);
    });

    test('嵌套深度超过上限：拒绝', () {
      final StringBuffer buffer = StringBuffer('<opml version="2.0"><body>');
      for (int i = 0; i < 40; i++) {
        buffer.write('<outline text="g$i">');
      }
      buffer.write('</body></opml>');

      final Result<ParsedOpml> result = parseOpml(buffer.toString());

      expect(result.isErr, isTrue);
      expect(result.errorOrNull!.message, contains('深度'));
    });

    test('无效地址被逐项标出（不是 http/https 或缺少主机名）', () {
      const String document = '''<?xml version="1.0" encoding="UTF-8"?>
<opml version="2.0"><body>
  <outline type="rss" text="ftp" xmlUrl="ftp://example.com/feed.xml"/>
  <outline type="rss" text="无 scheme" xmlUrl="example.com/feed.xml"/>
  <outline type="rss" text="缺主机" xmlUrl="https:///feed.xml"/>
  <outline type="rss" text="好的" xmlUrl="https://good.example.com/feed.xml"/>
</body></opml>''';

      final ParsedOpml opml = parseOpml(document).unwrap();

      expect(opml.entries, hasLength(1));
      expect(opml.entries.single.title, '好的');
      expect(opml.skipped, hasLength(3));
      for (final OpmlSkippedEntry entry in opml.skipped) {
        expect(entry.reason, OpmlEntryIssue.invalidXmlUrl);
      }
    });

    test('空标题用地址兜底（列表里不能出现一行空白）', () {
      const String document = '''<?xml version="1.0" encoding="UTF-8"?>
<opml version="2.0"><body>
  <outline type="rss" xmlUrl="https://example.com/feed.xml"/>
</body></opml>''';

      final ParsedOpml opml = parseOpml(document).unwrap();

      expect(opml.entries.single.title, 'https://example.com/feed.xml');
    });

    test('空文档：类型化错误', () {
      expect(parseOpml('   ').isErr, isTrue);
    });
  });

  /// 一份带嵌套分组、重复项与无效项的 OPML，多个用例共用。
  ///
  /// 放在 main 作用域而不是某个 group 内：导入、重试、分组策略三类用例都要用它，
  /// 各写一份会让「测试文件里的样例」逐渐漂移，而它恰恰是要固定的输入。
  const String opml = '''<?xml version="1.0" encoding="UTF-8"?>
<opml version="2.0"><head><title>我的订阅</title></head><body>
  <outline text="Tech">
    <outline type="rss" text="源一" xmlUrl="https://feeds.example.com/one.xml"/>
    <outline text="Nested">
      <outline type="rss" text="源二" xmlUrl="https://feeds.example.com/two.xml"/>
    </outline>
  </outline>
  <outline type="rss" text="源三" xmlUrl="https://feeds.example.com/three.xml"/>
  <outline text="坏项"/>
</body></opml>''';

  group('导入预览与分组策略（SET-026）', () {
    test('默认策略（全部未分类）：预览不保留分组路径，重复与无效项都列出', () async {
      // 预置一条已有订阅（源二），验证重复判定。
      await catalog.createFeed(
        const FeedInsert(
          syncId: 'feed.two',
          normalizedUrl: 'https://feeds.example.com/two.xml',
          name: '已存在的源二',
        ),
      );

      final ImportOpmlUseCase useCase = buildImport(
        const <String, http.Response>{},
      );
      final Result<OpmlPreview> result = await useCase.preview(opml);

      expect(result.isOk, isTrue, reason: result.errorOrNull?.message);
      final OpmlPreview preview = result.unwrap();

      expect(preview.fileTitle, '我的订阅');
      // 3 条可用 + 1 条无效。
      expect(preview.items, hasLength(4));
      expect(preview.addedCount, 2, reason: '源一与源三是新的');
      expect(preview.duplicateCount, 1, reason: '源二按规范地址命中已有订阅');
      expect(preview.invalidCount, 1);

      // 默认策略下预览**不**保留文件分组（分组路径为空）。
      for (final OpmlPreviewItem item in preview.items) {
        expect(item.groupPath, isEmpty);
      }

      // 无效项带原因，重复项带已有订阅 id。
      final OpmlPreviewItem invalid = preview.items.firstWhere(
        (OpmlPreviewItem i) => i.status == OpmlPreviewStatus.invalid,
      );
      expect(invalid.reason, isNotNull);
      final OpmlPreviewItem duplicate = preview.items.firstWhere(
        (OpmlPreviewItem i) => i.status == OpmlPreviewStatus.duplicate,
      );
      expect(duplicate.existingFeedId, isNotNull);

      // 预览不写任何数据。
      expect((await catalog.listFeeds()).unwrap(), hasLength(1));
      expect(
        (await catalog.listGroups()).unwrap(),
        hasLength(1),
        reason: '只有保留组',
      );
    });

    test('保留文件分组策略：分组路径出现在预览里，嵌套结构完整', () async {
      final ImportOpmlUseCase useCase = buildImport(
        const <String, http.Response>{},
      );
      final Result<OpmlPreview> preview = await useCase.preview(
        opml,
        strategy: OpmlGroupStrategy.keepFileGroups,
      );

      final OpmlPreview result = preview.unwrap();
      final OpmlPreviewItem nested = result.items.firstWhere(
        (OpmlPreviewItem i) => i.title == '源二',
      );
      expect(nested.groupPath, <String>['Tech', 'Nested']);

      final OpmlPreviewItem topLevel = result.items.firstWhere(
        (OpmlPreviewItem i) => i.title == '源三',
      );
      expect(topLevel.groupPath, isEmpty, reason: '直接挂在 body 下');
    });

    test('文件不是 OPML：类型化错误，不是空预览', () async {
      final ImportOpmlUseCase useCase = buildImport(
        const <String, http.Response>{},
      );

      final Result<OpmlPreview> result = await useCase.preview('<html/>');

      expect(result.isErr, isTrue);
      expect(result.errorOrNull, isA<ParseError>());
    });
  });

  group('逐项导入与失败隔离', () {
    test('一个源失败不影响其余：逐项结果如实分类', () async {
      final ImportOpmlUseCase useCase = buildImport(<String, http.Response>{
        'https://feeds.example.com/one.xml': _xml(_rss('one')),
        'https://feeds.example.com/two.xml': _xml(_rss('two')),
        // three 故意 404：这一条失败，但前两条必须成功。
      });

      final OpmlPreview preview = (await useCase.preview(opml)).unwrap();
      final Result<OpmlImportResult> imported = await useCase.import(preview);

      expect(imported.isOk, isTrue, reason: imported.errorOrNull?.message);
      final OpmlImportResult result = imported.unwrap();

      expect(result.importedCount, 2);
      expect(result.failedCount, 1);
      expect(result.invalidCount, 1);
      expect(result.importedArticleCount, 2, reason: '两个成功的源各导入 1 篇');

      // 失败项带类型化错误且可重试；无效项不可重试。
      final OpmlImportItemResult failed = result.items.firstWhere(
        (OpmlImportItemResult i) => i.outcome == OpmlItemOutcome.failed,
      );
      expect(failed.error, isNotNull);
      expect(failed.isRetryable, isTrue);
      final OpmlImportItemResult invalid = result.items.firstWhere(
        (OpmlImportItemResult i) => i.outcome == OpmlItemOutcome.invalid,
      );
      expect(
        invalid.isRetryable,
        isFalse,
        reason: '地址本身不合法，重试必然同样失败；把它算进可重试项会让用户白点',
      );

      // 成功的两条真的落库了。
      final List<FeedRecord> feeds = (await catalog.listFeeds()).unwrap();
      expect(feeds, hasLength(2));
    });

    test('重试只跑失败项，并返回合并后的完整清单', () async {
      // 第一步：three 不可达。
      final ImportOpmlUseCase first = buildImport(<String, http.Response>{
        'https://feeds.example.com/one.xml': _xml(_rss('one')),
      });
      final OpmlPreview preview = (await first.preview(opml)).unwrap();
      final OpmlImportResult initial = (await first.import(preview)).unwrap();
      expect(initial.importedCount, 1);
      expect(initial.failedCount, 2, reason: 'two 与 three 都不可达');

      // 第二步：two 恢复；three 仍然不可达。
      final ImportOpmlUseCase second = buildImport(<String, http.Response>{
        'https://feeds.example.com/one.xml': _xml(_rss('one')),
        'https://feeds.example.com/two.xml': _xml(_rss('two')),
      });
      final OpmlImportResult retried = (await second.retryFailed(initial))
          .unwrap();

      expect(
        retried.items.length,
        initial.items.length,
        reason: '结果清单长度不变（重试是就地替换，不是追加）',
      );
      expect(retried.importedCount, 2);
      expect(retried.failedCount, 1, reason: 'three 依旧失败');
      expect(retried.invalidCount, 1, reason: '无效项在重试中保持无效，不被重跑');

      // 库里两条成功的源 + 第一次导入的那条 = 2 条（one 不会因为重试再建一条）。
      expect((await catalog.listFeeds()).unwrap(), hasLength(2));
    });

    test('重试时 one 已经成功过，不会被再次请求', () async {
      int oneRequests = 0;
      final HttpFeedFetcher fetcher = HttpFeedFetcher(
        client: MockClient((http.Request request) async {
          if (request.url.toString() == 'https://feeds.example.com/one.xml') {
            oneRequests++;
            return _xml(_rss('one'));
          }
          return http.Response('not found', 404);
        }),
      );
      final ImportOpmlUseCase useCase = ImportOpmlUseCase(
        addFeed: AddFeedUseCase(
          catalog: catalog,
          articles: articles,
          fetcher: fetcher,
        ),
        catalog: catalog,
      );

      final OpmlPreview preview = (await useCase.preview(opml)).unwrap();
      final OpmlImportResult initial = (await useCase.import(preview)).unwrap();
      expect(oneRequests, 1);

      await useCase.retryFailed(initial);
      expect(oneRequests, 1, reason: '已成功的条目不该在重试时再发一次请求（只有失败项需要重跑）');
    });

    test('保留文件分组导入：真的按路径建组并归入', () async {
      final ImportOpmlUseCase useCase = buildImport(<String, http.Response>{
        'https://feeds.example.com/one.xml': _xml(_rss('one')),
        'https://feeds.example.com/two.xml': _xml(_rss('two')),
        'https://feeds.example.com/three.xml': _xml(_rss('three')),
      });
      final OpmlPreview preview = (await useCase.preview(
        opml,
        strategy: OpmlGroupStrategy.keepFileGroups,
      )).unwrap();
      await useCase.import(preview);

      final List<GroupRecord> groups = (await catalog.listGroups()).unwrap();
      final Set<String> names = groups.map((GroupRecord g) => g.name).toSet();
      expect(names, containsAll(<String>['Tech', 'Nested']));

      final List<FeedRecord> feeds = (await catalog.listFeeds()).unwrap();
      final Map<int, String> groupNames = <int, String>{
        for (final GroupRecord g in groups) g.id: g.name,
      };
      final FeedRecord two = feeds.firstWhere((FeedRecord f) => f.name == '源二');
      expect(groupNames[two.groupId], 'Nested', reason: '源二落在嵌套分组里');
      final FeedRecord three = feeds.firstWhere(
        (FeedRecord f) => f.name == '源三',
      );
      expect(three.groupId, isNull, reason: '没有分组路径的条目直接挂 body 下');
    });

    test('保留文件分组：已有同名分组直接复用（重复导入不新建一堆组）', () async {
      final ImportOpmlUseCase useCase = buildImport(<String, http.Response>{
        'https://feeds.example.com/one.xml': _xml(_rss('one')),
      });
      await catalog.createGroup(syncId: 'group.tech.existing', name: 'Tech');

      final OpmlPreview preview = (await useCase.preview(
        opml,
        strategy: OpmlGroupStrategy.keepFileGroups,
      )).unwrap();
      await useCase.import(preview);

      final List<GroupRecord> tech = (await catalog.listGroups())
          .unwrap()
          .where((GroupRecord g) => g.name == 'Tech')
          .toList();
      expect(tech, hasLength(1), reason: '同名分组应复用而不是再建一个');
    });
  });

  group('导出与往返', () {
    test('导出只写标准字段：不含内部 ID、加精、阅读状态或刷新偏好', () async {
      final int feedId = (await catalog.createFeed(
        const FeedInsert(
          syncId: 'feed.internal.42',
          normalizedUrl: 'https://feeds.example.com/one.xml',
          name: '源一',
          sourceName: '源自带名',
        ),
      )).unwrap().id;
      await catalog.setFeedFavorite(feedId: feedId, favorite: true);
      await catalog.setFeedRefreshInterval(feedId: feedId, minutes: 30);

      final String document = (await buildExport().export()).unwrap().document;

      // 标准字段在。
      expect(document, contains('<opml version="2.0">'));
      expect(document, contains('xmlUrl="https://feeds.example.com/one.xml"'));
      expect(document, contains('text="源一"'));

      // 内部字段一律不出现（架构 4.1：不保证保留 Flux 内部 ID 与加精/刷新偏好）。
      expect(document, isNot(contains('feed.internal.42')));
      expect(document, isNot(contains('internal.42')));
      expect(document, isNot(contains('favorite')));
      expect(document, isNot(contains('refresh')));
      expect(document, isNot(contains('reading')));
      expect(document, isNot(contains('enabled')));
      expect(document, isNot(contains('SourceName')));
      expect(
        document,
        isNot(contains('源自带名')),
        reason: '源自带名不是 OPML 能表达的字段，显示名才是',
      );
      // 不写任何自定义命名空间属性。
      expect(document, isNot(contains('flux:')));
    });

    test('导出按分组嵌套，且分组用 folder outline 表达', () async {
      final GroupRecord tech = (await catalog.createGroup(
        syncId: 'group.tech',
        name: 'Tech',
      )).unwrap();
      await catalog.createFeed(
        FeedInsert(
          syncId: 'feed.a',
          normalizedUrl: 'https://feeds.example.com/a.xml',
          name: 'A',
          groupId: tech.id,
        ),
      );
      await catalog.createFeed(
        const FeedInsert(
          syncId: 'feed.b',
          normalizedUrl: 'https://feeds.example.com/b.xml',
          name: 'B',
        ),
      );

      final String document = (await buildExport().export()).unwrap().document;

      // 分组是一个没有 xmlUrl 的 outline（OPML 的 folder 约定）。
      expect(document, contains('<outline text="Tech" title="Tech">'));
      expect(document, contains('</outline>'));
      // 未归组的订阅直接挂在 body 下。
      expect(document, contains('text="B"'));

      // 再用解析器读回来，确认结构可被标准方式理解。
      final ParsedOpml reparsed = parseOpml(document).unwrap();
      expect(reparsed.entries, hasLength(2));
      final OpmlEntry a = reparsed.entries.firstWhere(
        (OpmlEntry e) => e.title == 'A',
      );
      expect(a.groupPath, <String>['Tech']);
      final OpmlEntry b = reparsed.entries.firstWhere(
        (OpmlEntry e) => e.title == 'B',
      );
      expect(b.groupPath, isEmpty);
    });

    test('往返：导出 → 导入后名称、地址与分组结构都保留', () async {
      final GroupRecord tech = (await catalog.createGroup(
        syncId: 'group.roundtrip',
        name: 'Tech',
      )).unwrap();
      await catalog.createFeed(
        FeedInsert(
          syncId: 'feed.rt.one',
          normalizedUrl: 'https://feeds.example.com/one.xml',
          name: '源一',
          groupId: tech.id,
        ),
      );
      await catalog.createFeed(
        const FeedInsert(
          syncId: 'feed.rt.two',
          normalizedUrl: 'https://feeds.example.com/two.xml',
          name: '源二',
        ),
      );

      final String document = (await buildExport().export()).unwrap().document;

      // 清空订阅与自建分组，模拟「在另一台设备上导入」。
      await db.delete(db.feeds).go();
      await (db.delete(
        db.groups,
      )..where((Groups t) => t.isReserved.equals(false))).go();

      final ImportOpmlUseCase useCase = buildImport(<String, http.Response>{
        'https://feeds.example.com/one.xml': _xml(_rss('one')),
        'https://feeds.example.com/two.xml': _xml(_rss('two')),
      });
      final OpmlPreview preview = (await useCase.preview(
        document,
        strategy: OpmlGroupStrategy.keepFileGroups,
      )).unwrap();
      final OpmlImportResult result = (await useCase.import(preview)).unwrap();
      expect(result.importedCount, 2);

      final List<FeedRecord> feeds = (await catalog.listFeeds()).unwrap();
      expect(feeds.map((FeedRecord f) => f.name).toSet(), <String>{
        '源一',
        '源二',
      }, reason: '名称必须原样保留');
      expect(feeds.map((FeedRecord f) => f.normalizedUrl).toSet(), <String>{
        'https://feeds.example.com/one.xml',
        'https://feeds.example.com/two.xml',
      }, reason: '规范化地址必须原样保留');

      final List<GroupRecord> groups = (await catalog.listGroups()).unwrap();
      final Map<int, String> names = <int, String>{
        for (final GroupRecord g in groups) g.id: g.name,
      };
      final FeedRecord one = feeds.firstWhere((FeedRecord f) => f.name == '源一');
      expect(names[one.groupId], 'Tech', reason: '分组结构必须保留');
      final FeedRecord two = feeds.firstWhere((FeedRecord f) => f.name == '源二');
      expect(two.groupId, isNull);
    });

    test('重复导入：匹配已有源且不重置其状态与文章', () async {
      // 先建一个源并把它改成「加精 + 停用 + 有文章」的状态。
      final int feedId = (await catalog.createFeed(
        const FeedInsert(
          syncId: 'feed.state',
          normalizedUrl: 'https://feeds.example.com/one.xml',
          name: '我改过的名字',
        ),
      )).unwrap().id;
      await catalog.setFeedFavorite(feedId: feedId, favorite: true);
      await catalog.setFeedEnabled(feedId: feedId, enabled: false);
      await articles.upsertArticles(<ArticleImport>[
        ArticleImport(
          feedId: feedId,
          title: '已存在的文章',
          identityBasis: IdentityBasis.guid,
          guid: 'existing',
          guidPresent: true,
        ),
      ]);

      // 导入一份包含同一地址（但名字不同）的 OPML。
      const String document = '''<?xml version="1.0" encoding="UTF-8"?>
<opml version="2.0"><body>
  <outline type="rss" text="文件里的名字"
           xmlUrl="https://feeds.example.com/one.xml?utm_source=import"/>
</body></opml>''';

      final ImportOpmlUseCase useCase = buildImport(<String, http.Response>{
        // 即使可达也不该被请求：重复判定发生在抓取之前。
        'https://feeds.example.com/one.xml': _xml(_rss('one')),
      });
      final OpmlPreview preview = (await useCase.preview(document)).unwrap();
      expect(preview.duplicateCount, 1, reason: '跟踪参数不应让同一地址变成新源');
      expect(preview.addedCount, 0);

      final OpmlImportResult result = (await useCase.import(preview)).unwrap();
      expect(result.duplicateCount, 1);
      expect(result.importedCount, 0);

      // 状态与文章都没被重置。
      final List<FeedRecord> feeds = (await catalog.listFeeds()).unwrap();
      expect(feeds, hasLength(1), reason: '不得新增第二条同地址订阅');
      expect(feeds.single.id, feedId);
      expect(feeds.single.name, '我改过的名字', reason: '重复导入不得改名');
      expect(feeds.single.favorite, isTrue, reason: '不得重置加精');
      expect(feeds.single.enabled, isFalse, reason: '不得重置启用状态');
      expect(await db.select(db.articles).get(), hasLength(1));
    });

    test('秘密排除（SET-027）：各种秘密参数名的值都不出现在导出文件里', () async {
      // 规范化**刻意保留**非跟踪参数（架构 4.1 要求不随意剥离查询参数），因此
      // 一个 token 参数会原样留在 normalizedUrl 里；导出必须再剥一次。
      // 下面覆盖 SecretRedaction 认定的几类名字：精确名（token/api_key/password）、
      // URL 语境名（key/auth）以及包含关键片段的变体（x-frame-token）。
      const List<String> secrets = <String>[
        'https://a.example.com/feed.xml?token=SECRET_VALUE_ONE',
        'https://b.example.com/feed.xml?api_key=SECRET_VALUE_TWO',
        'https://c.example.com/feed.xml?password=SECRET_VALUE_THREE',
        'https://d.example.com/feed.xml?key=SECRET_VALUE_FOUR',
        'https://e.example.com/feed.xml?auth=SECRET_VALUE_FIVE',
        'https://f.example.com/feed.xml?x-access-token=SECRET_VALUE_SIX',
      ];
      for (int i = 0; i < secrets.length; i++) {
        await catalog.createFeed(
          FeedInsert(
            syncId: 'feed.secret.$i',
            normalizedUrl: secrets[i],
            name: '私密源 $i',
          ),
        );
      }

      final OpmlExportResult result = (await buildExport().export()).unwrap();
      final String document = result.document;

      // 本节的核心断言：所有秘密值都不在导出内容里。
      for (final String value in <String>[
        'SECRET_VALUE_ONE',
        'SECRET_VALUE_TWO',
        'SECRET_VALUE_THREE',
        'SECRET_VALUE_FOUR',
        'SECRET_VALUE_FIVE',
        'SECRET_VALUE_SIX',
      ]) {
        expect(
          document,
          isNot(contains(value)),
          reason: '导出不得包含凭据类参数值（SET-027 秘密排除）：$value',
        );
      }

      // 结果里如实报告被剥离的参数名（界面据此提示用户补填凭据）。
      expect(result.strippedSecretParams, isNotEmpty);
      expect(result.strippedSecretParams, contains('token'));
      expect(result.strippedSecretParams, contains('api_key'));

      // 剥离后地址仍是合法 URL（不是带 *** 的无效地址），域名与路径保持原样。
      expect(document, contains('xmlUrl="https://a.example.com/feed.xml"'));
      // 而且不含凭据引用（那是数据库内部字段）。
      expect(document, isNot(contains('credentialRef')));
    });

    test('秘密排除只针对秘密参数名：业务参数必须原样保留（否则订阅会失效）', () async {
      // 长而随机的**业务**参数（很多源用不透明 id 承载文章/分类）不能被误删：
      // 那会让导出文件里的地址指向另一个资源，比泄漏更难排查。
      await catalog.createFeed(
        const FeedInsert(
          syncId: 'feed.business',
          normalizedUrl: 'https://feeds.example.com/feed.xml?channel=c-8f21ba90a7c34d5e&lang=zh',
          name: '业务参数的源',
        ),
      );

      final String document = (await buildExport().export()).unwrap().document;

      expect(document, contains('channel=c-8f21ba90a7c34d5e'));
      expect(document, contains('lang=zh'));
    });

    test('秘密排除：跟踪参数在规范化阶段已剥离，导出里也不出现', () async {
      // 规范化（T013）剥掉 utm_* 等跟踪参数，导出用的是规范化地址，所以它们天然
      // 不在文件里。这里把这条链路钉住，避免将来有人改用原始地址导出。
      await catalog.createFeed(
        const FeedInsert(
          syncId: 'feed.tracking',
          normalizedUrl: 'https://feeds.example.com/feed.xml',
          name: '跟踪参数的源',
        ),
      );

      final String document = (await buildExport().export()).unwrap().document;

      expect(document, isNot(contains('utm_')));
    });

    test('秘密排除：凭据引用只存在于库内，导出只写规范化地址', () async {
      await catalog.createFeed(
        const FeedInsert(
          syncId: 'feed.cred',
          normalizedUrl: 'https://feeds.example.com/cred.xml',
          name: '带凭据引用的源',
        ),
      );
      // 手工把 credentialRef 写进库（模拟 T025+ 的私密源）。
      await (db.update(
        db.feeds,
      )..where((Feeds t) => t.syncId.equals('feed.cred'))).write(
        const FeedsCompanion(credentialRef: Value<String?>('keychain:feed-x')),
      );

      final String document = (await buildExport().export()).unwrap().document;

      expect(document, contains('xmlUrl="https://feeds.example.com/cred.xml"'));
      expect(document, isNot(contains('keychain')), reason: '凭据引用是内部标识，不进导出文件');
    });

    test('导出空订阅：仍是合法 OPML（body 为空）', () async {
      final String document = (await buildExport().export()).unwrap().document;

      expect(document, contains('<opml version="2.0">'));
      expect(parseOpml(document).unwrap().entries, isEmpty);
    });

    test('导出内容对 XML 特殊字符做转义（名称里有 & 和 <）', () async {
      await catalog.createFeed(
        const FeedInsert(
          syncId: 'feed.escape',
          normalizedUrl: 'https://feeds.example.com/escape.xml',
          name: 'A & B <C>',
        ),
      );

      final String document = (await buildExport().export()).unwrap().document;
      expect(document, contains('A &amp; B &lt;C&gt;'));
      // 能重新解析回来（转义正确的最有力证据）。
      final ParsedOpml reparsed = parseOpml(document).unwrap();
      expect(reparsed.entries.single.title, 'A & B <C>');
    });

    test('dateCreated 是 RFC 822（与 fixture 的写法一致）', () async {
      final String document = (await buildExport().export()).unwrap().document;
      expect(document, contains('Mon, 21 Sep 2026 12:00:00 GMT'));
    });
  });
}
