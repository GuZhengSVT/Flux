// AI 模型记录（T025；架构 5.1 的 AIProvider / Model 实体、SET-030/032/033）。
//
// 一条记录代表「一个可以被调用的模型」，字段按 SET 编号归口：
//   SET-030 提供商预设/协议/Base URL/别名 → [preset] / [protocol] / [baseUrl] / [alias]
//   SET-032 模型 ID/启用/排序/删除       → [modelId] / [enabled] / [sortOrder]
//   SET-033 能力与上下文/输出上限        → [capability]
//
// **凭据不在记录里**：SET-031 是秘密项，记录只持有 [credentialIdentifier]
// （提供商标识别名）。真正取值走 features 侧的 AiCredentialStore 端口，由组合根
// 接到 Keychain 上；数据库列里没有任何 Key 字段（架构 5.1「数据库不含秘密」、第 8 节）。
library;

import 'package:flux/core/core.dart';

import 'ai_protocol.dart';
import 'model_capability.dart';

/// 一个模型记录。
final class AiModel {
  /// 构造模型记录。
  const AiModel({
    this.id,
    required this.alias,
    this.preset,
    required this.protocol,
    required this.baseUrl,
    required this.modelId,
    this.enabled = true,
    this.sortOrder = 0,
    this.capability = const ModelCapability(),
    this.isDefaultForTasks = false,
    this.createdAt,
    this.updatedAt,
  });

  /// 本机自增 id；尚未落库时为 null。
  final int? id;

  /// 提供商别名（本机唯一，用户在 UI 里看到的名字）。
  final String alias;

  /// 预设名（例如 `deepseek`、`openai`）；自定义时为 null。
  final String? preset;

  /// 协议。
  final AiProtocol protocol;

  /// Base URL（不含协议路径，例如 `https://api.deepseek.com`）。
  final String baseUrl;

  /// 服务商侧的模型 ID（例如 `deepseek-chat`）。
  final String modelId;

  /// 是否启用（SET-032 的启用列；禁用后不参与故障转移）。
  final bool enabled;

  /// 故障转移顺序（升序；相同顺序按 id 稳定排序）。
  ///
  /// 用**显式序号**而不是「列表位置」：列表位置是查询结果的顺序，用户拖动一次若没有
  /// 持久化序号，重启后会回到插入顺序，「依排序故障转移」（SET-032）就变成了随机。
  final int sortOrder;

  /// 能力声明（SET-033）。
  final ModelCapability capability;

  /// 是否为任务默认模型（本机「首选」，供 T029/T034 的默认路由使用）。
  ///
  /// 单独一个布尔值而不是「排序第一」：用户可能希望某模型排在前面（例如先试一个
  /// 便宜的小模型做翻译），但**不**希望它成为每日总结的默认承担者。两者混为一谈
  /// 会让「调整顺序」意外改变计费主体。
  final bool isDefaultForTasks;

  /// 创建时间（UTC）。
  final DateTime? createdAt;

  /// 最后更新时间（UTC）。
  final DateTime? updatedAt;

  /// 凭据标识（SET-031）：同别名的模型共用一份凭据。
  ///
  /// 按**别名**定位而不是按自增 id：别名是用户可见的稳定标识，而 id 在导出/导入
  /// 后可能变化；按 id 存会让「恢复备份 + 重新导入」之后凭据找不到自己的记录。
  String get credentialIdentifier => alias;

  /// 复制并覆盖部分字段。
  AiModel copyWith({
    int? id,
    String? alias,
    String? preset,
    bool clearPreset = false,
    AiProtocol? protocol,
    String? baseUrl,
    String? modelId,
    bool? enabled,
    int? sortOrder,
    ModelCapability? capability,
    bool? isDefaultForTasks,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => AiModel(
    id: id ?? this.id,
    alias: alias ?? this.alias,
    preset: clearPreset ? null : (preset ?? this.preset),
    protocol: protocol ?? this.protocol,
    baseUrl: baseUrl ?? this.baseUrl,
    modelId: modelId ?? this.modelId,
    enabled: enabled ?? this.enabled,
    sortOrder: sortOrder ?? this.sortOrder,
    capability: capability ?? this.capability,
    isDefaultForTasks: isDefaultForTasks ?? this.isDefaultForTasks,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  @override
  String toString() =>
      'AiModel(id=$id, alias=$alias, protocol=${protocol.id}, '
      'model=$modelId, enabled=$enabled, sort=$sortOrder)';
}

/// 别名的长度上限。
const int aiModelAliasMaxLength = 64;

/// 模型 ID 的长度上限。
const int aiModelIdMaxLength = 128;

/// 校验一条模型记录（SET-030/032/033 的取值域）。
///
/// 这里**不**校验协议是否有适配器：那是可用性问题，不是取值域问题。用户可以先配好
/// 一条 Anthropic 记录，等 T027 落地后启用；把它当成非法会阻止用户提前配置。
Result<void> validateAiModel(AiModel model) {
  final Result<void> alias = validateAiModelAlias(model.alias);
  if (alias.isErr) {
    return alias;
  }
  final Result<void> modelId = validateAiModelId(model.modelId);
  if (modelId.isErr) {
    return modelId;
  }
  final Result<void> baseUrl = validateAiBaseUrl(model.baseUrl);
  if (baseUrl.isErr) {
    return baseUrl;
  }
  return validateCapability('SET-033', model.capability);
}

/// 校验提供商别名（非空、长度上限、不含控制字符）。
///
/// 别名会写进 Keychain 条目、诊断日志与（将来的）同步包，因此不允许控制字符：
/// 换行会让一条日志伪造出多行，污染解析与人工阅读。
Result<void> validateAiModelAlias(String alias) {
  final String trimmed = alias.trim();
  if (trimmed.isEmpty) {
    return Err<void>(ValidationError(field: 'SET-030.alias', reason: '别名不能为空'));
  }
  if (trimmed.length > aiModelAliasMaxLength) {
    return Err<void>(
      ValidationError(
        field: 'SET-030.alias',
        reason: '别名过长（上限 $aiModelAliasMaxLength）',
        value: '${trimmed.length}',
      ),
    );
  }
  if (RegExp(r'[\x00-\x1F\x7F]').hasMatch(trimmed)) {
    return Err<void>(
      ValidationError(field: 'SET-030.alias', reason: '别名不能包含控制字符'),
    );
  }
  return okUnit();
}

/// 校验模型 ID（非空、长度上限、无空白）。
///
/// 不允许空白字符：模型 ID 会原样进请求体与诊断日志，含空白的值几乎总是复制粘贴
/// 时多带了一个换行，而不是服务商真的支持这样名字的模型。
Result<void> validateAiModelId(String modelId) {
  final String trimmed = modelId.trim();
  if (trimmed.isEmpty) {
    return Err<void>(
      ValidationError(field: 'SET-032.modelId', reason: '模型 ID 不能为空'),
    );
  }
  if (trimmed.length > aiModelIdMaxLength) {
    return Err<void>(
      ValidationError(
        field: 'SET-032.modelId',
        reason: '模型 ID 过长（上限 $aiModelIdMaxLength）',
      ),
    );
  }
  if (RegExp(r'\s').hasMatch(trimmed)) {
    return Err<void>(
      ValidationError(field: 'SET-032.modelId', reason: '模型 ID 不能包含空白字符'),
    );
  }
  return okUnit();
}

/// 校验 Base URL。
///
/// 只接受 http/https 且必须有主机：`file://`、`ftp://` 或空主机在这里就被拒绝，
/// 而不是等到发请求时由 URL 守卫报一个更难理解的错误（架构第 8 节的出网边界在
/// **配置入口**先拦一道；DNS 解析与私网判定仍由发送前的守卫负责）。
Result<void> validateAiBaseUrl(String baseUrl) {
  final String trimmed = baseUrl.trim();
  if (trimmed.isEmpty) {
    return Err<void>(
      ValidationError(field: 'SET-030.baseUrl', reason: 'Base URL 不能为空'),
    );
  }
  final Uri? uri = Uri.tryParse(trimmed);
  if (uri == null || !uri.hasScheme) {
    return Err<void>(
      ValidationError(field: 'SET-030.baseUrl', reason: 'Base URL 必须是完整地址'),
    );
  }
  if (uri.scheme != 'http' && uri.scheme != 'https') {
    return Err<void>(
      ValidationError(
        field: 'SET-030.baseUrl',
        reason: '只允许 http/https',
        value: uri.scheme,
      ),
    );
  }
  if (uri.host.isEmpty) {
    return Err<void>(
      ValidationError(field: 'SET-030.baseUrl', reason: 'Base URL 缺少主机名'),
    );
  }
  return okUnit();
}

/// 拼接出协议端点（例如 `https://api.deepseek.com/chat/completions`）。
///
/// 处理三种用户会实际写出来的 Base URL：无尾斜杠、有尾斜杠、以及**已经带了路径**
/// （例如 `https://host/openai/v1`）。第三种应得到 `/openai/v1/chat/completions`，
/// 因此这里只做规范化：去掉末尾斜杠后追加协议路径，不改写已有路径段。
Uri aiEndpointFor(String baseUrl, AiProtocol protocol) {
  final String trimmed = baseUrl.trim();
  final String withoutTrailingSlash = trimmed.endsWith('/')
      ? trimmed.substring(0, trimmed.length - 1)
      : trimmed;
  return Uri.parse('$withoutTrailingSlash/${protocol.path}');
}
