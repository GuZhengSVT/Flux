// 搜索服务页的状态（T031）。
//
// 分工与 ModelManagerController 完全一致：本控制器只做「读列表 → 调用例 → 反映结果」，
// **不写**界面文案；失败按类型化类别分成 [AiFailureReason]（复用 AI 侧那一套分类，
// 因为两侧的失败类别是同一组：校验/认证/限流/网络/超时/取消/存储），由 presentation
// 映射到 l10n。
//
// 一个刻意的选择与 AI 侧一致：列表读取失败**不**淡化成空列表。空列表意味着「还没配置」，
// 而读取失败意味着「读不到」——两者在界面上的下一步动作不同（去添加 vs 去排查）。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flux/core/core.dart';

import '../domain/search_service.dart';
import 'ai_ports.dart';
import 'model_manager_controller.dart' show AiFailureReason;
import 'search_manager.dart';

/// 页面状态。
final class SearchServicesState {
  /// 构造状态。
  const SearchServicesState({
    required this.services,
    this.loaded = false,
    this.loadFailure,
    this.credentialStoreAvailable = true,
    this.credentialEpoch = 0,
  });

  /// 服务列表（已按选择顺序）。
  final List<SearchService> services;

  /// 是否已成功读到列表。
  final bool loaded;

  /// 读取失败类别；非空时 [services] 不可信。
  final AiFailureReason? loadFailure;

  /// 安全存储是否可用；false 时界面提示「本次会话可用但不保存」。
  final bool credentialStoreAvailable;

  /// 凭据变更计数（每次写入/删除凭据 +1）。
  ///
  /// 为什么需要它：凭据**不在**服务记录里（SET-039 只住 Keychain），因此「凭据已配置」
  /// 这件事不体现在 [services] 上。界面上每条卡片各自查询一次凭据状态，如果没有任何
  /// 可比较的量，保存凭据之后卡片的禁用态不会更新——用户会看到一个明明已经填了 Key
  /// 却依然禁用的测试按钮。用一个显式的变更计数让「凭据变了」成为界面可见的事实。
  final int credentialEpoch;

  /// 复制并覆盖部分字段。
  SearchServicesState copyWith({
    List<SearchService>? services,
    bool? loaded,
    AiFailureReason? loadFailure,
    bool clearLoadFailure = false,
    bool? credentialStoreAvailable,
    int? credentialEpoch,
  }) => SearchServicesState(
    services: services ?? this.services,
    loaded: loaded ?? this.loaded,
    loadFailure: clearLoadFailure ? null : (loadFailure ?? this.loadFailure),
    credentialStoreAvailable:
        credentialStoreAvailable ?? this.credentialStoreAvailable,
    credentialEpoch: credentialEpoch ?? this.credentialEpoch,
  );
}

/// 搜索服务管理控制器。
final class SearchManagerController extends AsyncNotifier<SearchServicesState> {
  /// 取用例。
  SearchManager get _manager => ref.read(searchManagerProvider);

  @override
  Future<SearchServicesState> build() async {
    final bool available = await _manager.isCredentialStoreAvailable();
    final Result<List<SearchService>> loaded = await _manager.loadServices();
    if (loaded.isErr) {
      return SearchServicesState(
        services: const <SearchService>[],
        loadFailure: AiFailureReason.classify(loaded.errorOrNull!),
        credentialStoreAvailable: available,
      );
    }
    return SearchServicesState(
      services: loaded.valueOrNull!,
      loaded: true,
      credentialStoreAvailable: available,
    );
  }

  /// 重新读取列表（保存/删除后调用）。
  Future<void> reload() async {
    state = AsyncData<SearchServicesState>(await build());
  }

  /// 保存一条服务记录。
  Future<Result<SearchService>> save(SearchService service) async {
    final Result<SearchService> saved = await _manager.saveService(service);
    if (saved.isOk) {
      await reload();
    }
    return saved;
  }

  /// 删除一条服务记录（force 由界面在用户确认引用后传入）。
  Future<Result<void>> delete(
    SearchService service, {
    bool force = false,
  }) async {
    final Result<void> deleted = await _manager.deleteService(
      service,
      force: force,
    );
    if (deleted.isOk) {
      await reload();
    }
    return deleted;
  }

  /// 计算引用（删除前展示）。
  Future<Result<List<String>>> describeReferences(SearchService service) =>
      _manager.describeReferencesTo(service);

  /// 启用/停用。
  Future<Result<SearchService>> setEnabled(
    SearchService service,
    bool enabled,
  ) => save(service.copyWith(enabled: enabled));

  /// 设为/取消任务默认搜索服务。
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

  /// 写入某个服务名的 Key。
  Future<Result<void>> saveCredential(String identifier, String apiKey) async {
    final Result<void> result = await _manager.saveCredential(
      identifier,
      apiKey,
    );
    if (result.isOk) {
      _bumpCredentialEpoch();
    }
    return result;
  }

  /// 删除某个服务名的 Key。
  Future<Result<void>> deleteCredential(String identifier) async {
    final Result<void> result = await _manager.deleteCredential(identifier);
    if (result.isOk) {
      _bumpCredentialEpoch();
    }
    return result;
  }

  /// 标记「凭据已变化」，让列表里的卡片重新查询凭据状态。
  void _bumpCredentialEpoch() {
    final SearchServicesState? current = state.value;
    if (current == null) {
      return;
    }
    state = AsyncData<SearchServicesState>(
      current.copyWith(credentialEpoch: current.credentialEpoch + 1),
    );
  }

  /// 某个服务名是否已配置 Key。
  Future<bool> hasCredential(String identifier) async {
    final Result<bool> result = await _manager.hasCredential(identifier);
    return result.getOrElse(false);
  }

  /// 发起一次最小检索测试（费用/数据发送确认由界面弹框并构造
  /// [SearchSendConfirmation]）。
  Future<Result<SearchTestReport>> test(
    SearchService service, {
    required SearchSendConfirmation confirmation,
  }) => _manager.runMinimalSearch(service, confirmation: confirmation);
}

/// 搜索服务管理控制器 Provider。
final AsyncNotifierProvider<SearchManagerController, SearchServicesState>
searchManagerControllerProvider =
    AsyncNotifierProvider<SearchManagerController, SearchServicesState>(
      SearchManagerController.new,
    );

/// 搜索服务管理用例 Provider（由组合根装配所需端口）。
final Provider<SearchManager> searchManagerProvider = Provider<SearchManager>(
  (Ref ref) => SearchManager(
    store: ref.watch(searchServiceStoreProvider),
    credentials: ref.watch(searchCredentialStoreProvider),
    diagnostics: ref.watch(aiDiagnosticSinkProvider),
    factory: ref.watch(searchProviderFactoryProvider),
  ),
);
