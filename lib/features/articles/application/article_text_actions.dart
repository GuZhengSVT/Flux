// 正文文本动作（T020）：全文纯文本拼接与「选词解释」的最小上下文。
//
// 为什么放在 application 而不是控件里：
//   - 「复制全文」的产出口径需要被测试逐步断言（标题、段落、列表、代码、表格各自
//     压平成什么形态），放在控件里就只能靠界面断言间接验证；
//   - 「只发送选区和最少上下文」是架构 4.2 的**数据出境**规则，而不是界面细节。
//     把截断规则写成纯函数，才能在没有 AI 提供商的现在就把它测清楚（T034 接 AI 时
//     用的是同一个函数，不重新写一套）。
library;

import 'package:flux/core/core.dart';

/// 复制全文时每段之间的分隔。
///
/// 用空行而不是单换行：读者把正文粘进笔记或邮件时，空行才是段落边界；单换行会让
/// 整篇变成一大段。
const String kArticleParagraphSeparator = '\n\n';

/// 把受控文档压平成**可复制的纯文本**。
///
/// 与 [docDocumentPlainText] 的区别：那个函数服务于**检索与摘要回退**，因此把图片压成
/// 替代文字、把分隔线压成横线、每行末尾都补换行；而复制全文服务于**读者手里的文本**，
/// 图片替代文字与分隔线都不是读者想粘出来的内容，段落之间应当是空行。
///
/// 保留代码块原文（读者复制正文时经常正是为了那段代码），保留表格的单元格（用竖线
/// 分隔，与纯文本表格的习惯一致），保留公式的 TeX 原文而不是图片替代。
String articlePlainText(DocDocument document) {
  final List<String> blocks = <String>[];
  for (final DocNode node in document.children) {
    final String text = _blockText(node);
    if (text.trim().isEmpty) {
      // 空块（例如只有一张图、没有替代文字的段落）不产生空段落：连续的三个换行会让
      // 粘贴结果里出现莫名其妙的空隙。
      continue;
    }
    blocks.add(text.trim());
  }
  return blocks.join(kArticleParagraphSeparator);
}

/// 单个块压平为文本（首尾空白由调用方裁剪）。
String _blockText(DocNode node) => switch (node) {
  DocHeading(:final List<DocInline> children) => docInlinePlainText(children),
  DocParagraph(:final List<DocInline> children) => docInlinePlainText(children),
  DocBlockQuote(:final List<DocNode> children) => _nested(children),
  DocList(:final List<DocListItem> items) =>
    items
        .map((DocListItem item) => _nested(item.children))
        .where((String text) => text.isNotEmpty)
        .join('\n'),
  // 代码块原文照抄：读者复制全文时经常正是为了那段代码。
  DocCodeBlock(:final String code) => code,
  // 图片**不**产出替代文字：复制全文是为了拿文字，把 alt 混进去会让粘贴结果里出现
  // 一段与上下文无关的说明（这与检索路径的选择相反，那里的目标是「不要丢信息」）。
  DocImageBlock() => '',
  // 公式保留 TeX 原文：读者拿到公式时，源码比空串有用。
  DocMathBlock(:final String tex) => tex,
  // 分隔线不产出内容：它没有可复制的文字。
  DocThematicBreak() => '',
  // 未解析块保留原文：宁可多给一段，也不要让读者以为原文里没有它。
  DocRawFallback(:final String text) => text,
  DocTable(:final List<List<DocInline>> header, :final rows) => <String>[
    header.map(docInlinePlainText).join(' | '),
    for (final List<List<DocInline>> row in rows)
      row.map(docInlinePlainText).join(' | '),
  ].where((String line) => line.trim().isNotEmpty).join('\n'),
};

/// 把一组块压平并用换行连接（引用与列表项内部用）。
String _nested(List<DocNode> nodes) => nodes
    .map(_blockText)
    .where((String text) => text.trim().isNotEmpty)
    .join('\n');

/// 「选词解释」请求：选区 + 最少上下文。
///
/// 为什么需要上下文而不是只发选区：一个孤立的「它」或「该模型」无法被解释。但上下文
/// 也不能是整篇——那是把用户的整篇文章交给外部服务，超出用户选中的范围。
///
/// 因此规则是两条明说的边界：
///   - 上下文总量上限 [maxContextCharacters]（默认 1200 字符，约一两段）；
///   - 选区**两侧**各取一半配额，并在**字符边界**处截断，截断处显式标注省略号，
///     让模型与用户都知道这里被截过（不悄悄截断成一句完整的话，那会让模型以为
///     上下文到此结束）。
final class SelectionExplanationRequest {
  /// 构造请求。
  const SelectionExplanationRequest({
    required this.selection,
    required this.contextBefore,
    required this.contextAfter,
  });

  /// 用户选中的文本（原样，不截断：截断选区会让「解释什么」变成另一个问题）。
  final String selection;

  /// 选区之前的上下文（可能以省略号开头）。
  final String contextBefore;

  /// 选区之后的上下文（可能以省略号结尾）。
  final String contextAfter;

  /// 会实际发送出去的文本（供界面「将发送什么」预览使用）。
  String get payload => '$contextBefore$selection$contextAfter';

  /// 从整篇纯文本与选区构造请求。
  ///
  /// [plainText] 是整篇正文的纯文本，[selection] 必须能在其中找到：找不到时（例如
  /// 用户选的是渲染后的公式字形、或文本来自另一个视图）**不猜位置**，直接把选区
  /// 本身当作全部内容，两端上下文为空。猜一个位置会让截出来的上下文来自正文里
  /// 另一处，那比没有上下文更糟。
  factory SelectionExplanationRequest.fromDocument({
    required String plainText,
    required String selection,
    int maxContextCharacters = 1200,
  }) {
    final String trimmed = selection.trim();
    if (trimmed.isEmpty) {
      return const SelectionExplanationRequest(
        selection: '',
        contextBefore: '',
        contextAfter: '',
      );
    }
    final int at = plainText.indexOf(trimmed);
    if (at < 0) {
      return SelectionExplanationRequest(
        selection: trimmed,
        contextBefore: '',
        contextAfter: '',
      );
    }
    final int half = (maxContextCharacters / 2).floor();
    final int beforeStart = at - half < 0 ? 0 : at - half;
    final int afterEnd = at + trimmed.length + half > plainText.length
        ? plainText.length
        : at + trimmed.length + half;
    final String before = plainText.substring(beforeStart, at);
    final String after = plainText.substring(at + trimmed.length, afterEnd);
    return SelectionExplanationRequest(
      selection: trimmed,
      contextBefore: beforeStart > 0 ? '…$before' : before,
      contextAfter: afterEnd < plainText.length ? '$after…' : after,
    );
  }
}
