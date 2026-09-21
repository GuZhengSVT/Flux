// 搜索服务管理用例（T031；SET-038/039/040/041 与 SET-042 的搜索测试动作）。
//
// 职责边界：本层只做「服务记录的增删改查 + 凭据读写 + 排序启用 + 一次最小检索测试」，
// 不碰 HTTP 细节（那在适配器）、不碰界面（那在 presentation）。
//
// 四条容易做错、因此显式设计的边界：
//
//   1) **Key 永不出现在日志/诊断里**。所有诊断文本都是「服务名 + 结果类别」，从不插值
//      Key；读取 Key 的方法返回的 Result 只交给适配器。这不是靠自觉：本文件里没有
//      任何一处把 apiKey 拼进字符串（有用例断言诊断日志中不含 Key 的形态）。
//
//   2) **没有凭据绝不发请求**。测试按钮在无 Key 时**不弹费用确认、不发请求**，直接
//      返回类型化配置错误。搜索服务按调用计费（Tavily/Brave 都是），一次「先试试看」
//      的请求就是一次真实消耗。
//
//   3) **删除留下悬空引用要能看见**。当前只有「任务默认搜索服务」这一个本机引用，
//      因此删除前的检查面比模型小；但仍然先算再说（见 describeReferencesTo），不为
//      「看起来没有引用」而省掉一步——将来 T036/T037 增加按名字的引用时这一步已经在了。
//
//   4) **私网端点需要显式批准（SET-041）**。批准存在记录里，校验发生在保存与调用
//      两处：保存时提示、调用前再拦一次（记录可能来自手工改库或旧版本导入）。
library;

import 'package:flux/core/core.dart';

import '../domain/search_credential_store.dart';
import '../domain/search_provider.dart';
import '../domain/search_result.dart';
import '../domain/search_service.dart';
import '../domain/search_service_store.dart';

/// 一次最小检索测试的授权凭据（SET-042「真实请求前提示收费/数据发送」）。
///
/// 与 CostConfirmation 同一个理由：布尔参数在调用点写成 testService(service, true)
/// 时读者无法知道那个 true 表示什么，也容易在重构时传错。一个命名类型让「调用方已经
/// 看到并确认了费用与数据去向提示」这件事在签名上可见。
final class SearchSendConfirmation {
  /// 构造已确认的凭据（只应由「用户点了确认」的代码路径创建）。
  const SearchSendConfirmation({required this.acknowledgedAtUtc});

  /// 用户确认的时刻（UTC），写进诊断便于核对「这次调用经过了知情确认」。
  final DateTime acknowledgedAtUtc;
}

/// 搜索测试的结果（供界面显示耗时与命中数）。
final class SearchTestReport {
  /// 构造报告。
  const SearchTestReport({
    required this.elapsed,
    required this.resultCount,
    required this.hasAnswer,
    this.firstTitle,
  });

  /// 端到端耗时。
  final Duration elapsed;

  /// 返回的结果条数（**不**回显片段内容：测试的目的是「通不通」，把内容存进日志或
  /// 界面会把一次连通性验证变成一次内容泄漏面）。
  final int resultCount;

  /// 服务商是否给出了答案摘要。
  final bool hasAnswer;

  /// 第一条结果的标题；没有结果时为 null。
  ///
  /// 标题会展示给用户（他要判断「搜的是不是想要的东西」），但**不进诊断日志**。
  final String? firstTitle;
}

/// 搜索服务管理用例。
final class SearchManager {
  /// 构造用例。
  const SearchManager({
    required this.store,
    required this.credentials,
    required this.diagnostics,
    this.factory,
    this.clock = const SystemClock(),
  });

  /// 服务记录存储。
  final SearchServiceStore store;

  /// 凭据存储（SET-039）。
  final SearchCredentialStore credentials;

  /// 诊断记录。
  final DiagnosticSink diagnostics;

  /// 适配器工厂；为空时测试功能明确报「工厂未接线」。
  final SearchProviderFactory? factory;

  /// 时钟（测试注入，用于耗时与确认时刻）。
  final Clock clock;

  /// 载入全部服务（已按选择顺序排序）。
  Future<Result<List<SearchService>>> loadServices() => store.loadAll();

  /// 载入启用中的服务（工具执行器的候选，按排序）。
  Future<Result<List<SearchService>>> loadEnabledServices() async {
    final Result<List<SearchService>> all = await store.loadAll();
    if (all.isErr) {
      return all;
    }
    return Ok<List<SearchService>>(
      all.valueOrNull!
          .where((SearchService service) => service.enabled)
          .toList(growable: false),
    );
  }

  /// 新建或更新一条服务记录（依据 id 是否为空）。
  ///
  /// 校验顺序：先做**取值域**校验（不给无效配置落库的机会），再写存储。
  /// 凭据是否已配置**不**在这里拒绝：用户可以先配好记录，等拿到 Key 再启用。
  Future<Result<SearchService>> saveService(SearchService service) async {
    final Result<void> valid = validateSearchService(service);
    if (valid.isErr) {
      return Err<SearchService>(valid.errorOrNull!);
    }
    final SearchService normalized = service.copyWith(
      label: service.label.trim(),
      baseUrl: service.baseUrl.trim(),
    );
    final Result<SearchService> saved = normalized.id == null
        ? await store.insert(normalized)
        : await store.update(normalized);
    if (saved.isErr) {
      // 失败原因类别进日志，**不含**完整端点地址与任何凭据。
      diagnostics.warning(
        '搜索服务保存失败 label=${normalized.label} '
        'kind=${saved.errorOrNull!.kind}',
        tag: 'search.service',
      );
      return saved;
    }
    diagnostics.info(
      '搜索服务已保存 label=${normalized.label} '
      'protocol=${normalized.protocol.id}',
      tag: 'search.service',
    );
    return saved;
  }

  /// 计算某个服务当前被哪些配置引用（删除前展示给用户）。
  ///
  /// 当前只有「任务默认搜索服务」这一个引用来源（记录自身的字段）。将来 T036/T037
  /// 的查询配置会按**名字**引用服务，届时这里补上；现在如实返回已检查的范围。
  Future<Result<List<String>>> describeReferencesTo(
    SearchService service,
  ) async {
    final int? id = service.id;
    if (id == null) {
      return const Ok<List<String>>(<String>[]);
    }
    final Result<List<SearchService>> all = await store.loadAll();
    if (all.isErr) {
      return Err<List<String>>(all.errorOrNull!);
    }
    // 「任务默认」以**落库状态**为准而不是传入对象：调用方手上的对象可能是一份
    // 编辑中的副本，用它判断会与实际库里的引用不一致。
    final bool isDefault = all.valueOrNull!.any(
      (SearchService candidate) =>
          candidate.id == id && candidate.isDefaultForTasks,
    );
    return Ok<List<String>>(<String>[if (isDefault) '任务默认搜索服务']);
  }

  /// 删除一条服务记录。
  ///
  /// force 为 false 且存在引用时返回 ModelInUseError（界面据此展示确认对话框）；
  /// 为 true 表示用户已经看到引用并确认。
  ///
  /// 与 ModelManager.deleteModel 同一取舍：**不**顺带删除凭据。删除凭据是一次独立的
  /// 显式操作（见 deleteCredential）——顺带删掉会让「我只是想删掉这条配置」变成一次
  /// 不可撤销的凭据清理。
  Future<Result<void>> deleteService(
    SearchService service, {
    bool force = false,
  }) async {
    final int? id = service.id;
    if (id == null) {
      return Err<void>(
        ValidationError(field: 'SET-038', reason: '删除需要已落库的搜索服务记录'),
      );
    }
    if (!force) {
      final Result<List<String>> references = await describeReferencesTo(
        service,
      );
      if (references.isErr) {
        return Err<void>(references.errorOrNull!);
      }
      if (references.valueOrNull!.isNotEmpty) {
        return Err<void>(
          ModelInUseError(
            alias: service.label,
            referenceDescriptions: references.valueOrNull!,
          ),
        );
      }
    }
    final Result<void> deleted = await store.delete(id);
    if (deleted.isErr) {
      return deleted;
    }
    diagnostics.info('搜索服务已删除 label=${service.label}', tag: 'search.service');
    return okUnit();
  }

  /// 启用/停用一条服务。
  Future<Result<SearchService>> setEnabled(
    SearchService service,
    bool enabled,
  ) => saveService(service.copyWith(enabled: enabled));

  /// 保存服务选择顺序。
  Future<Result<void>> reorder(List<int> idsInOrder) async {
    if (idsInOrder.length != idsInOrder.toSet().length) {
      return Err<void>(
        ValidationError(field: 'SET-038.sortOrder', reason: '排序列表里出现重复的服务记录'),
      );
    }
    return store.saveOrder(idsInOrder);
  }

  /// 设为/取消「任务默认搜索服务」（唯一）。
  Future<Result<void>> setDefaultForTasks(int id, {required bool isDefault}) =>
      store.setDefaultForTasks(id, isDefault: isDefault);

  // ---- SET-039 凭据 -----------------------------------------------------

  /// 保存（替换）某个服务名的 Key。
  ///
  /// 只记录「已写入/失败」，**不记录值**，也不回显值。
  Future<Result<void>> saveCredential(String identifier, String apiKey) async {
    if (apiKey.trim().isEmpty) {
      return Err<void>(
        ValidationError(field: 'SET-039', reason: 'API Key 不能为空'),
      );
    }
    final Result<void> written = await credentials.write(identifier, apiKey);
    if (written.isErr) {
      diagnostics.warning(
        '搜索凭据写入失败 label=$identifier kind=${written.errorOrNull!.kind}',
        tag: 'search.credential',
      );
      return written;
    }
    diagnostics.info('搜索凭据已写入 label=$identifier', tag: 'search.credential');
    return okUnit();
  }

  /// 删除某个服务名的 Key（幂等）。
  Future<Result<void>> deleteCredential(String identifier) async {
    final Result<void> deleted = await credentials.delete(identifier);
    if (deleted.isOk) {
      diagnostics.info('搜索凭据已删除 label=$identifier', tag: 'search.credential');
    }
    return deleted;
  }

  /// 某个服务名是否已配置 Key（**不返回 Key 本身**）。
  Future<Result<bool>> hasCredential(String identifier) =>
      credentials.exists(identifier);

  /// 安全存储是否可用；false 时界面必须提示「本次会话可用但不保存」。
  Future<bool> isCredentialStoreAvailable() => credentials.isAvailable();

  // ---- 最小检索测试（SET-042 的动作，会产生费用与数据发送） ----------------

  /// 发起一次最小检索测试。
  ///
  /// 前置检查全部在**发请求之前**完成，并且给出的原因都是「用户能据此采取动作」的：
  ///   - 没有 SearchSendConfirmation → 调用方没弹确认框，直接拒绝（不发请求）；
  ///   - 服务未启用 → 提示先启用；
  ///   - 工厂未接线 → 提示适配器未接线；
  ///   - **协议要求凭据但未配置** → 提示先去填 Key（SearXNG 不要求凭据，因此放行）；
  ///   - 私网端点未批准 → 适配器在发出请求前拒绝并提示去打开 SET-041。
  Future<Result<SearchTestReport>> runMinimalSearch(
    SearchService service, {
    required SearchSendConfirmation confirmation,
    String query = 'Flux 本地优先阅读器',
  }) async {
    if (!service.enabled) {
      return Err<SearchTestReport>(
        ValidationError(field: 'SET-038.enabled', reason: '服务未启用，请先启用'),
      );
    }
    final SearchProviderFactory? providerFactory = factory;
    if (providerFactory == null) {
      return Err<SearchTestReport>(
        ValidationError(field: 'SET-042', reason: '搜索适配器工厂未接线'),
      );
    }

    // 凭据是否必需由**协议**决定，不由「用户填没填」决定。
    String apiKey = '';
    final Result<String> key = await credentials.read(
      service.credentialIdentifier,
    );
    if (service.protocol.requiresCredential) {
      if (key.isErr) {
        return Err<SearchTestReport>(
          AuthError(provider: service.protocol.id, detail: 'credentialMissing'),
        );
      }
      apiKey = key.valueOrNull!;
    } else {
      // 可选认证：有就用，没有就发不带认证头的请求（自建实例常由反向代理认证）。
      apiKey = key.isOk ? key.valueOrNull! : '';
    }

    final Result<SearchProvider> created = providerFactory.create(
      protocol: service.protocol,
      baseUrl: service.baseUrl,
      apiKey: apiKey,
      timeout: Duration(seconds: service.timeoutSeconds),
      maxResults: service.maxResults,
      allowPrivateEndpoint: service.allowPrivateEndpoint,
    );
    if (created.isErr) {
      return Err<SearchTestReport>(created.errorOrNull!);
    }

    final Duration started = clock.monotonic();
    try {
      // 测试只取 1 条：目的只是「通不通」，不该按用户配置的 10 条去花。
      final Result<SearchResponse> response = await created.valueOrNull!.search(
        SearchRequest(text: query.trim(), count: 1),
      );
      final Duration elapsed = clock.monotonic() - started;
      if (response.isErr) {
        diagnostics.warning(
          '搜索测试失败 label=${service.label} '
          'kind=${response.errorOrNull!.kind}',
          tag: 'search.test',
        );
        return Err<SearchTestReport>(response.errorOrNull!);
      }
      final SearchResponse value = response.unwrap();
      // 诊断只记结构事实：耗时、条数、是否有答案、确认时刻。
      // **不记**查询词、不记片段、不记 Key——本行里没有任何一处插值它们。
      diagnostics.info(
        '搜索测试成功 label=${service.label} '
        'elapsedMs=${elapsed.inMilliseconds} results=${value.results.length} '
        'hasAnswer=${value.answer != null} '
        'confirmedAt=${confirmation.acknowledgedAtUtc.toIso8601String()}',
        tag: 'search.test',
      );
      return Ok<SearchTestReport>(
        SearchTestReport(
          elapsed: elapsed,
          resultCount: value.results.length,
          hasAnswer: value.answer != null,
          firstTitle: value.results.isEmpty ? null : value.results.first.title,
        ),
      );
    } on AppError catch (error) {
      diagnostics.warning(
        '搜索测试失败 label=${service.label} kind=${error.kind}',
        tag: 'search.test',
      );
      return Err<SearchTestReport>(error);
    } on Object catch (error, stackTrace) {
      // 适配器理论上只抛 AppError；到这里说明适配器有 bug。翻译成 NetworkError 而
      // 不是把原始异常往上抛：原始异常的 toString 可能带上查询词或响应片段。
      diagnostics.error(
        '搜索测试出现未类型化异常 label=${service.label} '
        'type=${error.runtimeType}',
        tag: 'search.test',
      );
      return Err<SearchTestReport>(
        NetworkError(
          uri: service.baseUrl,
          reason: '适配器抛出未类型化异常（${error.runtimeType}）',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }
}
