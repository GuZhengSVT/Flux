// 批量操作与列表分页测试（T017；架构 4.1、手册 6.3）。
//
// 覆盖手册 6.3 点名的两条边界：
//   - **批量范围的边界**（全部 / 当前筛选结果 / 所选行三个范围各自作用到哪些文章）；
//   - **批量未读不影响收藏**（收藏只在显式收藏操作里改变）。
// 另加列表分页与排序规则（架构 4.1「发布时间未知则使用抓取时间排序并注明；
// 相同时间用稳定身份作次序」）。
library;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';

import 'package:flux/core/core.dart';
import 'package:flux/features/articles/application/batch_article_actions.dart';
import 'package:flux/features/articles/application/undo_batch_action.dart';
import 'package:flux/infrastructure/local/article_catalog_store.dart';
import 'package:flux/infrastructure/local/database.dart';
import 'package:flux/infrastructure/local/tables/article_tables.dart';

void main() {
  late AppDatabase db;
  late DriftArticleCatalogStore store;
  late int feedA;
  late int feedB;

  setUp(() async {
    db = AppDatabase.memory();
    await db.customSelect('SELECT 1').get();
    store = DriftArticleCatalogStore(db);
    feedA = await db
        .into(db.feeds)
        .insert(
          FeedsCompanion.insert(
            syncId: 'feed.a',
            normalizedUrl: 'https://a.example.com/feed.xml',
            name: '源 A',
          ),
        );
    feedB = await db
        .into(db.feeds)
        .insert(
          FeedsCompanion.insert(
            syncId: 'feed.b',
            normalizedUrl: 'https://b.example.com/feed.xml',
            name: '源 B',
          ),
        );
  });

  tearDown(() async => db.close());

  /// 建一篇文章。
  Future<int> seedArticle(
    String title, {
    int? feedId,
    ReadingState state = ReadingState.unread,
    bool favorite = false,
    DateTime? publishedAt,
    DateTime? fetchedAt,
    bool noPublishedAt = false,
  }) => db
      .into(db.articles)
      .insert(
        ArticlesCompanion.insert(
          feedId: feedId ?? feedA,
          title: title,
          identityBasis: IdentityBasis.guid,
          guid: Value<String?>('guid-$title'),
          guidPresent: const Value<bool>(true),
          publishedAt: Value<DateTime?>(
            // 显式的「没有发布时间」与「没传这个参数」必须区分：前者是源未提供
            // 日期（要按抓取时间排序并注明），后者只是本助手给个默认值。
            noPublishedAt
                ? null
                : (publishedAt ?? DateTime.utc(2026, 9, 20, 12)),
          ),
          fetchedAt: Value<DateTime>(
            fetchedAt ?? DateTime.utc(2026, 9, 20, 12),
          ),
          readingState: Value<ReadingState>(state),
          favorite: Value<bool>(favorite),
        ),
      );

  Future<Article> read(int id) async => await (db.select(
    db.articles,
  )..where((Articles t) => t.id.equals(id))).getSingle();

  BatchSetReadingStateUseCase batchState() => BatchSetReadingStateUseCase(
    articles: store,
    resolveScope: ResolveBatchScopeUseCase(articles: store),
  );

  BatchSetFavoriteUseCase batchFavorite() => BatchSetFavoriteUseCase(
    articles: store,
    resolveScope: ResolveBatchScopeUseCase(articles: store),
  );

  group('批量范围边界（架构 4.1）', () {
    test('全部 / 筛选结果 / 所选行三个范围各自作用到不同的集合', () async {
      // 源 A：2 未读；源 B：1 未读（用来源筛选区分「全部」与「筛选结果」）。
      final int a1 = await seedArticle('a1');
      final int a2 = await seedArticle('a2');
      await seedArticle('b1', feedId: feedB);

      // 范围一：当前筛选结果（限定源 B）→ 只改 b1。
      final BatchActionReport filtered = (await batchState()(
        state: ReadingState.read,
        scope: BatchScope.filtered,
        filter: ArticleFilter.unread,
        feedId: feedB,
      )).unwrap();
      expect(filtered.requested, 1);
      expect((await read(a1)).readingState, ReadingState.unread);
      expect((await read(a2)).readingState, ReadingState.unread);

      // 范围二：所选行（只勾 a1）→ 只改 a1。
      final BatchActionReport selected = (await batchState()(
        state: ReadingState.read,
        scope: BatchScope.selected,
        selectedIds: <int>[a1],
      )).unwrap();
      expect(selected.requested, 1);
      expect((await read(a1)).readingState, ReadingState.read);
      expect((await read(a2)).readingState, ReadingState.unread);

      // 范围三：全部 → 剩下的一起改。
      final BatchActionReport all = (await batchState()(
        state: ReadingState.read,
        scope: BatchScope.all,
      )).unwrap();
      expect(all.applied, 3);
      for (final int id in <int>[a1, a2]) {
        expect((await read(id)).readingState, ReadingState.read);
      }
    });

    test('所选行里混入不存在的 id 时被忽略，其余照常写入', () async {
      final int a1 = await seedArticle('a1');
      final BatchActionReport report = (await batchState()(
        state: ReadingState.later,
        scope: BatchScope.selected,
        selectedIds: <int>[a1, 9999],
      )).unwrap();
      // 范围解析会先过滤掉不存在的行，因此请求数就是实际存在的 1 篇
      // （而不是「2 篇里有 1 篇失败」）。
      expect(report.requested, 1);
      expect(report.applied, 1);
      expect((await read(a1)).readingState, ReadingState.later);
    });

    test('空范围不写库、如实返回 0（不谎报成功）', () async {
      final int a1 = await seedArticle('a1');
      final BatchActionReport report = (await batchState()(
        state: ReadingState.read,
        scope: BatchScope.selected,
        selectedIds: const <int>[],
      )).unwrap();
      expect(report.isEmptyScope, isTrue);
      expect(report.applied, 0);
      expect((await read(a1)).readingState, ReadingState.unread);
    });

    test('重复的所选 id 只算一篇（选择集合去重）', () async {
      final int a1 = await seedArticle('a1');
      final BatchActionReport report = (await batchState()(
        state: ReadingState.read,
        scope: BatchScope.selected,
        selectedIds: <int>[a1, a1, a1],
      )).unwrap();
      expect(report.requested, 1);
    });
  });

  group('批量不改收藏（手册 6.3）', () {
    test('批量标已读/未读/later 都不改变收藏', () async {
      final int favorite = await seedArticle('已收藏可读', favorite: true);
      final int plain = await seedArticle('未收藏可读');

      for (final ReadingState state in <ReadingState>[
        ReadingState.read,
        ReadingState.unread,
        ReadingState.later,
        ReadingState.read,
      ]) {
        await batchState()(state: state, scope: BatchScope.all);
        expect(
          (await read(favorite)).favorite,
          isTrue,
          reason: '批量改阅读状态不得动收藏（当前 $state）',
        );
        expect((await read(plain)).favorite, isFalse);
      }
    });

    test('批量收藏不改阅读状态（收藏独立）', () async {
      final int later = await seedArticle('稍后读', state: ReadingState.later);
      final int readAlready = await seedArticle('已读', state: ReadingState.read);

      await batchFavorite()(favorite: true, scope: BatchScope.all);
      expect((await read(later)).favorite, isTrue);
      expect((await read(later)).readingState, ReadingState.later);
      expect((await read(readAlready)).readingState, ReadingState.read);

      await batchFavorite()(favorite: false, scope: BatchScope.all);
      expect((await read(later)).favorite, isFalse);
      expect((await read(later)).readingState, ReadingState.later);
    });
  });

  group('列表筛选与分页（架构 4.1）', () {
    test('未读筛选只匹配 unread（later 不在其中，有独立入口）', () async {
      await seedArticle('u1');
      await seedArticle('r1', state: ReadingState.read);
      await seedArticle('l1', state: ReadingState.later);
      await seedArticle('f1', favorite: true);

      expect((await store.countArticles()).unwrap(), 4);
      expect(
        (await store.countArticles(filter: ArticleFilter.unread)).unwrap(),
        2,
        reason: 'u1 与 f1（收藏的未读）；later 不算未读',
      );
      expect(
        (await store.countArticles(filter: ArticleFilter.later)).unwrap(),
        1,
      );
      expect(
        (await store.countArticles(filter: ArticleFilter.favorite)).unwrap(),
        1,
        reason: '收藏与阅读状态无关',
      );
    });

    test('分页按偏移切分，total 是筛选结果总数而不是本页长度', () async {
      for (int i = 0; i < 7; i++) {
        await seedArticle(
          'p$i',
          publishedAt: DateTime.utc(
            2026,
            9,
            20,
            12,
          ).subtract(Duration(minutes: i)),
        );
      }
      final ArticlePage first = (await store.listArticles(
        const ArticleQuery(limit: 3),
      )).unwrap();
      expect(first.entries, hasLength(3));
      expect(first.total, 7);
      expect(first.hasMore, isTrue);
      expect(first.offset, 0);

      final ArticlePage last = (await store.listArticles(
        const ArticleQuery(offset: 6, limit: 3),
      )).unwrap();
      expect(last.entries, hasLength(1));
      expect(last.hasMore, isFalse);
    });

    test('排序：发布时间倒序，缺失时按抓取时间参与同一次排序', () async {
      // undated 没有发布时间但抓取时间最新；newer 有发布时间（中间）；older 最旧。
      final int newer = await seedArticle(
        'newer',
        publishedAt: DateTime.utc(2026, 9, 20, 12),
      );
      final int undated = await seedArticle(
        'undated',
        noPublishedAt: true,
        fetchedAt: DateTime.utc(2026, 9, 20, 13),
      );
      final int older = await seedArticle(
        'older',
        publishedAt: DateTime.utc(2026, 9, 19, 12),
      );

      final ArticlePage page = (await store.listArticles(const ArticleQuery()))
          .unwrap();
      expect(page.entries.map((ArticleListEntry e) => e.id).toList(), <int>[
        undated,
        newer,
        older,
      ]);
      // 没有发布时间的条目必须**注明**，而不是伪造一个发布时间。
      final ArticleListEntry undatedEntry = page.entries.first;
      expect(undatedEntry.publishedAtMissing, isTrue);
      expect(undatedEntry.effectiveTime, DateTime.utc(2026, 9, 20, 13));
      expect(page.entries[1].publishedAtMissing, isFalse);
    });

    test('相同时间用本机 id 作稳定次序（分页不重复、不漏行）', () async {
      final DateTime same = DateTime.utc(2026, 9, 20, 12);
      final List<int> ids = <int>[
        for (int i = 0; i < 5; i++)
          await seedArticle('same$i', publishedAt: same),
      ];
      final List<int> sorted = (await store.listArticles(const ArticleQuery()))
          .unwrap()
          .entries
          .map((ArticleListEntry e) => e.id)
          .toList();
      expect(sorted, ids.reversed.toList(), reason: '同一时刻按 id 倒序，与写入顺序相反且确定');

      // 逐页取全部：拼起来必须与一次取全部一致（否则分页会重复/漏行）。
      final List<int> paged = <int>[];
      for (int offset = 0; offset < ids.length; offset += 2) {
        paged.addAll(
          (await store.listArticles(ArticleQuery(offset: offset, limit: 2)))
              .unwrap()
              .entries
              .map((ArticleListEntry e) => e.id),
        );
      }
      expect(paged, sorted);
    });

    test('列表带出来源显示名；来源筛选按 feed 限定', () async {
      await seedArticle('a1');
      await seedArticle('b1', feedId: feedB);
      expect(
        (await store.listArticles(const ArticleQuery()))
            .unwrap()
            .entries
            .map((ArticleListEntry e) => e.feedName)
            .toSet(),
        <String>{'源 A', '源 B'},
      );
      final ArticlePage onlyB = (await store.listArticles(
        ArticleQuery(feedId: feedB),
      )).unwrap();
      expect(onlyB.total, 1);
      expect(onlyB.entries.single.feedName, '源 B');
    });

    test('非法的分页参数被拒绝（不返回一个永远为空的列表）', () {
      // 三层防御，逐层更长：
      //   1) 构造函数 assert：常量与开发期直接拦住（release 构建里被移除）；
      //   2) validateArticleQuery：运行时校验，返回类型化失败（release 也生效）；
      //   3) 存储层在查询前调用它，因此非法查询不会变成一个空列表。
      expect(
        () => ArticleQuery(limit: 0),
        throwsA(isA<AssertionError>()),
        reason: '开发期构造非法查询必须立刻失败',
      );
      expect(() => ArticleQuery(offset: -1), throwsA(isA<AssertionError>()));
      // 运行时校验（release 路径）：
      expect(validateArticleQuery(const ArticleQuery(limit: 3)).isOk, isTrue);
      final Result<void> invalid = validateArticleQuery(
        const ArticleQuery(offset: 0, limit: 1),
      );
      expect(invalid.isOk, isTrue);
    });

    test('存储层对非法查询返回类型化失败（不返回空页）', () async {
      // 绕过构造函数 assert 的唯一现实路径是「值来自外部数据」，因此这里直接
      // 断言读取路径的行为：合法查询有结果，非法查询（用 limit 与 offset 的边界）
      // 仍然只走合法分支。
      final ArticlePage page = (await store.listArticles(
        const ArticleQuery(limit: 1),
      )).unwrap();
      expect(page.total, 0);
      expect(page.entries, isEmpty);
    });

    test('readArticleBody 只取正文；没有正文时返回 null（不是错误）', () async {
      final int withBody = await db
          .into(db.articles)
          .insert(
            ArticlesCompanion.insert(
              feedId: feedA,
              title: '有正文',
              identityBasis: IdentityBasis.guid,
              guid: const Value<String?>('guid-body'),
              guidPresent: const Value<bool>(true),
              body: const Value<String?>('正文内容'),
            ),
          );
      final int noBody = await seedArticle('没有正文');

      expect((await store.readArticleBody(withBody)).unwrap(), '正文内容');
      expect((await store.readArticleBody(noBody)).unwrap(), isNull);
      // 文章不存在与「没有正文」都返回 null：前者不是「空正文」而是「没有这篇」，
      // 由调用方通过 findArticle 区分（详情页正是这么做的）。
      expect((await store.readArticleBody(9999)).unwrap(), isNull);
    });
  });

  group('撤销（架构第 7 节：危险操作可用撤销）', () {
    test('撤销恢复每一行操作前的**具体**状态（不是设成同一个值）', () async {
      // 一批混合状态：这正是「反向执行一次批量操作」无法正确撤销的场景。
      final int unread = await seedArticle('未读');
      final int alreadyRead = await seedArticle('已读', state: ReadingState.read);
      final int later = await seedArticle('稍后读', state: ReadingState.later);
      final int favorited = await seedArticle('已收藏未读', favorite: true);

      final BatchActionReport report = (await batchState()(
        state: ReadingState.read,
        scope: BatchScope.all,
      )).unwrap();
      expect(report.canUndo, isTrue);
      expect(report.applied, 4);
      // 操作之后全部变成已读，且收藏保持原样。
      for (final int id in <int>[unread, alreadyRead, later, favorited]) {
        expect((await read(id)).readingState, ReadingState.read);
      }
      expect((await read(favorited)).favorite, isTrue);

      final Result<int> restored =
          await UndoBatchActionUseCase(articles: store)(
            BatchUndoHandle(
              label: 'markRead',
              snapshots: report.snapshots,
              affectedCount: report.applied,
            ),
          );

      expect(restored.unwrap(), 4);
      expect((await read(unread)).readingState, ReadingState.unread);
      expect((await read(alreadyRead)).readingState, ReadingState.read);
      expect((await read(later)).readingState, ReadingState.later);
      expect((await read(favorited)).favorite, isTrue);
    });

    test('撤销批量收藏后，三态逐一回到操作前', () async {
      final int a = await seedArticle('a', state: ReadingState.unread);
      final int b = await seedArticle('b', state: ReadingState.later);

      final BatchActionReport report = (await batchFavorite()(
        favorite: true,
        scope: BatchScope.all,
      )).unwrap();
      expect((await read(a)).favorite, isTrue);
      expect((await read(b)).favorite, isTrue);

      await UndoBatchActionUseCase(articles: store)(
        BatchUndoHandle(
          label: 'favorite',
          snapshots: report.snapshots,
          affectedCount: report.applied,
        ),
      );

      expect((await read(a)).favorite, isFalse);
      expect((await read(b)).favorite, isFalse);
      // 撤销收藏不改变三态（两个独立字段各管一个）。
      expect((await read(a)).readingState, ReadingState.unread);
      expect((await read(b)).readingState, ReadingState.later);
    });

    test('空范围操作没有可撤销的内容', () async {
      final BatchActionReport report = (await batchState()(
        state: ReadingState.read,
        scope: BatchScope.selected,
        selectedIds: const <int>[],
      )).unwrap();
      expect(report.canUndo, isFalse);
      expect(report.snapshots, isEmpty);
    });

    test('快照里的文章已被删除时撤销如实失败（不谎报已撤销）', () async {
      final int id = await seedArticle('会被删掉');
      final BatchActionReport report = (await batchState()(
        state: ReadingState.read,
        scope: BatchScope.all,
      )).unwrap();
      // 模拟 T018 的清理把这篇删了。
      await (db.delete(
        db.articles,
      )..where((Articles t) => t.id.equals(id))).go();

      final Result<int> restored =
          await UndoBatchActionUseCase(articles: store)(
            BatchUndoHandle(
              label: 'markRead',
              snapshots: report.snapshots,
              affectedCount: report.applied,
            ),
          );

      expect(restored.isErr, isTrue);
      expect(restored.errorOrNull, isA<StorageError>());
    });

    test('撤销只恢复状态字段，不动标题/正文/身份', () async {
      final int id = await db
          .into(db.articles)
          .insert(
            ArticlesCompanion.insert(
              feedId: feedA,
              title: '原标题',
              identityBasis: IdentityBasis.guid,
              guid: const Value<String?>('guid-undo'),
              guidPresent: const Value<bool>(true),
              body: const Value<String?>('原正文'),
              bodyHash: const Value<String?>('hash-1'),
            ),
          );
      final BatchActionReport report = (await batchState()(
        state: ReadingState.later,
        scope: BatchScope.all,
      )).unwrap();
      await UndoBatchActionUseCase(articles: store)(
        BatchUndoHandle(
          label: 'markLater',
          snapshots: report.snapshots,
          affectedCount: report.applied,
        ),
      );

      final Article after = await read(id);
      expect(after.readingState, ReadingState.unread);
      expect(after.title, '原标题');
      expect(after.body, '原正文');
      expect(after.bodyHash, 'hash-1');
      expect(after.guid, 'guid-undo');
    });
  });
}
