// T045：删除与收藏保留的跨设备集成（架构 5.2「未批准不自动清除本地内容」、
// 4.1「删除订阅」段、手册 6.3「删除」与「同步」两节）。
//
// 六组用例，逐条对应 T045 的验收点：
//   1) **远端删除确认流程**：预览（订阅名/文章数/收藏数/later 数）→ 确认 → 按 T018 规则执行；
//   2) **未确认不动数据**：预览是只读的，确认前一行都不许变（架构 5.2 的硬要求）；
//   3) **墓碑跳过刷新**：已删除的源不复活——刷新不经过合并，必须按墓碑在派发前拦下；
//   4) **占位升级保状态**：抓取拿到证据时把占位行升成正常行，阅读状态与收藏必须留下；
//   5) **删除操作元数据同步**：保留收藏的选择随快照离机，别的设备据此展示影响范围。
//
// 用真实内存库断言**数据**（哪一行真的没了、状态有没有保住），不用替身断言「调用了某个方法」。
library;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';

import 'package:flux/core/core.dart';
import 'package:flux/features/feeds/application/refresh_feed.dart';
import 'package:flux/features/feeds/application/refresh_scheduler.dart';
import 'package:flux/features/sync/application/remote_deletion_use_case.dart';
import 'package:flux/infrastructure/local/article_store.dart';
import 'package:flux/infrastructure/local/database.dart';
import 'package:flux/infrastructure/local/deletion_sync_recorder.dart';
import 'package:flux/infrastructure/local/feed_catalog_store.dart';
import 'package:flux/infrastructure/local/feed_tombstone_reader.dart';
import 'package:flux/infrastructure/local/sync_local_store.dart';
import 'package:flux/infrastructure/local/sync_store.dart';
import 'package:flux/infrastructure/local/tables/article_tables.dart';
import 'package:flux/infrastructure/local/tables/feed_tables.dart';

/// 记录诊断消息的 sink。
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

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late DriftFeedCatalogStore catalog;
  late RemoteDeletionUseCase useCase;
  late DriftSyncStore syncStore;
  late DriftSyncLocalStore localStore;
  late _RecordingSink diagnostics;

  setUp(() async {
    db = AppDatabase.memory();
    await db.customSelect('SELECT 1').get();
    catalog = DriftFeedCatalogStore(db);
    diagnostics = _RecordingSink();
    useCase = RemoteDeletionUseCase(catalog: catalog, diagnostics: diagnostics);
    syncStore = DriftSyncStore(db);
    localStore = DriftSyncLocalStore(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<int> seedFeed({String syncId = 'feed.a', String name = '示例源'}) async =>
      (await catalog.createFeed(
        FeedInsert(
          syncId: syncId,
          normalizedUrl: 'https://a.example.com/$syncId.xml',
          name: name,
        ),
      )).unwrap().id;

  /// 造一篇文章。
  Future<int> seedArticle(
    int feedId, {
    ReadingState state = ReadingState.unread,
    bool favorite = false,
    String title = '文章',
    IdentityBasis basis = IdentityBasis.guid,
    String? syncKey,
    String? guid,
  }) => db
      .into(db.articles)
      .insert(
        ArticlesCompanion.insert(
          feedId: Value<int?>(feedId),
          title: title,
          identityBasis: basis,
          readingState: Value<ReadingState>(state),
          favorite: Value<bool>(favorite),
          syncKey: Value<String?>(syncKey),
          guid: Value<String?>(guid),
          guidPresent: Value<bool>(guid != null),
        ),
      );

  Future<List<Article>> articles() async =>
      (db.select(db.articles)..orderBy(<OrderClauseGenerator<$ArticlesTable>>[
            (Articles t) => OrderingTerm(expression: t.id),
          ]))
          .get();

  group('远端删除的确认流程（订阅）', () {
    test('预览给出订阅名/文章数/收藏数/later 数，且**不改任何数据**', () async {
      final int feedId = await seedFeed(name: '被远端删掉的源');
      await seedArticle(feedId, title: '收藏', favorite: true);
      await seedArticle(feedId, title: '稍后再读', state: ReadingState.later);
      await seedArticle(feedId, title: '已读', state: ReadingState.read);
      final int before = (await articles()).length;

      const SyncDeletion deletion = SyncDeletion(
        kind: SyncEntityKind.feed,
        key: 'feed.a',
        displayName: '被远端删掉的源',
        keepFavorites: true,
      );
      final RemoteDeletionImpact impact = (await useCase.preview(deletion))
          .unwrap();

      expect(impact.applicable, isTrue);
      expect(impact.displayName, '被远端删掉的源');
      expect(impact.totalCount, 3);
      expect(impact.favoriteCount, 1);
      expect(impact.otherCount, 2, reason: '其余含 later');
      expect(impact.laterCount, 1);
      expect(
        (await articles()).length,
        before,
        reason: '预览是只读的：一行都不许变（未确认不清数据）',
      );
      expect(
        (await catalog.listFeeds()).unwrap().length,
        1,
        reason: '确认前订阅也还在',
      );
    });

    test('确认后按 T018 规则执行：非收藏（含 later）清理、收藏脱离源并冻结来源快照', () async {
      final int feedId = await seedFeed(name: '远端源');
      final int favoriteId = await seedArticle(feedId, favorite: true);
      await seedArticle(feedId, state: ReadingState.later);
      await seedArticle(feedId, state: ReadingState.read);

      final RemoteDeletionImpact impact = (await useCase.preview(
        const SyncDeletion(
          kind: SyncEntityKind.feed,
          key: 'feed.a',
          displayName: '远端源',
        ),
      )).unwrap();
      final RemoteDeletionApplication applied = (await useCase.applyConfirmed(
        impact: impact,
        keepFavorites: true,
      )).unwrap();

      expect(applied.deletedArticles, 2, reason: '非收藏含 later 全清理');
      expect(applied.keptFavorites, 1);
      final List<Article> remaining = await articles();
      expect(remaining.length, 1);
      expect(remaining.single.id, favoriteId);
      expect(remaining.single.feedId, isNull, reason: '收藏脱离源');
      expect(remaining.single.feedTitle, '远端源', reason: '冻结来源快照');
      expect((await catalog.listFeeds()).unwrap(), isEmpty);
      // 应用动作必须留痕（诊断 tag 与数据删除可对照），且日志只记数量不记正文。
      expect(
        diagnostics.messages.any(
          (String m) =>
              m.contains('sync.remoteDeletion') && m.contains('保留收藏 1 篇'),
        ),
        isTrue,
      );
    });

    test('不保留分支：全部清理（收藏也删）', () async {
      final int feedId = await seedFeed();
      await seedArticle(feedId, favorite: true);
      await seedArticle(feedId, state: ReadingState.later);

      final RemoteDeletionImpact impact = (await useCase.preview(
        const SyncDeletion(
          kind: SyncEntityKind.feed,
          key: 'feed.a',
          displayName: '示例源',
        ),
      )).unwrap();
      final RemoteDeletionApplication applied = (await useCase.applyConfirmed(
        impact: impact,
        keepFavorites: false,
      )).unwrap();

      expect(applied.deletedArticles, 2);
      expect(applied.keptFavorites, 0);
      expect(await articles(), isEmpty);
    });

    test('本机没对齐到这条删除 → 不可应用，且拒绝执行（不猜目标去删）', () async {
      final int localFeedId = await seedFeed(
        syncId: 'feed.local',
        name: '本机的源',
      );
      await seedArticle(localFeedId);

      final RemoteDeletionImpact impact = (await useCase.preview(
        const SyncDeletion(
          kind: SyncEntityKind.feed,
          key: 'feed.remote-only',
          displayName: '远端才有的源',
        ),
      )).unwrap();

      expect(impact.applicable, isFalse);
      expect(impact.blockedReason, 'feedNotAligned');
      final Result<RemoteDeletionApplication> applied = await useCase
          .applyConfirmed(impact: impact, keepFavorites: true);
      expect(applied.isErr, isTrue, reason: '假成功会让界面把这条划掉而数据其实没动');
      expect((await articles()).length, 1, reason: '拒绝执行：本机数据一行都没动');
      expect((await catalog.listFeeds()).unwrap().length, 1);
    });

    test('未知类别（未来实体）不猜着删', () async {
      final RemoteDeletionImpact impact = (await useCase.preview(
        const SyncDeletion(kind: 'unknownKind', key: 'x-1', displayName: '未知'),
      )).unwrap();
      expect(impact.applicable, isFalse);
      expect(impact.blockedReason, 'unsupportedEntityKind');
    });

    test('默认勾选状态沿用远端那次的选择（远端说保留就默认保留）', () async {
      final int feedId = await seedFeed();
      await seedArticle(feedId, favorite: true);

      final RemoteDeletionImpact keep = (await useCase.preview(
        const SyncDeletion(
          kind: SyncEntityKind.feed,
          key: 'feed.a',
          displayName: '示例源',
          keepFavorites: true,
        ),
      )).unwrap();
      final RemoteDeletionImpact drop = (await useCase.preview(
        const SyncDeletion(
          kind: SyncEntityKind.feed,
          key: 'feed.a',
          displayName: '示例源',
          keepFavorites: false,
        ),
      )).unwrap();

      expect(keep.defaultKeepFavorites, isTrue);
      expect(drop.defaultKeepFavorites, isFalse);
      expect(keep.remoteKeepFavorites, isTrue);
      expect(keep.keepFavoritesIsMeaningful, isTrue);
    });
  });

  group('远端删除的确认流程（分组）', () {
    test('分组删除的影响范围逐条累加组内订阅，确认后按所选分支执行', () async {
      final int groupId = (await catalog.createGroup(
        syncId: 'group.remote',
        name: '远端删掉的分组',
      )).unwrap().id;
      final int feedA = await seedFeed(syncId: 'feed.g1', name: '组内 A');
      final int feedB = await seedFeed(syncId: 'feed.g2', name: '组内 B');
      for (final int id in <int>[feedA, feedB]) {
        await (db.update(db.feeds)..where((Feeds t) => t.id.equals(id))).write(
          FeedsCompanion(groupId: Value<int?>(groupId)),
        );
      }
      await seedArticle(feedA, favorite: true);
      await seedArticle(feedA, state: ReadingState.later);
      await seedArticle(feedB, state: ReadingState.read);

      final RemoteDeletionImpact impact = (await useCase.preview(
        const SyncDeletion(
          kind: SyncEntityKind.group,
          key: 'group.remote',
          displayName: '远端删掉的分组',
          // 远端那次是「删除其中订阅」分支（不是移动到未分类）。
          keepFavorites: true,
        ),
      )).unwrap();

      expect(impact.applicable, isTrue);
      expect(impact.totalCount, 3);
      expect(impact.favoriteCount, 1);
      expect(impact.otherCount, 2);
      expect(impact.laterCount, 1);

      final RemoteDeletionApplication applied = (await useCase.applyConfirmed(
        impact: impact,
        keepFavorites: true,
      )).unwrap();
      expect(applied.deletedArticles, 2);
      expect(applied.keptFavorites, 1);
      // 删掉的是这个分组；保留组「未分类」仍应在（它不是被删掉的那一个）。
      expect(
        (await catalog.listGroups()).unwrap().where(
          (GroupRecord g) => g.syncId == 'group.remote',
        ),
        isEmpty,
      );
      expect((await catalog.listFeeds()).unwrap(), isEmpty);
    });

    test('分组只是被移动（操作元数据无 keepFavorites）→ 本机按移动分支处理', () async {
      final int groupId = (await catalog.createGroup(
        syncId: 'group.moved',
        name: '被移动的分组',
      )).unwrap().id;
      final int feedId = await seedFeed(syncId: 'feed.m1', name: '组内源');
      await (db.update(db.feeds)..where((Feeds t) => t.id.equals(feedId)))
          .write(FeedsCompanion(groupId: Value<int?>(groupId)));
      await seedArticle(feedId);

      final RemoteDeletionImpact impact = (await useCase.preview(
        const SyncDeletion(
          kind: SyncEntityKind.group,
          key: 'group.moved',
          displayName: '被移动的分组',
        ),
      )).unwrap();
      final RemoteDeletionApplication applied = (await useCase.applyConfirmed(
        impact: impact,
        keepFavorites: true,
      )).unwrap();

      expect(applied.deletedArticles, 0, reason: '移动分支不删文章');
      expect(
        (await catalog.listFeeds()).unwrap().length,
        1,
        reason: '订阅被移动到未分类',
      );
      expect((await articles()).length, 1);
    });
  });

  group('删除操作元数据进入同步（架构 5.2）', () {
    test('本机删除订阅 → 墓碑 + 待同步标记 + 修订号推进，且快照带 keepFavorites', () async {
      final int feedId = await seedFeed(syncId: 'feed.meta', name: '要删的源');
      await seedArticle(feedId, favorite: true);
      await seedArticle(feedId);

      final int revisionBefore = (await syncStore.readBaseline())
          .unwrap()
          .localRevision;
      await catalog.deleteFeed(feedId: feedId, keepFavorites: true);

      expect(
        (await syncStore.hasTombstone(
          entityKind: SyncEntityKind.feed,
          entityKey: 'feed.meta',
        )).unwrap(),
        isTrue,
        reason: '删除必须留下墓碑',
      );

      final SyncBaseline after = (await syncStore.readBaseline()).unwrap();
      expect(after.localRevision, greaterThan(revisionBefore));
      final List<PendingChange> pending = (await syncStore.pendingChangesUpTo(
        after.localRevision,
      )).unwrap();
      expect(
        pending.any(
          (PendingChange c) =>
              c.entityKind == SyncEntityKind.feed && c.entityKey == 'feed.meta',
        ),
        isTrue,
        reason: '删除要进待同步集合，否则别的设备永远不知道',
      );

      // 快照里的删除事实带上「保留收藏」：别的设备据此展示影响范围。
      final SyncSnapshot snapshot = (await localStore.readLocalSnapshot())
          .unwrap();
      final SyncDeletion? deletion = snapshot.deletion(
        SyncEntityKind.feed,
        'feed.meta',
      );
      expect(deletion, isNotNull);
      expect(deletion!.keepFavorites, isTrue);
      expect(deletion.displayName, '要删的源');
    });

    test('删除分组（两种分支）都留下墓碑', () async {
      for (final GroupDeletionMode mode in GroupDeletionMode.values) {
        final int groupId = (await catalog.createGroup(
          syncId: 'group.del.${mode.name}',
          name: '分组 ${mode.name}',
        )).unwrap().id;
        await catalog.deleteGroupWithFeeds(
          groupId: groupId,
          mode: mode,
          keepFavorites: true,
        );
        expect(
          (await syncStore.hasTombstone(
            entityKind: SyncEntityKind.group,
            entityKey: 'group.del.${mode.name}',
          )).unwrap(),
          isTrue,
          reason: '分支 ${mode.name}',
        );
      }
    });

    test('已确认应用远端删除之后，本机也产生一条墓碑（这次选择会传播出去）', () async {
      final int feedId = await seedFeed(syncId: 'feed.applied', name: '远端删的源');
      await seedArticle(feedId, favorite: true);

      final RemoteDeletionImpact impact = (await useCase.preview(
        const SyncDeletion(
          kind: SyncEntityKind.feed,
          key: 'feed.applied',
          displayName: '远端删的源',
        ),
      )).unwrap();
      await useCase.applyConfirmed(impact: impact, keepFavorites: false);

      expect(
        (await syncStore.hasTombstone(
          entityKind: SyncEntityKind.feed,
          entityKey: 'feed.applied',
        )).unwrap(),
        isTrue,
      );
      final SyncSnapshot snapshot = (await localStore.readLocalSnapshot())
          .unwrap();
      expect(
        snapshot.deletion(SyncEntityKind.feed, 'feed.applied')!.keepFavorites,
        isFalse,
        reason: '本机这次的选择（不保留）要写给其他设备',
      );
    });

    test('在本机重新添加同一个源 → 忘掉旧墓碑（新的决定，不是复活）', () async {
      final int feedId = await seedFeed(syncId: 'feed.re', name: '重新添加的源');
      await catalog.deleteFeed(feedId: feedId, keepFavorites: false);
      expect(
        (await syncStore.hasTombstone(
          entityKind: SyncEntityKind.feed,
          entityKey: 'feed.re',
        )).unwrap(),
        isTrue,
      );

      // 同一个规范化地址 → 同一个 syncId（T014）。
      await catalog.createFeed(
        const FeedInsert(
          syncId: 'feed.re',
          normalizedUrl: 'https://a.example.com/feed.re.xml',
          name: '重新添加的源',
        ),
      );
      expect(
        (await syncStore.hasTombstone(
          entityKind: SyncEntityKind.feed,
          entityKey: 'feed.re',
        )).unwrap(),
        isFalse,
        reason: '不忘记墓碑会让这个源永远跳过刷新，且没有任何线索',
      );
    });
  });

  group('已删除条目不复活：刷新按墓碑跳过（T045）', () {
    test('墓碑源在派发前被拦下：不发请求，且如实记进 skipped', () async {
      final int tombstonedFeedId = await seedFeed(
        syncId: 'feed.doomed',
        name: '已删除的源',
      );
      final int aliveFeedId = await seedFeed(
        syncId: 'feed.alive',
        name: '正常的源',
      );
      await db
          .into(db.syncTombstones)
          .insert(
            SyncTombstonesCompanion.insert(
              entityKind: SyncEntityKind.feed,
              entityKey: 'feed.doomed',
              deletedAt: DateTime.utc(2026, 9, 22),
              revision: 1,
              displayName: const Value<String?>('已删除的源'),
            ),
          );

      final List<int> requested = <int>[];
      final RefreshScheduler scheduler = RefreshScheduler(
        listFeeds: () => catalog.listFeeds(),
        refreshFeed: _RecordingRefreshFeed(onCall: requested.add),
        recordDeferral: ({
          required int feedId,
          required FeedRefreshOutcome outcome,
          String? errorKind,
        }) async => okUnit(),
        listFeedTombstoneSyncIds: () =>
            DriftFeedTombstoneReader(db).readFeedTombstoneSyncIds(),
      );

      final RefreshRunReport report = await scheduler.refreshAll();
      expect(requested, <int>[aliveFeedId], reason: '墓碑源一个请求都不发（否则它会被整条拉回来）');
      expect(
        report.skipped.any(
          (FeedRefreshSkip s) =>
              s.feedId == tombstonedFeedId && s.reason == 'tombstoned',
        ),
        isTrue,
        reason: '跳过必须可见，否则用户以为刷新坏了',
      );
    });

    test('墓碑读取失败时按「没有墓碑」放行（不让刷新静默停摆）', () async {
      final int feedId = await seedFeed(syncId: 'feed.x', name: '源');
      final List<int> requested = <int>[];
      final RefreshScheduler scheduler = RefreshScheduler(
        listFeeds: () => catalog.listFeeds(),
        refreshFeed: _RecordingRefreshFeed(onCall: requested.add),
        recordDeferral: ({
          required int feedId,
          required FeedRefreshOutcome outcome,
          String? errorKind,
        }) async => okUnit(),
        listFeedTombstoneSyncIds: () async =>
            Err<Set<String>>(StorageError(operation: 'test', detail: '读取失败')),
      );
      await scheduler.refreshAll();
      expect(requested, <int>[feedId]);
    });

    test('未接线（null）时不做墓碑过滤：照常刷新', () async {
      final int feedId = await seedFeed(syncId: 'feed.y', name: '源');
      final List<int> requested = <int>[];
      final RefreshScheduler scheduler = RefreshScheduler(
        listFeeds: () => catalog.listFeeds(),
        refreshFeed: _RecordingRefreshFeed(onCall: requested.add),
        recordDeferral: ({
          required int feedId,
          required FeedRefreshOutcome outcome,
          String? errorKind,
        }) async => okUnit(),
      );
      await scheduler.refreshAll();
      expect(requested, <int>[feedId]);
    });
  });

  group('占位行升级（T045：抓取补上身份与正文，状态必须保留）', () {
    test('抓取匹配占位行（按同步键）→ 补正文与身份，readingState/favorite 不动', () async {
      final int feedId = await seedFeed(syncId: 'feed.p', name: '源');

      // 抓取抓到同一篇：带 GUID 与正文。
      const String guid = 'post-1';
      final String ownKey = syncArticleKey(feedSyncId: 'feed.p', guid: guid)!;

      // 占位行：远端状态到达时落下（T041 的形态：有同步键、无身份证据、正文为空）。
      // 远端键 = 它按同一份证据算出的键，因此与本机这次算出的 ownKey **相等**（键函数是
      // 确定性纯函数）；占位键则由它派生。
      final String placeholderKey = syncPlaceholderKey(
        feedSyncId: 'feed.p',
        remoteKey: ownKey,
      );
      final int articleId = await seedArticle(
        feedId,
        title: '远端读过的',
        state: ReadingState.later,
        favorite: true,
        basis: IdentityBasis.remote,
        syncKey: placeholderKey,
      );

      expect(ownKey, isNot(placeholderKey), reason: '两类键空间不同');

      final Result<ArticleImportOutcome> stored = await db.upsertArticles(
        <ArticleImport>[
          ArticleImport(
            feedId: feedId,
            title: '抓到的标题',
            identityBasis: IdentityBasis.guid,
            guid: guid,
            guidPresent: true,
            body: '本机抓到的全文',
            bodyHash: 'hash-1',
          ),
        ],
      );

      expect(stored.isOk, isTrue);
      final List<Article> rows = await articles();
      expect(rows.length, 1, reason: '按同步键匹配上占位行：不得为同一篇文章再插一行');
      final Article row = rows.single;
      expect(row.id, articleId);
      expect(row.title, '抓到的标题', reason: '标题被这次抓取补上');
      expect(row.body, '本机抓到的全文', reason: '正文补上');
      expect(row.bodyHash, 'hash-1');
      expect(row.identityBasis, IdentityBasis.guid, reason: '身份依据从 remote 升级');
      expect(row.syncKey, ownKey, reason: '同步身份跟着升到本机算出的键');
      expect(row.readingState, ReadingState.later, reason: '**阅读状态必须保留**');
      expect(row.favorite, isTrue, reason: '**收藏必须保留**');
    });

    test('本次抓取没有证据 → 不算升级，占位行保持原样', () async {
      final int feedId = await seedFeed(syncId: 'feed.q', name: '源');
      final String placeholderKey = syncPlaceholderKey(
        feedSyncId: 'feed.q',
        remoteKey: 'r-1',
      );
      await seedArticle(
        feedId,
        title: '',
        state: ReadingState.read,
        basis: IdentityBasis.remote,
        syncKey: placeholderKey,
      );

      // 无 GUID、无链接、无指纹的导入项：本机算不出键，因此匹配不到（保持原样）。
      await db.upsertArticles(<ArticleImport>[
        ArticleImport(
          feedId: feedId,
          title: '仍无证据',
          identityBasis: IdentityBasis.fingerprint,
        ),
      ]);

      final List<Article> rows = await articles();
      expect(rows.length, 2, reason: '没有证据时不能把两行并成一行（那会把不同文章合成一篇）');
      final Article placeholder = rows.firstWhere(
        (Article a) => a.identityBasis == IdentityBasis.remote,
      );
      expect(placeholder.readingState, ReadingState.read);
      expect(placeholder.title, '', reason: '占位行不被无证据的导入改写');
    });

    test('真实身份的行不会被同步键路径改写（只有 remote → 真实）', () async {
      final int feedId = await seedFeed(syncId: 'feed.r', name: '源');
      const String guid = 'g-9';
      final String key = syncArticleKey(feedSyncId: 'feed.r', guid: guid)!;
      final int articleId = await seedArticle(
        feedId,
        title: '本机原有标题',
        basis: IdentityBasis.guid,
        guid: guid,
        syncKey: key,
      );

      // 同一个 GUID 再导入一次：必须按身份匹配到同一行，且身份依据不退回 remote。
      await db.upsertArticles(<ArticleImport>[
        ArticleImport(
          feedId: feedId,
          title: '抓到的新标题',
          identityBasis: IdentityBasis.guid,
          guid: guid,
          guidPresent: true,
        ),
      ]);

      final List<Article> rows = await articles();
      expect(rows.length, 1);
      expect(rows.single.id, articleId);
      expect(rows.single.identityBasis, IdentityBasis.guid);
      expect(rows.single.syncKey, key, reason: '真实键不被占位升级路径改写');
    });
  });

  group('记录删除事实的守卫', () {
    test('缺单行同步状态时抛错（由事务回滚，不编一个修订号）', () async {
      await db.customStatement('DELETE FROM sync_state_records');
      await expectLater(
        recordLocalDeletionFact(
          db,
          entityKind: SyncEntityKind.feed,
          entityKey: 'feed.x',
          displayName: 'x',
          deletedAt: DateTime.utc(2026, 9, 22),
        ),
        throwsA(isA<StorageError>()),
      );
    });

    test('forgetLocalDeletionTombstone 同时清掉待同步标记', () async {
      final int feedId = await seedFeed(syncId: 'feed.f', name: '源');
      await catalog.deleteFeed(feedId: feedId, keepFavorites: false);
      final SyncBaseline before = (await syncStore.readBaseline()).unwrap();
      expect(
        (await syncStore.pendingChangesUpTo(before.localRevision))
            .unwrap()
            .where((PendingChange c) => c.entityKey == 'feed.f'),
        isNotEmpty,
      );

      await forgetLocalDeletionTombstone(
        db,
        entityKind: SyncEntityKind.feed,
        entityKey: 'feed.f',
      );
      expect(
        (await syncStore.pendingChangesUpTo(before.localRevision))
            .unwrap()
            .where((PendingChange c) => c.entityKey == 'feed.f'),
        isEmpty,
        reason: '重新添加之后不该还留着一条「这个源被删了」的待上传改动',
      );
    });
  });
}

/// 记录被调用源 id 的刷新用例替身（只关心「有没有派发」，不真的联网）。
final class _RecordingRefreshFeed implements RefreshFeedUseCase {
  _RecordingRefreshFeed({required this.onCall});

  final void Function(int feedId) onCall;

  @override
  Future<FeedRefreshResult> call(FeedRefreshRequest request) async {
    onCall(request.feedId);
    return const FeedRefreshResult(outcome: FeedRefreshOutcome.unchanged);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName} 未在替身里实现');
}
