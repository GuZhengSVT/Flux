// 静态网页正文抽取（T024；架构 4.2 的 F-READ）。
//
// 架构口径：「主动提取只用 HTTP + 静态解析，不执行脚本、不绕过登录/付费墙/验证码；
// 失败保留原内容并给外部浏览器入口。」
//
// 因此本文件是**纯函数**，只做一件事：把一段 HTML 变成「标题 + 正文文本 + 图片引用」。
// 它不联网、不执行脚本、不写库——那三件事分别属于 infrastructure、绝不发生、以及用例层。
//
// 四步，每一步的失败都有明确归属：
//   1) **去掉噪音区块**（script/style/nav/footer/aside/header/form/svg）：它们的内容不是
//      正文。用配对扫描整段移除而不是只删标签——只删标签会让脚本文本印进正文；
//   2) **选正文区域**：优先 article，其次 main，再退到 role=main / id=content 一类常见
//      容器，最后在候选块里挑**文字最多**的那一块；
//   3) **交给受控清洗器**（T013 的 sanitizeHtmlToDocument）：白名单、危险 URL 拒绝、
//      节点/深度上限都在那一处，本文件不重复实现第二套判据（重复必然漂移）；
//   4) **判定失败类别**：付费墙迹象（meta/常见 class 名/正文提示语）与「正文过短
//      （可能纯 JS 渲染）」是两个**提示**而不是拒绝——用户仍然可以尝试，只是界面要他
//      做好失败的心理准备。
//
// 为什么「提示」不等于「阻止」：架构只要求不**绕过**付费墙，没有要求「看到付费墙就不抓」。
// 用户对自己的订阅内容有权获取，而判据本身也会误判（有的站点用 paywall 作为样式类名
// 但全文可见）。因此本层给出提示，由用户决定，而不是替他拒掉。
library;

import 'package:flux/core/core.dart';

import 'package:flux/features/feeds/domain/content_sanitizer.dart';

/// 抽取结果类别。
enum StaticExtractionOutcome {
  /// 抽到了可用的正文。
  ok,

  /// 拿到 HTML 但正文过短（通常是纯 JS 渲染）。
  empty,

  /// 没有任何可用正文区域，或正文为空。
  noContent,
}

/// 付费墙/登录墙的**提示**（不阻止抓取）。
enum PaywallSignal {
  /// meta keywords / description 里出现 paywall 一类词。
  meta,

  /// 标签属性（class/id）里出现 paywall/regwall 一类常见类名。
  className,

  /// 正文里出现「订阅后可读」「登录后阅读」这类提示文本。
  inlineText,
}

/// 一次静态抽取的结果。
final class StaticExtraction {
  /// 构造结果。
  const StaticExtraction({
    required this.outcome,
    required this.title,
    required this.text,
    required this.imageUrls,
    required this.paywallSignals,
    this.usedRegion,
  });

  /// 结果类别。
  final StaticExtractionOutcome outcome;

  /// 标题（来自 title 标签，回退到正文里的第一个 h1）；可能为空。
  final String title;

  /// 正文纯文本（已清洗）。
  final String text;

  /// 正文里的图片引用（**不下载**，只记录地址）。
  final List<String> imageUrls;

  /// 付费墙/登录墙迹象。
  final List<PaywallSignal> paywallSignals;

  /// 实际选中的区域描述（article / main / container / largest / body），用于诊断与测试。
  final String? usedRegion;

  /// 是否可用（有正文文本且长度达标）。
  bool get isUsable =>
      outcome == StaticExtractionOutcome.ok && text.trim().isNotEmpty;

  /// 是否有付费墙迹象。
  bool get hasPaywallSignal => paywallSignals.isNotEmpty;
}

/// 正文短于此长度时提示「可能纯 JS 渲染」。
///
/// 取值理由：一段正常正文的字数远大于此（一两句话就有 100 字）。取 200 字是为了让
/// 「几乎什么都没有」与「一篇很短的消息」区分开——后者仍然是有用的正文，不该被我们
/// 说成「提取失败」。
const int kMinUsableTextLength = 200;

/// 抽取用的上限（防畸形/超大页面耗尽内存）。
final class StaticExtractionLimits {
  /// 构造上限。
  const StaticExtractionLimits({
    this.maxInputLength = 4 * 1024 * 1024,
    this.maxImageUrls = 200,
    this.maxCandidates = 400,
  });

  /// 输入 HTML 长度上限（字符）。超出部分被截断而不是拒绝整篇。
  final int maxInputLength;

  /// 记录图片地址的上限。
  final int maxImageUrls;

  /// 候选块的扫描上限（防超长页面里的二次方扫描）。
  final int maxCandidates;
}

/// 从 HTML 里抽取正文。
StaticExtraction extractStaticArticle(
  String html, {
  StaticExtractionLimits limits = const StaticExtractionLimits(),
}) {
  final String input = html.length > limits.maxInputLength
      ? html.substring(0, limits.maxInputLength)
      : html;

  final String title = _extractTitle(input);
  final List<PaywallSignal> signals = _detectPaywall(input);
  final String cleaned = _stripNoiseRegions(_bodyOf(input));

  // 候选区域按优先级尝试：语义标签 → 常见容器 → 最大文字块 → 整个文档。
  for (final String tag in <String>['article', 'main']) {
    final String? region = _firstBalancedRegion(cleaned, tag);
    if (region != null && _visibleText(region).length >= kMinUsableTextLength) {
      return _finish(
        region: region,
        usedRegion: tag,
        title: title,
        signals: signals,
        limits: limits,
      );
    }
  }

  final String? byAttribute = _firstRegionWithAttribute(cleaned);
  if (byAttribute != null &&
      _visibleText(byAttribute).length >= kMinUsableTextLength) {
    return _finish(
      region: byAttribute,
      usedRegion: 'container',
      title: title,
      signals: signals,
      limits: limits,
    );
  }

  final String? largest = _largestTextBlock(cleaned, limits: limits);
  if (largest != null && _visibleText(largest).length >= kMinUsableTextLength) {
    return _finish(
      region: largest,
      usedRegion: 'largest',
      title: title,
      signals: signals,
      limits: limits,
    );
  }

  // 退到整页：仍然有文字就接受（短文章是真实存在的），只是把 usedRegion 标成 body，
  // 让诊断能区分「命中语义容器」与「只能整页兜底」。
  final StaticExtraction wholePage = _finish(
    region: cleaned,
    usedRegion: 'body',
    title: title,
    signals: signals,
    limits: limits,
  );
  return wholePage;
}

/// 组装最终结果（统一走受控清洗器）。
StaticExtraction _finish({
  required String region,
  required String usedRegion,
  required String title,
  required List<PaywallSignal> signals,
  required StaticExtractionLimits limits,
}) {
  // 清洗器是**唯一**的白名单与 URL 判据（T013）。本层不自己实现一套过滤——重复的判据
  // 必然漂移，而漂移的后果是「订阅抓取挡住了危险 URL、主动提取没挡住」。
  final SanitizerReport report = sanitizeHtmlToDocument(region);
  final String text = docDocumentPlainText(report.document.children).trim();
  final List<String> images = _collectImageUrls(
    report.document,
    limit: limits.maxImageUrls,
  );
  // 标题回退：title 标签往往带「 - 站点名」后缀，正文里的第一个 h1 更接近文章标题。
  final String resolvedTitle = title.isNotEmpty
      ? title
      : _firstHeading(report.document);
  if (text.isEmpty) {
    return StaticExtraction(
      outcome: StaticExtractionOutcome.noContent,
      title: resolvedTitle,
      text: '',
      imageUrls: images,
      paywallSignals: signals,
      usedRegion: usedRegion,
    );
  }
  return StaticExtraction(
    outcome: text.length < kMinUsableTextLength
        ? StaticExtractionOutcome.empty
        : StaticExtractionOutcome.ok,
    title: resolvedTitle,
    text: text,
    imageUrls: images,
    paywallSignals: signals,
    usedRegion: usedRegion,
  );
}

/// 收集正文里的图片地址（不下载）。
List<String> _collectImageUrls(DocDocument document, {required int limit}) {
  final List<String> urls = <String>[];
  final Set<String> seen = <String>{};
  void add(String url) {
    if (urls.length >= limit || !seen.add(url)) {
      return;
    }
    urls.add(url);
  }

  for (final DocInline inline in collectDocInlines(document)) {
    if (inline case DocImageInline(:final String url)) {
      add(url);
    }
  }
  for (final DocNode node in document.children) {
    if (node case DocImageBlock(:final String url)) {
      add(url);
    }
  }
  return urls;
}

/// 正文里的第一个标题文字（作为 title 缺失时的回退）。
String _firstHeading(DocDocument document) {
  for (final DocNode node in document.children) {
    if (node case DocHeading(:final List<DocInline> children)) {
      final String text = docInlinePlainText(children).trim();
      if (text.isNotEmpty) {
        return text;
      }
    }
  }
  return '';
}

/// 抽取 title 内容，并去掉常见的「站点名」后缀。
String _extractTitle(String html) {
  final RegExpMatch? match = RegExp(
    '<title[^>]*>([\\s\\S]*?)</title>',
    caseSensitive: false,
  ).firstMatch(html);
  if (match == null) {
    return '';
  }
  final String raw = decodeHtmlEntities(match.group(1) ?? '').trim();
  // 常见的「标题 - 站点」「标题 | 站点」分隔：只取第一段，因为详情页的标题位显示整串
  // 会让用户以为文章标题就叫「xxx - 某某新闻」。
  for (final String separator in <String>[' - ', ' | ', ' – ', ' — ', ' _ ']) {
    final int index = raw.indexOf(separator);
    if (index > 0) {
      return raw.substring(0, index).trim();
    }
  }
  return raw;
}

/// 付费墙/登录墙迹象（提示，不阻止）。
List<PaywallSignal> _detectPaywall(String html) {
  final List<PaywallSignal> signals = <PaywallSignal>[];
  final String lower = html.toLowerCase();

  final RegExp meta = RegExp(r'<meta\b[^>]*>', caseSensitive: false);
  for (final RegExpMatch m in meta.allMatches(html)) {
    final String tag = m.group(0)!.toLowerCase();
    if (!tag.contains('name=') && !tag.contains('property=')) {
      continue;
    }
    if (tag.contains('paywall') ||
        tag.contains('subscriber') ||
        tag.contains('subscription')) {
      signals.add(PaywallSignal.meta);
      break;
    }
  }

  // 类名迹象：只在**标签属性**里找，不在全文里找——正文里出现「付费」两个字是正常的
  // （例如一篇讨论付费墙的文章），拿它当迹象会造成大量误报。
  final RegExp attributes = RegExp(
    // 引号用 \x22 与 \x27 表达：这样整条正则可以写成 raw 单引号字符串（没有需要转义的
    // 引号字符），既避免 Dart 侧的转义叠加，也不会触发 prefer_single_quotes。
    r'(?:class|id)\s*=\s*[\x22\x27]([^\x22\x27]*)[\x22\x27]',
    caseSensitive: false,
  );
  for (final RegExpMatch m in attributes.allMatches(html)) {
    final String value = (m.group(1) ?? '').toLowerCase();
    if (value.contains('paywall') ||
        value.contains('regwall') ||
        value.contains('subscribe-wall') ||
        value.contains('subscriber-only') ||
        value.contains('premium-content')) {
      signals.add(PaywallSignal.className);
      break;
    }
  }

  if (lower.contains('subscribe to read') ||
      lower.contains('subscribers only') ||
      lower.contains('订阅后可读') ||
      lower.contains('登录后阅读') ||
      lower.contains('付费后继续')) {
    signals.add(PaywallSignal.inlineText);
  }
  return signals;
}

/// 去掉噪音区块（连同内容）。
///
/// 用**配对扫描**而不是正则替换标签：script 的内容里出现 `</div>` 这类字符串是很常见的，
/// 正则匹配到第一个结束标签后会把脚本尾部留在正文里。配对扫描按深度跳过整段。
///
/// 调用方先经 [_bodyOf]：真实浏览器遇到 body 时会**隐式闭合** head，而受控清洗器把
/// head/title 当作「连同内容丢弃」的标签。一份少写 `</head>` 的畸形页面会让整个正文被
/// 判成 head 的一部分而丢掉，用户看到的是一篇「提取失败」的文章——而它其实完全可读。
String _stripNoiseRegions(String html) {
  const List<String> noiseTags = <String>[
    'script',
    'style',
    'noscript',
    'template',
    'svg',
    'nav',
    'footer',
    'aside',
    'header',
    'form',
    'iframe',
    'object',
    'button',
    'select',
    'textarea',
  ];
  String result = html;
  for (final String tag in noiseTags) {
    result = _removeAllBalancedRegions(result, tag);
  }
  return result;
}

/// 移除所有该标签的配对区块（含内容，按深度配对）。
String _removeAllBalancedRegions(String html, String tag) {
  final RegExp open = RegExp('<$tag(?:\\s[^>]*)?>', caseSensitive: false);
  final RegExp close = RegExp('</$tag\\s*>', caseSensitive: false);

  final StringBuffer out = StringBuffer();
  int cursor = 0;
  while (true) {
    final RegExpMatch? openMatch = open.firstMatch(html.substring(cursor));
    if (openMatch == null) {
      out.write(html.substring(cursor));
      break;
    }
    final int openStart = cursor + openMatch.start;
    final int openEnd = cursor + openMatch.end;
    int depth = 1;
    int scan = openEnd;
    int regionEnd = html.length;
    while (depth > 0) {
      final String rest = html.substring(scan);
      final RegExpMatch? nextOpen = open.firstMatch(rest);
      final RegExpMatch? nextClose = close.firstMatch(rest);
      if (nextClose == null) {
        // 没有配对的结束标签：整段到文档末尾都算这个区块（宽容处理）。
        regionEnd = html.length;
        break;
      }
      if (nextOpen != null && nextOpen.start < nextClose.start) {
        depth++;
        scan += nextOpen.end;
        continue;
      }
      depth--;
      scan += nextClose.end;
      if (depth == 0) {
        regionEnd = scan;
      }
    }
    out.write(html.substring(cursor, openStart));
    cursor = regionEnd;
  }
  return out.toString();
}

/// 取第一个该标签的**内层**内容（按深度配对）；没有则 null。
/// 取出 body 的内容（对应浏览器的隐式闭合规则）。
///
/// 没有 body 标签时原样返回：那不是畸形，而是一些片段/测试输入。
String _bodyOf(String html) {
  final RegExpMatch? open = RegExp(
    r'<body\b[^>]*>',
    caseSensitive: false,
  ).firstMatch(html);
  if (open == null) {
    return html;
  }
  final String rest = html.substring(open.end);
  final RegExpMatch? close = RegExp(
    r'</body\s*>',
    caseSensitive: false,
  ).firstMatch(rest);
  return close == null ? rest : rest.substring(0, close.start);
}

String? _firstBalancedRegion(String html, String tag) {
  final RegExp open = RegExp('<$tag(?:\\s[^>]*)?>', caseSensitive: false);
  final RegExp close = RegExp('</$tag\\s*>', caseSensitive: false);
  final RegExpMatch? first = open.firstMatch(html);
  if (first == null) {
    return null;
  }
  int depth = 1;
  int scan = first.end;
  while (depth > 0) {
    final String rest = html.substring(scan);
    final RegExpMatch? nextOpen = open.firstMatch(rest);
    final RegExpMatch? nextClose = close.firstMatch(rest);
    if (nextClose == null) {
      return html.substring(first.end);
    }
    if (nextOpen != null && nextOpen.start < nextClose.start) {
      depth++;
      scan += nextOpen.end;
      continue;
    }
    depth--;
    final int closeStart = scan + nextClose.start;
    scan += nextClose.end;
    if (depth == 0) {
      return html.substring(first.end, closeStart);
    }
  }
  return null;
}

/// 取第一个符合常见正文容器特征的块内层内容。
String? _firstRegionWithAttribute(String html) {
  final RegExp pattern = RegExp(
    r'<(div|section|main)\b[^>]*\b(?:role\s*=\s*[\x22\x27]?main'
    r'|id\s*=\s*[\x22\x27]?content'
    r'|class\s*=\s*[\x22\x27][^\x22\x27]*'
    r'(?:article|post|entry|content)[^\x22\x27]*)[^>]*>',
    caseSensitive: false,
  );
  final RegExpMatch? match = pattern.firstMatch(html);
  if (match == null) {
    return null;
  }
  final String tagName = match.group(1)!.toLowerCase();
  return _firstBalancedRegion(html.substring(match.start), tagName);
}

/// 找「文字最多」的容器（div/section/article/main）。
String? _largestTextBlock(
  String html, {
  required StaticExtractionLimits limits,
}) {
  final RegExp container = RegExp(
    r'<(div|section|article|main)\b[^>]*>',
    caseSensitive: false,
  );
  String? best;
  int bestLength = 0;
  int scanned = 0;
  for (final RegExpMatch match in container.allMatches(html)) {
    if (scanned >= limits.maxCandidates) {
      break;
    }
    scanned++;
    final String tagName = match.group(1)!.toLowerCase();
    final String region =
        _firstBalancedRegion(html.substring(match.start), tagName) ?? '';
    // 只算**可见文字**长度（不含标签），否则一个包着很长 src 的容器会因此胜出。
    final int length = _visibleText(region).length;
    if (length > bestLength) {
      bestLength = length;
      best = region;
    }
  }
  return best;
}

/// 粗略取一段 HTML 的可见文字（用于选块）。
String _visibleText(String html) =>
    decodeHtmlEntities(html.replaceAll(RegExp(r'<[^>]*>'), ' '))
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

/// 解码常见的 HTML 实体（标题与选块用；正文的实体解码由受控清洗器负责）。
String decodeHtmlEntities(String input) => input
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&#39;', "'")
    .replaceAll('&apos;', "'")
    .replaceAll('&mdash;', '—')
    .replaceAll('&ndash;', '–')
    .replaceAll('&hellip;', '…');
