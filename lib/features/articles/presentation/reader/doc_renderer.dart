// 受控文档树 → Flutter 控件（T019；架构 2.1「受控文档树 + Flutter 组件」、4.2）。
//
// 每一个构造都由本文件（及其拆出的三个文件）画出。这里没有 HTML 字符串、没有 WebView、
// 没有脚本执行：文档树就是全部输入，每种节点都有一个显式控件。
//
// 两条被刻意保留的边界：
//   * **未知构造可见**：未能解析的块与行内内容以「原文 + 原因」呈现，而不是消失；
//   * **危险 URL 在解析期就被拒绝**（见 core/domain/document_tree.dart），渲染层只管画，
//     不做安全决策。
library;

import 'package:flutter/material.dart';

import 'package:flux/core/core.dart';
import 'package:flux/core/design/design_tokens.dart';
import 'package:flux/l10n/l10n.dart';

import 'doc_blocks.dart';
import 'doc_inline.dart';
import 'doc_math.dart';
import 'doc_theme.dart';

/// 渲染一个受控文档。
class DocDocumentView extends StatelessWidget {
  /// 构造渲染器。
  const DocDocumentView({
    super.key,
    required this.document,
    required this.typography,
    this.maxWidth = FluxBreakpoints.maxBodyWidth,
    this.onOpenLink,
    this.onCopyLink,
    this.onOpenImage,
    this.findQuery,
  });

  /// 文档。
  final DocDocument document;

  /// 排版。
  final DocTypography typography;

  /// 正文最大宽度（架构第 7 节：正文最大宽 720）。
  final double maxWidth;

  /// 链接打开回调（T020 接外部浏览器；本期由详情页提示可复制）。
  final void Function(String url)? onOpenLink;

  /// 链接复制回调。
  final void Function(String url)? onCopyLink;

  /// 图片点击回调（T020）。
  final void Function(String url, String alt)? onOpenImage;

  /// 页内查找词（非空时高亮匹配）。
  final String? findQuery;

  /// 统计 [query] 在 [document] 里出现的次数（页内查找的计数）。
  ///
  /// 大小写不敏感：读者不会记得标题里是大写还是小写。按**纯文本**统计而不是按节点，
  /// 因此跨节点的匹配（一句话被强调标签切开）也算得上——否则用户会搜索一个明明看得见的
  /// 短语却得到「没有匹配」。
  static int countMatches(DocDocument document, String query) {
    if (query.isEmpty) {
      return 0;
    }
    final String haystack = docDocumentPlainText(document.children)
        .toLowerCase();
    final String needle = query.toLowerCase();
    int count = 0;
    int index = haystack.indexOf(needle);
    while (index != -1) {
      count++;
      index = haystack.indexOf(needle, index + needle.length);
    }
    return count;
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (final DocNode node in document.children)
              Padding(
                padding: blockPadding(node, typography),
                child: BlockView(
                  node: node,
                  typography: typography,
                  onOpenLink: onOpenLink,
                  onCopyLink: onCopyLink,
                  onOpenImage: onOpenImage,
                  findQuery: findQuery,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 块的上下留白（架构第 7 节：段间距 0.8em）。
EdgeInsets blockPadding(DocNode node, DocTypography typography) {
  final double paragraph = typography.baseSize * 0.8;
  if (node is DocHeading) {
    return EdgeInsets.only(top: paragraph * 1.6, bottom: paragraph * 0.6);
  }
  if (node is DocThematicBreak) {
    return EdgeInsets.symmetric(vertical: paragraph * 1.3);
  }
  if (node is DocMathBlock) {
    return EdgeInsets.symmetric(vertical: paragraph * 1.2);
  }
  if (node is DocCodeBlock || node is DocTable) {
    return EdgeInsets.symmetric(vertical: paragraph * 0.8);
  }
  return EdgeInsets.only(bottom: paragraph);
}

/// 画一个块级节点。
class BlockView extends StatelessWidget {
  /// 构造块视图。
  const BlockView({
    super.key,
    required this.node,
    required this.typography,
    this.onOpenLink,
    this.onCopyLink,
    this.onOpenImage,
    this.autoLoadImages = true,
    this.findQuery,
  });

  /// 节点。
  final DocNode node;

  /// 排版。
  final DocTypography typography;

  /// 链接打开回调。
  final void Function(String url)? onOpenLink;

  /// 链接复制回调。
  final void Function(String url)? onCopyLink;

  /// 图片点击回调（T020：打开查看器）。
  final void Function(String url, String alt)? onOpenImage;

  /// 是否自动加载远程图片（SET-012）。
  final bool autoLoadImages;

  /// 页内查找词。
  final String? findQuery;

  /// 画一个子节点（供 [ListItemView] 复用）。
  Widget _child(DocNode child) => BlockView(
    node: child,
    typography: typography,
    onOpenLink: onOpenLink,
    onCopyLink: onCopyLink,
    onOpenImage: onOpenImage,
    autoLoadImages: autoLoadImages,
    findQuery: findQuery,
  );

  /// 画一段行内内容。
  Widget _inline(List<DocInline> nodes, {TextStyle? style, TextAlign? align}) =>
      InlineRichText(
        nodes: nodes,
        typography: typography,
        baseStyle: style,
        textAlign: align,
        onOpenLink: onOpenLink,
        onCopyLink: onCopyLink,
        findQuery: findQuery,
      );

  @override
  Widget build(BuildContext context) {
    final DocTheme theme = typography.theme;
    return switch (node) {
      DocHeading(:final int level, :final List<DocInline> children) => _inline(
        children,
        style: typography.heading(level),
      ),
      DocParagraph(:final List<DocInline> children) => _inline(
        children,
        style: typography.body,
      ),
      DocBlockQuote(:final List<DocNode> children) => Container(
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: theme.accent, width: 3)),
          color: theme.selectedSurface.withValues(alpha: 0.5),
        ),
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (final DocNode child in children)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _child(child),
              ),
          ],
        ),
      ),
      DocList(
        :final bool ordered,
        :final List<DocListItem> items,
        :final int start,
      ) =>
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (int i = 0; i < items.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: ListItemView(
                  marker: ordered ? '${start + i}.' : bulletMarker,
                  item: items[i],
                  typography: typography,
                  blocksBuilder: _child,
                ),
              ),
          ],
        ),
      DocCodeBlock(:final String code, :final String? language) =>
        CodeBlockView(code: code, language: language, typography: typography),
      DocImageBlock(:final String url, :final String alt) => ImageBlockView(
        url: url,
        alt: alt,
        typography: typography,
        autoLoad: autoLoadImages,
        onTap: onOpenImage == null ? null : () => onOpenImage!(url, alt),
      ),
      DocThematicBreak() => Container(height: 1, color: theme.border),
      DocMathBlock(:final String tex) => DocBlockMath(
        tex: tex,
        typography: typography,
      ),
      final DocTable tableValue => TableView(
        table: tableValue,
        typography: typography,
        onOpenLink: onOpenLink,
        onCopyLink: onCopyLink,
      ),
      DocRawFallback(:final String text, :final String reason) =>
        FallbackBlockView(
          text: text,
          // 原因文案在这里补齐前缀：解析层只给出结构性描述（例如
          // 'unsupported block <figure>'），不负责组装界面文案。
          reason: AppLocalizations.of(context)
              .readingRichBodyBlockReason(reason),
          typography: typography,
        ),
    };
  }
}
