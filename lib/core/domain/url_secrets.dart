// 订阅地址里的秘密参数处理（T015；架构 5.2、SET-027）。
//
// 背景：架构 4.1 明确要求「不随意剥离 URL 查询参数」——很多源用查询参数承载真实内容
// 标识（文章 id、分类），剥掉会让地址失效。但架构 5.2 同时要求「若 URL 含 token 或
// 认证，将秘密拆为本机凭据引用……不能把完整私密 URL 放入快照」。两条规则的交集是：
//
//   **只有明确的秘密参数名才被移除，其余参数一律保留。**
//
// 为什么是「移除」而不是像日志那样替换成 ***：导出文件是给别的阅读器读的，
// `xmlUrl="https://host/feed.xml?token=***"` 是一个无法工作的地址，用户导入后会得到
// 一个永远失败的订阅，而界面上看不出原因。移除参数后地址仍是合法 URL，用户按提示
// 在目标设备补填凭据即可——这正是架构 5.2 描述的流程。
//
// 为什么判定用 SecretRedaction.isSensitiveName：秘密参数名的清单必须只有一处
// （日志脱敏、同步投影、导出共用），否则「日志里遮了但导出没遮」这类漏洞迟早出现。
library;

import '../error/secret_redaction.dart';

/// 「userinfo 里的凭据」在 [UrlSecretStripResult.removed] 里的标记名。
///
/// 用带方括号的伪参数名而不是 `user`/`password`：它是**位置**而不是查询参数，
/// 界面据此提示的文案不同（「地址里的账号密码」而不是「地址参数 x」），而把两者
/// 混成同一个名字会让提示指向用户在地址里找不到的东西。
const String userInfoSecretParam = '[userinfo]';

/// 一次秘密参数剥离的结果。
class UrlSecretStripResult {
  /// 构造结果。
  const UrlSecretStripResult({required this.url, required this.removed});

  /// 处理后的地址（无可剥离参数时与原值相同）。
  final String url;

  /// 被移除的参数名（去重，按出现顺序）。
  ///
  /// 只保留**参数名**，不含值：这个结果会被界面用来提示「有 N 个地址的凭据未导出」，
  /// 若把值也带出来，就等于把秘密又搬到了另一条路径上。
  final List<String> removed;

  /// 是否发生了剥离。
  bool get changed => removed.isNotEmpty;
}

/// 移除地址里明确的秘密查询参数。
///
/// 只处理 http(s) 地址；无法解析或非 http(s) 时原样返回——那种地址本来也不该被
/// 导出（导入侧会拒绝），在这里猜测它的结构只会制造更多不确定性。
UrlSecretStripResult stripUrlSecrets(String raw) {
  final String trimmed = raw.trim();
  final Uri? uri = Uri.tryParse(trimmed);
  if (uri == null || (!uri.isScheme('http') && !uri.isScheme('https'))) {
    return UrlSecretStripResult(url: trimmed, removed: const <String>[]);
  }

  final List<String> removed = <String>[];
  final List<MapEntry<String, String>> kept = <MapEntry<String, String>>[];
  for (final MapEntry<String, List<String>> param
      in uri.queryParametersAll.entries) {
    if (SecretRedaction.isSensitiveName(param.key, inUrl: true)) {
      if (!removed.contains(param.key)) {
        removed.add(param.key);
      }
      continue;
    }
    // 同名多值：每个值各留一条，顺序保持原样。
    for (final String value in param.value) {
      kept.add(MapEntry<String, String>(param.key, value));
    }
  }

  // userinfo 是明文凭据（`https://user:pass@host/...`），必须单独判定：它不在
  // 查询串里，因此上面的循环看不到它，而「没有查询串」的地址同样可能有 userinfo。
  final bool hadUserInfo = uri.userInfo.isNotEmpty;
  if (hadUserInfo) {
    removed.add(userInfoSecretParam);
  }

  if (removed.isEmpty) {
    // 一个都没命中：返回**原字符串**而不是重建的 URI。重建会顺手改变编码形式
    // （例如 %2F 变成 %2f），让「没有改变」这个事实变得不精确。
    return UrlSecretStripResult(url: trimmed, removed: const <String>[]);
  }

  // 必须用 Uri 构造器重建，不能用 uri.replace(query: ...)：在 Dart 里
  // replace 的 query 为 null 表示「保持原值不变」（实测：token 仍留在结果里），
  // 而 query 为空串会留下一个尾随的问号。构造器把 query 为 null 表达为「没有
  // 查询串」，与 T013 的链接规范化用的是同一条路径。
  //
  // 重建时**不传 userInfo**（构造器里根本没有这个参数位置被赋值），因此上面的
  // `user:pass` 不会出现在结果里：重新构造即丢弃。
  final Uri cleaned = Uri(
    scheme: uri.scheme,
    // 有意为 null：见上面的说明。
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
    path: uri.path,
    query: kept.isEmpty
        ? null
        : kept
              .map(
                (MapEntry<String, String> e) =>
                    '${Uri.encodeQueryComponent(e.key)}='
                    '${Uri.encodeQueryComponent(e.value)}',
              )
              .join('&'),
    fragment: uri.hasFragment ? uri.fragment : null,
  );
  return UrlSecretStripResult(url: cleaned.toString(), removed: removed);
}
