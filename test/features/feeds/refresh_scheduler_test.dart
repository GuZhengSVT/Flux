// 刷新调度测试（T016；架构 4.1、手册 6.3）。
//
// 覆盖手册点名与架构 4.1 定义的四条规则：
//   - 定时触发窗口（用 [FakeClock] 推进，不真实等待）；
//   - 触发合并（同一源重复触发不重复入队）；
//   - 并发上限（SET-028 默认 4，实测在途峰值）；
//   - 失败隔离（一源失败不影响他源）与 304 不更新；
//   - 离线 / 计费网络守卫（SET-013）在上网**之前**拦下，且不推进「上次检查」。
//
// 全部使用内存数据库与 MockClient，不联网。
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:flux/core/core.dart';
import 'package:flux/features/feeds/application/refresh_feed.dart';
import 'package:flux/features/feeds/application/refresh_scheduler.dart';
import 'package:flux/features/feeds/domain/feed_interval.dart';
import 'package:flux/infrastructure/local/database.dart';
import 'package:flux/infrastructure/local/feed_catalog_store.dart';
import 'package:flux/infrastructure/local/feed_store_adapter.dart';
import 'package:flux/infrastructure/network/feed_fetcher.dart';

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

/// 可配置的网络状况探测替身。
final class _FakeNetwork implements NetworkConditionPort {
  _FakeNetwork({this.metered = false, this.offline = false});

  bool metered;
  bool offline;

  @override
  Future<bool> isMetered() async => metered;

  @override
  Future<bool> isOffline() async => offline;
}

/// 按 URL 路由响应的抓取器。
FeedFetcher _fetcher(
  Map<String, http.Response> routes, {
  Duration? delay,
  void Function(String url)? onRequest,
}) {
  return HttpFeedFetcher(
    client: MockClient((http.Request request) async {
      onRequest?.call(request.url.toString());
      if (delay != null) {
        await Future<void>.delayed(delay);
      }
      final http.Response? response = routes[request.url.toString()];
      if (response == null) {
        return http.Response('not found', 404);
      }
      return response;
    }),
  );
}

http.Response _xml(String body, {int status = 200}) => http.Response.bytes(
  utf8.encode(body),
  status,
  headers: <String, String>{'content-type': 'application/xml; charset=utf-8'},
);

/// 一个含 N 个条目的 RSS。
String _rssWith(int count, {String prefix = 'p'}) {
  final StringBuffer buffer = StringBuffer(
    '<?xml version="1.0" encoding="UTF-8"?><rss version="2.0"><channel>'
    '<title>源</title><link>https://example.com/</link>',
  );
  for (int i = 0; i < count; i++) {
    buffer.write(
      '<item><title>文章 $prefix$i</title>'
      '<link>https://example.com/$prefix$i</link>'
      '<guid isPermaLink="false">$prefix-guid-$i</guid>'
      '<pubDate>Sun, 20 Sep 2026 22:15:00 GMT</pubDate>'
      '<description>摘要 $prefix$i</description></item>',
    );
  }
  buffer.write('</channel></rss>');
  return buffer.toString();
}

void main() {
  late AppDatabase db;
  late DriftFeedCatalogStore catalog;
  late DriftFeedArticleStore store;
  late _RecordingSink sink;
  late FakeClock clock;

  setUp(() async {
    db = AppDatabase.memory();
    await db.customSelect('SELECT 1').get();
    catalog = DriftFeedCatalogStore(db);
    store = DriftFeedArticleStore(db);
    sink = _RecordingSink();
    clock = FakeClock(start: DateTime.utc(2026, 9, 21, 12));
  });

  tearDown(() async => db.close());

  /// 建一个订阅并返回其记录。
  Future<FeedRecord> seedFeed(
    String name, {
    String host = 'a',
    bool enabled = true,
    int? intervalMinutes,
    DateTime? lastCheckedAt,
  }) async {
    final FeedRecord created = (await catalog.createFeed(
      FeedInsert(
        syncId: 'feed.$host',
        normalizedUrl: 'https://$host.example.com/feed.xml',
        name: name,
      ),
    )).unwrap();
    if (!enabled) {
      await catalog.setFeedEnabled(feedId: created.id, enabled: false);
    }
    if (intervalMinutes != null) {
      await catalog.setFeedRefreshInterval(
        feedId: created.id,
        minutes: intervalMinutes,
      );
    }
    if (lastCheckedAt != null) {
      await store.recordRefreshOutcome(
        feedId: created.id,
        outcome: FeedRefreshOutcome.updated,
        checkedAt: lastCheckedAt,
      );
    }
    return (await catalog.findFeedById(created.id)).unwrap()!;
  }

  /// 构造调度器。
  RefreshScheduler buildScheduler({
    required FeedFetcher fetcher,
    NetworkConditionPort? network,
    RefreshSchedulePolicy? policy,
  }) {
    final RefreshScheduler scheduler = RefreshScheduler(
      listFeeds: catalog.listFeeds,
      refreshFeed: RefreshFeedUseCase(
        fetcher: fetcher,
        store: store,
        diagnostics: sink,
        clock: clock,
      ),
      recordDeferral:
          ({
            required int feedId,
            required FeedRefreshOutcome outcome,
            String? errorKind,
          }) => store.recordDeferredOutcome(
            feedId: feedId,
            outcome: outcome,
            errorKind: errorKind,
          ),
      networkConditions: network ?? _FakeNetwork(),
      diagnostics: sink,
      clock: clock,
    );
    scheduler.applyPolicy(
      policy ??
          const RefreshSchedulePolicy(
            autoRefreshEnabled: true,
            intervalSetting: '60',
            refreshOnLaunch: true,
            allowMeteredNetwork: false,
          ),
    );
    return scheduler;
  }

  Future<List<Article>> articles() => db.select(db.articles).get();

  group('间隔解析（SET-020/022）', () {
    test('manual 与未知取值都表示「不自动刷新」（不猜测默认值）', () {
      expect(intervalFromSetting('manual'), isNull);
      expect(intervalFromSetting('5'), const Duration(minutes: 5));
      expect(intervalFromSetting('60'), const Duration(minutes: 60));
      // 未知取值（旧版本写下的、已下线的选项）回退到「不自动刷新」，
      // 而不是猜一个 60 分钟——那会让用户看到自己没设过的行为。
      expect(intervalFromSetting('7'), const Duration(minutes: 7));
      expect(intervalFromSetting('abc'), isNull);
      expect(intervalFromSetting('0'), isNull);
      expect(intervalFromSetting(''), isNull);
      expect(intervalFromSetting(null), isNull);
    });
  });

  group('定时触发窗口（SET-020）', () {
    test('从未检查过的源立刻到期；检查过但未满间隔的不跑', () async {
      final FeedRecord fresh = await seedFeed('新的');
      final FeedRecord checked = await seedFeed(
        '刚检查过',
        host: 'b',
        lastCheckedAt: clock.now().subtract(const Duration(minutes: 10)),
      );
      final RefreshScheduler scheduler = buildScheduler(
        fetcher: _fetcher(<String, http.Response>{
          'https://a.example.com/feed.xml': _xml(_rssWith(1)),
          'https://b.example.com/feed.xml': _xml(_rssWith(1)),
        }),
      );

      expect(scheduler.isFeedDue(feed: fresh, now: clock.now()), isTrue);
      expect(scheduler.isFeedDue(feed: checked, now: clock.now()), isFalse);

      final RefreshRunReport report = await scheduler.refreshDueScheduled();
      expect(report.attempted, 1, reason: '只跑到期的源');
      expect(report.outcomes.containsKey(fresh.id), isTrue);
      expect(report.outcomes.containsKey(checked.id), isFalse);
      expect(
        report.skipped.any(
          (FeedRefreshSkip s) => s.reason == 'intervalNotReached',
        ),
        isTrue,
      );
    });

    test('假时钟推进到间隔之后，同一个源再次到期', () async {
      await seedFeed('源');
      final RefreshScheduler scheduler = buildScheduler(
        fetcher: _fetcher(<String, http.Response>{
          'https://a.example.com/feed.xml': _xml(_rssWith(1)),
        }),
      );

      expect((await scheduler.refreshDueScheduled()).attempted, 1);
      // 调度器记住了本次会话的执行时间，因此不需要依赖库里的 lastCheckedAt。
      clock.advance(const Duration(minutes: 59));
      expect((await scheduler.refreshDueScheduled()).attempted, 0);
      clock.advance(const Duration(minutes: 1));
      expect((await scheduler.refreshDueScheduled()).attempted, 1);
    });

    test('单源间隔覆盖优先于全局；覆盖为「手动」(0) 时不参与定时刷新', () async {
      final FeedRecord inherit = await seedFeed('继承全局');
      final FeedRecord fifteen = await seedFeed(
        '十五分钟',
        host: 'b',
        intervalMinutes: 15,
      );
      final FeedRecord manual = await seedFeed(
        '仅手动',
        host: 'c',
        intervalMinutes: 0,
      );
      final RefreshScheduler scheduler = buildScheduler(
        fetcher: _fetcher(<String, http.Response>{
          'https://a.example.com/feed.xml': _xml(_rssWith(1)),
          'https://b.example.com/feed.xml': _xml(_rssWith(1)),
          'https://c.example.com/feed.xml': _xml(_rssWith(1)),
        }),
      );
      const RefreshSchedulePolicy policy = RefreshSchedulePolicy(
        autoRefreshEnabled: true,
        intervalSetting: '60',
        refreshOnLaunch: true,
        allowMeteredNetwork: false,
      );

      expect(
        scheduler.intervalFor(fifteen, policy),
        const Duration(minutes: 15),
      );
      expect(
        scheduler.intervalFor(inherit, policy),
        const Duration(minutes: 60),
      );
      expect(scheduler.intervalFor(manual, policy), isNull);

      // 手动源即使手动刷新也**不**被跳过（手动刷新是用户明确要求），
      // 但在定时触发里它没有间隔因此不算到期。
      expect(scheduler.isFeedDue(feed: manual, now: clock.now()), isFalse);
    });

    test('SET-020 全局关闭时定时触发不跑任何源（禁用源也永远不跑）', () async {
      await seedFeed('源');
      final FeedRecord disabled = await seedFeed(
        '已禁用',
        host: 'b',
        enabled: false,
      );
      final RefreshScheduler scheduler = buildScheduler(
        fetcher: _fetcher(<String, http.Response>{
          'https://a.example.com/feed.xml': _xml(_rssWith(1)),
          'https://b.example.com/feed.xml': _xml(_rssWith(1)),
        }),
        policy: const RefreshSchedulePolicy(
          autoRefreshEnabled: false,
          intervalSetting: '60',
          refreshOnLaunch: true,
          allowMeteredNetwork: false,
        ),
      );

      final RefreshRunReport report = await scheduler.refreshDueScheduled();
      expect(report.attempted, 0);
      expect(scheduler.isFeedDue(feed: disabled, now: clock.now()), isFalse);
      // 手动刷新**仍然**只跑启用的源（禁用是「不想让它联网」，不是「不自动」）。
      final RefreshRunReport manual = await scheduler.refreshAll();
      expect(manual.attempted, 1);
      expect(
        manual.skipped.any(
          (FeedRefreshSkip s) =>
              s.feedId == disabled.id && s.reason == 'disabled',
        ),
        isTrue,
      );
    });
  });

  group('触发合并', () {
    test('同一源已在队列时不重复入队（合并而非丢弃整次触发）', () async {
      await seedFeed('源');
      final Completer<void> gate = Completer<void>();
      int requests = 0;
      final RefreshScheduler scheduler = buildScheduler(
        fetcher: HttpFeedFetcher(
          client: MockClient((http.Request request) async {
            requests++;
            await gate.future;
            return _xml(_rssWith(1));
          }),
        ),
      );

      // 第一次触发占住队列（请求被 gate 卡住）。
      final Future<RefreshRunReport> first = scheduler.refreshAll();
      await Future<void>.delayed(Duration.zero);
      expect(scheduler.queuedFeedIds, isNotEmpty);

      // 第二次与第三次触发：源已在队列，应当被合并。
      final RefreshRunReport second = await scheduler.refreshAll();
      final RefreshRunReport third = await scheduler.refreshAll();
      expect(second.attempted, 0);
      expect(second.mergedTriggers, 1);
      expect(third.mergedTriggers, 1);
      expect(scheduler.mergedTriggerTotal, 2);

      gate.complete();
      final RefreshRunReport done = await first;
      expect(done.attempted, 1);
      expect(requests, 1, reason: '同一个源只应该发一次请求');
    });

    test('不同源的触发不互相合并（合并粒度是源，不是整轮）', () async {
      await seedFeed('源 A');
      await seedFeed('源 B', host: 'b');
      final Completer<void> gate = Completer<void>();
      final RefreshScheduler scheduler = buildScheduler(
        fetcher: HttpFeedFetcher(
          client: MockClient((http.Request request) async {
            await gate.future;
            return _xml(_rssWith(1));
          }),
        ),
      );

      // 只让 A 到期：手动触发 A 之后，再定时触发时 B 尚未入队。
      final Future<RefreshRunReport> first = scheduler.refreshAll();
      await Future<void>.delayed(Duration.zero);
      gate.complete();
      await first;
      // 全部源都已跑过，再触发时两个源都已在这次会话里执行过（间隔内）→ 0。
      clock.advance(const Duration(minutes: 61));
      final RefreshRunReport scheduled = await scheduler.refreshDueScheduled();
      expect(scheduled.attempted, 2);
    });
  });

  group('并发上限（SET-028）', () {
    test('在途刷新数不超过策略上限，且全部任务最终完成', () async {
      for (int i = 0; i < 6; i++) {
        await seedFeed('源 $i', host: 'h$i');
      }
      int inFlight = 0;
      int peak = 0;
      final RefreshScheduler scheduler = buildScheduler(
        fetcher: HttpFeedFetcher(
          client: MockClient((http.Request request) async {
            inFlight++;
            peak = peak < inFlight ? inFlight : peak;
            await Future<void>.delayed(const Duration(milliseconds: 5));
            inFlight--;
            return _xml(_rssWith(1));
          }),
        ),
      );

      final RefreshRunReport report = await scheduler.refreshAll();
      expect(report.attempted, 6);
      expect(report.insertedTotal, 6, reason: '限流不得丢任务');
      expect(peak, lessThanOrEqualTo(4), reason: 'SET-028 默认并发 4');
      expect(peak, greaterThan(1), reason: '确实并发执行（否则上限断言没有意义）');
    });

    test('策略可把并发降到 1（串行）', () async {
      for (int i = 0; i < 3; i++) {
        await seedFeed('源 $i', host: 'h$i');
      }
      int inFlight = 0;
      int peak = 0;
      final RefreshScheduler scheduler = buildScheduler(
        fetcher: HttpFeedFetcher(
          client: MockClient((http.Request request) async {
            inFlight++;
            peak = peak < inFlight ? inFlight : peak;
            await Future<void>.delayed(const Duration(milliseconds: 2));
            inFlight--;
            return _xml(_rssWith(1));
          }),
        ),
        policy: const RefreshSchedulePolicy(
          autoRefreshEnabled: true,
          intervalSetting: '60',
          refreshOnLaunch: true,
          allowMeteredNetwork: false,
          maxConcurrency: 1,
        ),
      );
      await scheduler.refreshAll();
      expect(peak, 1);
    });
  });

  group('失败隔离与 304', () {
    test('一个源失败不影响其它源；失败源保留旧内容', () async {
      final FeedRecord failing = await seedFeed('会失败');
      final FeedRecord healthy = await seedFeed('正常', host: 'b');
      // 先给失败源写入一批文章（作为「旧内容」）。
      final RefreshScheduler good = buildScheduler(
        fetcher: _fetcher(<String, http.Response>{
          'https://a.example.com/feed.xml': _xml(_rssWith(2)),
          'https://b.example.com/feed.xml': _xml(_rssWith(1)),
        }),
      );
      await good.refreshAll();
      final int before = (await articles()).length;

      final RefreshScheduler mixed = buildScheduler(
        fetcher: _fetcher(<String, http.Response>{
          // A 返回 503：网络失败；B 正常。
          'https://a.example.com/feed.xml': http.Response('boom', 503),
          'https://b.example.com/feed.xml': _xml(_rssWith(3, prefix: 'b')),
        }),
      );
      clock.advance(const Duration(minutes: 61));
      final RefreshRunReport report = await mixed.refreshAll();

      expect(report.attempted, 2);
      expect(
        report.outcomes[failing.id]!.outcome,
        FeedRefreshOutcome.networkFailed,
      );
      expect(
        report.outcomes[healthy.id]!.outcome,
        FeedRefreshOutcome.updated,
        reason: '一源失败不得中断他源',
      );
      expect(report.failedCount, 1);
      expect(report.insertedTotal, 3);
      // A 的旧文章仍在（失败保留旧内容）。
      final List<Article> all = await articles();
      expect(all.length, before + 3);
      expect(all.where((Article a) => a.feedId == failing.id), hasLength(2));
      expect(sink.messages, isNotEmpty, reason: '失败必须留痕');
    });

    test('304 不写任何文章，但推进检查时间（与请求语义一致）', () async {
      final FeedRecord feed = await seedFeed('源');
      final RefreshScheduler first = buildScheduler(
        fetcher: _fetcher(<String, http.Response>{
          'https://a.example.com/feed.xml': _xml(_rssWith(2)),
        }),
      );
      await first.refreshAll();
      final List<Article> before = await articles();
      expect(before, hasLength(2));

      // 第二次：带 ETag 的条件请求命中 304。
      final FeedRecord withEtag = (await catalog.findFeedById(feed.id))
          .unwrap()!;
      final RefreshScheduler second = buildScheduler(
        fetcher: HttpFeedFetcher(
          client: MockClient((http.Request request) async {
            // 断言条件请求真的带上了（否则「304」根本不是条件请求的结果）。
            expect(request.headers['If-None-Match'], isNotNull);
            return http.Response('', 304);
          }),
        ),
      );
      await store.recordRefreshOutcome(
        feedId: feed.id,
        outcome: FeedRefreshOutcome.updated,
        checkedAt: clock.now(),
        etag: '"v1"',
      );
      clock.advance(const Duration(minutes: 61));

      final RefreshRunReport report = await second.refreshAll();
      expect(
        report.outcomes[withEtag.id]!.outcome,
        FeedRefreshOutcome.notModified,
      );
      expect(report.notModifiedCount, 1);
      expect(await articles(), hasLength(2), reason: '304 不更新任何文章');
    });
  });

  group('网络守卫（SET-013 / 离线）', () {
    test('离线时一个字节都不发，如实记录 waitingNetwork 且不推进检查时间', () async {
      final FeedRecord feed = await seedFeed('源');
      final DateTime? beforeCheck = (await catalog.findFeedById(feed.id))
          .unwrap()!
          .lastCheckedAt;
      int requests = 0;
      final RefreshScheduler scheduler = buildScheduler(
        fetcher: _fetcher(<String, http.Response>{
          'https://a.example.com/feed.xml': _xml(_rssWith(1)),
        }, onRequest: (String _) => requests++),
        network: _FakeNetwork(offline: true),
      );

      final RefreshRunReport report = await scheduler.refreshAll();
      expect(requests, 0, reason: '守卫必须在上网之前拦下');
      expect(report.deferredCount, 1);
      expect(
        report.outcomes[feed.id]!.outcome,
        FeedRefreshOutcome.waitingNetwork,
      );

      final FeedRecord after = (await catalog.findFeedById(feed.id)).unwrap()!;
      expect(after.lastRefreshResult, 'waitingNetwork');
      expect(after.lastRefreshErrorKind, 'offline');
      expect(
        after.lastCheckedAt,
        beforeCheck,
        reason: '没联网就不算检查过，否则恢复网络后要白等一个间隔',
      );
      expect(await articles(), isEmpty);
    });

    test('计费网络：SET-013 关闭时拦下，开启时放行', () async {
      await seedFeed('源');
      final _FakeNetwork network = _FakeNetwork(metered: true);

      // SET-013 默认关（allowMeteredNetwork: false）。
      int requests = 0;
      final RefreshScheduler blocked = buildScheduler(
        fetcher: _fetcher(<String, http.Response>{
          'https://a.example.com/feed.xml': _xml(_rssWith(1)),
        }, onRequest: (String _) => requests++),
        network: network,
      );
      final RefreshRunReport denied = await blocked.refreshAll();
      expect(requests, 0);
      expect(denied.deferredCount, 1);
      expect(
        denied.outcomes.values.first.outcome,
        FeedRefreshOutcome.skippedMetered,
      );

      // 打开 SET-013 之后放行。
      final RefreshScheduler allowed = buildScheduler(
        fetcher: _fetcher(<String, http.Response>{
          'https://a.example.com/feed.xml': _xml(_rssWith(1)),
        }, onRequest: (String _) => requests++),
        network: network,
        policy: const RefreshSchedulePolicy(
          autoRefreshEnabled: true,
          intervalSetting: '60',
          refreshOnLaunch: true,
          allowMeteredNetwork: true,
        ),
      );
      final RefreshRunReport granted = await allowed.refreshAll();
      expect(requests, 1);
      expect(granted.insertedTotal, 1);
    });

    test('守卫命中时整轮只判定一次网络状态（不出现部分源跑部分不跑）', () async {
      await seedFeed('源 A');
      await seedFeed('源 B', host: 'b');
      int probes = 0;
      final RefreshScheduler scheduler = buildScheduler(
        fetcher: _fetcher(<String, http.Response>{
          'https://a.example.com/feed.xml': _xml(_rssWith(1)),
          'https://b.example.com/feed.xml': _xml(_rssWith(1)),
        }),
        network: _CountingNetwork(() => probes++),
      );
      await scheduler.refreshAll();
      expect(probes, 2, reason: '一次 isMetered + 一次 isOffline，整轮共享');
    });
  });

  group('释放与诊断', () {
    test('释放后不再接受新的触发（不发起任何请求）', () async {
      await seedFeed('源');
      int requests = 0;
      final RefreshScheduler scheduler = buildScheduler(
        fetcher: _fetcher(<String, http.Response>{
          'https://a.example.com/feed.xml': _xml(_rssWith(1)),
        }, onRequest: (String _) => requests++),
      );
      scheduler.dispose();
      final RefreshRunReport report = await scheduler.refreshAll();
      expect(report.attempted, 0);
      expect(requests, 0);
      expect(sink.messages.any((String m) => m.contains('已释放')), isTrue);
    });

    test('读取订阅清单失败时本轮不执行，并明确记一条错误', () async {
      int requests = 0;
      final RefreshScheduler scheduler = RefreshScheduler(
        // 直接构造「清单读不到」的返回值：用关闭数据库来模拟会污染 tearDown
        // （同一个连接被关两次），而且那不是本用例要验证的行为。
        listFeeds: () async => Err<List<FeedRecord>>(
          StorageError(operation: 'listFeeds', detail: '测试构造的失败'),
        ),
        refreshFeed: RefreshFeedUseCase(
          fetcher: _fetcher(<String, http.Response>{
            'https://a.example.com/feed.xml': _xml(_rssWith(1)),
          }, onRequest: (String _) => requests++),
          store: store,
          diagnostics: sink,
          clock: clock,
        ),
        recordDeferral: ({
          required int feedId,
          required FeedRefreshOutcome outcome,
          String? errorKind,
        }) async => const Ok<void>(null),
        diagnostics: sink,
        clock: clock,
      );
      final RefreshRunReport report = await scheduler.refreshAll();
      expect(report.attempted, 0);
      expect(requests, 0);
      expect(sink.messages.any((String m) => m.contains('读取订阅清单失败')), isTrue);
    });
  });
}

/// 计数网络状态探测次数的替身。
final class _CountingNetwork implements NetworkConditionPort {
  _CountingNetwork(this.onProbe);

  final void Function() onProbe;

  @override
  Future<bool> isMetered() async {
    onProbe();
    return false;
  }

  @override
  Future<bool> isOffline() async {
    onProbe();
    return false;
  }
}
