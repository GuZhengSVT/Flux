// 三态与收藏的用例测试（T017；架构 4.1、手册 6.3）。
//
// 覆盖手册 6.3 点名的三条：
//   - 三态：每一对状态切换都成立（unread→read→later→read… 的往返）；
//   - later 打开不变 read（SET-010 的自动标已读不得碰 later）；
//   - 并发改 read/later 不出现双状态（条件写在 SQL 里）；
// 以及「收藏独立」这条产品规则。
//
// 用真实内存数据库（不是替身）：这些规则的最后一道保险在 SQL 条件与 CHECK 约束里，
// 用假端口会验证成「调用了一个方法」而不是「库里真的是这个状态」。
library;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';

import 'package:flux/core/core.dart';
import 'package:flux/features/articles/application/article_state.dart';
import 'package:flux/infrastructure/local/article_catalog_store.dart';
import 'package:flux/infrastructure/local/database.dart';
import 'package:flux/infrastructure/local/tables/article_tables.dart';

void main() {
  late AppDatabase db;
  late DriftArticleCatalogStore store;
  late int feedId;

  setUp(() async {
    db = AppDatabase.memory();
    await db.customSelect('SELECT 1').get();
    store = DriftArticleCatalogStore(db);
    feedId = await db
        .into(db.feeds)
        .insert(
          FeedsCompanion.insert(
            syncId: 'feed.a',
            normalizedUrl: 'https://a.example.com/feed.xml',
            name: '源 A',
          ),
        );
  });

  tearDown(() async => db.close());

  /// 插入一篇文章，返回 id。
  Future<int> seedArticle(
    String title, {
    ReadingState state = ReadingState.unread,
    bool favorite = false,
  }) => db
      .into(db.articles)
      .insert(
        ArticlesCompanion.insert(
          feedId: Value<int?>(feedId),
          title: title,
          identityBasis: IdentityBasis.guid,
          guid: Value<String?>('guid-$title'),
          guidPresent: const Value<bool>(true),
          publishedAt: Value<DateTime?>(DateTime.utc(2026, 9, 20, 12)),
          readingState: Value<ReadingState>(state),
          favorite: Value<bool>(favorite),
        ),
      );

  Future<Article> read(int id) async => await (db.select(
    db.articles,
  )..where((Articles t) => t.id.equals(id))).getSingle();

  group('三态互斥（架构 4.1）', () {
    test('三值可在任意方向上互相迁移，且任一时刻只有一个状态', () async {
      final int id = await seedArticle('往返');
      final SetReadingStateUseCase setState = SetReadingStateUseCase(
        articles: store,
      );

      // 手册 6.3 点名的路径：unread → read → later → read → unread → later。
      for (final ReadingState target in <ReadingState>[
        ReadingState.read,
        ReadingState.later,
        ReadingState.read,
        ReadingState.unread,
        ReadingState.later,
      ]) {
        final Result<ArticleStateChange> result = await setState(
          articleId: id,
          state: target,
        );
        expect(result.isOk, isTrue, reason: '切换到 $target 应成功');
        expect(result.unwrap().changed, isTrue);
        // 库里只有一个 reading_state 列，因此「已读且稍后读」在结构上不可能存在。
        expect((await read(id)).readingState, target);
      }
    });

    test('设置成当前状态时不写入、也不推进 updatedAt（幂等点击）', () async {
      final int id = await seedArticle('已读', state: ReadingState.read);
      final DateTime before = (await read(id)).updatedAt;

      final Result<ArticleStateChange> result = await SetReadingStateUseCase(
        articles: store,
      )(articleId: id, state: ReadingState.read);

      expect(result.unwrap().changed, isFalse);
      expect((await read(id)).updatedAt, before, reason: '无变化不写库');
    });

    test('文章不存在时如实失败（不报告成功）', () async {
      final Result<ArticleStateChange> result = await SetReadingStateUseCase(
        articles: store,
      )(articleId: 9999, state: ReadingState.read);

      expect(result.isErr, isTrue);
      expect(result.errorOrNull, isA<StorageError>());
    });
  });

  group('收藏独立（架构 4.1）', () {
    test('收藏与取消收藏都不改变阅读状态', () async {
      final int id = await seedArticle('稍后再读', state: ReadingState.later);
      final ToggleFavoriteUseCase toggle = ToggleFavoriteUseCase(
        articles: store,
      );

      expect((await toggle(articleId: id, favorite: true)).isOk, isTrue);
      Article row = await read(id);
      expect(row.favorite, isTrue);
      expect(row.readingState, ReadingState.later, reason: '收藏不改三态');

      expect((await toggle(articleId: id, favorite: false)).isOk, isTrue);
      row = await read(id);
      expect(row.favorite, isFalse);
      expect(row.readingState, ReadingState.later);
    });

    test('toggle 翻转当前值，且不影响三态', () async {
      final int id = await seedArticle('未读', state: ReadingState.unread);
      final ToggleFavoriteUseCase toggle = ToggleFavoriteUseCase(
        articles: store,
      );

      await toggle.toggle(id);
      expect((await read(id)).favorite, isTrue);
      expect((await read(id)).readingState, ReadingState.unread);

      await toggle.toggle(id);
      expect((await read(id)).favorite, isFalse);
      expect((await read(id)).readingState, ReadingState.unread);
    });
  });

  group('打开正文自动标已读（SET-010）', () {
    test('unread 打开后变 read', () async {
      final int id = await seedArticle('未读');
      final Result<ArticleStateChange> result = await MarkReadOnOpenUseCase(
        articles: store,
      )(articleId: id, autoMarkEnabled: true);

      expect(result.unwrap().changed, isTrue);
      expect((await read(id)).readingState, ReadingState.read);
    });

    test('later 打开后仍为 later（手册 6.3「later 打开不变 read」）', () async {
      final int id = await seedArticle('稍后再读', state: ReadingState.later);
      final Result<ArticleStateChange> result = await MarkReadOnOpenUseCase(
        articles: store,
      )(articleId: id, autoMarkEnabled: true);

      expect(result.unwrap().changed, isFalse);
      expect(
        (await read(id)).readingState,
        ReadingState.later,
        reason: '只有用户点「标为已读」才变 read',
      );
    });

    test('已读的文章打开不会再次写入', () async {
      final int id = await seedArticle('已读', state: ReadingState.read);
      final DateTime before = (await read(id)).updatedAt;
      final Result<ArticleStateChange> result = await MarkReadOnOpenUseCase(
        articles: store,
      )(articleId: id, autoMarkEnabled: true);

      expect(result.unwrap().changed, isFalse);
      expect((await read(id)).updatedAt, before);
    });

    test('SET-010 关闭时打开不改任何状态（含未读）', () async {
      final int id = await seedArticle('未读');
      final Result<ArticleStateChange> result = await MarkReadOnOpenUseCase(
        articles: store,
      )(articleId: id, autoMarkEnabled: false);

      expect(result.unwrap().changed, isFalse);
      expect((await read(id)).readingState, ReadingState.unread);
    });

    test('并发下 later 不会被打开动作改成 read（条件写在 SQL 里）', () async {
      final int id = await seedArticle('竞争');
      // 模拟「用户点开正文」与「另一端（或另一处）把状态设为 later」交错：
      // 条件写只看**写入那一刻**的库里值，因此后到的 later 不会被覆盖成 read。
      await store.setReadingState(
        articleIds: <int>[id],
        state: ReadingState.later,
      );
      final Result<int> changed = await store.markReadIfUnread(id);

      expect(changed.unwrap(), 0, reason: '受影响 0 行＝什么都没改');
      expect((await read(id)).readingState, ReadingState.later);
    });
  });
}
