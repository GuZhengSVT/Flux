// 代码块的静态高亮（T019；架构 4.2「代码静态高亮…未知语言按纯文本显示」）。
//
// 「静态」是字面意思：这是一个**纯 Dart 的词法着色器**，不注入脚本、不下载语法定义、
// 不引入任何 WebView 或远端服务。它认识的语法集合是固定的一小份，未知语言一律按纯文本
// 显示——架构明确要求「未知语言按纯文本显示」，而猜测一套语法只会把代码涂成误导性的颜色。
//
// 各语言的规则都用**同一套**词法（注释 / 字符串 / 数字 / 关键字 / 标识符调用），只有关键字
// 表与注释符号不同。这样做的理由是：一份真正的语法分析器（能分辨 JSX、泛型嵌套、宏展开）
// 需要为每种语言单独实现与验证，而着色错误在阅读代码时比不着色更糟——读者会以为某个
// 标识符是关键字。词法级着色不会声称自己理解语法，因此不会给出「这是函数定义」这类断言。
library;

/// 一段着色文本。
class HighlightSpan {
  /// 构造片段。
  const HighlightSpan(this.text, this.kind);

  /// 文本内容。
  final String text;

  /// 类别。
  final HighlightKind kind;

  @override
  String toString() => 'HighlightSpan(${kind.name}, "$text")';
}

/// 着色的类别。
enum HighlightKind {
  /// 普通文本。
  plain,

  /// 关键字。
  keyword,

  /// 字符串（含引号）。
  string,

  /// 注释。
  comment,

  /// 数字。
  number,

  /// 类型/类名（首字母大写的标识符）。
  type,
}

/// 一份语言的词法配置。
class _LanguageSpec {
  const _LanguageSpec({
    required this.lineComment,
    required this.blockComment,
    required this.keywords,
  });

  /// 行注释起始符；null 表示该语言没有行注释。
  final List<String> lineComment;

  /// 块注释定界符；null 表示没有。
  final (String, String)? blockComment;

  /// 关键字（含常见字面量与类型）。
  final Set<String> keywords;
}

const Set<String> _cLikeKeywords = <String>{
  'abstract',
  'as',
  'assert',
  'async',
  'await',
  'base',
  'bool',
  'break',
  'case',
  'catch',
  'char',
  'class',
  'const',
  'continue',
  'default',
  'defer',
  'do',
  'double',
  'dynamic',
  'else',
  'enum',
  'export',
  'extends',
  'extension',
  'external',
  'false',
  'final',
  'finally',
  'float',
  'for',
  'func',
  'get',
  'goto',
  'if',
  'implements',
  'import',
  'in',
  'interface',
  'int',
  'is',
  'late',
  'let',
  'long',
  'map',
  'mixin',
  'namespace',
  'new',
  'null',
  'operator',
  'override',
  'package',
  'private',
  'protected',
  'public',
  'required',
  'return',
  'sealed',
  'set',
  'short',
  'static',
  'struct',
  'super',
  'switch',
  'sync',
  'this',
  'throw',
  'true',
  'try',
  'typedef',
  'var',
  'void',
  'while',
  'with',
  'yield',
  'string',
  'number',
  'boolean',
  'any',
  'undefined',
};

const Set<String> _pythonKeywords = <String>{
  'and',
  'as',
  'assert',
  'async',
  'await',
  'break',
  'class',
  'continue',
  'def',
  'del',
  'elif',
  'else',
  'except',
  'False',
  'finally',
  'for',
  'from',
  'global',
  'if',
  'import',
  'in',
  'is',
  'lambda',
  'None',
  'nonlocal',
  'not',
  'or',
  'pass',
  'raise',
  'return',
  'True',
  'try',
  'while',
  'with',
  'yield',
  'match',
  'case',
  'self',
  'int',
  'str',
  'float',
  'bool',
  'list',
  'dict',
};

const Set<String> _shellKeywords = <String>{
  'if',
  'then',
  'else',
  'elif',
  'fi',
  'for',
  'while',
  'do',
  'done',
  'case',
  'esac',
  'function',
  'return',
  'export',
  'local',
  'readonly',
  'set',
  'unset',
  'echo',
  'cd',
  'sudo',
  'git',
  'npm',
  'flutter',
  'dart',
  'cargo',
  'make',
};

const Set<String> _sqlKeywords = <String>{
  'select',
  'from',
  'where',
  'insert',
  'into',
  'update',
  'delete',
  'values',
  'create',
  'table',
  'index',
  'drop',
  'alter',
  'join',
  'left',
  'right',
  'inner',
  'outer',
  'on',
  'group',
  'by',
  'order',
  'having',
  'limit',
  'offset',
  'and',
  'or',
  'not',
  'null',
  'primary',
  'key',
  'references',
  'foreign',
  'unique',
  'as',
  'case',
  'when',
  'then',
  'else',
  'end',
  'distinct',
  'union',
  'with',
};

const _LanguageSpec _cLike = _LanguageSpec(
  lineComment: <String>['//'],
  blockComment: ('/*', '*/'),
  keywords: _cLikeKeywords,
);

final Map<String, _LanguageSpec> _specs = <String, _LanguageSpec>{
  'dart': _cLike,
  'js': _cLike,
  'javascript': _cLike,
  'jsx': _cLike,
  'ts': _cLike,
  'typescript': _cLike,
  'tsx': _cLike,
  'java': _cLike,
  'kotlin': _cLike,
  'swift': _cLike,
  'c': _cLike,
  'cpp': _cLike,
  'c++': _cLike,
  'cs': _cLike,
  'csharp': _cLike,
  'go': _cLike,
  'golang': _cLike,
  'rust': _cLike,
  'rs': _cLike,
  'php': _cLike,
  'json': const _LanguageSpec(
    lineComment: <String>[],
    blockComment: null,
    keywords: <String>{'true', 'false', 'null'},
  ),
  'python': const _LanguageSpec(
    lineComment: <String>['#'],
    blockComment: null,
    keywords: _pythonKeywords,
  ),
  'py': const _LanguageSpec(
    lineComment: <String>['#'],
    blockComment: null,
    keywords: _pythonKeywords,
  ),
  'yaml': const _LanguageSpec(
    lineComment: <String>['#'],
    blockComment: null,
    keywords: <String>{'true', 'false', 'null', 'yes', 'no'},
  ),
  'yml': const _LanguageSpec(
    lineComment: <String>['#'],
    blockComment: null,
    keywords: <String>{'true', 'false', 'null', 'yes', 'no'},
  ),
  'toml': const _LanguageSpec(
    lineComment: <String>['#'],
    blockComment: null,
    keywords: <String>{'true', 'false'},
  ),
  'ini': const _LanguageSpec(
    lineComment: <String>[';', '#'],
    blockComment: null,
    keywords: <String>{},
  ),
  'sh': const _LanguageSpec(
    lineComment: <String>['#'],
    blockComment: null,
    keywords: _shellKeywords,
  ),
  'bash': const _LanguageSpec(
    lineComment: <String>['#'],
    blockComment: null,
    keywords: _shellKeywords,
  ),
  'zsh': const _LanguageSpec(
    lineComment: <String>['#'],
    blockComment: null,
    keywords: _shellKeywords,
  ),
  'shell': const _LanguageSpec(
    lineComment: <String>['#'],
    blockComment: null,
    keywords: _shellKeywords,
  ),
  'sql': const _LanguageSpec(
    lineComment: <String>['--'],
    blockComment: ('/*', '*/'),
    keywords: _sqlKeywords,
  ),
  'html': const _LanguageSpec(
    lineComment: <String>[],
    blockComment: ('<!--', '-->'),
    keywords: <String>{},
  ),
  'xml': const _LanguageSpec(
    lineComment: <String>[],
    blockComment: ('<!--', '-->'),
    keywords: <String>{},
  ),
  'css': const _LanguageSpec(
    lineComment: <String>[],
    blockComment: ('/*', '*/'),
    keywords: <String>{},
  ),
};

/// 这个语言标识是否会被着色。
///
/// 界面据此显示「纯文本」而不是语言名，避免出现「标着 dart 却一点颜色都没有」的
/// 自相矛盾：未识别时我们明确说这是纯文本，而不是假装认出了语言。
bool isHighlightableLanguage(String? language) {
  if (language == null) {
    return false;
  }
  return _specs.containsKey(language.toLowerCase());
}

/// 把代码切成带类别的片段。
///
/// [language] 为 null 或不在已知集合里时，整段作为一个 [HighlightKind.plain] 片段返回
/// ——这与架构的「未知语言按纯文本显示」是同一个决定，也让调用方不必自己分支。
List<HighlightSpan> highlightCode(String code, String? language) {
  final _LanguageSpec? spec = language == null
      ? null
      : _specs[language.toLowerCase()];
  if (spec == null || code.isEmpty) {
    return <HighlightSpan>[HighlightSpan(code, HighlightKind.plain)];
  }
  return _tokenize(code, spec);
}

List<HighlightSpan> _tokenize(String code, _LanguageSpec spec) {
  final List<HighlightSpan> out = <HighlightSpan>[];
  final StringBuffer plain = StringBuffer();

  void flushPlain() {
    if (plain.isNotEmpty) {
      out.add(HighlightSpan(plain.toString(), HighlightKind.plain));
      plain.clear();
    }
  }

  int i = 0;
  while (i < code.length) {
    // 1) 块注释（必须在行注释之前判定：`/*` 比 `//` 长，但两者首字符不同，顺序其实
    //    无关紧要；这里先判块注释是为了让代码读起来与语法的「最大匹配」一致）。
    final (String, String)? block = spec.blockComment;
    if (block != null && code.startsWith(block.$1, i)) {
      final int closeAt = code.indexOf(block.$2, i + block.$1.length);
      final int end = closeAt == -1 ? code.length : closeAt + block.$2.length;
      flushPlain();
      out.add(HighlightSpan(code.substring(i, end), HighlightKind.comment));
      i = end;
      continue;
    }

    // 2) 行注释。
    final String line = spec.lineComment.firstWhere(
      (String marker) => code.startsWith(marker, i),
      orElse: () => '',
    );
    if (line.isNotEmpty) {
      final int newline = code.indexOf('\n', i);
      final int end = newline == -1 ? code.length : newline;
      flushPlain();
      out.add(HighlightSpan(code.substring(i, end), HighlightKind.comment));
      i = end;
      continue;
    }

    final String ch = code[i];

    // 3) 字符串（含引号；支持转义）。
    if (ch == '"' || ch == "'" || ch == '`') {
      final int end = _stringEnd(code, i, ch);
      flushPlain();
      out.add(HighlightSpan(code.substring(i, end), HighlightKind.string));
      i = end;
      continue;
    }

    // 4) 数字（含十六进制、小数、下划线分隔与常见后缀）。
    if (_isDigitChar(ch)) {
      int j = i;
      while (j < code.length && _isNumberChar(code[j])) {
        j++;
      }
      flushPlain();
      out.add(HighlightSpan(code.substring(i, j), HighlightKind.number));
      i = j;
      continue;
    }

    // 5) 标识符 / 关键字 / 类型。
    if (_isIdentStart(ch)) {
      int j = i;
      while (j < code.length && _isIdentChar(code[j])) {
        j++;
      }
      final String word = code.substring(i, j);
      final HighlightKind? kind = _classify(word, spec);
      if (kind == null) {
        plain.write(word);
      } else {
        flushPlain();
        out.add(HighlightSpan(word, kind));
      }
      i = j;
      continue;
    }

    plain.write(ch);
    i++;
  }
  flushPlain();
  return out;
}

/// 识别一个词：关键字、或「像类型」的标识符（首字母大写且不是关键字）。
HighlightKind? _classify(String word, _LanguageSpec spec) {
  final String lower = word.toLowerCase();
  if (spec.keywords.contains(word) || spec.keywords.contains(lower)) {
    return HighlightKind.keyword;
  }
  // 首字母大写且长度 > 1 的标识符按类型着色。这是**词法**级判断，不声称它真的是类型
  // （可能是一个常量名）——但它足够稳定，且不会让读者误以为某个词是关键字。
  final String first = word[0];
  if (word.length > 1 &&
      first == first.toUpperCase() &&
      first != lower[0].toUpperCase()) {
    return HighlightKind.type;
  }
  if (word.length > 1 && first == first.toUpperCase() && _isLetter(first)) {
    return HighlightKind.type;
  }
  return null;
}

/// 字符串片段结束位置（不含引号的下一处引号之后）。
int _stringEnd(String code, int start, String quote) {
  int i = start + 1;
  while (i < code.length) {
    final String ch = code[i];
    if (ch == '\\' && i + 1 < code.length) {
      i += 2;
      continue;
    }
    if (ch == quote) {
      return i + 1;
    }
    if (ch == '\n' && quote != '`') {
      // 未闭合的单/双引号字符串：在行尾收住，不吞掉后面的代码。
      return i;
    }
    i++;
  }
  return code.length;
}

bool _isDigitChar(String ch) {
  final int code = ch.codeUnitAt(0);
  return code >= 0x30 && code <= 0x39;
}

bool _isNumberChar(String ch) {
  if (_isDigitChar(ch)) {
    return true;
  }
  final int code = ch.codeUnitAt(0);
  // a-f/A-F：十六进制；x/X/b/o：进制前缀；. _ + -：小数/分隔/指数符号。
  return (code >= 0x61 && code <= 0x66) ||
      (code >= 0x41 && code <= 0x46) ||
      ch == 'x' ||
      ch == 'X' ||
      ch == 'b' ||
      ch == 'o' ||
      ch == '.' ||
      ch == '_' ||
      ch == '+' ||
      ch == '-';
}

bool _isLetter(String ch) {
  final int code = ch.codeUnitAt(0);
  return (code >= 0x41 && code <= 0x5a) || (code >= 0x61 && code <= 0x7a);
}

bool _isIdentStart(String ch) {
  // 注意这里的 $ 必须写成转义形式：Dart 的字符串插值会把裸的美元号当成占位符起始。
  return _isLetter(ch) || ch == '_' || ch == r'$';
}

bool _isIdentChar(String ch) {
  return _isIdentStart(ch) || _isDigitChar(ch);
}
