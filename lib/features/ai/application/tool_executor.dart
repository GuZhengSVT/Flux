// 受控工具执行器（T032；架构 4.3「工具层至少支持 search(query)、fetchPage(url)、
// inspectImage(imageRef)。客户端校验参数、网络目的地和预算后执行，模型没有任意 HTTP、
// 文件或 shell 权限」、SET-061/062）。
//
// 本文件是整条工具链的**唯一执行点**。它做四件事，顺序固定：
//
//   1) **预算闸门**（先扣次数）：SET-062 的次数上限必须在**任何**工作之前检查。
//      放到后面会让一次被拒绝的调用也消耗额度，也会让「先抓一个页面再发现超预算」
//      变成一次真实出网（钱已经花了）。
//   2) **工具名白名单**：不在封闭三项里的名字直接拒绝。readFile / shell / 任意 HTTP
//      不是「还没实现」，而是**不存在这条路径**（枚举里没有）。
//   3) **参数校验**（checkSearchArguments 等纯函数）：含 fetchPage 的地址守卫。
//      地址检查发生在**发出请求之前**，因此指向 169.254.169.254 这类注入目标连一次
//      连接都不会建立。
//   4) **执行**：search 走已启用服务、fetchPage 走 T024 的完整安全链、inspectImage
//      只认客户端注册过的材料引用。
//
// 三条刻意的边界：
//
//   - **不抛异常**：所有失败都变成 [ToolResult]，因为执行结果要回填进消息序列交给模型
//     （模型必须看到「这次调用被拒绝了，原因是……」，否则它会一直重试同一件事）。
//     异常只可能来自编程错误。
//   - **fail-closed**：任何一步判断不清（没有启用的搜索服务、图片引用不存在、参数形态
//     可疑）都拒绝，不放行。放行一次不该放行的出网，代价远大于让模型看到一次拒绝。
//   - **单材料预算**（SET-061）：fetchPage 的正文按任务预算截断并**标注截断**。不标注
//     截断会让模型把半篇文章当全文总结，而用户看到的结论没有任何线索指向材料不全。
library;

import 'package:flux/core/core.dart';

import '../domain/search_provider.dart';
import '../domain/search_result.dart';
import '../domain/search_service.dart';
import '../domain/ai_message.dart';
import '../domain/tool_arguments.dart';
import '../domain/tool_call.dart';
import 'search_manager.dart';
import 'tool_ports.dart';

/// 工具执行器的配置（一次任务一份）。
final class ToolExecutorConfig {
  /// 构造配置。
  const ToolExecutorConfig({
    this.singleMaterialCharBudget = 8000,
    this.searchCount = kSearchDefaultMaxResults,
    this.enableImageInspection = true,
  });

  /// 单材料文本预算（SET-061：默认 8000 字符）。
  final int singleMaterialCharBudget;

  /// search 未指定 count 时使用的条数（来自当前启用服务的 SET-040 配置）。
  final int searchCount;

  /// 是否暴露 inspectImage（视觉能力与 SET-065 的开关属 T033；这里只做开关位）。
  final bool enableImageInspection;

  /// 从设置读取预算；读取失败或结构不符时回退注册表默认值。
  ///
  /// 与 AiTaskBudget.fromSettingsReader 同一口径：预算是**总资源边界**，读不到就按
  /// 文档默认值继续，比「因为一次设置读失败就不做任何事」更符合用户预期。
  static Future<ToolExecutorConfig> fromSettingsReader(
    ToolBudgetSettings? reader, {
    int? searchCount,
  }) async {
    if (reader == null) {
      return ToolExecutorConfig(
        searchCount: searchCount ?? kSearchDefaultMaxResults,
      );
    }
    final Object? raw = await reader.readSingleMaterialBudget();
    final int budget = raw is int && raw > 0 ? raw : 8000;
    return ToolExecutorConfig(
      singleMaterialCharBudget: budget,
      searchCount: searchCount ?? kSearchDefaultMaxResults,
    );
  }
}

/// 受控工具执行器。
final class ToolExecutor {
  /// 构造执行器。
  ToolExecutor({
    required this.budget,
    required this.config,
    required this.searchManager,
    required this.pageFetcher,
    required this.imageInspector,
    required this.diagnostics,
    this.visionAnalyzer,
    this.materials,
  });

  /// 工具调用次数预算（SET-062）。
  final ToolCallBudget budget;

  /// 配置（单材料预算、检索条数、是否暴露看图）。
  final ToolExecutorConfig config;

  /// 搜索服务管理（取当前启用服务）。
  final SearchManager searchManager;

  /// 受控网页抓取。
  final ControlledPageFetcher pageFetcher;

  /// 受控图片查看（元数据：MIME/尺寸/体积，已过 T021 的校验）。
  final ToolImageInspector imageInspector;

  /// 诊断记录。
  final DiagnosticSink diagnostics;

  /// 受控视觉分析（T033）；为空时 inspectImage 仍然可用，但只给元数据（不分析）。
  ///
  /// 允许为空而不是必需：T032 的「只给元数据」是一条仍然成立的降级路径（例如只配了
  /// 纯文本模型的场景），而把分析器做成必需参数会让执行器无法在 T033 的链路未接线时
  /// 独立使用。为空时的回填文本明确写「本次没有分析」。
  final ToolVisionAnalyzer? visionAnalyzer;

  /// 图片材料集合；为空时新建一个（同一次任务内共享同一个注册表）。
  final ImageMaterialRegistry? materials;

  /// 本次任务的材料集合（inspectImage 的唯一合法输入来源）。
  ///
  /// 用 getter 而不是 late final 字段：执行器需要是**可被构造为 const-free 值语义**
  /// 的对象（同一次任务内共享同一个注册表），而 late final 与「注入可选注册表」两者
  /// 合起来会让「谁持有这份材料」变得含糊。getter 每次都返回同一个实例（_materials）。
  ImageMaterialRegistry get materialRegistry =>
      materials ?? (_fallbackMaterials ??= ImageMaterialRegistry());

  ImageMaterialRegistry? _fallbackMaterials;

  /// 发给模型的工具声明（与参数校验逐条对应）。
  List<AiToolDeclaration> get declarations => toolDeclarations(
    maxResults: config.searchCount,
    includeImageInspection: config.enableImageInspection,
  );

  /// 执行一次工具调用。
  ///
  /// **永不抛异常**：所有失败都以 [ToolResult] 返回（模型需要看到拒绝原因）。
  Future<ToolResult> execute(ToolCall call) async {
    final ToolName? name = call.name;
    if (name == null) {
      // 未知工具名：诊断里只记名字与调用 id（不含参数值）。
      diagnostics.warning('工具调用被拒绝（未知工具） ${call.describe()}', tag: 'ai.tool');
      return ToolResult.rejected(
        callId: call.id,
        reason: ToolRejectionReason.unknownTool,
        detail: '未知工具 ${call.rawName}',
      );
    }
    // 预算闸门在**任何**工作之前（见文件头说明）。未知工具已经在上面返回了——它不
    // 消耗额度，因为它根本没有做任何工作的可能。
    if (!budget.consume()) {
      diagnostics.warning(
        '工具调用被拒绝（次数用尽） ${call.describe()} used=${budget.used}',
        tag: 'ai.tool',
      );
      return ToolResult.rejected(
        callId: call.id,
        reason: ToolRejectionReason.budgetExhausted,
        detail: '工具调用次数已达上限 ${budget.limit}',
      );
    }

    return switch (name) {
      ToolName.search => _search(call),
      ToolName.fetchPage => _fetchPage(call),
      ToolName.inspectImage => _inspectImage(call),
    };
  }

  /// 批量执行（同一批内的顺序保持；任一条失败不影响其余）。
  Future<List<ToolResult>> executeAll(List<ToolCall> calls) async {
    final List<ToolResult> results = <ToolResult>[];
    for (final ToolCall call in calls) {
      results.add(await execute(call));
    }
    return results;
  }

  Future<ToolResult> _search(ToolCall call) async {
    final ToolArgumentCheck<SearchToolArgs> checked = checkSearchArguments(
      call.args,
      defaultCount: config.searchCount,
    );
    if (checked is ToolArgumentsRejected<SearchToolArgs>) {
      return _reject(call, checked);
    }
    final SearchToolArgs args =
        (checked as ToolArgumentsOk<SearchToolArgs>).value;

    // 当前启用服务（按排序取第一个）。**没有启用服务就拒绝**，而不是静默返回空结果：
    // 空结果会让模型以为「搜了但没有」，而实际是「我们没配搜索服务」。
    final Result<List<SearchService>> enabled = await searchManager
        .loadEnabledServices();
    if (enabled.isErr) {
      return ToolResult.failed(callId: call.id, error: enabled.errorOrNull!);
    }
    final List<SearchService> services = enabled.valueOrNull!;
    if (services.isEmpty) {
      return ToolResult.rejected(
        callId: call.id,
        reason: ToolRejectionReason.unavailable,
        detail: '没有启用的搜索服务',
      );
    }
    final SearchService service = services.first;

    // 凭据：协议要求而拿不到时拒绝（与 T031 的测试路径同一条规则）。
    String apiKey = '';
    final Result<String> key = await searchManager.credentials.read(
      service.credentialIdentifier,
    );
    if (service.protocol.requiresCredential) {
      if (key.isErr) {
        return ToolResult.rejected(
          callId: call.id,
          reason: ToolRejectionReason.unavailable,
          detail: '搜索服务缺少凭据',
        );
      }
      apiKey = key.valueOrNull!;
    } else {
      apiKey = key.isOk ? key.valueOrNull! : '';
    }

    final Result<SearchProvider> provider =
        searchManager.factory?.create(
          protocol: service.protocol,
          baseUrl: service.baseUrl,
          apiKey: apiKey,
          timeout: Duration(seconds: service.timeoutSeconds),
          maxResults: service.maxResults,
          allowPrivateEndpoint: service.allowPrivateEndpoint,
        ) ??
        Err<SearchProvider>(
          ValidationError(field: 'SET-042', reason: '搜索适配器工厂未接线'),
        );
    if (provider.isErr) {
      return ToolResult.failed(callId: call.id, error: provider.errorOrNull!);
    }

    final Result<SearchResponse> response = await provider.valueOrNull!.search(
      SearchRequest(text: args.query, count: args.count),
    );
    if (response.isErr) {
      return ToolResult.failed(callId: call.id, error: response.errorOrNull!);
    }
    final SearchResponse value = response.unwrap();
    // 结果地址不直接注册为图片（它是一篇文章，不是一张图）；这里不做任何注册，
    // 因为搜索结果里没有「图片引用」这一项——图片材料只来自网页正文（见 _fetchPage）。
    _logSuccess(call, 'search', results: value.results.length);
    return ToolResult.ok(
      callId: call.id,
      payload: SearchToolPayload(
        query: value.query,
        provider: value.provider,
        results: value.results,
        answer: value.answer,
      ),
    );
  }

  Future<ToolResult> _fetchPage(ToolCall call) async {
    final ToolArgumentCheck<FetchPageToolArgs> checked =
        checkFetchPageArguments(call.args);
    if (checked is ToolArgumentsRejected<FetchPageToolArgs>) {
      // 被守卫拒绝时按**安全事件**记 warning：地址指向内网不是「模型手滑」，
      // 而是值得被看见的一次尝试。
      final ToolArgumentsRejected<FetchPageToolArgs> rejected = checked;
      if (rejected.reason == ToolRejectionReason.forbiddenDestination) {
        diagnostics.warning(
          '工具试图访问被禁止的目的地 ${call.describe()} '
          'detail=${rejected.detail}',
          tag: 'ai.tool.security',
        );
      }
      return _reject(call, checked);
    }
    final FetchPageToolArgs args =
        (checked as ToolArgumentsOk<FetchPageToolArgs>).value;

    // 抓取本身仍会再走一遍完整安全链（地址守卫 + DNS 解析后复检 + 逐跳校验）：
    // 参数层只做了字面量判断，挡不住 evil.example.com → 127.0.0.1。
    final Result<FetchedPage> fetched = await pageFetcher.fetch(args.uri);
    if (fetched.isErr) {
      final AppError error = fetched.errorOrNull!;
      if (error is NetworkError && !error.isRetryable) {
        diagnostics.warning(
          '工具抓取被拒绝 ${call.describe()} kind=${error.kind}',
          tag: 'ai.tool.security',
        );
      }
      return ToolResult.failed(callId: call.id, error: error);
    }
    final FetchedPage page = fetched.unwrap();

    // 单材料预算（SET-061）：截断并**标注**。
    final String full = page.text;
    final int budgetChars = config.singleMaterialCharBudget;
    final bool truncated = full.length > budgetChars;
    final String text = truncated ? full.substring(0, budgetChars) : full;

    // 正文里的图片注册为材料（引用由客户端生成，模型只会看到引用）。
    final List<String> refs = <String>[];
    for (final String imageUrl in page.imageUrls) {
      refs.add(registerImageCandidate(url: imageUrl, origin: 'page'));
    }

    _logSuccess(
      call,
      'fetchPage',
      chars: text.length,
      note: truncated ? 'truncated' : null,
    );
    return ToolResult.ok(
      callId: call.id,
      payload: FetchPageToolPayload(
        url: page.finalUri,
        title: page.title,
        text: text,
        originalLength: full.length,
        truncated: truncated,
        imageRefs: refs,
        outcome: page.outcome,
      ),
    );
  }

  Future<ToolResult> _inspectImage(ToolCall call) async {
    if (!config.enableImageInspection) {
      return ToolResult.rejected(
        callId: call.id,
        reason: ToolRejectionReason.unavailable,
        detail: '图像查看未启用',
      );
    }
    final ToolArgumentCheck<InspectImageToolArgs> checked =
        checkInspectImageArguments(call.args);
    if (checked is ToolArgumentsRejected<InspectImageToolArgs>) {
      return _reject(call, checked);
    }
    final InspectImageToolArgs args =
        (checked as ToolArgumentsOk<InspectImageToolArgs>).value;

    // **唯一**合法输入来源：客户端注册过的材料。没有这一步，inspectImage 就是一个
    // 「按名字下载任意图片」的接口（架构 4.3 明确不允许）。
    final ImageMaterial? material = materialRegistry.lookup(args.imageRef);
    if (material == null) {
      diagnostics.warning(
        '工具请求了未知的图片引用 ${call.describe()}',
        tag: 'ai.tool.security',
      );
      return ToolResult.rejected(
        callId: call.id,
        reason: ToolRejectionReason.unknownImageReference,
        detail: '引用不在本次材料集合里',
      );
    }

    // 元数据仍然先取：它是「这张图确实存在且合法」的判据，视觉分析只是它的附加产出。
    final Result<InspectedImage> inspected = await imageInspector.inspect(
      material.sourceUrl,
    );
    if (inspected.isErr) {
      return ToolResult.failed(callId: call.id, error: inspected.errorOrNull!);
    }
    final InspectedImage image = inspected.unwrap();

    // ---- T033：接上视觉路由做真正的分析 ----
    //
    // 没有分析器（未接线）或没有视觉模型时**不失败**：给一条明确的「本次没有分析」说明
    // （见 InspectImageToolPayload.toModelContent），文本链路照常继续。这条路径是架构 4.3
    // 「均无视觉能力时跳过图像分析并明确标签」在执行器里的落点。
    final ToolVisionAnalyzer? analyzer = visionAnalyzer;
    VisionAnalysisResult? analysis;
    if (analyzer != null) {
      final Result<VisionAnalysisResult> result = await analyzer.analyze(
        imageRef: args.imageRef,
        url: material.sourceUrl,
      );
      if (result.isErr) {
        // 分析链路本身失败（不是「没有视觉模型」）：如实回填失败原因，让模型据此停止重试。
        return ToolResult.failed(callId: call.id, error: result.errorOrNull!);
      }
      analysis = result.unwrap();
      if (analysis.error != null) {
        return ToolResult.failed(callId: call.id, error: analysis.error!);
      }
    }
    _logSuccess(
      call,
      'inspectImage',
      note: analysis == null
          ? image.mimeType
          : analysis.ok
          ? '${image.mimeType} analyzed'
          : '${image.mimeType} skipped=${analysis.skippedReason?.name ?? 'unknown'}',
    );
    return ToolResult.ok(
      callId: call.id,
      payload: InspectImageToolPayload(
        imageRef: args.imageRef,
        mimeType: image.mimeType,
        width: image.width,
        height: image.height,
        byteLength: image.byteLength,
        description: analysis?.description,
        skippedReason: analysis == null
            ? 'visionNotWired'
            : analysis.skippedReason?.name,
        downsampled: analysis?.downsampled ?? false,
        endpoint: analysis?.endpoint,
      ),
    );
  }

  /// 注册一张候选图片为材料（客户端生成引用；同一地址复用同一引用）。
  ///
  /// 公开给调用方（T033 的视觉路由会直接注册候选图），也供测试构造材料。
  String registerImageCandidate({
    required String url,
    required String origin,
  }) => materialRegistry.register(sourceUrl: url, origin: origin);

  ToolResult _reject(ToolCall call, ToolArgumentsRejected<Object?> rejected) {
    // 诊断只记工具名、调用 id 与原因类别；**不记参数值**（可能含查询词或地址）。
    diagnostics.warning(
      '工具参数被拒绝 ${call.describe()} reason=${rejected.reason.name}',
      tag: 'ai.tool',
    );
    return ToolResult.rejected(
      callId: call.id,
      reason: rejected.reason,
      detail: rejected.detail,
    );
  }

  /// 成功后的结构性诊断（不含任何材料内容）。
  void _logSuccess(
    ToolCall call,
    String tool, {
    int? results,
    int? chars,
    String? note,
  }) {
    final String extra = <String>[
      if (results != null) 'results=$results',
      if (chars != null) 'chars=$chars',
      if (note != null) 'note=$note',
    ].join(' ');
    diagnostics.info(
      '工具调用成功 ${call.describe()} tool=$tool'
      '${extra.isEmpty ? '' : ' $extra'}',
      tag: 'ai.tool',
    );
  }
}
