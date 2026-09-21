// 搜索服务的错误映射与地址过滤判据（T031；架构 4.3 的搜索协议一行、第 8 节）。
//
// 为什么不能直接复用 mapAiHttpError：**语义重叠但口径不同**。
//   - 搜索的 401/403 是「Key 错或没权限」（Brave 的免费层有速率档位），与 AI 的
//     401 语义一致，因此仍然复用 AuthError/RateLimitError 这两个 core 类型；
//   - 但搜索**没有内容拒绝**这个概念（400 通常是「查询参数非法」），若沿用
//     isContentFilterSignal 的判据，一个参数错误可能被误判成「内容被拒」而终止整条
//     链路。因此搜索自己定义一条更窄的映射：只区分限流、认证、其余 4xx/5xx。
//
// 安全约束（架构第 8 节）：映射只使用**状态码**与结构性字段，不使用响应体文案。
// 搜索响应体可能回显查询词（也就是用户的检索意图），把它拼进错误消息等于把用户
// 内容写进日志。
library;

import 'package:flux/core/core.dart';

import 'search_result.dart';

/// HTTP 状态码到类型化错误的搜索口径映射。
///
///   429             → RateLimitError（可重试，服从 Retry-After）
///   401 / 402 / 403 → AuthError（不可重试，配置问题）
///   其余 4xx/5xx    → NetworkError（保留状态码；5xx 可重试）
AppError mapSearchHttpError({
  required String provider,
  required Uri endpoint,
  required int statusCode,
  Duration? retryAfter,
  Object? cause,
  StackTrace? stackTrace,
}) {
  if (statusCode == 429) {
    return RateLimitError(
      provider: provider,
      retryAfter: retryAfter,
      cause: cause,
      stackTrace: stackTrace,
    );
  }
  if (statusCode == 401 || statusCode == 402 || statusCode == 403) {
    return AuthError(
      provider: provider,
      statusCode: statusCode,
      cause: cause,
      stackTrace: stackTrace,
    );
  }
  return NetworkError(
    uri: endpoint.toString(),
    statusCode: statusCode,
    reason: '搜索服务返回非成功状态码',
    cause: cause,
    stackTrace: stackTrace,
  );
}

/// 一条结果地址是否安全（可以进入下游与界面）。
///
/// 为什么需要它而不仅是渲染层判断：搜索结果来自**第三方**（搜索服务），不是用户
/// 自己配置的地址，因此按 embeddedContent 策略处理——拒绝私网、回环、链路本地与
/// 唯一本地地址。一个被投毒的结果里塞进 http://169.254.169.254/... 会让阅读器替
/// 攻击者去访问内网（SSRF 的客户端形态，同 T021/T024 的判据）。
///
/// 返回 false 的条目由适配器**丢弃**并计入诊断，而不是保留在列表里等下游再判一次
/// ——「先收进来再过滤」会让某条路径忘记过滤。
bool isUsableSearchResultUrl(String url) {
  final Uri? uri = Uri.tryParse(url.trim());
  if (uri == null) {
    return false;
  }
  return checkUrlGuarded(uri, UrlGuardPolicy.embeddedContent).allowed;
}

/// 技术类常见域名（用于访问类别判定）。
///
/// 用显式表格而不是「命中关键词就算技术」：关键词匹配会把地址里恰好含 dev 的
/// 新闻站也判成技术资料。表格是**可核对**的，且漏项只影响分类标签，不影响结果可用性。
const Set<String> _technicalHostSuffixes = <String>{
  'github.com',
  'gitlab.com',
  'stackoverflow.com',
  'stackexchange.com',
  'developer.mozilla.org',
  'docs.python.org',
  'readthedocs.io',
  'arxiv.org',
  'pub.dev',
  'npmjs.com',
  'pypi.org',
  'serverfault.com',
  'superuser.com',
  'askubuntu.com',
};

/// 判定一条结果的访问类别。
///
/// 判据顺序（先具体后笼统）：
///   1) **有发布时间 → news**：协议给出绝对时间说明这条材料是时效性的，这是三家
///      协议里最强的信号；
///   2) **主机命中技术表 → technical**；
///   3) 其余 → general。
///
/// 刻意**不**用「域名里含 news 就是新闻」这类匹配：news.ycombinator.com 是技术
/// 聚合站，sports.news.example 与 blog.example/news 也无法用后缀区分。时效性由
/// 发布时间表达，比域名猜测可靠。
SearchAccessCategory classifySearchAccessCategory({
  required String url,
  DateTime? publishedAt,
}) {
  if (publishedAt != null) {
    return SearchAccessCategory.news;
  }
  final Uri? uri = Uri.tryParse(url.trim());
  final String host = uri?.host.toLowerCase() ?? '';
  if (host.isEmpty) {
    return SearchAccessCategory.general;
  }
  for (final String suffix in _technicalHostSuffixes) {
    if (host == suffix || host.endsWith('.$suffix')) {
      return SearchAccessCategory.technical;
    }
  }
  return SearchAccessCategory.general;
}

/// 剥离 HTML 高亮标签（Brave 的 description 里含 b 标签）。
///
/// 为什么自己剥离而不是交给通用清洗器：这里的输入是**一小段纯文本**，其中只有
/// 高亮标签有意义，通用清洗器会把它当 HTML 片段解析并可能丢弃整段（它面向的是
/// 正文字段，且带节点/深度上限）。剥离规则只需处理这一种已知标签，且必须
/// **只删标签、保留文字**——否则 Brave 的结果片段会整个消失。
///
/// 同时剥离其它标签：搜索服务偶尔会在片段里带 span、em 之类的变体，留着它们会让
/// 片段在界面上显示成源码。
String stripSearchHighlight(String text) {
  if (!text.contains('<')) {
    return text;
  }
  // 去掉成对/自闭合标签本体，保留其中文字。
  final String withoutTags = text.replaceAll(RegExp(r'</?[A-Za-z][^>]*>'), '');
  // 常见实体的最小解码：搜索服务对片段做的转义只有这几类。
  return withoutTags
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&');
}
