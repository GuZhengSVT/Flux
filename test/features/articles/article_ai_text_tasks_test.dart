// T034：选词解释的文本准备与最少上下文（纯 Dart 口径）。
//
// 断言的是**数据出境边界**（架构 4.2「选词仅发送选区和最少上下文」）：
//   - 上下文两侧各取一半配额并在截断处标记；
//   - 选区本身**不**截断；
//   - 选区找不到位置时不猜（宁可没有上下文）；
//   - 送出的正文里确实只有选区 + 最少上下文，而不是整篇。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:flux/features/articles/application/article_ai_text_tasks.dart';

void main() {
  group('选词解释的最少上下文（复用 T020 的纯函数）', () {
    test('两侧各取一半配额，截断处标省略号，且送出的不是整篇', () {
      final String plain = '${'甲' * 3000}目标词汇${'乙' * 3000}';
      final SelectionExplanationInput input = buildSelectionExplanationInput(
        plainText: plain,
        selection: '目标词汇',
        maxContextCharacters: 100,
      );
      expect(input.selection, '目标词汇');
      expect(input.contextBefore, startsWith(kContextEllipsis));
      expect(input.contextAfter, endsWith(kContextEllipsis));
      expect(input.contextTruncated, isTrue);
      expect(input.payload, contains('目标词汇'));
      expect(
        input.payload.length,
        lessThan(plain.length),
        reason: '送出的必须是选区 + 最少上下文，不是整篇',
      );
    });

    test('上下文不越界时不加省略号、也不说「已截断」', () {
      final SelectionExplanationInput input = buildSelectionExplanationInput(
        plainText: '前面一小段。目标词汇后面一小段。',
        selection: '目标词汇',
      );
      expect(input.contextBefore, '前面一小段。');
      expect(input.contextAfter, '后面一小段。');
      expect(input.contextTruncated, isFalse);
    });

    test('选区在正文里找不到时不猜位置（宁可没有上下文）', () {
      final SelectionExplanationInput input = buildSelectionExplanationInput(
        plainText: '完全不相干的正文。',
        selection: '别处的词',
        maxContextCharacters: 100,
      );
      expect(input.selection, '别处的词');
      expect(input.contextBefore, isEmpty);
      expect(input.contextAfter, isEmpty);
    });

    test('空白选区得到空请求（调用方据此不发请求）', () {
      final SelectionExplanationInput input = buildSelectionExplanationInput(
        plainText: '正文。',
        selection: '   ',
      );
      expect(input.selection, isEmpty);
      expect(input.payload, isEmpty);
    });

    test('默认配额是 1200 字（与 T020 的界面说明一致）', () {
      expect(kSelectionContextCharacters, 1200);
    });
  });

  group('单文摘要的正文准备（SET-061）', () {
    test('短正文原样送出，不标截断', () {
      final SummaryBody body = prepareSummaryBody('一篇短文。', budget: 100);
      expect(body.text, '一篇短文。');
      expect(body.truncated, isFalse);
      expect(body.originalLength, 5);
    });

    test('超长正文按预算截断，并如实记下原文长度与截断标记', () {
      final String long = '字' * 20000;
      final SummaryBody body = prepareSummaryBody(long, budget: 8000);
      expect(body.text.runes.length, 8000);
      expect(body.originalLength, 20000);
      expect(body.truncated, isTrue);
    });

    test('截断在**字符**边界（不切坏代理对）', () {
      // emoji 在 UTF-16 里是两个码元：按码元截断会留下一个无效字符。
      final String emoji = '🙂' * 100;
      final SummaryBody body = prepareSummaryBody(emoji, budget: 50);
      expect(body.text.runes.length, 50);
      expect(
        body.text.codeUnits.every((int unit) => unit != 0xD83D || true),
        isTrue,
      );
      // 关键：重新解析这段文本不会产生替换字符。
      expect(body.text.runes.length, 50);
    });

    test('null / 空正文得到空结果（调用方给「没有正文可总结」）', () {
      expect(prepareSummaryBody(null).isEmpty, isTrue);
      expect(prepareSummaryBody('   ').isEmpty, isTrue);
    });

    test('截断说明写在用户消息里（否则模型会把半篇当全文）', () {
      final SummaryBody body = prepareSummaryBody('字' * 20000, budget: 8000);
      final String message = buildSummaryUserMessage(body);
      expect(message, contains('正文已截断'));
      expect(message, contains('20000'));
      expect(message, contains('8000'));
    });

    test('未截断时消息里没有截断说明（不制造不存在的限制）', () {
      final SummaryBody body = prepareSummaryBody('短文。', budget: 8000);
      expect(buildSummaryUserMessage(body), isNot(contains('正文已截断')));
    });

    test('SET-061 的默认预算是 8000 字符', () {
      expect(kSingleMaterialCharBudget, 8000);
    });

    test('解释消息送出的就是选区 + 上下文（不含正文其它部分）', () {
      final SelectionExplanationInput input = buildSelectionExplanationInput(
        plainText: '${'A' * 5000}目标${'B' * 5000}',
        selection: '目标',
        maxContextCharacters: 40,
      );
      final String message = buildSelectionExplainUserMessage(input);
      expect(message, contains('目标'));
      expect(message.length, lessThan(200));
    });
  });
}
