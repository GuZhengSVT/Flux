// OPML 解析与生成（T015；架构 4.1「订阅导入导出采用 OPML」）。
//
// 安全边界与 T013 的 feed_parser **完全一致**，因为 OPML 同样是用户提供的 XML：
//   1) 解析前拒绝 DOCTYPE 与 ENTITY（大小写与空白变形同样拒绝）：外部实体能读本机
//      文件、实体扩展能耗尽内存，而一个订阅清单没有任何正当理由需要它们；
//   2) 事件流二次确认 doctype，并限制嵌套深度与节点总数；
//   3) 文档长度上限。
//
// 与 feed_parser 的差别（因此没有复用它的代码）：
//   - OPML 的产物是「订阅清单 + 分组嵌套结构」，而不是文章条目；
//   - 分组嵌套是**有意义的层级信息**（架构 4.1 的「保留文件分组」策略要用它），
//     而 feed_parser 只取条目、忽略层级；
//   - 无效项要**逐项**报告（预览界面要列出「哪些条目不能用、为什么」），而不是
//     只给一个计数。因此这里返回带原因的诊断列表。
//
// 本文件只解析与生成，不做「匹配已有源」「决定分组策略」这类业务判断——那些在
// application 层的 ImportOpmlUseCase。
library;

import 'package:xml/xml.dart';
import 'package:xml/xml_events.dart';

import 'package:flux/core/core.dart';

/// OPML 解析限制。
class OpmlParserLimits {
  /// 构造限制。
  const OpmlParserLimits({
    this.maxDocumentLength = 10 * 1024 * 1024,
    this.maxDepth = 32,
    this.maxNodes = 50000,
    this.maxEntries = 5000,
  });

  /// 文档长度上限（字符）。
  final int maxDocumentLength;

  /// 嵌套深度上限（OPML 用嵌套 outline 表达分组，正常文件很浅）。
  final int maxDepth;

  /// 元素总数上限。
  final int maxNodes;

  /// 接受的订阅条目数上限。
  final int maxEntries;
}

/// 一个订阅条目（已从 outline 提取，尚未做业务判断）。
class OpmlEntry {
  /// 构造条目。
  const OpmlEntry({
    required this.outlineIndex,
    required this.title,
    required this.xmlUrl,
    required this.groupPath,
    this.htmlUrl,
    this.type,
  });

  /// 在文件中的 outline 序号（从 1 开始，含分组）。
  ///
  /// 与 [OpmlSkippedEntry.index] 共用同一套编号空间，因此调用方可以把「可用条目」
  /// 与「被跳过的条目」按序号归并回**文件顺序**（预览界面要按文件顺序展示明细）。
  final int outlineIndex;

  /// 显示名（outline 的 text/title 属性）。
  final String title;

  /// 订阅地址（**原样保留**用户文件里的写法）。规范化在业务层做，解析层不替用户
  /// 改写地址——那样会让「导出回同一个文件」出现难以解释的差异。
  final String xmlUrl;

  /// 从根到该条目所属分组的路径（外层在前）。
  ///
  /// 用路径而不是单个组名：OPML 允许任意深度的嵌套分组（fixture 里就有
  /// Tech → Nested Group）。压平成一个名字会丢掉层级，而「保留文件分组」策略下
  /// 用户期望看到的是他文件里的结构。
  final List<String> groupPath;

  /// 站点地址（htmlUrl 属性）。
  final String? htmlUrl;

  /// 声明的类型（type 属性，通常是 "rss"）。
  final String? type;
}

/// 无效条目的原因。
enum OpmlEntryIssue {
  /// 缺少 xmlUrl：这条 outline 是一个分组或纯说明，不是订阅。
  ///
  /// 单独一类而不是「无效」：OPML 里**分组本来就是没有 xmlUrl 的 outline**，
  /// 把它当错误会淹没真正的问题。
  missingXmlUrl,

  /// xmlUrl 存在但不是可用的 http(s) 地址。
  invalidXmlUrl,

  /// 标题为空：可以入库（用地址兜底），但要让用户知道它没有名字。
  emptyTitle,
}

/// 一个被跳过的条目及其原因。
class OpmlSkippedEntry {
  /// 构造跳过记录。
  const OpmlSkippedEntry({
    required this.index,
    required this.reason,
    this.title,
    this.xmlUrl,
    this.groupPath = const <String>[],
  });

  /// 在文件中的出现序号（从 1 开始，含分组）。
  ///
  /// 用序号而不是「第 N 个订阅」：预览界面要让用户能在文件里找到它，而分组的计数
  /// 方式与用户看到的不一致。序号是「按文档顺序的第几个 outline」。
  final int index;

  /// 跳过原因。
  final OpmlEntryIssue reason;

  /// 条目标题（若有）。
  final String? title;

  /// 条目地址（若有；[OpmlEntryIssue.missingXmlUrl] 时为 null）。
  final String? xmlUrl;

  /// 所属分组路径。
  final List<String> groupPath;
}

/// 一次解析的产物。
class ParsedOpml {
  /// 构造解析结果。
  const ParsedOpml({
    required this.entries,
    required this.skipped,
    required this.groups,
    this.title,
  });

  /// 可用的订阅条目（顺序与文件一致）。
  final List<OpmlEntry> entries;

  /// 被跳过的条目（含原因）。
  final List<OpmlSkippedEntry> skipped;

  /// 文件中出现的全部分组路径（去重，按首次出现顺序）。
  ///
  /// 用于界面提示「文件里有这些分组」，以及「保留文件分组」策略的预览。
  final List<List<String>> groups;

  /// 文件标题（head/title）。
  final String? title;

  /// 是否没有任何可用条目。
  bool get isEmpty => entries.isEmpty;
}

/// 解析一个 OPML 文档。
///
/// 失败一律返回 [ParseError]（类型化），与 feed_parser 保持一致：调用方需要区分
/// 「文件坏了」与「网络失败」，两者的处理策略不同。
Result<ParsedOpml> parseOpml(
  String document, {
  String source = 'opml',
  OpmlParserLimits limits = const OpmlParserLimits(),
}) {
  if (document.trim().isEmpty) {
    return Err<ParsedOpml>(ParseError(source: source, detail: '文档为空'));
  }
  if (document.length > limits.maxDocumentLength) {
    return Err<ParsedOpml>(
      ParseError(
        source: source,
        detail: '文档长度 ${document.length} 超过上限 ${limits.maxDocumentLength}',
      ),
    );
  }

  // ---- 第一道防线：拒绝 DTD 与实体声明 --------------------------------------
  final Result<void> dtdCheck = rejectOpmlDoctypeAndEntities(document, source);
  if (dtdCheck.isErr) {
    return Err<ParsedOpml>(dtdCheck.errorOrNull!);
  }

  // ---- 第二道防线：事件流扫描结构上限，并再次确认没有 doctype ----------------
  final Result<void> structureCheck = _scanOpmlEvents(document, source, limits);
  if (structureCheck.isErr) {
    return Err<ParsedOpml>(structureCheck.errorOrNull!);
  }

  // ---- 建树并取值 ---------------------------------------------------------
  final XmlDocument xml;
  try {
    xml = XmlDocument.parse(document);
  } on XmlException catch (error) {
    // 只保留结构性描述（类型名），不把原文塞进错误里。
    return Err<ParsedOpml>(
      ParseError(
        source: source,
        detail: 'XML 结构非法（${error.runtimeType}）',
        cause: error,
      ),
    );
  } on Exception catch (error) {
    return Err<ParsedOpml>(
      ParseError(
        source: source,
        detail: 'XML 解析失败（${error.runtimeType}）',
        cause: error,
      ),
    );
  }

  final XmlElement? root = xml.childElements.firstOrNull;
  if (root == null) {
    return Err<ParsedOpml>(ParseError(source: source, detail: '缺少根元素'));
  }
  if (root.name.local.toLowerCase() != 'opml') {
    return Err<ParsedOpml>(
      ParseError(
        source: source,
        detail: '根元素不是 <opml>（实际 <${root.name.local}>）',
      ),
    );
  }

  final XmlElement? body = _findElement(root, 'body');
  if (body == null) {
    return Err<ParsedOpml>(ParseError(source: source, detail: '缺少 <body>'));
  }

  final List<OpmlEntry> entries = <OpmlEntry>[];
  final List<OpmlSkippedEntry> skipped = <OpmlSkippedEntry>[];
  final List<List<String>> groups = <List<String>>[];
  final Set<String> seenGroupKeys = <String>{};
  int outlineIndex = 0;

  // 深度优先遍历 body 下的 outline 树。
  //
  // 用显式递归而不是「收集所有 outline 再按深度字段排序」：后者依赖文档顺序与
  // 深度字段的一致性，而畸形文件里两者可以矛盾。递归保证分组归属来自**实际嵌套**。
  void walk(XmlElement parent, List<String> path) {
    for (final XmlElement outline in _findElements(parent, 'outline')) {
      outlineIndex++;
      if (entries.length >= limits.maxEntries) {
        return;
      }
      final String? rawXmlUrl = _nonEmpty(outline.getAttribute('xmlUrl'));
      final String? title =
          _nonEmpty(outline.getAttribute('text')) ??
          _nonEmpty(outline.getAttribute('title'));
      final String? htmlUrl = _nonEmpty(outline.getAttribute('htmlUrl'));
      final String? type = _nonEmpty(outline.getAttribute('type'));

      if (rawXmlUrl == null) {
        // 没有 xmlUrl：是分组或说明性 outline。
        final bool hasChildren = _findElements(outline, 'outline').isNotEmpty;
        if (hasChildren) {
          final String groupName = title ?? '';
          final List<String> childPath = groupName.isEmpty
              ? path
              : <String>[...path, groupName];
          if (groupName.isNotEmpty) {
            final String key = childPath.join('\u0000');
            if (seenGroupKeys.add(key)) {
              groups.add(childPath);
            }
          }
          walk(outline, childPath);
          continue;
        }
        // 既没有地址也没有子节点：记录为无效项（用户文件里常有这类残留）。
        skipped.add(
          OpmlSkippedEntry(
            index: outlineIndex,
            reason: OpmlEntryIssue.missingXmlUrl,
            title: title,
            groupPath: path,
          ),
        );
        continue;
      }

      final String? validation = validateSubscribeUrl(rawXmlUrl);
      if (validation != null) {
        skipped.add(
          OpmlSkippedEntry(
            index: outlineIndex,
            reason: OpmlEntryIssue.invalidXmlUrl,
            title: title,
            xmlUrl: rawXmlUrl,
            groupPath: path,
          ),
        );
        continue;
      }

      entries.add(
        OpmlEntry(
          outlineIndex: outlineIndex,
          // 标题为空用地址兜底：列表里一行空白无法辨认，也没法搜索。
          title: title ?? rawXmlUrl,
          xmlUrl: rawXmlUrl,
          groupPath: path,
          htmlUrl: htmlUrl,
          type: type,
        ),
      );
    }
  }

  walk(body, const <String>[]);

  final XmlElement? head = _findElement(root, 'head');
  return Ok<ParsedOpml>(
    ParsedOpml(
      entries: entries,
      skipped: skipped,
      groups: groups,
      title: head == null
          ? null
          : _nonEmpty(_findElement(head, 'title')?.innerText),
    ),
  );
}

/// 校验一个订阅地址是否可用；返回 null 表示可用，否则返回原因文案。
/// 把解析层的跳过原因翻译成用户可读的说明。
///
/// 放在解析层而不是用例层：原因与枚举在同一个文件里定义，改枚举时忘记改文案的
/// 位置只有一个（编译器还会提示 switch 不穷尽）。
String describeOpmlIssue(OpmlEntryIssue issue) => switch (issue) {
  OpmlEntryIssue.missingXmlUrl => '缺少订阅地址（xmlUrl）',
  OpmlEntryIssue.invalidXmlUrl => '订阅地址不可用（不是 http/https 的完整 URL）',
  OpmlEntryIssue.emptyTitle => '缺少名称',
};

///
/// 只接受 http/https，与添加订阅的规则一致：架构第 8 节的边界校验要求，且不接受
/// feed:// 之类的私有 scheme（导入后无法请求）。
String? validateSubscribeUrl(String raw) {
  final String trimmed = raw.trim();
  if (trimmed.isEmpty) {
    return '地址为空';
  }
  final Uri? uri = Uri.tryParse(trimmed);
  if (uri == null || !uri.hasScheme) {
    return '不是完整 URL';
  }
  if (!uri.isScheme('http') && !uri.isScheme('https')) {
    return '只支持 http/https（实际 ${uri.scheme}）';
  }
  if (uri.host.isEmpty) {
    return '缺少主机名';
  }
  return null;
}

/// 拒绝 DTD 与实体声明（与 feed_parser 同一条防线，独立实现以便各自演进）。
Result<void> rejectOpmlDoctypeAndEntities(String document, String source) {
  final RegExp doctype = RegExp(r'<\s*!\s*DOCTYPE', caseSensitive: false);
  final RegExp entity = RegExp(r'<\s*!\s*ENTITY', caseSensitive: false);
  final RegExpMatch? doctypeMatch = doctype.firstMatch(document);
  final RegExpMatch? entityMatch = entity.firstMatch(document);
  if (doctypeMatch == null && entityMatch == null) {
    return const Ok<void>(null);
  }

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

/// 事件流结构扫描：深度、节点数、doctype 二次确认。
Result<void> _scanOpmlEvents(
  String document,
  String source,
  OpmlParserLimits limits,
) {
  int depth = 0;
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
    // 事件流与 DOM 的容忍度不同；这里只处理深度类错误，其余交给 DOM 给出一致结果。
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
// 导出
// ===========================================================================

/// 一个待导出的订阅（只含 OPML 能表达的标准字段）。
class OpmlExportEntry {
  /// 构造导出条目。
  const OpmlExportEntry({
    required this.title,
    required this.xmlUrl,
    this.htmlUrl = '',
    this.groupPath = const <String>[],
  });

  /// 订阅名。
  final String title;

  /// 订阅地址（调用方应传**规范化**地址）。
  final String xmlUrl;

  /// 站点地址。
  final String htmlUrl;

  /// 分组路径（外层在前）；空表示直接挂在 body 下。
  final List<String> groupPath;
}

/// 生成一个标准 OPML 2.0 文档。
///
/// 只写 OPML 规范定义的标准字段（text/title/type/xmlUrl/htmlUrl 与分组嵌套），
/// **不写**任何应用内部字段：架构 4.1 明确要求「不保证保留 Flux 内部 ID、加精/刷新
/// 偏好或阅读状态」，也不得为实现往返而伪造通用格式不包含的字段。
///
/// 因此这里也不写 flux: 之类的自定义属性——那会让别的阅读器收到无法理解的字段，
/// 而用户以为「导出就是完整备份」。完整备份是 T046 的职责。
String buildOpml({
  required List<OpmlExportEntry> entries,
  String title = 'Flux Subscriptions',
  DateTime? createdAt,
}) {
  final StringBuffer buffer = StringBuffer();
  buffer.writeln('<?xml version="1.0" encoding="UTF-8"?>');
  buffer.writeln('<opml version="2.0">');
  buffer.writeln('  <head>');
  buffer.writeln('    <title>${_escapeXml(title)}</title>');
  buffer.writeln(
    '    <dateCreated>${_rfc822(createdAt ?? DateTime.now().toUtc())}</dateCreated>',
  );
  buffer.writeln('  </head>');
  buffer.writeln('  <body>');

  // 按分组路径建树后递归输出，使同一分组的订阅落在一个 folder 里。
  final _ExportNode root = _ExportNode();
  for (final OpmlExportEntry entry in entries) {
    _ExportNode node = root;
    for (final String segment in entry.groupPath) {
      if (segment.isEmpty) {
        continue;
      }
      node = node.children.putIfAbsent(segment, _ExportNode.new);
    }
    node.entries.add(entry);
  }

  void write(_ExportNode node, int indent) {
    final String pad = '  ' * indent;
    for (final OpmlExportEntry entry in node.entries) {
      final StringBuffer line = StringBuffer('$pad<outline type="rss"');
      line.write(' text="${_escapeXml(entry.title)}"');
      line.write(' title="${_escapeXml(entry.title)}"');
      line.write(' xmlUrl="${_escapeXml(entry.xmlUrl)}"');
      if (entry.htmlUrl.isNotEmpty) {
        line.write(' htmlUrl="${_escapeXml(entry.htmlUrl)}"');
      }
      line.write('/>');
      buffer.writeln(line);
    }
    for (final MapEntry<String, _ExportNode> child in node.children.entries) {
      buffer.writeln(
        '$pad<outline text="${_escapeXml(child.key)}" '
        'title="${_escapeXml(child.key)}">',
      );
      write(child.value, indent + 1);
      buffer.writeln('$pad</outline>');
    }
  }

  write(root, 2);
  buffer.writeln('  </body>');
  buffer.writeln('</opml>');
  return buffer.toString();
}

/// 导出树的一个节点。
class _ExportNode {
  /// 按分组名索引的子节点（Map 的插入顺序即输出顺序）。
  final Map<String, _ExportNode> children = <String, _ExportNode>{};

  /// 直接挂在该节点下的订阅。
  final List<OpmlExportEntry> entries = <OpmlExportEntry>[];
}

// ===========================================================================
// XML 小工具
// ===========================================================================

XmlElement? _findElement(XmlElement parent, String localName) =>
    _findElements(parent, localName).firstOrNull;

/// 按本地名找子元素（忽略命名空间前缀与大小写）。
Iterable<XmlElement> _findElements(XmlElement parent, String localName) {
  final String needle = localName.toLowerCase();
  return parent.childElements.where(
    (XmlElement e) => e.name.local.toLowerCase() == needle,
  );
}

String? _nonEmpty(String? value) {
  if (value == null) {
    return null;
  }
  final String trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

/// XML 属性/文本转义。
String _escapeXml(String input) => input
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

/// RFC 822 时间（OPML 的 dateCreated 惯例）。
String _rfc822(DateTime utc) {
  const List<String> weekdays = <String>[
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
  ];
  const List<String> months = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final DateTime value = utc.toUtc();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${weekdays[value.weekday - 1]}, ${two(value.day)} '
      '${months[value.month - 1]} ${value.year} '
      '${two(value.hour)}:${two(value.minute)}:${two(value.second)} GMT';
}
