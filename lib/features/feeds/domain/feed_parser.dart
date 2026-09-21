// RSS 2.0 / Atom 解析（T013；架构 4.1、第 8 节）。
//
// 安全边界（本文件最重要的部分）：
//   1) **拒绝 DTD 与外部实体**。XML 外部实体（XXE）能读本机文件、发起内网请求，实体
//      扩展（billion laughs）能瞬间耗尽内存。因此这里在解析**之前**扫描原文，只要出现
//      `<!DOCTYPE` 或 `<!ENTITY` 就直接拒绝：一个新闻源没有任何正当理由需要它们。
//      同时在事件流里再判一次 doctype，防止绕过（例如大小写变形、分段空白）。
//   2) **解析深度与节点数上限**：畸形/恶意文档不得构造出超深结构。
//   3) **正文不在此处解释**：这里的产物是「原始 HTML 字符串」，清洗由
//      content_sanitizer.dart 负责。解析层不产出任何可执行内容。
//
// 为什么用事件流解析而不是 XmlDocument.parse：
//   XmlDocument.parse 会先构造整棵树，DTD 检测只能在建树之后进行；事件流允许我们在
//   第一个事件时就发现 doctype 并中止。两者都保留：先用事件流做安全扫描与计数，
//   再对**已通过检查**的文本做 DOM 解析以便取值。
library;

import 'package:xml/xml.dart';
import 'package:xml/xml_events.dart';

import 'package:flux/core/core.dart';

/// 源格式。
enum FeedFormat {
  /// RSS 2.0（`<rss version="2.0">`）。
  rss2,

  /// RSS 1.0 / RDF（`<rdf:RDF>`）。存在但较少见，按 RSS 处理。
  rss1,

  /// Atom 1.0（`<feed xmlns="http://www.w3.org/2005/Atom">`）。
  atom,
}

/// 解析限制。
class FeedParserLimits {
  /// 构造限制。
  const FeedParserLimits({
    this.maxDocumentLength = 10 * 1024 * 1024,
    this.maxDepth = 64,
    this.maxNodes = 200000,
    this.maxEntries = 5000,
  });

  /// 文档长度上限（字符）。响应体上限在抓取层，这里是第二道防线。
  final int maxDocumentLength;

  /// 嵌套深度上限。
  final int maxDepth;

  /// 元素总数上限。
  final int maxNodes;

  /// 单次解析接受的条目数上限（防止一个源塞进几十万条把内存吃光）。
  final int maxEntries;
}

/// 一个待入库的条目（解析产物，尚未分配 feedId、尚未清洗正文）。
class ParsedFeedEntry {
  /// 构造条目。
  const ParsedFeedEntry({
    required this.title,
    this.guid,
    this.guidIsPermaLink = false,
    this.link,
    this.author,
    this.publishedAt,
    this.updatedAt,
    this.summary,
    this.contentHtml,
    this.enclosureImageUrl,
  });

  /// 标题（已去除首尾空白；源未给标题时为空串）。
  final String title;

  /// 源内标识：RSS 的 `guid`、Atom 的 `id`。
  final String? guid;

  /// RSS `guid isPermaLink="true"` 的语义（表示 guid 本身就是 URL）。
  final bool guidIsPermaLink;

  /// 原始链接（**保留全部查询参数**；规范化只用于匹配，另行处理）。
  final String? link;

  /// 作者。
  final String? author;

  /// 发布时间。RSS 取 `pubDate`，Atom 取 `published`（缺失时退到 `updated`）。
  final DateTime? publishedAt;

  /// Atom `updated`（有则记录，用于修订判断的辅助信息）。
  final DateTime? updatedAt;

  /// 摘要：RSS `description`、Atom `summary`。
  final String? summary;

  /// 正文原始 HTML：RSS `content:encoded`、Atom `content`。
  final String? contentHtml;

  /// enclosure / media 图片地址（可选；仅当协议安全时才保留）。
  final String? enclosureImageUrl;
}

/// 一次解析的产物。
class ParsedFeed {
  /// 构造解析结果。
  const ParsedFeed({
    required this.format,
    required this.entries,
    this.title,
    this.siteUrl,
    this.rejectedEntries = 0,
  });

  /// 源格式。
  final FeedFormat format;

  /// 条目。
  final List<ParsedFeedEntry> entries;

  /// 源标题（频道标题 / feed 标题）。
  final String? title;

  /// 站点地址。
  final String? siteUrl;

  /// 因缺少最小必需字段（标题与链接/标识都为空白）而被跳过的条目数。
  final int rejectedEntries;
}

/// 解析 RSS/Atom 文档。
///
/// 失败一律返回 [ParseError]（类型化），不抛裸异常：调用方需要区分「网络失败」与
/// 「内容坏了」，两者的处理策略不同（前者可重试，后者不该反复重试）。
Result<ParsedFeed> parseFeed(
  String document, {
  String source = 'feed',
  FeedParserLimits limits = const FeedParserLimits(),
}) {
  if (document.trim().isEmpty) {
    return Err<ParsedFeed>(ParseError(source: source, detail: '文档为空'));
  }
  if (document.length > limits.maxDocumentLength) {
    return Err<ParsedFeed>(
      ParseError(
        source: source,
        detail: '文档长度 ${document.length} 超过上限 ${limits.maxDocumentLength}',
      ),
    );
  }

  // ---- 第一道防线：拒绝 DTD 与实体声明 --------------------------------------
  final Result<void> dtdCheck = _rejectDoctypeAndEntities(document, source);
  if (dtdCheck.isErr) {
    return Err<ParsedFeed>(dtdCheck.errorOrNull!);
  }

  // ---- 第二道防线：事件流扫描结构上限，并再次确认没有 doctype ----------------
  final Result<void> structureCheck = _scanEvents(document, source, limits);
  if (structureCheck.isErr) {
    return Err<ParsedFeed>(structureCheck.errorOrNull!);
  }

  // ---- 建树并取值 ---------------------------------------------------------
  final XmlDocument xml;
  try {
    xml = XmlDocument.parse(document);
  } on XmlException catch (error) {
    // 只保留结构性描述（行列/类型），不把原文塞进错误里。
    return Err<ParsedFeed>(
      ParseError(
        source: source,
        detail: 'XML 结构非法（${error.runtimeType}）',
        cause: error,
      ),
    );
  } on Exception catch (error) {
    return Err<ParsedFeed>(
      ParseError(
        source: source,
        detail: 'XML 解析失败（${error.runtimeType}）',
        cause: error,
      ),
    );
  }

  // XmlDocument.rootElement 在「只有声明或注释、没有元素」时会**抛 StateError**，
  // 因此这里自己找根元素，把这种情况翻译成类型化的 ParseError 而不是编程异常。
  final XmlElement? root = xml.childElements.firstOrNull;
  if (root == null) {
    return Err<ParsedFeed>(ParseError(source: source, detail: '缺少根元素'));
  }

  final String rootName = root.name.local.toLowerCase();
  switch (rootName) {
    case 'rss':
      return Ok<ParsedFeed>(_parseRss(root, FeedFormat.rss2, limits));
    case 'rdf':
      return Ok<ParsedFeed>(_parseRss(root, FeedFormat.rss1, limits));
    case 'feed':
      return Ok<ParsedFeed>(_parseAtom(root, limits));
    default:
      return Err<ParsedFeed>(
        ParseError(source: source, detail: '不支持的根元素 <$rootName>（只支持 RSS/Atom）'),
      );
  }
}

/// 扫描 DTD 与实体声明（大小写不敏感，容忍标签内空白）。
Result<void> _rejectDoctypeAndEntities(String document, String source) {
  final RegExp doctype = RegExp(r'<\s*!\s*DOCTYPE', caseSensitive: false);
  final RegExp entity = RegExp(r'<\s*!\s*ENTITY', caseSensitive: false);
  final RegExpMatch? doctypeMatch = doctype.firstMatch(document);
  final RegExpMatch? entityMatch = entity.firstMatch(document);
  if (doctypeMatch == null && entityMatch == null) {
    return const Ok<void>(null);
  }

  // 两类都报：ENTITY 是更具体、更危险的事实（billion laughs / XXE），DOCTYPE 是承载它的容器。
  // 只报一半会让排查者以为另一条不存在。
  final List<String> parts = <String>[
    if (entityMatch != null) '实体声明（<!ENTITY），可能是实体扩展攻击',
    if (doctypeMatch != null) 'DTD 声明（<!DOCTYPE），外部实体可能读取本机文件',
  ];
  final int offset = <int>[
    if (doctypeMatch != null) doctypeMatch.start,
    if (entityMatch != null) entityMatch.start,
  ].reduce((int a, int b) => a < b ? a : b);

  return Err<void>(
    ParseError(
      source: source,
      offset: offset,
      detail: '拒绝解析：文档含 ${parts.join('与')}',
    ),
  );
}

/// 用事件流做结构扫描：深度、节点数、以及 doctype 的二次确认。
Result<void> _scanEvents(
  String document,
  String source,
  FeedParserLimits limits,
) {
  int depth = 0;
  int peakDepth = 0;
  int nodes = 0;
  try {
    for (final XmlEvent event in parseEvents(document)) {
      if (event is XmlDoctypeEvent) {
        return Err<void>(
          ParseError(source: source, detail: '拒绝解析：事件流中出现 doctype'),
        );
      }
      if (event is XmlStartElementEvent) {
        depth++;
        nodes++;
        if (depth > peakDepth) {
          peakDepth = depth;
        }
        if (depth > limits.maxDepth) {
          return Err<void>(
            ParseError(source: source, detail: '嵌套深度超过上限 ${limits.maxDepth}'),
          );
        }
        if (nodes > limits.maxNodes) {
          return Err<void>(
            ParseError(source: source, detail: '元素数超过上限 ${limits.maxNodes}'),
          );
        }
      } else if (event is XmlEndElementEvent) {
        if (depth > 0) {
          depth--;
        }
      }
    }
  } on XmlParserException catch (error) {
    // 事件流与 DOM 解析对畸形文档的容忍度不同；这里只记录，交给 DOM 解析给出
    // 一致的失败结果（避免两处各自报不同原因）。
    if (error.message.contains('depth')) {
      return Err<void>(
        ParseError(source: source, detail: '事件流解析失败：${error.message}'),
      );
    }
    return const Ok<void>(null);
  } on XmlException {
    return const Ok<void>(null);
  }
  return const Ok<void>(null);
}

// ===========================================================================
// RSS 2.0 / 1.0
// ===========================================================================

ParsedFeed _parseRss(
  XmlElement root,
  FeedFormat format,
  FeedParserLimits limits,
) {
  final XmlElement? channel = format == FeedFormat.rss2
      ? root.findElements('channel').firstOrNull
      : root;
  if (channel == null) {
    return ParsedFeed(format: format, entries: const <ParsedFeedEntry>[]);
  }

  final List<ParsedFeedEntry> entries = <ParsedFeedEntry>[];
  int rejected = 0;
  for (final XmlElement item in _findElements(channel, 'item')) {
    if (entries.length >= limits.maxEntries) {
      break;
    }
    final ParsedFeedEntry? entry = _rssItem(item);
    if (entry == null) {
      rejected++;
      continue;
    }
    entries.add(entry);
  }

  return ParsedFeed(
    format: format,
    entries: entries,
    title: _textOf(channel, 'title'),
    siteUrl: _textOf(channel, 'link'),
    rejectedEntries: rejected,
  );
}

ParsedFeedEntry? _rssItem(XmlElement item) {
  final String title = (_textOf(item, 'title') ?? '').trim();
  final String? link = _nonEmpty(_textOf(item, 'link'));
  final XmlElement? guidElement = _findElement(item, 'guid');
  final String? guid = _nonEmpty(guidElement?.innerText);
  final bool guidIsPermaLink =
      guidElement?.getAttribute('isPermaLink')?.toLowerCase() == 'true';

  // 一条entry至少要有「标题」或「链接/标识」之一，否则它不构成可读文章。
  if (title.isEmpty && link == null && guid == null) {
    return null;
  }

  final String? description = _nonEmpty(_textOf(item, 'description'));
  final String? contentEncoded = _nonEmpty(_textOf(item, 'encoded'));

  return ParsedFeedEntry(
    title: title,
    guid: guid,
    guidIsPermaLink: guidIsPermaLink,
    link: link,
    author:
        _nonEmpty(_textOf(item, 'creator')) ??
        _nonEmpty(_textOf(item, 'author')),
    publishedAt:
        parseFeedDate(_textOf(item, 'pubDate')) ??
        parseFeedDate(_textOf(item, 'date')),
    summary: description,
    contentHtml: contentEncoded,
    enclosureImageUrl: _rssEnclosureImage(item),
  );
}

/// RSS `<enclosure>` 中的图片地址（仅在 MIME 是图片时采用）。
///
/// 只认 `type="image/*"`：把音频/视频的 enclosure 当图片会把播客封面之外的
/// 媒体地址塞进图片位置，渲染时必然失败。
String? _rssEnclosureImage(XmlElement item) {
  for (final XmlElement enclosure in _findElements(item, 'enclosure')) {
    final String? mime = _nonEmpty(enclosure.getAttribute('type'));
    final String? url = _nonEmpty(enclosure.getAttribute('url'));
    if (url == null) {
      continue;
    }
    if (mime != null && mime.toLowerCase().startsWith('image/')) {
      return url;
    }
  }
  return null;
}

// ===========================================================================
// Atom 1.0
// ===========================================================================

ParsedFeed _parseAtom(XmlElement root, FeedParserLimits limits) {
  // Atom 规范允许条目**继承** feed 级的 author：条目自身没有 author 时用 feed 的。
  // 这是规范行为，不是容错式猜测；不给继承会让大量正常源的文章作者变成空。
  final String? feedAuthor = _atomAuthorName(root);
  final List<ParsedFeedEntry> entries = <ParsedFeedEntry>[];
  int rejected = 0;
  for (final XmlElement entry in _findElements(root, 'entry')) {
    if (entries.length >= limits.maxEntries) {
      break;
    }
    final ParsedFeedEntry? parsed = _atomEntry(entry, feedAuthor: feedAuthor);
    if (parsed == null) {
      rejected++;
      continue;
    }
    entries.add(parsed);
  }

  return ParsedFeed(
    format: FeedFormat.atom,
    entries: entries,
    title: _nonEmpty(_textOf(root, 'title')),
    siteUrl: _atomLink(root, preferAlternate: true),
    rejectedEntries: rejected,
  );
}

ParsedFeedEntry? _atomEntry(XmlElement entry, {String? feedAuthor}) {
  final String title = (_textOf(entry, 'title') ?? '').trim();
  final String? id = _nonEmpty(_textOf(entry, 'id'));
  final String? link = _atomLink(entry, preferAlternate: true);

  if (title.isEmpty && id == null && link == null) {
    return null;
  }

  final XmlElement? content = _findElement(entry, 'content');
  final String? contentHtml = _atomContentHtml(content);

  return ParsedFeedEntry(
    title: title,
    // Atom 的 id 语义上就是「源内标识」，但规范里它通常是一个 URL（urn:uuid:…）；
    // 因此不把 guidIsPermaLink 置真——是否可用作链接由 link 元素表达。
    guid: id,
    guidIsPermaLink: false,
    link: link,
    // 条目自身没有 author 时继承 feed 级 author（Atom 规范允许）。
    author: _atomAuthorName(entry) ?? feedAuthor,
    // Atom 里 published 才是发布时间；缺失时退到 updated（规范允许只给 updated）。
    publishedAt:
        parseFeedDate(_textOf(entry, 'published')) ??
        parseFeedDate(_textOf(entry, 'updated')),
    updatedAt: parseFeedDate(_textOf(entry, 'updated')),
    summary: _nonEmpty(_textOf(entry, 'summary')),
    contentHtml: contentHtml,
    enclosureImageUrl: _atomEnclosureImage(entry),
  );
}

/// Atom `<content>` 转 HTML 字符串。
///
/// 三种 `type`：
///   - `html`：内容是转义的 HTML 字符串，直接可用；
///   - `xhtml`：内容是一个 XHTML 子树，需要把它**序列化**回 HTML 字符串再交给清洗器
///     （这是 Atom 规范定义的第三种正文承载方式，fixture 里有样本）；
///   - `text`（或无 type）：内容是纯文本，转义后当作最小 HTML 处理，避免把
///     `<` 之类当成标签。
/// `src` 形式（只有 `src` 没有内嵌内容）本任务**不主动抓取**：那需要第二次网络请求
/// 且有自己的信任边界，属 T024 的范围；这里返回 null 并保留 summary。
String? _atomContentHtml(XmlElement? content) {
  if (content == null) {
    return null;
  }
  final String type = (content.getAttribute('type') ?? 'text').toLowerCase();
  switch (type) {
    case 'xhtml':
      final StringBuffer buffer = StringBuffer();
      for (final XmlNode child in content.children) {
        if (child is XmlElement) {
          buffer.write(child.toXmlString());
        }
      }
      final String html = buffer.toString();
      return html.trim().isEmpty ? null : html;
    case 'html':
      return _nonEmpty(content.innerText);
    case 'text':
    default:
      final String text = content.innerText;
      return text.trim().isEmpty ? null : _escapeTextToHtml(text);
  }
}

/// Atom `<author><name>`。
/// 同时适用于 feed 与 entry 两级（两级结构相同），因此参数名通用。
String? _atomAuthorName(XmlElement element) {
  final XmlElement? author = _findElement(element, 'author');
  if (author == null) {
    return null;
  }
  return _nonEmpty(_textOf(author, 'name'));
}

/// Atom `<link>`：优先 `rel="alternate"`，其次 `rel` 缺失，再次第一个可用 href。
String? _atomLink(XmlElement element, {required bool preferAlternate}) {
  String? fallback;
  for (final XmlElement link in _findElements(element, 'link')) {
    final String? href = _nonEmpty(link.getAttribute('href'));
    if (href == null) {
      continue;
    }
    final String rel = (link.getAttribute('rel') ?? 'alternate').toLowerCase();
    if (preferAlternate && rel == 'alternate') {
      return href;
    }
    fallback ??= href;
  }
  return fallback;
}

/// Atom `<link rel="enclosure">` 中的图片。
String? _atomEnclosureImage(XmlElement entry) {
  for (final XmlElement link in _findElements(entry, 'link')) {
    final String rel = (link.getAttribute('rel') ?? '').toLowerCase();
    if (rel != 'enclosure' && rel != 'image') {
      continue;
    }
    final String? mime = _nonEmpty(link.getAttribute('type'));
    final String? href = _nonEmpty(link.getAttribute('href'));
    if (href == null) {
      continue;
    }
    if (mime == null || mime.toLowerCase().startsWith('image/')) {
      return href;
    }
  }
  return null;
}

// ===========================================================================
// 日期解析（RFC 822 + ISO 8601）
// ===========================================================================

/// 解析订阅里的日期，兼容 RFC 822 与 ISO 8601。
///
/// 为什么两者都要：RSS 2.0 规范用 RFC 822（`Sun, 20 Sep 2026 22:15:00 GMT`），Atom 用
/// ISO 8601（`2026-09-20T22:15:00Z`），而现实中源经常写错格式。解析失败返回 null，
/// 由上层决定「用抓取时间并标记」——这里**不猜**，猜出来的时间会被当成源的声明的。
DateTime? parseFeedDate(String? raw) {
  if (raw == null) {
    return null;
  }
  final String input = raw.trim();
  if (input.isEmpty) {
    return null;
  }

  // ISO 8601。
  //
  // 这里不能直接信 DateTime.tryParse：它对超出范围的字段会**静默滚动**而不报错，
  // 例如 '2026-13-45T99:99:99Z' 会变成 2027-02-18T04:40:39Z。那是一个凭空捷造的时间，
  // 而上层会把它当成源声明的发布时间展示给用户。
  // 因此先用严格正则验证字段与取值范围，再交给 tryParse 做时区运算。
  if (_isStrictIso8601(input)) {
    final DateTime? iso = DateTime.tryParse(input);
    if (iso != null) {
      return iso.toUtc();
    }
  }

  // RFC 822：`[Day, ]DD Mon YYYY HH:MM[:SS] [zone]`
  final RegExpMatch? match = RegExp(
    r'^(?:[A-Za-z]{3},?\s+)?'
    r'(\d{1,2})\s+([A-Za-z]{3})\s+(\d{2,4})'
    r'(?:\s+(\d{1,2}):(\d{2})(?::(\d{2}))?)?'
    r'(?:\s+([A-Za-z]{1,5}|[+-]\d{4}))?$',
  ).firstMatch(input);
  if (match == null) {
    return null;
  }

  final int? day = int.tryParse(match.group(1)!);
  final int? month = _monthNumber(match.group(2)!);
  int? year = int.tryParse(match.group(3)!);
  if (day == null || month == null || year == null) {
    return null;
  }
  // 两位年份按 RFC 822 的惯例展开（源里偶尔出现）。
  if (year < 100) {
    year += year < 70 ? 2000 : 1900;
  }
  final int hour = int.tryParse(match.group(4) ?? '') ?? 0;
  final int minute = int.tryParse(match.group(5) ?? '') ?? 0;
  final int second = int.tryParse(match.group(6) ?? '') ?? 0;
  if (day < 1 || day > 31 || hour > 23 || minute > 59 || second > 60) {
    return null;
  }

  final int? offsetMinutes = _zoneOffsetMinutes(match.group(7));
  final DateTime naive = DateTime.utc(year, month, day, hour, minute, second);
  if (naive.month != month || naive.day != day) {
    // 例如 "31 Feb"：DateTime 会静默滚动到下个月，这里必须拒绝。
    return null;
  }
  return offsetMinutes == null
      ? naive
      : naive.subtract(Duration(minutes: offsetMinutes));
}

/// 严格校验 ISO 8601 字符串（日期 + 可选时间 + 可选时区）。
///
/// 只做一件 DateTime.tryParse 不会做的事：拒绝超出范围的月/日/时/分/秒，而不让它们静默滚动。
/// 合法性进一步用 DateTime.utc 构造后回读比对，以捕获二月三十日这类闰年短月问题。
bool _isStrictIso8601(String input) {
  // 严格格式：完整日期，可选时间（时:分[:秒[.小数]]），可选时区。
  final RegExpMatch? match = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})'
    r'(?:[Tt ](\d{2}):(\d{2})(?::(\d{2})(?:[.]\d+)?)?)?'
    r'(Z|z|[+-]\d{2}:?\d{2})?$',
  ).firstMatch(input);
  if (match == null) {
    return false;
  }
  final int year = int.parse(match.group(1)!);
  final int month = int.parse(match.group(2)!);
  final int day = int.parse(match.group(3)!);
  final int hour = int.tryParse(match.group(4) ?? '') ?? 0;
  final int minute = int.tryParse(match.group(5) ?? '') ?? 0;
  final int second = int.tryParse(match.group(6) ?? '') ?? 0;
  if (month < 1 || month > 12) {
    return false;
  }
  if (day < 1 || day > 31) {
    return false;
  }
  if (hour > 23 || minute > 59 || second > 60) {
    return false;
  }
  // 回读比对：DateTime 会把 2 月 31 日滚到 3 月，读回后与原值不等即为非法。
  final DateTime probe = DateTime.utc(year, month, day);
  return probe.year == year && probe.month == month && probe.day == day;
}

/// 时区名/偏移 → 相对 UTC 的分钟数；无法识别时返回 null（按 UTC 处理）。
int? _zoneOffsetMinutes(String? zone) {
  if (zone == null || zone.isEmpty) {
    return null;
  }
  final String upper = zone.toUpperCase();
  switch (upper) {
    case 'UT':
    case 'UTC':
    case 'GMT':
    case 'Z':
      return 0;
    case 'EST':
      return -300;
    case 'EDT':
      return -240;
    case 'CST':
      return -360;
    case 'CDT':
      return -300;
    case 'MST':
      return -420;
    case 'MDT':
      return -360;
    case 'PST':
      return -480;
    case 'PDT':
      return -420;
  }
  final RegExpMatch? offset = RegExp(r'^([+-])(\d{2})(\d{2})$')
      .firstMatch(upper);
  if (offset == null) {
    return null;
  }
  final int hours = int.parse(offset.group(2)!);
  final int minutes = int.parse(offset.group(3)!);
  final int total = hours * 60 + minutes;
  return offset.group(1) == '-' ? -total : total;
}

int? _monthNumber(String name) {
  const List<String> months = <String>[
    'jan',
    'feb',
    'mar',
    'apr',
    'may',
    'jun',
    'jul',
    'aug',
    'sep',
    'oct',
    'nov',
    'dec',
  ];
  final int index = months.indexOf(name.toLowerCase().substring(0, 3));
  return index == -1 ? null : index + 1;
}

// ===========================================================================
// XML 取值小工具（按**本地名**匹配，忽略命名空间前缀）
// ===========================================================================

/// 按本地名找第一个子元素（`content:encoded` 与 `encoded` 都能命中）。
XmlElement? _findElement(XmlElement parent, String localName) =>
    _findElements(parent, localName).firstOrNull;

/// 按本地名找全部子元素。
///
/// 两侧都小写化后再比较：元素名侧必须小写（XML 里有 pubDate / lastBuildDate 这类驼峰写法），
/// 查询侧同样要小写——否则传 pubDate 会与 pubdate 不相等而永远匹配不到，
/// 静默地把发布时间变成 null（用 rss_sample.rss2.xml 实测踩到）。
Iterable<XmlElement> _findElements(XmlElement parent, String localName) {
  final String needle = localName.toLowerCase();
  return parent.childElements.where(
    (XmlElement e) => e.name.local.toLowerCase() == needle,
  );
}

/// 取第一个同名子元素的文本（已 trim）；不存在或为空返回 null。
String? _textOf(XmlElement parent, String localName) {
  final XmlElement? element = _findElement(parent, localName);
  if (element == null) {
    return null;
  }
  return _nonEmpty(element.innerText);
}

String? _nonEmpty(String? value) {
  if (value == null) {
    return null;
  }
  final String trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

/// 把纯文本转成最小 HTML（转义 `<`、`>`、`&`），交给清洗器统一处理。
String _escapeTextToHtml(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');
