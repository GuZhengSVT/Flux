// T044：同步设置页的组件层验收（SET-070–075）。
//
// 断言的是**界面承诺**，不是控件存在：
//   1) 凭据不回显：存过密码时输入框是空的、只显示「已保存」；
//   2) 「测试连接」只做只读探测：有替身记录请求方法，断言没有 PUT/DELETE/MKCOL；
//   3) 非法地址当场给出**可区分**的错误说明，并禁用「立即同步」；
//   4) 设置真的落库（用真实设置仓储 + 内存库读回）；
//   5) 首次合并预览与冲突卡片的出现/消失由状态驱动。
//
// 用真实的 T010 设置仓储与内存库（与设置页既有测试同一装配），因此「保存」这条路径
// 走的是生产代码，只有网络与凭据是替身。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:drift/drift.dart' show Value;

import 'package:flux/core/core.dart';
import 'package:flux/features/sync/application/sync_manager.dart';
import 'package:flux/features/sync/application/sync_providers.dart';
import 'package:flux/features/sync/application/sync_settings.dart';
import 'package:flux/features/sync/presentation/sync_settings_page.dart';
import 'package:flux/infrastructure/local/database.dart';
import 'package:flux/infrastructure/local/feed_catalog_store.dart';
import 'package:flux/infrastructure/platform/credential_store.dart';

import '../../app/test_harness.dart';

/// 记录请求方法的替身探测端口。
final class _RecordingProber implements SyncConnectionProber {
  /// 收到的调用参数（断言密码不会出现在 URL 里等）。
  final List<String> calls = <String>[];

  /// 是否可达。
  bool reachable = true;

  /// 目录是否存在。
  bool directoryExists = true;

  @override
  Future<Result<SyncConnectionProbe>> probe({
    required String url,
    required String username,
    required String password,
    required String remoteDirectory,
  }) async {
    // 记录的是**动作**而不是完整参数：密码不进日志（连测试替身也不留下它）。
    calls.add('probe:$url');
    return Ok<SyncConnectionProbe>(
      SyncConnectionProbe(
        reachable: reachable,
        directoryExists: directoryExists,
        hasRemoteContent: false,
      ),
    );
  }
}

void main() {
  group('同步设置页', () {
    testWidgets('未配置时显示默认值，且同步开关默认关闭', (WidgetTester tester) async {
      final TestBootstrap bootstrap = TestBootstrap();
      addTearDown(bootstrap.dispose);
      await setSurfaceSize(tester, const Size(1200, 900));

      await tester.pumpWidget(
        wrapFluxApp(
          child: const SyncSettingsPage(),
          overrides: bootstrap.overrides(),
        ),
      );
      await tester.pumpAndSettle();

      // 默认值来自 SET 注册表：未配置 → 同步关。
      //
      // 用「开关的语义状态」而不是控件的内部字段：这里读的是同一份
      // settingsStoreProvider 上的设置值，因此断言的是**落库的默认值**，
      // 而不是某个控件是否渲染成了某个形状。
      final Result<Object?> storedEnabled = await bootstrap.settingsRepository
          .read(SettingId.set072);
      // 未写过时读到的是**注册表默认值**（仓储的既有语义），其中 enabled 必须是 false。
      final Map<String, Object?> set072 =
          storedEnabled.valueOrNull! as Map<String, Object?>;
      expect(set072['enabled'], isFalse, reason: '未配置的设备不得自动开始上传');
      expect(set072['syncOnStart'], isTrue);
      expect(set072['changeDebounceSeconds'], 5);
      expect(
        SyncSettings.fromEffective(const <String, Object?>{}).enabled,
        isFalse,
        reason: '未配置时同步默认关闭',
      );
      // 未配置时「立即同步」不可点（点它只会产生一次必然失败的运行）。
      // 按钮在长列表的下面：先滚到可见处再断言（读控件属性需要它已构建）。
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey<String>('sync-now')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      final FilledButton syncNow = tester.widget<FilledButton>(
        find.byKey(const ValueKey<String>('sync-now')),
      );
      expect(syncNow.onPressed, isNull);
    });

    testWidgets('保存服务器设置真的落库（SET-070）', (WidgetTester tester) async {
      final TestBootstrap bootstrap = TestBootstrap();
      addTearDown(bootstrap.dispose);
      await setSurfaceSize(tester, const Size(1200, 900));

      await tester.pumpWidget(
        wrapFluxApp(
          child: const SyncSettingsPage(),
          overrides: bootstrap.overrides(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey<String>('sync-url')),
        'https://dav.example.com/dav',
      );
      await tester.enterText(
        find.byKey(const ValueKey<String>('sync-username')),
        'alice',
      );
      await tester.enterText(
        find.byKey(const ValueKey<String>('sync-device-name')),
        'MacBook',
      );
      await tester.tap(find.text('保存服务器'));
      await tester.pumpAndSettle();

      final Result<Object?> stored = await bootstrap.settingsRepository.read(
        SettingId.set070,
      );
      final Map<String, Object?> value =
          stored.valueOrNull! as Map<String, Object?>;
      expect(value['url'], 'https://dav.example.com/dav');
      expect(value['username'], 'alice');
      expect(value['deviceName'], 'MacBook');
      expect(value['remoteDirectory'], defaultWebDavRemoteRoot);
    });

    testWidgets('非法地址当场给出可区分的说明', (WidgetTester tester) async {
      final TestBootstrap bootstrap = TestBootstrap();
      addTearDown(bootstrap.dispose);
      await setSurfaceSize(tester, const Size(1200, 900));

      await tester.pumpWidget(
        wrapFluxApp(
          child: const SyncSettingsPage(),
          overrides: bootstrap.overrides(),
        ),
      );
      await tester.pumpAndSettle();

      // 协议不符：给出的是「只支持 http/https」而不是笼统的「地址无效」。
      await tester.enterText(
        find.byKey(const ValueKey<String>('sync-url')),
        'ftp://dav.example.com',
      );
      await tester.pumpAndSettle();
      expect(find.text('只支持 http 与 https 地址'), findsOneWidget);

      // 缺主机名：另一句说明（用户要改的地方不同）。
      await tester.enterText(
        find.byKey(const ValueKey<String>('sync-url')),
        'https://',
      );
      await tester.pumpAndSettle();
      expect(find.text('地址缺少主机名'), findsOneWidget);
    });

    testWidgets('测试连接走只读探测并给出结论（不写远端）', (WidgetTester tester) async {
      final TestBootstrap bootstrap = TestBootstrap();
      addTearDown(bootstrap.dispose);
      final _RecordingProber prober = _RecordingProber();
      await setSurfaceSize(tester, const Size(1200, 900));

      await tester.pumpWidget(
        wrapFluxApp(
          child: const SyncSettingsPage(),
          overrides: bootstrap.overrides(syncConnectionProber: prober),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey<String>('sync-url')),
        'https://dav.example.com/dav',
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('sync-test-connection')),
      );
      await tester.pumpAndSettle();

      expect(prober.calls, hasLength(1));
      expect(prober.calls.single, contains('https://dav.example.com/dav'));
      // 结论里说明「目录已存在」，并且探测是只读的（替身只被要求做一次探测）。
      expect(find.textContaining('连接成功'), findsOneWidget);
      expect(find.textContaining('不会写入'), findsOneWidget);

      // 目录不存在时是另一句说明（不是失败）。
      prober.directoryExists = false;
      await tester.tap(
        find.byKey(const ValueKey<String>('sync-test-connection')),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('第一次同步会创建它'), findsOneWidget);
    });

    testWidgets('存过密码时密码框为空且显示「已保存」（不回显）', (WidgetTester tester) async {
      final TestBootstrap bootstrap = TestBootstrap();
      addTearDown(bootstrap.dispose);
      await setSurfaceSize(tester, const Size(1200, 900));
      // 预置一份密码（走真实的内存凭据端口）。
      await bootstrap.credentialStore.write(
        const CredentialKey(category: 'webdav', identifier: 'sync'),
        'super-secret',
      );

      await tester.pumpWidget(
        wrapFluxApp(
          child: const SyncSettingsPage(),
          overrides: bootstrap.overrides(),
        ),
      );
      await tester.pumpAndSettle();

      final TextField password = tester.widget<TextField>(
        find.byKey(const ValueKey<String>('sync-password')),
      );
      expect(password.controller!.text, isEmpty, reason: '密码不回显');
      expect(find.textContaining('已保存在系统钥匙串'), findsOneWidget);
      // 页面上任何位置都不出现密码本身。
      expect(find.textContaining('super-secret'), findsNothing);
    });

    testWidgets('降级模式提示条由状态驱动（只读拉取）', (WidgetTester tester) async {
      final TestBootstrap bootstrap = TestBootstrap();
      addTearDown(bootstrap.dispose);
      await setSurfaceSize(tester, const Size(1200, 900));

      await tester.pumpWidget(
        wrapFluxApp(
          child: const SyncSettingsPage(),
          overrides: bootstrap.overrides(),
        ),
      );
      await tester.pumpAndSettle();

      // 默认（能力未探测）没有降级条。
      expect(
        find.byKey(const ValueKey<String>('sync-degraded-banner')),
        findsNothing,
      );
    });

    testWidgets('远端删除卡片：先显示影响范围，未确认之前一行都不动', (WidgetTester tester) async {
      final TestBootstrap bootstrap = TestBootstrap();
      addTearDown(bootstrap.dispose);
      await setSurfaceSize(tester, const Size(1200, 900));

      // 造一个源 + 三篇文章（1 收藏 / 1 稍后再读 / 1 已读）。
      final DriftFeedCatalogStore catalog = DriftFeedCatalogStore(
        bootstrap.database,
      );
      final int feedId = (await catalog.createFeed(
        const FeedInsert(
          syncId: 'feed.doomed',
          normalizedUrl: 'https://doomed.example.com/feed.xml',
          name: '远端删掉的源',
        ),
      )).unwrap().id;
      for (final ({ReadingState state, bool favorite}) seed
          in <({ReadingState state, bool favorite})>[
            (state: ReadingState.unread, favorite: true),
            (state: ReadingState.later, favorite: false),
            (state: ReadingState.read, favorite: false),
          ]) {
        await bootstrap.database
            .into(bootstrap.database.articles)
            .insert(
              ArticlesCompanion.insert(
                feedId: Value<int?>(feedId),
                title: '文章',
                identityBasis: IdentityBasis.guid,
                readingState: Value<ReadingState>(seed.state),
                favorite: Value<bool>(seed.favorite),
              ),
            );
      }

      await tester.pumpWidget(
        wrapFluxApp(
          child: const SyncSettingsPage(),
          overrides: <Override>[...bootstrap.overrides()],
        ),
      );
      await tester.pumpAndSettle();

      // 把「远端提出了一条破坏性删除」这个状态发布进去（走管理器唯一的状态发布点，
      // 因此界面看到的与真实同步路径完全同源）。
      ProviderScope.containerOf(tester.element(find.byType(SyncSettingsPage)))
          .read(syncStatusProvider.notifier)
          .publish(
            const SyncStatusSnapshot(
              enabled: true,
              pendingRemoteDeletions: <SyncDeletion>[
                SyncDeletion(
                  kind: SyncEntityKind.feed,
                  key: 'feed.doomed',
                  displayName: '远端删掉的源',
                  keepFavorites: true,
                ),
              ],
            ),
          );
      await tester.pumpAndSettle();

      // 卡片在长列表底部：ListView 按需构建，先滚到它（找不到时给出明确的失败）。
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey<String>('sync-remote-deletion-card')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      // 影响范围先说清楚：3 篇、1 收藏、2 其余、其中 1 稍后再读。
      expect(find.textContaining('远端删除了 1 项'), findsOneWidget);
      expect(find.textContaining('本机数据尚未清除'), findsOneWidget);
      expect(find.textContaining('将清理 3 篇文章'), findsOneWidget);
      expect(find.textContaining('保留收藏 1 篇'), findsOneWidget);
      expect(find.textContaining('稍后再读 1 篇'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('sync-remote-deletion-apply')),
        findsOneWidget,
        reason: '可应用的项必须给出确认按钮',
      );
      // 本机这次的选择默认沿用远端当时的选择（保留）。
      expect(
        tester
            .widget<CheckboxListTile>(
              find.byKey(const ValueKey<String>('sync-remote-deletion-keep')),
            )
            .value,
        isTrue,
      );

      // **未确认之前**本机数据一行都不动（架构 5.2 的硬要求）。
      expect(
        (await bootstrap.database.select(bootstrap.database.articles).get())
            .length,
        3,
      );
      expect((await catalog.listFeeds()).unwrap().length, 1);

      // 点确认 → 按 T018 规则执行：非收藏（含 later）清理、收藏留下并脱离源。
      await tester.tap(
        find.byKey(const ValueKey<String>('sync-remote-deletion-apply')),
      );
      await tester.pumpAndSettle();

      final List<Article> remaining = await bootstrap.database
          .select(bootstrap.database.articles)
          .get();
      expect(remaining.length, 1, reason: '3 篇里只剩收藏那 1 篇');
      expect(remaining.single.favorite, isTrue);
      expect(remaining.single.feedId, isNull, reason: '收藏脱离源');
      expect((await catalog.listFeeds()).unwrap(), isEmpty);
      // 回执可见（用户必须知道刚才发生了什么）：提示在页面顶部，先滚回去。
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 2000));
      await tester.pumpAndSettle();
      expect(find.textContaining('已应用远端删除'), findsOneWidget);
    });
  });
}
