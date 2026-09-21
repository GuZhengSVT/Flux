// 搜索服务协议标识与认证方式（T031；架构 4.3 的「搜索协议」一行、SET-038/039）。
//
// 与 [AiProtocol] 同一个理由：协议是**显式枚举**，不是从地址猜出来的。
//   - Tavily 是 POST + JSON body，认证走 Authorization Bearer；
//   - Brave 是 GET + 查询参数，认证走 X-Subscription-Token 头；
//   - SearXNG 是自建实例的 GET + format=json，认证头可有可无（实例自配）。
// 三者的请求形状、响应形状与认证头**没有一处相同**，因此它们是三个独立适配器，
// 不能靠「改一个 URL」复用（架构 4.3 对 AI 协议的要求同样适用于搜索）。
//
// 为什么认证方式是协议的一部分而不是「用户填什么就是什么」：Brave 用 Bearer 发
// 一定会 401，Tavily 用 X-Subscription-Token 也一定失败。把认证写成协议属性之后，
// 适配器与界面展示的说明来自同一份数据，不会出现「界面写着 Bearer、代码发的是另一种」。
library;

/// 搜索服务的认证方式。
enum SearchAuthScheme {
  /// Authorization: Bearer（Tavily）。
  bearer,

  /// X-Subscription-Token（Brave Search）。
  braveSubscriptionToken,

  /// 可选认证（自建 SearXNG 可能由实例自己在反向代理层做认证）。
  ///
  /// 「可选」不等于「不需要」：真正需要 Key 的实例会返回 401/403，那时错误分类会
  /// 明确告诉用户去补凭据，而不是把一次认证失败说成网络问题。
  optionalBearer,
}

/// 一个搜索服务协议（请求形状 + 响应形状 + 认证方式的唯一标识）。
enum SearchProtocol {
  /// Tavily Search API（POST {base}/search）。
  tavily(
    id: 'tavily',
    label: 'Tavily',
    path: 'search',
    defaultBaseUrl: 'https://api.tavily.com',
    authScheme: SearchAuthScheme.bearer,
    requiresCredential: true,
    supportsOffset: false,
  ),

  /// Brave Search API（GET {base}/res/v1/web/search）。
  brave(
    id: 'brave',
    label: 'Brave Search',
    path: 'res/v1/web/search',
    defaultBaseUrl: 'https://api.search.brave.com',
    authScheme: SearchAuthScheme.braveSubscriptionToken,
    requiresCredential: true,
    supportsOffset: true,
  ),

  /// 自建 SearXNG 实例（GET {instance}/search?format=json）。
  ///
  /// 没有默认 Base URL：实例地址只有用户自己知道，替用户猜一个公网实例等于把查询
  /// 发给一个他没选过的第三方。
  searxng(
    id: 'searxng',
    label: 'SearXNG（自建实例）',
    path: 'search',
    defaultBaseUrl: '',
    authScheme: SearchAuthScheme.optionalBearer,
    requiresCredential: false,
    supportsOffset: false,
  );

  const SearchProtocol({
    required this.id,
    required this.label,
    required this.path,
    required this.defaultBaseUrl,
    required this.authScheme,
    required this.requiresCredential,
    required this.supportsOffset,
  });

  /// 稳定协议标识（落库、诊断、夹具名都用它；不改写）。
  final String id;

  /// 界面展示名（产品专有名词，中英一致）。
  final String label;

  /// 相对 Base URL 的请求路径（不含前导斜杠）。
  final String path;

  /// 预设 Base URL；空串表示「必须由用户填写」（SearXNG 自建实例）。
  final String defaultBaseUrl;

  /// 认证方式。
  final SearchAuthScheme authScheme;

  /// 是否必须有凭据才能调用。
  ///
  /// Tavily/Brave 没有 Key 一定失败，因此**在发出任何请求之前**就拒绝；SearXNG
  /// 由实例自行决定，因此允许无凭据调用（认证失败会作为类型化错误返回）。
  final bool requiresCredential;

  /// 协议是否支持 offset 分页。
  ///
  /// Tavily 的请求体没有 offset 字段，SearXNG 用 pageno 而不是 offset。两者都必须
  /// 显式声明「不支持」：静默忽略一个 offset 会让调用方以为拿到了第二页，实际却是
  /// 同一页的重复结果。
  final bool supportsOffset;

  /// 由稳定标识还原协议；未知标识返回 null（调用方据此报校验错误）。
  static SearchProtocol? fromId(String? id) {
    for (final SearchProtocol protocol in SearchProtocol.values) {
      if (protocol.id == id) {
        return protocol;
      }
    }
    return null;
  }

  /// 拼接出实际请求的端点（去尾斜杠后追加协议路径）。
  ///
  /// 与 AI 侧的 aiEndpointFor 同一口径：保留用户 Base URL 里已有的路径段
  /// （例如自建 SearXNG 常挂在 https://host/searxng）。
  Uri endpointFor(String baseUrl) {
    final String trimmed = baseUrl.trim();
    final String withoutTrailingSlash = trimmed.endsWith('/')
        ? trimmed.substring(0, trimmed.length - 1)
        : trimmed;
    return Uri.parse('$withoutTrailingSlash/$path');
  }
}
