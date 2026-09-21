// 行内节点的 span 构造（T019）。
//
// 行内公式会成为 [WidgetSpan]（数学控件自己完成布局），其余都是文本 span。被拒绝的 URL
// 保留为**可见**的删除线文字并附上原因：一个被拦下的链接是证据，不是静默消失——读者要能
// 看出原文想链接到哪里，而渲染层不会把它交给启动器或图片加载器。
//
// 链接 span 需要 [TapGestureRecognizer]，它会持有资源、必须被释放。因此
// [InlineRichText] 在它的 State 里持有这些 recognizer 并在 dispose 时释放；每次重建都造
// 一个 recognizer 会泄漏。
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'package:flux/core/core.dart';
import 'package:flux/l10n/l10n.dart';

import 'doc_math.dart';
import 'doc_theme.dart';

/// 由行内节点构造的可选中富文本。
class InlineRichText extends StatefulWidget {
  /// 构造富文本。
  const InlineRichText({
    super.key,
    required this.nodes,
    required this.typography,
    this.baseStyle,
    this.textAlign,
    this.onOpenLink,
    this.onCopyLink,
    this.findQuery,
  });

  /// 行内节点。
  final List<DocInline> nodes;

  /// 排版。
  final DocTypography typography;

  /// 基础样式。
  final TextStyle? baseStyle;

  /// 对齐。
  final TextAlign? textAlign;

  /// 点击链接时的回调（T020 接外部浏览器；本期由详情页提示可复制）。
  final void Function(String url)? onOpenLink;

  /// 长按/右键链接时的回调（复制地址）。
  final void Function(String url)? onCopyLink;

  /// 页内查找词：非空时把匹配的片段标成高亮底色。
  final String? findQuery;

  @override
  State<InlineRichText> createState() => _InlineRichTextState();
}

class _InlineRichTextState extends State<InlineRichText> {
  final List<TapGestureRecognizer> _recognizers = <TapGestureRecognizer>[];

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final TapGestureRecognizer recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  @override
  Widget build(BuildContext context) {
    // 重建前先释放上一批：recognizer 与 span 一一对应，保留旧的只会积累未释放的手势
    // 识别器（且它们仍挂在已不存在的 span 上）。
    _disposeRecognizers();
    final List<InlineSpan> spans = buildInlineSpans(
      widget.nodes,
      widget.typography,
      AppLocalizations.of(context),
      onOpenLink: widget.onOpenLink,
      onCopyLink: widget.onCopyLink,
      ownedRecognizers: _recognizers,
      findQuery: widget.findQuery,
    );
    return SelectableText.rich(
      TextSpan(style: widget.baseStyle, children: spans),
      textAlign: widget.textAlign,
    );
  }
}

/// 把行内节点转成 span。
///
/// 为链接创建的 recognizer 会被追加进 [ownedRecognizers]，由调用方负责释放。
List<InlineSpan> buildInlineSpans(
  List<DocInline> nodes,
  DocTypography typography,
  AppLocalizations l10n, {
  void Function(String url)? onOpenLink,
  void Function(String url)? onCopyLink,
  List<TapGestureRecognizer>? ownedRecognizers,
  String? findQuery,
}) {
  final List<InlineSpan> spans = <InlineSpan>[];
  final DocTheme theme = typography.theme;
  for (final DocInline node in nodes) {
    switch (node) {
      case DocText(:final String text):
        spans.addAll(_highlightSpans(text, findQuery, typography, theme));
      case DocEmphasis(:final List<DocInline> children):
        spans.add(
          TextSpan(
            style: const TextStyle(fontStyle: FontStyle.italic),
            children: buildInlineSpans(
              children,
              typography,
              l10n,
              onOpenLink: onOpenLink,
              onCopyLink: onCopyLink,
              ownedRecognizers: ownedRecognizers,
              findQuery: findQuery,
            ),
          ),
        );
      case DocStrong(:final List<DocInline> children):
        spans.add(
          TextSpan(
            style: const TextStyle(fontWeight: FontWeight.w700),
            children: buildInlineSpans(
              children,
              typography,
              l10n,
              onOpenLink: onOpenLink,
              onCopyLink: onCopyLink,
              ownedRecognizers: ownedRecognizers,
              findQuery: findQuery,
            ),
          ),
        );
      case DocStrikethrough(:final List<DocInline> children):
        spans.add(
          TextSpan(
            style: const TextStyle(decoration: TextDecoration.lineThrough),
            children: buildInlineSpans(
              children,
              typography,
              l10n,
              onOpenLink: onOpenLink,
              onCopyLink: onCopyLink,
              ownedRecognizers: ownedRecognizers,
              findQuery: findQuery,
            ),
          ),
        );
      case DocCodeSpan(:final String code):
        spans.add(
          TextSpan(
            text: code,
            style: typography.inlineCode.copyWith(
              backgroundColor: theme.codeBackground,
            ),
          ),
        );
      case DocLinkInline(:final String url, :final List<DocInline> children):
        // 一个 recognizer 同时承载「点击打开」与「右键复制」：TextSpan 只接受一个
        // gestureRecognizer，而 TapGestureRecognizer 自身就区分主键与次键。
        // 对桌面阅读来说右键复制比长按更自然（长按在 macOS 上是选择文本）。
        TapGestureRecognizer? recognizer;
        if (onOpenLink != null || onCopyLink != null) {
          recognizer = TapGestureRecognizer();
          if (onOpenLink != null) {
            recognizer.onTap = () => onOpenLink(url);
          }
          if (onCopyLink != null) {
            recognizer.onSecondaryTap = () => onCopyLink(url);
          }
          ownedRecognizers?.add(recognizer);
        }
        spans.add(
          TextSpan(
            style: TextStyle(
              color: theme.accent,
              decoration: TextDecoration.underline,
              decorationColor: theme.accent,
            ),
            children: buildInlineSpans(
              children,
              typography,
              l10n,
              onOpenLink: onOpenLink,
              onCopyLink: onCopyLink,
              ownedRecognizers: ownedRecognizers,
              findQuery: findQuery,
            ),
            recognizer: recognizer,
          ),
        );
      case DocRejectedUrl(
        :final String url,
        :final String label,
        :final String reason,
      ):
        // 保留可见 + 说明被拦截：安全决定不该表现为「原文这里什么都没有」。
        spans.add(
          TextSpan(
            text:
                '${label.isEmpty ? url : label}（${l10n.readingLinkBlocked(reason)}）',
            style: TextStyle(
              color: theme.danger,
              decoration: TextDecoration.lineThrough,
              decorationColor: theme.danger,
            ),
          ),
        );
      case DocImageInline(:final String alt, :final String url):
        // 图片是**占位**：远程图片加载与缓存属 T021，这里只标出「这里有一张图」并给出
        // 替代文字，让正文的语义保持完整。
        spans.add(
          TextSpan(
            text: '□ ${alt.isEmpty ? url : alt}',
            style: typography.secondary,
          ),
        );
      case DocSoftBreak():
        spans.add(const TextSpan(text: ' '));
      case DocHardBreak():
        spans.add(const TextSpan(text: '\n'));
      case DocMathInline(:final String tex):
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: DocInlineMath(tex: tex, typography: typography),
          ),
        );
      case DocUnsupportedMath(:final String raw, :final String reason):
        spans.add(
          TextSpan(
            text: '$raw（${l10n.readingMathUnsupportedReason(reason)}）',
            style: TextStyle(color: theme.danger),
          ),
        );
      case DocUnsupportedInline(:final String text, :final String reason):
        spans.add(
          TextSpan(
            text: '$text（$reason）',
            style: TextStyle(color: theme.danger),
          ),
        );
    }
  }
  return spans;
}

/// 在一个文本片段里标出查找词的匹配（大小写不敏感）。
///
/// 只对**纯文本节点**做高亮：代码块里的高亮由代码块自己负责，而把匹配塞进代码 span
/// 会与语法着色互相覆盖。
List<InlineSpan> _highlightSpans(
  String text,
  String? findQuery,
  DocTypography typography,
  DocTheme theme,
) {
  if (findQuery == null || findQuery.isEmpty || text.isEmpty) {
    return <InlineSpan>[TextSpan(text: text)];
  }
  final String haystack = text.toLowerCase();
  final String needle = findQuery.toLowerCase();
  final List<InlineSpan> out = <InlineSpan>[];
  int cursor = 0;
  while (true) {
    final int at = haystack.indexOf(needle, cursor);
    if (at == -1) {
      if (cursor < text.length) {
        out.add(TextSpan(text: text.substring(cursor)));
      }
      return out;
    }
    if (at > cursor) {
      out.add(TextSpan(text: text.substring(cursor, at)));
    }
    out.add(
      TextSpan(
        text: text.substring(at, at + needle.length),
        style: TextStyle(backgroundColor: theme.accent.withValues(alpha: 0.35)),
      ),
    );
    cursor = at + needle.length;
  }
}
