// 订阅管理用例测试（T014）。
//
// 覆盖手册点名的必测项与架构 4.1 的硬规则：
//   - 同 URL 重复添加 → 返回已有源且**不重置状态**（分组/加精/名称/文章都不变）；
//   - 失败给类型化错误（地址非法 / 网络 / 解析 / 存储）；
//   - 未分类保留组不可删除、不可改名，但**可以置顶**；
//   - 分组排序是整段重排（不完整的顺序被拒绝），置顶独立于权重；
//   - 禁用源的真实落库（SET-022），加精的真实落库（SET-023）；
//   - 删除分组的两个分支：移动到未分类真的搬移；删除订阅只做预留（数据必须还在）。
//
// 全部使用内存库 + MockClient，不联网。
library;

import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:flux/core/core.dart';
import 'package:flux/features/feeds/application/add_feed.dart';
import 'package:flux/features/feeds/application/edit_feed.dart';
import 'package:flux/features/feeds/application/feed_overview.dart';
import 'package:flux/features/feeds/application/manage_groups.dart';
import 'package:flux/infrastructure/local/database.dart';
import 'package:flux/infrastructure/local/feed_catalog_store.dart';
import 'package:flux/infrastructure/local/feed_store_adapter.dart';
import 'package:flux/infrastructure/local/tables/article_tables.dart';
import 'package:flux/infrastructure/network/feed_fetcher.dart';

/// 记录诊断消息（验证「失败要留痕」）。
final class _RecordingSink implements DiagnosticSink {
  final List<String> messages = <String>[];

  @override
  void record(DiagnosticSeverity severity, String message, {String? tag}) =>
      messages.add('${severity.name}:$tag:$message');

  @override
  void error(String message, {String? tag}) =>
      record(DiagnosticSeverity.error, message, tag: tag);

  @override
  void warning(String message, {String? tag}) =>
      record(DiagnosticSeverity.warning, message, tag: tag);

  @override
  void info(String message, {String? tag}) =>
      record(DiagnosticSeverity.info, message, tag: tag);
}

/// 固定时钟（让抓取时间可预测）。
final class _FixedClock implements Clock {
  const _FixedClock(this._now);

  final DateTime _now;

  @override
  DateTime now() => _now;

  @override
  Duration monotonic() => Duration.zero;
}

const String _rssTwoItems = '''<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0"><channel>
  <title>测试订阅</title>
  <link>https://feeds.example.com/</link>
  <item>
    <title>第一篇</title>
    <link>https://feeds.example.com/posts/1</link>
    <guid isPermaLink="false">post-1</guid>
    <pubDate>Sun, 20 Sep 2026 22:15:00 GMT</pubDate>
    <description>摘要一</description>
    <content:encoded xmlns:content="http://purl.org/rss/1.0/modules/content/">
      <![CDATA[<p>正文一</p>]]>
    </content:encoded>
  </item>
  <item>
    <title>第二篇</title>
    <link>https://feeds.example.com/posts/2</link>
    <guid isPermaLink="false">post-2</guid>
    <pubDate>Sun, 20 Sep 2026 23:15:00 GMT</pubDate>
    <description>摘要二</description>
  </item>
</channel></rss>''';

/// 带外部实体的文档：必须在解析前被拒绝（T013 的安全边界）。
const String _rssWithDoctype = '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE rss [ <!ENTITY xxe SYSTEM "file:///etc/passwd"> ]>
<rss version="2.0"><channel>
  <title>恶意源</title>
  <item><title>&xxe;</title><link>https://evil.example.com/1</link></item>
</channel></rss>''';

http.Response _xml(String body) => http.Response.bytes(
  utf8.encode(body),
  200,
  headers: <String, String>{'content-type': 'application/xml; charset=utf-8'},
);

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

  /// 构造添加订阅用例。
  AddFeedUseCase buildAdd({
    required Map<String, http.Response> routes,
    DiagnosticSink? diagnostics,
  }) => AddFeedUseCase(
    fetcher: HttpFeedFetcher(
      client: MockClient((http.Request request) async {
        final http.Response? response = routes[request.url.toString()];
        return response ?? http.Response('not found', 404);
      }),
    ),
    catalog: catalog,
    articles: articles,
    diagnostics: diagnostics ?? const NoopDiagnosticSink(),
    clock: _FixedClock(DateTime.utc(2026, 9, 21, 12)),
  );

  /// 取保留组「未分类」。
  Future<GroupRecord> uncategorized() async {
    final Result<GroupRecord?> found = await catalog.findGroupBySyncId(
      groupUncategorizedSyncId,
    );
    expect(found.isOk, isTrue);
    expect(found.valueOrNull, isNotNull, reason: '建库种子必须包含未分类');
    return found.valueOrNull!;
  }

  group('添加订阅：预览 → 确认', () {
    test('预览只读不写：抓取解析出标题、条目数与规范化地址，库里仍无订阅', () async {
      final AddFeedUseCase useCase = buildAdd(
        routes: <String, http.Response>{
          'https://feeds.example.com/a.xml': _xml(_rssTwoItems),
        },
      );

      final Result<FeedPreview> preview = await useCase.preview(
        'https://feeds.example.com/a.xml',
      );

      expect(preview.isOk, isTrue, reason: preview.errorOrNull?.message);
      final FeedPreview value = preview.unwrap();
      expect(value.title, '测试订阅', reason: '优先用源自带标题');
      expect(value.entryCount, 2);
      expect(value.duplicateOf, isNull);
      expect(value.isDuplicate, isFalse);
      expect(
        value.normalizedUrl,
        'https://feeds.example.com/a.xml',
        reason: '规范化地址是匹配与去重的依据',
      );

      // 预览**不写任何数据**。
      expect((await catalog.listFeeds()).unwrap(), isEmpty);
      expect(await db.select(db.articles).get(), isEmpty);
    });

    test('确认入库：订阅与文章都落库，标题/分组按输入', () async {
      final AddFeedUseCase useCase = buildAdd(
        routes: <String, http.Response>{
          'https://feeds.example.com/a.xml': _xml(_rssTwoItems),
        },
      );
      final GroupRecord reserved = await uncategorized();

      final Result<FeedPreview> preview = await useCase.preview(
        'https://feeds.example.com/a.xml',
      );
      final Result<AddFeedOutcome> outcome = await useCase.confirm(
        preview: preview.unwrap(),
        name: '我的测试源',
        groupId: reserved.id,
      );

      expect(outcome.isOk, isTrue, reason: outcome.errorOrNull?.message);
      final AddFeedOutcome added = outcome.unwrap();
      expect(added.isDuplicate, isFalse);
      expect(added.imported!.inserted, 2);
      expect(added.feed.name, '我的测试源');
      expect(added.feed.sourceName, '测试订阅', reason: '源自带名与显示名分开保存');
      expect(added.feed.groupId, reserved.id);
      expect(added.feed.enabled, isTrue, reason: '新订阅默认参与自动刷新');
      expect(added.feed.favorite, isFalse);

      final List<Article> stored = await db.select(db.articles).get();
      expect(stored, hasLength(2));
      expect(
        stored.every((Article a) => a.readingState == ReadingState.unread),
        isTrue,
      );
    });

    test('同一地址重复添加：返回已有源且不重置状态', () async {
      final AddFeedUseCase useCase = buildAdd(
        routes: <String, http.Response>{
          'https://feeds.example.com/a.xml': _xml(_rssTwoItems),
        },
      );
      final GroupRecord reserved = await uncategorized();

      final Result<FeedPreview> first = await useCase.preview(
        'https://feeds.example.com/a.xml',
      );
      final Result<AddFeedOutcome> created = await useCase.confirm(
        preview: first.unwrap(),
        name: '第一次起的名字',
        groupId: reserved.id,
      );
      final int feedId = created.unwrap().feed.id;

      // 用户改动状态：加精 + 停用。
      await catalog.setFeedFavorite(feedId: feedId, favorite: true);
      await catalog.setFeedEnabled(feedId: feedId, enabled: false);

      // 第二次添加同一地址（带跟踪参数也不应被当成新源）。
      final Result<FeedPreview> second = await useCase.preview(
        'https://feeds.example.com/a.xml?utm_source=newsletter',
      );
      expect(second.isOk, isTrue);
      expect(second.unwrap().isDuplicate, isTrue, reason: '同 URL 必须判定为重复');
      expect(second.unwrap().entryCount, 0, reason: '重复时不重新抓取');
      expect(second.unwrap().parsed, isNull, reason: '重复时没有抓取内容可写');

      final Result<AddFeedOutcome> again = await useCase.confirm(
        preview: second.unwrap(),
        name: '试图改名',
        groupId: reserved.id,
      );
      expect(again.unwrap().isDuplicate, isTrue);
      expect(again.unwrap().imported, isNull, reason: '重复添加不写文章');

      // 已有源的一切都没变。
      final Result<List<FeedRecord>> all = await catalog.listFeeds();
      expect(all.unwrap(), hasLength(1), reason: '不得新增第二条同 URL 订阅');
      final FeedRecord only = all.unwrap().single;
      expect(only.id, feedId);
      expect(only.name, '第一次起的名字', reason: '重复添加不得改名');
      expect(only.favorite, isTrue, reason: '重复添加不得重置加精');
      expect(only.enabled, isFalse, reason: '重复添加不得重置启用状态');
      expect(await db.select(db.articles).get(), hasLength(2));

      expect(again.unwrap().feed.id, feedId);
    });

    test('重复添加不发网络请求（判定先于抓取）', () async {
      int requests = 0;
      final AddFeedUseCase useCase = AddFeedUseCase(
        fetcher: HttpFeedFetcher(
          client: MockClient((http.Request request) async {
            requests++;
            return _xml(_rssTwoItems);
          }),
        ),
        catalog: catalog,
        articles: articles,
        clock: _FixedClock(DateTime.utc(2026, 9, 21, 12)),
      );

      final Result<FeedPreview> first = await useCase.preview(
        'https://feeds.example.com/a.xml',
      );
      await useCase.confirm(preview: first.unwrap(), name: '源');
      expect(requests, 1);

      await useCase.preview('https://feeds.example.com/a.xml');
      expect(requests, 1, reason: '已订阅的地址不应再联网');
    });

    test('地址非法：类型化校验错误且不发请求', () async {
      int requests = 0;
      final AddFeedUseCase useCase = AddFeedUseCase(
        fetcher: HttpFeedFetcher(
          client: MockClient((http.Request request) async {
            requests++;
            return _xml(_rssTwoItems);
          }),
        ),
        catalog: catalog,
        articles: articles,
      );

      for (final String bad in <String>[
        '',
        '   ',
        'example.com/feed.xml',
        'ftp://example.com/feed.xml',
        'file:///etc/passwd',
        'https:///no-host',
      ]) {
        final Result<FeedPreview> result = await useCase.preview(bad);
        expect(result.isErr, isTrue, reason: '「$bad」应被拒绝');
        expect(result.errorOrNull, isA<ValidationError>());
        expect(
          AddFeedFailureReason.classify(result.errorOrNull!),
          AddFeedFailureReason.invalidUrl,
        );
      }
      expect(requests, 0, reason: '地址不合法时不得联网');
    });

    test('网络失败：类型化网络错误，且没有写任何数据', () async {
      final _RecordingSink sink = _RecordingSink();
      final AddFeedUseCase useCase = buildAdd(
        routes: <String, http.Response>{},
        diagnostics: sink,
      );

      final Result<FeedPreview> result = await useCase.preview(
        'https://feeds.example.com/missing.xml',
      );

      expect(result.isErr, isTrue);
      final AppError error = result.errorOrNull!;
      expect(error, isA<NetworkError>());
      expect(
        AddFeedFailureReason.classify(error),
        AddFeedFailureReason.network,
      );
      expect((await catalog.listFeeds()).unwrap(), isEmpty);
      expect(sink.messages, isNotEmpty, reason: '失败必须留痕');
    });

    test('内容不是 RSS/Atom：解析错误；含 DTD/外部实体同样被拒', () async {
      final AddFeedUseCase useCase = buildAdd(
        routes: <String, http.Response>{
          'https://feeds.example.com/html': http.Response.bytes(
            utf8.encode('<html><body>这不是订阅</body></html>'),
            200,
            headers: <String, String>{'content-type': 'text/html'},
          ),
          'https://feeds.example.com/evil.xml': _xml(_rssWithDoctype),
        },
      );

      for (final String url in <String>[
        'https://feeds.example.com/html',
        'https://feeds.example.com/evil.xml',
      ]) {
        final Result<FeedPreview> result = await useCase.preview(url);
        expect(result.isErr, isTrue, reason: url);
        expect(result.errorOrNull, isA<ParseError>(), reason: url);
        expect(
          AddFeedFailureReason.classify(result.errorOrNull!),
          AddFeedFailureReason.parse,
        );
      }
      expect((await catalog.listFeeds()).unwrap(), isEmpty);
    });

    test('空名被拒绝：用例层校验，不依赖界面', () async {
      final AddFeedUseCase useCase = buildAdd(
        routes: <String, http.Response>{
          'https://feeds.example.com/a.xml': _xml(_rssTwoItems),
        },
      );
      final Result<FeedPreview> preview = await useCase.preview(
        'https://feeds.example.com/a.xml',
      );

      final Result<AddFeedOutcome> result = await useCase.confirm(
        preview: preview.unwrap(),
        name: '   ',
      );

      expect(result.isErr, isTrue);
      expect(result.errorOrNull, isA<ValidationError>());
      expect((await catalog.listFeeds()).unwrap(), isEmpty);
    });

    test('预览标题兜底：源无标题时用主机名，绝不留空', () async {
      const String noTitle = '''<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0"><channel>
  <item><title>只有条目</title><link>https://feeds.example.com/x</link></item>
</channel></rss>''';
      final AddFeedUseCase useCase = buildAdd(
        routes: <String, http.Response>{
          'https://feeds.example.com/notitle.xml': _xml(noTitle),
        },
      );

      final Result<FeedPreview> preview = await useCase.preview(
        'https://feeds.example.com/notitle.xml',
      );
      expect(preview.unwrap().title, 'feeds.example.com');
    });

    test('源里没有条目也能添加（地址有效即为有效订阅）', () async {
      const String empty = '''<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0"><channel><title>空源</title></channel></rss>''';
      final AddFeedUseCase useCase = buildAdd(
        routes: <String, http.Response>{
          'https://feeds.example.com/empty.xml': _xml(empty),
        },
      );

      final Result<FeedPreview> preview = await useCase.preview(
        'https://feeds.example.com/empty.xml',
      );
      expect(preview.unwrap().entryCount, 0);

      final Result<AddFeedOutcome> outcome = await useCase.confirm(
        preview: preview.unwrap(),
        name: '空源',
      );
      expect(outcome.isOk, isTrue);
      expect(outcome.unwrap().imported!.inserted, 0);
      expect((await catalog.listFeeds()).unwrap(), hasLength(1));
    });
  });

  group('编辑订阅（SET-022/023）', () {
    late int feedId;

    setUp(() async {
      final Result<FeedRecord> created = await catalog.createFeed(
        const FeedInsert(
          syncId: 'feed.edit',
          normalizedUrl: 'https://feeds.example.com/edit.xml',
          name: '原名',
          sourceName: '源自己的名字',
        ),
      );
      feedId = created.unwrap().id;
    });

    test('改名：只改显示名，源自带名保留', () async {
      final EditFeedUseCase useCase = EditFeedUseCase(catalog: catalog);

      final Result<FeedRecord> result = await useCase.rename(
        feedId: feedId,
        name: '  新名字  ',
      );

      expect(result.unwrap().name, '新名字', reason: '名称前后空白被去掉');
      final FeedRecord stored = (await catalog.listFeeds()).unwrap().single;
      expect(stored.name, '新名字');
      expect(
        stored.sourceName,
        '源自己的名字',
        reason: '源自带名是抓取事实，改名不得覆盖它（架构 5.1 要求两者分开）',
      );
    });

    test('改名：空名被拒绝，已存名称不变', () async {
      final EditFeedUseCase useCase = EditFeedUseCase(catalog: catalog);

      final Result<FeedRecord> result = await useCase.rename(
        feedId: feedId,
        name: '',
      );

      expect(result.isErr, isTrue);
      expect(result.errorOrNull, isA<ValidationError>());
      expect((await catalog.listFeeds()).unwrap().single.name, '原名');
    });

    test('移动分组：目标不存在时报校验错误而不是存储错误', () async {
      final EditFeedUseCase useCase = EditFeedUseCase(catalog: catalog);

      final Result<FeedRecord> result = await useCase.moveToGroup(
        feedId: feedId,
        groupId: 999999,
      );

      expect(result.isErr, isTrue);
      expect(result.errorOrNull, isA<ValidationError>());
      expect((await catalog.listFeeds()).unwrap().single.groupId, isNull);
    });

    test('移动分组到未分类；再移出分组', () async {
      final EditFeedUseCase useCase = EditFeedUseCase(catalog: catalog);
      final GroupRecord reserved = await uncategorized();

      final Result<FeedRecord> moved = await useCase.moveToGroup(
        feedId: feedId,
        groupId: reserved.id,
      );
      expect(moved.unwrap().groupId, reserved.id);

      final Result<FeedRecord> out = await useCase.moveToGroup(
        feedId: feedId,
        groupId: null,
      );
      expect(out.unwrap().groupId, isNull);
      expect((await catalog.listFeeds()).unwrap().single.groupId, isNull);
    });

    test('启用开关真实落库（SET-022）；禁用不清空文章', () async {
      final EditFeedUseCase useCase = EditFeedUseCase(catalog: catalog);
      await articles.upsertArticles(<ArticleImport>[
        ArticleImport(
          feedId: feedId,
          title: '禁用前的文章',
          identityBasis: IdentityBasis.guid,
          guid: 'keep-me',
          guidPresent: true,
          fetchedAt: DateTime.utc(2026, 9, 21),
        ),
      ]);

      final Result<FeedRecord> disabled = await useCase.setEnabled(
        feedId: feedId,
        enabled: false,
      );

      expect(disabled.unwrap().enabled, isFalse);
      expect((await catalog.listFeeds()).unwrap().single.enabled, isFalse);
      expect(
        await db.select(db.articles).get(),
        hasLength(1),
        reason: '禁用是「不要再联网」，不是「把内容清掉」（架构 4.1 保留旧内容）',
      );
    });

    test('加精真实落库（SET-023），且不改动其他字段', () async {
      final EditFeedUseCase useCase = EditFeedUseCase(catalog: catalog);

      final Result<FeedRecord> result = await useCase.setFavorite(
        feedId: feedId,
        favorite: true,
      );

      expect(result.unwrap().favorite, isTrue);
      final FeedRecord stored = (await catalog.listFeeds()).unwrap().single;
      expect(stored.favorite, isTrue);
      expect(stored.name, '原名', reason: '加精只写一个布尔列');
      expect(stored.enabled, isTrue);
      expect(stored.refreshIntervalMinutes, isNull);
    });

    test('刷新间隔：只接受 SET-020 的取值集合或继承全局', () async {
      final EditFeedUseCase useCase = EditFeedUseCase(catalog: catalog);

      final Result<FeedRecord> inherit = await useCase.setRefreshInterval(
        feedId: feedId,
      );
      expect(inherit.unwrap().refreshIntervalMinutes, isNull);

      final Result<FeedRecord> thirty = await useCase.setRefreshInterval(
        feedId: feedId,
        minutes: 30,
      );
      expect(thirty.unwrap().refreshIntervalMinutes, 30);
      expect(
        (await catalog.listFeeds()).unwrap().single.refreshIntervalMinutes,
        30,
      );

      final Result<FeedRecord> manual = await useCase.setRefreshInterval(
        feedId: feedId,
        minutes: 0,
      );
      expect(manual.unwrap().refreshIntervalMinutes, 0, reason: '0 表示手动');

      final Result<FeedRecord> rejected = await useCase.setRefreshInterval(
        feedId: feedId,
        minutes: 7,
      );
      expect(rejected.isErr, isTrue, reason: '7 分钟不在 SET-020 取值集合内');
      expect(
        (await catalog.listFeeds()).unwrap().single.refreshIntervalMinutes,
        0,
        reason: '被拒绝的写入不得改动已存值',
      );
    });

    test('操作不存在的订阅：类型化错误而不是静默成功', () async {
      final EditFeedUseCase useCase = EditFeedUseCase(catalog: catalog);

      final Result<FeedRecord> result = await useCase.rename(
        feedId: 424242,
        name: '任意',
      );

      expect(result.isErr, isTrue);
      expect(result.errorOrNull, isA<StorageError>());
      expect((result.errorOrNull! as StorageError).isMissing, isTrue);
    });
  });

  group('分组管理（SET-024、架构 4.1）', () {
    late ManageGroupsUseCase groups;

    setUp(() {
      groups = ManageGroupsUseCase(catalog: catalog);
    });

    test('建组：排在末尾（sortOrder = 现有最大 + 1），且不是保留组', () async {
      final Result<GroupRecord> first = await groups.create(name: '技术');
      expect(first.unwrap().sortOrder, 1, reason: '未分类的 sortOrder 是 0，新组排其后');
      expect(first.unwrap().isReserved, isFalse);

      final Result<GroupRecord> second = await groups.create(name: '生活');
      expect(second.unwrap().sortOrder, 2);

      // 删掉第一个再建：新组应取「最大 + 1」而不是「数量」，
      // 否则它会插到已存在的组前面（与「按创建顺序」不符）。
      await groups.delete(first.unwrap().id);
      final Result<GroupRecord> third = await groups.create(name: '新闻');
      expect(third.unwrap().sortOrder, 3);
    });

    test('建组：空名被拒绝', () async {
      final Result<GroupRecord> result = await groups.create(name: '   ');
      expect(result.isErr, isTrue);
      expect(result.errorOrNull, isA<ValidationError>());
    });

    test('建组：两次生成不同 syncId（不会撞唯一索引）', () async {
      final Result<GroupRecord> a = await groups.create(name: 'A');
      final Result<GroupRecord> b = await groups.create(name: 'B');
      expect(a.unwrap().syncId, isNot(b.unwrap().syncId));
    });

    test('未分类不可改名：用例层拒绝，不依赖界面禁用', () async {
      final GroupRecord reserved = await uncategorized();

      final Result<GroupRecord> result = await groups.rename(
        groupId: reserved.id,
        name: '随便改',
      );

      expect(result.isErr, isTrue);
      expect(result.errorOrNull, isA<ValidationError>());
      final GroupRecord stored = await uncategorized();
      expect(stored.name, groupUncategorizedDefaultName);
    });

    test('未分类不可删除：用例层拒绝（它是「移动到未分类」的目标）', () async {
      final GroupRecord reserved = await uncategorized();

      final Result<GroupDeletionOutcome> result = await groups.delete(
        reserved.id,
      );

      expect(result.isErr, isTrue);
      expect(result.errorOrNull, isA<ValidationError>());
      expect((await catalog.listGroups()).unwrap(), hasLength(1));
    });

    test('未分类可以置顶（架构只限制删除与改名）', () async {
      final GroupRecord reserved = await uncategorized();

      final Result<GroupRecord> result = await groups.setPinned(
        groupId: reserved.id,
        pinned: true,
      );

      expect(result.unwrap().pinned, isTrue);
      expect((await uncategorized()).pinned, isTrue);
    });

    test('置顶独立于权重：取消置顶后回到原相对位置', () async {
      final Result<GroupRecord> tech = await groups.create(name: '技术');
      final Result<GroupRecord> life = await groups.create(name: '生活');
      expect(tech.unwrap().sortOrder < life.unwrap().sortOrder, isTrue);

      await groups.setPinned(groupId: life.unwrap().id, pinned: true);
      // 置顶用独立布尔列，因此权重没有被改动。
      final List<GroupRecord> afterPin = (await catalog.listGroups()).unwrap();
      expect(
        afterPin
            .firstWhere((GroupRecord g) => g.id == life.unwrap().id)
            .sortOrder,
        2,
        reason: '置顶不得靠改权重实现',
      );

      await groups.setPinned(groupId: life.unwrap().id, pinned: false);
      final List<GroupRecord> sorted = sortGroupsForDisplay(
        (await catalog.listGroups()).unwrap(),
      );
      expect(sorted.map((GroupRecord g) => g.name).toList(), <String>[
        groupUncategorizedDefaultName,
        '技术',
        '生活',
      ], reason: '取消置顶后回到权重决定的顺序');
    });

    test('排序：必须包含全部分组，且顺序真实落库', () async {
      final Result<GroupRecord> tech = await groups.create(name: '技术');
      final GroupRecord reserved = await uncategorized();

      // 少一个 → 拒绝。
      final Result<List<GroupRecord>> partial = await groups.reorder(<int>[
        tech.unwrap().id,
      ]);
      expect(partial.isErr, isTrue);
      expect(partial.errorOrNull, isA<ValidationError>());

      // 完整顺序 → 落库，权重按下标重排。
      final Result<List<GroupRecord>> ok = await groups.reorder(<int>[
        tech.unwrap().id,
        reserved.id,
      ]);
      expect(ok.isOk, isTrue, reason: ok.errorOrNull?.message);

      final List<GroupRecord> stored = sortGroupsForDisplay(
        (await catalog.listGroups()).unwrap(),
      );
      expect(stored.map((GroupRecord g) => g.name).toList(), <String>[
        '技术',
        groupUncategorizedDefaultName,
      ]);
      expect(stored.first.sortOrder, 0);
      expect(stored.last.sortOrder, 1);
    });

    test('排序拒绝重复 id（否则会出现重复权重）', () async {
      final Result<GroupRecord> tech = await groups.create(name: '技术');
      await uncategorized();

      final Result<List<GroupRecord>> result = await groups.reorder(<int>[
        tech.unwrap().id,
        tech.unwrap().id,
      ]);

      expect(result.isErr, isTrue, reason: '长度相同但集合不同，必须拒绝');
    });

    test('删除分组（移动到未分类）：订阅搬移、分组消失、文章不受影响', () async {
      final Result<GroupRecord> tech = await groups.create(name: '技术');
      final Result<FeedRecord> feed = await catalog.createFeed(
        FeedInsert(
          syncId: 'feed.in.tech',
          normalizedUrl: 'https://feeds.example.com/tech.xml',
          name: '技术源',
          groupId: tech.unwrap().id,
        ),
      );
      await articles.upsertArticles(<ArticleImport>[
        ArticleImport(
          feedId: feed.unwrap().id,
          title: '文章',
          identityBasis: IdentityBasis.guid,
          guid: 'g1',
          guidPresent: true,
        ),
      ]);

      final Result<GroupDeletionOutcome> result = await groups.delete(
        tech.unwrap().id,
      );

      final GroupDeletionOutcome outcome = result.unwrap();
      expect(outcome.movedFeedCount, 1);
      expect(outcome.deletedFeedCount, 0);
      expect(outcome.deletedArticles, 0, reason: '移动分支不删任何文章');

      final List<GroupRecord> remaining = (await catalog.listGroups()).unwrap();
      expect(remaining, hasLength(1), reason: '只剩保留组');
      expect(remaining.single.syncId, groupUncategorizedSyncId);

      final FeedRecord moved = (await catalog.listFeeds()).unwrap().single;
      expect(moved.id, feed.unwrap().id, reason: '订阅行本身不变（id 相同）');
      expect(moved.groupId, remaining.single.id, reason: '归属改为未分类');
      expect(await db.select(db.articles).get(), hasLength(1), reason: '文章不动');
    });

    test('删除分组（删除订阅分支）：T018 起真正删除，且保留收藏的规则生效', () async {
      final Result<GroupRecord> tech = await groups.create(name: '技术');
      final Result<FeedRecord> feed = await catalog.createFeed(
        FeedInsert(
          syncId: 'feed.in.tech2',
          normalizedUrl: 'https://feeds.example.com/tech2.xml',
          name: '技术源二',
          groupId: tech.unwrap().id,
        ),
      );
      // 两条文章：一条收藏、一条稍后再读。删除分支必须「收藏留下、later 清掉」。
      await articles.upsertArticles(<ArticleImport>[
        ArticleImport(
          feedId: feed.unwrap().id,
          title: '收藏的文章',
          identityBasis: IdentityBasis.guid,
          guid: 'keep-me',
          guidPresent: true,
        ),
        ArticleImport(
          feedId: feed.unwrap().id,
          title: '稍后再读的文章',
          identityBasis: IdentityBasis.guid,
          guid: 'later-one',
          guidPresent: true,
        ),
      ]);
      final List<Article> seeded = await db.select(db.articles).get();
      await (db.update(db.articles)
            ..where((Articles t) => t.guid.equals('keep-me')))
          .write(const ArticlesCompanion(favorite: Value<bool>(true)));
      await (db.update(
        db.articles,
      )..where((Articles t) => t.guid.equals('later-one'))).write(
        const ArticlesCompanion(
          readingState: Value<ReadingState>(ReadingState.later),
        ),
      );
      expect(seeded, hasLength(2));

      final Result<GroupDeletionOutcome> result = await groups.delete(
        tech.unwrap().id,
        mode: GroupDeletionMode.deleteFeeds,
      );

      final GroupDeletionOutcome outcome = result.unwrap();
      expect(outcome.mode, GroupDeletionMode.deleteFeeds);
      expect(outcome.deletedFeedCount, 1);
      expect(outcome.movedFeedCount, 0);
      expect(outcome.keptFavorites, 1, reason: '收藏留下并脱离源');
      expect(outcome.deletedArticles, 1, reason: '含 later 的非收藏被清理');

      // 分组与订阅都真的没了（T018 起「删除其中订阅」不再只是记录）。
      final List<GroupRecord> allGroups = (await catalog.listGroups()).unwrap();
      expect(allGroups, hasLength(1), reason: '只剩保留组');
      final List<FeedRecord> allFeeds = (await catalog.listFeeds()).unwrap();
      expect(allFeeds, isEmpty, reason: '组内订阅被真正删除');

      // 收藏那条留下、脱离源并带上来源快照；later 那条被清理。
      final List<Article> remaining = await db.select(db.articles).get();
      expect(remaining, hasLength(1));
      expect(remaining.single.title, '收藏的文章');
      expect(remaining.single.feedId, isNull, reason: '已脱离源');
      expect(remaining.single.feedTitle, '技术源二', reason: '来源快照冻结');
      expect(remaining.single.feedUrl, 'https://feeds.example.com/tech2.xml');
      expect(remaining.single.favorite, isTrue);
    });

    test('操作不存在的分组：类型化错误', () async {
      final Result<GroupRecord> rename = await groups.rename(
        groupId: 987654,
        name: '任意',
      );
      expect(rename.isErr, isTrue);
      expect(rename.errorOrNull, isA<StorageError>());
    });
  });

  group('读模型：分组展示顺序与孤儿订阅', () {
    test('置顶组在前；未归组订阅归入未分类；未读数按 feed 聚合', () async {
      final ManageGroupsUseCase groups = ManageGroupsUseCase(catalog: catalog);
      final Result<GroupRecord> tech = await groups.create(name: '技术');
      final Result<GroupRecord> life = await groups.create(name: '生活');
      await catalog.setGroupPinned(groupId: life.unwrap().id, pinned: true);

      final int inTech = (await catalog.createFeed(
        FeedInsert(
          syncId: 'feed.1',
          normalizedUrl: 'https://feeds.example.com/1.xml',
          name: '技术源',
          groupId: tech.unwrap().id,
        ),
      )).unwrap().id;
      // 一个未归组的源：应出现在未分类区块里，而不是被丢掉。
      final int orphan = (await catalog.createFeed(
        const FeedInsert(
          syncId: 'feed.2',
          normalizedUrl: 'https://feeds.example.com/2.xml',
          name: '未归组源',
        ),
      )).unwrap().id;

      await articles.upsertArticles(<ArticleImport>[
        ArticleImport(
          feedId: inTech,
          title: '未读一',
          identityBasis: IdentityBasis.guid,
          guid: 'a',
          guidPresent: true,
        ),
        ArticleImport(
          feedId: inTech,
          title: '未读二',
          identityBasis: IdentityBasis.guid,
          guid: 'b',
          guidPresent: true,
        ),
        ArticleImport(
          feedId: orphan,
          title: '未读三',
          identityBasis: IdentityBasis.guid,
          guid: 'c',
          guidPresent: true,
        ),
      ]);
      // 把其中一条标为 later：它**不算未读**（架构 4.1：仅未读筛选只匹配 unread）。
      await (db.update(
        db.articles,
      )..where((Articles t) => t.guid.equals('c'))).write(
        const ArticlesCompanion(readingState: Value(ReadingState.later)),
      );

      final FeedOverviewReader reader = FeedOverviewReader(catalog: catalog);
      final FeedOverview overview = (await reader.read()).unwrap();

      expect(overview.totalFeeds, 2);
      expect(
        overview.sections.map((FeedGroupSection s) => s.displayName).toList(),
        <String>['生活', groupUncategorizedDefaultName, '技术'],
        reason: '置顶组在前，其余按权重',
      );

      final FeedGroupSection reserved = overview.sections.firstWhere(
        (FeedGroupSection s) => s.isReserved,
      );
      expect(
        reserved.entries.map((FeedListEntry e) => e.feed.name).toList(),
        <String>['未归组源'],
        reason: '未归组订阅不能被丢掉',
      );
      expect(reserved.entries.single.unreadCount, 0, reason: 'later 不算未读');

      final FeedGroupSection techSection = overview.sections.firstWhere(
        (FeedGroupSection s) => s.displayName == '技术',
      );
      expect(techSection.entries.single.unreadCount, 2);
    });

    test('指向不存在分组的订阅：归入未分类并记一条诊断（不静默丢行）', () async {
      final _RecordingSink sink = _RecordingSink();
      final GroupRecord reserved = await uncategorized();
      // 直接构造孤儿：绕过用例层（用例层会校验目标分组存在），模拟库被破坏。
      final FeedOverview overview = FeedOverviewReader.buildOverview(
        groups: <GroupRecord>[reserved],
        feeds: <FeedRecord>[
          const FeedRecord(
            id: 1,
            syncId: 'feed.dangling',
            normalizedUrl: 'https://feeds.example.com/dangling.xml',
            name: '孤儿源',
            favorite: false,
            enabled: true,
            sortOrder: 0,
            groupId: 4242,
          ),
        ],
        unreadCounts: const <int, int>{},
        diagnostics: sink,
      );

      expect(overview.totalFeeds, 1);
      expect(
        overview.sections.single.displayName,
        groupUncategorizedDefaultName,
      );
      expect(overview.sections.single.entries.single.feed.name, '孤儿源');
      expect(overview.sections.single.orphanCount, 1);
      expect(sink.messages, isNotEmpty, reason: '必须留痕');
    });

    test('没有任何订阅时是空态（不是错误）', () async {
      final FeedOverviewReader reader = FeedOverviewReader(catalog: catalog);
      final FeedOverview overview = (await reader.read()).unwrap();

      expect(overview.isEmpty, isTrue);
      expect(overview.sections, hasLength(1), reason: '保留组始终存在');
      expect(overview.sections.single.entries, isEmpty);
    });
  });

  group('稳定标识（架构 5.1/5.2）', () {
    test('同一规范化地址在任何设备上得到同一 feed syncId', () {
      final String a = feedSyncIdFor('https://example.com/feed.xml');
      final String b = feedSyncIdFor('https://example.com/feed.xml');
      expect(a, b);
      expect(a, startsWith('feed.'));
      expect(
        feedSyncIdFor('https://example.com/other.xml'),
        isNot(a),
        reason: '不同地址必须得到不同 syncId',
      );
    });

    test('分组 syncId 前缀明确，且与保留组不同', () {
      final DateTime fixed = DateTime.utc(2026, 9, 21, 12);
      final String a = newGroupSyncId(now: fixed, sequence: 0);
      expect(a, startsWith('group.'));
      expect(a, isNot(groupUncategorizedSyncId));
    });
  });
}
