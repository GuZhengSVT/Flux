// 全文拼接与选区上下文（T020）的**纯 Dart** 口径。
//
// 这些规则是数据出境与「读者拿到什么」的边界，不是界面细节，因此用纯 Dart 断言：
//   - 复制全文压平成什么形态（标题/段落/列表/代码/表格/图片/公式各自如何）；
//   - 「选词解释」只带最少上下文，且截断处有明确标记。
//
// 把这两条放在这里，T034 接真实 AI 调用时用的是**同一份**实现，不会重新写一套截断规则。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:flux/core/core.dart';
import 'package:flux/features/articles/application/article_text_actions.dart';
import 'package:flux/features/articles/domain/markdown_to_document.dart';

/// 解析一段 Markdown 得到文档（与阅读路径同一个解析器）。
DocDocument parse(String markdown) => parseMarkdownToDocument(markdown);

void main() {
  group('复制全文的纯文本口径', () {
    test('段落之间是空行（粘贴到笔记里就是段落）', () {
      final String text = articlePlainText(parse('第一段。\n\n第二段。'));
      expect(text, '第一段。\n\n第二段。');
    });

    test('标题与列表项各自成段，列表项之间是单换行', () {
      final String text = articlePlainText(parse('# 标题\n\n- 甲\n- 乙\n\n有序收尾。'));
      expect(text, contains('标题'));
      expect(text, contains('甲\n乙'));
      expect(text, contains('有序收尾。'));
      // 标题与列表之间是空行（块级分隔）。
      expect(text, contains('标题\n\n甲\n乙'));
    });

    test('代码块原文照抄（读者复制全文常常正是为了那段代码）', () {
      final String text = articlePlainText(
        // 用拼接而不是三引号：Dart 的三引号字面量里嵌不下三引号（与 article_reader_test
        // 的 kDartFence 同一做法）。
        parse(
          '说明。\n\n'
          '\u0060\u0060\u0060dart\nfinal x = 1;\n\u0060\u0060\u0060',
        ),
      );
      expect(text, contains('final x = 1;'));
      // 不带上围栏标记：复制的目的是拿到代码本身。
      expect(text, isNot(contains('dart\nfinal')));
    });

    test('表格按行压平，单元格用竖线分隔', () {
      final String text = articlePlainText(
        parse('| 甲 | 乙 |\n| --- | --- |\n| 1 | 2 |'),
      );
      expect(text, contains('甲 | 乙'));
      expect(text, contains('1 | 2'));
    });

    test('图片不产出替代文字（复制正文是为了拿文字）', () {
      final String text = articlePlainText(
        parse('正文。\n\n![一张图的说明](https://example.com/a.png)'),
      );
      expect(text, '正文。');
      expect(text, isNot(contains('一张图的说明')));
    });

    test('公式保留 TeX 原文而不是丢掉', () {
      final String text = articlePlainText(parse(r'公式 $E = mc^2$ 在这里。'));
      expect(text, contains(r'E = mc^2'));
    });

    test('空文档得到空串（调用方据此说「没有可复制的内容」）', () {
      expect(articlePlainText(parse('')), isEmpty);
    });

    test('引用块内的段落被压平，不丢内容', () {
      final String text = articlePlainText(parse('> 引用的一句话。\n\n正文。'));
      expect(text, contains('引用的一句话。'));
      expect(text, contains('正文。'));
    });
  });

  group('选词解释的最少上下文', () {
    test('选区两侧各取一半配额，并在截断处标注省略号', () {
      final String plain = '${"甲" * 3000}目标词汇${"乙" * 3000}';
      final SelectionExplanationRequest request =
          SelectionExplanationRequest.fromDocument(
            plainText: plain,
            selection: '目标词汇',
            maxContextCharacters: 100,
          );

      expect(request.selection, '目标词汇');
      // 两侧各 50 字。
      expect(request.contextBefore.length, 51, reason: '50 字 + 一个省略号');
      expect(request.contextAfter.length, 51);
      expect(request.contextBefore, startsWith('…'));
      expect(request.contextAfter, endsWith('…'));
      // 出发的文本确实只带最少上下文，而不是整篇。
      expect(request.payload.length, lessThan(plain.length));
      expect(request.payload, contains('目标词汇'));
    });

    test('上下文不超出正文边界时不加省略号（不假装被截断）', () {
      final SelectionExplanationRequest request =
          SelectionExplanationRequest.fromDocument(
            plainText: '前面一小段。目标词汇后面一小段。',
            selection: '目标词汇',
            maxContextCharacters: 1200,
          );
      expect(request.contextBefore, '前面一小段。');
      expect(request.contextAfter, '后面一小段。');
      expect(request.payload, '前面一小段。目标词汇后面一小段。');
    });

    test('选区在正文里找不到时不猜位置（宁可没有上下文）', () {
      final SelectionExplanationRequest request =
          SelectionExplanationRequest.fromDocument(
            plainText: '完全不相干的正文。',
            selection: '别处的词',
            maxContextCharacters: 100,
          );
      expect(request.selection, '别处的词');
      expect(request.contextBefore, isEmpty);
      expect(request.contextAfter, isEmpty);
      expect(request.payload, '别处的词', reason: '猜一个位置会把正文另一处的内容当成上下文发出去');
    });

    test('空白选区得到空请求（调用方据此不发请求）', () {
      final SelectionExplanationRequest request =
          SelectionExplanationRequest.fromDocument(
            plainText: '正文。',
            selection: '   ',
          );
      expect(request.selection, isEmpty);
      expect(request.payload, isEmpty);
    });

    test('选区本身**不**被截断（截断会把「解释什么」变成另一个问题）', () {
      final String longSelection = '长' * 500;
      final SelectionExplanationRequest request =
          SelectionExplanationRequest.fromDocument(
            plainText: '前缀。$longSelection后缀。',
            selection: longSelection,
            maxContextCharacters: 20,
          );
      expect(request.selection.length, 500);
    });
  });
}
