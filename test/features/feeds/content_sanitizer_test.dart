// 正文清洗测试（T013；架构 4.2 与第 8 节）。
//
// 安全断言分三类，缺一不可：
//   1) **绝不出现**：脚本、事件属性、iframe/form 等内容不得以任何形式出现在产物里
//      （不是「变成文本」也不行——脚本源码出现在正文里同样是失败）；
//   2) **必须拒绝但可见**：javascript: 等危险 URL 变成 DocRejectedUrl，读者能看到
//      原文想链接到哪里，但渲染层不会把它交给启动器；
//   3) **必须保留**：允许的标签与文本一个都不能丢。第 3 类最容易被忽略——只测「危险
//      的被挡住了」会让实现趋向「宁可多丢」，而正文丢内容对阅读器是致命缺陷。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:flux/core/core.dart';
import 'package:flux/features/feeds/domain/content_sanitizer.dart';

/// 产物中所有可见文字（用于「不得出现」类断言）。
String _visibleText(SanitizerReport report) =>
    docDocumentPlainText(report.document.children);

/// 产物中所有被拒绝的 URL。
List<DocRejectedUrl> _rejected(SanitizerReport report) =>
    collectDocInlines(report.document).whereType<DocRejectedUrl>().toList();

void main() {
  group('白名单与结构（必须保留）', () {
    test('标题、段落、强调、链接、列表、引用、代码、表格都被保留', () {
      final SanitizerReport report = sanitizeHtmlToDocument(
        '<h2>标题</h2>'
        '<p>正文 <em>斜体</em> <strong>粗体</strong> '
        '<a href="https://example.com/x">链接</a></p>'
        '<blockquote><p>引用</p></blockquote>'
        '<ul><li>一</li><li>二</li></ul>'
        '<ol start="3"><li>三</li></ol>'
        '<pre><code class="language-dart">final x = 1;</code></pre>'
        '<table><tr><th>表头</th></tr><tr><td>数据</td></tr></table>'
        '<hr>',
      );

      final List<DocNode> nodes = report.document.children;
      expect(nodes.whereType<DocHeading>(), hasLength(1));
      expect(nodes.whereType<DocHeading>().first.level, 2);
      expect(nodes.whereType<DocParagraph>(), hasLength(1));
      expect(nodes.whereType<DocBlockQuote>(), hasLength(1));
      expect(nodes.whereType<DocList>(), hasLength(2));
      expect(nodes.whereType<DocCodeBlock>(), hasLength(1));
      expect(nodes.whereType<DocTable>(), hasLength(1));
      expect(nodes.whereType<DocThematicBreak>(), hasLength(1));

      final DocList ordered = nodes.whereType<DocList>().firstWhere(
        (DocList l) => l.ordered,
      );
      expect(ordered.start, 3, reason: 'ol start 必须保留');
      expect(ordered.items, hasLength(1));

      final DocCodeBlock code = nodes.whereType<DocCodeBlock>().single;
      expect(code.code, 'final x = 1;');
      expect(code.language, 'dart');

      final DocTable table = nodes.whereType<DocTable>().single;
      expect(table.header, hasLength(1));
      expect(table.rows, hasLength(1));

      // 行内强调与链接确实成了对应节点，而不是被压成纯文字。
      final List<DocInline> inlines = collectDocInlines(report.document);
      expect(inlines.whereType<DocEmphasis>(), hasLength(1));
      expect(inlines.whereType<DocStrong>(), hasLength(1));
      final DocLinkInline link = inlines.whereType<DocLinkInline>().single;
      expect(link.url, 'https://example.com/x');
      expect(docInlinePlainText(link.children), '链接');
      expect(report.rejectedUrls, 0);
    });

    test('图片：安全 URL 保留为 DocImageInline 并带 alt', () {
      final SanitizerReport report = sanitizeHtmlToDocument(
        '<p><img src="https://example.com/a.png" alt="示意图"></p>',
      );
      final DocImageInline image = collectDocInlines(report.document)
          .whereType<DocImageInline>()
          .single;
      expect(image.url, 'https://example.com/a.png');
      expect(image.alt, '示意图');
    });

    test('裸行内内容被聚成段落（不丢文字）', () {
      // 真实源里 <div>裸文字<a>x</a></div> 极常见；直接丢弃等于丢正文。
      final SanitizerReport report = sanitizeHtmlToDocument(
        '<div>开头文字<a href="https://example.com">链接文字</a>结尾文字</div>',
      );
      final List<DocNode> nodes = report.document.children;
      expect(nodes, hasLength(1));
      expect(nodes.single, isA<DocParagraph>());
      final String text = _visibleText(report);
      expect(text, contains('开头文字'));
      expect(text, contains('链接文字'));
      expect(text, contains('结尾文字'));
    });

    test('未知标签拆掉外壳但保留文字（不整段丢弃）', () {
      final SanitizerReport report = sanitizeHtmlToDocument(
        '<p>前<custom-tag>未知标签里的文字</custom-tag>后</p>'
        '<x-unknown-block><p>未知块里的段落</p></x-unknown-block>',
      );
      final String text = _visibleText(report);
      expect(text, contains('未知标签里的文字'));
      expect(text, contains('未知块里的段落'));
    });

    test('未闭合标签被宽容闭合（仍产出完整内容）', () {
      // 这是「为什么不用严格 XML 解析」的直接证据：这段不是合法 XML。
      final SanitizerReport report = sanitizeHtmlToDocument(
        '<p>第一段<br>换行后<p>第二段<b>加粗',
      );
      final String text = _visibleText(report);
      expect(text, contains('第一段'));
      expect(text, contains('换行后'));
      expect(text, contains('第二段'));
      expect(text, contains('加粗'));
      expect(report.hitDepthLimit, isFalse);
    });

    test('实体被解码，且影响阅读与安全的实体收全', () {
      final SanitizerReport report = sanitizeHtmlToDocument(
        '<p>AT&amp;T 3 &lt; 5 &quot;引号&quot; &#65;&#x42; &mdash; &nbsp;结束</p>',
      );
      final String text = _visibleText(report);
      expect(text, contains('AT&T'));
      expect(text, contains('3 < 5'));
      expect(text, contains('"引号"'));
      expect(text, contains('AB'), reason: '十进制与十六进制实体都要解码');
      expect(text, contains('—'));
    });

    test('裸 & 与未收录实体退化可读文本，不破坏其它内容', () {
      final SanitizerReport report = sanitizeHtmlToDocument(
        '<p>A & B 与 &unknownentity; 以及 &amp;</p>',
      );
      final String text = _visibleText(report);
      // 裸 '&' 原样保留（含空格，避免把 "AT&T" 里的字符吃掉）。
      expect(text, contains('A & B'));
      // 未收录的实体退化成**字面文本**（含分号），这样读者能看出原文写了什么；
      // 收录的实体正常解码。两者必须同时成立。
      expect(text, contains('&unknownentity;'));
      expect(text, contains('以及 &'));
      expect(text, isNot(contains('&amp;')));
    });

    test('CDATA 内容按文本处理（这是它存在的意义）', () {
      final SanitizerReport report = sanitizeHtmlToDocument(
        '<p><![CDATA[<b>这里不是标签</b>]]></p>',
      );
      final String text = _visibleText(report);
      expect(text, contains('<b>这里不是标签</b>'));
      expect(
        collectDocInlines(report.document).whereType<DocStrong>(),
        isEmpty,
        reason: 'CDATA 里的内容不得被解释成标记',
      );
    });

    test('pre 内的空白与标签文字按字面保留（代码块语义）', () {
      final SanitizerReport report = sanitizeHtmlToDocument(
        '<pre>line1\n  indented\n<b>keep</b></pre>',
      );
      final DocCodeBlock code = report.document.children
          .whereType<DocCodeBlock>()
          .single;
      expect(code.code, 'line1\n  indented\nkeep');
    });
  });

  group('危险内容必须被拒绝或丢弃', () {
    test('script/style/iframe/form 连同内容一起丢弃（不得以文本形式残留）', () {
      final SanitizerReport report = sanitizeHtmlToDocument(
        '<p>正文</p>'
        '<script>var secret = "alert(1)";</script>'
        '<style>.x { color: red; }</style>'
        '<iframe src="https://evil.example.com"></iframe>'
        '<form action="https://evil.example.com"><input name="a"></form>'
        '<noscript>noscript 内容</noscript>',
      );
      final String text = _visibleText(report);
      expect(text, contains('正文'));
      // 关键是**脚本源码与标签本身不能出现在产物里**，而不是「变成文本后可见」。
      for (final String forbidden in <String>[
        'alert(1)',
        'var secret',
        'color: red',
        '<script',
        '<iframe',
        'evil.example.com',
        'noscript 内容',
      ]) {
        expect(
          text.contains(forbidden),
          isFalse,
          reason: '丢弃类标签的内容泄漏到正文：$forbidden',
        );
      }
      expect(
        report.droppedBlocks,
        containsAll(<String>['script', 'style', 'iframe', 'form', 'noscript']),
      );
      expect(report.isLossy, isTrue);
    });

    test('嵌套的同名丢弃标签仍然配对（不会提前恢复正文）', () {
      final SanitizerReport report = sanitizeHtmlToDocument(
        '<p>前</p><script>a<script>b</script>c</script><p>后</p>',
      );
      final String text = _visibleText(report);
      expect(text, contains('前'));
      expect(text, contains('后'));
      expect(text, isNot(contains('c')), reason: '嵌套丢弃区间内的内容不得泄漏');
    });

    test('事件属性被丢弃（不会随标签保留）', () {
      final SanitizerReport report = sanitizeHtmlToDocument(
        '<p onclick="alert(1)">文字</p>'
        '<img src="https://example.com/a.png" onerror="alert(2)" alt="x">'
        '<a href="https://example.com" onmouseover="alert(3)">链接</a>',
      );
      // 属性是否保留通过节点本身验证：产物里只有白名单字段，事件属性无处存放。
      final DocImageInline image = collectDocInlines(report.document)
          .whereType<DocImageInline>()
          .single;
      expect(image.url, 'https://example.com/a.png');
      final DocLinkInline link = collectDocInlines(report.document)
          .whereType<DocLinkInline>()
          .single;
      expect(link.url, 'https://example.com');
      expect(_visibleText(report), isNot(contains('alert(')));
    });

    test('javascript:/data:/vbscript:/file: 链接被拒绝但保持可见', () {
      for (final String url in <String>[
        'javascript:alert(1)',
        'JavaScript:alert(1)',
        'data:text/html;base64,PHNjcmlwdD4=',
        'vbscript:msgbox',
        'file:///etc/passwd',
      ]) {
        final SanitizerReport report = sanitizeHtmlToDocument(
          '<p><a href="$url">点我</a></p>',
        );
        final List<DocLinkInline> links = collectDocInlines(report.document)
            .whereType<DocLinkInline>()
            .toList();
        expect(links, isEmpty, reason: '危险协议不得成为可点链接：$url');
        final List<DocRejectedUrl> rejected = _rejected(report);
        expect(rejected, hasLength(1), reason: '必须留下可见的拒绝记录：$url');
        expect(rejected.single.label, '点我', reason: '链接文字必须保留，读者要知道原文指向什么');
        expect(report.rejectedUrls, 1);
      }
    });

    test('相对地址与无协议地址被拒绝（没有可信 base URL 时不猜）', () {
      for (final String url in <String>[
        '/path/to/page',
        'page.html',
        '#anchor',
        '//example.com/x',
      ]) {
        final SanitizerReport report = sanitizeHtmlToDocument(
          '<p><a href="$url">文字</a></p>',
        );
        expect(
          collectDocInlines(report.document).whereType<DocLinkInline>(),
          isEmpty,
          reason: '$url 不应成为可点链接',
        );
        expect(_rejected(report), hasLength(1));
      }
    });

    test('危险协议的图片同样被拒绝且不可加载', () {
      final SanitizerReport report = sanitizeHtmlToDocument(
        '<p><img src="javascript:alert(1)" alt="坏图"></p>'
        '<p><img src="data:image/png;base64,AAAA" alt="内嵌图"></p>',
      );
      expect(
        collectDocInlines(report.document).whereType<DocImageInline>(),
        isEmpty,
      );
      expect(_rejected(report), hasLength(2));
      expect(_rejected(report).first.label, '坏图');
    });

    test('HTML 注释与 DOCTYPE 被丢弃', () {
      final SanitizerReport report = sanitizeHtmlToDocument(
        '<!DOCTYPE html><!-- 注释内容 --><p>正文</p>',
      );
      expect(_visibleText(report), contains('正文'));
      expect(_visibleText(report), isNot(contains('注释内容')));
    });

    test('实体编码的控制字符与方向控制符被丢弃（不能用于伪装文本）', () {
      final SanitizerReport report = sanitizeHtmlToDocument(
        '<p>a&#0;b&#x202E;c&#xFEFF;d&#x200B;e</p>',
      );
      final String text = _visibleText(report);
      // 这些码点会破坏显示顺序或注入不可见字符，必须不出现。
      expect(text.contains('\u0000'), isFalse);
      expect(text.contains('\u202E'), isFalse);
      expect(text.contains('\uFEFF'), isFalse);
      expect(text.contains('\u200B'), isFalse);
      // 正常字符仍然连在一起。
      expect(text.replaceAll(RegExp(r'\s'), ''), 'abcde');
    });

    test('同名属性只保留第一个（后写的覆盖值不生效）', () {
      final SanitizerReport report = sanitizeHtmlToDocument(
        '<p><a href="https://safe.example.com" '
        'href="javascript:alert(1)">文字</a></p>',
      );
      final DocLinkInline link = collectDocInlines(report.document)
          .whereType<DocLinkInline>()
          .single;
      expect(link.url, 'https://safe.example.com');
      expect(report.rejectedUrls, 0);
    });
  });

  group('上限与诊断', () {
    test('输入超长被截断并标记（不是拒绝整篇）', () {
      final String long = '<p>${'a' * 500}</p>';
      final SanitizerReport report = sanitizeHtmlToDocument(
        long,
        limits: const SanitizerLimits(maxInputLength: 100),
      );
      expect(report.truncated, isTrue);
      expect(report.isLossy, isTrue);
      expect(_visibleText(report), isNotEmpty);
    });

    test('节点数超限被标记（正文可能不完整）', () {
      final StringBuffer buffer = StringBuffer();
      for (int i = 0; i < 200; i++) {
        buffer.write('<p>段落 $i</p>');
      }
      final SanitizerReport report = sanitizeHtmlToDocument(
        buffer.toString(),
        limits: const SanitizerLimits(maxNodes: 20),
      );
      expect(report.hitNodeLimit, isTrue);
      expect(report.document.children.length, lessThan(200));
      expect(report.isLossy, isTrue);
    });

    test('深度超限被标记，且不会无限递归', () {
      final String deep = '${'<div>' * 200}文字${'</div>' * 200}';
      final SanitizerReport report = sanitizeHtmlToDocument(
        deep,
        limits: const SanitizerLimits(maxDepth: 16),
      );
      expect(report.hitDepthLimit, isTrue);
      expect(report.isLossy, isTrue);
    });

    test('空输入与纯空白返回空文档，且不算有损失', () {
      for (final String? input in <String?>[null, '', '   ']) {
        final SanitizerReport report = sanitizeHtmlToDocument(input);
        expect(report.document.isEmpty, isTrue);
        expect(report.isLossy, isFalse);
      }
    });

    test('纯文本输入（无标签）被当作一个段落', () {
      final SanitizerReport report = sanitizeHtmlToDocument('就是一段文字');
      expect(report.document.children, hasLength(1));
      expect(_visibleText(report).trim(), '就是一段文字');
    });

    test('畸形输入不会抛异常（孤立尖括号、未闭合引号、孤立结束标签）', () {
      for (final String input in <String>[
        '3 < 5 且 7 > 2',
        '<p class="未闭合>文字</p>',
        '</p>孤立结束标签',
        '<p><<<<>>></p>',
        '<a href=>空值</a>',
        '<img>',
        '<>',
        '< p >不是标签</ p >',
      ]) {
        expect(
          () => sanitizeHtmlToDocument(input),
          returnsNormally,
          reason: '畸形输入不得抛出：$input',
        );
      }
    });

    test('纯文本导出与文档树一致（摘要回退用）', () {
      const String html = '<h1>标题</h1><p>段落一</p><ul><li>项</li></ul>';
      final String plain = sanitizeHtmlToPlainText(html);
      expect(plain, contains('标题'));
      expect(plain, contains('段落一'));
      expect(plain, contains('项'));
    });
  });

  group('URL 白名单函数（独立于清洗流程）', () {
    test('允许 http/https/mailto 绝对地址', () {
      for (final String url in <String>[
        'http://example.com',
        'https://example.com/path?q=1#frag',
        'mailto:someone@example.com',
      ]) {
        expect(isSafeDocUrl(url), isTrue, reason: url);
      }
    });

    test('拒绝危险协议、相对地址与怪异形态', () {
      for (final String url in <String>[
        'javascript:alert(1)',
        'JAVASCRIPT:alert(1)',
        'data:text/html,x',
        'file:///x',
        'about:blank',
        'chrome://settings',
        'blob:https://x/y',
        '/relative',
        'relative/path',
        '',
        '   ',
        'ftp://example.com',
      ]) {
        expect(isSafeDocUrl(url), isFalse, reason: url);
      }
    });

    test('路径中的冒号不被误判为协议（"a/b:c" 不是协议）', () {
      expect(isSafeDocUrl('https://example.com/a/b:c'), isTrue);
      expect(isSafeDocUrl('path/to:x'), isFalse);
    });
  });
}
