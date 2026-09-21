// Flux 脱敏工具（T007）。
//
// 目标（架构第 8 节、SET-082 诊断）：任何进入异常消息、日志或诊断包的文本
// 都不应包含 API Key、Bearer token 或 URL query 中的秘密参数。
//
// 策略是“宁可多遮，不可漏遮”：遮盖会让诊断信息略少，漏遮会泄漏用户凭据，
// 两者代价不对称，所以宁可对可疑的长随机串也做遮盖。
library;

/// 文本脱敏工具集。
///
/// 所有方法都是无 I/O、无 Flutter 依赖的纯函数，可在纯 Dart 测试中直接调用。
abstract final class SecretRedaction {
  /// 被遮盖部分的统一占位符。
  static const String masked = '***';

  /// 无论出现在哪种语境都视为秘密的参数名（比较时统一转小写）。
  static const Set<String> sensitiveNames = <String>{
    'token',
    'access_token',
    'access-token',
    'refresh_token',
    'refresh-token',
    'id_token',
    'api_key',
    'api-key',
    'apikey',
    'x-api-key',
    'secret',
    'client_secret',
    'client-secret',
    'secret_key',
    'private_key',
    'password',
    'passwd',
    'pwd',
    'signature',
    'sig',
    'authorization',
    'credential',
    'credentials',
    'cookie',
    'session',
    'sessionid',
    'session_id',
  };

  /// 只在 URL query/fragment 语境下视为秘密的参数名。
  ///
  /// 这些名字（例如 `key`、`code`）在普通文本里可能只是业务词，但在订阅地址
  /// 和回调 URL 里经常承载凭据，因此在 URL 中一并遮盖。
  static const Set<String> sensitiveUrlParamNames = <String>{
    'key',
    'code',
    'auth',
    'p',
    't',
    'hash',
    'pass',
  };

  /// 匹配 `scheme://...` 形式的 URL。
  static final RegExp _urlPattern = RegExp(
    r'''[A-Za-z][A-Za-z0-9+.-]*://[^\s<>"'`]+''',
  );

  /// 匹配 `Bearer <credential>`。
  ///
  /// 注意：Dart 的 RegExp 基于 ECMAScript，**不支持** `(?i)` 内联标志
  /// （运行时会抛 "Invalid group"），大小写不敏感必须用 [caseSensitive] 表达。
  /// 单位是**字节**而非 UTF-16 码元，与 Dart 的 `RegExp` 语义一致。
  static final RegExp _bearerPattern = RegExp(
    r'bearer\s+[A-Za-z0-9._~+/=\-]{4,}',
    caseSensitive: false,
  );

  /// 匹配常见前缀的凭据串（OpenAI `sk-`、Slack `xox*`、GitHub `ghp_`、AWS `AKIA`）。
  static final RegExp _credentialPattern = RegExp(
    r'\b(sk|xoxb|xoxp|xoxa|ghp|gho|glpat|AKIA)[-_]?[A-Za-z0-9_\-]{6,}',
  );

  /// 匹配 `name=value` / `name: value` 到行尾，用于遮盖敏感参数。
  ///
  /// 值取到行尾而不是第一个空白，是为了完整遮盖多词值——例如
  /// `Authorization: Bearer <token>` 的凭据在第二个词上，只吃第一个词会把
  /// token 留在消息里。代价是敏感参数后面的非敏感内容也变成 `***`；
  /// 在“漏遮凭据”与“日志略少”之间，这里明确选择前者。
  static final RegExp _pairPattern = RegExp(
    '([A-Za-z][A-Za-z0-9_\\-]*)(\\s*[:=]\\s*)([^\\r\\n]*)',
  );

  /// 匹配 URL 中的 userinfo（`user:pass@`）。
  static final RegExp _userInfoPattern = RegExp(r'://[^/@\s]*@');

  /// 判断参数名是否属于需要遮盖的秘密名。
  ///
  /// [inUrl] 为 true 时会额外匹配 [sensitiveUrlParamNames]。
  static bool isSensitiveName(String name, {required bool inUrl}) {
    final String normalized = name.trim().toLowerCase();
    if (sensitiveNames.contains(normalized)) {
      return true;
    }
    if (inUrl && sensitiveUrlParamNames.contains(normalized)) {
      return true;
    }
    // 形如 `?some_token=`、`?x-apikey=` 的变体也按秘密处理。
    if (inUrl) {
      for (final String marker in <String>[
        'token',
        'secret',
        'apikey',
        'api_key',
        'password',
        'auth',
        'sig',
      ]) {
        if (normalized.contains(marker)) {
          return true;
        }
      }
    }
    return false;
  }

  /// 对任意文本脱敏；`null` 或空串返回空串。
  ///
  /// 处理顺序刻意如此（顺序会影响结果）：
  /// 1. `Bearer <credential>` —— 必须最先，否则后续 `name=value` 规则只会吃掉
  ///    头名后的第一个词 `Bearer`，把真正的 token 留在消息里；
  /// 2. 常见凭据前缀（`sk-`/`ghp_`/`xoxb`/`AKIA`）—— 无参数名的裸凭据；
  /// 3. URL —— 按参数名与熵遮盖 query，并清掉 userinfo；
  /// 4. `name=value` —— 处理剩下的敏感参数（此时秘密多已被替换为 `***`）。
  static String redact(String? input) {
    if (input == null || input.isEmpty) {
      return '';
    }
    String output = input.replaceAllMapped(
      _bearerPattern,
      (Match match) => 'Bearer $masked',
    );
    output = output.replaceAllMapped(
      _credentialPattern,
      (Match match) => masked,
    );
    output = output.replaceAllMapped(
      _urlPattern,
      (Match match) => sanitizeUrlString(match[0]!),
    );
    output = output.replaceAllMapped(_pairPattern, (Match match) {
      final String name = match[1]!;
      if (!isSensitiveName(name, inUrl: false)) {
        return match[0]!;
      }
      return '$name${match[2]}$masked';
    });
    return output;
  }

  /// 遮盖 URL 中的秘密参数并移除 userinfo，返回可安全写入日志的字符串。
  ///
  /// 不改变 scheme/host/path，便于定位问题；query 中命中敏感名或看起来像随机
  /// 凭据的值变为 `***`。
  static String sanitizeUrlString(String url) {
    final String trimmed = url.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    final int fragmentIndex = trimmed.indexOf('#');
    final String head = fragmentIndex < 0
        ? trimmed
        : trimmed.substring(0, fragmentIndex);
    final String fragment = fragmentIndex < 0
        ? ''
        : trimmed.substring(fragmentIndex);

    String sanitized = head.replaceFirst(_userInfoPattern, '://$masked@');
    final int queryIndex = sanitized.indexOf('?');
    String suffix = fragment;
    if (queryIndex >= 0) {
      final String base = sanitized.substring(0, queryIndex);
      final String query = sanitized.substring(queryIndex + 1);
      final Iterable<String> parts = query
          .split('&')
          .map(_sanitizeQueryPart)
          .where((String part) => part.isNotEmpty);
      sanitized = '$base?${parts.join('&')}';
    }
    if (suffix.isNotEmpty) {
      suffix = suffix.replaceAllMapped(_pairPattern, (Match match) {
        final String name = match[1]!;
        if (!isSensitiveName(name, inUrl: true)) {
          return match[0]!;
        }
        return '$name${match[2]}$masked';
      });
    }
    return '$sanitized$suffix';
  }

  /// 返回已脱敏的 [uri]，用于把端点存进错误对象前先去掉凭据。
  static Uri sanitizeUri(Uri uri) {
    final String sanitized = sanitizeUrlString(uri.toString());
    return Uri.parse(sanitized);
  }

  /// 判断一个值是否“看起来像随机凭据”：长度不短、不含空白、字符集受限。
  static bool looksLikeSecretValue(String value) {
    if (value.length < 20) {
      return false;
    }
    if (RegExp(r'\s').hasMatch(value)) {
      return false;
    }
    return RegExp(r'^[A-Za-z0-9+/_\-=.%]+$').hasMatch(value);
  }

  static String _sanitizeQueryPart(String part) {
    final int equalsIndex = part.indexOf('=');
    if (equalsIndex < 0) {
      return looksLikeSecretValue(part) ? masked : part;
    }
    final String name = part.substring(0, equalsIndex);
    final String value = part.substring(equalsIndex + 1);
    if (value.isEmpty) {
      return part;
    }
    if (isSensitiveName(name, inUrl: true) || looksLikeSecretValue(value)) {
      return '$name=$masked';
    }
    return part;
  }
}
