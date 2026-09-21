// 搜索服务记录（T031；架构 5.1 的 SearchConfig 实体、SET-038/039/040/041）。
//
// 一条记录代表「一个可以被调用的搜索端点」，字段按 SET 编号归口：
//   SET-038 协议/端点/排序/启用 → [protocol] / [baseUrl] / [sortOrder] / [enabled]
//   SET-039 搜索 API Key/实例认证 → 只持有 [credentialIdentifier]，值住 Keychain
//   SET-040 每次结果数/单次超时   → [maxResults] / [timeoutSeconds]
//   SET-041 允许指定内网/HTTP 端点 → [allowPrivateEndpoint]（显式批准）
//
// **凭据不在记录里**（架构 5.1「数据库不含秘密」、第 8 节）：与 [AiModel] 同一条纪律，
// 数据库列里没有任何 Key 字段，明文备份不会泄漏搜索 Key。
//
// 为什么单独建模而不是复用 SET-038 的设置行：架构 5.1 把 SearchConfig 列为一个**实体**，
// 而「排序/启用/多条服务」是一个列表语义——塞进一个 (key, value) 设置行只能用 JSON
// 数组表达，于是「改一个开关要读改写整行」，两次并发修改必丢一次（T025 的模型记录
// 当初也是这个理由落的表）。
library;

import 'package:flux/core/core.dart';

import 'search_protocol.dart';

/// 一个搜索服务记录。
final class SearchService {
  /// 构造记录。
  const SearchService({
    this.id,
    required this.label,
    required this.protocol,
    required this.baseUrl,
    this.enabled = true,
    this.sortOrder = 0,
    this.maxResults = kSearchDefaultMaxResults,
    this.timeoutSeconds = kSearchDefaultTimeoutSeconds,
    this.allowPrivateEndpoint = false,
    this.isDefaultForTasks = false,
    this.createdAt,
    this.updatedAt,
  });

  /// 本机自增 id；尚未落库时为 null。
  final int? id;

  /// 用户可见的名字（本机唯一，也是 Keychain 条目的定位键）。
  final String label;

  /// 协议。
  final SearchProtocol protocol;

  /// Base URL（不含协议路径；SearXNG 为自建实例地址）。
  final String baseUrl;

  /// 是否启用（停用后不参与工具执行器的服务选择）。
  final bool enabled;

  /// 排序（升序；工具执行器按此顺序取第一个可用服务）。
  ///
  /// 用**显式序号**而不是列表位置：列表位置是查询结果的顺序，用户拖动一次若没有
  /// 持久化序号，重启后会回到插入顺序，「按排序选择服务」就变成了随机。
  final int sortOrder;

  /// 每次检索的结果数（SET-040：默认 10，范围 1–20）。
  final int maxResults;

  /// 单次检索超时（SET-040：默认 20 秒，范围 5–60）。
  final int timeoutSeconds;

  /// 是否已显式批准该端点指向内网/明文 HTTP（SET-041）。
  ///
  /// 默认 false：自建 SearXNG 常挂在局域网地址上（http://192.168.x.x:8080），
  /// 默认拒绝私网会让这类真实用法完全不可用；但**默认放行**又会让一个被误导的用户
  /// 把查询发到本机某个不该被访问的端口。因此这一项必须由用户逐端点显式打开，
  /// 打开的事实落在记录里（而不是靠一个全局开关，全局开关无法表达「只批准这一个」）。
  final bool allowPrivateEndpoint;

  /// 是否为任务默认搜索服务（本机唯一）。
  final bool isDefaultForTasks;

  /// 创建时间（UTC）。
  final DateTime? createdAt;

  /// 最后更新时间（UTC）。
  final DateTime? updatedAt;

  /// 凭据标识（SET-039）：同名字的服务共用一份凭据，且与 AI 凭据分属不同类别。
  ///
  /// 按**名字**定位而不是按自增 id：名字是用户可见的稳定标识，而 id 在导出/导入后
  /// 可能变化（与 AiModel.credentialIdentifier 同一理由）。
  String get credentialIdentifier => label;

  /// 实际请求的端点。
  Uri get endpoint => protocol.endpointFor(baseUrl);

  /// 复制并覆盖部分字段。
  SearchService copyWith({
    int? id,
    String? label,
    SearchProtocol? protocol,
    String? baseUrl,
    bool? enabled,
    int? sortOrder,
    int? maxResults,
    int? timeoutSeconds,
    bool? allowPrivateEndpoint,
    bool? isDefaultForTasks,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => SearchService(
    id: id ?? this.id,
    label: label ?? this.label,
    protocol: protocol ?? this.protocol,
    baseUrl: baseUrl ?? this.baseUrl,
    enabled: enabled ?? this.enabled,
    sortOrder: sortOrder ?? this.sortOrder,
    maxResults: maxResults ?? this.maxResults,
    timeoutSeconds: timeoutSeconds ?? this.timeoutSeconds,
    allowPrivateEndpoint: allowPrivateEndpoint ?? this.allowPrivateEndpoint,
    isDefaultForTasks: isDefaultForTasks ?? this.isDefaultForTasks,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  @override
  String toString() =>
      'SearchService(id=$id, label=$label, protocol=${protocol.id}, '
      'enabled=$enabled, sort=$sortOrder, '
      'allowPrivate=$allowPrivateEndpoint)';
}

/// SET-040 的默认结果数。
const int kSearchDefaultMaxResults = 10;

/// SET-040 的默认超时（秒）。
const int kSearchDefaultTimeoutSeconds = 20;

/// SET-040 的结果数范围。
const int kSearchMinResults = 1;
const int kSearchMaxResults = 20;

/// SET-040 的超时范围（秒）。
const int kSearchMinTimeoutSeconds = 5;
const int kSearchMaxTimeoutSeconds = 60;

/// 名字长度上限。
const int kSearchLabelMaxLength = 64;

/// 查询词长度上限。
///
/// 为什么要有上限：查询词会被拼进 GET 查询串（Brave/SearXNG）。一个几 MB 的「查询」
/// 会让 URL 被服务端或中间件拒绝，也会把真实意图藏进一个不可能被人工核对的长串里。
/// 512 字符足够表达任何正常检索式。
const int kSearchQueryMaxLength = 512;

/// 校验一条搜索服务记录（SET-038/040/041 的取值域）。
///
/// 与 validateAiModel 同一条边界：这里**不**校验「凭据是否已配置」或「端点是否可达」
/// ——那是可用性问题，不是取值域问题；用户可以先配好一条记录，等拿到 Key 再启用。
Result<void> validateSearchService(SearchService service) {
  final Result<void> label = validateSearchLabel(service.label);
  if (label.isErr) {
    return label;
  }
  final Result<void> baseUrl = validateSearchBaseUrl(service.baseUrl);
  if (baseUrl.isErr) {
    return baseUrl;
  }
  if (service.maxResults < kSearchMinResults ||
      service.maxResults > kSearchMaxResults) {
    return Err<void>(
      ValidationError(
        field: 'SET-040.maxResults',
        reason: '结果数必须在 $kSearchMinResults–$kSearchMaxResults 之间',
        value: '${service.maxResults}',
      ),
    );
  }
  if (service.timeoutSeconds < kSearchMinTimeoutSeconds ||
      service.timeoutSeconds > kSearchMaxTimeoutSeconds) {
    return Err<void>(
      ValidationError(
        field: 'SET-040.timeoutSeconds',
        reason:
            '超时必须在 '
            '$kSearchMinTimeoutSeconds–$kSearchMaxTimeoutSeconds 秒之间',
        value: '${service.timeoutSeconds}',
      ),
    );
  }
  return okUnit();
}

/// 校验服务名字（非空、长度上限、不含控制字符）。
///
/// 名字会写进 Keychain 条目与诊断日志，因此不允许控制字符：换行会让一条日志伪造出
/// 多行，污染解析与人工阅读（与 validateAiModelAlias 同一条判据）。
Result<void> validateSearchLabel(String label) {
  final String trimmed = label.trim();
  if (trimmed.isEmpty) {
    return Err<void>(
      ValidationError(field: 'SET-038.label', reason: '服务名不能为空'),
    );
  }
  if (trimmed.length > kSearchLabelMaxLength) {
    return Err<void>(
      ValidationError(
        field: 'SET-038.label',
        reason: '服务名过长（上限 $kSearchLabelMaxLength）',
        value: '${trimmed.length}',
      ),
    );
  }
  if (RegExp(r'[\x00-\x1F\x7F]').hasMatch(trimmed)) {
    return Err<void>(
      ValidationError(field: 'SET-038.label', reason: '服务名不能包含控制字符'),
    );
  }
  return okUnit();
}

/// 校验 Base URL。
///
/// 只接受 http/https 且必须有主机：file:// 或空主机在这里就被拒绝，而不是等到
/// 发请求时由地址守卫报一个更难理解的错误（架构第 8 节的出网边界在**配置入口**
/// 先拦一道；DNS 解析与私网判定仍由发送前的守卫负责）。
Result<void> validateSearchBaseUrl(String baseUrl) {
  final String trimmed = baseUrl.trim();
  if (trimmed.isEmpty) {
    return Err<void>(
      ValidationError(
        field: 'SET-038.baseUrl',
        reason: '端点地址不能为空（自建 SearXNG 需要填写实例地址）',
      ),
    );
  }
  final Uri? uri = Uri.tryParse(trimmed);
  if (uri == null || !uri.hasScheme) {
    return Err<void>(
      ValidationError(field: 'SET-038.baseUrl', reason: '端点必须是完整地址'),
    );
  }
  if (uri.scheme != 'http' && uri.scheme != 'https') {
    return Err<void>(
      ValidationError(
        field: 'SET-038.baseUrl',
        reason: '只允许 http/https',
        value: uri.scheme,
      ),
    );
  }
  if (uri.host.isEmpty) {
    return Err<void>(
      ValidationError(field: 'SET-038.baseUrl', reason: '端点缺少主机名'),
    );
  }
  return okUnit();
}

/// 校验查询词（非空、长度上限）。
Result<void> validateSearchQueryText(String query) {
  final String trimmed = query.trim();
  if (trimmed.isEmpty) {
    return Err<void>(ValidationError(field: 'query', reason: '查询词不能为空'));
  }
  if (trimmed.length > kSearchQueryMaxLength) {
    return Err<void>(
      ValidationError(
        field: 'query',
        reason: '查询词过长（上限 $kSearchQueryMaxLength）',
        value: '${trimmed.length}',
      ),
    );
  }
  return okUnit();
}
