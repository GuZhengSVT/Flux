// 删除订阅/分组与保留收藏策略的用例测试（T018；架构 4.1「删除订阅」段、手册 6.3「删除」）。
//
// 覆盖手册点名的必测项：
//   - 默认保留收藏：非收藏（**含 later**）清理、收藏留下并**脱离源 + 冻结来源快照**；
//   - 不保留分支：全部清理；
//   - 影响预览与实际删除的**数字一致**（预览说删几篇，就真的删几篇）；
//   - 事务回滚：注入失败后**一行都不许变**（源还在、文章还在、收藏没脱离）；
//   - 分组删除的两个分支（移动 / 删除其中订阅）。
//
// 全部使用内存库，不联网。
library;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';

import 'package:flux/core/core.dart';
import 'package:flux/features/feeds/application/delete_feed.dart';
import 'package:flux/features/feeds/application/manage_groups.dart';
import 'package:flux/infrastructure/local/database.dart';
import 'package:flux/infrastructure/local/feed_catalog_store.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late DriftFeedCatalogStore catalog;
  late DeleteFeedUseCase deleteFeed;
  late ManageGroupsUseCase groups;
  late DeleteGroupUseCase deleteGroup;
  late int feedId;

  setUp(() async {
    db = AppDatabase.memory();
    await db.customSelect('SELECT 1').get();
    catalog = DriftFeedCatalogStore(db);
    deleteFeed = DeleteFeedUseCase(catalog: catalog);
    groups = ManageGroupsUseCase(catalog: catalog);
    deleteGroup = DeleteGroupUseCase(catalog: catalog);
    feedId = (await catalog.createFeed(
      const FeedInsert(
        syncId: 'feed.a',
        normalizedUrl: 'https://a.example.com/feed.xml',
        name: '示例源',
      ),
    )).unwrap().id;
  });

  tearDown(() async {
    await db.close();
  });

  /// 造一篇文章；[state] 为三态，[favorite] 为收藏。
  Future<int> seed(
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
          guid: Value<String?>(title),
          guidPresent: const Value<bool>(true),
          readingState: Value<ReadingState>(state),
          favorite: Value<bool>(favorite),
        ),
      );

  group('影响预览（只读）', () {
    test('分别给出收藏数、其他数（含 later）与其中 later 数', () async {
      await seed('收藏的', favorite: true);
      await seed('收藏且稍后读的', state: ReadingState.later, favorite: true);
      await seed('稍后读的', state: ReadingState.later);
      await seed('已读的', state: ReadingState.read);

      final FeedDeletionPreview preview = (await deleteFeed.preview(feedId))
          .unwrap();

      expect(preview.favoriteCount, 2);
      expect(preview.otherCount, 2, reason: '非收藏 = later + read，later 必须计入');
      expect(preview.laterCount, 1, reason: 'later 数只统计非收藏里的 later');
      expect(preview.totalCount, 4);
      expect(preview.hasNoArticles, isFalse);
    });

    test('预览是只读的：读完不影响任何一行，也不留下墓碑', () async {
      await seed('一篇', favorite: true);

      await deleteFeed.preview(feedId);
      await deleteFeed.preview(feedId);

      expect(await db.select(db.articles).get(), hasLength(1));
      expect(await db.select(db.feeds).get(), hasLength(1));
      expect(
        await db.select(db.deletionEvents).get(),
        isEmpty,
        reason: '「先看看影响」不能自己成为一次删除',
      );
    });

    test('空源：预览为 0，但界面仍能显示一个说得清的说明', () async {
      final FeedDeletionPreview preview = (await deleteFeed.preview(feedId))
          .unwrap();
      expect(preview.hasNoArticles, isTrue);
      expect(preview.totalCount, 0);
    });

    test('源不存在：类型化错误而不是全 0 的预览', () async {
      final Result<FeedDeletionPreview> result = await deleteFeed.preview(
        98765,
      );
      expect(result.isErr, isTrue);
      expect(result.errorOrNull, isA<StorageError>());
      expect((result.errorOrNull! as StorageError).isMissing, isTrue);
    });
  });

  group('保留收藏分支（SET-081 默认）', () {
    test('收藏留下并脱离源；非收藏含 later 全部清理；来源快照冻结', () async {
      final int kept = await seed('收藏的', favorite: true);
      final int keptLater = await seed(
        '收藏且稍后读的',
        state: ReadingState.later,
        favorite: true,
      );
      await seed('非收藏稍后读的', state: ReadingState.later);
      await seed('非收藏已读的', state: ReadingState.read);
      await seed('非收藏未读的');

      final FeedDeletionOutcome outcome = (await deleteFeed.confirm(
        feedId: feedId,
        keepFavorites: true,
      )).unwrap();

      expect(outcome.keepFavorites, isTrue);
      expect(outcome.keptFavorites, 2);
      expect(outcome.deletedArticles, 3, reason: '含 later 的 3 篇非收藏被清理');

      // 订阅本身真的删了。
      expect(await db.select(db.feeds).get(), isEmpty);

      final List<Article> remaining = await db.select(db.articles).get();
      expect(remaining, hasLength(2));
      expect(remaining.map((Article a) => a.id).toSet(), <int>{
        kept,
        keptLater,
      }, reason: '留下的必须正是那两条收藏');
      for (final Article article in remaining) {
        expect(article.feedId, isNull, reason: '必须脱离源');
        expect(article.feedTitle, '示例源', reason: '来源快照冻结当时的显示名');
        expect(
          article.feedUrl,
          'https://a.example.com/feed.xml',
          reason: '快照用规范化地址',
        );
        expect(article.favorite, isTrue, reason: '收藏值不变（它本来就是留下的依据）');
      }
      // later 那条收藏**仍是 later**：脱离源不改变阅读状态。
      final Article stillLater = remaining.firstWhere(
        (Article a) => a.id == keptLater,
      );
      expect(stillLater.readingState, ReadingState.later);

      // 墓碑记录了这次选择与数字。
      final List<DeletionEvent> events = await db
          .select(db.deletionEvents)
          .get();
      expect(events, hasLength(1));
      expect(events.single.entityType, 'feed');
      expect(events.single.syncId, 'feed.a');
      expect(events.single.keepFavorites, isTrue);
      expect(events.single.deletedArticleCount, 3);
      expect(events.single.keptFavoriteCount, 2);
    });

    test('来源快照冻结：删除后新加同名源不改写快照', () async {
      await seed('收藏的', favorite: true);
      await deleteFeed.confirm(feedId: feedId, keepFavorites: true);

      // 重新添加同一个地址的源并改名，快照必须仍然指向删除那一刻的值。
      final int again = (await catalog.createFeed(
        const FeedInsert(
          syncId: 'feed.a.again',
          normalizedUrl: 'https://a.example.com/feed.xml',
          name: '改名后的源',
        ),
      )).unwrap().id;
      await catalog.renameFeed(feedId: again, name: '又被改了一次');

      final Article kept = (await db.select(db.articles).get()).single;
      expect(kept.feedTitle, '示例源', reason: '快照是历史事实，不随源改名而变');
      expect(kept.feedId, isNull);
    });

    test('一条收藏都没有时：勾选保留也不留下任何文章', () async {
      await seed('非收藏一');
      await seed('非收藏二', state: ReadingState.later);

      final FeedDeletionOutcome outcome = (await deleteFeed.confirm(
        feedId: feedId,
        keepFavorites: true,
      )).unwrap();

      expect(outcome.keptFavorites, 0);
      expect(outcome.deletedArticles, 2);
      expect(await db.select(db.articles).get(), isEmpty);
    });
  });

  group('不保留收藏分支', () {
    test('取消保留：收藏也一起清理，且不留脱离源的行', () async {
      await seed('收藏的', favorite: true);
      await seed('收藏且稍后读的', state: ReadingState.later, favorite: true);
      await seed('非收藏的');

      final FeedDeletionOutcome outcome = (await deleteFeed.confirm(
        feedId: feedId,
        keepFavorites: false,
      )).unwrap();

      expect(outcome.keepFavorites, isFalse);
      expect(outcome.keptFavorites, 0);
      expect(outcome.deletedArticles, 3);
      expect(await db.select(db.articles).get(), isEmpty);
      expect(await db.select(db.feeds).get(), isEmpty);

      final DeletionEvent event =
          (await db.select(db.deletionEvents).get()).single;
      expect(
        event.keepFavorites,
        isFalse,
        reason: '墓碑必须记下当次选择，否则同步端无法知道本机当时选了哪一档',
      );
    });
  });

  group('事务回滚（注入失败）', () {
    test('写文章时失败：订阅、文章、收藏归属全部保持原样', () async {
      await seed('收藏的', favorite: true);
      await seed('非收藏的', state: ReadingState.later);

      // 注入失败：在**文章清理那一步**挂一个会 ABORT 的触发器。
      //
      // 为什么用触发器而不是「传一个坏 id」：本用例要证明的是「保留收藏的快照写入」
      // 也会被回滚，因此失败必须发生在快照写入**之后**。触发器正好落在清理文章那一步
      // ——此时收藏已经从源上脱离（feed_id 已置空）、快照已写入，事务回滚必须把这一切
      // 撤回。若失败发生在最开始（例如源不存在），就完全测不到这一点。
      await db.customStatement(
        'CREATE TRIGGER t018_block_article_delete '
        'BEFORE DELETE ON articles BEGIN '
        "SELECT RAISE(ABORT, 'injected failure for rollback test'); "
        'END',
      );

      final Result<FeedDeletionOutcome> result = await deleteFeed.confirm(
        feedId: feedId,
        keepFavorites: true,
      );

      await db.customStatement('DROP TRIGGER t018_block_article_delete');

      expect(result.isErr, isTrue, reason: '失败必须如实报告，不能吞掉');
      expect(result.errorOrNull, isA<StorageError>());

      // 关键：**一行都不许变**。半删状态（源没了、文章还在，或收藏刚脱离就中断）
      // 比整批失败更糟，因为用户无法理解也无法修复。
      expect(await db.select(db.feeds).get(), hasLength(1));
      final List<Article> articles = await db.select(db.articles).get();
      expect(articles, hasLength(2));
      for (final Article article in articles) {
        expect(article.feedId, feedId, reason: '归属必须回到原样，不能停在已脱离');
        expect(article.feedTitle, isNull);
        expect(article.feedUrl, isNull);
      }
      expect(
        await db.select(db.deletionEvents).get(),
        isEmpty,
        reason: '回滚后不得留下墓碑（否则同步端会以为这次删除发生了）',
      );
    });
  });

  group('分组删除（T018 起真正删除）', () {
    /// 建一个分组并把当前订阅放进去。
    Future<int> groupWithFeed(String name) async {
      final GroupRecord group = (await groups.create(name: name)).unwrap();
      await catalog.moveFeedToGroup(feedId: feedId, groupId: group.id);
      return group.id;
    }

    test('移动到未分类：订阅与文章都保留，只改归属；组内收藏不受影响', () async {
      final int groupId = await groupWithFeed('技术');
      await seed('收藏的', favorite: true);
      await seed('非收藏的', state: ReadingState.later);

      final GroupDeletionOutcome outcome = (await deleteGroup.confirm(
        groupId: groupId,
        mode: GroupDeletionMode.moveToUncategorized,
        keepFavorites: true,
      )).unwrap();

      expect(outcome.movedFeedCount, 1);
      expect(outcome.deletedFeedCount, 0);
      expect(outcome.deletedArticles, 0);
      final Feed moved = (await db.select(db.feeds).get()).single;
      expect(moved.id, feedId);
      final Group reserved = (await db.select(db.groups).get()).single;
      expect(reserved.syncId, groupUncategorizedSyncId);
      expect(moved.groupId, reserved.id);
      expect(await db.select(db.articles).get(), hasLength(2));
      // 移动分支不涉及「保留收藏」的选择，墓碑里该字段为 null。
      final DeletionEvent event =
          (await db.select(db.deletionEvents).get()).single;
      expect(event.entityType, 'group');
      expect(event.keepFavorites, isNull);
    });

    test('删除其中订阅：复用同一套保留收藏规则（收藏脱离源、later 清理）', () async {
      final int groupId = await groupWithFeed('技术');
      await seed('收藏的', favorite: true);
      await seed('稍后读的', state: ReadingState.later);

      final Result<GroupDeletionPreview> preview = await deleteGroup.preview(
        groupId: groupId,
        groupName: '技术',
      );
      final GroupDeletionPreview p = preview.unwrap();
      expect(p.feedCount, 1);
      expect(p.favoriteCount, 1);
      expect(p.otherCount, 1);
      expect(p.laterCount, 1);
      expect(p.totalCount, 2);

      final GroupDeletionOutcome outcome = (await deleteGroup.confirm(
        groupId: groupId,
        mode: GroupDeletionMode.deleteFeeds,
        keepFavorites: true,
      )).unwrap();

      expect(outcome.deletedFeedCount, 1);
      expect(outcome.movedFeedCount, 0);
      expect(outcome.keptFavorites, p.favoriteCount, reason: '预览与实际必须一致');
      expect(outcome.deletedArticles, p.otherCount, reason: '预览与实际必须一致');

      expect(await db.select(db.feeds).get(), isEmpty, reason: '分组与订阅都真的删了');
      expect(
        (await db.select(db.groups).get()).single.syncId,
        groupUncategorizedSyncId,
        reason: '只剩保留组',
      );
      final Article kept = (await db.select(db.articles).get()).single;
      expect(kept.favorite, isTrue);
      expect(kept.feedId, isNull);
      expect(kept.feedTitle, '示例源');
    });

    test('保留组不可删除（移动分支的目标不能被删掉）', () async {
      final GroupRecord reserved = (await catalog.listGroups()).unwrap().single;
      final Result<GroupDeletionOutcome> result = await deleteGroup.confirm(
        groupId: reserved.id,
        mode: GroupDeletionMode.moveToUncategorized,
        keepFavorites: true,
      );
      expect(result.isErr, isTrue);
      expect(await db.select(db.groups).get(), hasLength(1));
    });

    test('组内没有订阅：删除组本身成功，文章与订阅不受影响', () async {
      final int groupId = await groupWithFeed('空组');
      await seed('别处的文章');
      // 把订阅移出该分组，制造一个空组。
      await catalog.moveFeedToGroup(feedId: feedId, groupId: null);

      final GroupDeletionOutcome outcome = (await deleteGroup.confirm(
        groupId: groupId,
        mode: GroupDeletionMode.deleteFeeds,
        keepFavorites: true,
      )).unwrap();

      expect(outcome.deletedFeedCount, 0);
      expect(outcome.deletedArticles, 0);
      expect(await db.select(db.feeds).get(), hasLength(1));
      expect(await db.select(db.articles).get(), hasLength(1));
    });
  });
}
