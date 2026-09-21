// T028：预设目录与验证矩阵状态（**数据完整性**，不测「看起来对」）。
//
// 三条断言，每条都对应一个「不写用例就一定会漂移」的事实：
//   1) 每条预设字段齐全、URL 合法、标识唯一；
//   2) 状态与协议适配器**自洽**：fixture/实测的预设其协议必须有适配器；
//      而且只有 DeepSeek 是实测——「不伪称支持」在这里是可执行的，不是靠自觉；
//   3) OpenAI 的 Base URL 必须带 /v1（否则适配器拼出 /chat/completions 会 404）——
//      这是「预设里的地址不是厂商官网列的主机」这一差异的唯一防线。
import 'package:flutter_test/flutter_test.dart';

import 'package:flux/features/ai/domain/ai_protocol.dart';
import 'package:flux/features/ai/domain/provider_preset.dart';

void main() {
  group('PresetCatalog 数据完整性', () {
    test('每个预设的必需字段齐全且标识唯一', () {
      expect(PresetCatalog.all, isNotEmpty);
      final Set<String> ids = <String>{};
      for (final ProviderPreset preset in PresetCatalog.all) {
        expect(preset.id.trim(), isNotEmpty, reason: '标识不能为空');
        expect(ids.add(preset.id), isTrue, reason: '标识必须唯一（落库用它识别预设）');
        expect(preset.displayName.trim(), isNotEmpty);
        expect(preset.note.trim(), isNotEmpty, reason: '每个预设都要写明口径或待确认点');
      }
    });

    test('Base URL 都是合法的 http(s) 地址且有主机', () {
      for (final ProviderPreset preset in PresetCatalog.all) {
        final Uri? uri = Uri.tryParse(preset.baseUrl);
        expect(uri, isNotNull, reason: '${preset.id} 的 Base URL 无法解析');
        expect(
          uri!.scheme,
          anyOf('http', 'https'),
          reason: '${preset.id} 只允许 http/https',
        );
        expect(uri.host, isNotEmpty, reason: '${preset.id} 缺少主机名');
      }
    });

    test('endpoint 由 Base URL 与协议路径拼成（与适配器同口径）', () {
      for (final ProviderPreset preset in PresetCatalog.all) {
        expect(
          preset.endpoint.toString(),
          endsWith('/${preset.protocol.path}'),
          reason: '${preset.id} 的最终端点必须落在协议路径上',
        );
        expect(
          preset.endpoint.toString(),
          isNot(contains('//${preset.protocol.path}')),
          reason: '去尾斜杠后追加，不应出现双斜杠',
        );
      }
    });
  });

  group('验证状态与真实证据一致（不伪称支持）', () {
    test('只有 DeepSeek 是实测；其余都不是 liveVerified', () {
      final List<ProviderPreset> live = PresetCatalog.all
          .where(
            (ProviderPreset p) =>
                p.status == PresetVerificationStatus.liveVerified,
          )
          .toList();
      expect(live.map((ProviderPreset p) => p.id).toList(), <String>[
        'deepseek',
      ], reason: '本轮唯一实测的是 DeepSeek（见 R026）；不得把没跑过的预设标成实测');
      expect(PresetCatalog.hasLiveVerified, isTrue);
    });

    test('fixture 通过的预设其协议必须有适配器', () {
      for (final ProviderPreset preset in PresetCatalog.all) {
        if (preset.status == PresetVerificationStatus.fixtureVerified) {
          expect(
            preset.protocol.hasAdapter,
            isTrue,
            reason: '${preset.id} 标了 fixture 通过，但它的协议还没有适配器',
          );
        }
      }
    });

    test('OpenAI 双协议的 Base URL 带 /v1（否则拼出缺段路径）', () {
      final ProviderPreset cc = PresetCatalog.byId('openai.chat_completions')!;
      final ProviderPreset responses = PresetCatalog.byId('openai.responses')!;
      expect(
        cc.endpoint.toString(),
        'https://api.openai.com/v1/chat/completions',
      );
      expect(
        responses.endpoint.toString(),
        'https://api.openai.com/v1/responses',
      );
    });

    test('Anthropic 预设用 x-api-key 认证方式、协议是 Messages', () {
      final ProviderPreset anthropic = PresetCatalog.byId(
        'anthropic.messages',
      )!;
      expect(anthropic.protocol, AiProtocol.anthropicMessages);
      expect(anthropic.authScheme, PresetAuthScheme.anthropicApiKey);
      expect(
        anthropic.endpoint.toString(),
        'https://api.anthropic.com/v1/messages',
      );
    });

    test('MiMo 与 OpenCode Zen 明确标注待验证', () {
      for (final String id in <String>['mimo', 'opencode.zen']) {
        final ProviderPreset preset = PresetCatalog.byId(id)!;
        expect(
          preset.status,
          PresetVerificationStatus.unverified,
          reason: '$id 本轮未做真实调用，必须如实标待验证',
        );
        expect(preset.isSupported, isFalse, reason: '$id 未实测，不得标成已支持');
        expect(preset.note, contains('待真实验证'), reason: '$id 的注释必须写明端点待验证');
      }
    });

    test('Qwen / MiMo / OpenCode Zen 共用 CC 协议但状态不被协议继承', () {
      for (final String id in <String>['qwen', 'mimo', 'opencode.zen']) {
        final ProviderPreset preset = PresetCatalog.byId(id)!;
        expect(preset.protocol, AiProtocol.openAiChatCompletions);
        expect(
          preset.status,
          PresetVerificationStatus.unverified,
          reason: '共用协议不等于共用验证状态：端点必须逐个验证',
        );
      }
    });
  });

  group('目录查询', () {
    test('byId 命中已知标识，未知或空标识返回 null', () {
      expect(PresetCatalog.byId('deepseek')?.displayName, 'DeepSeek');
      expect(PresetCatalog.byId('nope'), isNull);
      expect(PresetCatalog.byId(null), isNull);
    });

    test('forProtocol 只返回该协议的预设', () {
      final List<ProviderPreset> cc = PresetCatalog.forProtocol(
        AiProtocol.openAiChatCompletions,
      );
      expect(cc, isNotEmpty);
      expect(
        cc.every(
          (ProviderPreset p) => p.protocol == AiProtocol.openAiChatCompletions,
        ),
        isTrue,
      );
      final List<ProviderPreset> anthropic = PresetCatalog.forProtocol(
        AiProtocol.anthropicMessages,
      );
      expect(anthropic.map((ProviderPreset p) => p.id), <String>[
        'anthropic.messages',
      ]);
    });

    test('预设里没有任何凭据（Key 不进目录）', () {
      for (final ProviderPreset preset in PresetCatalog.all) {
        expect(
          preset.note,
          isNot(matches(RegExp(r'sk-[A-Za-z0-9]{8,}'))),
          reason: '注释里出现了形如 Key 的串',
        );
        expect(preset.baseUrl, isNot(contains('key=')));
      }
    });
  });
}
