// Markdown → 受控文档树（T019；架构 4.2「渲染受控文档树」）。
//
// 这里只调用 markdown 包的**解析器**（文本 → 节点列表），从不调用它的 HTML renderer，
// 也没有任何 HTML 字符串进入界面：每个节点都被映射成一个显式的 [DocNode]，因此渲染层
// 永远知道「可能出现的构造有哪些」。这条路线与 T013 的 HTML 清洗路径共用同一棵树。
//
// 扩展集：GitHub Flavored **减去**原始 HTML 透传。原始 HTML 有意不被带进树里——它以
// 可见文本的形式出现，使文档无法通过一个标签或脚本穿到渲染器。
//
// 与 T004 原型的关系：原型验证了这条路线可行，本文件按同样思路移植其映射规则（节点
// 种类、未知构造保留可见、危险 URL 在解析期拒绝），并把「未映射」统一成
// [DocRawFallback] / [DocUnsupportedInline]（原型里叫 DocRawFallback / DocUnsupportedInline）。
library;

import 'package:markdown/markdown.dart' as md;

import 'package:flux/core/core.dart';

import 'markdown_math.dart';

/// 把 Markdown 解析成受控文档树。
DocDocument parseMarkdownToDocument(String markdown) {
  final ProtectedDocument protected = protectMath(markdown);
  final md.Document document = md.Document(
    extensionSet: md.ExtensionSet.gitHubFlavored,
    encodeHtml: true,
  );
  final List<md.Node> nodes = document.parse(protected.markdown);
  final _ParseContext context = _ParseContext(protected.math);
  return DocDocument(_convertBlocks(nodes, context));
}

/// 一次解析的上下文（公式表）。
class _ParseContext {
  _ParseContext(this.math);

  final List<String> math;

  /// 取第 [index] 段公式；编号越界时如实返回一个「无法渲染」节点而不是空字符串。
  DocInline mathInline(int index) {
    if (index < 0 || index >= math.length) {
      return DocUnsupportedMath(
        raw: mathSentinel(index),
        reason: 'missing math payload',
      );
    }
    return DocMathInline(math[index]);
  }

  String? texAt(int index) =>
      index < 0 || index >= math.length ? null : math[index];
}

List<DocNode> _convertBlocks(List<md.Node> nodes, _ParseContext context) {
  final List<DocNode> out = <DocNode>[];
  for (final md.Node node in nodes) {
    final DocNode? converted = _convertBlock(node, context);
    if (converted != null) {
      out.add(converted);
    }
  }
  return out;
}

DocNode? _convertBlock(md.Node node, _ParseContext context) {
  if (node is md.Text) {
    final String text = node.text;
    if (text.trim().isEmpty) {
      return null;
    }
    // 单独一个哨兵就是独占公式：Markdown 解析器把独占一行看起来像段落的哨兵包进了
    // 段落，因此这里要把它还原成块级公式。
    if (text.trim().length == text.length) {
      final int? index = mathSentinelIndex(text);
      if (index != null) {
        return DocMathBlock(context.texAt(index) ?? text);
      }
    }
    final List<DocInline> inlines = _convertInlines(<md.Node>[
      md.Text(text),
    ], context);
    if (inlines.isEmpty) {
      return null;
    }
    return DocParagraph(inlines);
  }
  if (node is! md.Element) {
    return DocRawFallback(
      node.textContent,
      reason: 'unmapped node type ${node.runtimeType}',
    );
  }
  final md.Element element = node;
  switch (element.tag) {
    case 'h1':
    case 'h2':
    case 'h3':
    case 'h4':
    case 'h5':
    case 'h6':
      final int level = int.parse(element.tag.substring(1));
      return DocHeading(
        level,
        _convertInlines(element.children ?? const <md.Node>[], context),
      );
    case 'p':
      final List<md.Node> children = element.children ?? const <md.Node>[];
      final DocMathBlock? mathBlock = _sentinelOnlyMathBlock(children, context);
      if (mathBlock != null) {
        return mathBlock;
      }
      final DocImageBlock? onlyImage = _soleImageBlock(children);
      if (onlyImage != null) {
        return onlyImage;
      }
      return DocParagraph(_convertInlines(children, context));
    case 'blockquote':
      return DocBlockQuote(
        _convertBlocks(element.children ?? const <md.Node>[], context),
      );
    case 'ul':
      return _convertList(element, context, ordered: false);
    case 'ol':
      return _convertList(element, context, ordered: true);
    case 'pre':
      return _convertCodeBlock(element);
    case 'hr':
      return const DocThematicBreak();
    case 'table':
      return _convertTable(element, context);
    case 'img':
      final String src = element.attributes['src'] ?? '';
      final String alt = element.attributes['alt'] ?? '';
      if (!isSafeDocUrl(src)) {
        return DocParagraph(<DocInline>[
          DocRejectedUrl(url: src, label: alt, reason: 'blocked image scheme'),
        ]);
      }
      return DocImageBlock(url: src, alt: alt);
    default:
      // 不支持的块（脚注定义、原始 HTML 文本、告示框…）：保留原文可见，
      // 而不是静默丢弃。
      return DocRawFallback(
        element.textContent,
        reason: 'unsupported block <${element.tag}>',
      );
  }
}

/// [children] 恰好是一个公式哨兵时返回块级公式。
DocMathBlock? _sentinelOnlyMathBlock(
  List<md.Node> children,
  _ParseContext context,
) {
  if (children.length != 1) {
    return null;
  }
  final md.Node only = children.first;
  if (only is! md.Text) {
    return null;
  }
  final String text = only.text.trim();
  final int? index = mathSentinelIndex(text);
  if (index == null) {
    return null;
  }
  return DocMathBlock(context.texAt(index) ?? text);
}

/// [children] 恰好是一张图片时返回块级图片；否则 null。
DocImageBlock? _soleImageBlock(List<md.Node> children) {
  if (children.length != 1) {
    return null;
  }
  final md.Node only = children.first;
  if (only is! md.Element || only.tag != 'img') {
    return null;
  }
  final String src = only.attributes['src'] ?? '';
  if (!isSafeDocUrl(src)) {
    return null;
  }
  return DocImageBlock(url: src, alt: only.attributes['alt'] ?? '');
}

DocCodeBlock? _convertCodeBlock(md.Element pre) {
  final List<md.Node> children = pre.children ?? const <md.Node>[];
  for (final md.Node child in children) {
    if (child is md.Element && child.tag == 'code') {
      final String code = child.textContent;
      final String className = child.attributes['class'] ?? '';
      String? language;
      if (className.startsWith('language-')) {
        final String value = className.substring('language-'.length).trim();
        if (value.isNotEmpty) {
          language = value;
        }
      }
      return DocCodeBlock(code: code, language: language);
    }
  }
  return DocCodeBlock(code: pre.textContent);
}

DocList _convertList(
  md.Element element,
  _ParseContext context, {
  required bool ordered,
}) {
  int start = 1;
  if (ordered) {
    final String? raw = element.attributes['start'];
    if (raw != null) {
      start = int.tryParse(raw) ?? 1;
    }
  }
  final List<DocListItem> items = <DocListItem>[];
  for (final md.Node child in element.children ?? const <md.Node>[]) {
    if (child is! md.Element || child.tag != 'li') {
      continue;
    }
    bool? checked;
    if (child.attributes['data-checked'] == 'true') {
      checked = true;
    } else if (child.attributes['data-checked'] == 'false') {
      checked = false;
    }
    final List<md.Node> contents = <md.Node>[];
    for (final md.Node grand in child.children ?? const <md.Node>[]) {
      if (grand is md.Element && grand.tag == 'input') {
        checked = grand.attributes['checked'] != null;
        continue;
      }
      contents.add(grand);
    }
    items.add(
      DocListItem(
        children: _convertBlocks(contents, context),
        checked: checked,
      ),
    );
  }
  return DocList(ordered: ordered, start: start, items: items);
}

DocTable _convertTable(md.Element table, _ParseContext context) {
  final List<List<DocInline>> header = <List<DocInline>>[];
  final List<List<List<DocInline>>> rows = <List<List<DocInline>>>[];
  List<String?> alignments = <String?>[];
  for (final md.Node section in table.children ?? const <md.Node>[]) {
    if (section is! md.Element) {
      continue;
    }
    if (section.tag == 'thead') {
      for (final md.Node row in section.children ?? const <md.Node>[]) {
        if (row is! md.Element || row.tag != 'tr') {
          continue;
        }
        for (final md.Node cell in row.children ?? const <md.Node>[]) {
          if (cell is! md.Element || (cell.tag != 'th' && cell.tag != 'td')) {
            continue;
          }
          header.add(
            _convertInlines(cell.children ?? const <md.Node>[], context),
          );
          alignments.add(cell.attributes['align']);
        }
      }
    } else if (section.tag == 'tbody') {
      for (final md.Node row in section.children ?? const <md.Node>[]) {
        if (row is! md.Element || row.tag != 'tr') {
          continue;
        }
        final List<List<DocInline>> cells = <List<DocInline>>[];
        for (final md.Node cell in row.children ?? const <md.Node>[]) {
          if (cell is! md.Element || (cell.tag != 'th' && cell.tag != 'td')) {
            continue;
          }
          cells.add(
            _convertInlines(cell.children ?? const <md.Node>[], context),
          );
        }
        rows.add(cells);
      }
    }
  }
  final int width = header.isNotEmpty
      ? header.length
      : (rows.isEmpty ? 0 : rows.first.length);
  if (alignments.length < width) {
    alignments = <String?>[
      ...alignments,
      ...List<String?>.filled(width - alignments.length, null),
    ];
  }
  return DocTable(header: header, rows: rows, alignments: alignments);
}

List<DocInline> _convertInlines(List<md.Node> nodes, _ParseContext context) {
  final List<DocInline> out = <DocInline>[];
  for (final md.Node node in nodes) {
    _appendInline(out, node, context);
  }
  return _mergeAdjacentText(out);
}

void _appendInline(List<DocInline> out, md.Node node, _ParseContext context) {
  if (node is md.Text) {
    _appendTextWithMath(out, node.text, context);
    return;
  }
  if (node is! md.Element) {
    out.add(
      DocUnsupportedInline(
        text: node.textContent,
        reason: 'unmapped inline node ${node.runtimeType}',
      ),
    );
    return;
  }
  final md.Element element = node;
  switch (element.tag) {
    case 'em':
      out.add(
        DocEmphasis(
          _convertInlines(element.children ?? const <md.Node>[], context),
        ),
      );
    case 'strong':
      out.add(
        DocStrong(
          _convertInlines(element.children ?? const <md.Node>[], context),
        ),
      );
    case 'del':
      out.add(
        DocStrikethrough(
          _convertInlines(element.children ?? const <md.Node>[], context),
        ),
      );
    case 'code':
      out.add(DocCodeSpan(element.textContent));
    case 'softbreak':
      out.add(const DocSoftBreak());
    case 'a':
      final String href = element.attributes['href'] ?? '';
      final List<DocInline> children = _convertInlines(
        element.children ?? const <md.Node>[],
        context,
      );
      if (!isSafeDocUrl(href)) {
        out.add(
          DocRejectedUrl(
            url: href,
            label: docInlinePlainText(children),
            reason: 'blocked link scheme',
          ),
        );
      } else {
        out.add(DocLinkInline(url: href, children: children));
      }
    case 'img':
      final String src = element.attributes['src'] ?? '';
      final String alt = element.attributes['alt'] ?? '';
      if (!isSafeDocUrl(src)) {
        out.add(
          DocRejectedUrl(url: src, label: alt, reason: 'blocked image scheme'),
        );
      } else {
        out.add(DocImageInline(url: src, alt: alt));
      }
    case 'br':
      out.add(const DocHardBreak());
    case 'input':
      // 任务列表的勾选框：状态已经挂在列表项上，这里不再产出重复节点。
      break;
    default:
      out.add(
        DocUnsupportedInline(
          text: element.textContent,
          reason: 'unsupported inline <${element.tag}>',
        ),
      );
  }
}

/// 按哨兵切分 Markdown 文本并逐个追加。
void _appendTextWithMath(
  List<DocInline> out,
  String text,
  _ParseContext context,
) {
  if (text.isEmpty) {
    return;
  }
  int cursor = 0;
  while (true) {
    final int at = text.indexOf(kMathSentinelPrefix, cursor);
    if (at == -1) {
      if (cursor < text.length) {
        out.add(DocText(text.substring(cursor)));
      }
      return;
    }
    final int endAt = text.indexOf(
      kMathSentinelSuffix,
      at + kMathSentinelPrefix.length,
    );
    if (endAt == -1) {
      out.add(DocText(text.substring(cursor)));
      return;
    }
    if (at > cursor) {
      out.add(DocText(text.substring(cursor, at)));
    }
    final String token = text.substring(at, endAt + kMathSentinelSuffix.length);
    final int? index = mathSentinelIndex(token);
    if (index == null) {
      out.add(DocText(token));
    } else {
      out.add(context.mathInline(index));
    }
    cursor = endAt + kMathSentinelSuffix.length;
  }
}

List<DocInline> _mergeAdjacentText(List<DocInline> nodes) {
  final List<DocInline> out = <DocInline>[];
  for (final DocInline node in nodes) {
    if (node is DocText && out.isNotEmpty && out.last is DocText) {
      final DocText previous = out.removeLast() as DocText;
      out.add(DocText(previous.text + node.text));
    } else {
      out.add(node);
    }
  }
  return out;
}
