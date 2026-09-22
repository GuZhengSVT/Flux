// T040：设置页的「每日定时总结」小节（SET-056/057、D-08）。
//
// 盯的是「默认开 + 等待配置可见 + 不发请求」这三件用户看得见的事：
//   * 默认显示开（与注册表一致），时点显示 20:00；
//   * 缺模型时显示「等待配置」并点明去配什么，且状态里没有任何运行；
//   * 确认费用告知后等待配置解除；
//   * 关闭开关写入 SET-056 且状态变成「已关闭」。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flux/core/core.dart';
import 'package:flux/features/ai/domain/ai_model.dart';
import 'package:flux/features/ai/domain/ai_protocol.dart';
import 'package:flux/features/news/presentation/news_source_settings_page.dart';
import 'package:flux/infrastructure/local/ai_model_store.dart';
import 'package:flux/infrastructure/local/device_state_repository.dart';
import 'package:flux/infrastructure/platform/credential_store.dart';

import '../../app/test_harness.dart';

void main() {
  late TestBootstrap bootstrap;

  setUp(() async {
    bootstrap = TestBootstrap();
    await bootstrap.database.customSelect('SELECT 1').get();
  });

  tearDown(() async {
    await bootstrap.dispose();
  });

  /// 这个页面有多个开关（RSS 总开关在最上，定时开关在小节里），因此不能用
  /// `find.byType(Switch).first`：那会点到 RSS 总开关，而用例却以为改的是 SET-056。
  Finder scheduleSwitch() => find.descendant(
    of: find.widgetWithText(SwitchListTile, '本设备自动定时总结'),
    matching: find.byType(Switch),
  );

  Future<void> pumpPage(WidgetTester tester) async {
    await setSurfaceSize(tester, const Size(1200, 1400));
    await tester.pumpWidget(
      wrapFluxApp(
        overrides: bootstrap.overrides(),
        child: const NewsSourceSettingsPage(),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 启用一个模型（让「缺模型」不再是等待配置的原因）。
  Future<void> enableModel({required bool withCredential}) async {
    await DriftAiModelStore(bootstrap.database).insert(
      const AiModel(
        alias: 'deepseek',
        protocol: AiProtocol.openAiChatCompletions,
        baseUrl: 'https://api.example.com',
        modelId: 'deepseek-chat',
      ),
    );
    if (withCredential) {
      await bootstrap.credentialStore.write(
        const CredentialKey(category: 'ai-provider', identifier: 'deepseek'),
        'sk-test',
      );
    }
  }

  group('默认开与默认时点（SET-056/057）', () {
    testWidgets('默认显示开启与 20:00，并给出当前时区', (WidgetTester tester) async {
      await pumpPage(tester);
      expect(find.text('每日定时总结'), findsOneWidget);
      expect(find.text('本设备自动定时总结'), findsOneWidget);
      expect(find.text('20:00'), findsOneWidget);
      expect(find.textContaining('当前时区'), findsOneWidget);

      final Switch toggle = tester.widget<Switch>(scheduleSwitch());
      expect(toggle.value, isTrue, reason: 'SET-056 默认开');
    });

    testWidgets('关掉开关写入 SET-056，状态变成「已关闭」', (WidgetTester tester) async {
      await pumpPage(tester);
      await tester.tap(scheduleSwitch());
      await tester.pumpAndSettle();

      final Result<Object?> stored = await bootstrap.settingsRepository.read(
        SettingId.set056,
      );
      expect(stored.valueOrNull, isFalse);
      expect(find.textContaining('已关闭'), findsOneWidget);
    });
  });

  group('等待配置可见且不发请求（D-08）', () {
    testWidgets('没有启用模型时显示等待配置，并点明去「AI 服务」配', (WidgetTester tester) async {
      await pumpPage(tester);
      expect(find.text('等待配置：不会发出任何请求'), findsOneWidget);
      expect(find.textContaining('没有启用的 AI 模型'), findsOneWidget);
    });

    testWidgets('有模型但没 Key 时原因可区分', (WidgetTester tester) async {
      await enableModel(withCredential: false);
      await pumpPage(tester);
      expect(find.textContaining('没有配置 API Key'), findsOneWidget);
    });

    testWidgets('模型与 Key 都就绪但未确认费用告知：显示可点确认的按钮与告知正文', (
      WidgetTester tester,
    ) async {
      await enableModel(withCredential: true);
      await pumpPage(tester);
      expect(find.textContaining('尚未确认定时任务的费用与数据发送告知'), findsOneWidget);
      // 告知正文必须说清「会联网检索与调用模型」「可能产生费用」与「退出后不后台执行」。
      expect(find.textContaining('可能产生费用'), findsWidgets);
      expect(find.textContaining('不会后台执行'), findsOneWidget);
      expect(find.text('我已了解（会按计划自动运行）'), findsOneWidget);
    });

    testWidgets('确认费用告知后写入本机状态，等待配置解除', (WidgetTester tester) async {
      await enableModel(withCredential: true);
      await pumpPage(tester);
      await tester.tap(find.text('我已了解（会按计划自动运行）'));
      await tester.pumpAndSettle();

      final Result<bool> stored = await bootstrap.deviceStateRepository
          .readBool(DeviceStateKey.newsCostNoticeAcknowledged);
      expect(stored.valueOrNull, isTrue);
      // 解除等待：等待配置的横幅消失（下一次到点时会运行）。
      expect(find.text('等待配置：不会发出任何请求'), findsNothing);
    });
  });

  group('缺搜索不阻塞（只提示）', () {
    testWidgets('没有搜索服务时提示「仍会运行，但标注未联网核验」', (WidgetTester tester) async {
      await pumpPage(tester);
      await tester.scrollUntilVisible(
        find.textContaining('未配置联网搜索'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.textContaining('未配置联网搜索'), findsOneWidget);
      // 提示是提示：等待配置的原因仍然是缺模型，而不是缺搜索。
      expect(find.textContaining('没有启用的 AI 模型'), findsOneWidget);
    });
  });
}
