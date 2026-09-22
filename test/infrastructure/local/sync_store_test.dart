// T041：同步状态存储与占位行的真实 SQLite 往返（架构 5.1 的 SyncState、架构 5.2）。
//
// 五组用例，每一组对应一条实现纪律：
//   1) 基线单行、诚实默认（未同步 / 未探测）；
//   2) **确认按修订号上界**（上传期间的新改动必须留下）；
//   3) **墓碑幂等且不自动清除**；
//   4) **占位行不虚构正文**（正文为空、身份依据是 remote）；
//   5) **已有本机行时只应用状态**（正文/标题/身份依据一律不动）。
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';

import 'package:flux/core/core.dart';
import 'package:flux/infrastructure/local/database.dart';
import 'package:flux/infrastructure/local/sync_store.dart';

void main() {
  late AppDatabase db;
  late DriftSyncStore store;

  setUp(() async {
    db = AppDatabase.memory();
    await db.customSelect('SELECT 1').get();
    store = DriftSyncStore(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<int> insertFeed({
    required String syncId,
    required String url,
    String name = '源',
  }) => db
      .into(db.feeds)
      .insert(
        FeedsCompanion.insert(syncId: syncId, normalizedUrl: url, name: name),
      );

  group('同步基线', () {
    test('新库的基线是诚实的默认：无基线、修订 0、能力未探测', () async {
      final SyncBaseline baseline = (await store.readBaseline()).unwrap();
      expect(baseline.baseVersion, isNull);
      expect(baseline.localRevision, 0);
      expect(baseline.lastSyncedAt, isNull);
      expect(baseline.supportsConditionalWrite, isNull);
      expect(baseline.capabilityProbed, isFalse);
    });

    test('推进修订号单调递增，且写回设备名与探测结果', () async {
      expect((await store.bumpRevision()).unwrap(), 1);
      expect((await store.bumpRevision()).unwrap(), 2);
      await store.writeDeviceName('MacBook');
      await store.writeCapability(
        supportsConditionalWrite: true,
        probedAt: DateTime.utc(2026, 9, 22),
      );
      final SyncBaseline baseline = (await store.readBaseline()).unwrap();
      expect(baseline.localRevision, 2);
      expect(baseline.deviceName, 'MacBook');
      expect(baseline.supportsConditionalWrite, isTrue);
      expect(baseline.capabilityProbed, isTrue);
    });
  });

  group('待同步变更与确认（架构 5.2「固定变更集合」「仅确认已包含的修订」）', () {
    test('同实体同字段只有一条待同步行（反复修改不堆积）', () async {
      final int r1 = (await store.bumpRevision()).unwrap();
      await store.recordPendingChanges(<PendingChange>[
        PendingChange(
          entityKind: SyncEntityKind.feed,
          entityKey: 'feed.x',
          fieldName: 'name',
          revision: r1,
          changedAt: DateTime.utc(2026, 9, 22, 1),
        ),
      ]);
      final int r2 = (await store.bumpRevision()).unwrap();
      await store.recordPendingChanges(<PendingChange>[
        PendingChange(
          entityKind: SyncEntityKind.feed,
          entityKey: 'feed.x',
          fieldName: 'name',
          revision: r2,
          changedAt: DateTime.utc(2026, 9, 22, 2),
        ),
      ]);
      final List<PendingChange> pending = (await store.pendingChangesUpTo(99))
          .unwrap();
      expect(pending.length, 1);
      expect(pending.single.revision, r2, reason: '后一次修改覆盖前一次');
    });

    test('**确认只清 ≤ 本次修订**：上传期间产生的新改动仍然待同步', () async {
      final int snapshotRevision = (await store.bumpRevision()).unwrap(); // 1
      await store.recordPendingChanges(<PendingChange>[
        PendingChange(
          entityKind: SyncEntityKind.feed,
          entityKey: 'feed.a',
          fieldName: 'name',
          revision: snapshotRevision,
          changedAt: DateTime.utc(2026, 9, 22),
        ),
      ]);

      // 上传期间用户又改了一处（架构 5.2 要求这条改动必须保留到下一轮）。
      final int laterRevision = (await store.bumpRevision()).unwrap(); // 2
      await store.recordPendingChanges(<PendingChange>[
        PendingChange(
          entityKind: SyncEntityKind.feed,
          entityKey: 'feed.b',
          fieldName: 'favorite',
          revision: laterRevision,
          changedAt: DateTime.utc(2026, 9, 22, 0, 1),
        ),
      ]);

      final int removed = (await store.confirmPendingUpTo(snapshotRevision))
          .unwrap();
      expect(removed, 1, reason: '只确认本次快照包含的那一条');

      final List<PendingChange> remaining = (await store.pendingChangesUpTo(99))
          .unwrap();
      expect(remaining.length, 1);
      expect(remaining.single.entityKey, 'feed.b');
      expect(
        remaining.single.revision,
        greaterThan(snapshotRevision),
        reason: '上传期间的新改动不得被一并清空',
      );
    });

    test('固定变更集合：按快照修订读出的集合不含更晚的改动', () async {
      final int r1 = (await store.bumpRevision()).unwrap();
      await store.recordPendingChanges(<PendingChange>[
        PendingChange(
          entityKind: SyncEntityKind.setting,
          entityKey: 'SET-002',
          fieldName: '',
          revision: r1,
          changedAt: DateTime.utc(2026, 9, 22),
        ),
      ]);
      final int r2 = (await store.bumpRevision()).unwrap();
      await store.recordPendingChanges(<PendingChange>[
        PendingChange(
          entityKind: SyncEntityKind.setting,
          entityKey: 'SET-020',
          fieldName: '',
          revision: r2,
          changedAt: DateTime.utc(2026, 9, 22, 0, 2),
        ),
      ]);

      final List<PendingChange> snapshot = (await store.pendingChangesUpTo(r1))
          .unwrap();
      expect(snapshot.length, 1);
      expect(snapshot.single.entityKey, 'SET-002');
    });

    test('同步成功：清掉已确认的行、推进基线，且修订号不回退', () async {
      final int r1 = (await store.bumpRevision()).unwrap();
      await store.recordPendingChanges(<PendingChange>[
        PendingChange(
          entityKind: SyncEntityKind.setting,
          entityKey: 'x',
          fieldName: '',
          revision: r1,
          changedAt: DateTime.utc(2026, 9, 22),
        ),
      ]);
      final int r2 = (await store.bumpRevision()).unwrap(); // 上传期间的新改动
      await store.recordPendingChanges(<PendingChange>[
        PendingChange(
          entityKind: SyncEntityKind.feed,
          entityKey: 'feed.c',
          fieldName: '',
          revision: r2,
          changedAt: DateTime.utc(2026, 9, 22, 0, 3),
        ),
      ]);

      await store.recordSyncSuccess(
        baseVersion: 'v-sha-1',
        confirmedRevision: r1,
        syncedAt: DateTime.utc(2026, 9, 22, 3),
      );
      final SyncBaseline baseline = (await store.readBaseline()).unwrap();
      expect(baseline.baseVersion, 'v-sha-1');
      expect(baseline.lastSyncedAt, DateTime.utc(2026, 9, 22, 3));
      expect(baseline.localRevision, r2, reason: '修订号不得回退，否则上传期间的新改动会落在已确认区间里');
      final List<PendingChange> remaining = (await store.pendingChangesUpTo(99))
          .unwrap();
      expect(remaining.length, 1);
      expect(remaining.single.entityKey, 'feed.c');
    });
  });

  group('墓碑（架构 5.2「删除使用墓碑，首发不自动清除」）', () {
    test('记录幂等：重复删除不新增行，也不刷新删除时间', () async {
      final DateTime first = DateTime.utc(2026, 9, 22, 1);
      await store.recordTombstone(
        SyncTombstone(
          entityKind: SyncEntityKind.feed,
          entityKey: 'feed.gone',
          deletedAt: first,
          revision: 1,
          displayName: '删掉的源',
        ),
      );
      await store.recordTombstone(
        SyncTombstone(
          entityKind: SyncEntityKind.feed,
          entityKey: 'feed.gone',
          deletedAt: DateTime.utc(2026, 9, 23),
          revision: 5,
          displayName: '删掉的源（第二次）',
        ),
      );
      final List<SyncTombstone> tombstones = (await store.listTombstones())
          .unwrap();
      expect(tombstones.length, 1);
      expect(tombstones.single.deletedAt, first, reason: '「什么时候删的」不随重复操作漂移');
      expect(tombstones.single.displayName, '删掉的源');
    });

    test('墓碑不随同步成功被清除（首发不自动清除）', () async {
      await store.recordTombstone(
        SyncTombstone(
          entityKind: SyncEntityKind.feed,
          entityKey: 'feed.gone',
          deletedAt: DateTime.utc(2026, 9, 22),
          revision: 1,
          displayName: null,
        ),
      );
      await store.recordSyncSuccess(
        baseVersion: 'v1',
        confirmedRevision: 1,
        syncedAt: DateTime.utc(2026, 9, 22, 1),
      );
      expect((await store.listTombstones()).unwrap().length, 1);
    });

    test('按实体查询「是否已删除」，并可按类别过滤', () async {
      await store.recordTombstone(
        SyncTombstone(
          entityKind: SyncEntityKind.feed,
          entityKey: 'feed.gone',
          deletedAt: DateTime.utc(2026, 9, 22),
          revision: 1,
          displayName: null,
        ),
      );
      expect(
        (await store.hasTombstone(
          entityKind: SyncEntityKind.feed,
          entityKey: 'feed.gone',
        )).unwrap(),
        isTrue,
      );
      expect(
        (await store.hasTombstone(
          entityKind: SyncEntityKind.feed,
          entityKey: 'feed.alive',
        )).unwrap(),
        isFalse,
      );
      expect(
        (await store.hasTombstone(
          entityKind: SyncEntityKind.group,
          entityKey: 'feed.gone',
        )).unwrap(),
        isFalse,
        reason: '实体类别参与判定（同名不同类别互不影响）',
      );
      expect(
        (await store.listTombstones(entityKind: SyncEntityKind.feed))
            .unwrap()
            .length,
        1,
      );
      expect(
        (await store.listTombstones(entityKind: SyncEntityKind.group)).unwrap(),
        isEmpty,
      );
    });
  });

  group('别名（架构 5.2「对齐后保存别名」）', () {
    test('保存与读取；重复保存被忽略', () async {
      final int feedId = await insertFeed(
        syncId: 'feed.local',
        url: 'https://alias.example.com/feed.xml',
      );
      await store.saveFeedAlias(syncId: 'feed.remote', localFeedId: feedId);
      await store.saveFeedAlias(syncId: 'feed.remote', localFeedId: feedId);
      final List<SyncFeedAlias> aliases = (await store.loadFeedAliases())
          .unwrap();
      expect(aliases.length, 1);
      expect(aliases.single.syncId, 'feed.remote');
      expect(aliases.single.localFeedId, feedId);
    });
  });

  group('远端状态到达：占位行（架构 5.2「不把不存在的文章虚构成全文」）', () {
    test('本机没有该文章 → 建占位行：状态落库、正文为空、依据是 remote', () async {
      final int feedId = await insertFeed(
        syncId: 'feed.p',
        url: 'https://p.example.com/feed.xml',
      );
      final RemoteStateOutcome outcome = (await store.applyRemoteArticleState(
        const RemoteArticleState(
          feedSyncId: 'feed.p',
          remoteKey: 'remote-key-1',
          readingState: ReadingState.later,
          favorite: true,
          revision: 3,
          title: '远端读过的一篇',
        ),
      )).unwrap();

      expect(outcome.createdPlaceholder, isTrue);
      expect(outcome.identityBasis, IdentityBasis.remote);

      final Article row = (await db.select(db.articles).get()).single;
      expect(row.id, outcome.localArticleId);
      expect(row.feedId, feedId);
      expect(row.title, '远端读过的一篇');
      expect(row.readingState, ReadingState.later);
      expect(row.favorite, isTrue);
      expect(row.identityBasis, IdentityBasis.remote);
      expect(row.body, isNull, reason: '**不虚构全文**：远端首发不同步正文，占位行的正文必须为空');
      expect(row.bodyHash, isNull);
      expect(row.summary, isNull);
      expect(row.guid, isNull);
      expect(row.syncKey, isNotNull, reason: '占位行必须能被后续抓取匹配上');
    });

    test('再同步一次同一状态：不重复建行（占位键稳定）', () async {
      await insertFeed(syncId: 'feed.p', url: 'https://p.example.com/feed.xml');
      const RemoteArticleState state = RemoteArticleState(
        feedSyncId: 'feed.p',
        remoteKey: 'remote-key-1',
        readingState: ReadingState.later,
        favorite: false,
      );
      await store.applyRemoteArticleState(state);
      final RemoteStateOutcome second = (await store.applyRemoteArticleState(
        state,
      )).unwrap();
      expect(second.createdPlaceholder, isFalse);
      expect((await db.select(db.articles).get()).length, 1);
    });

    test('本机已有正文（同源同 GUID）→ 只应用状态，正文与身份依据一律不动', () async {
      final int feedId = await insertFeed(
        syncId: 'feed.p',
        url: 'https://p.example.com/feed.xml',
      );
      final int articleId = await db
          .into(db.articles)
          .insert(
            ArticlesCompanion.insert(
              feedId: Value<int?>(feedId),
              title: '本机抓到的标题',
              identityBasis: IdentityBasis.guid,
              guid: const Value<String?>('g-1'),
              guidPresent: const Value<bool>(true),
              body: const Value<String?>('本机已抓到的全文'),
              bodyHash: const Value<String?>('hash-1'),
              summary: const Value<String?>('本机摘要'),
              readingState: const Value<ReadingState>(ReadingState.unread),
            ),
          );

      final RemoteStateOutcome outcome = (await store.applyRemoteArticleState(
        const RemoteArticleState(
          feedSyncId: 'feed.p',
          remoteKey: 'remote-key-2',
          readingState: ReadingState.read,
          favorite: true,
          guid: 'g-1',
          title: '远端看到的标题',
        ),
      )).unwrap();

      expect(outcome.action, SyncRemoteStateAction.applyStateOnly);
      expect(outcome.localArticleId, articleId);
      expect(outcome.identityBasis, IdentityBasis.guid);

      final Article row = (await db.select(db.articles).get()).single;
      expect(row.readingState, ReadingState.read, reason: '状态被应用');
      expect(row.favorite, isTrue);
      expect(row.body, '本机已抓到的全文', reason: '远端的空正文不得覆盖本机已抓取的全文');
      expect(row.bodyHash, 'hash-1');
      expect(row.summary, '本机摘要');
      expect(row.title, '本机抓到的标题', reason: '标题不被远端的另一份覆盖');
      expect(row.identityBasis, IdentityBasis.guid, reason: '身份依据不退回 remote');
    });

    test('本机已有占位行（此前同步过、抓取还没补上）→ 只更新状态', () async {
      await insertFeed(syncId: 'feed.p', url: 'https://p.example.com/feed.xml');
      await store.applyRemoteArticleState(
        const RemoteArticleState(
          feedSyncId: 'feed.p',
          remoteKey: 'remote-key-3',
          readingState: ReadingState.later,
          favorite: false,
          title: '占位标题',
        ),
      );
      final RemoteStateOutcome outcome = (await store.applyRemoteArticleState(
        const RemoteArticleState(
          feedSyncId: 'feed.p',
          remoteKey: 'remote-key-3',
          readingState: ReadingState.read,
          favorite: true,
          title: '占位标题',
        ),
      )).unwrap();
      expect(outcome.createdPlaceholder, isFalse);
      final Article row = (await db.select(db.articles).get()).single;
      expect(row.readingState, ReadingState.read);
      expect(row.favorite, isTrue);
      expect(row.body, isNull, reason: '仍是占位：正文没有凭空出现');
      expect(row.identityBasis, IdentityBasis.remote);
    });

    test('远端带来本机已算过的同步键 → 认成同一篇，不建第二行', () async {
      final int feedId = await insertFeed(
        syncId: 'feed.p',
        url: 'https://p.example.com/feed.xml',
      );
      final String key = syncArticleKey(feedSyncId: 'feed.p', guid: 'g-same')!;
      await db
          .into(db.articles)
          .insert(
            ArticlesCompanion.insert(
              feedId: Value<int?>(feedId),
              title: '同键文章',
              identityBasis: IdentityBasis.guid,
              guid: const Value<String?>('g-same'),
              guidPresent: const Value<bool>(true),
              syncKey: Value<String?>(key),
            ),
          );
      final RemoteStateOutcome outcome = (await store.applyRemoteArticleState(
        RemoteArticleState(
          feedSyncId: 'feed.p',
          remoteKey: key,
          readingState: ReadingState.read,
          favorite: false,
          guid: 'g-same',
        ),
      )).unwrap();
      expect(outcome.createdPlaceholder, isFalse);
      expect((await db.select(db.articles).get()).length, 1);
    });

    test('本机还没有对齐这条订阅 → 落无归属占位行（而不是整批失败）', () async {
      final RemoteStateOutcome outcome = (await store.applyRemoteArticleState(
        const RemoteArticleState(
          feedSyncId: 'feed.unknown',
          remoteKey: 'rk-1',
          readingState: ReadingState.later,
          favorite: false,
        ),
      )).unwrap();
      expect(outcome.createdPlaceholder, isTrue);
      final Article row = (await db.select(db.articles).get()).single;
      expect(row.feedId, isNull, reason: '没有归属源：状态仍然保留，等待对齐');
      expect(row.readingState, ReadingState.later);
    });

    test('对齐后（写了别名）占位行挂在正确的本机订阅上', () async {
      final int feedId = await insertFeed(
        syncId: 'feed.local',
        url: 'https://alias2.example.com/feed.xml',
      );
      await store.saveFeedAlias(syncId: 'feed.remote', localFeedId: feedId);
      await store.applyRemoteArticleState(
        const RemoteArticleState(
          feedSyncId: 'feed.remote',
          remoteKey: 'rk-2',
          readingState: ReadingState.read,
          favorite: false,
        ),
      );
      final Article row = (await db.select(db.articles).get()).single;
      expect(row.feedId, feedId);
    });
  });

  group('同步表不含凭据（架构 5.1、第 8 节）', () {
    test('同步四表没有任何凭据列（WebDAV 密码只住 Keychain）', () async {
      final List<QueryRow> rows = await db
          .customSelect(
            "SELECT name FROM pragma_table_info('sync_state_records') "
            "UNION ALL SELECT name FROM pragma_table_info('sync_pending_changes') "
            "UNION ALL SELECT name FROM pragma_table_info('sync_tombstones') "
            "UNION ALL SELECT name FROM pragma_table_info('sync_feed_alias_records')",
          )
          .get();
      final List<String> columns = rows
          .map((QueryRow r) => r.read<String>('name').toLowerCase())
          .toList();
      expect(columns, isNotEmpty);
      for (final String column in columns) {
        expect(column, isNot(contains('password')));
        expect(column, isNot(contains('secret')));
        expect(column, isNot(contains('api_key')));
        expect(column, isNot(contains('token')));
      }
    });
  });
}
