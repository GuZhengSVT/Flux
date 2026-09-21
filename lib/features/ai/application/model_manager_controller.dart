// AI 模型管理页的状态（T025）。
//
// 分工：本控制器只做「读列表 → 调用例 → 反映结果」，**不写**界面文案；
// 失败按类型化类别分成 [AiFailureReason]，由 presentation 映射到 l10n
// （与 subscription_error 同一做法：控制器不依赖 l10n）。
//
// 一个刻意的选择：列表读取失败**不**淡化成空列表。空列表意味着「还没配置」，
// 而读取失败意味着「读不到」——两者在界面上的下一步动作不同（去添加 vs 去排查），
// 混成一个会让用户以为自己的配置丢了。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flux/core/core.dart';

import '../domain/ai_model.dart';
import '../domain/ai_model_references.dart';
import 'ai_ports.dart';
import 'model_manager.dart';

/// 失败类别（界面据此选文案；控制器不产出文案）。
enum AiFailureReason {
  /// 校验失败（取值域非法）。
  validation,

  /// 认证失败（Key 错/余额不足）。
  authentication,

  /// 限流。
  rateLimited,

  /// 内容被拒绝。
  contentFiltered,

  /// 网络失败。
  network,

  /// 超时。
  timeout,

  /// 已取消。
  cancelled,

  /// 协议没有适配器。
  adapterMissing,

  /// 缺少凭据。
  credentialMissing,

  /// 模型被停用。
  disabled,

  /// 本地存储失败。
  storage,

  /// 其它。
  unknown;

  /// 把一个类型化错误归类。
  static AiFailureReason classify(AppError error) => switch (error) {
    ValidationError() => validation,
    AuthError() => authentication,
    RateLimitError() => rateLimited,
    ContentFilteredError() => contentFiltered,
    DeadlineExceededError() => timeout,
    CancelledError() => cancelled,
    StorageError() => storage,
    NetworkError() => network,
    ModelConfigurationError(:final String reason) => switch (reason) {
      'adapterMissing' => adapterMissing,
      'credentialMissing' => credentialMissing,
      'disabled' => disabled,
      _ => unknown,
    },
    _ => unknown,
  };
}

/// 页面状态。
final class AiModelsState {
  /// 构造状态。
  const AiModelsState({
    required this.models,
    this.loaded = false,
    this.loadFailure,
    this.credentialStoreAvailable = true,
  });

  /// 模型列表（已按故障转移顺序）。
  final List<AiModel> models;

  /// 是否已成功读到列表。
  final bool loaded;

  /// 读取失败类别；非空时 [models] 不可信。
  final AiFailureReason? loadFailure;

  /// 安全存储是否可用；false 时界面提示「本次会话可用但不保存」。
  final bool credentialStoreAvailable;

  /// 复制并覆盖部分字段。
  AiModelsState copyWith({
    List<AiModel>? models,
    bool? loaded,
    AiFailureReason? loadFailure,
    bool clearLoadFailure = false,
    bool? credentialStoreAvailable,
  }) => AiModelsState(
    models: models ?? this.models,
    loaded: loaded ?? this.loaded,
    loadFailure: clearLoadFailure ? null : (loadFailure ?? this.loadFailure),
    credentialStoreAvailable:
        credentialStoreAvailable ?? this.credentialStoreAvailable,
  );
}

/// 模型管理控制器。
final class ModelManagerController extends AsyncNotifier<AiModelsState> {
  /// 取用例。
  ModelManager get _manager => ref.read(modelManagerProvider);

  @override
  Future<AiModelsState> build() async {
    final bool available = await _manager.isCredentialStoreAvailable();
    final Result<List<AiModel>> loaded = await _manager.loadModels();
    if (loaded.isErr) {
      return AiModelsState(
        models: const <AiModel>[],
        loadFailure: AiFailureReason.classify(loaded.errorOrNull!),
        credentialStoreAvailable: available,
      );
    }
    return AiModelsState(
      models: loaded.valueOrNull!,
      loaded: true,
      credentialStoreAvailable: available,
    );
  }

  /// 重新读取列表（保存/删除后调用）。
  Future<void> reload() async {
    state = AsyncData<AiModelsState>(await build());
  }

  /// 保存一条模型记录。
  Future<Result<AiModel>> save(AiModel model) async {
    final Result<AiModel> saved = await _manager.saveModel(model);
    if (saved.isOk) {
      await reload();
    }
    return saved;
  }

  /// 删除一条模型记录（force 由界面在用户确认引用后传入）。
  Future<Result<void>> delete(AiModel model, {bool force = false}) async {
    final Result<void> deleted = await _manager.deleteModel(
      model,
      force: force,
    );
    if (deleted.isOk) {
      await reload();
    }
    return deleted;
  }

  /// 计算引用（删除前展示）。
  Future<Result<List<ModelReference>>> describeReferences(AiModel model) =>
      _manager.describeReferencesTo(model);

  /// 启用/停用。
  Future<Result<AiModel>> setEnabled(AiModel model, bool enabled) =>
      save(model.copyWith(enabled: enabled));

  /// 设为/取消任务默认模型。
  Future<Result<void>> setDefaultForTasks(
    int id, {
    required bool isDefault,
  }) async {
    final Result<void> result = await _manager.setDefaultForTasks(
      id,
      isDefault: isDefault,
    );
    if (result.isOk) {
      await reload();
    }
    return result;
  }

  /// 保存顺序（传完整的新顺序）。
  Future<Result<void>> reorder(List<int> idsInOrder) async {
    final Result<void> result = await _manager.reorder(idsInOrder);
    if (result.isOk) {
      await reload();
    }
    return result;
  }

  /// 写入某个别名的 Key。
  Future<Result<void>> saveCredential(String alias, String apiKey) =>
      _manager.saveCredential(alias, apiKey);

  /// 删除某个别名的 Key。
  Future<Result<void>> deleteCredential(String alias) =>
      _manager.deleteCredential(alias);

  /// 某个别名是否已配置 Key。
  Future<bool> hasCredential(String alias) async {
    final Result<bool> result = await _manager.hasCredential(alias);
    return result.getOrElse(false);
  }

  /// 发起一次最小生成测试（费用确认由界面负责弹框并构造 [CostConfirmation]）。
  Future<Result<ModelTestReport>> test(
    AiModel model, {
    required CostConfirmation confirmation,
  }) => _manager.runMinimalGeneration(model, confirmation: confirmation);
}

/// 模型管理控制器 Provider。
final AsyncNotifierProvider<ModelManagerController, AiModelsState>
modelManagerControllerProvider =
    AsyncNotifierProvider<ModelManagerController, AiModelsState>(
      ModelManagerController.new,
    );

/// 模型管理用例 Provider（由组合根装配所需端口）。
final Provider<ModelManager> modelManagerProvider = Provider<ModelManager>(
  (Ref ref) => ModelManager(
    store: ref.watch(aiModelStoreProvider),
    credentials: ref.watch(aiCredentialStoreProvider),
    diagnostics: ref.watch(aiDiagnosticSinkProvider),
    providerFactory: ref.watch(aiProviderFactoryProvider),
    settings: ref.watch(aiSettingsReaderProvider),
  ),
);

/// 设置读取端口 Provider（由组合根接上 SettingsStore）。
final Provider<SettingsReader?> aiSettingsReaderProvider =
    Provider<SettingsReader?>((Ref ref) => null);
