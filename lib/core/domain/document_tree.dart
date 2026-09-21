// 受控文档树（T013；架构 2.1「受控文档树 + Flutter 组件」、4.2「渲染受控文档树」）。
//
// 这是 Flux 自己的中间表示：HTML/Markdown 先被解析成这里的节点，再由渲染层画成
// Flutter 组件。**不存在**把 HTML 交给浏览器内核或网页运行时的路径。
//
// 为什么放在 core 而不是 features/feeds 或 features/articles：
//   生产方是 features/feeds（T013 的清洗器），消费方是 features/articles
//   （T019/T020 的渲染与选区）。放在任一 feature 下都会让另一个 feature 横向依赖它，
//   而 core 是唯一被允许跨模块共享的层。本文件**不依赖 Flutter 或任何第三方包**，
//   因此符合 core 的约束（见 test/core/architecture_layering_test.dart）。
//
// 与 T003 原型的关系（docs/Flux_项目架构说明书.md 的选型前提）：
//   原型验证过「受控文档树」这条路线可行，本文件按同样的思路**独立实现**：节点种类、
//   字段名与语义对齐（标题层级/段落/引用/列表/代码块/表格/图片/行内强调与链接），
//   但不复刻原型代码。
//
// T019 补充（Markdown 正文路径，架构 4.2「数学首发验收」）：
//   Markdown 解析会产出 HTML 路径产不出（或名称不同）的构造：行内/独占公式、
//   删除线、任务列表勾选状态、表格列对齐、标题锚点、以及「解析器不认识的东西」
//   （[DocRawFallback] / [DocUnsupportedInline] / [DocUnsupportedMath]）。它们被加进
//   同一棵树而不是另建一套：渲染层因此只需要认识**一种**文档模型，而「公式用哪种
//   语法写进源里」不会变成渲染层的分支。
//
// 两条不可妥协的规则：
//   1) 未知/不受支持的构造**必须保留可见**（成为 [DocRejectedUrl] 或原样文本），
//      不能静默丢弃——静默丢弃会让读者以为原文里没有那段内容；
//   2) 危险 URL 在**解析时**就被拒绝，而不是等渲染时再判断。渲染层只管画，
//      不做安全决策（架构第 8 节：边界校验）。
library;

/// 允许出现在链接与图片上的协议。
const Set<String> kAllowedDocUrlSchemes = <String>{'http', 'https', 'mailto'};

/// 永不进入可点击/可加载控件的协议。
const Set<String> kBlockedDocUrlSchemes = <String>{
  'javascript',
  'data',
  'vbscript',
  'file',
  'blob',
  'about',
  'chrome',
  'jar',
};

/// [url] 是否是渲染层愿意交给启动器/图片加载器的地址。
///
/// 只接受 http/https/mailto 的**绝对** URL：相对地址会被拒绝，因为本层没有可信的
/// base URL 概念，替调用方补一个 base 等于把「这个地址指向哪里」的决定悄悄做掉。
/// 页面内锚点（`#section`）同理被拒绝——正文清洗不重写链接，也就不该凭空生成锚点。
bool isSafeDocUrl(String url) {
  final String trimmed = url.trim();
  if (trimmed.isEmpty) {
    return false;
  }
  final int colon = trimmed.indexOf(':');
  if (colon <= 0) {
    return false;
  }
  // 形如 "a/b:foo" 的情况不是协议：冒号必须出现在第一个 / ? # 之前。
  final int slash = trimmed.indexOf('/');
  final int hash = trimmed.indexOf('#');
  final int query = trimmed.indexOf('?');
  if (slash != -1 && colon > slash) {
    return false;
  }
  if (hash != -1 && colon > hash) {
    return false;
  }
  if (query != -1 && colon > query) {
    return false;
  }
  final String scheme = trimmed.substring(0, colon).toLowerCase();
  if (kBlockedDocUrlSchemes.contains(scheme)) {
    return false;
  }
  return kAllowedDocUrlSchemes.contains(scheme);
}

/// 文档树节点（块级）。
sealed class DocNode {
  /// 保护构造。
  const DocNode();
}

/// 行内节点。
sealed class DocInline {
  /// 保护构造。
  const DocInline();
}

/// 纯文本。
final class DocText extends DocInline {
  /// 构造文本节点。
  const DocText(this.text);

  /// 文本内容（已做实体解码，不含标签）。
  final String text;

  @override
  String toString() => 'DocText("$text")';
}

/// 强调（HTML `em`、`i`）。
final class DocEmphasis extends DocInline {
  /// 构造强调节点。
  const DocEmphasis(this.children);

  /// 子行内节点。
  final List<DocInline> children;

  @override
  String toString() => 'DocEmphasis($children)';
}

/// 加粗（HTML `strong`、`b`）。
final class DocStrong extends DocInline {
  /// 构造加粗节点。
  const DocStrong(this.children);

  /// 子行内节点。
  final List<DocInline> children;

  @override
  String toString() => 'DocStrong($children)';
}

/// 行内代码（HTML `code`）。
final class DocCodeSpan extends DocInline {
  /// 构造行内代码。
  const DocCodeSpan(this.code);

  /// 代码文本；**永不**被解释为标记。
  final String code;

  @override
  String toString() => 'DocCodeSpan("$code")';
}

/// 删除线（Markdown `~~...~~`、GFM 扩展）。
///
/// HTML 正文路径不会产出它（`del`/`s` 不在清洗白名单里），但 Markdown 的
/// `ExtensionSet.gitHubFlavored` 会——因此它必须是一个显式节点，而不是被静默降级成
/// 普通文字：读者应当能看出原文划掉了什么。
final class DocStrikethrough extends DocInline {
  /// 构造删除线。
  const DocStrikethrough(this.children);

  /// 子行内节点。
  final List<DocInline> children;

  @override
  String toString() => 'DocStrikethrough($children)';
}

/// 行内公式（Markdown `$...$`；架构 4.2）。
///
/// [tex] 是**原始 TeX 字节**：数学段落必须在 Markdown 解析之前被摘出来，否则 TeX 里
/// 的 `_`、`^`、`{}` 会被 CommonMark 当成标记改写（`$a_i + b_j$` 的两个下划线会被读
/// 成一个强调对，`\frac{a}{b}` 会丢掉花括号）。摘出来之后渲染层拿到的是作者写的原样。
final class DocMathInline extends DocInline {
  /// 构造行内公式。
  const DocMathInline(this.tex);

  /// 原始 TeX 正文。
  final String tex;

  @override
  String toString() => 'DocMathInline("$tex")';
}

/// 渲染不了的公式：原式与原因都留在树里（架构 4.2：不支持命令显示原式与提示，
/// 不能空白或冒充成功）。
final class DocUnsupportedMath extends DocInline {
  /// 构造无法渲染的公式。
  const DocUnsupportedMath({required this.raw, required this.reason});

  /// 原始写法（含定界符）。
  final String raw;

  /// 人类可读的原因（结构性描述，供测试与提示使用）。
  final String reason;

  @override
  String toString() => 'DocUnsupportedMath("$raw")';
}

/// 映射不出来的行内构造：保留文字并附上原因，而不是丢掉。
final class DocUnsupportedInline extends DocInline {
  /// 构造未映射的行内节点。
  const DocUnsupportedInline({required this.text, required this.reason});

  /// 原文。
  final String text;

  /// 原因。
  final String reason;

  @override
  String toString() => 'DocUnsupportedInline("$text", $reason)';
}

/// 链接。
final class DocLinkInline extends DocInline {
  /// 构造链接。
  const DocLinkInline({required this.url, required this.children});

  /// 已通过 [isSafeDocUrl] 的地址。
  final String url;

  /// 链接文字。
  final List<DocInline> children;

  @override
  String toString() => 'DocLinkInline($url, $children)';
}

/// 行内图片。
final class DocImageInline extends DocInline {
  /// 构造行内图片。
  const DocImageInline({required this.url, required this.alt});

  /// 已通过 [isSafeDocUrl] 的地址。
  final String url;

  /// 替代文字（读屏与加载失败时使用）。
  final String alt;

  @override
  String toString() => 'DocImageInline($url, alt="$alt")';
}

/// 软换行（源里的普通换行）。
final class DocSoftBreak extends DocInline {
  /// 构造软换行。
  const DocSoftBreak();

  @override
  String toString() => 'DocSoftBreak()';
}

/// 硬换行（HTML `br`）。
final class DocHardBreak extends DocInline {
  /// 构造硬换行。
  const DocHardBreak();

  @override
  String toString() => 'DocHardBreak()';
}

/// 被拒绝的链接或图片。
///
/// 保留 [label] 与 [url] 是为了「不静默丢弃」：读者能看到原文想链接到哪里，
/// 但渲染层**不会**把它交给启动器或图片加载器。
final class DocRejectedUrl extends DocInline {
  /// 构造被拒绝的链接。
  const DocRejectedUrl({
    required this.url,
    required this.label,
    required this.reason,
  });

  /// 被拒绝的原始地址（只用于显示，不再被解析）。
  final String url;

  /// 可见文字（链接文字或图片 alt）。
  final String label;

  /// 拒绝原因（结构性描述，供测试与诊断使用）。
  final String reason;

  @override
  String toString() => 'DocRejectedUrl("$url", $reason)';
}

/// 标题（HTML `h1`–`h6`）。
final class DocHeading extends DocNode {
  /// 构造标题。
  const DocHeading(this.level, this.children);

  /// 层级 1–6。
  final int level;

  /// 标题文字。
  final List<DocInline> children;

  @override
  String toString() => 'DocHeading($level, $children)';
}

/// 段落。
final class DocParagraph extends DocNode {
  /// 构造段落。
  const DocParagraph(this.children);

  /// 段落内容。
  final List<DocInline> children;

  @override
  String toString() => 'DocParagraph($children)';
}

/// 引用块。
final class DocBlockQuote extends DocNode {
  /// 构造引用。
  const DocBlockQuote(this.children);

  /// 引用的块级内容。
  final List<DocNode> children;

  @override
  String toString() => 'DocBlockQuote($children)';
}

/// 列表项。
final class DocListItem {
  /// 构造列表项。
  const DocListItem({required this.children, this.checked});

  /// 项内的块级内容（通常是段落）。
  final List<DocNode> children;

  /// 任务列表勾选状态：null 表示普通项，true/false 表示已勾选/未勾选。
  ///
  /// 为什么放在列表项上而不是一个独立的「复选框」行内节点：勾选语义属于**整个项**，
  /// 而 Markdown 里的 input-checkbox 只是它的呈现形式。放进行内节点会让渲染层需要在
  /// 一个文本 run 里画勾选框，并让「哪一项被勾了」变得难以查询。
  final bool? checked;

  @override
  String toString() => 'DocListItem(checked=$checked, $children)';
}

/// 列表（有序/无序）。
final class DocList extends DocNode {
  /// 构造列表。
  const DocList({required this.ordered, required this.items, this.start = 1});

  /// 是否有序。
  final bool ordered;

  /// 有序列表的起始序号（HTML `ol start`）。
  final int start;

  /// 列表项。
  final List<DocListItem> items;

  @override
  String toString() => 'DocList(ordered=$ordered, items=$items)';
}

/// 代码块（HTML `pre`，可选内嵌 `code`）。
final class DocCodeBlock extends DocNode {
  /// 构造代码块。
  const DocCodeBlock({required this.code, this.language});

  /// 代码原文；**永不**被解释为标记。
  final String code;

  /// 语言标识（来自 `class="language-xxx"`）；无法识别时为 null。
  final String? language;

  @override
  String toString() => 'DocCodeBlock(lang=$language, ${code.length} chars)';
}

/// 独占一段的图片。
final class DocImageBlock extends DocNode {
  /// 构造块级图片。
  const DocImageBlock({required this.url, required this.alt});

  /// 已通过 [isSafeDocUrl] 的地址。
  final String url;

  /// 替代文字。
  final String alt;

  @override
  String toString() => 'DocImageBlock($url)';
}

/// 分隔线（HTML `hr`）。
final class DocThematicBreak extends DocNode {
  /// 构造分隔线。
  const DocThematicBreak();

  @override
  String toString() => 'DocThematicBreak()';
}

/// 独占一段的公式（Markdown `$$...$$`）。
final class DocMathBlock extends DocNode {
  /// 构造块级公式。
  const DocMathBlock(this.tex);

  /// 原始 TeX 正文（多行时保留换行，供矩阵/对齐环境使用）。
  final String tex;

  @override
  String toString() => 'DocMathBlock("$tex")';
}

/// 解析器无法归类的块：保留原文与原因，而不是丢掉整块。
///
/// 为什么这一类比「未知 HTML 标签」更需要一个显式节点：Markdown 的扩展语法很多
/// （脚注定义、告示框、自定义容器），而我们的解析器只映射了一部分。把这类内容静默
/// 丢掉会让读者以为原文里没有那段；因此它以「未能解析的内容（已按原文显示）」的形式
/// 出现在阅读页上。
final class DocRawFallback extends DocNode {
  /// 构造未解析块。
  const DocRawFallback(this.text, {required this.reason});

  /// 原文。
  final String text;

  /// 原因。
  final String reason;

  @override
  String toString() => 'DocRawFallback("$text")';
}

/// 表格。
final class DocTable extends DocNode {
  /// 构造表格。
  const DocTable({
    required this.header,
    required this.rows,
    this.alignments = const <String?>[],
  });

  /// 表头单元格（每格是一段行内内容）。
  final List<List<DocInline>> header;

  /// 数据行。
  final List<List<List<DocInline>>> rows;

  /// 每列对齐（left / center / right / null）。
  ///
  /// 来自 Markdown 表格的分隔行（|:---:|）。HTML 正文路径不产出它（那里没有列对齐的
  /// 语义来源），因此默认空列表——渲染层按下标取值，越界即按起始对齐处理。
  final List<String?> alignments;

  @override
  String toString() =>
      'DocTable(header=${header.length}, rows=${rows.length}, '
      'align=${alignments.length})';
}

/// 一个受控文档。
final class DocDocument {
  /// 构造文档。
  const DocDocument(this.children);

  /// 块级内容。
  final List<DocNode> children;

  /// 是否没有任何可见内容（用于判定「正文为空」）。
  bool get isEmpty => children.isEmpty;

  @override
  String toString() => 'DocDocument($children)';
}

/// 按文档顺序收集全部行内节点。
///
/// 抽成独立函数而不是让测试自己走树：多个测试要断言「链接/图片是否被拒绝」，
/// 各自实现遍历会漂移，最终出现「这个测试认为该拒绝、那个测试认为不用」。
List<DocInline> collectDocInlines(DocDocument document) {
  final List<DocInline> out = <DocInline>[];

  void addInlines(List<DocInline> nodes) {
    for (final DocInline node in nodes) {
      out.add(node);
      switch (node) {
        case DocEmphasis(:final List<DocInline> children):
          addInlines(children);
        case DocStrong(:final List<DocInline> children):
          addInlines(children);
        case DocStrikethrough(:final List<DocInline> children):
          addInlines(children);
        case DocLinkInline(:final List<DocInline> children):
          addInlines(children);
        case DocText():
        case DocCodeSpan():
        case DocImageInline():
        case DocSoftBreak():
        case DocHardBreak():
        case DocRejectedUrl():
        case DocMathInline():
        case DocUnsupportedMath():
        case DocUnsupportedInline():
          break;
      }
    }
  }

  void walk(List<DocNode> nodes) {
    for (final DocNode node in nodes) {
      switch (node) {
        case DocHeading(:final List<DocInline> children):
          addInlines(children);
        case DocParagraph(:final List<DocInline> children):
          addInlines(children);
        case DocBlockQuote(:final List<DocNode> children):
          walk(children);
        case DocList(:final List<DocListItem> items):
          for (final DocListItem item in items) {
            walk(item.children);
          }
        case DocTable(:final header, :final rows):
          for (final List<DocInline> cell in header) {
            addInlines(cell);
          }
          for (final List<List<DocInline>> row in rows) {
            for (final List<DocInline> cell in row) {
              addInlines(cell);
            }
          }
        case DocCodeBlock():
        case DocImageBlock():
        case DocThematicBreak():
        case DocMathBlock():
        case DocRawFallback():
          break;
      }
    }
  }

  walk(document.children);
  return out;
}

/// 把一段行内内容压平成可见文字。
String docInlinePlainText(List<DocInline> nodes) {
  final StringBuffer buffer = StringBuffer();
  for (final DocInline node in nodes) {
    switch (node) {
      case DocText(:final String text):
        buffer.write(text);
      case DocEmphasis(:final List<DocInline> children):
        buffer.write(docInlinePlainText(children));
      case DocStrong(:final List<DocInline> children):
        buffer.write(docInlinePlainText(children));
      case DocStrikethrough(:final List<DocInline> children):
        buffer.write(docInlinePlainText(children));
      case DocCodeSpan(:final String code):
        buffer.write(code);
      case DocLinkInline(:final List<DocInline> children):
        buffer.write(docInlinePlainText(children));
      case DocImageInline(:final String alt):
        buffer.write(alt);
      case DocSoftBreak():
        buffer.write(' ');
      case DocHardBreak():
        buffer.write('\n');
      case DocRejectedUrl(:final String label, :final String url):
        // 文字优先：链接文字通常比 URL 更有信息量；没有文字时才退到 URL。
        buffer.write(label.isEmpty ? url : label);
      case DocMathInline(:final String tex):
        // 公式压平为它的 TeX 正文：纯文本导出（检索、摘要回退）里保留那几个字符，
        // 比丢掉整段公式更接近原文。
        buffer.write(tex);
      case DocUnsupportedMath(:final String raw):
        buffer.write(raw);
      case DocUnsupportedInline(:final String text):
        buffer.write(text);
    }
  }
  return buffer.toString();
}

/// 把整篇文档压平成可见文字（用于摘要回退、纯文本检索与测试断言）。
String docDocumentPlainText(List<DocNode> nodes) {
  final StringBuffer buffer = StringBuffer();
  for (final DocNode node in nodes) {
    switch (node) {
      case DocHeading(:final List<DocInline> children):
        buffer.writeln(docInlinePlainText(children));
      case DocParagraph(:final List<DocInline> children):
        buffer.writeln(docInlinePlainText(children));
      case DocBlockQuote(:final List<DocNode> children):
        buffer.writeln(docDocumentPlainText(children));
      case DocList(:final List<DocListItem> items):
        for (final DocListItem item in items) {
          buffer.writeln(docDocumentPlainText(item.children));
        }
      case DocCodeBlock(:final String code):
        buffer.writeln(code);
      case DocImageBlock(:final String alt):
        buffer.writeln(alt);
      case DocMathBlock(:final String tex):
        buffer.writeln(tex);
      case DocRawFallback(:final String text):
        // 未解析块在纯文本里保留原文：否则「检索不到那段」与「原文没有那段」无法区分。
        buffer.writeln(text);
      case DocThematicBreak():
        buffer.writeln('---');
      case DocTable(:final header, :final rows):
        buffer.writeln(header.map(docInlinePlainText).join(' | '));
        for (final List<List<DocInline>> row in rows) {
          buffer.writeln(row.map(docInlinePlainText).join(' | '));
        }
    }
  }
  return buffer.toString();
}
