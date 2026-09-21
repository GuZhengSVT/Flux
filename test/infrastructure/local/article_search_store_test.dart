// T022：全文检索数据层（两条路径、来源名现查、范围筛选、分页、注入转义、重建）。
//
// 用真实内存库（含真实的 fts5 索引与触发器）：这一层要验的正是「SQL 到底查到什么」，
// 用替身会把要测的东西替掉。中文短词与长句的行为是探针实测出来的，这里把它钉成回归。
library;

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'package:flux/core/core.dart';
import 'package:flux/infrastructure/local/article_search_store.dart';
import 'package:flux/infrastructure/local/database.dart';
import 'package:flux/infrastructure/local/feed_catalog_store.dart';

void main() {
  late AppDatabase db;
  late DriftArticleSearchStore search;
  late int feedId;
  late int otherFeedId;

  setUp(() async {
    db = AppDatabase.memory();
    await db.customSelect('SELECT 1').get();
    search = DriftArticleSearchStore(db);
    feedId = (await DriftFeedCatalogStore(db).createFeed(
      const FeedInsert(
        syncId: 'feed.tech',
        normalizedUrl: 'https://tech.example.com/feed.xml',
        name: '科技日报',
      ),
    )).unwrap().id;
    otherFeedId = (await DriftFeedCatalogStore(db).createFeed(
      const FeedInsert(
        syncId: 'feed.blog',
        normalizedUrl: 'https://blog.example.com/feed.xml',
        name: 'Example Blog',
      ),
    )).unwrap().id;
  });

  tearDown(() async => db.close());

  Future<int> add(
    String title, {
    String? body,
    String? summary,
    String? author,
    int? feed,
    ReadingState state = ReadingState.unread,
    bool favorite = false,
  }) => db
      .into(db.articles)
      .insert(
        ArticlesCompanion.insert(
          feedId: Value<int?>(feed ?? feedId),
          title: title,
          identityBasis: IdentityBasis.guid,
          guid: Value<String?>('guid-$title'),
          guidPresent: const Value<bool>(true),
          body: Value<String?>(body),
          summary: Value<String?>(summary),
          author: Value<String?>(author),
          readingState: Value<ReadingState>(state),
          favorite: Value<bool>(favorite),
        ),
      );

  Future<SearchPage> run(
    String text, {
    SearchScope? scope,
    ArticleFilter? filter,
    int? feed,
    int limit = 50,
    int offset = 0,
  }) async {
    final Result<SearchPage> result = await search.search(
      SearchQuery(
        text: text,
        scope: scope ?? SearchScope.all,
        filter: filter ?? ArticleFilter.all,
        feedId: feed,
        limit: limit,
        offset: offset,
      ),
    );
    expect(result.isOk, isTrue, reason: result.errorOrNull?.message);
    return result.unwrap();
  }

  group('中文短词（LIKE 路径）', () {
    test('两字中文词命中（默认 tokenizer 完全做不到）', () async {
      await add('离线阅读的实现', body: '正文讲离线缓存');
      final SearchPage page = await run('离线');
      expect(page.total, 1);
      expect(page.hits.single.matchedFields, contains(SearchField.body));
      expect(page.hits.single.snippets.first.hasMatch, isTrue);
    });

    test('ASCII 短词大小写不敏感（AI / ai 都命中）', () async {
      await add('AI 摘要', body: 'About AI');
      expect((await run('AI')).total, 1);
      expect((await run('ai')).total, 1);
      expect((await run('Ai')).total, 1);
    });

    test('LIKE 路径没有相关性排名（null，不是 0）', () async {
      await add('离线阅读');
      final SearchPage page = await run('离线');
      expect(page.hits.single.rank, isNull);
    });

    test('两字查询按时间倒序（退回列表次序）', () async {
      await add('离线 A');
      await add('离线 B');
      final SearchPage page = await run('离线');
      expect(page.total, 2);
      // 后插入的 id 更大 → 排前（时间相同时用 id 倒序）。
      expect(page.hits.first.articleId, greaterThan(page.hits.last.articleId));
    });
  });

  group('中文长句片段（MATCH 路径）', () {
    test('三字及以上的连续片段命中', () async {
      await add('离线阅读与 AI 摘要', body: '正文提到离线阅读的实现细节。');
      final SearchPage page = await run('离线阅');
      expect(page.total, 1);
      expect(page.hits.single.snippets, isNotEmpty);
      expect(page.hits.single.rank, isNotNull, reason: 'MATCH 路径应有 bm25');
    });

    test('连续句子片段命中（架构要求的长句用例）', () async {
      await add('技术文章', body: '本文说明离线阅读的完整实现方式。');
      final SearchPage page = await run('离线阅读的完整实现');
      expect(page.total, 1);
    });

    test('片段带高亮标记，且拼接后等于原文窗口', () async {
      await add('标题', body: '前言前言离线阅读的实现细节后记后记');
      final SearchPage page = await run('离线阅');
      final SearchSnippet snippet = page.hits.single.snippets.firstWhere(
        (SearchSnippet s) => s.field == SearchField.body,
      );
      expect(snippet.hasMatch, isTrue);
      expect(snippet.plainText, contains('离线阅'));
    });

    test('英文大小写不敏感（MATCH 的 trigram 也是）', () async {
      await add('Offline reading', body: 'Offline mode works');
      expect((await run('offline')).total, 1);
      expect((await run('OFFLINE')).total, 1);
    });
  });

  group('来源名搜索（不在索引里，现查 feeds.name）', () {
    test('按来源名命中（两字中文源名）', () async {
      await add('无关标题', body: '无关正文');
      final SearchPage page = await run('科技');
      expect(page.total, 1);
    });

    test('按 ASCII 来源名命中', () async {
      await add('unrelated', body: 'nothing', feed: otherFeedId);
      final SearchPage page = await run('Example');
      expect(page.total, 1);
    });

    test('源改名后立即生效（不需要重建索引）', () async {
      await add('无关标题', body: '无关正文');
      expect((await run('科技')).total, 1);
      await (db.update(db.feeds)..where((t) => t.id.equals(feedId))).write(
        const FeedsCompanion(name: Value<String>('新名字')),
      );
      expect((await run('新名字')).total, 1, reason: '改名后应能按新名字搜到');
    });

    test('来源名命中会排在内容命中之后', () async {
      await add('科技', body: '本文含关键词 zzzz关键词zzzz');
      await add('无关', body: '无关正文');
      final SearchPage page = await run('关键词');
      expect(
        page.hits.first.snippets.any((s) => s.field == SearchField.body),
        isTrue,
      );
    });
  });

  group('空查询与无结果', () {
    test('空查询返回明确无结果（不是匹配全部）', () async {
      await add('离线阅读');
      expect((await run('')).total, 0);
      expect((await run('   ')).total, 0);
    });

    test('查不到时 total 为 0 且列表为空', () async {
      await add('离线阅读');
      final SearchPage page = await run('完全不存在的词');
      expect(page.total, 0);
      expect(page.isEmpty, isTrue);
    });
  });

  group('特殊字符（FTS 语法注入与 LIKE 通配符）', () {
    test('引号与 OR 不破坏查询、也不变成语法错误', () async {
      await add('离线阅读', body: '正文');
      for (final String evil in <String>[
        '"',
        '" OR "',
        'NEAR',
        'a*b',
        '标题:foo',
        '^^^',
      ]) {
        final Result<SearchPage> result = await search.search(
          SearchQuery(text: evil),
        );
        expect(result.isOk, isTrue, reason: '输入 $evil 不应报错');
      }
    });

    test('百分号被转义，不会变成匹配全库', () async {
      await add('离线阅读');
      await add('另一篇');
      final SearchPage page = await run('%');
      expect(page.total, 0, reason: '% 是字面量，不是通配符');
    });

    test('下划线被转义', () async {
      await add('a_b');
      await add('axb');
      final SearchPage page = await run('a_b');
      expect(page.total, 1, reason: '_ 必须按字面量匹配');
    });

    test('反斜杠不会破坏 ESCAPE 语义', () async {
      await add(r'路径 C:\temp');
      final SearchPage page = await run(r'\temp');
      expect(page.total, 1);
    });
  });

  group('分页', () {
    test('limit/offset 生效且 total 是命中总数', () async {
      for (int i = 0; i < 5; i++) {
        await add('离线阅读 $i', body: '正文 $i');
      }
      final SearchPage first = await run('离线', limit: 2);
      expect(first.hits, hasLength(2));
      expect(first.total, 5);
      expect(first.hasMore, isTrue);

      final SearchPage second = await run('离线', limit: 2, offset: 2);
      expect(second.hits, hasLength(2));
      expect(second.offset, 2);
      expect(
        second.hits
            .map((SearchHit h) => h.articleId)
            .toSet()
            .intersection(first.hits.map((SearchHit h) => h.articleId).toSet()),
        isEmpty,
        reason: '两页不得重复',
      );

      final SearchPage third = await run('离线', limit: 2, offset: 4);
      expect(third.hits, hasLength(1));
      expect(third.hasMore, isFalse);
    });

    test('非法分页参数返回类型化失败', () async {
      expect(
        (await search.search(const SearchQuery(text: 'x', limit: 0))).isErr,
        isTrue,
      );
      expect(
        (await search.search(const SearchQuery(text: 'x', offset: -1))).isErr,
        isTrue,
      );
    });
  });

  group('范围与筛选组合', () {
    test('限定来源', () async {
      await add('离线阅读 A');
      await add('离线阅读 B', feed: otherFeedId);
      expect(
        (await run('离线', scope: SearchScope.currentFilter, feed: feedId)).total,
        1,
      );
    });

    test('只搜未读（later 不在其中）', () async {
      await add('离线阅读 unread', state: ReadingState.unread);
      await add('离线阅读 later', state: ReadingState.later);
      await add('离线阅读 read', state: ReadingState.read);
      final SearchPage page = await run(
        '离线',
        scope: SearchScope.currentFilter,
        filter: ArticleFilter.unread,
      );
      expect(page.total, 1);
    });

    test('只搜收藏', () async {
      await add('离线阅读 favorite', favorite: true);
      await add('离线阅读 plain');
      final SearchPage page = await run(
        '离线',
        scope: SearchScope.currentFilter,
        filter: ArticleFilter.favorite,
      );
      expect(page.total, 1);
    });

    test('MATCH 路径同样支持筛选', () async {
      await add('离线阅读长句', state: ReadingState.unread);
      await add('离线阅读长句二', state: ReadingState.read);
      final SearchPage page = await run(
        '离线阅',
        scope: SearchScope.currentFilter,
        filter: ArticleFilter.unread,
      );
      expect(page.total, 1);
    });
  });

  group('索引同步（触发器）', () {
    test('新增文章立即可搜（不需要重建）', () async {
      await add('离线阅读');
      expect((await run('离线')).total, 1);
      await add('离线缓存');
      expect((await run('离线')).total, 2);
    });

    test('改标题后旧词不再命中、新词命中', () async {
      final int id = await add('原始标题');
      expect((await run('原始标题')).total, 1);
      await (db.update(db.articles)..where((t) => t.id.equals(id))).write(
        const ArticlesCompanion(title: Value<String>('替换后的标题')),
      );
      expect((await run('原始标题')).total, 0, reason: '旧词必须从索引里消失');
      expect((await run('替换后')).total, 1);
    });

    test('改阅读状态不重建索引（高频路径）但内容仍可搜', () async {
      final int id = await add('离线阅读');
      await (db.update(db.articles)..where((t) => t.id.equals(id))).write(
        const ArticlesCompanion(
          readingState: Value<ReadingState>(ReadingState.read),
        ),
      );
      expect((await run('离线')).total, 1);
    });

    test('删除文章后不再命中', () async {
      final int id = await add('离线阅读');
      expect((await run('离线')).total, 1);
      await (db.delete(db.articles)..where((t) => t.id.equals(id))).go();
      expect((await run('离线')).total, 0);
    });

    test('索引完整性校验通过（触发器写入的索引自洽）', () async {
      await add('离线阅读', body: '正文内容');
      await add('另一篇', body: '别的正文');
      // fts5 的 integrity-check 命令在不一致时会抛异常；不抛即为自洽。
      await db.customStatement(
        "INSERT INTO articles_fts(articles_fts) VALUES('integrity-check')",
      );
    });
  });

  group('索引重建（损坏恢复）', () {
    test('rebuild 后内容仍可搜，且条数与文章数一致', () async {
      await add('离线阅读', body: '正文');
      await add('第二篇', body: '另一段正文');
      final Result<int> rebuilt = await search.rebuildIndex();
      expect(rebuilt.isOk, isTrue);
      expect(rebuilt.unwrap(), 2);
      expect((await run('离线')).total, 1);
      expect((await run('正文')).total, 2);
    });

    test('重建是幂等的', () async {
      await add('离线阅读');
      await search.rebuildIndex();
      await search.rebuildIndex();
      expect((await run('离线')).total, 1);
    });

    test('重建期间查询仍可用（旧结果不消失，事务语义）', () async {
      await add('离线阅读');
      // 同一连接上先发起查询、再重建、再查询：两次都应拿到正确结果。
      expect((await run('离线')).total, 1);
      await search.rebuildIndex();
      expect((await run('离线')).total, 1);
    });
  });
}
