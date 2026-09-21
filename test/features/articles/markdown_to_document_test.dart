// Markdown → 受控文档树 与 LaTeX 定界符的解析测试（T019；架构 4.2）。
//
// 覆盖手册点名的必测项（6.3「渲染」）：长中文与中英混排、数学矩阵/对齐、美元货币、
// 不支持语法原样可见。
//
// 美元货币规则来自 T004 的 fixture（原型已固化过同一组边界），本文件把它作为主工程的
// 实现契约重新断言一遍——移植时最容易悄悄改掉的就是这条启发式。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:flux/core/core.dart';
import 'package:flux/features/articles/domain/markdown_math.dart';
import 'package:flux/features/articles/domain/markdown_to_document.dart';
import 'package:flux/features/articles/presentation/reader/doc_math.dart';

/// 厨房水槽 fixture：把块级构造一次给全（用三引号原样书写，避免转义噪音）。
const String _kitchenSink = '''# 一级

段落。

> 引用

- A
- B

1. 一
2. 二

```dart
void main() {}
```

---

| a | b |
| --- | --- |
| 1 | 2 |
''';

void main() {
  group('美元货币与公式定界符', () {
    test('货币金额不被当成公式', () {
      // 三个原型固化过的形态：金额后跟数字、金额前有空格、单独的美元号。
      for (final String text in <String>[r'$100 元', r'$5 到 $10', r'价格 $ 与 $']) {
        expect(
          splitInlineMath(escapeCurrencyDollars(text)),
          isEmpty,
          reason: '不应把货币读成公式：$text',
        );
      }
    });

    test('真正的公式被识别，且 TeX 原样保留', () {
      final List<MathSegment> segments = splitInlineMath(
        r'公式 $x^2$ 与 $5 到 $10',
      );
      expect(segments, hasLength(1));
      expect(segments.single.tex, 'x^2');
    });

    test('未闭合的美元号不跨行配对', () {
      final List<MathSegment> segments = splitInlineMath('第一段有 \$x\n第二段也有 \$y');
      expect(segments, isEmpty, reason: '跨行配对会把两段之间的全部内容吞进公式里');
    });

    test('独占公式先于行内公式处理', () {
      final ProtectedDocument protected = protectMath('\$\$a=b\$\$');
      expect(protected.math, <String>['a=b']);
      expect(protected.markdown, mathSentinel(0));
    });

    test('多行独占公式（矩阵/对齐环境）整体保留', () {
      final ProtectedDocument protected = protectMath(
        '前文\n\$\$\n\\begin{aligned}\na &= b \\\\\nc &= d\n\\end{aligned}\n\$\$\n后文',
      );
      expect(protected.math, hasLength(1));
      expect(protected.math.single, contains(r'\begin{aligned}'));
      expect(
        protected.math.single,
        contains(r'\\'),
        reason: '换行符必须保留：矩阵与对齐环境靠它分行',
      );
    });

    test('货币转义后再解析：正文里出现的是金额原文', () {
      final DocDocument doc = parseMarkdownToDocument(r'价格是 $100，不是 $200。');
      final String text = docDocumentPlainText(doc.children);
      expect(text, contains('\$100'));
      expect(text, contains('\$200'));
    });
  });

  group('Markdown → 受控文档树', () {
    test('块级构造都对上号（标题/段落/引用/列表/代码/分隔线/表格）', () {
      final DocDocument doc = parseMarkdownToDocument(_kitchenSink);
      final List<Type> kinds = doc.children
          .map((DocNode n) => n.runtimeType)
          .toList();
      expect(kinds, contains(DocHeading));
      expect(kinds, contains(DocParagraph));
      expect(kinds, contains(DocBlockQuote));
      expect(kinds, contains(DocList));
      expect(kinds, contains(DocCodeBlock));
      expect(kinds, contains(DocThematicBreak));
      expect(kinds, contains(DocTable));

      final DocHeading heading = doc.children.first as DocHeading;
      expect(heading.level, 1);
      expect(docInlinePlainText(heading.children), '一级');

      final DocCodeBlock code = doc.children.whereType<DocCodeBlock>().single;
      expect(code.language, 'dart');
      expect(code.code, contains('void main()'));

      final DocList unordered = doc.children.whereType<DocList>().first;
      expect(unordered.ordered, isFalse);
      expect(unordered.items, hasLength(2));
    });

    test('表格列对齐来自分隔行', () {
      final DocDocument doc = parseMarkdownToDocument(
        '| 左 | 中 | 右 |\n| :--- | :---: | ---: |\n| 1 | 2 | 3 |\n',
      );
      final DocTable table = doc.children.whereType<DocTable>().single;
      expect(table.header, hasLength(3));
      expect(table.alignments, <String?>['left', 'center', 'right']);
      expect(table.rows, hasLength(1));
    });

    test('任务列表把勾选状态放在项上', () {
      final DocDocument doc = parseMarkdownToDocument(
        '- [x] 做完的\n- [ ] 没做的\n- 普通项\n',
      );
      final DocList list = doc.children.whereType<DocList>().single;
      expect(list.items, hasLength(3));
      expect(list.items[0].checked, isTrue);
      expect(list.items[1].checked, isFalse);
      expect(list.items[2].checked, isNull, reason: '普通项不该被标成未勾选');
    });

    test('有序列表起始序号被保留', () {
      final DocDocument doc = parseMarkdownToDocument('3. 三\n4. 四\n');
      final DocList list = doc.children.whereType<DocList>().single;
      expect(list.ordered, isTrue);
      expect(list.start, 3);
    });

    test('删除线、强调、加粗、行内代码都是显式节点', () {
      final DocDocument doc = parseMarkdownToDocument('*斜* **粗** ~~删~~ `码`');
      final List<DocInline> inlines = collectDocInlines(doc);
      expect(inlines.whereType<DocEmphasis>(), hasLength(1));
      expect(inlines.whereType<DocStrong>(), hasLength(1));
      expect(inlines.whereType<DocStrikethrough>(), hasLength(1));
      expect(inlines.whereType<DocCodeSpan>(), hasLength(1));
    });

    test('实体文本原样保留，且不会变成标记（不静默丢弃）', () {
      final DocDocument doc = parseMarkdownToDocument('a &amp; b &lt;tag&gt;');
      // 关键是**没有东西消失**，且实体文本没有变成受控节点（那取决于 markdown 包对
      // 实体引用的处理策略，本项目有意不对它做二次加工）。
      final String text = docDocumentPlainText(doc.children);
      expect(text, contains('a '));
      expect(text, contains('b '));
      expect(text, contains('tag'));
      expect(collectDocInlines(doc).whereType<DocLinkInline>(), isEmpty);
    });

    test('长中文与中英混排整段保留（不截断）', () {
      final String long = List<String>.filled(
        40,
        '这是一段很长的中文正文，Mixed with English.',
      ).join();
      final DocDocument doc = parseMarkdownToDocument(long);
      final String text = docDocumentPlainText(doc.children);
      expect(text.length, greaterThanOrEqualTo(long.length - 4));
      expect(text, contains('Mixed with English.'));
    });

    test('原始 HTML 不透传：它至多作为可见文本出现', () {
      final DocDocument doc = parseMarkdownToDocument(
        '前文\n\n<div onclick="boom()">块内容</div>\n\n后文',
      );
      final String text = docDocumentPlainText(doc.children);
      // 原始 HTML 有意不进受控树：它不会变成可点击/可加载节点。
      expect(collectDocInlines(doc).whereType<DocLinkInline>(), isEmpty);
      expect(text, contains('前文'));
      expect(text, contains('后文'));
    });

    test('未知构造保留可见（不静默丢弃）', () {
      final DocDocument doc = parseMarkdownToDocument('==高亮==\n');
      expect(docDocumentPlainText(doc.children), contains('==高亮=='));
    });

    test('危险协议的链接与图片在解析期就被拒绝', () {
      final DocDocument doc = parseMarkdownToDocument(
        '[点我](javascript:alert(1)) ![图](data:image/png;base64,AAAA)',
      );
      final List<DocRejectedUrl> rejected = collectDocInlines(doc)
          .whereType<DocRejectedUrl>()
          .toList();
      expect(rejected, hasLength(2));
      expect(
        collectDocInlines(doc).whereType<DocLinkInline>(),
        isEmpty,
        reason: '危险链接不得进入可点击节点',
      );
      // 仍然可见：读者能看出原文想链接到哪里。
      expect(rejected.first.label, '点我');
    });

    test('http/https/mailto 链接保留为可点击节点', () {
      final DocDocument doc = parseMarkdownToDocument(
        '[a](https://example.com/x?y=1) [b](mailto:x@example.com)',
      );
      final List<DocLinkInline> links = collectDocInlines(doc)
          .whereType<DocLinkInline>()
          .toList();
      expect(links, hasLength(2));
      expect(links.first.url, 'https://example.com/x?y=1', reason: '查询参数不得被剥离');
    });
  });

  group('数学渲染契约（不支持的命令不得空白）', () {
    test('常用语法能被 TeX 解析器接受', () {
      for (final String tex in <String>[
        'x^2',
        r'\frac{a}{b}',
        r'\sqrt{x}',
        r'\sum_{i=1}^{n} i',
        r'\int_0^1 x\,dx',
        r'\alpha + \beta = \gamma',
        r'\left(\frac{a}{b}\right)',
        r'\begin{matrix}a & b \\ c & d\end{matrix}',
      ]) {
        final ({bool ok, String? message}) result = tryParseTex(tex);
        expect(result.ok, isTrue, reason: '应支持 Tex=$tex（${result.message}）');
      }
    });

    test('不支持的语法被识别为失败（界面据此显示原式）', () {
      final ({bool ok, String? message}) result = tryParseTex(
        r'\thiscommanddoesnotexist{abc}',
      );
      expect(result.ok, isFalse);
      expect(result.message, isNotNull);
    });

    test('空公式判为失败', () {
      expect(tryParseTex('   ').ok, isFalse);
    });
  });

  group('纯文本导出（摘要回退、检索与测试断言共用）', () {
    test('公式按 TeX 原样进入纯文本，而不是消失', () {
      final DocDocument doc = parseMarkdownToDocument(r'结果 $E = mc^2$。');
      expect(docDocumentPlainText(doc.children), contains('E = mc^2'));
    });

    test('代码块内容原样进入纯文本', () {
      final DocDocument doc = parseMarkdownToDocument(
        '```\nselect * from t;\n```',
      );
      expect(docDocumentPlainText(doc.children), contains('select * from t;'));
    });
  });
}
