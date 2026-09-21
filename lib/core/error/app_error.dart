// Flux 类型化错误体系（T007，架构第 2.2 节与第 8 节）。
//
// 设计要点：
// - 用 Dart 3 `sealed class`，使 `switch` 在编译器帮助下穷尽所有错误类型；
// - 错误层级不依赖 Flutter、Drift、HTTP 等具体包，domain/application 可以安全
//   依赖它，而 infrastructure 负责把底层异常翻译成本层错误；
// - 所有 `message` 都经过 SecretRedaction，异常在向上传播的途中不会被顺手
//   打进日志而泄漏 API Key 或 URL 里的 token（SET-082 诊断约束）。
library;

import '../error/secret_redaction.dart';

/// 所有 Flux 可预期错误的基类。
///
/// 这是“业务可恢复/可解释”的错误通道；编程错误（例如断言失败、状态错误）仍用
/// Flutter/Dart 自身的异常，不混入这里，避免把 bug 伪装成用户可见状态。
sealed class AppError implements Exception {
  /// 保护构造：外部只能通过具体子类创建错误。
  AppError(
    String message, {
    this.cause,
    this.stackTrace,
    this.isRetryable = false,
  }) : message = SecretRedaction.redact(message);

  /// 面向日志与诊断的脱敏描述；可直接写入日志。
  ///
  /// 不是给最终用户看的文案——UI 文案走 l10n 资源（T011 之后），这里只保证
  /// 同一错误类型在日志、测试断言、诊断包中有一致且安全的表示。
  final String message;

  /// 触发该错误的底层原因（通常是原始异常对象）。
  ///
  /// 不参与 `toString()` 的默认输出，避免底层对象自带的凭据泄漏；
  /// 需要时由诊断层显式处理。
  final Object? cause;

  /// 原始栈；只在确有排查价值时保留。
  final StackTrace? stackTrace;

  /// 该错误是否值得原样重试（不改变输入）。
  ///
  /// 例如网络超时可重试；校验失败、预算耗尽不可通过重试解决。
  /// 预算/取消这类错误即使可重试也需上层显式决策，不能自动无限重试。
  final bool isRetryable;

  /// 稳定的错误类别标识，用于测试与统计，不用来匹配文案。
  String get kind;

  /// 可安全写入日志/诊断的单行表示。
  String toLogString() {
    final String buffer = cause == null ? '' : ' cause=${cause.runtimeType}';
    return '${runtimeType.toString()}(kind=$kind, retryable=$isRetryable, '
        'message=$message)$buffer';
  }

  @override
  String toString() => toLogString();
}

/// 网络层错误：DNS、连接、TLS、超时、非 2xx 响应等。
final class NetworkError extends AppError {
  /// [uri] 会先脱敏再保存，因此可以在错误里安全携带出错的地址。
  NetworkError({
    required this.uri,
    this.statusCode,
    String? reason,
    super.cause,
    super.stackTrace,
    super.isRetryable = true,
  }) : super(
         '网络请求失败：${SecretRedaction.sanitizeUrlString(uri)}'
         '${statusCode == null ? '' : ' (HTTP $statusCode)'}'
         '${reason == null || reason.isEmpty ? '' : ' — $reason'}',
       );

  /// 已脱敏的请求地址。
  final String uri;

  /// HTTP 状态码；连接层失败（未收到响应）时为 null。
  final int? statusCode;

  @override
  String get kind => 'network';

  /// 5xx 与 429 值得稍后重试；4xx 通常是配置/权限问题。
  bool get isServerSideFailure =>
      statusCode == null || statusCode! >= 500 || statusCode == 429;
}

/// 本地存储错误：SQLite/Drift 失败、文件读写失败、磁盘空间不足等。
///
/// 只描述操作本身，不携带正文或凭据内容。
final class StorageError extends AppError {
  StorageError({
    required this.operation,
    String? detail,
    this.isMissing = false,
    super.cause,
    super.stackTrace,
    super.isRetryable = false,
  }) : super(
         '存储操作失败：$operation'
         '${detail == null || detail.isEmpty ? '' : ' — $detail'}',
       );

  /// 失败的操作名，例如 `openDatabase`、`insertArticle`。
  final String operation;

  /// 目标是否不存在（区别于“存在但读取失败”）。
  final bool isMissing;

  @override
  String get kind => 'storage';
}

/// 解析错误：RSS/Atom 异常 XML、Markdown/HTML 结构非法、AI 返回非法 JSON 等。
///
/// **安全约束**：[detail] 只能是结构性描述（标签名、行列、期望类型），不能把
/// 原始正文或响应体整段塞进来；[source] 只放来源标识（如 feed id、`chat.completions`）。
final class ParseError extends AppError {
  ParseError({
    required this.source,
    required this.detail,
    this.offset,
    super.cause,
    super.stackTrace,
  }) : super('解析失败：$source${offset == null ? '' : ' @$offset'} — $detail');

  /// 来源标识，例如 `feed:12`、`opml`、`ai.result`。
  final String source;

  /// 结构性描述；不允许包含完整原始文档。
  final String detail;

  /// 出错位置（字符偏移）；未知为 null。
  final int? offset;

  @override
  String get kind => 'parse';
}

/// 取消错误：用户主动取消、页面销毁、上层替换了新的请求。
///
/// 取消不是失败，UI 应回到稳定态而非报错；保留类型化对象是为了让上层能精确
/// 区分“被取消”和“真的失败”。
final class CancelledError extends AppError {
  CancelledError({String? reason, super.stackTrace})
    : super(
        '操作已取消'
        '${reason == null || reason.isEmpty ? '' : ' — $reason'}',
      );

  @override
  String get kind => 'cancelled';
}

/// 预算耗尽：调用前检查发现会超出任务/当天额度（SET-059/063/064 等）。
///
/// [consumed] 与 [limit] 用同一计量单位（Token 数、次数或秒数），由调用方说明。
final class BudgetExhaustedError extends AppError {
  BudgetExhaustedError({
    required this.limitKind,
    required this.limit,
    required this.consumed,
    String? detail,
  }) : assert(limit >= 0, 'limit 不能为负'),
       assert(consumed >= 0, 'consumed 不能为负'),
       super(
         '预算已耗尽：$limitKind 已用 $consumed / 上限 $limit'
         '${detail == null || detail.isEmpty ? '' : ' — $detail'}',
       );

  /// 预算类别，例如 `totalMinutes`、`tokens`、`dailySummaryTasks`。
  final String limitKind;

  /// 额度上限。
  final int limit;

  /// 已消耗量。
  final int consumed;

  /// 剩余可用量（不会小于 0，便于 UI 直接显示）。
  int get remaining => consumed >= limit ? 0 : limit - consumed;

  @override
  String get kind => 'budgetExhausted';
}

/// 超时错误：任务/请求超过了约定时限（SET-059 总时限、SET-036 单次超时等）。
final class DeadlineExceededError extends AppError {
  DeadlineExceededError({
    required this.limitKind,
    required this.limit,
    this.elapsed,
  }) : assert(limit >= Duration.zero, 'limit 不能为负'),
       super(
         '超过时限：$limitKind 上限 ${limit.inMilliseconds}ms'
         '${elapsed == null ? '' : '，已用 ${elapsed.inMilliseconds}ms'}',
       );

  /// 时限类别，例如 `taskTotal`、`firstResponse`、`streamStall`。
  final String limitKind;

  /// 约定上限。
  final Duration limit;

  /// 实际耗时；未知为 null。
  final Duration? elapsed;

  @override
  String get kind => 'deadlineExceeded';
}

/// AI/搜索服务提供商返回的可解释错误。
///
/// [provider] 只放本机配置的别名/预设名，不放 Base URL 中的凭据；
/// [kind] 描述失败种类（认证失败、限流、内容拒绝、服务不可用等）。
final class ProviderError extends AppError {
  ProviderError({
    required this.provider,
    required this.kind,
    String? detail,
    this.statusCode,
    super.cause,
    super.stackTrace,
    super.isRetryable = false,
  }) : super(
         '服务调用失败：$provider/$kind'
         '${statusCode == null ? '' : ' (HTTP $statusCode)'}'
         '${detail == null || detail.isEmpty ? '' : ' — $detail'}',
       );

  /// 提供商别名，例如 `openai-main`、`anthropic`。
  final String provider;

  /// 失败种类标识，例如 `unauthorized`、`rateLimited`、`contentRefused`。
  @override
  final String kind;

  /// 响应状态码（若有）。
  final int? statusCode;
}

/// 数据校验错误：字段不符合取值域（读状态、设置范围、必填项缺失等）。
final class ValidationError extends AppError {
  ValidationError({required this.field, required this.reason, this.value})
    : super(
        '校验失败：$field — $reason'
        '${value == null ? '' : '（值为 $value）'}',
      );

  /// 字段名（设置 ID 或实体字段）。
  final String field;

  /// 失败原因。
  final String reason;

  /// 被拒绝的值；**调用方必须确保它本身不是秘密**。
  final String? value;

  @override
  String get kind => 'validation';
}

/// 任务状态机拒绝的迁移原因。
enum StateTransitionFailure {
  /// 迁移边不在合法迁移表内。
  illegalTransition,

  /// 源状态是终态，不允许再迁移。
  terminalStateImmutable,

  /// 试图把 deadline 推后（deadline 只允许保持不变或提前）。
  deadlineImmutable,

  /// 乐观并发冲突：调用方持有的 revision 已过期。
  concurrentModification,
}

/// 任务状态迁移被拒绝（T007 状态机）。
///
/// 这是“规则性拒绝”，不是崩溃：上层可据此决定是忽略、刷新快照重试，还是把
/// 冲突交给用户处理。因此一律以 [Result] 返回的类型化错误出现，而不是抛字符串。
final class StateTransitionError extends AppError {
  StateTransitionError({
    required this.failure,
    required this.from,
    required this.to,
    required this.taskId,
    String? detail,
  }) : super(
         '状态迁移被拒绝（$taskId）：${from.name} -> ${to.name}'
         '，原因 ${failure.name}'
         '${detail == null || detail.isEmpty ? '' : ' — $detail'}',
       );

  /// 拒绝原因。
  final StateTransitionFailure failure;

  /// 迁移前的状态（[TaskStatus] 或相同形态的枚举）。
  final Enum from;

  /// 被请求的目标状态。
  final Enum to;

  /// 相关任务 ID，便于把日志与具体任务对应。
  final String taskId;

  @override
  String get kind => 'stateTransition';
}

// ---------------------------------------------------------------------------
// AI / 服务商调用错误（T025）
// ---------------------------------------------------------------------------
//
// 为什么这四个子类住在 core 而不是 lib/features/ai：core 的 [AppError] 是
// **sealed** 类型，闭包里的子类必须与它同库（否则 sealed 的穷尽匹配能力就失去意义）。
// 它们描述的是「调用一个外部服务商失败」这类通用语义，与具体某家协议无关，因此放在
// core 是合适的归属。
//
// 为什么不能只复用 ProviderError(kind: ...)：上层对它们的**动作不同**，而且都不能靠
// 「换个模型重试」绕过：
//   - [RateLimitError]：可重试，且 429 可能带 Retry-After，重试前要等待；
//   - [AuthError]：不可重试，Key 错/余额不足，重试只会白花钱；
//   - [ContentFilteredError]：不可重试，也**不得跨服务商重试规避**（架构 4.5 明确写了
//     这一条：换一家的模型再问一遍是绕过审核，不是容错）。
// 若都塞进 ProviderError(kind: 'rateLimited') 这类字符串，任何一处漏判断字符串，就会
// 把「认证失败」当成「稍后重试」而无限重试、无限计费。
//
// 安全约束：[detail] 只放结构性描述（错误类型、状态码、服务商错误码），不放响应体
// 原文——响应体可能回显请求内容（架构第 8 节）。基类构造器还会对 message 再跑一遍脱敏。

/// 限流：服务商要求稍后重试（HTTP 429）。
final class RateLimitError extends AppError {
  /// 构造限流错误。
  RateLimitError({
    required this.provider,
    this.statusCode = 429,
    this.retryAfter,
    String? detail,
    super.cause,
    super.stackTrace,
  }) : super(
         '调用被限流：$provider'
         '${retryAfter == null ? '' : '，建议 ${retryAfter.inSeconds}s 后重试'}'
         '${detail == null || detail.isEmpty ? '' : ' — $detail'}',
         isRetryable: true,
       );

  /// 提供商别名（本机配置的别名，不是 Base URL）。
  final String provider;

  /// HTTP 状态码（通常 429）。
  final int? statusCode;

  /// 服务商建议的等待时长（来自 Retry-After 头）；未给出或无法解析时为 null。
  ///
  /// 只在**解析成功**时非 null：日期形式的 Retry-After 需要「现在」才能换算成时长，
  /// 适配器不持有可信时钟，因此这里不猜一个秒数，交上层按退避策略处理（架构 4.5 的
  /// 2/4/8/16 秒）。
  final Duration? retryAfter;

  @override
  String get kind => 'rateLimited';
}

/// 认证/授权失败：Key 缺失、错误、无权限或余额不足（HTTP 401/402/403）。
final class AuthError extends AppError {
  /// 构造认证错误。
  AuthError({
    required this.provider,
    this.statusCode,
    String? detail,
    super.cause,
    super.stackTrace,
  }) : super(
         '认证失败：$provider'
         '${statusCode == null ? '' : ' (HTTP $statusCode)'}'
         '${detail == null || detail.isEmpty ? '' : ' — $detail'}',
         // 不可重试：Key 不会因为再试一次而变对（架构 4.5「Key 错、余额不足、
         // 模型不存在，直接标记配置错误」）。
         isRetryable: false,
       );

  /// 提供商别名。
  final String provider;

  /// HTTP 状态码；未收到响应（例如本地发现 Key 缺失就直接拒绝）时为 null。
  final int? statusCode;

  @override
  String get kind => 'authentication';
}

/// 内容被拒绝：服务商的内容策略拦截了本次请求或输出（HTTP 400 content_filter 等）。
final class ContentFilteredError extends AppError {
  /// 构造内容拒绝错误。
  ContentFilteredError({
    required this.provider,
    this.statusCode,
    String? detail,
    super.cause,
    super.stackTrace,
  }) : super(
         '内容被服务商拒绝：$provider'
         '${statusCode == null ? '' : ' (HTTP $statusCode)'}'
         '${detail == null || detail.isEmpty ? '' : ' — $detail'}',
         isRetryable: false,
       );

  /// 提供商别名。
  final String provider;

  /// HTTP 状态码（通常 400）。
  final int? statusCode;

  @override
  String get kind => 'contentFiltered';
}

/// 模型仍被其他配置引用（T025：删除引用不悬空）。
///
/// 这是一个**需要用户决策**的结果，不是错误：引用存在时删除会让视觉路由或故障转移
/// 列表指向不存在的模型，因此先返回它、由界面展示「谁在用它」并提供明确确认；
/// 用户确认后带 force 再删。
///
/// 单独一个类型而不是 ValidationError：界面需要拿到 [referenceDescriptions] 才能说清
/// 「被哪里引用」，而从 ValidationError 里反解引用信息只能靠解析文案。
final class ModelInUseError extends AppError {
  /// 构造「仍被引用」错误。
  ModelInUseError({required this.alias, required this.referenceDescriptions})
    : super('模型 $alias 仍被引用：${referenceDescriptions.join('、')}');

  /// 被引用的模型别名。
  final String alias;

  /// 引用来源的稳定描述（$defaultForTasks、$visionModel(SET-034) 等）。
  final List<String> referenceDescriptions;

  @override
  String get kind => 'modelInUse';
}

/// 模型配置不可用（协议无适配器、Key 缺失、模型未启用等**配置层面**的拒绝）。
///
/// 与 [ProviderError] 的区别：这一类在**发出请求之前**就确定了，重试不会改变结果，
/// 界面的下一步动作是「去改配置」而不是「稍后重试」。
final class ModelConfigurationError extends AppError {
  /// 构造配置错误。
  ModelConfigurationError({
    required this.alias,
    required this.reason,
    String? detail,
  }) : super(
         '模型配置不可用：$alias — $reason'
         '${detail == null || detail.isEmpty ? '' : ' ($detail)'}',
       );

  /// 模型别名。
  final String alias;

  /// 结构性原因（例如 $adapterMissing、$credentialMissing、$disabled）。
  final String reason;

  @override
  String get kind => 'modelConfiguration';
}
