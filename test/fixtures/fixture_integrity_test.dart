// 夹具完整性测试（T008）。
//
// 目的不是“测夹具”，而是保证共享夹具不会在后续任务里被悄悄改坏：
// 一旦 fixture 变得非法/退化，消费它的解析测试会以更难定位的方式失败，
// 不如在这里先给出明确的失败信息。
//
// 这里只用 Dart 标准库做结构级校验，不引入 XML/JSON Schema 依赖（T007 边界：
// 不新增第三方依赖）。真正的语义解析测试由 T013/T026 用各自适配器完成。

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const String _fixtureDir = 'test/fixtures';

String _read(String name) => File('$_fixtureDir/$name').readAsStringSync();

void main() {
  group('夹具存在且非空', () {
    test('T008 要求的夹具文件全部存在', () {
      for (final String name in <String>[
        'README.md',
        'rss_sample.rss2.xml',
        'rss_sample.atom.xml',
        'rss_sample.atom_xhtml.xml',
        'opml_sample.opml',
        'markdown_math_sample.md',
        'fake_ai_response.json',
        'fake_ai_tool_call_response.json',
      ]) {
        final File file = File('$_fixtureDir/$name');
        expect(file.existsSync(), isTrue, reason: '缺少夹具 $name');
        expect(file.lengthSync(), greaterThan(32), reason: '$name 过小');
      }
    });

    test('夹具不含 BOM，避免解析器把首字符当成内容', () {
      for (final FileSystemEntity entity in Directory(_fixtureDir).listSync()) {
        if (entity is! File) {
          continue;
        }
        final List<int> bytes = entity.readAsBytesSync();
        if (bytes.length >= 3 &&
            bytes[0] == 0xEF &&
            bytes[1] == 0xBB &&
            bytes[2] == 0xBF) {
          fail('${entity.path} 含 UTF-8 BOM');
        }
      }
    });

    test('夹具不引用真实域名或真实凭据（只用保留域名）', () {
      // 只允许 example.com / example.org / nested.example.com / w3.org / purl.org 等。
      const List<String> allowedHosts = <String>[
        'example.com',
        'example.org',
        'nested.example.com',
        'www.w3.org',
        'w3.org',
        'purl.org',
      ];
      final RegExp host = RegExp(r'https?://([A-Za-z0-9.-]+)');
      for (final FileSystemEntity entity in Directory(_fixtureDir).listSync()) {
        if (entity is! File || entity.path.endsWith('README.md')) {
          continue;
        }
        for (final RegExpMatch match in host.allMatches(
          entity.readAsStringSync(),
        )) {
          final String name = match.group(1)!.toLowerCase();
          expect(
            allowedHosts.contains(name),
            isTrue,
            reason: '${entity.path} 引用了非保留域名 $name',
          );
        }
      }
    });
  });

  group('JSON 夹具', () {
    test('fake_ai_response.json 是合法 JSON 且含 chat.completion 结构', () {
      final Object? decoded = jsonDecode(_read('fake_ai_response.json'));
      expect(decoded, isA<Map<String, Object?>>());
      final Map<String, Object?> body = decoded! as Map<String, Object?>;

      expect(body['object'], 'chat.completion');
      expect(body['id'], isA<String>());
      expect(body['model'], isA<String>());
      expect(body['created'], isA<int>());

      final List<Object?> choices = body['choices']! as List<Object?>;
      expect(choices, hasLength(1));
      final Map<String, Object?> choice =
          choices.first! as Map<String, Object?>;
      expect(choice['index'], 0);
      expect(choice['finish_reason'], 'stop');
      final Map<String, Object?> message =
          choice['message']! as Map<String, Object?>;
      expect(message['role'], 'assistant');
      expect(message['content'], isA<String>());
      expect(message['content'], isNotEmpty);
    });

    test('fake_ai_response.json 的 usage 明细可支撑预算核算', () {
      final Map<String, Object?> body =
          jsonDecode(_read('fake_ai_response.json')) as Map<String, Object?>;
      final Map<String, Object?> usage = body['usage']! as Map<String, Object?>;

      final int prompt = usage['prompt_tokens']! as int;
      final int completion = usage['completion_tokens']! as int;
      final int total = usage['total_tokens']! as int;
      expect(prompt, greaterThan(0));
      expect(completion, greaterThan(0));
      // 不变量：total = prompt + completion（SET-063 的消耗统计依赖此恒等）。
      expect(total, prompt + completion);
      expect(usage['prompt_tokens_details'], isA<Map<String, Object?>>());
      expect(usage['completion_tokens_details'], isA<Map<String, Object?>>());
    });

    test('fake_ai_tool_call_response.json 含两个工具的合法参数 JSON', () {
      final Map<String, Object?> body = jsonDecode(
        _read('fake_ai_tool_call_response.json'),
      ) as Map<String, Object?>;
      final Map<String, Object?> choice =
          (body['choices']! as List<Object?>).first! as Map<String, Object?>;
      expect(choice['finish_reason'], 'tool_calls');

      final Map<String, Object?> message =
          choice['message']! as Map<String, Object?>;
      expect(message['content'], isNull, reason: '工具调用轮 content 允许为 null');

      final List<Object?> calls = message['tool_calls']! as List<Object?>;
      expect(calls, hasLength(2));
      final List<String> names = <String>[];
      for (final Object? call in calls) {
        final Map<String, Object?> entry = call! as Map<String, Object?>;
        expect(entry['type'], 'function');
        expect(entry['id'], startsWith('call_'));
        final Map<String, Object?> function =
            entry['function']! as Map<String, Object?>;
        names.add(function['name']! as String);
        // arguments 是字符串，内容必须是可解析的 JSON（真实协议如此）。
        final Object? args = jsonDecode(function['arguments']! as String);
        expect(args, isA<Map<String, Object?>>());
      }
      expect(names, <String>['search', 'fetchPage']);
    });
  });

  group('XML 夹具', () {
    test('RSS 2.0 样本结构完整', () {
      final String xml = _read('rss_sample.rss2.xml');
      expect(xml, startsWith('<?xml version="1.0"'));
      expect(xml, contains('<rss version="2.0"'));
      expect(xml, contains('<channel>'));
      expect(xml, contains('</channel>'));
      expect('<rss'.allMatches(xml).length, 1);
      // 三个 item 覆盖：有 GUID、无 GUID（走规范化链接兜底）、无 pubDate。
      expect('<item>'.allMatches(xml).length, 3);
      expect('</item>'.allMatches(xml).length, 3);
      expect(xml, contains('<guid isPermaLink="false">'));
      expect(xml, contains('content:encoded'));
      // URL 查询参数被保留，用于验证“不随意剥离参数”。
      expect(xml, contains('utm_source=fixture'));
    });

    test('Atom 样本结构完整且含 rel 变体', () {
      final String xml = _read('rss_sample.atom.xml');
      expect(xml, contains('<feed xmlns="http://www.w3.org/2005/Atom"'));
      expect('</feed>'.allMatches(xml).length, 1);
      expect('<entry>'.allMatches(xml).length, 2);
      expect('</entry>'.allMatches(xml).length, 2);
      expect(xml, contains('rel="self"'));
      expect(xml, contains('rel="alternate"'));
      // 两种 content 类型都覆盖。
      expect(xml, contains('type="html"'));
      expect(xml, contains('type="text"'));
    });

    test('Atom XHTML 样本含 type="xhtml" 与 src-only content', () {
      final String xml = _read('rss_sample.atom_xhtml.xml');
      expect(xml, contains('type="xhtml"'));
      expect(xml, contains('xmlns="http://www.w3.org/1999/xhtml"'));
      expect(xml, contains('src="https://example.com/xhtml/two/body.html"'));
    });

    test('XML 夹具的标签成对（粗粒度检查，防止手改后结构破损）', () {
      for (final String name in <String>[
        'rss_sample.rss2.xml',
        'rss_sample.atom.xml',
        'rss_sample.atom_xhtml.xml',
        'opml_sample.opml',
      ]) {
        final String xml = _read(name);
        final RegExp open = RegExp(
          r'<([a-zA-Z][A-Za-z0-9:_\-]*)(?:\s[^>]*?)?>',
        );
        final RegExp close = RegExp(r'</([a-zA-Z][A-Za-z0-9:_\-]*)\s*>');
        final Map<String, int> opened = <String, int>{};
        for (final RegExpMatch match in open.allMatches(xml)) {
          opened.update(match.group(1)!, (int v) => v + 1, ifAbsent: () => 1);
        }
        for (final RegExpMatch match in close.allMatches(xml)) {
          final String tag = match.group(1)!;
          opened.update(tag, (int v) => v - 1, ifAbsent: () => -1);
        }
        // 自闭合标签不会出现在 close 里，因此只断言“没有多余的结束标签”。
        opened.forEach((String tag, int balance) {
          expect(
            balance,
            greaterThanOrEqualTo(0),
            reason: '$name 中 <$tag> 结束标签过多',
          );
        });
      }
    });

    test('OPML 样本含分组嵌套、重复地址与故意无效项', () {
      final String xml = _read('opml_sample.opml');
      expect(xml, contains('<opml version="2.0">'));
      expect(xml, contains('<body>'));
      // 嵌套分组：Tech -> Nested Group。
      expect(xml, contains('<outline text="Nested Group"'));
      // 重复订阅地址：用于验证“重复导入匹配已有源”。
      expect(
        'xmlUrl="https://example.com/feed.xml"'.allMatches(xml).length,
        2,
        reason: '应包含两条相同地址，用于重复项处理测试',
      );
      // 无效项：只有 text 没有 xmlUrl。
      expect(
        xml,
        contains('<outline text="Missing xmlUrl (invalid on purpose)"'),
      );
      expect(xml, contains('htmlUrl="https://example.com/"'));
    });
  });

  group('Markdown/LaTeX 夹具', () {
    test('覆盖架构 4.2 列出的常用 LaTeX 语法族', () {
      final String md = _read('markdown_math_sample.md');
      // 行内与独立公式定界符。
      expect(md, contains(r'$E = mc^2$'));
      expect(md, contains(r'$$\frac{-b \pm \sqrt{b^2 - 4ac}}{2a}$$'));
      // 上下标。
      expect(md, contains(r'$x_1^2 + x_2^2 = r^2$'));
      // 分数与根式。
      expect(md, contains(r'\frac'));
      expect(md, contains(r'\sqrt'));
      // 求和与积分。
      expect(md, contains(r'\sum_{n=1}^{\infty}'));
      expect(md, contains(r'\int_{0}^{\infty}'));
      // 希腊字母。
      for (final String greek in <String>[
        r'\alpha',
        r'\beta',
        r'\gamma',
        r'\theta',
        r'\lambda',
        r'\pi',
        r'\sigma',
        r'\Omega',
      ]) {
        expect(md, contains(greek), reason: '缺少 $greek');
      }
      // 括号伸缩、矩阵、分段、对齐。
      expect(md, contains(r'\left( \frac{a}{b} \right)^{n}'));
      expect(md, contains(r'\begin{pmatrix}'));
      expect(md, contains(r'\begin{cases}'));
      expect(md, contains(r'\begin{aligned}'));
    });

    test('覆盖渲染边界：货币美元、转义美元、未闭合公式、未知宏', () {
      final String md = _read('markdown_math_sample.md');
      expect(md, contains(r'\$100'), reason: '需要转义美元样本');
      expect(md, contains(r'$19.99'), reason: '需要货币误判样本');
      expect(md, contains(r'$x + y 而没有结束符'), reason: '需要未闭合公式样本');
      expect(md, contains(r'\notacommand'), reason: '需要未知宏回退样本');
    });

    test('覆盖受控文档树的块级结构', () {
      final String md = _read('markdown_math_sample.md');
      expect(md, contains('| 列一 | 列二 | 列三 |'), reason: '需要表格');
      expect(md, contains('```dart'), reason: '需要已知语言代码块');
      expect(md, contains('```text-unknown-language'), reason: '需要未知语言代码块');
      expect(md, contains('> > 二级引用'), reason: '需要嵌套引用');
      expect(md, contains('1. 有序项一'), reason: '需要有序列表');
      expect(md, contains('- 嵌套无序项'), reason: '需要嵌套列表');
    });

    test('覆盖危险内容：脚本、事件属性、javascript 协议必须被拒绝', () {
      final String md = _read('markdown_math_sample.md');
      expect(md, contains('<script>'), reason: '需要脚本样本以验证剥离');
      expect(md, contains('onerror='), reason: '需要事件属性样本');
      expect(md, contains('javascript:alert(1)'), reason: '需要危险协议样本');
    });
  });
}
