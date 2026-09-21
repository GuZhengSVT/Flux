// 正文渲染 golden（T019：混排/数学/代码，浅色为主，混排另加深色）。
//
// 为什么值得入库：正文渲染的回归大多是「一眼看不出但确实错」的东西——标题层级挤在一起、
// 代码块底色与正文底色分不开、公式回退提示没有边框、表格边框丢失。golden 把整屏钉住，
// token 与排版回归会以像素差异暴露。
//
// 测试环境不加载系统字体，因此这里显式注册 CJK、等宽、Material 图标与 KaTeX 字族（与
// T004 原型同一套做法）：不注册的话中文与代码全都渲染成方框，golden 就证明不了任何东西。
//
// 更新方式：flutter test --update-goldens test/features/articles/golden/article_reader_golden_test.dart
// 更新前必须人工确认截图符合架构第 7 节，而不是「跑一下让它变成绿的」。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flux/features/articles/domain/markdown_to_document.dart';
import 'package:flux/features/articles/presentation/reader/doc_renderer.dart';
import 'package:flux/features/articles/presentation/reader/doc_theme.dart';

import '../../../app/test_harness.dart';

/// 三引号围栏的转义写法：Dart 的三引号字面量里嵌不下三引号，因此用转义码拼。
const String _fence =
    '\u0060'
    '\u0060'
    '\u0060';

/// golden 用的 CJK 字族名（必须与下面 _loadFonts 里注册的名字一致）。
const String kGoldenFontFamily = 'PingFang SC';

/// 系统里带 CJK 字形的字体，按偏好顺序。
const List<String> _cjkCandidates = <String>[
  '/System/Library/Fonts/Supplemental/Arial Unicode.ttf',
  '/System/Library/Fonts/PingFang.ttc',
  '/System/Library/Fonts/Hiragino Sans GB.ttc',
];

/// 等宽字体（CJK 字体追加在后面，见 doc_theme 的说明）。
const List<String> _monoCandidates = <String>[
  '/System/Library/Fonts/SFNSMono.ttf',
  '/System/Library/Fonts/Menlo.ttc',
];

/// KaTeX 字体文件 → 字族。
const Map<String, String> _katexFontFiles = <String, String>{
  'KaTeX_Main-Regular.ttf': 'KaTeX_Main',
  'KaTeX_Main-Italic.ttf': 'KaTeX_Main',
  'KaTeX_Math-Italic.ttf': 'KaTeX_Math',
  'KaTeX_AMS-Regular.ttf': 'KaTeX_AMS',
  'KaTeX_Size1-Regular.ttf': 'KaTeX_Size1',
  'KaTeX_Size2-Regular.ttf': 'KaTeX_Size2',
  'KaTeX_Size3-Regular.ttf': 'KaTeX_Size3',
  'KaTeX_Size4-Regular.ttf': 'KaTeX_Size4',
};

Future<void> _register(String family, List<File> files) async {
  final FontLoader loader = FontLoader(family);
  for (final File file in files) {
    loader.addFont(
      file.readAsBytes().then(
        (List<int> bytes) => Uint8List.fromList(bytes).buffer.asByteData(),
      ),
    );
  }
  await loader.load();
}

Directory? _findMathPackageRoot() {
  for (final String candidate in <String>[
    '.dart_tool/package_config.json',
    '../.dart_tool/package_config.json',
  ]) {
    final File file = File(candidate);
    if (!file.existsSync()) {
      continue;
    }
    final Object? decoded = jsonDecode(file.readAsStringSync());
    if (decoded is! Map<String, Object?>) {
      continue;
    }
    final Object? packages = decoded['packages'];
    if (packages is! List) {
      continue;
    }
    for (final Object? entry in packages) {
      if (entry is! Map<String, Object?>) {
        continue;
      }
      if (entry['name'] != 'flutter_math_fork') {
        continue;
      }
      final Object? rootUri = entry['rootUri'];
      if (rootUri is! String) {
        continue;
      }
      return Directory.fromUri(Uri.parse(rootUri));
    }
  }
  return null;
}

String? _materialIconsPath() {
  final String? flutterRoot = Platform.environment['FLUTTER_ROOT'];
  const String relative =
      '/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf';
  for (final String base in <String>[
    ?flutterRoot,
    '/opt/homebrew/share/flutter',
  ]) {
    final String path = base + relative;
    if (File(path).existsSync()) {
      return path;
    }
  }
  return null;
}

/// 注册 CJK、等宽、Material 图标与 KaTeX 字族。
Future<void> _loadFonts() async {
  String? cjkPath;
  for (final String path in _cjkCandidates) {
    if (!File(path).existsSync()) {
      continue;
    }
    await _register(kGoldenFontFamily, <File>[File(path)]);
    cjkPath = path;
    break;
  }
  if (cjkPath == null) {
    fail('缺少 CJK 字体；查找过：${_cjkCandidates.join(', ')}');
  }
  final String? icons = _materialIconsPath();
  if (icons != null) {
    await _register('MaterialIcons', <File>[File(icons)]);
  }
  for (final String path in _monoCandidates) {
    if (!File(path).existsSync()) {
      continue;
    }
    await _register('Menlo', <File>[File(path), File(cjkPath)]);
    break;
  }
  final Directory? root = _findMathPackageRoot();
  if (root == null) {
    return;
  }
  final Directory fontDir = Directory('${root.path}/lib/katex_fonts/fonts');
  if (!fontDir.existsSync()) {
    return;
  }
  final Map<String, List<File>> byFamily = <String, List<File>>{};
  for (final MapEntry<String, String> entry in _katexFontFiles.entries) {
    final File file = File('${fontDir.path}/${entry.key}');
    if (!file.existsSync()) {
      continue;
    }
    byFamily.putIfAbsent(entry.value, () => <File>[]).add(file);
  }
  for (final MapEntry<String, List<File>> entry in byFamily.entries) {
    await _register('packages/flutter_math_fork/${entry.key}', entry.value);
  }
}

/// 把行列表拼成 Markdown（每行一个 '\n'）。
///
/// 用拼接而不是三引号：fixture 里含三引号围栏与美元号，直接内嵌会让字面量提前结束、
/// 或让 Dart 把美元号当成插值起始。拼接把这两类字符都留在普通字符串里。
String _doc(List<String> lines) => lines.join('\n');

/// 混排 fixture：标题层级、中文段落、强调、引用、列表、表格、行内代码。
final String kMixed = _doc(<String>[
  '# 混合排版的示例',
  '',
  '这是一段中文正文，中间夹着 **加粗** 与 *斜体*，还有 '
      '\u0060inline_code()\u0060。',
  '',
  '## 二级标题',
  '',
  '> 引用块里的一句话，用来检查左侧强调边与其底色的对比。',
  '',
  '- 第一项',
  '- 第二项',
  '',
  '| 列 | 值 |',
  '| --- | --- |',
  '| 中文 | 128 |',
  '| English | 256 |',
]);

/// 数学 fixture：常用语法与一个不支持的命令（回退路径必须可见）。
final String kMath = _doc(<String>[
  '公式排版：',
  '',
  r'行内公式 $E = mc^2$，分数 $\frac{a}{b}$，根式 $\sqrt{x}$。',
  '',
  r'$$\sum_{i=1}^{n} i \quad \int_0^1 x\,dx$$',
  '',
  '矩阵：',
  '',
  r'$$\begin{matrix}a & b \\ c & d\end{matrix}$$',
  '',
  r'不支持的命令：$\thiscommanddoesnotexist{abc}$',
]);

/// 代码 fixture：已知语言（着色）、未知语言（纯文本）。
final String kCode = _doc(<String>[
  '代码块：',
  '',
  '\u0060\u0060\u0060dart',
  '/// 计算阶乘。',
  'int factorial(int n) {',
  '  if (n <= 1) return 1;',
  '  return n * factorial(n - 1);',
  '}',
  _fence,
  '',
  '未知语言按纯文本：',
  '',
  '\u0060\u0060\u0060notalanguage',
  'some text without highlighting',
  _fence,
]);

void main() {
  setUpAll(_loadFonts);

  Future<void> snap(
    WidgetTester tester,
    String markdown, {
    required Size size,
    Brightness brightness = Brightness.light,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      wrapFluxApp(
        // 把已注册的 CJK 字族同时写进 DefaultTextStyle **与** textTheme：生产主题依赖
        // 系统字体回退，而测试环境没有系统回退，不显式指定的话中文会渲染成方框（那样
        // golden 证明不了混排排版）。两处都要改——正文与公式读默认样式，而按钮一类的
        // 控件文本来自 textTheme，只改前者会让「复制代码」这类标签仍是方框。
        child: Builder(
          builder: (BuildContext context) {
            final ThemeData base = Theme.of(context);
            return Theme(
              data: base.copyWith(
                textTheme: base.textTheme.apply(fontFamily: kGoldenFontFamily),
              ),
              child: DefaultTextStyle.merge(
                style: const TextStyle(fontFamily: kGoldenFontFamily),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: DocDocumentView(
                    document: parseMarkdownToDocument(markdown),
                    typography: DocTypography(
                      baseSize: 18,
                      theme: brightness == Brightness.dark
                          ? DocTheme.dark
                          : DocTheme.light,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        overrides: TestBootstrap().overrides(),
        localeOverride: const Locale('zh'),
        themeMode: brightness == Brightness.dark
            ? ThemeMode.dark
            : ThemeMode.light,
        platformBrightness: brightness,
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('混排（浅色）', (WidgetTester tester) async {
    await snap(tester, kMixed, size: const Size(900, 1000));
    await expectLater(
      find.byType(DocDocumentView),
      matchesGoldenFile('article_mixed_light.png'),
    );
  });

  testWidgets('数学（浅色）', (WidgetTester tester) async {
    await snap(tester, kMath, size: const Size(900, 1000));
    await expectLater(
      find.byType(DocDocumentView),
      matchesGoldenFile('article_math_light.png'),
    );
  });

  testWidgets('代码（浅色）', (WidgetTester tester) async {
    await snap(tester, kCode, size: const Size(900, 900));
    await expectLater(
      find.byType(DocDocumentView),
      matchesGoldenFile('article_code_light.png'),
    );
  });

  testWidgets('混排（深色）', (WidgetTester tester) async {
    await snap(
      tester,
      kMixed,
      size: const Size(900, 1000),
      brightness: Brightness.dark,
    );
    await expectLater(
      find.byType(DocDocumentView),
      matchesGoldenFile('article_mixed_dark.png'),
    );
  });
}
