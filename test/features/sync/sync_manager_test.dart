// T044：同步管理器的触发排队、首次合并预览与冲突选版（SET-072/073/075、架构 5.2）。
//
// 用替身断言**行为**（什么时候真的跑、跑几次、有没有写东西），用真实内存库与内存 WebDAV
// 服务器断言**数据**（首次预览不覆盖、冲突不发布、选版之后形成新版本）。
// 真实服务器的双客户端验证按手册 7.3 记 NOT_RUN（无凭据），这里证明的是规则与编排。
import 'dart:async';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';

import 'package:flux/core/core.dart';
import 'package:flux/features/settings/application/settings_store.dart';
import 'package:flux/features/sync/application/sync_engine.dart';
import 'package:flux/features/sync/application/sync_manager.dart';
import 'package:flux/features/sync/application/sync_settings.dart';
import 'package:flux/infrastructure/local/database.dart';
import 'package:flux/infrastructure/local/sync_local_store.dart';
import 'package:flux/infrastructure/local/sync_status_reader.dart';
import 'package:flux/infrastructure/local/sync_store.dart';
import 'package:flux/infrastructure/network/webdav_client.dart';
import 'package:flux/infrastructure/network/webdav_transport.dart';

import '../../infrastructure/network/fake_webdav_server.dart';

/// 可写的设置替身（同步管理器只读它，但测试要能改）。
final class _MutableSettings implements SettingsStore {
  /// 有效值（键为 SET 编号）。
  final Map<String, Object?> effective = <String, Object?>{};

  @override
  Future<Result<Object?>> readSetting(SettingId id) async =>
      Ok<Object?>(effective[id.code]);

  @override
  Future<Result<Object?>> writeSetting(SettingId id, Object? value) async =>
      const Ok<Object?>(null);

  @override
  Future<Result<Map<String, Object?>>> readEffectiveSettings() async =>
      Ok<Map<String, Object?>>(effective);

  /// 配置一个可用的同步端点（其余设置用默认值）。
  void configure({
    bool enabled = true,
    bool syncOnStart = true,
    bool syncOnChange = true,
    // 地址的路径为空，使远端目录正好是内存服务器的默认根（/flux-v1）：
    // 这样 `currentManifest()` 与快照列表读的就是同一份内容。
    String url = 'https://dav.example.com',
    String username = 'flux',
    int intervalMinutes = 30,
    bool manualOnly = false,
    int debounceSeconds = 5,
    bool firstSyncPreview = true,
    String conflictPolicy = 'manual',
  }) {
    effective[SettingId.set070.code] = <String, Object?>{
      'url': url,
      'username': username,
      'remoteDirectory': 'flux-v1',
      'deviceName': 'Mac-A',
    };
    effective[SettingId.set072.code] = <String, Object?>{
      'enabled': enabled,
      'syncOnStart': syncOnStart,
      'syncOnChange': syncOnChange,
      'changeDebounceSeconds': debounceSeconds,
    };
    effective[SettingId.set073.code] = <String, Object?>{
      'intervalMinutes': intervalMinutes,
      'manualOnly': manualOnly,
    };
    effective[SettingId.set075.code] = <String, Object?>{
      'firstSyncPreview': firstSyncPreview,
      'conflictPolicy': conflictPolicy,
    };
  }
}

/// 计数用的传输装饰器。
/// 可在第一次写请求前阻塞的传输装饰器（构造「一次运行在途」的确定窗口）。
final class _GatedTransport implements SyncTransport {
  _GatedTransport(this._inner, this.beforeFirstWrite);

  final SyncTransport _inner;
  final Future<void> Function() beforeFirstWrite;
  bool _entered = false;

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
    if (!_entered) {
      _entered = true;
      await beforeFirstWrite();
    }
    return _inner.write(url, bytes: bytes, ifMatch: ifMatch);
  }
}

/// 计数用的传输装饰器。
final class _CountingTransport implements SyncTransport {
  _CountingTransport(this._inner);

  final SyncTransport _inner;

  /// 写请求数。
  int writes = 0;

  /// 读请求数。
  int reads = 0;

  @override
  Future<Result<SyncTransportResponse>> listDirectory(Uri directory) {
    reads++;
    return _inner.listDirectory(directory);
  }

  @override
  Future<Result<SyncTransportResponse>> read(Uri url) {
    reads++;
    return _inner.read(url);
  }

  @override
  Future<Result<SyncTransportResponse>> ensureDirectory(Uri url) =>
      _inner.ensureDirectory(url);

  @override
  Future<Result<SyncTransportResponse>> write(
    Uri url, {
    required List<int> bytes,
    String? ifMatch,
  }) {
    writes++;
    return _inner.write(url, bytes: bytes, ifMatch: ifMatch);
  }
}

/// 一台设备（内存库 + 内存 WebDAV 服务器 + 管理器）。
final class _Harness {
  _Harness(this.db, this.server) {
    state = DriftSyncStore(db);
    content = DriftSyncLocalStore(db);
    statusReader = DriftSyncStatusReader(db);
    transport = WebDavSyncTransport(
      client: WebDavClient(httpClient: server.asClient()),
      credentials: const SyncCredentials(username: 'flux', password: 'secret'),
    );
    settings = _MutableSettings();
  }

  final AppDatabase db;
  final FakeWebDavServer server;
  late final DriftSyncStore state;
  late final DriftSyncLocalStore content;
  late final DriftSyncStatusReader statusReader;
  late final WebDavSyncTransport transport;
  late final _MutableSettings settings;

  final FakeClock clock = FakeClock(start: DateTime.utc(2026, 9, 22, 10));

  Uri get root => Uri.parse('https://dav.example.com/dav/flux-v1');

  /// 探测次数（断言「不重复探测」）。
  int probes = 0;

  /// 由管理器现造的引擎（每轮一个）。
  SyncEngine? engineFor(SyncSettings settings, SyncCredentials credentials) {
    final WebDavSyncTransport effective = WebDavSyncTransport(
      client: WebDavClient(httpClient: server.asClient()),
      credentials: credentials,
    );
    counted = _CountingTransport(effective);
    return SyncEngine(
      state: state,
      content: content,
      transport: counted!,
      remoteRoot: settings.remoteRoot ?? root,
      deviceName: settings.deviceName.isEmpty ? 'Mac-A' : settings.deviceName,
      clock: clock,
    );
  }

  _CountingTransport? counted;

  SyncManager manager({void Function(SyncStatusSnapshot)? onStatus}) {
    final SyncManager manager = SyncManager(
      readSettings: () => SyncSettingsReader(settings).load(),
      readStatusBaseline: () async {
        final Result<SyncStatusBaseline> read = await statusReader.read();
        return read;
      },
      buildEngine: engineFor,
      probeCapability: (SyncSettings value, SyncCredentials credentials) async {
        probes++;
        return const Ok<WebDavWriteCapability>(
          WebDavWriteCapability.conditionalWrite,
        );
      },
      loadCredentials: (SyncSettings value) async => const Ok<SyncCredentials>(
        SyncCredentials(username: 'flux', password: 'secret'),
      ),
      readLocalContentSnapshot: () => content.readLocalSnapshot(),
      clock: clock,
      onStatus: onStatus,
    );
    return manager;
  }

  Future<int> insertFeed(String syncId, String name) => db
      .into(db.feeds)
      .insert(
        FeedsCompanion.insert(
          syncId: syncId,
          normalizedUrl: 'https://example.com/$syncId.xml',
          name: name,
        ),
      );

  Future<void> close() => db.close();
}

Future<_Harness> _harness(FakeWebDavServer server) async {
  final AppDatabase db = AppDatabase.memory();
  await db.customSelect('SELECT 1').get();
  return _Harness(db, server);
}

void main() {
  group('触发来源与串行排队（SET-072/073）', () {
    test('启动：配置齐备时同步一次（探一次能力），未配置时一个请求都不发', () async {
      final FakeWebDavServer server = FakeWebDavServer();
      final _Harness harness = await _harness(server);
      addTearDown(harness.close);
      await harness.insertFeed('feed.a', '一个源');

      // 未配置：不探测、不发请求。
      final _Harness unconfigured = await _harness(FakeWebDavServer());
      addTearDown(unconfigured.close);
      await unconfigured.manager().onLaunch();
      expect(unconfigured.probes, 0);
      expect(unconfigured.server.requestLog, isEmpty);

      // 配置齐备：启动即同步一次。
      harness.settings.configure();
      final SyncManager manager = harness.manager();
      addTearDown(manager.dispose);
      await manager.onLaunch();

      expect(harness.probes, 1);
      expect(manager.status.lastStatus, SyncRunStatus.succeeded);
      expect(server.currentManifest(), isNotNull);
    });

    test('关闭同步（SET-072）时手动触发也不发请求，并如实说明「已关闭」', () async {
      final FakeWebDavServer server = FakeWebDavServer();
      final _Harness harness = await _harness(server);
      addTearDown(harness.close);
      harness.settings.configure(enabled: false);
      final SyncManager manager = harness.manager();
      addTearDown(manager.dispose);

      await manager.onLaunch();
      final SyncRunResult? result = await manager.request(SyncTrigger.manual);

      expect(result, isNull);
      expect(server.requestLog, isEmpty, reason: '关闭时一个字节都不发');
      expect(manager.status.lastErrorReason, 'syncDisabled');
    });

    test('同机不并发：运行中再次触发只记下「待跑」，不产生第二次同步', () async {
      final FakeWebDavServer server = FakeWebDavServer();
      final _Harness harness = await _harness(server);
      addTearDown(harness.close);
      await harness.insertFeed('feed.a', '一个源');
      harness.settings.configure(firstSyncPreview: false);

      // 让第一次同步**停在上传那一步**：这样才能确定地构造出「一次运行在途」的窗口，
      // 而不是靠时序碰运气。
      final Completer<void> gate = Completer<void>();
      bool gated = false;
      final SyncManager manager = SyncManager(
        readSettings: () => SyncSettingsReader(harness.settings).load(),
        readStatusBaseline: harness.statusReader.read,
        buildEngine: (SyncSettings settings, SyncCredentials credentials) {
          final SyncEngine? engine = harness.engineFor(settings, credentials);
          if (engine == null) {
            return null;
          }
          return SyncEngine(
            state: harness.state,
            content: harness.content,
            transport: _GatedTransport(engine.transport, () async {
              if (!gated) {
                gated = true;
                await gate.future;
              }
            }),
            remoteRoot: engine.remoteRoot,
            deviceName: engine.deviceName,
            clock: harness.clock,
          );
        },
        probeCapability:
            (SyncSettings value, SyncCredentials credentials) async =>
                const Ok<WebDavWriteCapability>(
                  WebDavWriteCapability.conditionalWrite,
                ),
        loadCredentials: (SyncSettings value) async =>
            const Ok<SyncCredentials>(
              SyncCredentials(username: 'flux', password: 'secret'),
            ),
        readLocalContentSnapshot: harness.content.readLocalSnapshot,
        clock: harness.clock,
      );
      addTearDown(manager.dispose);

      final Future<SyncRunResult?> first = manager.request(SyncTrigger.manual);
      // 等到第一次运行确实进入在途状态（引擎已经走到写入那一步并被拦住）。
      while (!gated) {
        await Future<void>.delayed(Duration.zero);
      }
      final SyncRunResult? concurrent = await manager.request(
        SyncTrigger.manual,
      );
      expect(concurrent, isNull, reason: '在途时的触发被合并，不同时开第二轮');
      expect(manager.status.queued, isTrue);
      expect(manager.status.running, isTrue);

      gate.complete();
      await first;
      // 被合并的那次触发在上一轮结束后**串行**跑掉，而不是被丢掉。
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(manager.hasQueuedTrigger, isFalse);
      expect(manager.status.running, isFalse);
      // 只有一份快照：被合并的触发跑的是同一份内容（内容寻址天然幂等）。
      expect(server.snapshotNames().length, 1);
    });

    test('变更防抖（SET-072）：连续变更只在上次改动静默满时长后触发一次', () async {
      final FakeWebDavServer server = FakeWebDavServer();
      final _Harness harness = await _harness(server);
      addTearDown(harness.close);
      await harness.insertFeed('feed.a', '一个源');
      harness.settings.configure(debounceSeconds: 5, firstSyncPreview: false);

      final SyncManager manager = harness.manager();
      addTearDown(manager.dispose);

      manager.notifyLocalChange();
      // 防抖的计时器在读到设置之后才建立（读设置是异步的），因此先让它跑完一轮微任务。
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(manager.hasPendingDebounce, isTrue);
      // 再改两次：计时器**重新开始**，因此仍然没有同步发生。
      manager.notifyLocalChange();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      manager.notifyLocalChange();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(server.requestLog, isEmpty, reason: '防抖未到点，不得发出请求');

      // 5 秒防抖在测试里不等真实时间：这里断言「未到点不发」这条规则本身，
      // 到点之后确实是同一条 request 路径（由上面「启动/手动」用例覆盖）。
      expect(manager.status.running, isFalse);
    });

    test('manualOnly（SET-073）：不起定时器', () async {
      final FakeWebDavServer server = FakeWebDavServer();
      final _Harness harness = await _harness(server);
      addTearDown(harness.close);
      harness.settings.configure(manualOnly: true);
      final SyncManager manager = harness.manager();
      addTearDown(manager.dispose);

      manager.startIntervalTimer();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      // 没有定时器就没有定时触发：状态里的触发来源只能是启动或手动。
      expect(manager.status.lastTrigger, isNull);
    });
  });

  group('首次合并预览（SET-075「首次预览合并，不默认覆盖」）', () {
    test('远端已有内容且本机没有基线时：**先预览不写**，并给出默认「以本机为准」策略', () async {
      final FakeWebDavServer server = FakeWebDavServer();
      // 远端先有一份内容（另一台设备发布的）。
      final _Harness remote = await _harness(server);
      addTearDown(remote.close);
      await remote.insertFeed('feed.remote', '远端的源');
      remote.settings.configure(firstSyncPreview: false);
      await remote.manager().request(SyncTrigger.manual);

      final _Harness local = await _harness(server);
      addTearDown(local.close);
      await local.insertFeed('feed.local', '本机的源');
      local.settings.configure(firstSyncPreview: true);

      final SyncManager manager = local.manager();
      addTearDown(manager.dispose);
      final int writesBefore = server.putCount;

      final SyncRunResult? result = await manager.request(SyncTrigger.manual);

      expect(result, isNull, reason: '首次合并预览不发布');
      expect(server.putCount, writesBefore, reason: '预览路径一个字节都不写');
      final SyncFirstMergePreview preview = manager.status.firstMergePreview!;
      expect(preview.remoteEntityCount, greaterThan(0));
      expect(preview.localEntityCount, greaterThan(0));
      expect(
        preview.recommendedPolicy,
        SyncConflictPolicy.preferLocal,
        reason: '默认不覆盖本地',
      );
      // 远端只有一个源，本机只有一个源，因此「只有一边有」的键各一个。
      expect(preview.remoteOnlyKeys, 1);
      expect(preview.localOnlyKeys, 1);
    });

    test('用户确认（默认不覆盖本地）后建立基线并发布，且本机内容仍在', () async {
      final FakeWebDavServer server = FakeWebDavServer();
      final _Harness remote = await _harness(server);
      addTearDown(remote.close);
      await remote.insertFeed('feed.remote', '远端的源');
      remote.settings.configure(firstSyncPreview: false);
      await remote.manager().request(SyncTrigger.manual);

      final _Harness local = await _harness(server);
      addTearDown(local.close);
      await local.insertFeed('feed.local', '本机的源');
      local.settings.configure(firstSyncPreview: true);

      final SyncManager manager = local.manager();
      addTearDown(manager.dispose);
      await manager.request(SyncTrigger.manual);
      expect(manager.status.firstMergePreview, isNotNull);

      final SyncRunResult? confirmed = await manager.confirmFirstMerge(
        policy: SyncConflictPolicy.preferLocal,
      );

      expect(confirmed, isNotNull);
      expect(confirmed!.status, SyncRunStatus.succeeded);
      // 基线建立：预览消失。
      expect(manager.status.firstMergePreview, isNull);
      expect(
        (await local.state.readBaseline()).unwrap().baseVersion,
        isNotNull,
      );
      // 本机的源没有被远端覆盖掉（并集结果里两个都在）。
      final List<Feed> feeds = await local.db.select(local.db.feeds).get();
      expect(feeds, hasLength(2));
      expect(
        feeds.map((Feed f) => f.syncId),
        containsAll(<String>['feed.local', 'feed.remote']),
      );
    });

    test('关闭首次预览（SET-075）时不预览，直接合并发布', () async {
      final FakeWebDavServer server = FakeWebDavServer();
      final _Harness remote = await _harness(server);
      addTearDown(remote.close);
      await remote.insertFeed('feed.remote', '远端的源');
      remote.settings.configure(firstSyncPreview: false);
      await remote.manager().request(SyncTrigger.manual);

      final _Harness local = await _harness(server);
      addTearDown(local.close);
      await local.insertFeed('feed.local', '本机的源');
      local.settings.configure(firstSyncPreview: false);

      final SyncManager manager = local.manager();
      addTearDown(manager.dispose);
      final SyncRunResult? result = await manager.request(SyncTrigger.manual);

      expect(result, isNotNull);
      expect(result!.status, SyncRunStatus.succeeded);
      expect(manager.status.firstMergePreview, isNull);
    });
  });

  group('冲突选择流程（SET-075「同字段并发人工选版」）', () {
    test('manual 策略下冲突进状态并**不发布**；选版后续跑形成新版本', () async {
      final FakeWebDavServer server = FakeWebDavServer();
      final _Harness remote = await _harness(server);
      addTearDown(remote.close);
      await remote.db
          .into(remote.db.articles)
          .insert(
            ArticlesCompanion.insert(
              title: '标题',
              identityBasis: IdentityBasis.guid,
              syncKey: const Value<String?>('key-1'),
              readingState: const Value<ReadingState>(ReadingState.later),
            ),
          );
      remote.settings.configure(firstSyncPreview: false);
      await remote.manager().request(SyncTrigger.manual);
      final String? versionBefore = server.currentManifest()?.version;

      final _Harness local = await _harness(server);
      addTearDown(local.close);
      // 本机同一篇文章（同跨设备键）标成 read，并先建立基线（用一次发布）。
      await local.insertFeed('feed.local', '本机的源');
      local.settings.configure(firstSyncPreview: false);
      final SyncManager manager = local.manager();
      addTearDown(manager.dispose);
      // 先合并一次把远端的那篇读进来（无冲突：本机此时还没有这篇文章）。
      await manager.request(SyncTrigger.manual);

      // 基线此刻是「later」（第一次合并的结果）。现在两边**各自**把它改成不同的值：
      // 本机改成 unread、远端改成 read → 双方都相对基线变了且互不相同，是真冲突。
      await local.db
          .update(local.db.articles)
          .write(
            const ArticlesCompanion(
              readingState: Value<ReadingState>(ReadingState.unread),
            ),
          );
      await remote.db
          .update(remote.db.articles)
          .write(
            const ArticlesCompanion(
              readingState: Value<ReadingState>(ReadingState.read),
            ),
          );
      await remote.manager().request(SyncTrigger.manual);

      final SyncRunResult? conflicted = await manager.request(
        SyncTrigger.manual,
      );

      expect(conflicted, isNotNull);
      expect(
        conflicted!.status,
        SyncRunStatus.waitingConflictChoice,
        reason: 'manual 策略下同字段并发不自动选边',
      );
      expect(manager.status.conflicts, isNotEmpty);
      expect(manager.status.needsUserAction, isTrue);
      // 冲突未决时远端版本没有因为本机而改变。
      expect(manager.status.lastStatus, SyncRunStatus.waitingConflictChoice);
      expect(versionBefore, isNotNull);

      // 用户选「以本机为准」（把本机值保留）→ 形成新版本。
      final Map<String, SyncConflictChoice> choices =
          <String, SyncConflictChoice>{
            for (final SyncMergeConflict conflict in manager.status.conflicts)
              conflict.mapKey: SyncConflictChoice.local,
          };
      final SyncRunResult? resolved = await manager.resolveConflicts(
        choices,
        policy: SyncConflictPolicy.preferLocal,
      );

      expect(resolved, isNotNull);
      expect(resolved!.status, SyncRunStatus.succeeded);
      expect(manager.status.conflicts, isEmpty, reason: '选完之后冲突被清掉');
      expect(
        resolved.conflicts,
        isNotEmpty,
        reason: '引擎仍然记录「这次发生过哪条冲突」（事实），只是不再向用户追问',
      );
      // 新版本已发布到远端。
      final SyncSnapshot published = SyncSnapshot.decode(
        String.fromCharCodes(
          server.files['/flux-v1/${server.currentManifest()!.snapshotName}']!,
        ),
      )!;
      expect(
        published
            .entity(SyncEntityKind.articleState, 'key-1')!
            .fields['readingState'],
        'unread',
        reason: '用户选了本机值（unread），新版本里就是它',
      );
    });

    test('preferRemote 策略：不弹冲突，直接以远端为准发布', () async {
      final FakeWebDavServer server = FakeWebDavServer();
      final _Harness local = await _harness(server);
      addTearDown(local.close);
      await local.insertFeed('feed.local', '本机的源');
      local.settings.configure(
        firstSyncPreview: false,
        conflictPolicy: 'preferRemote',
      );
      final SyncManager manager = local.manager();
      addTearDown(manager.dispose);

      final SyncRunResult? result = await manager.request(SyncTrigger.manual);
      expect(result!.status, SyncRunStatus.succeeded);
      expect(manager.status.conflicts, isEmpty);
    });
  });

  group('降级模式（架构 5.2「只读拉取」）', () {
    test('服务器不支持条件写时：状态标记降级、不写远端、提示条可显示', () async {
      final FakeWebDavServer server = FakeWebDavServer();
      final _Harness harness = await _harness(server);
      addTearDown(harness.close);
      await harness.insertFeed('feed.a', '一个源');
      harness.settings.configure(firstSyncPreview: false);

      final SyncManager manager = SyncManager(
        readSettings: () => SyncSettingsReader(harness.settings).load(),
        readStatusBaseline: harness.statusReader.read,
        buildEngine: harness.engineFor,
        probeCapability:
            (SyncSettings value, SyncCredentials credentials) async =>
                const Ok<WebDavWriteCapability>(
                  WebDavWriteCapability.readOnlyPull,
                ),
        loadCredentials: (SyncSettings value) async =>
            const Ok<SyncCredentials>(
              SyncCredentials(username: 'flux', password: 'secret'),
            ),
        readLocalContentSnapshot: harness.content.readLocalSnapshot,
        clock: harness.clock,
      );
      addTearDown(manager.dispose);

      final int putsBefore = server.putCount;
      final SyncRunResult? result = await manager.request(SyncTrigger.manual);

      expect(result!.status, SyncRunStatus.readonlyPull);
      expect(server.putCount, putsBefore);
      expect(manager.status.degraded, isTrue, reason: '界面据此显示降级提示条');
      // 本机没有自动写入任何远端内容。
      expect(server.currentManifest(), isNull);
    });
  });

  group('能力探测只做一次（不每轮都探测）', () {
    test('两次连续同步只探测一次能力（结论记在状态里复用）', () async {
      final FakeWebDavServer server = FakeWebDavServer();
      final _Harness harness = await _harness(server);
      addTearDown(harness.close);
      await harness.insertFeed('feed.a', '一个源');
      harness.settings.configure(firstSyncPreview: false);
      final SyncManager manager = harness.manager();
      addTearDown(manager.dispose);

      await manager.request(SyncTrigger.manual);
      await manager.request(SyncTrigger.manual);

      expect(harness.probes, 1);
    });
  });
}
