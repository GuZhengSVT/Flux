// T043：同步引擎的编排（架构 5.2 的条件发布协议、手册 6.3「同步」节的验收核心）。
//
// 全部用**内存 WebDAV 服务器**（T042 的状态化替身）+ 真实 drift 内存库：没有网络、
// 没有凭据、没有两台真实设备。测试证明的是协议规则与引擎行为，**不是**服务器兼容性
// （真实服务器验证属 T044 的 NOT_RUN 项）。
//
// 本文件把手册 6.3 点名的同步条目逐条落成用例：
//   并发 412（两轮收敛 / 三轮用尽）· 读状态反转不出 OR · 取消收藏不复活 ·
//   墓碑防复活 · 上传期间的新修改保留 · 远端发布成功后本机中断可幂等恢复 ·
//   降级服务器只读不清数据 · 设备时钟偏移无影响。
import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:flux/core/core.dart';
import 'package:flux/features/sync/application/sync_engine.dart';
import 'package:flux/infrastructure/local/database.dart';
import 'package:flux/infrastructure/local/sync_local_store.dart';
import 'package:flux/infrastructure/local/sync_store.dart';
import 'package:flux/infrastructure/network/webdav_client.dart';
import 'package:flux/infrastructure/network/webdav_transport.dart';
import 'package:flux/infrastructure/local/tables/feed_tables.dart';

import '../../infrastructure/network/fake_webdav_server.dart';

/// 一个**总是**返回 412 的服务器（manifest 写入永远冲突）。
///
/// 它模拟的是「另一台设备在每一次尝试之间都恰好又发布了一版」这种最坏情形，
/// 用来断言三轮上限确实生效、且用尽之后远端 manifest 从未被本机改写。
class _AlwaysConflictingServer extends FakeWebDavServer {
  /// 已拒绝的 manifest 写入次数。
  int rejectedManifestWrites = 0;

  @override
  Future<http.StreamedResponse> handle(http.BaseRequest request) async {
    if (request.method == 'PUT' && request.url.path.endsWith('manifest.json')) {
      rejectedManifestWrites++;
      return http.StreamedResponse(
        const Stream<List<int>>.empty(),
        412,
        headers: <String, String>{'content-length': '0'},
      );
    }
    return super.handle(request);
  }
}

/// 一个在**第一次** manifest 写入时抢先发布一版的服务器（并发 412 的来源）。
class _RacingServer extends FakeWebDavServer {
  /// 抢先发布的内容（另一台设备的那一版快照，是一份**合法**快照：
  /// 否则引擎读回来会按「快照无法解析」明确失败——那是正确的行为，但这个用例
  /// 要验的是 412 重试，不是解析失败）。
  List<int> raceContent = utf8.encode(
    SyncSnapshot.of(
      entities: <SyncEntity>[
        const SyncEntity(
          kind: SyncEntityKind.feed,
          key: 'feed.other',
          fields: <String, Object?>{
            'syncId': 'feed.other',
            'name': '另一台设备的源',
            'normalizedUrl': 'https://other.example.com/feed.xml',
          },
        ),
      ],
    ).encode(),
  );

  /// 还剩几次「抢先发布」。
  int pendingRaces = 1;

  /// 是否真的发生过抢先发布。
  bool raced = false;

  @override
  Future<http.StreamedResponse> handle(http.BaseRequest request) async {
    if (pendingRaces > 0 &&
        request.method == 'PUT' &&
        request.url.path.endsWith('manifest.json')) {
      pendingRaces--;
      raced = true;
      final String hash = snapshotContentHash(raceContent);
      seedFile('/flux-v1/${snapshotFileName(hash)}', raceContent);
      final SyncManifest? current = currentManifest();
      final SyncManifest racing = SyncManifest.forSnapshot(
        snapshotHash: hash,
        deviceName: 'other-device',
        revision: 7,
        publishedAt: DateTime.utc(2026, 9, 22, 3),
        parentVersion: current?.version,
      );
      seedFile('/flux-v1/manifest.json', utf8.encode(racing.encode()));
      // 我们读到的 ETag 已经过期：条件写必然失败。
      return http.StreamedResponse(
        const Stream<List<int>>.empty(),
        412,
        headers: <String, String>{'content-length': '0'},
      );
    }
    return super.handle(request);
  }
}

/// 一个会在第一次写入时执行回调的传输装饰器（模拟「上传期间用户又改了东西」）。
class _HookedTransport implements SyncTransport {
  _HookedTransport(this._inner, {required this.onFirstWrite});

  final SyncTransport _inner;
  final Future<void> Function() onFirstWrite;
  bool _fired = false;

  @override
  Future<Result<SyncTransportResponse>> listDirectory(Uri directory) =>
      _inner.listDirectory(directory);

  @override
  Future<Result<SyncTransportResponse>> read(Uri url) => _inner.read(url);

  @override
  Future<Result<SyncTransportResponse>> ensureDirectory(Uri url) =>
      _inner.ensureDirectory(url);

  @override
  Future<Result<SyncTransportResponse>> write(
    Uri url, {
    required List<int> bytes,
    String? ifMatch,
  }) async {
    if (!_fired) {
      _fired = true;
      await onFirstWrite();
    }
    return _inner.write(url, bytes: bytes, ifMatch: ifMatch);
  }
}

/// 一台设备的最小装配（内存库 + 引擎 + 共享的内存服务器）。
final class _Device {
  _Device(
    this.db,
    this.server, {
    required this.deviceName,
    DateTime? clockStart,
  }) {
    state = DriftSyncStore(db);
    content = DriftSyncLocalStore(db);
    transport = WebDavSyncTransport(
      client: WebDavClient(httpClient: server.asClient()),
      credentials: const SyncCredentials(username: 'flux', password: 'secret'),
    );
    clock = FakeClock(start: clockStart);
  }

  final AppDatabase db;
  final FakeWebDavServer server;
  final String deviceName;
  late final DriftSyncStore state;
  late final DriftSyncLocalStore content;
  late final WebDavSyncTransport transport;
  late final FakeClock clock;

  Uri get root => Uri.parse('http://dav.example.com/flux-v1');

  SyncEngine engine({SyncTransport? overrideTransport}) => SyncEngine(
    state: state,
    content: content,
    transport: overrideTransport ?? transport,
    remoteRoot: root,
    deviceName: deviceName,
    clock: clock,
  );

  Future<int> insertFeed({
    required String syncId,
    required String name,
    String? url,
    bool favorite = false,
    bool enabled = true,
  }) => db
      .into(db.feeds)
      .insert(
        FeedsCompanion.insert(
          syncId: syncId,
          // 规范化地址在库里有唯一索引（T013 的去重依据），因此测试里默认按 syncId
          // 派生一个互不相同的地址——共用同一个默认地址会让两个源在库里撞唯一约束。
          normalizedUrl: url ?? 'https://example.com/$syncId/feed.xml',
          name: name,
          favorite: Value<bool>(favorite),
          enabled: Value<bool>(enabled),
        ),
      );

  Future<int> insertArticle({
    required String syncKey,
    String state = 'unread',
    bool favorite = false,
    String? body,
  }) => db
      .into(db.articles)
      .insert(
        ArticlesCompanion.insert(
          title: '标题',
          identityBasis: IdentityBasis.guid,
          readingState: Value<ReadingState>(
            ReadingState.values.firstWhere((ReadingState s) => s.name == state),
          ),
          favorite: Value<bool>(favorite),
          syncKey: Value<String?>(syncKey),
          body: Value<String?>(body),
        ),
      );

  /// 记一条待同步变更（模拟用户改了这个字段）。
  Future<int> recordChange({
    required String kind,
    required String key,
    required String field,
  }) async {
    final int revision = (await state.bumpRevision()).unwrap();
    await state.recordPendingChanges(<PendingChange>[
      PendingChange(
        entityKind: kind,
        entityKey: key,
        fieldName: field,
        revision: revision,
        changedAt: DateTime.utc(2026, 9, 22),
      ),
    ]);
    return revision;
  }

  Future<void> close() => db.close();
}

Future<_Device> _newDevice(
  FakeWebDavServer server, {
  String name = 'Mac-A',
  DateTime? clockStart,
}) async {
  final AppDatabase db = AppDatabase.memory();
  await db.customSelect('SELECT 1').get();
  return _Device(db, server, deviceName: name, clockStart: clockStart);
}

/// 服务器上当前 manifest 的版本（用于断言「远端有没有被改写」）。
String? _remoteVersion(FakeWebDavServer server) =>
    server.currentManifest()?.version;

void main() {
  group('首次发布（远端还没有当前版本）', () {
    test('上传快照 → 条件写 manifest → 本机确认，基线推进到这一版', () async {
      final FakeWebDavServer server = FakeWebDavServer();
      final _Device device = await _newDevice(server);
      addTearDown(device.close);
      await device.insertFeed(syncId: 'feed.one', name: '一个源');

      final SyncRunResult result = await device.engine().run(
        capability: WebDavWriteCapability.conditionalWrite,
      );

      expect(result.status, SyncRunStatus.succeeded);
      expect(result.attempts, 1);
      expect(result.publishedVersion, isNotNull);
      expect(result.recoveredWithoutUpload, isFalse);
      // 远端确实有了当前版本，且它指向一个真实存在的快照文件。
      final SyncManifest? manifest = server.currentManifest();
      expect(manifest, isNotNull);
      expect(manifest!.version, result.publishedVersion);
      expect(
        server.files.containsKey('/flux-v1/${manifest.snapshotName}'),
        isTrue,
      );
      // 本机基线推进：下一轮就有了共同基线。
      final SyncBaseline baseline = (await device.state.readBaseline())
          .unwrap();
      expect(baseline.baseVersion, manifest.version);
      expect(baseline.lastSyncedAt, isNotNull);
    });

    test('发布内容里没有凭据（SET-071 不进快照）', () async {
      final FakeWebDavServer server = FakeWebDavServer();
      final _Device device = await _newDevice(server);
      addTearDown(device.close);
      await device.insertFeed(syncId: 'feed.one', name: '一个源');

      await device.engine().run(
        capability: WebDavWriteCapability.conditionalWrite,
      );

      final String body = utf8.decode(
        server.files['/flux-v1/${server.currentManifest()!.snapshotName}']!,
      );
      expect(body.contains('secret'), isFalse);
      expect(body.toLowerCase().contains('password'), isFalse);
    });
  });

  group('并发 412：重读 → 重合并 → 重试（≤3 轮）', () {
    test('两轮收敛：第二轮基于新读到的父版本发布，父版本链连续', () async {
      final _RacingServer server = _RacingServer();
      final _Device device = await _newDevice(server);
      addTearDown(device.close);
      await device.insertFeed(syncId: 'feed.one', name: '本机源');

      final SyncRunResult result = await device.engine().run(
        capability: WebDavWriteCapability.conditionalWrite,
      );

      expect(server.raced, isTrue, reason: '并发确实发生了');
      expect(
        result.status,
        SyncRunStatus.succeeded,
        reason: 'reason=${result.reason} attempts=${result.attempts}',
      );
      expect(result.attempts, 2, reason: '第一轮 412、第二轮成功');
      final SyncManifest manifest = server.currentManifest()!;
      expect(manifest.version, result.publishedVersion);
      // 父版本链：本机发布的那一版以「抢先的那一版」为父，因此两台设备的改动都在链上。
      expect(manifest.parentVersion, isNotNull);
      expect(
        manifest.parentVersion,
        versionForSnapshot(snapshotContentHash(server.raceContent)),
      );
      final String body = utf8.decode(
        server.files['/flux-v1/${manifest.snapshotName}']!,
      );
      final SyncSnapshot published = SyncSnapshot.decode(body)!;
      // 重合并的结果里同时包含另一台设备抢先发布的订阅与本机的订阅（键的并集）。
      expect(published.hasEntity(SyncEntityKind.feed, 'feed.one'), isTrue);
      expect(published.hasEntity(SyncEntityKind.feed, 'feed.other'), isTrue);
      // 基线推进到本机发布的那一版。
      expect(
        (await device.state.readBaseline()).unwrap().baseVersion,
        manifest.version,
      );
    });

    test('三轮用尽：等待重试，且远端 manifest 从未被本机改写', () async {
      final _AlwaysConflictingServer server = _AlwaysConflictingServer();
      final _Device device = await _newDevice(server);
      addTearDown(device.close);
      await device.insertFeed(syncId: 'feed.one', name: '本机源');

      final SyncRunResult result = await device.engine().run(
        capability: WebDavWriteCapability.conditionalWrite,
      );

      expect(result.status, SyncRunStatus.waitingRetry);
      expect(result.attempts, manifestConflictRetryLimit);
      expect(result.reason, 'manifestConflict');
      expect(server.rejectedManifestWrites, manifestConflictRetryLimit);
      // 远端没有当前版本（本机从没成功写过 manifest）。
      expect(server.currentManifest(), isNull);
      // 本机基线未推进：下一轮会重新走一遍，而不是以为已经同步过。
      final SyncBaseline baseline = (await device.state.readBaseline())
          .unwrap();
      expect(baseline.baseVersion, isNull);
    });
  });

  group('同字段并发冲突：不出 OR，等用户选版', () {
    test('read ↔ later 冲突时**不发布**，远端版本保持不变', () async {
      final FakeWebDavServer server = FakeWebDavServer();
      final _Device remote = await _newDevice(server, name: 'Mac-B');
      addTearDown(remote.close);
      final _Device local = await _newDevice(server, name: 'Mac-A');
      addTearDown(local.close);

      await remote.insertArticle(syncKey: 'key-1', state: 'later');
      await remote.engine().run(
        capability: WebDavWriteCapability.conditionalWrite,
      );
      final String? afterRemotePublish = _remoteVersion(server);

      // 本机有同一篇文章（同键），把它标成 read。
      await local.insertArticle(syncKey: 'key-1', state: 'read');
      final SyncRunResult result = await local.engine().run(
        capability: WebDavWriteCapability.conditionalWrite,
      );

      expect(result.status, SyncRunStatus.waitingConflictChoice);
      expect(result.conflicts.length, 1);
      expect(result.conflicts.single.field, 'readingState');
      expect(result.conflicts.single.localValue, 'read');
      expect(result.conflicts.single.remoteValue, 'later');
      // **没有发布**：远端版本一格没动（否则冲突就被一次上传单方面决定了）。
      expect(_remoteVersion(server), afterRemotePublish);
      // 本机基线也没推进：选版之前不算同步成功。
      expect((await local.state.readBaseline()).unwrap().baseVersion, isNull);
    });

    test('用户选远端后形成新版本并发布（选择就是「形成新版本」）', () async {
      final FakeWebDavServer server = FakeWebDavServer();
      final _Device remote = await _newDevice(server, name: 'Mac-B');
      addTearDown(remote.close);
      final _Device local = await _newDevice(server, name: 'Mac-A');
      addTearDown(local.close);

      await remote.insertArticle(syncKey: 'key-1', state: 'later');
      await remote.engine().run(
        capability: WebDavWriteCapability.conditionalWrite,
      );
      await local.insertArticle(syncKey: 'key-1', state: 'read');

      final SyncRunResult probe = await local.engine().run(
        capability: WebDavWriteCapability.conditionalWrite,
      );
      final String conflictKey = probe.conflicts.single.mapKey;

      final SyncRunResult result = await local.engine().run(
        capability: WebDavWriteCapability.conditionalWrite,
        choices: <String, SyncConflictChoice>{
          conflictKey: SyncConflictChoice.remote,
        },
      );

      expect(result.status, SyncRunStatus.succeeded);
      final SyncSnapshot published = SyncSnapshot.decode(
        utf8.decode(
          server.files['/flux-v1/${server.currentManifest()!.snapshotName}']!,
        ),
      )!;
      expect(
        published
            .entity(SyncEntityKind.articleState, 'key-1')!
            .fields['readingState'],
        'later',
      );
    });

    test('取消收藏不会被远端复活（收藏是独立字段，与本机值一致时不是冲突）', () async {
      final FakeWebDavServer server = FakeWebDavServer();
      final _Device local = await _newDevice(server, name: 'Mac-A');
      addTearDown(local.close);

      // 本机先发布一版（建立共同基线），内容 = 「已读 + 收藏」。
      await local.insertArticle(
        syncKey: 'key-9',
        state: 'read',
        favorite: true,
      );
      await local.engine().run(
        capability: WebDavWriteCapability.conditionalWrite,
      );
      // 然后本机取消收藏（并记录一条待同步变更，模拟真实写入路径）。
      await local.db
          .update(local.db.articles)
          .write(const ArticlesCompanion(favorite: Value<bool>(false)));
      await local.recordChange(
        kind: SyncEntityKind.articleState,
        key: 'key-9',
        field: 'favorite',
      );

      final SyncRunResult result = await local.engine().run(
        capability: WebDavWriteCapability.conditionalWrite,
      );

      expect(result.status, SyncRunStatus.succeeded);
      final SyncSnapshot published = SyncSnapshot.decode(
        utf8.decode(
          server.files['/flux-v1/${server.currentManifest()!.snapshotName}']!,
        ),
      )!;
      expect(
        published
            .entity(SyncEntityKind.articleState, 'key-9')!
            .fields['favorite'],
        isFalse,
        reason: '取消收藏不得被 OR 回来',
      );
      // 本机自己也仍然是「未收藏」（远端与基线同值，因此没有被 OR 回来）。
      final Article row =
          (await local.db.select(local.db.articles).get()).single;
      expect(row.favorite, isFalse);
    });
  });

  group('墓碑：删除不复活', () {
    test('本机已删除的订阅不会因为远端还在而被写回，远端发布的内容里也没有它', () async {
      final FakeWebDavServer server = FakeWebDavServer();
      final _Device remote = await _newDevice(server, name: 'Mac-B');
      addTearDown(remote.close);
      final _Device local = await _newDevice(server, name: 'Mac-A');
      addTearDown(local.close);

      await remote.insertFeed(syncId: 'feed.gone', name: '远端还有');
      await remote.engine().run(
        capability: WebDavWriteCapability.conditionalWrite,
      );

      // 本机：没有这条订阅，但有它的墓碑（用户在这台设备上删过）。
      await local.state.recordTombstone(
        SyncTombstone(
          entityKind: SyncEntityKind.feed,
          entityKey: 'feed.gone',
          deletedAt: DateTime.utc(2026, 9, 22, 2),
          revision: 1,
          displayName: '远端还有',
        ),
      );

      final SyncRunResult result = await local.engine().run(
        capability: WebDavWriteCapability.conditionalWrite,
      );

      expect(result.status, SyncRunStatus.succeeded);
      // 本机没有被写回这条订阅。
      expect(await local.db.select(local.db.feeds).get(), isEmpty);
      // 远端新发布的那一版里也没有它（墓碑随快照传播）。
      final SyncSnapshot published = SyncSnapshot.decode(
        utf8.decode(
          server.files['/flux-v1/${server.currentManifest()!.snapshotName}']!,
        ),
      )!;
      expect(
        published.hasEntity(SyncEntityKind.feed, 'feed.gone'),
        isFalse,
        reason: '删除优先于远端复活',
      );
      expect(
        published.hasDeletion(SyncEntityKind.feed, 'feed.gone'),
        isTrue,
        reason: '墓碑必须继续传播（首发不自动清除）',
      );
    });

    test('远端破坏性删除只登记为待确认，本机数据不清', () async {
      final FakeWebDavServer server = FakeWebDavServer();
      final _Device remote = await _newDevice(server, name: 'Mac-B');
      addTearDown(remote.close);
      final _Device local = await _newDevice(server, name: 'Mac-A');
      addTearDown(local.close);

      await local.insertFeed(syncId: 'feed.alive', name: '本机的源');
      await local.engine().run(
        capability: WebDavWriteCapability.conditionalWrite,
      );

      // 另一台设备把这条订阅删了（墓碑 + 内容里没有它）。
      final SyncSnapshot tombstoned = SyncSnapshot.of(
        entities: const <SyncEntity>[],
        deletions: <SyncDeletion>[
          const SyncDeletion(
            kind: SyncEntityKind.feed,
            key: 'feed.alive',
            keepFavorites: false,
            displayName: '本机的源',
          ),
        ],
      );
      final List<int> bytes = utf8.encode(tombstoned.encode());
      final String hash = snapshotContentHash(bytes);
      final String snapName = snapshotFileName(hash);
      server.seedFile('/flux-v1/$snapName', bytes);
      server.seedFile(
        '/flux-v1/manifest.json',
        utf8.encode(
          SyncManifest.forSnapshot(
            snapshotHash: hash,
            deviceName: 'Mac-B',
            revision: 9,
            publishedAt: DateTime.utc(2026, 9, 22, 5),
          ).encode(),
        ),
      );

      final SyncRunResult result = await local.engine().run(
        capability: WebDavWriteCapability.conditionalWrite,
      );

      expect(result.pendingRemoteDeletions.length, 1);
      expect(result.pendingRemoteDeletions.single.key, 'feed.alive');
      // **未确认不清数据**：本机的订阅还在。
      expect(await local.db.select(local.db.feeds).get(), hasLength(1));
    });
  });

  group('上传期间的新本地修改必须留下（架构 5.2「仅确认已包含的修订」）', () {
    test('上传期间用户又改了同一个字段 → 该字段保留本机新值，且待同步行仍在', () async {
      final FakeWebDavServer server = FakeWebDavServer();
      final _Device device = await _newDevice(server);
      addTearDown(device.close);
      final int feedId = await device.insertFeed(
        syncId: 'feed.one',
        name: '旧名字',
      );

      // 本次同步开始前：本机已有一批待同步变更（修订 1）。
      await device.recordChange(
        kind: SyncEntityKind.feed,
        key: 'feed.one',
        field: 'name',
      );

      // 上传第一次写入发生时（也就是同步已经在途），用户把名字改成了新值，
      // 并产生一条**更大修订号**的待同步变更。
      final int newer = await device.recordChange(
        kind: SyncEntityKind.feed,
        key: 'feed.one',
        field: 'name',
      );
      final _HookedTransport hooked = _HookedTransport(
        device.transport,
        onFirstWrite: () async {
          await (device.db.update(device.db.feeds)
                ..where((Feeds t) => t.id.equals(feedId)))
              .write(const FeedsCompanion(name: Value<String>('上传期间的新名字')));
          await device.recordChange(
            kind: SyncEntityKind.feed,
            key: 'feed.one',
            field: 'name',
          );
        },
      );

      final SyncRunResult result = await device
          .engine(overrideTransport: hooked)
          .run(capability: WebDavWriteCapability.conditionalWrite);

      expect(result.status, SyncRunStatus.succeeded);
      // 本机的新名字没有被那一轮上传的旧值盖掉。
      final Feed row = (await device.db.select(device.db.feeds).get()).single;
      expect(row.name, '上传期间的新名字');
      expect(result.preservedLocalFields, isNotEmpty);
      expect(
        result.preservedLocalFields.any(
          (String entry) => entry.contains('name'),
        ),
        isTrue,
      );
      // 待同步行仍然在（更大的修订号 > 本轮固定上界），因此下一轮会把它上传。
      final List<SyncPendingChange> left = await device.db
          .select(device.db.syncPendingChanges)
          .get();
      expect(left, isNotEmpty);
      expect(
        left.every(
          (SyncPendingChange r) => r.revision > result.confirmedRevision,
        ),
        isTrue,
      );
      expect(newer, greaterThan(0));
    });
  });

  group('崩溃恢复：远端已发布而本机未确认 → 幂等补确认，不重复上传', () {
    test('重跑一轮不产生新快照，也不推进远端版本', () async {
      final FakeWebDavServer server = FakeWebDavServer();
      final _Device device = await _newDevice(server);
      addTearDown(device.close);
      await device.insertFeed(syncId: 'feed.one', name: '一个源');

      final SyncRunResult first = await device.engine().run(
        capability: WebDavWriteCapability.conditionalWrite,
      );
      expect(first.status, SyncRunStatus.succeeded);
      final List<String> snapshotsAfterFirst = server.snapshotNames();
      final String? versionAfterFirst = _remoteVersion(server);

      // 模拟「远端发布成功但本机未确认就崩溃」：本机基线没推进。
      await device.db
          .update(device.db.syncStateRecords)
          .write(
            const SyncStateRecordsCompanion(
              baseVersion: Value<String?>(null),
              lastSyncedAt: Value<DateTime?>(null),
            ),
          );

      final SyncRunResult second = await device.engine().run(
        capability: WebDavWriteCapability.conditionalWrite,
      );

      expect(second.status, SyncRunStatus.succeeded);
      expect(second.recoveredWithoutUpload, isTrue);
      expect(second.publishedVersion, versionAfterFirst);
      // **没有重复上传**：快照集合与远端版本都没变。
      expect(server.snapshotNames(), snapshotsAfterFirst);
      expect(_remoteVersion(server), versionAfterFirst);
      // 本机基线补确认。
      expect(
        (await device.state.readBaseline()).unwrap().baseVersion,
        versionAfterFirst,
      );
    });
  });

  group('降级服务器：只读拉取，不覆盖（架构 5.2）', () {
    test('readOnlyPull：一个字节都不写，但能把远端快照读下来', () async {
      final FakeWebDavServer server = FakeWebDavServer();
      final _Device remote = await _newDevice(server, name: 'Mac-B');
      addTearDown(remote.close);
      final _Device local = await _newDevice(server, name: 'Mac-A');
      addTearDown(local.close);

      await remote.insertFeed(syncId: 'feed.remote', name: '远端源');
      await remote.engine().run(
        capability: WebDavWriteCapability.conditionalWrite,
      );
      final int putsBefore = server.putCount;
      final String? versionBefore = _remoteVersion(server);

      final SyncRunResult result = await local.engine().run(
        capability: WebDavWriteCapability.readOnlyPull,
      );

      expect(result.status, SyncRunStatus.readonlyPull);
      expect(result.reason, 'conditionalWriteUnsupported');
      expect(server.putCount, putsBefore, reason: '降级路径一个字节都不写');
      expect(_remoteVersion(server), versionBefore);
      // 远端内容可以读下来（供显式导入预览），但本机没有自动写入任何订阅。
      expect(result.pulledSnapshot, isNotNull);
      expect(
        result.pulledSnapshot!.hasEntity(SyncEntityKind.feed, 'feed.remote'),
        isTrue,
      );
      expect(await local.db.select(local.db.feeds).get(), isEmpty);
    });

    test('能力未探测（unknown）同样 fail-closed：不写', () async {
      final FakeWebDavServer server = FakeWebDavServer();
      final _Device device = await _newDevice(server);
      addTearDown(device.close);
      await device.insertFeed(syncId: 'feed.one', name: '一个源');

      final SyncRunResult result = await device.engine().run(
        capability: WebDavWriteCapability.unknown,
      );

      expect(result.status, SyncRunStatus.readonlyPull);
      expect(server.putCount, 0);
    });
  });

  group('设备时钟偏移不影响结果（架构 5.2「不得仅比较设备墙钟」）', () {
    test('两台设备相差一年、且互相超前落后，合并结果只由基线决定', () async {
      // 两台设备共享**同一份**远端（同一个服务器实例），因此能互相看到对方发布的版本；
      // 它们的时钟一个落后一年、一个超前一年——「谁更新」在这套规则里根本无从比较。
      final FakeWebDavServer server = FakeWebDavServer();
      final _Device deviceA = await _newDevice(
        server,
        name: 'Mac-A',
        clockStart: DateTime.utc(2025, 1, 1),
      );
      addTearDown(deviceA.close);
      final _Device deviceB = await _newDevice(
        server,
        name: 'Mac-B',
        clockStart: DateTime.utc(2027, 1, 1),
      );
      addTearDown(deviceB.close);

      await deviceA.insertArticle(syncKey: 'key-1');
      await deviceA.insertFeed(syncId: 'feed.a', name: 'A 的源');
      await deviceB.insertArticle(syncKey: 'key-1');
      await deviceB.insertFeed(syncId: 'feed.b', name: 'B 的源');

      // 1) B 先发布，建立共同基线（内容：这篇文章未读、两个源还没有并集）。
      final SyncRunResult firstByB = await deviceB.engine().run(
        capability: WebDavWriteCapability.conditionalWrite,
      );
      expect(firstByB.status, SyncRunStatus.succeeded);

      // 2) A 合并发布：两边的订阅并集进来（A 与 B 各有一条）。
      final SyncRunResult byA = await deviceA.engine().run(
        capability: WebDavWriteCapability.conditionalWrite,
      );
      expect(
        byA.status,
        SyncRunStatus.succeeded,
        reason: 'reason=${byA.reason} attempts=${byA.attempts}',
      );
      expect(byA.merged!.hasEntity(SyncEntityKind.feed, 'feed.a'), isTrue);
      expect(byA.merged!.hasEntity(SyncEntityKind.feed, 'feed.b'), isTrue);

      // 3) A 把这篇标成已读并发布（A 的时钟比 B 落后一年）。
      await deviceA.db
          .update(deviceA.db.articles)
          .write(
            const ArticlesCompanion(
              readingState: Value<ReadingState>(ReadingState.read),
            ),
          );
      await deviceA.recordChange(
        kind: SyncEntityKind.articleState,
        key: 'key-1',
        field: 'readingState',
      );
      final SyncRunResult readByA = await deviceA.engine().run(
        capability: WebDavWriteCapability.conditionalWrite,
      );
      expect(
        readByA.status,
        SyncRunStatus.succeeded,
        reason: 'reason=${readByA.reason} attempts=${readByA.attempts}',
      );

      // 4) B 再同步：B 没有改过这篇文章（相对它的基线仍是 unread），因此取远端的 read。
      //    若这里按墙钟判断（B 的时钟超前一年），就会得出「B 更新」并把 unread 发回去。
      final SyncRunResult byB = await deviceB.engine().run(
        capability: WebDavWriteCapability.conditionalWrite,
      );
      expect(byB.status, SyncRunStatus.succeeded);
      expect(
        byB.merged!
            .entity(SyncEntityKind.articleState, 'key-1')!
            .fields['readingState'],
        'read',
      );

      // 远端最终那一版同样是 read（而不是被「时钟更晚」的那台改回未读）。
      final SyncManifest finalManifest = server.currentManifest()!;
      final SyncSnapshot finalSnapshot = SyncSnapshot.decode(
        utf8.decode(server.files['/flux-v1/${finalManifest.snapshotName}']!),
      )!;
      expect(
        finalSnapshot
            .entity(SyncEntityKind.articleState, 'key-1')!
            .fields['readingState'],
        'read',
      );
      expect(finalSnapshot.hasEntity(SyncEntityKind.feed, 'feed.a'), isTrue);
      expect(finalSnapshot.hasEntity(SyncEntityKind.feed, 'feed.b'), isTrue);
    });
  });
}
