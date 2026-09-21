// T033：正文单图分析的界面结局翻译（ArticleVisionAnalyzer）。
//
// 这一层存在的意义是「页面里不该有 if 判断链」，因此断言的对象就是那张翻译表：
//   - 成功 → Text（带降采样与数据去向）；
//   - 没有视觉模型 / 开关关闭 → Skipped（**不是失败**，文案与处理都不同）；
//   - 需要首次发送告知 → NeedsConsent（未发出任何字节）；
//   - 图拿不到 → Skipped（imageUnavailable）。
library;

import 'package:flutter_test/flutter_test.dart';

import 'dart:typed_data';

import 'package:flux/core/core.dart';
import 'package:flux/features/ai/application/ai_task_budget.dart';
import 'package:flux/features/ai/application/ai_task_runner.dart';
import 'package:flux/features/ai/application/tool_ports.dart';
import 'package:flux/features/ai/application/vision_ports.dart';
import 'package:flux/infrastructure/network/vision_adapters.dart';
import 'package:flux/features/ai/application/visual_router.dart';
import 'package:flux/features/ai/domain/ai_model.dart';
import 'package:flux/features/ai/domain/ai_protocol.dart';
import 'package:flux/features/ai/domain/model_capability.dart';
import 'package:flux/features/ai/domain/vision_consent.dart';
import 'package:flux/features/ai/domain/vision_routing.dart';
import 'package:flux/features/articles/application/article_vision_analysis.dart';

import '../ai/ai_runner_support.dart';
import '../ai/vision_test_support.dart';

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
        const ScriptSuccess(deltas: <String>['一', '只', '猫']),
      ],
    });
    loader = FakeVisionImageLoader();
    settings = FakeVisionSettings();
    consent = InMemoryVisionConsent();
  });

  AiModel visionModel() => const AiModel(
    alias: 'vision',
    protocol: AiProtocol.openAiChatCompletions,
    baseUrl: 'https://vision.example.com',
    modelId: 'vision-model',
    capability: ModelCapability(vision: true),
  );

  ArticleVisionAnalyzer analyzer({
    List<AiModel>? models,
    Future<Result<void>> Function(bool enabled)? writer,
  }) => ArticleVisionAnalyzer(
    analyzeImage: AnalyzeImageUseCase(
      VisualRouter(
        runner: AiTaskRunner(
          credentials: const AlwaysCredentialStore(),
          factory: factory,
          diagnostics: sink,
          budget: const AiTaskBudget(),
          clock: clock,
        ),
        loader: loader,
        loadEnabledModels: () async =>
            Ok<List<AiModel>>(models ?? <AiModel>[visionModel()]),
        settings: settings,
        consent: consent,
        clock: clock,
        diagnostics: sink,
      ),
    ),
    settingsWriter: writer,
  );

  test('首次分析返回 NeedsConsent（未确认时不发请求）', () async {
    final ArticleVisionInsight insight = await analyzer().analyze(
      imageUrl: 'https://cdn.example.com/a.png',
      imageRef: 'img-1',
    );
    expect(insight, isA<ArticleVisionInsightNeedsConsent>());
    expect(
      (insight as ArticleVisionInsightNeedsConsent).endpoint,
      'https://vision.example.com',
    );
    expect(factory.totalIssued, 0);
  });

  test('带确认后成文，并带数据去向', () async {
    final ArticleVisionInsight insight = await analyzer().analyze(
      imageUrl: 'https://cdn.example.com/a.png',
      imageRef: 'img-1',
      confirmation: VisionSendConfirmation(acknowledgedAtUtc: clock.now()),
    );
    expect(insight, isA<ArticleVisionInsightText>());
    final ArticleVisionInsightText text = insight as ArticleVisionInsightText;
    expect(text.text, '一只猫');
    expect(text.endpoint, 'https://vision.example.com');
    expect(text.downsampled, isFalse);
  });

  test('没有视觉模型时给 Skipped（不是 Failed），且不发请求', () async {
    final ArticleVisionInsight insight = await analyzer(
      models: <AiModel>[
        const AiModel(
          alias: 'text',
          protocol: AiProtocol.openAiChatCompletions,
          baseUrl: 'https://text.example.com',
          modelId: 'm',
        ),
      ],
    ).analyze(imageUrl: 'https://cdn.example.com/a.png', imageRef: 'img-1');
    expect(insight, isA<ArticleVisionInsightSkipped>());
    expect(
      (insight as ArticleVisionInsightSkipped).reason,
      ArticleVisionSkipReason.noVisionModel,
    );
    expect(factory.totalIssued, 0);
  });

  test('开关关闭时写回设置并重跑（用户的显式点击 = 要打开这个能力）', () async {
    settings.limits = const ImageInputLimits(enabled: false);
    final List<bool> writes = <bool>[];
    final ArticleVisionAnalyzer sut = analyzer(
      writer: (bool enabled) async {
        writes.add(enabled);
        settings.limits = ImageInputLimits(enabled: enabled);
        return okUnit();
      },
    );
    final ArticleVisionInsight insight = await sut.analyze(
      imageUrl: 'https://cdn.example.com/a.png',
      imageRef: 'img-1',
      confirmation: VisionSendConfirmation(acknowledgedAtUtc: clock.now()),
    );
    expect(writes, <bool>[true], reason: '只写一次、且是打开');
    expect(insight, isA<ArticleVisionInsightText>());
    expect(factory.totalIssued, 1);
  });

  test('开关写回失败时如实给 Skipped（不假装已打开）', () async {
    settings.limits = const ImageInputLimits(enabled: false);
    final ArticleVisionAnalyzer sut = analyzer(
      writer: (bool enabled) async =>
          Err<void>(StorageError(operation: 'writeSetting')),
    );
    final ArticleVisionInsight insight = await sut.analyze(
      imageUrl: 'https://cdn.example.com/a.png',
      imageRef: 'img-1',
    );
    expect(insight, isA<ArticleVisionInsightSkipped>());
    expect((insight as ArticleVisionInsightSkipped).detail, '开关写回失败');
    expect(factory.totalIssued, 0, reason: '没有打开就不得发送');
  });

  test('图拿不到时给 Skipped（imageUnavailable）', () async {
    loader.failFor = 'a.png';
    final ArticleVisionInsight insight = await analyzer().analyze(
      imageUrl: 'https://cdn.example.com/a.png',
      imageRef: 'img-1',
      confirmation: VisionSendConfirmation(acknowledgedAtUtc: clock.now()),
    );
    expect(insight, isA<ArticleVisionInsightSkipped>());
    expect(
      (insight as ArticleVisionInsightSkipped).reason,
      ArticleVisionSkipReason.imageUnavailable,
    );
  });

  test('空地址直接给 Skipped（不发请求）', () async {
    final ArticleVisionInsight insight = await analyzer().analyze(
      imageUrl: '   ',
      imageRef: 'img-1',
    );
    expect(insight, isA<ArticleVisionInsightSkipped>());
    expect(factory.totalIssued, 0);
  });

  test('降采样后成文时带 downsample 标记', () async {
    loader.result = VisionLoadedImage(
      bytes: Uint8List.fromList(<int>[9, 9, 9]),
      mimeType: 'image/png',
      width: 320,
      height: 240,
      downsampled: true,
    );
    final ArticleVisionInsight insight = await analyzer().analyze(
      imageUrl: 'https://cdn.example.com/a.png',
      imageRef: 'img-1',
      confirmation: VisionSendConfirmation(acknowledgedAtUtc: clock.now()),
    );
    expect((insight as ArticleVisionInsightText).downsampled, isTrue);
  });

  test('执行器侧的分析端口：接上路由后回填的是真实分析文本', () async {
    final VisualRouterToolAnalyzer toolAnalyzer = VisualRouterToolAnalyzer(
      VisualRouter(
        runner: AiTaskRunner(
          credentials: const AlwaysCredentialStore(),
          factory: factory,
          diagnostics: sink,
          budget: const AiTaskBudget(),
          clock: clock,
        ),
        loader: loader,
        loadEnabledModels: () async =>
            Ok<List<AiModel>>(<AiModel>[visionModel()]),
        settings: settings,
        consent: consent,
        clock: clock,
        diagnostics: sink,
      ),
    );
    await consent.save(
      VisionSendAcknowledgement(
        endpoint: 'https://vision.example.com',
        providerAlias: 'vision',
        acknowledgedAtUtc: clock.now(),
      ),
    );
    final Result<VisionAnalysisResult> result = await toolAnalyzer.analyze(
      imageRef: 'img-page-1',
      url: 'https://cdn.example.com/a.png',
    );
    expect(result.valueOrNull!.ok, isTrue);
    expect(result.valueOrNull!.description, '一只猫');
  });

  test('执行器侧的分析端口：待确认时不失败、返回 awaitingConsent 跳过原因', () async {
    final VisualRouterToolAnalyzer toolAnalyzer = VisualRouterToolAnalyzer(
      VisualRouter(
        runner: AiTaskRunner(
          credentials: const AlwaysCredentialStore(),
          factory: factory,
          diagnostics: sink,
          budget: const AiTaskBudget(),
          clock: clock,
        ),
        loader: loader,
        loadEnabledModels: () async =>
            Ok<List<AiModel>>(<AiModel>[visionModel()]),
        settings: settings,
        consent: consent,
        clock: clock,
        diagnostics: sink,
      ),
    );
    final Result<VisionAnalysisResult> result = await toolAnalyzer.analyze(
      imageRef: 'img-page-1',
      url: 'https://cdn.example.com/a.png',
    );
    expect(result.isOk, isTrue, reason: '待确认不是失败');
    expect(result.valueOrNull!.skippedReason, VisionSkipKind.awaitingConsent);
    expect(factory.totalIssued, 0);
  });
}
