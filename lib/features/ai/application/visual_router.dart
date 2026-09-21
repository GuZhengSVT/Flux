// 视觉分析链路（T033；架构 4.3「视觉用于理解新闻图片和静态网页中的图片。优先指定视觉
// 模型，其次有视觉能力的主模型；均无视觉能力时跳过图像分析并明确标签，文本搜索/抓取/
// 总结仍正常工作」、SET-034、SET-065、架构第 8 节「首次数据发送告知」）。
//
// 这一层把五件事按固定顺序串起来，每一步都有明确的「不做什么」：
//
//   1) **路由**（[selectVisionRoute]）：专用视觉模型 → 有视觉能力的主模型 → 跳过。
//      跳过**不是失败**：返回一个带原因的结论，调用方据此在结果里明确标注，文本链路照常。
//   2) **限额与规划**（[planImageInputs]）：SET-065 的开关 / 6 张 / 4 MiB。超单图上限的
//      标降采样，超数量的标跳过并置 truncatedByCount——两者都不静默。
//   3) **加载与降采样**：走端口（实现复用 T021 的受控管线）。一张图失败**不影响其余**，
//      失败的图变成一条「拿不到」的说明；把整批作废会让一张坏图吃掉整篇新闻的图片分析。
//   4) **告知闸门**：每个端点第一次发图之前必须有本机确认记录，否则返回带
//      awaitingConsentEndpoint 的结论——**一个字节都不发**，也**不**产生任何费用。
//   5) **真实调用**：每张图一次 [AiTaskRunner] 任务（预算、五次无响应、跨模型故障转移都在
//      那里，本层不重写第二套规则）。一张图一次请求而不是一批一次：这样一张图的失败只影响
//      它自己，而「批量请求」在协议上通常要么全成功要么整条失败。
//
// 本层刻意**不**做的事：不截图动态网页（架构 4.3 明确禁止），不把图片地址交给服务商去取
// （统一以字节发送），不在没有视觉模型时伪造一段「看起来像分析结果」的文本——那会让 T033
// 的缺口无法被察觉（T032 的占位文案那条教训）。
library;

import 'package:flux/core/core.dart';

import '../domain/ai_message.dart';
import '../domain/ai_model.dart';
import '../domain/vision_consent.dart';
import '../domain/vision_routing.dart';
import 'ai_task_budget.dart';
import 'ai_task_runner.dart';
import 'tool_ports.dart';
import 'vision_ports.dart';

/// 单张图片视觉分析的界面用例（T033）。
///
/// 为什么需要它而不是让页面直接调 VisualRouter：页面要处理的是**三种不同的界面结局**——
/// 「拿到了描述」「需要先确认发送」「跳过（没有视觉模型/开关关闭）」，而 VisualRouter 的产出
/// 里这三件事混在 route/analyses/awaitingConsent 里。把翻译集中在这里，页面里就没有
/// 「if skippedReason == ...」这类判断，测试也可以直接断言三种结局。
final class VisionAnalysisView {
  /// 构造结果。
  const VisionAnalysisView({
    this.description,
    this.skipKind,
    this.consentEndpoint,
    this.error,
    this.downsampled = false,
    this.endpoint,
  });

  /// 分析描述；成功时有值。
  final String? description;

  /// 跳过原因；跳过时有值。
  final VisionSkipKind? skipKind;

  /// 需要用户确认发送的端点；非空时界面要弹首次发送告知，且**没有发出任何字节**。
  final String? consentEndpoint;

  /// 失败原因。
  final AppError? error;

  /// 是否降采样后送出。
  final bool downsampled;

  /// 实际接收端点。
  final String? endpoint;

  /// 是否有可用描述。
  bool get hasDescription => description != null && description!.isNotEmpty;

  /// 是否需要用户先确认发送。
  bool get needsConsent => consentEndpoint != null;
}

/// 单图分析用例。
final class AnalyzeImageUseCase {
  /// 构造用例。
  const AnalyzeImageUseCase(this.router);

  /// 视觉链路。
  final VisualRouter router;

  /// 分析一张图；[confirmation] 非空表示用户刚刚在对话框上确认过。
  Future<VisionAnalysisView> call({
    required String taskId,
    required String imageRef,
    required String url,
    VisionSendConfirmation? confirmation,
    AiCancellation? cancellation,
  }) async {
    final VisionAnalysisOutcome outcome = await router.analyze(
      taskId: taskId,
      images: <VisionImageRequest>[VisionImageRequest(ref: imageRef, url: url)],
      confirmation: confirmation,
      cancellation: cancellation,
    );
    if (outcome.needsConsent) {
      return VisionAnalysisView(
        consentEndpoint: outcome.awaitingConsentEndpoint,
      );
    }
    if (outcome.error != null) {
      return VisionAnalysisView(error: outcome.error);
    }
    if (outcome.skippedNoVisionModel) {
      return const VisionAnalysisView(skipKind: VisionSkipKind.noVisionModel);
    }
    if (outcome.analyses.isEmpty) {
      // 开关关闭或没有候选：都是**不失败**的跳过。
      return const VisionAnalysisView(
        skipKind: VisionSkipKind.disabledBySetting,
      );
    }
    final VisionImageAnalysis first = outcome.analyses.first;
    if (first.ok) {
      return VisionAnalysisView(
        description: first.text,
        downsampled: first.downsampled,
        endpoint: _endpointOf(outcome.route),
      );
    }
    if (first.error != null) {
      return VisionAnalysisView(
        skipKind: VisionSkipKind.imageUnavailable,
        error: first.error,
      );
    }
    return const VisionAnalysisView(skipKind: VisionSkipKind.imageUnavailable);
  }

  static String? _endpointOf(VisionRoute route) => switch (route) {
    VisionRouteDedicated(:final AiModel model) => model.baseUrl,
    VisionRoutePrimary(:final AiModel model) => model.baseUrl,
    VisionRouteSkip() => null,
  };
}

/// 默认的分析指令。
///
/// 两条克制：要求「只描述确实看到的」并禁止推断人物身份——图片分析是这套系统里最容易
/// 编造事实的一环，而用户没有任何办法核对一句「图中人物正在发言」。
const String kDefaultVisionAnalysisPrompt =
    '请用两到四句话描述这张新闻图片的内容。只描述你确实看到的东西，不要推测图片之外的'
    '背景，也不要推断任何人的身份或立场。如果图中有文字，原样写出其中关键的部分。';

/// 一次待分析的图片（引用 + 地址 + 可选替代文字）。
final class VisionImageRequest {
  /// 构造请求。
  const VisionImageRequest({required this.ref, required this.url, this.alt});

  /// 客户端材料引用（模型看到的短标识）。
  final String ref;

  /// 图片地址（**只用于本机加载**，不进请求）。
  final String url;

  /// 替代文字（可为空；只用于本机说明与日志）。
  final String? alt;
}

/// 一张图的分析结论。
final class VisionImageAnalysis {
  /// 构造结论。
  const VisionImageAnalysis({
    required this.ref,
    required this.route,
    this.text,
    this.error,
    this.downsampled = false,
    this.usedCache = false,
    this.note,
  });

  /// 图片引用（客户端的材料引用）。
  final String ref;

  /// 本次实际使用的路由（逐张记录：一次分析里可能因为故障转移换过模型）。
  final VisionRoute? route;

  /// 分析文本；失败或被跳过时为 null。
  final String? text;

  /// 失败原因（图拿不到 / 协议失败）。
  final AppError? error;

  /// 这张图是否被降采样后送出。
  final bool downsampled;

  /// 是否命中结果缓存（没有发出请求）。
  final bool usedCache;

  /// 结构性备注（例如「图片拿不到」「降采样后送出」）。
  final String? note;

  /// 是否拿到了可用的分析文本。
  bool get ok => text != null && text!.isNotEmpty;
}

/// 一次视觉分析的产出。
final class VisionAnalysisOutcome {
  /// 构造产出。
  const VisionAnalysisOutcome({
    required this.route,
    required this.analyses,
    this.skipped,
    this.error,
    this.awaitingConsentEndpoint,
    this.truncatedByCount = false,
    this.plan,
  });

  /// 路由结论（整体跳过时也是这一项）。
  final VisionRoute route;

  /// 每张图的结论（顺序与候选一致）。
  final List<VisionImageAnalysis> analyses;

  /// 没有任何视觉模型时的整体跳过结论；null 表示链路正常走完。
  final VisionRouteSkip? skipped;

  /// 发生在「已经决定要发」之后的链路级失败。
  final AppError? error;

  /// 需要用户先确认发送的端点；非空时**一个字节都没有发出**。
  final String? awaitingConsentEndpoint;

  /// 是否有图片因数量上限被舍弃（SET-065）。
  final bool truncatedByCount;

  /// 本次的输入规划（诊断与界面说明用）。
  final ImageInputPlan? plan;

  /// 是否有可用结论。
  bool get hasResults => analyses.any(
    (VisionImageAnalysis a) => a.text != null && a.text!.isNotEmpty,
  );

  /// 是否需要用户确认才能继续（调用方据此弹首次发送告知）。
  bool get needsConsent => awaitingConsentEndpoint != null;

  /// 是否因为「没有视觉模型」而跳过（文本链路继续，不是错误）。
  bool get skippedNoVisionModel => skipped != null;
}

/// 视觉分析链路。
final class VisualRouter {
  /// 构造链路。
  const VisualRouter({
    required this.runner,
    required this.loader,
    required this.loadEnabledModels,
    required this.clock,
    required this.diagnostics,
    this.settings,
    this.consent,
    this.budget = const AiTaskBudget(),
    this.analysisPrompt = kDefaultVisionAnalysisPrompt,
  });

  /// 有预算的任务队列（T029）：预算、五次无响应与故障转移都在它里面。
  final AiTaskRunner runner;

  /// 图片加载与降采样端口（实现复用 T021 的受控管线）。
  final VisionImageLoader loader;

  /// 读启用模型（按故障转移顺序）。
  ///
  /// 用回调而不是直接持有 ModelManager：本层只关心「给我一个按顺序排好的启用列表」，
  /// 注入之后测试也不必构造整个管理器。
  final Future<Result<List<AiModel>>> Function() loadEnabledModels;

  /// 设置读取（SET-034 / SET-065）；未接线时用注册表默认值。
  final VisionSettingsReader? settings;

  /// 发送告知的记录端口；未接线时**按需告知处理**（fail-closed）。
  final VisionConsentStore? consent;

  /// 时钟。
  final Clock clock;

  /// 诊断。
  final DiagnosticSink diagnostics;

  /// 预算（每次分析一份；deadline 由 runner 在开始时固定）。
  final AiTaskBudget budget;

  /// 分析用的指令文本。
  final String analysisPrompt;

  /// 分析一批图片。
  ///
  /// [taskId] 是本次分析的任务标识前缀（每张图各派生一个，便于在任务列表里分辨）。
  /// [confirmation] 非空表示用户刚刚在对话框上确认过向该端点发送图片；此时会把确认记录
  /// 落本机（架构第 8 节：确认记录绑定端点与能力）。
  /// [cancellation] 是本次分析的取消信号（架构 4.2「可取消」）。取消后**不再**发起新的
  /// 图片请求，并且在途请求通过子信号被中止；已经拿到的结论仍然返回——半途取消不等于
  /// 「什么都没发生」，把它丢掉会让用户看到一次「点了取消，什么都没变」的空白。
  Future<VisionAnalysisOutcome> analyze({
    required String taskId,
    required List<VisionImageRequest> images,
    VisionSendConfirmation? confirmation,
    AiCancellation? cancellation,
  }) async {
    final ImageInputLimits limits = await _readLimits();
    final Result<List<AiModel>> modelsResult = await loadEnabledModels();
    if (modelsResult.isErr) {
      // 读模型失败：如实返回错误，**不**降级成「没有视觉模型」。两者对用户的含义完全不同
      // （前者要去排查存储，后者要去配模型）。
      return VisionAnalysisOutcome(
        route: const VisionRouteSkip(reason: VisionSkipReason.noVisionModel),
        analyses: const <VisionImageAnalysis>[],
        error: modelsResult.errorOrNull,
      );
    }
    final List<AiModel> enabled = modelsResult.valueOrNull!;
    final String? dedicatedAlias = await _readDedicatedAlias();
    final VisionRoute route = selectVisionRoute(
      enabledModels: enabled,
      dedicatedAlias: dedicatedAlias,
    );

    // 没有视觉模型：跳过并明确标注（架构 4.3）。**不**报错、**不**发请求。
    if (route is VisionRouteSkip) {
      diagnostics.info(
        '视觉分析跳过（无可用视觉模型）task=$taskId reason=${route.reason.name}',
        tag: 'ai.vision',
      );
      return VisionAnalysisOutcome(
        route: route,
        skipped: route,
        analyses: const <VisionImageAnalysis>[],
      );
    }

    final ImageInputPlan plan = planImageInputs(
      candidates: <ImageCandidateInfo>[
        for (final VisionImageRequest image in images)
          ImageCandidateInfo(ref: image.ref),
      ],
      limits: limits,
    );
    final List<ImageInputDecision> accepted = plan.accepted;
    if (accepted.isEmpty) {
      // 开关关闭或没有候选：同样不是失败。
      return VisionAnalysisOutcome(
        route: route,
        analyses: const <VisionImageAnalysis>[],
        truncatedByCount: plan.truncatedByCount,
        plan: plan,
      );
    }

    final List<AiModel> candidates = _visionCandidates(route, enabled);
    final String endpoint = _endpointOf(candidates.first);

    // ---- 告知闸门：确认记录不在本机且这次也没有刚确认过 → 一个字节都不发 ----
    final bool acknowledged = await _isAcknowledged(endpoint);
    if (!acknowledged && confirmation == null) {
      diagnostics.info(
        '视觉分析等待首次发送告知 endpoint=$endpoint task=$taskId',
        tag: 'ai.vision',
      );
      return VisionAnalysisOutcome(
        route: route,
        analyses: const <VisionImageAnalysis>[],
        awaitingConsentEndpoint: endpoint,
        truncatedByCount: plan.truncatedByCount,
        plan: plan,
      );
    }
    if (!acknowledged && confirmation != null) {
      // 用户刚确认：记录落本机，绑定端点与能力（架构第 8 节）。
      await _recordConsent(
        endpoint: endpoint,
        providerAlias: candidates.first.alias,
        at: confirmation.acknowledgedAtUtc,
      );
    }

    // ---- 逐张加载 + 分析 ----
    final List<VisionImageAnalysis> analyses = <VisionImageAnalysis>[];
    int index = 0;
    for (final ImageInputDecision decision in accepted) {
      if (cancellation != null && cancellation.isCancelled) {
        break;
      }
      index++;
      final VisionImageRequest request = images.firstWhere(
        (VisionImageRequest candidate) =>
            candidate.ref == decision.candidate.ref,
      );
      final Result<VisionLoadedImage> loaded = await loader.load(
        url: request.url,
        maxBytes: limits.maxImageBytes,
      );
      if (loaded.isErr) {
        // 一张图拿不到不影响其余（与 T021「失败不阻塞文章」同一条产品规则）。
        analyses.add(
          VisionImageAnalysis(
            ref: request.ref,
            route: route,
            error: loaded.errorOrNull,
            note: '图片未能加载',
          ),
        );
        continue;
      }
      final VisionLoadedImage image = loaded.unwrap();
      final VisionImageAnalysis analysis = await _analyzeOne(
        taskId: '$taskId-i$index',
        request: request,
        image: image,
        models: candidates,
        route: route,
        cancellation: cancellation,
      );
      analyses.add(analysis);
    }
    final VisionAnalysisOutcome outcome = VisionAnalysisOutcome(
      route: route,
      analyses: List<VisionImageAnalysis>.unmodifiable(analyses),
      truncatedByCount: plan.truncatedByCount,
      plan: plan,
    );
    diagnostics.info(
      '视觉分析完成 task=$taskId images=${analyses.length} '
      'ok=${analyses.where((VisionImageAnalysis a) => a.ok).length} '
      'downsampled=${plan.downsampleCount}',
      tag: 'ai.vision',
    );
    return outcome;
  }

  /// 判断某端点是否已经有本机的发送确认。
  ///
  /// 端口未接线时按**未确认**处理（fail-closed）：少发一次图只是功能没跑起来，
  /// 而多发一次图是一次没有授权的外部数据发送。
  Future<bool> _isAcknowledged(String endpoint) async {
    final VisionConsentStore? store = consent;
    if (store == null) {
      return false;
    }
    final Result<VisionSendAcknowledgement?> found = await store.find(endpoint);
    if (found.isErr) {
      diagnostics.warning(
        '视觉发送告知读取失败，按未确认处理 kind=${found.errorOrNull!.kind}',
        tag: 'ai.vision',
      );
      return false;
    }
    return found.valueOrNull != null;
  }

  /// 记录一次发送确认（幂等）。
  Future<void> _recordConsent({
    required String endpoint,
    required String providerAlias,
    required DateTime at,
  }) async {
    final VisionConsentStore? store = consent;
    if (store == null) {
      return;
    }
    final Result<void> saved = await store.save(
      VisionSendAcknowledgement(
        endpoint: endpoint,
        providerAlias: providerAlias,
        acknowledgedAtUtc: at,
      ),
    );
    if (saved.isErr) {
      // 写失败**不阻断本次发送**（用户已经明确同意了这一次）：留下事实即可，否则用户会
      // 遇到「点了确认却什么都没发生」而找不到原因。
      diagnostics.warning(
        '视觉发送告知写入失败，本次仍按已确认处理 kind=${saved.errorOrNull!.kind}',
        tag: 'ai.vision',
      );
    }
  }

  /// 分析单张图（一次真实请求）。
  Future<VisionImageAnalysis> _analyzeOne({
    required String taskId,
    required VisionImageRequest request,
    required VisionLoadedImage image,
    required List<AiModel> models,
    required VisionRoute route,
    AiCancellation? cancellation,
  }) async {
    final AiRequest aiRequest = AiRequest(
      cancellation: cancellation,
      modelId: models.first.modelId,
      messages: <AiMessage>[
        AiMessage.user(
          analysisPrompt,
          images: <AiImagePart>[
            AiImagePart(
              bytes: image.bytes,
              mimeType: image.mimeType,
              width: image.width,
              height: image.height,
              downsampled: image.downsampled,
              sourceRef: request.ref,
            ),
          ],
        ),
      ],
      // 分析文本很短：给一个明确的上限，避免模型「写一篇论文」把费用放大。
      maxTokens: 512,
    );
    final AiTaskOutcome outcome = await runner.run(
      taskId: taskId,
      request: aiRequest,
      models: models,
    );
    final bool ok =
        (outcome.status == TaskStatus.succeeded ||
            outcome.status == TaskStatus.partial) &&
        outcome.hasResult;
    return VisionImageAnalysis(
      ref: request.ref,
      route: route,
      text: ok ? outcome.text : null,
      error: ok ? null : outcome.error,
      downsampled: image.downsampled,
      note: image.downsampled ? '降采样后送出' : null,
    );
  }

  /// 本次尝试的模型顺序：路由选中的排第一，其余有视觉能力的按原顺序跟随。
  ///
  /// 为什么把其余视觉模型也带上：故障转移是架构 4.5 的既有规则（同一任务连续五次无响应
  /// 才换下一个模型），而「只有一个候选」会让一次端点抖动直接变成任务失败。候选**只含**
  /// 声明了视觉能力的模型——把图发给一个纯文本模型是协议层面的错误，不是一次重试。
  List<AiModel> _visionCandidates(VisionRoute route, List<AiModel> enabled) {
    final AiModel first = switch (route) {
      VisionRouteDedicated(:final AiModel model) => model,
      VisionRoutePrimary(:final AiModel model) => model,
      VisionRouteSkip() => throw StateError('跳过结论不应进入候选构造'),
    };
    return <AiModel>[
      first,
      for (final AiModel model in enabled)
        if (model.capability.vision && model.alias != first.alias) model,
    ];
  }

  /// 一个模型的发送端点（用户看到的「图像将发送至 <端点>」用的就是它）。
  static String _endpointOf(AiModel model) => model.baseUrl.trim();

  /// 读 SET-065 的图像限额。
  Future<ImageInputLimits> _readLimits() async {
    final VisionSettingsReader? reader = settings;
    if (reader == null) {
      return const ImageInputLimits();
    }
    final Object? raw = await reader.readImageLimits();
    return ImageInputLimits.fromSetting(raw);
  }

  /// 读 SET-034 的专用视觉模型别名。
  Future<String?> _readDedicatedAlias() async {
    final VisionSettingsReader? reader = settings;
    if (reader == null) {
      return null;
    }
    final Object? raw = await reader.readDedicatedVisionModel();
    if (raw is! String) {
      return null;
    }
    final String trimmed = raw.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
