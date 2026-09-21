// RSS 去向刷新接线测试（T016）。
//
// 验证三件事，都是「界面如实反映数据」而不是「按钮存在」：
//   1) 顶部「刷新」按钮点了会真的走一遍抓取（用 MockClient 计数），并把结果文案
//      显示出来；
//   2) 未读计数来自数据库的真实统计（不是写死的 0），刷新后跟着变大；
//   3) 离线时按钮给出「未发起刷新」的提示，而不是「刷新完成」。
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:flux/core/core.dart';
import 'package:flux/features/feeds/presentation/reading_refresh_placeholder.dart';
import 'package:flux/infrastructure/local/database.dart';
import 'package:flux/infrastructure/local/feed_catalog_store.dart';
import 'package:flux/infrastructure/network/feed_fetcher.dart';

import '../../app/test_harness.dart';

/// 网络状况替身：由测试指定「离线」与「计费」两个状态。
///
/// 为什么这两个测试必须注入替身而不是用 DesktopNetworkConditions：真实实现在
/// 「无网络」判定里会调用 dart:io 的 NetworkInterface.list，而 widget 测试运行在
/// 受控的假时钟环境里，那类真实 I/O 的完成时机不受 pump 控制，会让「刷新完成」
/// 永远等不到（表现为按钮一直停在「正在刷新…」）——那是测试环境的问题，不是产品
/// 行为的问题。真实实现自己的边界由
/// test/infrastructure/platform/network_conditions_test.dart 覆盖。
final class _FakeNetwork implements NetworkConditionPort {
  const _FakeNetwork({this.offline = false});

  final bool offline;

  @override
  // 计费网络守卫由 refresh_scheduler_test 的用例覆盖（那里能直接断言「一个字节都
  // 不发」）；本文件只关心界面接线，因此 isMetered 固定为「不拦」。
  Future<bool> isMetered() async => false;

  @override
  Future<bool> isOffline() async => offline;
}

const String _rss = '''<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0"><channel>
  <title>测试源</title>
  <link>https://a.example.com/</link>
  <item>
    <title>第一篇</title>
    <link>https://a.example.com/1</link>
    <guid isPermaLink="false">g-1</guid>
    <pubDate>Sun, 20 Sep 2026 22:15:00 GMT</pubDate>
    <description>摘要一</description>
  </item>
  <item>
    <title>第二篇</title>
    <link>https://a.example.com/2</link>
    <guid isPermaLink="false">g-2</guid>
    <pubDate>Sun, 20 Sep 2026 23:15:00 GMT</pubDate>
    <description>摘要二</description>
  </item>
</channel></rss>''';

http.Response _xml(String body) => http.Response.bytes(
  utf8.encode(body),
  200,
  headers: <String, String>{'content-type': 'application/xml; charset=utf-8'},
);

void main() {
  late TestBootstrap bootstrap;
  late AppDatabase db;
  late DriftFeedCatalogStore catalog;

  setUp(() async {
    bootstrap = TestBootstrap();
    db = bootstrap.database;
    await db.customSelect('SELECT 1').get();
    catalog = DriftFeedCatalogStore(db);
  });

  tearDown(() async => bootstrap.dispose());

  Future<void> seedFeed() async {
    await catalog.createFeed(
      const FeedInsert(
        syncId: 'feed.a',
        normalizedUrl: 'https://a.example.com/feed.xml',
        name: '测试源',
      ),
    );
  }

  Future<void> pump(
    WidgetTester tester, {
    required FeedFetcher fetcher,
    NetworkConditionPort network = const _FakeNetwork(),
  }) async {
    await tester.pumpWidget(
      wrapFluxApp(
        // 包一层 Scaffold：生产里本页渲染在 AppShell 的 Scaffold 之内，刷新结果的
        // 提示条（SnackBar）需要那个祖先才能显示。测试也照做，否则断言的是
        // 「页面没挂 Scaffold」而不是「刷新没有结果」。
        child: const Scaffold(body: ReadingRefreshPlaceholder()),
        overrides: bootstrap.overrides(
          feedFetcher: fetcher,
          networkConditions: network,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 点「刷新」，让**真实事件循环**跑一段，再回到伪时间线完成布局。
  ///
  /// 两个坑，都在这里一次说明：
  ///   1) pumpAndSettle 只推进测试的伪时间线（定时器与帧），而抓取层的响应流来自
  ///      http 客户端的真实异步管道（以及 drift 的真实微任务）。实测表现是刷新永远
  ///      停在「正在刷新…」，与「订阅管理页预览永远不出现」是同一类假失败；
  ///   2) 用 [FluxLoadingIndicator] 的消失当完成信号也不行：它一挂上就持续动画，
  ///      pumpAndSettle 会直接超时。因此这里先 runAsync 让真实 I/O 完成，再用
  ///      pumpAndSettle 收敛界面。
  Future<void> tapRefresh(WidgetTester tester) async {
    await tester.tap(find.text('刷新'));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 60)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('刷新按钮走真实抓取，未读计数来自数据库并在刷新后变大', (WidgetTester tester) async {
    await seedFeed();
    int requests = 0;
    await pump(
      tester,
      fetcher: HttpFeedFetcher(
        client: MockClient((http.Request request) async {
          requests++;
          return _xml(_rss);
        }),
      ),
    );

    expect(find.textContaining('当前未读 0 篇'), findsOneWidget);

    await tapRefresh(tester);

    expect(requests, 1, reason: '按钮必须真的发起抓取');
    expect(find.textContaining('新增 2 篇'), findsOneWidget);
    // 未读计数跟着真实数据变化（不是写死的 0）。
    expect(find.textContaining('当前未读 2 篇'), findsOneWidget);
  });

  testWidgets('离线时按钮说明「未发起刷新」而不是「刷新完成」', (WidgetTester tester) async {
    await seedFeed();
    int requests = 0;
    await pump(
      tester,
      fetcher: HttpFeedFetcher(
        client: MockClient((http.Request request) async {
          requests++;
          return _xml(_rss);
        }),
      ),
      network: const _FakeNetwork(offline: true),
    );

    await tapRefresh(tester);

    expect(requests, 0, reason: '守卫必须在上网之前拦下');
    expect(find.textContaining('当前无网络'), findsOneWidget);
    expect(find.textContaining('刷新完成'), findsNothing);
    // 没有新文章，未读计数保持 0（不伪造内容）。
    expect(find.textContaining('当前未读 0 篇'), findsOneWidget);
  });

  testWidgets('页面明确说明列表属 T017，不画假的文章列表', (WidgetTester tester) async {
    await seedFeed();
    await pump(
      tester,
      fetcher: HttpFeedFetcher(
        client: MockClient((http.Request request) async => _xml(_rss)),
      ),
    );

    expect(find.textContaining('属 T017'), findsOneWidget);
  });
}
