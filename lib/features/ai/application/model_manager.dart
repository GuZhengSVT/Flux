// 模型管理用例（T025；SET-030/031/032/033）。
//
// 职责边界：本层只做「模型记录的增删改查 + 凭据读写 + 引用检查 + 最小生成测试」，
// 不碰 HTTP 细节（那在适配器）、不碰界面（那在 presentation）。
//
// 三条容易做错、因此显式设计的边界：
//
//   1) **Key 永不出现在日志/诊断里**。所有诊断文本都是「别名 + 结果类别」，
//      从不插值 Key；读取 Key 的方法返回的 [Result] 只交给适配器。
//      这不是靠自觉：本文件里没有任何一处把 apiKey 拼进字符串（有用例断言
//      诊断日志中不含 Key 的形态）。
//
//   2) **删除引用不悬空**。删除分两段：先 [describeReferencesTo] 返回引用清单，
//      用户确认后带 force 删。没有引用时不需要打扰用户。
//
//   3) **最小生成测试先告知费用**。测试会真实计费，因此本层不自己决定「要不要测」，
//      而是把「这是一次付费调用」这一点作为**调用方必须先确认的前置**：UI 用
//      [CostConfirmation] 表达，缺它就不发请求。这样「忘了弹确认框」在类型上就不可能
//      ——而不是靠每个调用点自觉。
library;

import 'dart:async';

import 'package:flux/core/core.dart';

import '../domain/ai_credential_store.dart';
import '../domain/ai_message.dart';
import '../domain/ai_model.dart';
import '../domain/ai_model_references.dart';
import '../domain/ai_model_store.dart';
import '../domain/ai_provider.dart';

/// 一次最小生成测试的授权凭据。
///
/// 为什么用一个显式类型而不是 `bool confirmed`：布尔参数在调用点写成
/// `testModel(model, true)` 时读者无法知道 `true` 表示什么，也容易在重构时传错。
/// 一个命名类型让「调用方已经看到并确认了费用提示」这件事在签名上可见。
final class CostConfirmation {
  /// 构造已确认的凭据（只应由「用户点了确认」的代码路径创建）。
  const CostConfirmation({required this.acknowledgedAtUtc});

  /// 用户确认的时刻（UTC），写进诊断便于核对「这次调用经过了知情确认」。
  final DateTime acknowledgedAtUtc;
}

/// 一次最小生成测试的结果（供界面显示耗时与 token）。
final class ModelTestReport {
  /// 构造测试报告。
  const ModelTestReport({
    required this.elapsed,
    required this.usage,
    required this.textLength,
    required this.finishReason,
  });

  /// 端到端耗时。
  final Duration elapsed;

  /// 服务商给出的用量；协议未提供时为 null（不编造数字）。
  final AiUsage? usage;

  /// 收到的文本字符数（**不**回显文本内容：测试生成的文本无展示价值，
  /// 而把它存进日志或界面会把一次技术验证变成内容泄漏面）。
  final int textLength;

  /// 结束原因。
  final String? finishReason;
}

/// 模型管理用例。
final class ModelManager {
  /// 构造用例。
  const ModelManager({
    required this.store,
    required this.credentials,
    required this.diagnostics,
    this.settings,
    this.providerFactory,
    this.clock = const SystemClock(),
  });

  /// 模型记录存储。
  final AiModelStore store;

  /// 凭据存储（SET-031）。
  final AiCredentialStore credentials;

  /// 诊断记录。
  final DiagnosticSink diagnostics;

  /// 设置读写（用于 SET-034/035 的引用检查）；为空时跳过这两项检查并如实说明。
  final SettingsReader? settings;

  /// 适配器工厂；为空时测试功能明确报「适配器未接线」。
  final AiProviderFactory? providerFactory;

  /// 时钟（测试注入，用于耗时与确认时刻）。
  final Clock clock;

  /// 载入全部模型（已按故障转移顺序排序）。
  Future<Result<List<AiModel>>> loadModels() => store.loadAll();

  /// 载入启用中的模型（故障转移候选，SET-032/035）。
  Future<Result<List<AiModel>>> loadEnabledModels() async {
    final Result<List<AiModel>> all = await store.loadAll();
    if (all.isErr) {
      return all;
    }
    return Ok<List<AiModel>>(
      all.valueOrNull!
          .where((AiModel model) => model.enabled)
          .toList(growable: false),
    );
  }

  /// 新建或更新一条模型记录（依据 `id` 是否为空）。
  ///
  /// 校验顺序：先做**取值域**校验（不给无效配置落库的机会），再写存储。
  /// 协议适配器是否可用**不**在这里拒绝：见 [validateAiModel] 的说明。
  Future<Result<AiModel>> saveModel(AiModel model) async {
    final Result<void> valid = validateAiModel(model);
    if (valid.isErr) {
      return Err<AiModel>(valid.errorOrNull!);
    }
    final AiModel normalized = model.copyWith(
      alias: model.alias.trim(),
      baseUrl: model.baseUrl.trim(),
      modelId: model.modelId.trim(),
      preset: _emptyToNull(model.preset),
      clearPreset: _emptyToNull(model.preset) == null,
    );
    final Result<AiModel> saved = normalized.id == null
        ? await store.insert(normalized)
        : await store.update(normalized);
    if (saved.isErr) {
      // 失败原因类别进日志，**不含** Base URL 的完整 query 与任何凭据。
      diagnostics.warning(
        'AI 模型保存失败 alias=${normalized.alias} kind=${saved.errorOrNull!.kind}',
        tag: 'ai.model',
      );
      return saved;
    }
    diagnostics.info(
      'AI 模型已保存 alias=${normalized.alias} protocol=${normalized.protocol.id}',
      tag: 'ai.model',
    );
    return saved;
  }

  /// 计算某个模型当前被哪些配置引用（删除前展示给用户）。
  ///
  /// 设置读取失败时**不**把「读不到」当成「没有引用」：那会静默地允许一次危险删除。
  /// 因此读取失败直接返回错误，让上层提示「无法确认引用，稍后再试」。
  Future<Result<List<ModelReference>>> describeReferencesTo(
    AiModel model,
  ) async {
    final List<ModelReference> references = <ModelReference>[];
    if (model.id != null) {
      final Result<List<AiModel>> all = await store.loadAll();
      if (all.isErr) {
        return Err<List<ModelReference>>(all.errorOrNull!);
      }
      // 「任务默认」以**落库状态**为准而不是传入对象：调用方手上的对象可能是一份
      // 编辑中的副本，用它判断会与实际库里的引用不一致。
      final bool isDefault = all.valueOrNull!.any(
        (AiModel candidate) =>
            candidate.id == model.id && candidate.isDefaultForTasks,
      );
      references.addAll(<ModelReference>[
        if (isDefault)
          const ModelReference(kind: ModelReferenceKind.defaultForTasks),
      ]);
    }

    final SettingsReader? reader = settings;
    if (reader == null) {
      // 没有设置端口时返回已算出的引用，并在诊断里说明**这不是「没有引用」**：
      // 让它静默返回空列表会把「没检查」伪装成「检查过且为空」。
      diagnostics.warning(
        'SET-034/035 引用未检查（设置端口未接线）alias=${model.alias}',
        tag: 'ai.model',
      );
      return Ok<List<ModelReference>>(references);
    }
    final Result<Object?> vision = await reader.readSetting(SettingId.set034);
    if (vision.isErr) {
      return Err<List<ModelReference>>(vision.errorOrNull!);
    }
    final Result<Object?> failover = await reader.readSetting(SettingId.set035);
    if (failover.isErr) {
      return Err<List<ModelReference>>(failover.errorOrNull!);
    }
    final List<String> allowed = _allowedModels(failover.valueOrNull);
    references.addAll(
      referencesToAlias(
        alias: model.alias,
        isDefaultForTasks: false,
        visionModelAlias: vision.valueOrNull is String
            ? vision.valueOrNull! as String
            : null,
        failoverAllowList: allowed,
      ),
    );
    return Ok<List<ModelReference>>(references);
  }

  /// 删除一条模型记录。
  ///
  /// [force] 为 false 且存在引用时返回 [ModelInUseError]（界面据此展示确认对话框）；
  /// 为 true 表示用户已经看到引用并确认。
  ///
  /// 无论哪种路径都**同时删除该别名的凭据**吗？不。理由：同一别名下可能有多个模型
  /// 记录（不同模型 ID 共用一份提供商凭据），此处删掉 Key 会让另一个仍在使用的模型
  /// 突然认证失败。凭据的删除由用户显式操作（见 [deleteCredential]）。
  Future<Result<void>> deleteModel(AiModel model, {bool force = false}) async {
    final int? id = model.id;
    if (id == null) {
      return Err<void>(
        ValidationError(field: 'SET-032', reason: '删除需要已落库的模型记录'),
      );
    }
    if (!force) {
      final Result<List<ModelReference>> references =
          await describeReferencesTo(model);
      if (references.isErr) {
        return Err<void>(references.errorOrNull!);
      }
      if (references.valueOrNull!.isNotEmpty) {
        return Err<void>(
          ModelInUseError(
            alias: model.alias,
            referenceDescriptions: references.valueOrNull!
                .map((ModelReference reference) => reference.describe())
                .toList(growable: false),
          ),
        );
      }
    }
    final Result<void> deleted = await store.delete(id);
    if (deleted.isErr) {
      return deleted;
    }
    diagnostics.info('AI 模型已删除 alias=${model.alias}', tag: 'ai.model');
    return okUnit();
  }

  /// 启用/停用一个模型（SET-032）。
  Future<Result<AiModel>> setEnabled(AiModel model, bool enabled) =>
      saveModel(model.copyWith(enabled: enabled));

  /// 保存故障转移顺序（SET-032/035）。
  Future<Result<void>> reorder(List<int> idsInOrder) async {
    if (idsInOrder.length != idsInOrder.toSet().length) {
      return Err<void>(
        ValidationError(field: 'SET-032.sortOrder', reason: '排序列表里出现重复的模型'),
      );
    }
    return store.saveOrder(idsInOrder);
  }

  /// 设为/取消「任务默认模型」（唯一）。
  Future<Result<void>> setDefaultForTasks(int id, {required bool isDefault}) =>
      store.setDefaultForTasks(id, isDefault: isDefault);

  // ---- SET-031 凭据 -----------------------------------------------------

  /// 保存（替换）某个别名的 Key。
  ///
  /// 只记录「已写入/失败」，**不记录值**，也不回显值。
  Future<Result<void>> saveCredential(String alias, String apiKey) async {
    if (apiKey.trim().isEmpty) {
      return Err<void>(
        ValidationError(field: 'SET-031', reason: 'API Key 不能为空'),
      );
    }
    final Result<void> written = await credentials.write(alias, apiKey);
    if (written.isErr) {
      diagnostics.warning(
        'AI 凭据写入失败 alias=$alias kind=${written.errorOrNull!.kind}',
        tag: 'ai.credential',
      );
      return written;
    }
    diagnostics.info('AI 凭据已写入 alias=$alias', tag: 'ai.credential');
    return okUnit();
  }

  /// 删除某个别名的 Key（幂等）。
  Future<Result<void>> deleteCredential(String alias) async {
    final Result<void> deleted = await credentials.delete(alias);
    if (deleted.isOk) {
      diagnostics.info('AI 凭据已删除 alias=$alias', tag: 'ai.credential');
    }
    return deleted;
  }

  /// 某别名是否已配置 Key（**不返回 Key 本身**）。
  Future<Result<bool>> hasCredential(String alias) => credentials.exists(alias);

  /// 安全存储是否可用；false 时界面必须提示「本次会话可用但不保存」。
  Future<bool> isCredentialStoreAvailable() => credentials.isAvailable();

  // ---- 最小生成测试（SET-042 的动作，会产生费用） ------------------------

  /// 发起一次最小生成测试。
  ///
  /// 前置检查全部在**发请求之前**完成，并且给出的原因都是「用户能据此采取动作」的：
  ///   - 没有 [CostConfirmation] → 调用方没弹确认框，直接拒绝（不发请求）；
  ///   - 模型未启用 → 提示先启用；
  ///   - 协议没有适配器 / 工厂未接线 → 提示适配器尚未实现；
  ///   - Key 缺失或读取失败 → 提示先去填 Key。
  ///
  /// 参数里的 maxTokens 由调用方按 SET-033 的输出预算给出，但这里再夹一道上限
  /// （[minimalTestMaxTokens]）：测试的目的只是「通不通」，不该按用户配的最大预算去花。
  Future<Result<ModelTestReport>> runMinimalGeneration(
    AiModel model, {
    required CostConfirmation confirmation,
    int? maxTokens,
  }) async {
    if (!model.enabled) {
      return Err<ModelTestReport>(
        ModelConfigurationError(alias: model.alias, reason: 'disabled'),
      );
    }
    if (!model.protocol.hasAdapter) {
      return Err<ModelTestReport>(
        ModelConfigurationError(
          alias: model.alias,
          reason: 'adapterMissing',
          detail: model.protocol.missingAdapterReason,
        ),
      );
    }
    final AiProviderFactory? factory = providerFactory;
    if (factory == null) {
      return Err<ModelTestReport>(
        ModelConfigurationError(
          alias: model.alias,
          reason: 'adapterMissing',
          detail: '适配器工厂未接线',
        ),
      );
    }
    final Result<String> key = await credentials.read(
      model.credentialIdentifier,
    );
    if (key.isErr) {
      return Err<ModelTestReport>(
        ModelConfigurationError(
          alias: model.alias,
          reason: 'credentialMissing',
          detail: key.errorOrNull!.kind,
        ),
      );
    }
    final Result<AiProvider> created = factory.create(
      alias: model.alias,
      protocolId: model.protocol.id,
      baseUrl: model.baseUrl,
      modelId: model.modelId,
      apiKey: key.valueOrNull!,
    );
    if (created.isErr) {
      return Err<ModelTestReport>(created.errorOrNull!);
    }

    final int budget = _minimalTestBudget(model, maxTokens);
    final AiRequest request = AiRequest(
      modelId: model.modelId,
      messages: const <AiMessage>[
        AiMessage.system('你是连接测试助手，只回答一个短句。'),
        AiMessage.user('回复：连接正常'),
      ],
      maxTokens: budget,
    );

    final Duration started = clock.monotonic();
    final StringBuffer received = StringBuffer();
    AiUsage? usage;
    String? finishReason;
    try {
      await for (final AiEvent event in created.valueOrNull!.generate(
        request,
      )) {
        switch (event) {
          case AiDelta(:final String text):
            received.write(text);
          case AiUsage():
            usage = event;
          case AiDone():
            // 连接测试不发送工具声明，因此不会有工具调用；真收到也**不执行**
            // （测试路径不该有能力做任何工具动作——那会把一次连通性验证
            // 变成一次出网与计费）。显式列出并忽略，让「有工具调用」这件事
            // 在编译器层面被处理掉而不是漏掉。
            finishReason = event.finishReason;
          case AiToolCalls():
            // 连接测试不发送工具声明，因此理论上收不到；真收到也**不执行**
            // （测试路径不该有能力做任何工具动作——那会把一次连通性验证变成一次
            // 出网与计费）。显式列出并忽略，让「有工具调用」在编译器层面被处理掉。
            break;
        }
      }
    } on AppError catch (error) {
      diagnostics.warning(
        'AI 连接测试失败 alias=${model.alias} kind=${error.kind}',
        tag: 'ai.test',
      );
      return Err<ModelTestReport>(error);
    } on Object catch (error, stackTrace) {
      // 适配器理论上只抛 AppError；到这里说明适配器有 bug。翻译成 NetworkError 而
      // 不是把原始异常往上抛：原始异常的 toString 可能带上请求体或响应片段。
      diagnostics.error(
        'AI 连接测试出现未类型化异常 alias=${model.alias} '
        'type=${error.runtimeType}',
        tag: 'ai.test',
      );
      return Err<ModelTestReport>(
        NetworkError(
          uri: model.baseUrl,
          reason: '适配器抛出未类型化异常（${error.runtimeType}）',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }

    final Duration elapsed = clock.monotonic() - started;
    // 诊断只记结构事实：耗时、token 数、字符数、结束原因。**不记文本内容**，
    // 也不记 Key——本行里没有任何一处插值 Key。
    diagnostics.info(
      'AI 连接测试成功 alias=${model.alias} elapsedMs=${elapsed.inMilliseconds} '
      'inTokens=${usage?.inputTokens ?? 'unknown'} '
      'outTokens=${usage?.outputTokens ?? 'unknown'} '
      'chars=${received.length} confirmedAt=${confirmation.acknowledgedAtUtc.toIso8601String()}',
      tag: 'ai.test',
    );
    return Ok<ModelTestReport>(
      ModelTestReport(
        elapsed: elapsed,
        usage: usage,
        textLength: received.length,
        finishReason: finishReason,
      ),
    );
  }

  /// 最小生成测试的输出上限。
  static const int minimalTestMaxTokens = 64;

  /// 测试用的输出预算：取用户预算与 [minimalTestMaxTokens] 的较小值。
  ///
  /// 只用于「连通性」判断，因此不需要按用户配置的 2048 去花；同时也不做「至少 64」
  /// 之外的抬高——用户把预算设成 16 时，测试就该只花 16。
  static int _minimalTestBudget(AiModel model, int? maxTokens) {
    final int configured = maxTokens ?? model.capability.effectiveOutputBudget;
    return configured < minimalTestMaxTokens
        ? configured
        : minimalTestMaxTokens;
  }

  /// 从 SET-035 的值里取出允许模型别名列表（容错：结构不符时返回空列表）。
  static List<String> _allowedModels(Object? raw) {
    if (raw is! Map<Object?, Object?>) {
      return const <String>[];
    }
    final Object? allowed = raw['allowedModels'];
    if (allowed is! List<Object?>) {
      return const <String>[];
    }
    return allowed.whereType<String>().toList(growable: false);
  }

  static String? _emptyToNull(String? value) {
    if (value == null) {
      return null;
    }
    final String trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}

/// 设置读取端口（本用例只需要「按编号读」；由组合根把 SettingsStore 适配上来）。
///
/// 单独一个窄接口而不是直接依赖 SettingsStore：本用例只读两项（SET-034/035），
/// 不该拿到写入口——一个「顺手把设置改了」的路径会让模型管理与设置页各写一套状态。
abstract interface class SettingsReader {
  /// 读取一个设置项（未存过时返回注册表默认值）。
  Future<Result<Object?>> readSetting(SettingId id);
}
