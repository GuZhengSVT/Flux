// T033：VisualRouter 的行为（路由顺序、告知闸门、文本降级、取消）。
//
// 断言重点是「哪些情况下**一个字节都没发**」——用 RequestCountingFactory 的调用计数直接
// 断言请求数，而不是只看返回的状态：视觉链路最严重的缺陷是「在没有获准或没有视觉模型的
// 情况下把图片发了出去」，而那种缺陷在只断言状态码的测试里是看不见的。
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:flux/core/core.dart';
import 'package:flux/features/ai/application/ai_task_budget.dart';
import 'package:flux/features/ai/application/ai_task_runner.dart';
import 'package:flux/features/ai/application/vision_ports.dart';
import 'package:flux/features/ai/application/visual_router.dart';
import 'package:flux/features/ai/domain/ai_model.dart';
import 'package:flux/features/ai/domain/ai_message.dart';
import 'package:flux/features/ai/domain/ai_protocol.dart';
import 'package:flux/features/ai/domain/model_capability.dart';
import 'package:flux/features/ai/domain/vision_consent.dart';
import 'package:flux/features/ai/domain/vision_routing.dart';

import 'ai_runner_support.dart';
import 'vision_test_support.dart';

AiModel visionModel(String alias) => AiModel(
  alias: alias,
  protocol: AiProtocol.anthropicMessages,
  baseUrl: 'https://$alias.example.com',
  modelId: '$alias-model',
  capability: const ModelCapability(vision: true),
);

void main() {
  late FakeClock clock;
  late RecordingSink sink;
  late ScriptedAiFactory factory;
  late FakeVisionImageLoader loader;
  late FakeVisionSettings settings;
  late InMemoryVisionConsent consent;

  setUp(() {
    clock = FakeClock();
    sink = RecordingSink();
    factory = ScriptedAiFactory(<String, List<AiAttemptScript>>{
      'vision': <AiAttemptScript>[
        const ScriptSuccess(deltas: <String>['图', '中', '有', '一', '只', '猫']),
      ],
    });
    loader = FakeVisionImageLoader();
    settings = FakeVisionSettings();
    consent = InMemoryVisionConsent();
  });

  VisualRouter router({List<AiModel> Function()? models}) => VisualRouter(
    runner: AiTaskRunner(
      credentials: const AlwaysCredentialStore(),
      factory: factory,
      diagnostics: sink,
      budget: const AiTaskBudget(),
      clock: clock,
    ),
    loader: loader,
    loadEnabledModels: () async =>
        Ok<List<AiModel>>(models?.call() ?? <AiModel>[visionModel('vision')]),
    settings: settings,
    consent: consent,
    clock: clock,
    diagnostics: sink,
  );

  VisionImageRequest request({String ref = 'img-1'}) =>
      VisionImageRequest(ref: ref, url: 'https://cdn.example.com/$ref.png');

  group('告知闸门（架构第 8 节）', () {
    test('首次分析前未确认时**一个字节都不发**，并返回待确认端点', () async {
      final VisionAnalysisOutcome outcome = await router().analyze(
        taskId: 't1',
        images: <VisionImageRequest>[request()],
      );
      expect(outcome.needsConsent, isTrue);
      expect(outcome.awaitingConsentEndpoint, 'https://vision.example.com');
      expect(factory.totalIssued, 0, reason: '未确认发送时不得发出任何请求');
      expect(loader.loads, 0, reason: '未确认时连本机加载都不必做');
    });

    test('带确认凭据时发送并记录到本机（绑定端点）', () async {
      final VisionAnalysisOutcome outcome = await router().analyze(
        taskId: 't2',
        images: <VisionImageRequest>[request()],
        confirmation: VisionSendConfirmation(acknowledgedAtUtc: clock.now()),
      );
      expect(outcome.hasResults, isTrue);
      expect(factory.totalIssued, 1);
      final Result<VisionSendAcknowledgement?> record = await consent.find(
        'https://vision.example.com',
      );
      expect(record.valueOrNull, isNotNull);
      expect(
        record.valueOrNull!.endpoint,
        'https://vision.example.com',
        reason: '记录必须绑定端点',
      );
      expect(
        VisionSendAcknowledgement.storageKeyFor('https://vision.example.com'),
        contains('device.visionSendAck.'),
        reason: '确认记录是本机状态（device. 命名空间），不随普通设置同步',
      );
    });

    test('已有本机确认记录时不再询问（直接发送）', () async {
      await consent.save(
        VisionSendAcknowledgement(
          endpoint: 'https://vision.example.com',
          providerAlias: 'vision',
          acknowledgedAtUtc: clock.now(),
        ),
      );
      final VisionAnalysisOutcome outcome = await router().analyze(
        taskId: 't3',
        images: <VisionImageRequest>[request()],
      );
      expect(outcome.needsConsent, isFalse);
      expect(factory.totalIssued, 1);
    });
  });

  group('文本降级（架构 4.3：均无视觉能力时跳过并标注）', () {
    test('没有视觉模型时不报错、不发请求、明确标注跳过', () async {
      final VisionAnalysisOutcome outcome = await router(
        models: () => <AiModel>[
          const AiModel(
            alias: 'text',
            protocol: AiProtocol.openAiChatCompletions,
            baseUrl: 'https://text.example.com',
            modelId: 'text-model',
          ),
        ],
      ).analyze(taskId: 't4', images: <VisionImageRequest>[request()]);
      expect(outcome.skippedNoVisionModel, isTrue);
      expect(outcome.error, isNull, reason: '跳过不是失败');
      expect(factory.totalIssued, 0);
      expect(loader.loads, 0);
    });

    test('SET-065 开关关闭时不发请求（跳过而不是失败）', () async {
      settings.limits = const ImageInputLimits(enabled: false);
      final VisionAnalysisOutcome outcome = await router().analyze(
        taskId: 't5',
        images: <VisionImageRequest>[request()],
      );
      expect(outcome.error, isNull);
      expect(outcome.analyses, isEmpty);
      expect(factory.totalIssued, 0);
    });

    test('读模型列表失败时如实报错，不伪装成「没有视觉模型」', () async {
      final VisualRouter broken = VisualRouter(
        runner: AiTaskRunner(
          credentials: const AlwaysCredentialStore(),
          factory: factory,
          diagnostics: sink,
          budget: const AiTaskBudget(),
          clock: clock,
        ),
        loader: loader,
        loadEnabledModels: () async =>
            Err<List<AiModel>>(StorageError(operation: 'loadModels')),
        settings: settings,
        consent: consent,
        clock: clock,
        diagnostics: sink,
      );
      final VisionAnalysisOutcome outcome = await broken.analyze(
        taskId: 't6',
        images: <VisionImageRequest>[request()],
      );
      expect(outcome.error, isA<StorageError>());
      expect(outcome.skippedNoVisionModel, isFalse);
    });
  });

  group('图像输入与降采样', () {
    test('超过单图上限的图被降采样，结论带 downsample 标记', () async {
      loader.result = VisionLoadedImage(
        bytes: Uint8List.fromList(<int>[1, 2, 3]),
        mimeType: 'image/png',
        width: 800,
        height: 600,
        downsampled: true,
      );
      final VisionAnalysisOutcome outcome = await router().analyze(
        taskId: 't7',
        images: <VisionImageRequest>[request()],
        confirmation: VisionSendConfirmation(acknowledgedAtUtc: clock.now()),
      );
      expect(outcome.analyses.first.downsampled, isTrue);
      expect(outcome.analyses.first.note, contains('降采样'));
      expect(
        factory.requests.single.messages.single.images.single.downsampled,
        isTrue,
        reason: '降采样标记必须跟着图片进请求，而不是只留在界面文案里',
      );
    });

    test('一张图加载失败不影响其余（失败不阻塞）', () async {
      loader.failFor = 'img-bad';
      final VisionAnalysisOutcome outcome = await router().analyze(
        taskId: 't8',
        images: <VisionImageRequest>[
          request(ref: 'img-bad'),
          request(ref: 'img-1'),
        ],
        confirmation: VisionSendConfirmation(acknowledgedAtUtc: clock.now()),
      );
      expect(outcome.analyses, hasLength(2));
      expect(outcome.analyses.first.error, isNotNull);
      expect(outcome.analyses.first.note, '图片未能加载');
      expect(outcome.analyses.last.ok, isTrue);
    });

    test('图片字节进请求、地址不进（模型看到的是内容）', () async {
      final VisionAnalysisOutcome outcome = await router().analyze(
        taskId: 't9',
        images: <VisionImageRequest>[request()],
        confirmation: VisionSendConfirmation(acknowledgedAtUtc: clock.now()),
      );
      expect(outcome.hasResults, isTrue);
      final AiRequest sent = factory.requests.single;
      expect(sent.messages.single.images, hasLength(1));
      expect(
        sent.messages.single.content.contains('cdn.example.com'),
        isFalse,
        reason: '图片地址是加载用的本机事实，不该进 prompt',
      );
    });

    test('超过 6 张时只发送前 6 张，结论置 truncatedByCount', () async {
      final VisionAnalysisOutcome outcome = await router().analyze(
        taskId: 't10',
        images: <VisionImageRequest>[
          for (int i = 1; i <= 8; i++) request(ref: 'img-$i'),
        ],
        confirmation: VisionSendConfirmation(acknowledgedAtUtc: clock.now()),
      );
      expect(outcome.truncatedByCount, isTrue);
      expect(outcome.analyses, hasLength(6));
      expect(factory.totalIssued, 6);
    });
  });

  group('取消', () {
    test('已取消的信号：不再发起任何图片请求，且不报错', () async {
      final AiCancellation cancellation = AiCancellation();
      cancellation.cancel(reason: 'userCancelled');
      final VisionAnalysisOutcome outcome = await router().analyze(
        taskId: 't11',
        images: <VisionImageRequest>[request()],
        confirmation: VisionSendConfirmation(acknowledgedAtUtc: clock.now()),
        cancellation: cancellation,
      );
      expect(factory.totalIssued, 0);
      expect(outcome.analyses, isEmpty);
    });
  });

  group('诊断', () {
    test('结构化诊断不含图片地址、不含 prompt（架构第 8 节）', () async {
      await router().analyze(
        taskId: 't12',
        images: <VisionImageRequest>[request()],
        confirmation: VisionSendConfirmation(acknowledgedAtUtc: clock.now()),
      );
      final String all = sink.messages.join('\n');
      expect(all, contains('视觉分析完成'));
      expect(all, isNot(contains('cdn.example.com')));
      expect(all, isNot(contains('test-key')));
    });
  });
}
