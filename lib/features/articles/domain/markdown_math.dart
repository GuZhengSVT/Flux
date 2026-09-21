// Markdown 正文里的 LaTeX 定界符处理（T019；移植自 T004 原型并做产品化调整）。
//
// 为什么数学必须在 Markdown 解析**之前**被摘出来：TeX 正文里满是 CommonMark 的标记
// 字符。`$a_i + b_j$` 的两个下划线会被读成一个强调对，`\frac{a}{b}` 会被当成转义
// 丢掉花括号。先摘出来，渲染层才能拿到作者写的那一份原始字节。
//
// 定界符规则（一条规则，处处一致）：
//   * 美元号能**开启**一段公式：仅当它的下一个字符既不是数字也不是空白；
//   * 美元号能**闭合**一段公式：仅当它的前一个字符不是空白；
//   * 两者都不是的美元号是货币，被转义成字面文本。
//
// 这就是 `我花了 $100`、`$5 to $10`、`价格 $ 与 $` 与 `$x^2$` 的区别。有意不支持
// 带空格的定界符（`$ x $` 保持字面）：在中英混排文本里，美元号后面跟一个空格压倒
// 性地是货币或散文，不是公式。这条规则与 T004 原型一致，并由同一份 fixture 固化。
library;

/// 包住受保护公式的哨兵标记。
///
/// 取自没有 Markdown 语义的字符，使解析器把它当作普通文本原样透传。
const String kMathSentinelPrefix = '%%FLUXMATH';

/// 哨兵收尾。
const String kMathSentinelSuffix = '%%';

/// [index] 位置的字符是否被奇数个反斜杠转义。
bool _isEscaped(String source, int index) {
  int backslashes = 0;
  int i = index - 1;
  while (i >= 0 && source[i] == r'\') {
    backslashes++;
    i--;
  }
  return backslashes.isOdd;
}

bool _isDigit(String ch) {
  if (ch.length != 1) {
    return false;
  }
  final int code = ch.codeUnitAt(0);
  return code >= 0x30 && code <= 0x39;
}

bool _isSpace(String ch) => ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r';

/// [index] 处的美元号能否开启一段公式。
bool canOpenMathSpan(String source, int index) {
  if (source[index] != r'$') {
    return false;
  }
  if (_isEscaped(source, index)) {
    return false;
  }
  if (index + 1 >= source.length) {
    return false;
  }
  final String after = source[index + 1];
  if (_isSpace(after)) {
    return false;
  }
  if (_isDigit(after)) {
    return false;
  }
  return true;
}

/// [index] 处的美元号能否闭合一段公式。
bool canCloseMathSpan(String source, int index) {
  if (source[index] != r'$') {
    return false;
  }
  if (_isEscaped(source, index)) {
    return false;
  }
  if (index == 0) {
    return false;
  }
  return !_isSpace(source[index - 1]);
}

/// 把货币美元号转义，使 CommonMark 把它渲染成字面文本。
String escapeCurrencyDollars(String markdown) {
  final StringBuffer out = StringBuffer();
  for (int i = 0; i < markdown.length; i++) {
    final String ch = markdown[i];
    if (ch != r'$') {
      out.write(ch);
      continue;
    }
    if (canOpenMathSpan(markdown, i) || canCloseMathSpan(markdown, i)) {
      out.write(r'$');
    } else {
      out.write(r'\$');
    }
  }
  return out.toString();
}

/// 文本里找到的一段行内公式。
class MathSegment {
  /// 构造片段。
  const MathSegment({
    required this.tex,
    required this.start,
    required this.end,
  });

  /// TeX 正文。
  final String tex;

  /// 起始下标（含定界符）。
  final int start;

  /// 结束下标（不含定界符）。
  final int end;

  @override
  String toString() => 'MathSegment($start..$end, "$tex")';
}

/// 从左到右找出全部行内公式，互不重叠。
///
/// 未闭合的定界符**保持不动**：一个孤立的美元号更可能是货币或散文，而不是写坏的公式。
List<MathSegment> splitInlineMath(String source) {
  final List<MathSegment> out = <MathSegment>[];
  int i = 0;
  while (i < source.length) {
    if (source[i] != r'$' || !canOpenMathSpan(source, i)) {
      i++;
      continue;
    }
    final int close = _findInlineClose(source, i + 1);
    if (close == -1) {
      i++;
      continue;
    }
    final String tex = source.substring(i + 1, close);
    if (tex.trim().isEmpty) {
      i++;
      continue;
    }
    out.add(MathSegment(tex: tex, start: i, end: close + 1));
    i = close + 1;
  }
  return out;
}

int _findInlineClose(String source, int from) {
  for (int k = from; k < source.length; k++) {
    // 行内公式不跨换行。没有这条规则，一个落单的美元号（打错，或被上面启发式判成
    // 非货币的金额）会与后面某段的美元号配成一对，把中间整段悄悄吞进公式里。
    if (source[k] == '\n') {
      return -1;
    }
    if (source[k] != r'$') {
      continue;
    }
    if (_isEscaped(source, k)) {
      continue;
    }
    if (!canCloseMathSpan(source, k)) {
      continue;
    }
    // 闭合美元号后面紧跟数字说明这本来就是货币：`$100 and $200` 不得连成一段公式。
    if (k + 1 < source.length && _isDigit(source[k + 1])) {
      continue;
    }
    return k;
  }
  return -1;
}

/// 已经摘出公式的 Markdown 源与它的 TeX 正文表。
class ProtectedDocument {
  /// 构造结果。
  const ProtectedDocument({required this.markdown, required this.math});

  /// 每一段公式都被替换成哨兵的 Markdown。
  final String markdown;

  /// TeX 正文，下标即哨兵里的编号。
  final List<String> math;

  @override
  String toString() => 'ProtectedDocument(math=${math.length})';
}

/// 把行内与独占公式都替换成哨兵。
///
/// 独占公式先跑：`$$...$$` 不能被当成两段行内公式消费掉。
ProtectedDocument protectMath(String markdown) {
  final String escaped = escapeCurrencyDollars(markdown);
  final List<String> math = <String>[];
  final String afterDisplay = _protectDisplayMath(escaped, math);
  return ProtectedDocument(
    markdown: _protectInlineMath(afterDisplay, math),
    math: math,
  );
}

/// 生成第 [index] 段公式的哨兵。
String mathSentinel(int index) =>
    kMathSentinelPrefix + index.toString() + kMathSentinelSuffix;

/// 读出 [token] 里的公式编号；不是哨兵时返回 null。
int? mathSentinelIndex(String token) {
  if (!token.startsWith(kMathSentinelPrefix)) {
    return null;
  }
  if (!token.endsWith(kMathSentinelSuffix)) {
    return null;
  }
  final String body = token.substring(
    kMathSentinelPrefix.length,
    token.length - kMathSentinelSuffix.length,
  );
  return int.tryParse(body);
}

String _protectInlineMath(String markdown, List<String> math) {
  final StringBuffer out = StringBuffer();
  int cursor = 0;
  for (final MathSegment segment in splitInlineMath(markdown)) {
    out.write(markdown.substring(cursor, segment.start));
    out.write(mathSentinel(math.length));
    math.add(segment.tex);
    cursor = segment.end;
  }
  out.write(markdown.substring(cursor));
  return out.toString();
}

String _protectDisplayMath(String markdown, List<String> math) {
  final List<String> lines = markdown.split('\n');
  final List<String> out = <String>[];
  int i = 0;
  while (i < lines.length) {
    final String line = lines[i];
    final int? openAt = _displayOpenIndex(line);
    if (openAt == null) {
      out.add(line);
      i++;
      continue;
    }
    final String afterOpen = line.substring(openAt + 2);
    final String leading = line.substring(0, openAt);
    final int sameLine = _displayCloseIndex(afterOpen, 0);
    if (sameLine != -1) {
      if (leading.trim().isNotEmpty) {
        out.add(leading);
      }
      out.add(mathSentinel(math.length));
      math.add(afterOpen.substring(0, sameLine).trim());
      final String trailing = afterOpen.substring(sameLine + 2);
      if (trailing.trim().isNotEmpty) {
        out.add(trailing);
      }
      i++;
      continue;
    }
    final List<String> body = <String>[afterOpen];
    int j = i + 1;
    bool closed = false;
    while (j < lines.length) {
      final int closeAt = _displayCloseIndex(lines[j], 0);
      if (closeAt != -1) {
        final String head = lines[j].substring(0, closeAt);
        if (head.trim().isNotEmpty) {
          body.add(head);
        }
        final String tail = lines[j].substring(closeAt + 2);
        if (tail.trim().isNotEmpty) {
          body.add(tail);
        }
        closed = true;
        break;
      }
      body.add(lines[j]);
      j++;
    }
    if (!closed) {
      // 没找到闭合：整段保持原样（宁可让读者看到原文，也不吞掉后面的段落）。
      out.add(line);
      i++;
      continue;
    }
    if (leading.trim().isNotEmpty) {
      out.add(leading);
    }
    out.add(mathSentinel(math.length));
    math.add(body.join('\n').trim());
    i = j + 1;
  }
  return out.join('\n');
}

/// [line] 上独占公式开启符的下标；要求这一行除了空白没有别的前缀，且紧跟的不是数字。
int? _displayOpenIndex(String line) {
  final int at = line.indexOf(r'$$');
  if (at == -1) {
    return null;
  }
  if (_isEscaped(line, at)) {
    return null;
  }
  if (line.substring(0, at).trim().isNotEmpty) {
    return null;
  }
  final String after = line.substring(at + 2);
  if (after.isNotEmpty && _isDigit(after[0])) {
    return null;
  }
  return at;
}

/// [haystack] 里从 [from] 开始的独占公式闭合符下标；没有返回 -1。
int _displayCloseIndex(String haystack, int from) {
  int k = from;
  while (k < haystack.length - 1) {
    if (haystack[k] == r'$' &&
        haystack[k + 1] == r'$' &&
        !_isEscaped(haystack, k)) {
      return k;
    }
    k++;
  }
  return -1;
}
