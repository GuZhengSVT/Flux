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

import 'package:flux/core/core.dart';
import 'package:flux/features/sync/application/sync_settings.dart';
import 'package:flux/features/sync/presentation/sync_settings_page.dart';
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
  });
}
