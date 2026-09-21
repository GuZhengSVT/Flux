// T022：检索语义的纯函数判据（计划选择、FTS 短语与 LIKE 转义、高亮与片段截取）。
//
// 这些规则决定了「搜得到什么」，必须在纯 Dart 层逐条钉住：真实库测试覆盖了端到端
// 行为，但边界（1 字、2 字、3 字、含空白、含 % / _ / 引号）用纯函数能穷举完。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:flux/core/core.dart';

void main() {
  group('执行计划选择（实测语义的可执行形式）', () {
    test('空查询返回 null（不检索，也不是匹配全部）', () {
      expect(planSearch(''), isNull);
      expect(planSearch('   '), isNull);
      expect(planSearch('\t\n '), isNull);
    });

    test('1–2 字查询走 LIKE（trigram 索引里没有这么短的项）', () {
      for (final String text in <String>['a', '离', 'ai', 'AI', '离线', 'ab']) {
        final SearchPlan plan = planSearch(text)!;
        expect(plan.mode, SearchMode.like, reason: text);
        expect(plan.likePattern, isNotNull, reason: text);
        expect(plan.matchPhrase, isNull, reason: text);
      }
    });

    test('3 字及以上的连续片段走 MATCH', () {
      for (final String text in <String>['abc', '离线阅', 'offline', '离线阅读的实现']) {
        final SearchPlan plan = planSearch(text)!;
        expect(plan.mode, SearchMode.match, reason: text);
        expect(plan.matchPhrase, isNotNull, reason: text);
        expect(plan.likePattern, isNull, reason: text);
      }
    });

    test('含空白的查询走 LIKE（MATCH 短语会要求片段连续出现，与预期不符）', () {
      for (final String text in <String>['离线 阅读', 'AI 与 离线', 'a b c']) {
        final SearchPlan plan = planSearch(text)!;
        expect(plan.mode, SearchMode.like, reason: text);
      }
    });

    test('空白被归一化（首尾去掉、内部折叠为一个空格）', () {
      expect(planSearch('  离线  ')!.normalized, '离线');
      expect(planSearch('离线   阅读')!.normalized, '离线 阅读');
      expect(planSearch('a\nb')!.normalized, 'a b');
    });
  });

  group('FTS 短语构造（防语法注入）', () {
    test('包成带引号的短语', () {
      expect(ftsPhrase('离线阅'), '"离线阅"');
      expect(ftsPhrase('offline'), '"offline"');
    });

    test('内部引号双写转义（fts5 的规则）', () {
      expect(ftsPhrase('a"b'), '"a""b"');
    });

    test('含 OR / NEAR / 列名语法时不改变查询含义（都按字面量处理）', () {
      for (final String evil in <String>[
        'OR',
        'NEAR',
        'title:foo',
        'a*',
        '^x',
      ]) {
        final String phrase = ftsPhrase(evil);
        expect(phrase.startsWith('"'), isTrue, reason: evil);
        expect(phrase.endsWith('"'), isTrue, reason: evil);
        // 短语内的内容原样保留（只有引号被双写）。
        expect(
          phrase.contains(evil.replaceAll('"', '""')),
          isTrue,
          reason: evil,
        );
      }
    });
  });

  group('LIKE 模式转义', () {
    test('% 与 _ 被转义（否则变成通配符，一次检索返回全库）', () {
      expect(escapeLikePattern('100%'), r'%100\%%');
      expect(escapeLikePattern('a_b'), r'%a\_b%');
    });

    test('反斜杠自身被转义（保证 ESCAPE 语义一致）', () {
      expect(escapeLikePattern(r'C:\temp'), r'%C:\\temp%');
    });

    test('两端加 % 形成子串匹配', () {
      expect(escapeLikePattern('离线'), r'%离线%');
    });

    test('普通文本不被改动', () {
      expect(escapeLikePattern('offline reading'), '%offline reading%');
    });
  });

  group('高亮标记解析', () {
    test('单处命中', () {
      final List<HighlightSegment> segments = parseHighlightMarkers(
        '前\u0001离线阅\u0002后',
      );
      expect(segments, <HighlightSegment>[
        const HighlightSegment(text: '前', isMatch: false),
        const HighlightSegment(text: '离线阅', isMatch: true),
        const HighlightSegment(text: '后', isMatch: false),
      ]);
    });

    test('多处命中', () {
      final List<HighlightSegment> segments = parseHighlightMarkers(
        '\u0001a\u0002 与 \u0001b\u0002',
      );
      expect(segments.where((HighlightSegment s) => s.isMatch).length, 2);
      expect(segments.map((HighlightSegment s) => s.text).join(), 'a 与 b');
    });

    test('无标记时整段为普通文本', () {
      expect(parseHighlightMarkers('纯文本'), <HighlightSegment>[
        const HighlightSegment(text: '纯文本', isMatch: false),
      ]);
    });

    test('未闭合的标记不丢字', () {
      final List<HighlightSegment> segments = parseHighlightMarkers('前\u0001后');
      expect(segments.map((HighlightSegment s) => s.text).join(), '前后');
      expect(segments.any((HighlightSegment s) => s.isMatch), isFalse);
    });

    test('片段拼接等于原文窗口，且 plainText 不含标记', () {
      const String marked = '正文\u0001离线阅\u0002读细节';
      final List<HighlightSegment> segments = parseHighlightMarkers(marked);
      expect(segments.map((HighlightSegment s) => s.text).join(), '正文离线阅读细节');
    });
  });

  group('纯文本高亮（LIKE 路径）', () {
    test('大小写不敏感地高亮所有出现', () {
      final List<HighlightSegment> segments = highlightText('AI 与 ai 都要', 'ai');
      expect(segments.where((HighlightSegment s) => s.isMatch).length, 2);
      // 命中的文本保留**原文**大小写（不是查询词的大小写）。
      expect(
        segments
            .where((HighlightSegment s) => s.isMatch)
            .map((s) => s.text)
            .toList(),
        <String>['AI', 'ai'],
      );
    });

    test('中文子串高亮', () {
      final List<HighlightSegment> segments = highlightText('离线阅读与离线缓存', '离线');
      expect(segments.where((HighlightSegment s) => s.isMatch).length, 2);
    });

    test('无命中时整段为普通文本', () {
      final List<HighlightSegment> segments = highlightText('正文', 'zzz');
      expect(segments.single.isMatch, isFalse);
      expect(segments.single.text, '正文');
    });

    test('空查询原样返回（不高亮任何东西）', () {
      expect(highlightText('正文', '').single.isMatch, isFalse);
      expect(highlightText('正文', '').single.text, '正文');
    });
  });

  group('片段截取（LIKE 路径的 snippet 等价物）', () {
    test('围绕首个命中截取，并如实标出两端省略', () {
      final String body = '${'前缀' * 40}关键词${'后缀' * 40}';
      final SearchSnippet snippet = snippetAround(
        text: body,
        query: '关键词',
        field: SearchField.body,
        contextChars: 10,
      )!;
      expect(snippet.truncatedStart, isTrue);
      expect(snippet.truncatedEnd, isTrue);
      expect(snippet.hasMatch, isTrue);
      expect(snippet.plainText, contains('关键词'));
      // 窗口长度 = 命中前 10 + 命中 3 + 命中后 10。
      expect(snippet.plainText.length, 10 + 3 + 10);
    });

    test('短文本不标省略', () {
      final SearchSnippet snippet = snippetAround(
        text: '含关键词的短句',
        query: '关键词',
        field: SearchField.title,
      )!;
      expect(snippet.truncatedStart, isFalse);
      expect(snippet.truncatedEnd, isFalse);
      expect(snippet.plainText, '含关键词的短句');
    });

    test('命中在开头/结尾时只标一端', () {
      final String body = '关键词${'后' * 50}';
      final SearchSnippet head = snippetAround(
        text: body,
        query: '关键词',
        field: SearchField.body,
        contextChars: 5,
      )!;
      expect(head.truncatedStart, isFalse);
      expect(head.truncatedEnd, isTrue);

      final String tail = '${'前' * 50}关键词';
      final SearchSnippet end = snippetAround(
        text: tail,
        query: '关键词',
        field: SearchField.body,
        contextChars: 5,
      )!;
      expect(end.truncatedStart, isTrue);
      expect(end.truncatedEnd, isFalse);
    });

    test('无命中或空文本返回 null（不伪造片段）', () {
      expect(
        snippetAround(text: '正文', query: 'zzz', field: SearchField.body),
        isNull,
      );
      expect(
        snippetAround(text: '', query: 'x', field: SearchField.body),
        isNull,
      );
      expect(
        snippetAround(text: '正文', query: '', field: SearchField.body),
        isNull,
      );
    });
  });

  group('字段序号（与 fts5 建表列顺序一致）', () {
    test('顺序即 snippet() 的列号，不能随便改', () {
      expect(indexOfField(SearchField.title), 0);
      expect(indexOfField(SearchField.author), 1);
      expect(indexOfField(SearchField.summary), 2);
      expect(indexOfField(SearchField.body), 3);
    });
  });

  group('检索请求校验', () {
    test('合法请求通过', () {
      expect(validateSearchQuery(const SearchQuery(text: 'x')).isOk, isTrue);
    });

    test('limit 为 0 或负数失败（会让结果永久为空且无错误）', () {
      expect(
        validateSearchQuery(const SearchQuery(text: 'x', limit: 0)).isErr,
        isTrue,
      );
      expect(
        validateSearchQuery(const SearchQuery(text: 'x', limit: -1)).isErr,
        isTrue,
      );
    });

    test('负偏移失败', () {
      expect(
        validateSearchQuery(const SearchQuery(text: 'x', offset: -1)).isErr,
        isTrue,
      );
    });
  });

  group('结果页', () {
    test('hasMore 由 total 与 offset 推出（不靠本页长度猜）', () {
      const SearchPage page = SearchPage(
        hits: <SearchHit>[SearchHit(articleId: 1, snippets: <SearchSnippet>[])],
        total: 3,
        offset: 0,
      );
      expect(page.hasMore, isTrue);

      const SearchPage last = SearchPage(
        hits: <SearchHit>[SearchHit(articleId: 1, snippets: <SearchSnippet>[])],
        total: 3,
        offset: 2,
      );
      expect(last.hasMore, isFalse);
    });

    test('换页保留查询与范围', () {
      const SearchQuery query = SearchQuery(
        text: '离线',
        scope: SearchScope.currentFilter,
        filter: ArticleFilter.unread,
        feedId: 7,
      );
      final SearchQuery next = query.atPage(50);
      expect(next.text, '离线');
      expect(next.scope, SearchScope.currentFilter);
      expect(next.filter, ArticleFilter.unread);
      expect(next.feedId, 7);
      expect(next.offset, 50);
    });
  });
}
