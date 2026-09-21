// 检索片段的高亮渲染（T022）。
//
// 片段在存储层是「文本 + 标记」，在这里变成一段带强调的富文本。放在 presentation 而不是
// application：标记到颜色/字重的映射是**视觉决定**（跟随主题 token），而「哪里命中」
// 是数据（在 core 的 HighlightSegment 里）。
//
// 为什么片段用 RichText 而不是把标记直接画成字符：控制字符（哨兵）绝不能出现在界面上，
// 也不该被读屏念出来——把分段交给 TextSpan 是唯一能保证这件事的做法。
library;

import 'package:flutter/material.dart';

import 'package:flux/core/core.dart';

/// 一段带高亮的信息（标题或片段文本）。
class HighlightedText extends StatelessWidget {
  /// 构造富文本。
  const HighlightedText({
    super.key,
    required this.segments,
    required this.baseStyle,
    this.highlightStyle,
    this.maxLines,
    this.ellipsis = true,
  });

  /// 分段。
  final List<HighlightSegment> segments;

  /// 基础样式。
  final TextStyle baseStyle;

  /// 命中段样式；为空时用「主色 + 半粗」的默认强调。
  final TextStyle? highlightStyle;

  /// 最大行数。
  final int? maxLines;

  /// 是否在截断处显示省略号。
  final bool ellipsis;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final TextStyle highlight =
        highlightStyle ??
        baseStyle.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w600,
        );
    return Text.rich(
      TextSpan(
        children: <InlineSpan>[
          for (final HighlightSegment segment in segments)
            TextSpan(
              text: segment.text,
              style: segment.isMatch ? highlight : baseStyle,
            ),
        ],
      ),
      maxLines: maxLines,
      overflow: ellipsis ? TextOverflow.ellipsis : TextOverflow.clip,
    );
  }
}

/// 一条结果的片段区：把各字段的片段按「标题 → 摘要 → 正文」的优先级依次展示。
///
/// 为什么不把所有命中字段都列出来：一篇文章的正文可能命中十几处，全列会让一条结果
/// 占据整屏，把真正不同的结果挤下去。每个结果只展示有限条目，让用户先看到「哪些文章
/// 命中」，细节点进正文看（那里有页内查找）。
class SearchSnippetView extends StatelessWidget {
  /// 构造片段区。
  const SearchSnippetView({
    super.key,
    required this.snippets,
    this.maxSnippets = 2,
  });

  /// 命中片段。
  final List<SearchSnippet> snippets;

  /// 最多展示几条。
  final int maxSnippets;

  /// 片段展示优先级：标题最相关，其次摘要，然后正文，作者最后。
  static const List<SearchField> _priority = <SearchField>[
    SearchField.title,
    SearchField.summary,
    SearchField.body,
    SearchField.author,
  ];

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<SearchSnippet> ordered = <SearchSnippet>[
      for (final SearchField field in _priority)
        ...snippets.where((SearchSnippet s) => s.field == field),
    ];
    final List<SearchSnippet> shown = ordered
        .take(maxSnippets)
        .toList(growable: false);
    if (shown.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (int i = 0; i < shown.length; i++)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : 2),
            child: HighlightedText(
              segments: shown[i].segments,
              baseStyle: theme.textTheme.bodySmall ?? const TextStyle(),
              maxLines: 2,
            ),
          ),
      ],
    );
  }
}
