// 正文清洗（T013；架构 4.2「渲染受控文档树…拒绝脚本、事件属性、iframe、表单和危险
// URL」、第 8 节「不可信 RSS…在边界校验」）。
//
// 为什么手写分词器 + 元素树，而不是用 xml 包解析这段 HTML：
//   本文件处理的是**正文里嵌的 HTML 片段**，它不受「必须是合法 XML」的约束。真实源
//   里普遍存在 `<br>`（未自闭合）、`<img ...>`、裸 `&`、未闭合的 `<p>`，而 xml 包
//   是严格解析器、没有错误恢复，用它解析这类片段会大量失败。失败后只剩两个选择：
//   丢掉正文（读者看不到内容）或原样输出（等于把 HTML 当纯文本展示）。两者都不可接受。
//   因此这里自己实现一个**宽容但受限**的解析路径：
//     - 宽容：自动闭合未闭合的标签、容忍裸 `&`、容忍属性无引号；
//     - 受限：只认识白名单标签；未知标签「拆掉外壳、保留文字」；script 类标签连同
//       内容一起丢弃；深度与节点数有硬上限。
//   注意边界不混：**RSS/Atom 文档本身**仍用 xml 包严格解析，并拒绝 DTD/外部实体
//   （见 feed_parser.dart）。
//
// 三步流水线，每一步都可独立测试：
//   1. _Tokenizer：文本 → 词法事件（标签/文本）。只认字符，不做白名单判断。
//   2. _ElementTree：事件 → 元素树（宽容闭合、丢弃 script 类内容）。
//   3. _Converter：元素树 → 受控文档树（白名单、URL 校验、节点/深度上限）。
//
// 三条不可妥协的规则：
//   1) script/iframe/style/form 等**连同内容**丢弃（只丢标签会让脚本源码印在正文里）；
//   2) 危险 URL 在解析时变成 DocRejectedUrl——仍然可见，但永不交给启动器或图片加载器；
//   3) 未知标签保留其文字，避免「正文看着少了半段」而无人察觉。
library;

import 'package:flux/core/core.dart';

/// 清洗限制（防御性上限，避免恶意/畸形正文耗尽内存与栈）。
class SanitizerLimits {
  /// 构造限制。
  const SanitizerLimits({
    this.maxInputLength = 512 * 1024,
    this.maxNodes = 20000,
    this.maxDepth = 64,
  });

  /// 输入文本长度上限（字符）。超出部分被截断而不是拒绝整篇。
  final int maxInputLength;

  /// 输出节点总数上限（含行内）。
  final int maxNodes;

  /// 嵌套深度上限。
  final int maxDepth;
}

/// 清洗结果（含诊断计数，便于写入日志与测试，不用于 UI 文案）。
class SanitizerReport {
  /// 构造结果。
  const SanitizerReport({
    required this.document,
    this.droppedBlocks = const <String>[],
    this.rejectedUrls = 0,
    this.truncated = false,
    this.hitNodeLimit = false,
    this.hitDepthLimit = false,
  });

  /// 产出的受控文档。
  final DocDocument document;

  /// 被整段丢弃的标签名（去重，按首次出现顺序）。
  final List<String> droppedBlocks;

  /// 被替换为 DocRejectedUrl 的 URL 数量。
  final int rejectedUrls;

  /// 输入是否被长度上限截断。
  final bool truncated;

  /// 是否触及节点数上限（正文可能不完整）。
  final bool hitNodeLimit;

  /// 是否触及深度上限（正文可能不完整）。
  final bool hitDepthLimit;

  /// 是否有任何东西被丢弃或截断（调用方据此决定是否标注正文不完整）。
  bool get isLossy =>
      truncated || hitNodeLimit || hitDepthLimit || droppedBlocks.isNotEmpty;
}

/// 把一段 HTML 清洗成受控文档树。
///
/// 返回 [SanitizerReport]：调用方需要知道「有东西被丢掉了」，而不是只拿到一棵看着
/// 没问题的树。诊断信息进入 DiagnosticLog 与「正文可能不完整」标注。
SanitizerReport sanitizeHtmlToDocument(
  String? html, {
  SanitizerLimits limits = const SanitizerLimits(),
}) {
  if (html == null || html.trim().isEmpty) {
    return const SanitizerReport(document: DocDocument(<DocNode>[]));
  }

  final bool truncated = html.length > limits.maxInputLength;
  final String input = truncated
      ? html.substring(0, limits.maxInputLength)
      : html;

  final _ElementTree tree = _ElementTree(limits: limits);
  tree.consume(_Tokenizer(input).tokenize());

  final _Converter converter = _Converter(limits: limits);
  final List<DocNode> blocks = converter.convertBlocks(tree.children);

  return SanitizerReport(
    document: DocDocument(blocks),
    droppedBlocks: tree.droppedBlocks,
    rejectedUrls: converter.rejectedUrls,
    truncated: truncated,
    hitNodeLimit: converter.hitNodeLimit,
    hitDepthLimit: converter.hitDepthLimit || tree.hitDepthLimit,
  );
}

/// 把一段 HTML 清洗成纯文本（用于摘要回退与检索）。
String sanitizeHtmlToPlainText(
  String? html, {
  SanitizerLimits limits = const SanitizerLimits(),
}) => docDocumentPlainText(
  sanitizeHtmlToDocument(html, limits: limits).document.children,
).trim();

// ===========================================================================
// 1. 词法
// ===========================================================================

/// 会**连同内容**一起被丢弃的标签。
///
/// 与「保留文字」的未知标签不同，这些标签的内容本身就是代码或样式：保留下来只会变成
/// 满屏乱码，而且它们的存在往往意味着有人在尝试注入。整段丢弃并在诊断里记录标签名。
const Set<String> kDropWithContentTags = <String>{
  'script',
  'style',
  'iframe',
  'object',
  'embed',
  'applet',
  'noscript',
  'template',
  'svg',
  'math',
  'form',
  'input',
  'textarea',
  'select',
  'option',
  'button',
  'meta',
  'link',
  'base',
  'title',
  'head',
};

/// 块级标签白名单。
const Set<String> kBlockTags = <String>{
  'p',
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
  'blockquote',
  'ul',
  'ol',
  'li',
  'pre',
  'table',
  'thead',
  'tbody',
  'tfoot',
  'tr',
  'td',
  'th',
  'figure',
  'figcaption',
};

/// 行内标签白名单。
const Set<String> kInlineTags = <String>{
  'em',
  'i',
  'strong',
  'b',
  'code',
  'a',
  'span',
  'sub',
  'sup',
  'u',
  's',
  'del',
  'ins',
  'mark',
  'small',
  'big',
  'abbr',
  'cite',
  'q',
  'time',
  'label',
};

/// HTML 的**空元素**（void elements）：没有内容、没有结束标签。
///
/// 必须与 HTML 规范一致，不能只列常用的几个。原因很具体：
///   - 漏掉某个空元素时，解析器会把它当成「需要配对的开始标签」压栈；
///   - 于是它后面真正的结束标签会去配对**它**，而它的区间被误认为还没结束；
///   - 结果是后续内容整段被吞掉（曾用 `&lt;form&gt;&lt;input&gt;&lt;/form&gt;&lt;noscript&gt;…` 复现过：
///     `input` 不在空元素表里，导致后面的 `noscript` 被当成仍在丢弃区间内而漏登记）。
/// 规范清单：area, base, br, col, embed, hr, img, input, link, meta, param,
/// source, track, wbr。
const Set<String> kVoidTags = <String>{
  'area',
  'base',
  'br',
  'col',
  'embed',
  'hr',
  'img',
  'input',
  'link',
  'meta',
  'param',
  'source',
  'track',
  'wbr',
};

/// 实体解码结果。
sealed class _EntityResult {
  const _EntityResult();
}

/// 无法识别的实体（退化成字面 '&'）。
final class _UnknownEntity extends _EntityResult {
  const _UnknownEntity();
}

/// 必须整个丢弃的引用（指向控制字符/方向控制符）。
final class _DroppedEntity extends _EntityResult {
  const _DroppedEntity();
}

/// 成功解码。
final class _DecodedEntity extends _EntityResult {
  const _DecodedEntity(this.text);

  final String text;
}

/// 一个词法事件。
sealed class _Token {
  const _Token();
}

/// 开始标签。
final class _OpenTag extends _Token {
  const _OpenTag(this.name, this.attributes, {required this.selfClosing});

  final String name;
  final Map<String, String> attributes;
  final bool selfClosing;
}

/// 结束标签。
final class _CloseTag extends _Token {
  const _CloseTag(this.name);

  final String name;
}

/// 文本（已做实体解码）。
final class _TextToken extends _Token {
  const _TextToken(this.text);

  final String text;
}

/// 宽容的 HTML 分词器：只做词法层面的工作，不做白名单判断。
class _Tokenizer {
  _Tokenizer(this.input);

  final String input;
  int _pos = 0;

  List<_Token> tokenize() {
    final List<_Token> tokens = <_Token>[];
    final StringBuffer text = StringBuffer();

    void flushText() {
      if (text.isEmpty) {
        return;
      }
      final String decoded = _decodeEntities(text.toString());
      if (decoded.isNotEmpty) {
        tokens.add(_TextToken(decoded));
      }
      text.clear();
    }

    while (_pos < input.length) {
      final String char = input[_pos];
      if (char != '<') {
        text.write(char);
        _pos++;
        continue;
      }

      if (input.startsWith('<!--', _pos)) {
        final int end = input.indexOf('-->', _pos + 4);
        _pos = end == -1 ? input.length : end + 3;
        continue;
      }
      if (input.startsWith('<![CDATA[', _pos)) {
        // CDATA 的内容是**文本**而不是标记，这正是它存在的意义。
        final int end = input.indexOf(']]>', _pos + 9);
        final String raw = end == -1
            ? input.substring(_pos + 9)
            : input.substring(_pos + 9, end);
        text.write(raw);
        _pos = end == -1 ? input.length : end + 3;
        continue;
      }
      if (input.startsWith('<!', _pos) || input.startsWith('<?', _pos)) {
        final int end = input.indexOf('>', _pos);
        _pos = end == -1 ? input.length : end + 1;
        continue;
      }

      final bool closing = input.startsWith('</', _pos);
      final int nameStart = _pos + (closing ? 2 : 1);
      final int nameEnd = _scanName(nameStart);
      if (nameEnd == -1) {
        // 孤立的 '<'（例如 "3 < 5"）：当普通文本，不启动标签解析。
        text.write(char);
        _pos++;
        continue;
      }
      final String rawName = input.substring(nameStart, nameEnd);
      final int tagEnd = _scanTagEnd(nameEnd);
      final int end = tagEnd == -1 ? input.length : tagEnd + 1;
      final String rawTag = input.substring(_pos, end);
      // 属性区在原始输入里的偏移：从标签名结束处开始。
      final int attributesOffset = nameEnd - _pos;
      _pos = end;

      final String name = rawName.toLowerCase();
      flushText();
      if (closing) {
        tokens.add(_CloseTag(name));
        continue;
      }
      tokens.add(
        _OpenTag(
          name,
          _parseAttributes(rawTag, attributesOffset),
          selfClosing: rawTag.endsWith('/>') || kVoidTags.contains(name),
        ),
      );
    }

    flushText();
    return tokens;
  }

  /// 扫描标签名，返回结束位置；无合法名称时返回 -1。
  int _scanName(int from) {
    int i = from;
    final int start = i;
    while (i < input.length) {
      final int code = input.codeUnitAt(i);
      final bool ok =
          (code >= 0x41 && code <= 0x5A) || // A-Z
          (code >= 0x61 && code <= 0x7A) || // a-z
          (code >= 0x30 && code <= 0x39) || // 0-9
          code == 0x2D || // -
          code == 0x5F || // _
          code == 0x3A || // :
          code == 0x2E; // .
      if (!ok) {
        break;
      }
      i++;
    }
    return i == start ? -1 : i;
  }

  /// 从 [from] 找标签结束的 '>'，跳过引号内的内容；未找到返回 -1。
  int _scanTagEnd(int from) {
    int i = from;
    String? quote;
    while (i < input.length) {
      final String c = input[i];
      if (quote != null) {
        if (c == quote) {
          quote = null;
        }
      } else if (c == '"' || c == "'") {
        quote = c;
      } else if (c == '>') {
        return i;
      }
      i++;
    }
    return -1;
  }

  /// 解析属性（宽容：允许无引号值、忽略残缺属性）。
  ///
  /// [attributeStart] 是 rawTag 内的偏移（rawTag 以 '<' 开头）。
  Map<String, String> _parseAttributes(String rawTag, int attributeStart) {
    final Map<String, String> attributes = <String, String>{};
    int i = attributeStart.clamp(1, rawTag.length);
    int end = rawTag.length;
    while (end > 0 && (rawTag[end - 1] == '>' || rawTag[end - 1] == '/')) {
      end--;
    }
    while (i < end) {
      while (i < end && _isSpace(rawTag[i])) {
        i++;
      }
      if (i >= end) {
        break;
      }
      final int nameStart = i;
      while (i < end &&
          !_isSpace(rawTag[i]) &&
          rawTag[i] != '=' &&
          rawTag[i] != '/' &&
          rawTag[i] != '>') {
        i++;
      }
      if (i == nameStart) {
        // 无法前进时强制跳出，避免畸形输入造成死循环。
        i++;
        continue;
      }
      final String name = rawTag.substring(nameStart, i).toLowerCase();
      while (i < end && _isSpace(rawTag[i])) {
        i++;
      }
      String value = '';
      if (i < end && rawTag[i] == '=') {
        i++;
        while (i < end && _isSpace(rawTag[i])) {
          i++;
        }
        if (i < end && (rawTag[i] == '"' || rawTag[i] == "'")) {
          final String quote = rawTag[i];
          i++;
          final int valueStart = i;
          while (i < end && rawTag[i] != quote) {
            i++;
          }
          value = rawTag.substring(valueStart, i);
          if (i < end) {
            i++;
          }
        } else {
          final int valueStart = i;
          while (i < end && !_isSpace(rawTag[i]) && rawTag[i] != '>') {
            i++;
          }
          value = rawTag.substring(valueStart, i);
        }
      }
      // 同名属性只保留第一个：重复值在 HTML 里本就被忽略，保留会让「注入一个
      // 覆盖用的 href」看起来有效。
      if (name.isNotEmpty && !attributes.containsKey(name)) {
        attributes[name] = _decodeEntities(value);
      }
    }
    return attributes;
  }

  static bool _isSpace(String c) =>
      c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\f';

  /// 实体解码：命名实体 + 十进制 + 十六进制。
  static String _decodeEntities(String value) {
    if (!value.contains('&')) {
      return value;
    }
    final StringBuffer out = StringBuffer();
    int i = 0;
    while (i < value.length) {
      final String c = value[i];
      if (c != '&') {
        out.write(c);
        i++;
        continue;
      }
      final int semi = value.indexOf(';', i + 1);
      // 实体名过长时视为普通 '&'（真实文本里 "AT&T"、"3 & 5" 很常见）。
      if (semi == -1 || semi - i > 33) {
        out.write('&');
        i++;
        continue;
      }
      final _EntityResult decoded = _decodeEntity(value.substring(i + 1, semi));
      switch (decoded) {
        case _UnknownEntity():
          // 未收录的实体：退化成字面 '&'，其余字符按普通文本继续（不丢内容）。
          out.write('&');
          i++;
        case _DroppedEntity():
          // 数字字符引用指向控制字符/方向控制符：整个引用丢弃，
          // 但**不**留下 `&#0;` 这样的字面文本（那既难看又会让读者困惑）。
          i = semi + 1;
        case _DecodedEntity(:final String text):
          out.write(text);
          i = semi + 1;
      }
    }
    return out.toString();
  }

  static _EntityResult _decodeEntity(String body) {
    if (body.isEmpty) {
      return const _UnknownEntity();
    }
    if (body.startsWith('#x') || body.startsWith('#X')) {
      return _numericEntity(int.tryParse(body.substring(2), radix: 16));
    }
    if (body.startsWith('#')) {
      return _numericEntity(int.tryParse(body.substring(1)));
    }
    final String? named = _namedEntities[body];
    return named == null ? const _UnknownEntity() : _DecodedEntity(named);
  }

  /// 数字字符引用：能解码且码点合法就解码，否则整个引用丢弃。
  ///
  /// 与命名实体不同，这里**不**退化成字面文本：`&#0;`、`&#x202E;` 这类引用的唯一
  /// 作用就是注入不可见/混淆字符，把 `&#0;` 原样留在正文里只会让读者看到乱码。
  static _EntityResult _numericEntity(int? code) {
    final String? decoded = _codePoint(code);
    return decoded == null ? const _DroppedEntity() : _DecodedEntity(decoded);
  }

  /// 码点转字符；拒绝不可见控制字符、代理区与方向控制符。
  ///
  /// 为什么必须校验：`&#0;` 会把 NUL 注入文本；`&#x202E;` 之类的方向控制符可以
  /// 反转显示顺序（用于伪造文本），零宽字符可以隐藏内容。这些在正文里没有正当用途。
  static String? _codePoint(int? code) {
    if (code == null || code <= 0 || code > 0x10FFFF) {
      return null;
    }
    if (code >= 0xD800 && code <= 0xDFFF) {
      return null;
    }
    const Set<int> blocked = <int>{
      0x200B,
      0x200C,
      0x200D,
      0x200E,
      0x200F,
      0x202A,
      0x202B,
      0x202C,
      0x202D,
      0x202E,
      0x2066,
      0x2067,
      0x2068,
      0x2069,
      0xFEFF,
    };
    if (blocked.contains(code)) {
      return null;
    }
    // C0/C1 控制字符（\t \n \r 除外）一律丢弃。
    if (code < 0x20 && code != 0x09 && code != 0x0A && code != 0x0D) {
      return null;
    }
    if (code >= 0x7F && code <= 0x9F) {
      return null;
    }
    return String.fromCharCode(code);
  }

  /// 常用命名实体。
  ///
  /// 只覆盖实际会遇到的一小部分，而不是完整的 HTML 实体表：未收录的实体会退化成字面
  /// 文本——这是**故意**的取舍。收录全部 2000+ 实体需要一张大表，而长尾实体在正文里
  /// 概率极低，且退化成字面文本仍可读、不丢信息。影响阅读与安全的（< > & " '、空格、
  /// 引号、破折号）都收全了。
  static const Map<String, String> _namedEntities = <String, String>{
    'amp': '&',
    'lt': '<',
    'gt': '>',
    'quot': '"',
    'apos': "'",
    'nbsp': ' ',
    'copy': '©',
    'reg': '®',
    'trade': '™',
    'deg': '°',
    'plusmn': '±',
    'times': '×',
    'divide': '÷',
    'frac12': '½',
    'frac14': '¼',
    'frac34': '¾',
    'sup2': '²',
    'sup3': '³',
    'micro': 'µ',
    'para': '¶',
    'sect': '§',
    'middot': '·',
    'hellip': '…',
    'mdash': '—',
    'ndash': '–',
    'lsquo': '‘',
    'rsquo': '’',
    'ldquo': '“',
    'rdquo': '”',
    'laquo': '«',
    'raquo': '»',
    'larr': '←',
    'rarr': '→',
    'uarr': '↑',
    'darr': '↓',
    'harr': '↔',
    'bull': '•',
    'dagger': '†',
    'prime': '′',
    'euro': '€',
    'pound': '£',
    'yen': '¥',
    'cent': '¢',
    'eacute': 'é',
    'egrave': 'è',
    'agrave': 'à',
    'ccedil': 'ç',
    'uuml': 'ü',
    'ouml': 'ö',
    'auml': 'ä',
    'szlig': 'ß',
    'alpha': 'α',
    'beta': 'β',
    'gamma': 'γ',
    'pi': 'π',
    'infin': '∞',
    'ne': '≠',
    'le': '≤',
    'ge': '≥',
  };
}

// ===========================================================================
// 2. 元素树（宽容闭合）
// ===========================================================================

/// 一个元素节点。
class _Element {
  _Element(this.name, this.attributes);

  final String name;
  final Map<String, String> attributes;

  /// 子节点：[_Element] 或 String（文本）。
  final List<Object> children = <Object>[];
}

/// 从词法事件构造元素树。
///
/// 宽容策略（本层唯一复杂的地方，因此显式写下来）：
///   - 未闭合的标签在文档结束时自动闭合（栈里剩下的元素直接留在树上）；
///   - 遇到结束标签时向上找最近的同名开始标签，把它之上的未闭合元素一并闭合；
///   - 找不到对应开始标签的结束标签被忽略；
///   - script 类标签连同内容整段丢弃，用**深度计数**而不是「跳过下一个结束标签」，
///     因为嵌套的同名标签必须配对（`<script>...<script>...</script>...</script>`）。
/// 深度上限在这里就生效：超限的元素不再入树，避免畸形输入构造出极深的结构。
class _ElementTree {
  _ElementTree({required this.limits});

  final SanitizerLimits limits;

  /// 顶层子节点。
  final List<Object> children = <Object>[];

  /// 被整段丢弃的标签名（按首次出现顺序去重）。
  final List<String> droppedBlocks = <String>[];

  final List<_Element> _stack = <_Element>[];
  final Set<String> _dropped = <String>{};

  /// 丢弃区间的剩余嵌套深度（0 表示不在丢弃区间）。
  int _dropping = 0;

  /// 是否触及深度上限。
  bool hitDepthLimit = false;

  List<Object> get _current => _stack.isEmpty ? children : _stack.last.children;

  void consume(List<_Token> tokens) {
    for (final _Token token in tokens) {
      switch (token) {
        case _OpenTag():
          _open(token);
        case _CloseTag():
          _close(token);
        case _TextToken():
          // 丢弃区间内的文本必须一并丢弃，否则脚本源码会变成正文文字。
          if (_dropping == 0) {
            _current.add(token.text);
          }
      }
    }
  }

  void _open(_OpenTag tag) {
    if (_dropping > 0) {
      if (!tag.selfClosing) {
        _dropping++;
      }
      return;
    }
    if (kDropWithContentTags.contains(tag.name)) {
      if (_dropped.add(tag.name)) {
        droppedBlocks.add(tag.name);
      }
      if (!tag.selfClosing) {
        _dropping = 1;
      }
      return;
    }
    if (_stack.length >= limits.maxDepth) {
      hitDepthLimit = true;
      return;
    }
    final _Element element = _Element(tag.name, tag.attributes);
    _current.add(element);
    if (!tag.selfClosing) {
      _stack.add(element);
    }
  }

  void _close(_CloseTag tag) {
    if (_dropping > 0) {
      _dropping--;
      return;
    }
    int index = -1;
    for (int i = _stack.length - 1; i >= 0; i--) {
      if (_stack[i].name == tag.name) {
        index = i;
        break;
      }
    }
    if (index == -1) {
      return;
    }
    while (_stack.length > index) {
      _stack.removeLast();
    }
  }
}

// ===========================================================================
// 3. 元素树 → 受控文档树
// ===========================================================================

/// 属性白名单（其余属性一律丢弃）。
///
/// 只保留渲染真正需要的：href（链接）、src/alt（图片）、start（有序列表起点）、
/// class（代码语言）、title（悬停说明）。**不保留** style、id、on*、srcset、
/// width、height：前两者没有用处，on* 是注入面，后三者会与阅读版式冲突（正文宽度
/// 由应用决定，源里写死的尺寸会让窄窗出现横向滚动）。
const Set<String> kAllowedDocAttributes = <String>{
  'href',
  'src',
  'alt',
  'start',
  'class',
  'title',
};

/// 把元素树转换成受控文档树。
class _Converter {
  _Converter({required this.limits});

  final SanitizerLimits limits;

  /// 被拒绝的 URL 数量。
  int rejectedUrls = 0;

  /// 是否触及节点数上限。
  bool hitNodeLimit = false;

  /// 是否触及深度上限。
  bool hitDepthLimit = false;

  int _nodes = 0;

  /// 消耗一个节点配额；返回 false 表示已达上限（调用方应停止产出节点）。
  bool _budget() {
    if (_nodes >= limits.maxNodes) {
      hitNodeLimit = true;
      return false;
    }
    _nodes++;
    return true;
  }

  /// 转换一批块级子节点。
  ///
  /// 裸行内内容会被聚集成段落：`<div>文字<a>x</a></div>` 这种结构在真实源里极常见，
  /// 如果直接丢弃就等于丢正文。
  List<DocNode> convertBlocks(List<Object> nodes, {int depth = 0}) {
    final List<DocNode> out = <DocNode>[];
    List<DocInline> pending = <DocInline>[];

    void flushPending() {
      final List<DocInline> trimmed = _trimInlines(pending);
      pending = <DocInline>[];
      if (trimmed.isEmpty) {
        return;
      }
      if (_budget()) {
        out.add(DocParagraph(trimmed));
      }
    }

    for (final Object node in nodes) {
      if (hitNodeLimit) {
        break;
      }
      if (node is String) {
        pending.addAll(_textInlines(node));
        continue;
      }
      final _Element element = node as _Element;
      if (_isStandaloneBlock(element.name)) {
        // hr 是块级语义的孤立标签（没有内容）。它同时满足「孤立标签」与「块级语义」，
        // 若跟着下面的行内分支走就会变成 DocHardBreak，整条分隔线消失。
        flushPending();
        final DocNode? block = _convertBlockElement(element, depth: depth);
        if (block != null) {
          out.add(block);
        }
        continue;
      }
      if (kInlineTags.contains(element.name) ||
          kVoidTags.contains(element.name)) {
        // 行内级元素出现在块级上下文里：并入当前段落。
        pending.addAll(convertInlineOf(element, depth: depth));
        continue;
      }
      if (_isTransparentContainer(element.name)) {
        final _Split split = _splitChildren(element, depth: depth);
        pending.addAll(split.inline);
        flushPending();
        out.addAll(split.blocks);
        continue;
      }
      flushPending();
      final DocNode? block = _convertBlockElement(element, depth: depth);
      if (block != null) {
        out.add(block);
      } else if (_needsContentFallback(element)) {
        // 块级转换返回 null 意味着「这个标签不是已知块级结构」（未知标签、孤立 li）。
        // 未知标签必须**保留其文字**，否则读者会看到「正文少了半段」而无人察觉。
        // 递归子节点即可：它们的文本会走 convertBlocks 的裸行内分支被聚成段落。
        out.addAll(convertBlocks(element.children, depth: depth + 1));
      }
    }
    flushPending();
    return out;
  }

  /// 块级转换返回 null 时，是否需要用「保留文字」的兜底递归。
  ///
  /// 已知块级标签返回 null 只表示「内容为空」（例如空的 <p>），此时不该再递归——
  /// 递归也拿不到东西，只会白跑一遍。只有真正的未知标签与孤立 <li> 需要兜底。
  static bool _needsContentFallback(_Element element) =>
      !kBlockTags.contains(element.name);

  /// 无内容的**块级**孤立标签（目前只有 hr）。
  ///
  /// 这类标签同时满足「孤立标签」（无内容、不需配对）与「块级语义」，任何一边的判断
  /// 都不足以覆盖它，因此单独列出，避免它落进行内分支被降级成硬换行。
  static bool _isStandaloneBlock(String name) => name == 'hr';

  /// 透明容器：本身不产出节点，只是位置（div/figure）。
  static bool _isTransparentContainer(String name) =>
      name == 'div' || name == 'figure' || name == 'figcaption';

  /// 把元素的子节点拆成「裸行内」与「块级」两部分。
  _Split _splitChildren(_Element element, {required int depth}) {
    final List<DocNode> blocks = <DocNode>[];
    List<DocInline> pending = <DocInline>[];

    void flush() {
      final List<DocInline> trimmed = _trimInlines(pending);
      pending = <DocInline>[];
      if (trimmed.isEmpty) {
        return;
      }
      if (_budget()) {
        blocks.add(DocParagraph(trimmed));
      }
    }

    for (final Object child in element.children) {
      if (child is String) {
        pending.addAll(_textInlines(child));
        continue;
      }
      final _Element childElement = child as _Element;
      if (_isStandaloneBlock(childElement.name)) {
        flush();
        final DocNode? block = _convertBlockElement(childElement, depth: depth);
        if (block != null) {
          blocks.add(block);
        }
        continue;
      }
      if (kInlineTags.contains(childElement.name) ||
          kVoidTags.contains(childElement.name)) {
        pending.addAll(convertInlineOf(childElement, depth: depth));
        continue;
      }
      if (_isTransparentContainer(childElement.name)) {
        final _Split nested = _splitChildren(childElement, depth: depth);
        pending.addAll(nested.inline);
        flush();
        blocks.addAll(nested.blocks);
        continue;
      }
      flush();
      final DocNode? block = _convertBlockElement(childElement, depth: depth);
      if (block != null) {
        blocks.add(block);
      }
    }
    final List<DocInline> inline = _trimInlines(pending);
    return _Split(inline: inline, blocks: blocks);
  }

  DocNode? _convertBlockElement(_Element element, {required int depth}) {
    if (depth + 1 > limits.maxDepth) {
      hitDepthLimit = true;
      return null;
    }
    switch (element.name) {
      case 'p':
        final List<DocInline> children = convertInline(
          element.children,
          depth: depth + 1,
        );
        if (children.isEmpty) {
          return null;
        }
        return _budget() ? DocParagraph(children) : null;
      case 'h1':
      case 'h2':
      case 'h3':
      case 'h4':
      case 'h5':
      case 'h6':
        final List<DocInline> children = convertInline(
          element.children,
          depth: depth + 1,
        );
        if (children.isEmpty) {
          return null;
        }
        final int level = int.parse(element.name.substring(1));
        return _budget() ? DocHeading(level, children) : null;
      case 'blockquote':
        // 只调用一次 convertBlocks：它内部已经会把「裸行内内容」聚成段落。
        // 曾经这里同时调用 convertBlocks 与 convertInline，结果是引用里的每个段落
        // 都被产出两遍——那是重复内容，不是排版差异。
        final List<DocNode> children = convertBlocks(
          element.children,
          depth: depth + 1,
        );
        if (children.isEmpty) {
          return null;
        }
        return _budget() ? DocBlockQuote(children) : null;
      case 'ul':
      case 'ol':
        return _convertList(element, depth: depth);
      case 'pre':
        return _convertPre(element);
      case 'table':
        return _convertTable(element, depth: depth);
      case 'hr':
        return _budget() ? const DocThematicBreak() : null;
      default:
        // 未知块级标签（含孤立 li）：外壳不存在，但内容必须保留。
        //
        // 这里返回 null 而不是包一个节点，同时**不**把内容写进任何全局暂存：
        // 调用方 _convertBlockList 会在拿到 null 后自行递归该元素，因此每层的内容
        // 只被产出一次。用全局暂存容易出现「同一段内容被两次加入」的重复。
        return null;
    }
  }

  DocNode? _convertList(_Element element, {required int depth}) {
    final bool ordered = element.name == 'ol';
    int start = 1;
    if (ordered) {
      final int? parsed = int.tryParse(element.attributes['start'] ?? '');
      if (parsed != null && parsed > 0) {
        start = parsed;
      }
    }
    final List<DocListItem> items = <DocListItem>[];
    for (final Object child in element.children) {
      if (hitNodeLimit) {
        break;
      }
      if (child is! _Element || child.name != 'li') {
        // 列表里直接出现的文本（如 <ul>裸文本</ul>）：包成一个列表项，不丢内容。
        if (child is String && child.trim().isNotEmpty) {
          final List<DocInline> inline = _trimInlines(_textInlines(child));
          if (inline.isNotEmpty && _budget()) {
            items.add(DocListItem(children: <DocNode>[DocParagraph(inline)]));
          }
        }
        continue;
      }
      // 只走 convertBlocks：<li>纯文字</li> 会被它聚成一个段落。
      // 曾经这里还叠加了一次 convertInline，结果是每个列表项的正文出现两遍——
      // 这是重复内容，读者会看到同一句话印在项里两次。
      final List<DocNode> children = convertBlocks(
        child.children,
        depth: depth + 1,
      );
      if (children.isEmpty) {
        continue;
      }
      if (!_budget()) {
        break;
      }
      items.add(DocListItem(children: children));
    }
    if (items.isEmpty) {
      return null;
    }
    return _budget()
        ? DocList(ordered: ordered, start: start, items: items)
        : null;
  }

  DocNode? _convertPre(_Element element) {
    // pre 内的一切都按字面文本处理（含子标签的文字），这是代码块的语义。
    final StringBuffer buffer = StringBuffer();
    void walk(List<Object> nodes) {
      for (final Object node in nodes) {
        if (node is String) {
          buffer.write(node);
        } else {
          walk((node as _Element).children);
        }
      }
    }

    walk(element.children);
    final String code = _trimTrailingNewlines(buffer.toString());
    if (code.trim().isEmpty) {
      return null;
    }
    return _budget()
        ? DocCodeBlock(code: code, language: _detectCodeLanguage(element))
        : null;
  }

  /// 从 `class="language-dart"` 或 `class="lang-dart"` 提取语言标识。
  static String? _detectCodeLanguage(_Element element) {
    final String classes = element.attributes['class'] ?? '';
    for (final String raw in classes.split(RegExp(r'\s+'))) {
      final String token = raw.trim();
      if (token.isEmpty) {
        continue;
      }
      for (final String prefix in <String>['language-', 'lang-', 'brush:']) {
        if (token.toLowerCase().startsWith(prefix) &&
            token.length > prefix.length) {
          return token.substring(prefix.length).toLowerCase();
        }
      }
    }
    // <pre><code class="language-x"> 的常见写法：语言在子 code 上。
    for (final Object child in element.children) {
      if (child is _Element && child.name == 'code') {
        return _detectCodeLanguage(child);
      }
    }
    return null;
  }

  DocNode? _convertTable(_Element element, {required int depth}) {
    final List<List<List<DocInline>>> rows = <List<List<DocInline>>>[];
    final List<List<List<DocInline>>> headRows = <List<List<DocInline>>>[];

    void collectRows(List<Object> nodes, {required bool inHead}) {
      for (final Object node in nodes) {
        if (node is! _Element) {
          continue;
        }
        switch (node.name) {
          case 'thead':
            collectRows(node.children, inHead: true);
          case 'tbody':
          case 'tfoot':
            collectRows(node.children, inHead: false);
          case 'tr':
            // 一行由若干单元格组成，每个单元格是一段行内内容。
            final List<List<DocInline>> cells = <List<DocInline>>[];
            for (final Object cell in node.children) {
              if (cell is! _Element ||
                  (cell.name != 'td' && cell.name != 'th')) {
                continue;
              }
              cells.add(convertInline(cell.children, depth: depth + 1));
            }
            if (cells.isEmpty) {
              continue;
            }
            (inHead ? headRows : rows).add(cells);
          default:
            collectRows(node.children, inHead: inHead);
        }
      }
    }

    collectRows(element.children, inHead: false);

    // HTML 不强制 thead：没有 thead 时把第一行当表头，这是最常见的排版约定。
    final List<List<DocInline>> header;
    if (headRows.isNotEmpty) {
      header = headRows.first;
    } else if (rows.isNotEmpty) {
      header = rows.removeAt(0);
    } else {
      return null;
    }
    if (header.isEmpty && rows.isEmpty) {
      return null;
    }
    return _budget() ? DocTable(header: header, rows: rows) : null;
  }

  /// 转换一批子节点中的行内内容。
  List<DocInline> convertInline(List<Object> nodes, {required int depth}) {
    final List<DocInline> out = <DocInline>[];
    for (final Object node in nodes) {
      if (hitNodeLimit) {
        break;
      }
      if (node is String) {
        out.addAll(_textInlines(node));
        continue;
      }
      out.addAll(convertInlineOf(node as _Element, depth: depth));
    }
    return out;
  }

  /// 转换单个元素为行内节点（可能产出 0 个、1 个或多个）。
  List<DocInline> convertInlineOf(_Element element, {required int depth}) {
    if (depth + 1 > limits.maxDepth) {
      hitDepthLimit = true;
      return const <DocInline>[];
    }
    switch (element.name) {
      case 'br':
        _nodes++;
        return const <DocInline>[DocHardBreak()];
      case 'hr':
        // hr 是块级语义，出现在行内位置时降级为硬换行（避免整段消失）。
        _nodes++;
        return const <DocInline>[DocHardBreak()];
      case 'img':
        final DocInline? image = _buildImage(element.attributes);
        if (image == null) {
          return const <DocInline>[];
        }
        _nodes++;
        return <DocInline>[image];
      case 'em':
      case 'i':
        final List<DocInline> children = convertInline(
          element.children,
          depth: depth + 1,
        );
        if (children.isEmpty) {
          return const <DocInline>[];
        }
        _nodes++;
        return <DocInline>[DocEmphasis(children)];
      case 'strong':
      case 'b':
        final List<DocInline> children = convertInline(
          element.children,
          depth: depth + 1,
        );
        if (children.isEmpty) {
          return const <DocInline>[];
        }
        _nodes++;
        return <DocInline>[DocStrong(children)];
      case 'code':
        final String text = _plainTextOf(element.children);
        if (text.isEmpty) {
          return const <DocInline>[];
        }
        _nodes++;
        return <DocInline>[DocCodeSpan(text)];
      case 'a':
        _nodes++;
        return <DocInline>[_buildLink(element, depth: depth)];
      default:
        // 其它行内标签（span/u/s/mark/time…）只是外壳：保留文字。
        return convertInline(element.children, depth: depth + 1);
    }
  }

  DocRejectedUrl _rejected(String raw, String label) {
    rejectedUrls++;
    return DocRejectedUrl(
      url: raw,
      label: label.isEmpty ? raw : label,
      reason: _rejectReason(raw),
    );
  }

  DocInline _buildLink(_Element element, {required int depth}) {
    final String raw = (element.attributes['href'] ?? '').trim();
    final List<DocInline> children = convertInline(
      element.children,
      depth: depth + 1,
    );
    final String label = docInlinePlainText(children);
    if (raw.startsWith('#')) {
      // 页内锚点（Hugo/Hexo 的标题自链接常是 <a href="#.."></a>）：不是外链。
      // 空锚点直接丢弃（否则 href 文本会被当作正文印出来，形如 #%e8...起因）；
      // 带文字的锚点只保留文字。
      return DocText(label);
    }
    if (raw.isEmpty) {
      // 没有 href 的 <a>：只保留文字。
      return DocText(label);
    }
    if (!isSafeDocUrl(raw)) {
      return _rejected(raw, label);
    }
    return DocLinkInline(
      url: raw,
      children: children.isEmpty ? <DocInline>[DocText(raw)] : children,
    );
  }

  DocInline? _buildImage(Map<String, String> attributes) {
    final String raw = (attributes['src'] ?? '').trim();
    final String alt = (attributes['alt'] ?? '').trim();
    if (raw.isEmpty) {
      return null;
    }
    if (!isSafeDocUrl(raw)) {
      return _rejected(raw, alt);
    }
    return DocImageInline(url: raw, alt: alt);
  }

  static String _rejectReason(String url) {
    final int colon = url.indexOf(':');
    if (colon <= 0) {
      return 'relative-or-schemeless';
    }
    final String scheme = url.substring(0, colon).toLowerCase();
    if (kBlockedDocUrlSchemes.contains(scheme)) {
      return 'blocked-scheme:$scheme';
    }
    return 'unsupported-scheme:$scheme';
  }

  /// 把文本切成行内节点。
  ///
  /// 折叠连续空白：HTML 的排版规则本就是「连续空白视作一个空格」，而源文件里的换行与
  /// 缩进不应在正文中产生额外空白；不折叠会让排版出现随机的大段空白。
  static List<DocInline> _textInlines(String text) {
    final String collapsed = text.replaceAll(RegExp(r'[ \t\r\n\f]+'), ' ');
    if (collapsed.isEmpty) {
      return const <DocInline>[];
    }
    return <DocInline>[DocText(collapsed)];
  }

  /// 去掉段落首尾的纯空白文本节点与首尾空格。
  static List<DocInline> _trimInlines(List<DocInline> nodes) {
    final List<DocInline> out = List<DocInline>.of(nodes);
    while (out.isNotEmpty) {
      final DocInline first = out.first;
      if (first is DocText && first.text.trim().isEmpty) {
        out.removeAt(0);
        continue;
      }
      break;
    }
    while (out.isNotEmpty) {
      final DocInline last = out.last;
      if (last is DocText && last.text.trim().isEmpty) {
        out.removeLast();
        continue;
      }
      break;
    }
    // 段落内部的首尾空格也要去掉：折叠后 ' 文字 ' 会留下可见的空隙。
    if (out.isNotEmpty && out.first is DocText) {
      final DocText first = out.first as DocText;
      final String trimmed = first.text.replaceFirst(RegExp(r'^ +'), '');
      if (trimmed.isEmpty) {
        out.removeAt(0);
      } else {
        out[0] = DocText(trimmed);
      }
    }
    if (out.isNotEmpty && out.last is DocText) {
      final DocText last = out.last as DocText;
      final String trimmed = last.text.replaceFirst(RegExp(r' +$'), '');
      if (trimmed.isEmpty) {
        out.removeLast();
      } else {
        out[out.length - 1] = DocText(trimmed);
      }
    }
    return out;
  }

  static String _plainTextOf(List<Object> nodes) {
    final StringBuffer buffer = StringBuffer();
    void walk(List<Object> list) {
      for (final Object node in list) {
        if (node is String) {
          buffer.write(node);
        } else {
          walk((node as _Element).children);
        }
      }
    }

    walk(nodes);
    return buffer.toString();
  }

  static String _trimTrailingNewlines(String code) {
    String out = code;
    while (out.endsWith('\n')) {
      out = out.substring(0, out.length - 1);
    }
    return out;
  }
}

/// 拆分结果（裸行内内容 vs 块级内容）。
class _Split {
  const _Split({required this.inline, required this.blocks});

  final List<DocInline> inline;
  final List<DocNode> blocks;
}
