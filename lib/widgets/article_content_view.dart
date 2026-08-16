import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import '../theme/flux_theme.dart';
import 'lazy_network_image.dart';

/// 将 RSS 中的 HTML 正文渲染为可阅读的 Flutter 组件。
///
/// 支持：
/// - 标题、段落、列表、引用、代码块、表格、分割线
/// - 图片懒加载
/// - 行内 Markdown：**加粗**、*斜体*、`代码`、[链接](url)
/// - TeX 公式：`$...$` 行内公式、`$$...$$` 块级公式（KaTeX 风格渲染）
class ArticleContentView extends StatelessWidget {
  const ArticleContentView({
    super.key,
    required this.html,
    this.baseUrl,
    this.fontSize = 16,
    this.onOpenLink,
  });

  final String html;
  final String? baseUrl;
  final double fontSize;
  final void Function(String url)? onOpenLink;

  @override
  Widget build(BuildContext context) {
    final cleanedHtml = _cleanHtml(html);
    final document = html_parser.parse(cleanedHtml);
    final body = document.body;
    if (body == null) {
      return const SizedBox.shrink();
    }

    final baseStyle =
        Theme.of(context).textTheme.bodyLarge
            ?.copyWith(fontSize: fontSize, height: 1.7) ??
        TextStyle(fontSize: fontSize, height: 1.7);

    final blocks = _buildBlocks(context, body.nodes, baseStyle);
    return SelectionArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: blocks,
      ),
    );
  }

  // ============ Block-level ============

  List<Widget> _buildBlocks(
    BuildContext context,
    List<dom.Node> nodes,
    TextStyle baseStyle,
  ) {
    final result = <Widget>[];
    for (var i = 0; i < nodes.length; i++) {
      final node = nodes[i];
      if (node is dom.Element) {
        // 过滤文章结尾的“本文首发/版权”页脚。
        if (_isFooterParagraph(node)) {
          continue;
        }
        if ((node.localName ?? '').toLowerCase() == 'hr' &&
            _hasFooterAfter(nodes, i + 1)) {
          continue;
        }
        result.addAll(_buildElementBlock(context, node, baseStyle));
      } else if (node is dom.Text) {
        final text = node.text.trim();
        if (text.isNotEmpty) {
          result.add(_buildTextBlock(context, text, baseStyle));
        }
      }
    }
    return result;
  }

  bool _isFooterParagraph(dom.Element element) {
    if ((element.localName ?? '').toLowerCase() != 'p') {
      return false;
    }
    final text = element.text;
    return text.contains('首发于') &&
        (text.contains('本博客所有文章') || text.contains('BY-NC-SA'));
  }

  bool _hasFooterAfter(List<dom.Node> nodes, int start) {
    for (var i = start; i < nodes.length; i++) {
      final node = nodes[i];
      if (node is dom.Element && _isFooterParagraph(node)) {
        return true;
      }
    }
    return false;
  }

  List<Widget> _buildElementBlock(
    BuildContext context,
    dom.Element element,
    TextStyle baseStyle,
  ) {
    final name = element.localName?.toLowerCase() ?? '';
    switch (name) {
      case 'h1':
      case 'h2':
      case 'h3':
      case 'h4':
      case 'h5':
      case 'h6':
        return [_buildHeading(context, element, baseStyle)];
      case 'p':
        return [_buildParagraph(context, element, baseStyle)];
      case 'img':
        return [_buildImage(context, element, baseStyle)];
      case 'ul':
        return _buildList(context, element, baseStyle, ordered: false);
      case 'ol':
        return _buildList(context, element, baseStyle, ordered: true);
      case 'pre':
        return [_buildCodeBlock(context, element, baseStyle)];
      case 'blockquote':
        return [_buildBlockquote(context, element, baseStyle)];
      case 'table':
        return [_buildTable(context, element, baseStyle)];
      case 'hr':
        return [
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Divider(),
          ),
        ];
      case 'div':
      case 'section':
      case 'article':
      case 'main':
      case 'figure':
        return _buildBlocks(context, element.nodes, baseStyle);
      case 'script':
      case 'style':
      case 'head':
      case 'meta':
      case 'link':
        return const [];
      default:
        return [_buildParagraph(context, element, baseStyle)];
    }
  }

  Widget _buildHeading(
    BuildContext context,
    dom.Element element,
    TextStyle baseStyle,
  ) {
    final level = int.tryParse((element.localName ?? '').substring(1)) ?? 2;
    final size = switch (level) {
      1 => 28.0,
      2 => 24.0,
      3 => 20.0,
      4 => 18.0,
      5 => 16.0,
      _ => 15.0,
    };
    final style = baseStyle.copyWith(
      fontSize: size,
      fontWeight: FontWeight.w800,
      height: 1.35,
    );
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 6),
      child: Text.rich(
        TextSpan(children: _buildInlineSpans(context, element.nodes, style)),
        style: style,
      ),
    );
  }

  Widget _buildParagraph(
    BuildContext context,
    dom.Element element,
    TextStyle baseStyle,
  ) {
    // 如果段落只包含图片，按块级大图渲染，而不是缩成行内小图。
    final directImages = element.nodes
        .whereType<dom.Element>()
        .where((e) => (e.localName ?? '').toLowerCase() == 'img')
        .toList();
    final hasText = element.nodes.any(
      (n) => n is dom.Text && n.text.trim().isNotEmpty,
    );
    final hasOtherElement = element.nodes.any(
      (n) => n is dom.Element && (n.localName ?? '').toLowerCase() != 'img',
    );
    if (directImages.isNotEmpty && !hasText && !hasOtherElement) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final img in directImages) _buildImage(context, img, baseStyle),
        ],
      );
    }

    // 如果段落包含块级公式，按块级公式拆分渲染，避免大公式塞进 Text.rich。
    if (RegExp(r'\$\$.+?\$\$', dotAll: true).hasMatch(element.text)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: _buildTextBlocks(context, element.text, baseStyle),
      );
    }

    final spans = _buildInlineSpans(context, element.nodes, baseStyle);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text.rich(TextSpan(children: spans), style: baseStyle),
    );
  }

  Widget _buildTextBlock(
    BuildContext context,
    String text,
    TextStyle baseStyle,
  ) {
    if (RegExp(r'\$\$.+?\$\$', dotAll: true).hasMatch(text)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: _buildTextBlocks(context, text, baseStyle),
      );
    }
    final spans = _parseInlineText(context, text, baseStyle);
    if (spans.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text.rich(TextSpan(children: spans), style: baseStyle),
    );
  }

  /// 将包含 `$$...$$` 的文本拆成“普通段落 + 块级公式”的列表。
  List<Widget> _buildTextBlocks(
    BuildContext context,
    String text,
    TextStyle baseStyle,
  ) {
    final result = <Widget>[];
    final pattern = RegExp(r'\$\$(.+?)\$\$', dotAll: true);
    var last = 0;

    for (final match in pattern.allMatches(text)) {
      final before = text.substring(last, match.start);
      if (before.trim().isNotEmpty) {
        result.add(_buildTextBlock(context, before, baseStyle));
      }
      final tex = _sanitizeTex(match.group(1) ?? '');
      if (tex.isNotEmpty) {
        result.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Math.tex(
              tex,
              mathStyle: MathStyle.display,
              textStyle: baseStyle,
            ),
          ),
        );
      }
      last = match.end;
    }

    final after = text.substring(last);
    if (after.trim().isNotEmpty) {
      result.add(_buildTextBlock(context, after, baseStyle));
    }

    return result;
  }

  Widget _buildImage(
    BuildContext context,
    dom.Element element,
    TextStyle baseStyle,
  ) {
    final src =
        element.attributes['src'] ??
        element.attributes['data-src'] ??
        element.attributes['data-lazy-src'];
    if (src == null || src.isEmpty) {
      return const SizedBox.shrink();
    }
    final resolved = _resolveUrl(src);
    final alt = element.attributes['alt'] ?? '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: FractionallySizedBox(
              // 图片锁定在内容区约 0.9 幅宽，避免过小或贴边。
              widthFactor: 0.9,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: 120,
                  maxHeight: 420,
                ),
                child: LazyNetworkImage(
                  url: resolved,
                  width: double.infinity,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
          if (alt.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                alt,
                textAlign: TextAlign.center,
                style: baseStyle.copyWith(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _buildList(
    BuildContext context,
    dom.Element element,
    TextStyle baseStyle, {
    required bool ordered,
  }) {
    final items = element.nodes
        .whereType<dom.Element>()
        .where((e) => (e.localName ?? '').toLowerCase() == 'li')
        .toList();
    final result = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      final marker = ordered ? '${i + 1}.' : '•';
      result.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 28,
                child: Text(
                  marker,
                  style: baseStyle.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              Expanded(
                child: _buildListItemContent(context, items[i], baseStyle),
              ),
            ],
          ),
        ),
      );
    }
    return result;
  }

  Widget _buildListItemContent(
    BuildContext context,
    dom.Element li,
    TextStyle baseStyle,
  ) {
    final hasBlockChild = li.nodes.any(
      (n) =>
          n is dom.Element &&
          const {
            'p',
            'ul',
            'ol',
            'pre',
            'blockquote',
            'table',
            'div',
          }.contains(n.localName?.toLowerCase() ?? ''),
    );
    if (!hasBlockChild) {
      return Text.rich(
        TextSpan(children: _buildInlineSpans(context, li.nodes, baseStyle)),
        style: baseStyle,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: _buildBlocks(context, li.nodes, baseStyle),
    );
  }

  Widget _buildCodeBlock(
    BuildContext context,
    dom.Element element,
    TextStyle baseStyle,
  ) {
    final code = element.text.trim();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? FluxColors.darkRaised : const Color(0xFFF0ECE3),
        borderRadius: BorderRadius.circular(2),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Text(
        code,
        style: baseStyle.copyWith(
          fontFamily: 'monospace',
          fontSize: 14,
          height: 1.5,
        ),
      ),
    );
  }

  Widget _buildBlockquote(
    BuildContext context,
    dom.Element element,
    TextStyle baseStyle,
  ) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: FluxColors.red.withValues(alpha: 0.7),
            width: 3,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: _buildBlocks(context, element.nodes, baseStyle),
      ),
    );
  }

  Widget _buildTable(
    BuildContext context,
    dom.Element element,
    TextStyle baseStyle,
  ) {
    final rows = element
        .querySelectorAll('tr')
        .map((tr) => tr.querySelectorAll('td,th'))
        .where((cells) => cells.isNotEmpty)
        .toList();
    if (rows.isEmpty) {
      return const SizedBox.shrink();
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Table(
        defaultColumnWidth: const FixedColumnWidth(140),
        border: TableBorder.all(color: Theme.of(context).dividerColor),
        children: [
          for (final cells in rows)
            TableRow(
              children: [
                for (final cell in cells)
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text.rich(
                      TextSpan(
                        children: _buildInlineSpans(
                          context,
                          cell.nodes,
                          baseStyle.copyWith(
                            fontWeight:
                                (cell.localName ?? '').toLowerCase() == 'th'
                                ? FontWeight.w800
                                : FontWeight.w400,
                          ),
                        ),
                      ),
                      style: baseStyle.copyWith(fontSize: 14),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  // ============ Inline-level ============

  List<InlineSpan> _buildInlineSpans(
    BuildContext context,
    List<dom.Node> nodes,
    TextStyle baseStyle,
  ) {
    final spans = <InlineSpan>[];
    for (final node in nodes) {
      if (node is dom.Text) {
        final text = _normalizeInlineText(node.text);
        if (text.isEmpty) {
          continue;
        }
        spans.addAll(_parseInlineText(context, text, baseStyle));
      } else if (node is dom.Element) {
        spans.addAll(_buildElementInline(context, node, baseStyle));
      }
    }
    return spans;
  }

  List<InlineSpan> _buildElementInline(
    BuildContext context,
    dom.Element element,
    TextStyle baseStyle,
  ) {
    // 跳过 Hugo 生成的标题锚点空链接。
    if ((element.attributes['class'] ?? '').contains('header-anchor')) {
      return const [];
    }
    final name = element.localName?.toLowerCase() ?? '';
    switch (name) {
      case 'br':
        return const [TextSpan(text: '\n')];
      case 'strong':
      case 'b':
        return [
          TextSpan(
            style: baseStyle.copyWith(fontWeight: FontWeight.w800),
            children: _buildInlineSpans(context, element.nodes, baseStyle),
          ),
        ];
      case 'em':
      case 'i':
        return [
          TextSpan(
            style: baseStyle.copyWith(fontStyle: FontStyle.italic),
            children: _buildInlineSpans(context, element.nodes, baseStyle),
          ),
        ];
      case 'code':
        return [
          TextSpan(
            style: baseStyle.copyWith(
              fontFamily: 'monospace',
              fontSize: baseStyle.fontSize! - 1,
              backgroundColor: Theme.of(context)
                  .colorScheme
                  .surfaceContainerHighest,
            ),
            children: _buildInlineSpans(context, element.nodes, baseStyle),
          ),
        ];
      case 'a':
        final href = element.attributes['href'] ?? '';
        final resolved = _resolveUrl(href);
        return [
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: GestureDetector(
              onTap: resolved.isEmpty ? null : () => onOpenLink?.call(resolved),
              child: Text.rich(
                TextSpan(
                  style: baseStyle.copyWith(
                    color: FluxColors.red,
                    decoration: TextDecoration.underline,
                  ),
                  children: _buildInlineSpans(
                    context,
                    element.nodes,
                    baseStyle,
                  ),
                ),
              ),
            ),
          ),
        ];
      case 'img':
        final src =
            element.attributes['src'] ??
            element.attributes['data-src'] ??
            element.attributes['data-lazy-src'];
        if (src == null || src.isEmpty) {
          return const [];
        }
        return [
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: LazyNetworkImage(
                url: _resolveUrl(src),
                width: 140,
                height: 100,
                fit: BoxFit.cover,
              ),
            ),
          ),
        ];
      default:
        return _buildInlineSpans(context, element.nodes, baseStyle);
    }
  }

  // ============ Markdown / Math inline ============

  List<InlineSpan> _parseInlineText(
    BuildContext context,
    String text,
    TextStyle baseStyle,
  ) {
    final spans = <InlineSpan>[];
    final buffer = StringBuffer();
    var i = 0;

    void flush() {
      if (buffer.isNotEmpty) {
        spans.addAll(_parseMarkdown(buffer.toString(), baseStyle));
        buffer.clear();
      }
    }

    while (i < text.length) {
      // $$...$$ 块级公式
      if (text.startsWith(r'$$', i)) {
        final end = text.indexOf(r'$$', i + 2);
        if (end != -1) {
          flush();
          final tex = _sanitizeTex(text.substring(i + 2, end));
          if (tex.isNotEmpty) {
            spans.add(
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Math.tex(
                    tex,
                    mathStyle: MathStyle.display,
                    textStyle: baseStyle.copyWith(fontSize: baseStyle.fontSize),
                  ),
                ),
              ),
            );
          }
          i = end + 2;
          continue;
        }
      }

      // $...$ 行内公式
      if (text[i] == r'$') {
        final end = _findInlineMathEnd(text, i + 1);
        if (end != -1) {
          flush();
          final tex = _sanitizeTex(text.substring(i + 1, end));
          if (tex.isNotEmpty) {
            spans.add(
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Math.tex(
                  tex,
                  mathStyle: MathStyle.text,
                  textStyle: baseStyle.copyWith(fontSize: baseStyle.fontSize),
                ),
              ),
            );
          }
          i = end + 1;
          continue;
        }
      }

      buffer.write(text[i]);
      i++;
    }

    flush();
    return spans;
  }

  /// 防御性清理历史数据中可能残留的 CDATA 标记。
  ///
  /// 早期版本可能把 `<![CDATA[` / `]]>` 存进数据库，
  /// 这里在渲染前统一剥掉，避免它们出现在正文中。
  String _cleanHtml(String html) {
    return html
        .replaceAll('<![CDATA[', '')
        .replaceAll(']]>', '')
        .trim();
  }

  /// 规范化行内文本：把连续空白/换行压缩为单个空格，并去掉首尾空白。
  String _normalizeInlineText(String text) {
    return text.replaceAll(RegExp(r'[ \t\r\n]+'), ' ').trim();
  }

  /// 清理 flutter_math_fork 不支持的 TeX 片段。
  ///
  /// 该博客的公式使用 `\tag{...}` 编号，展开后会生成 `\gdef`，
  /// 当前数学渲染器不支持 `\gdef`，这里先移除编号与 label。
  String _sanitizeTex(String tex) {
    return tex
        .replaceAll(RegExp(r'\\tag\*?\{[^}]*\}'), '')
        .replaceAll(RegExp(r'\\label\{[^}]*\}'), '')
        .replaceAll(r'\notag', '')
        .replaceAll(RegExp(r'\\gdef\s*\\[a-zA-Z@]+\s*\{[^}]*\}'), '')
        .trim();
  }

  int _findInlineMathEnd(String text, int start) {
    for (var i = start; i < text.length; i++) {
      if (text[i] == r'$') {
        if (i > start && text[i - 1] == r'\') {
          continue;
        }
        return i;
      }
    }
    return -1;
  }

  List<InlineSpan> _parseMarkdown(String text, TextStyle style) {
    final spans = <InlineSpan>[];
    var i = 0;
    final buffer = StringBuffer();

    void flush() {
      if (buffer.isNotEmpty) {
        spans.add(TextSpan(text: buffer.toString()));
        buffer.clear();
      }
    }

    while (i < text.length) {
      if (text.startsWith('**', i)) {
        final end = text.indexOf('**', i + 2);
        if (end != -1) {
          flush();
          spans.add(
            TextSpan(
              text: text.substring(i + 2, end),
              style: style.copyWith(fontWeight: FontWeight.w800),
            ),
          );
          i = end + 2;
          continue;
        }
      }

      if (text[i] == '*' && (i + 1 >= text.length || text[i + 1] != '*')) {
        final end = text.indexOf('*', i + 1);
        if (end != -1) {
          flush();
          spans.add(
            TextSpan(
              text: text.substring(i + 1, end),
              style: style.copyWith(fontStyle: FontStyle.italic),
            ),
          );
          i = end + 1;
          continue;
        }
      }

      if (text[i] == '`') {
        final end = text.indexOf('`', i + 1);
        if (end != -1) {
          flush();
          spans.add(
            TextSpan(
              text: text.substring(i + 1, end),
              style: style.copyWith(
                fontFamily: 'monospace',
                fontSize: (style.fontSize ?? 16) - 1,
              ),
            ),
          );
          i = end + 1;
          continue;
        }
      }

      if (text.startsWith('[', i)) {
        final close = text.indexOf(']', i + 1);
        if (close != -1 && close + 1 < text.length && text[close + 1] == '(') {
          final end = text.indexOf(')', close + 2);
          if (end != -1) {
            flush();
            final label = text.substring(i + 1, close);
            final url = text.substring(close + 2, end);
            spans.add(
              WidgetSpan(
                alignment: PlaceholderAlignment.baseline,
                baseline: TextBaseline.alphabetic,
                child: GestureDetector(
                  onTap: () => onOpenLink?.call(_resolveUrl(url)),
                  child: Text(
                    label,
                    style: style.copyWith(
                      color: FluxColors.red,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ),
            );
            i = end + 1;
            continue;
          }
        }
      }

      buffer.write(text[i]);
      i++;
    }

    flush();
    return spans;
  }

  String _resolveUrl(String url) {
    if (url.isEmpty) {
      return url;
    }
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return url;
    }
    if (url.startsWith('//')) {
      return 'https:$url';
    }
    final base = baseUrl;
    if (base != null && base.isNotEmpty) {
      final uri = Uri.tryParse(base);
      if (uri != null) {
        return uri.resolve(url).toString();
      }
    }
    return url;
  }
}
