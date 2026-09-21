// T036：新闻来源配置、组合 prompt 与版本化（SET-050–055、架构 4.4）。
//
// 这一组用例盯的是四件「界面与文档都承诺过」的事：
//   1) **固定协议段不可删**：组合与高级覆盖两条路径都必须带上它；
//   2) **必访站不静默消失**：组合结果里逐站可见，高级覆盖模式下缺了哪几个要能说出来；
//   3) **两个禁词列表独立**：查询禁词只影响「发什么查询」，主题排除只影响「prompt 里写什么」；
//   4) **版本保存与回退**：每次保存新增一版，旧版仍在列表里。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:flux/core/core.dart';
import 'package:flux/features/news/application/news_source_config.dart';

NewsRequiredSite site(String name, String url, {bool enabled = true}) =>
    NewsRequiredSite(name: name, url: url, enabled: enabled, sortOrder: 0);

void main() {
  group('组合 prompt（SET-055 的自动组合）', () {
    test('四段齐全：任务 → 来源 → 规范 → 固定协议', () {
      final ComposedNewsPrompt composed = composeNewsPrompt(
        const NewsPromptInput(language: NewsPromptLanguage.chinese),
      );
      expect(composed.text, contains('生成今天的新闻摘要'));
      expect(composed.taskSection.trim(), isNotEmpty);
      expect(composed.specSection.trim(), isNotEmpty);
      expect(composed.citationSection, kNewsCitationProtocolZh);
      expect(composed.text.endsWith(kNewsCitationProtocolZh), isTrue);
      expect(
        composed.text.indexOf(composed.specSection),
        lessThan(composed.text.indexOf(composed.citationSection)),
      );
    });

    test('必访站逐站出现在组合结果里（架构 4.4 的「逐站」）', () {
      final ComposedNewsPrompt composed = composeNewsPrompt(
        const NewsPromptInput(
          language: NewsPromptLanguage.chinese,
          requiredSites: <NewsRequiredSite>[
            NewsRequiredSite(name: '甲站', url: 'https://a.example.com'),
            NewsRequiredSite(name: '乙站', url: 'https://b.example.com'),
          ],
        ),
      );
      expect(composed.listsRequiredSites, isTrue);
      expect(composed.requiredSiteLines, hasLength(2));
      expect(composed.text, contains('https://a.example.com'));
      expect(composed.text, contains('https://b.example.com'));
      expect(composed.text, contains('甲站'));
    });

    test('停用的必访站不进 prompt（也不参与逐站执行）', () {
      final ComposedNewsPrompt composed = composeNewsPrompt(
        NewsPromptInput(
          language: NewsPromptLanguage.chinese,
          requiredSites: <NewsRequiredSite>[
            site('启用站', 'https://on.example.com'),
            site('停用站', 'https://off.example.com', enabled: false),
          ],
        ),
      );
      expect(composed.text, contains('https://on.example.com'));
      expect(composed.text, isNot(contains('https://off.example.com')));
      expect(composed.requiredSiteLines, hasLength(1));
    });

    test('没有必访站时明确说明，而不是留一段空白', () {
      final ComposedNewsPrompt composed = composeNewsPrompt(
        const NewsPromptInput(language: NewsPromptLanguage.chinese),
      );
      expect(composed.sourcesSection, contains('没有配置必访问网站'));
    });

    test('必访站按顺序权重排列（顺序稳定）', () {
      final ComposedNewsPrompt composed = composeNewsPrompt(
        const NewsPromptInput(
          language: NewsPromptLanguage.chinese,
          requiredSites: <NewsRequiredSite>[
            NewsRequiredSite(
              name: '后',
              url: 'https://2.example.com',
              sortOrder: 2,
            ),
            NewsRequiredSite(
              name: '前',
              url: 'https://1.example.com',
              sortOrder: 1,
            ),
          ],
        ),
      );
      expect(
        composed.requiredSiteLines.first,
        contains('https://1.example.com'),
      );
    });

    test('英文模板独立（中英各一套，互不混用）', () {
      final ComposedNewsPrompt composed = composeNewsPrompt(
        const NewsPromptInput(language: NewsPromptLanguage.english),
      );
      expect(composed.citationSection, kNewsCitationProtocolEn);
      expect(composed.text, isNot(contains('引用规则')));
    });
  });

  group('固定协议段不可删（SET-054）', () {
    test('用户改了任务与规范，协议段仍在', () {
      final ComposedNewsPrompt composed = composeNewsPrompt(
        const NewsPromptInput(
          language: NewsPromptLanguage.chinese,
          taskInstruction: '随便写点什么。',
          outputSpec: '只要一行。',
        ),
      );
      expect(composed.text, contains('随便写点什么。'));
      expect(composed.text, contains('只要一行。'));
      expect(composed.text, contains(kNewsCitationProtocolZh));
    });

    test('用户可改部分写满「不要引用」也不影响固定段（两段是不同字符串）', () {
      final ComposedNewsPrompt composed = composeNewsPrompt(
        const NewsPromptInput(
          language: NewsPromptLanguage.chinese,
          outputSpec: '不要写任何方括号引用。',
        ),
      );
      expect(composed.text, contains('不要写任何方括号引用。'));
      expect(composed.text, contains(kNewsCitationProtocolZh));
    });

    test('高级覆盖模式也带协议段（两种模式在此汇合）', () {
      final String prompt = resolveNewsPrompt(
        mode: NewsPromptMode.advancedOverride,
        input: const NewsPromptInput(language: NewsPromptLanguage.chinese),
        advancedPrompt: '只写三句话。',
      );
      expect(prompt, startsWith('只写三句话。'));
      expect(prompt, contains(kNewsCitationProtocolZh));
    });

    test('高级覆盖但内容为空时回退到组合结果（不发一个只剩协议的 prompt）', () {
      final String prompt = resolveNewsPrompt(
        mode: NewsPromptMode.advancedOverride,
        input: const NewsPromptInput(language: NewsPromptLanguage.chinese),
        advancedPrompt: '   ',
      );
      expect(prompt, contains('生成今天的新闻摘要'));
    });

    test('恢复默认：内置模板不含协议段（避免两处维护同一段文本）', () {
      expect(
        builtInOutputSpec(NewsPromptLanguage.chinese),
        isNot(contains(kNewsCitationProtocolZh)),
      );
      final ComposedNewsPrompt composed = composeNewsPrompt(
        NewsPromptInput(
          language: NewsPromptLanguage.chinese,
          outputSpec: builtInOutputSpec(NewsPromptLanguage.chinese),
        ),
      );
      expect(composed.text, contains(kNewsCitationProtocolZh));
    });
  });

  group('必访任务不静默消失（架构 4.4 的差异预览）', () {
    test('高级 prompt 里缺了必访站时逐个报出来', () {
      final NewsPromptDiff diff = newsPromptDiff(
        advancedPrompt: '先看甲站（https://a.example.com），再总结。',
        requiredSites: <NewsRequiredSite>[
          site('甲站', 'https://a.example.com'),
          site('乙站', 'https://b.example.com'),
          site('丙站', 'https://c.example.com'),
        ],
      );
      expect(diff.hasWarning, isTrue);
      expect(
        diff.missingSites.map((NewsRequiredSite s) => s.name).toList(),
        <String>['乙站', '丙站'],
      );
    });

    test('按站名提到也算（不要求用户照抄地址）', () {
      final NewsPromptDiff diff = newsPromptDiff(
        advancedPrompt: '先看甲站与乙站，再总结。',
        requiredSites: <NewsRequiredSite>[
          site('甲站', 'https://a.example.com'),
          site('乙站', 'https://b.example.com'),
        ],
      );
      expect(diff.missingSites, isEmpty);
      expect(diff.hasWarning, isFalse);
    });

    test('停用的必访站不参与差异检查（它本就不该在 prompt 里）', () {
      final NewsPromptDiff diff = newsPromptDiff(
        advancedPrompt: '随便写。',
        requiredSites: <NewsRequiredSite>[
          site('停用站', 'https://off.example.com', enabled: false),
        ],
      );
      expect(diff.missingSites, isEmpty);
    });

    test('差异检查会指出协议标志是否还在', () {
      expect(
        newsPromptDiff(
          advancedPrompt: '结论后面写 [sourceId]。',
          requiredSites: const <NewsRequiredSite>[],
        ).hasCitationProtocol,
        isTrue,
      );
      expect(
        newsPromptDiff(
          advancedPrompt: '不要写引用。',
          requiredSites: const <NewsRequiredSite>[],
        ).hasCitationProtocol,
        isFalse,
      );
    });

    test('状态对象在组合模式下不报差异（没有覆盖就没什么可差）', () {
      const NewsConfigState state = NewsConfigState(
        globalEnabled: true,
        requiredSites: <NewsRequiredSite>[
          NewsRequiredSite(name: '甲站', url: 'https://a.example.com'),
        ],
        keywords: <String>[],
        blockedQueryTerms: <String>[],
        excludedTopics: <String>[],
        mode: NewsPromptMode.composed,
        taskInstruction: '',
        outputSpec: '',
        advancedPrompt: '',
        versions: <NewsPromptVersion>[],
      );
      expect(state.diff.hasWarning, isFalse);
      expect(state.resolvedPrompt, contains('https://a.example.com'));
      expect(state.resolvedPrompt, contains(kNewsCitationProtocolZh));
    });
  });

  group('查询禁词与主题排除是两个独立列表（SET-053）', () {
    test('查询禁词挡住发送，按包含匹配', () {
      final List<String> queries = buildNewsSearchQueries(
        keywords: <String>['股市行情', 'AI 芯片', '天气'],
        blockedQueryTerms: <String>['股市'],
      );
      expect(queries, <String>['AI 芯片', '天气']);
    });

    test('主题排除不出现在查询里，只出现在 prompt 文本里', () {
      final List<String> queries = buildNewsSearchQueries(
        keywords: <String>['AI 芯片'],
      );
      expect(queries, <String>['AI 芯片']);
      expect(newsExcludedTopicsSection(<String>['娱乐八卦']), contains('娱乐八卦'));
    });

    test('改一个列表不影响另一个（两个独立入口）', () {
      expect(newsExcludedTopicsSection(<String>['体育']), contains('体育'));
      final List<String> queries = buildNewsSearchQueries(
        keywords: <String>['体育新闻'],
      );
      expect(queries, <String>['体育新闻'], reason: '主题排除不得影响实际发送的查询（架构 4.4）');
    });

    test('空主题列表不产出那一段（不留一句空话）', () {
      expect(newsExcludedTopicsSection(const <String>[]), isEmpty);
      expect(newsExcludedTopicsSection(<String>['  ']), isEmpty);
    });

    test('派生查询与关键词合并、去重、限数', () {
      final List<String> queries = buildNewsSearchQueries(
        keywords: <String>['甲'],
        derivedQueries: <String>['甲', '乙', '丙'],
        maxQueries: 2,
      );
      expect(queries, <String>['甲', '乙']);
    });

    test('禁词只挡自己那一类：另一个列表的词不会误伤', () {
      final List<String> queries = buildNewsSearchQueries(
        keywords: <String>['娱乐生成'],
        blockedQueryTerms: <String>['股市'],
      );
      expect(queries, <String>['娱乐生成']);
    });

    test('关键词与禁词都写进来源段（用户能看到实际生效的规则）', () {
      final ComposedNewsPrompt composed = composeNewsPrompt(
        const NewsPromptInput(
          language: NewsPromptLanguage.chinese,
          keywords: <String>['AI 芯片'],
          blockedQueryTerms: <String>['股市'],
          excludedTopics: <String>['娱乐'],
        ),
      );
      expect(composed.sourcesSection, contains('AI 芯片'));
      expect(composed.sourcesSection, contains('股市'));
      expect(composed.sourcesSection, contains('娱乐'));
    });
  });

  group('逐源新闻开关的生效值（SET-050）', () {
    test('未设置时跟随订阅启用状态（「已启用订阅默认开」）', () {
      expect(newsIncludesFeed(newsEnabled: null, feedEnabled: true), isTrue);
      expect(newsIncludesFeed(newsEnabled: null, feedEnabled: false), isFalse);
    });

    test('显式设置覆盖跟随（可只排除新闻而保留订阅刷新）', () {
      expect(newsIncludesFeed(newsEnabled: false, feedEnabled: true), isFalse);
      expect(newsIncludesFeed(newsEnabled: true, feedEnabled: false), isTrue);
    });
  });

  group('版本化与回退（SET-055）', () {
    NewsPromptVersion versionWith(int number) => NewsPromptVersion(
      version: number,
      mode: NewsPromptMode.composed,
      taskInstruction: 'a',
      outputSpec: 'b',
      advancedPrompt: '',
      createdAt: DateTime.utc(2026, 9, 22),
    );

    test('下一版号 = 现有最大值 + 1', () {
      expect(nextNewsPromptVersion(const <NewsPromptVersion>[]), 1);
      expect(
        nextNewsPromptVersion(<NewsPromptVersion>[
          versionWith(1),
          versionWith(5),
        ]),
        6,
      );
    });

    test('新版本插到最前（列表按版本号倒序，最新是当前配置）', () {
      final List<NewsPromptVersion> updated =
          NewsSourceConfigService.withVersion(<NewsPromptVersion>[
            versionWith(1),
          ], versionWith(2));
      expect(updated.first.version, 2);
      expect(updated, hasLength(2), reason: '旧版本仍在列表里（可回退）');
    });

    test('模式与语言由稳定标识还原；未知值不猜', () {
      expect(NewsPromptMode.fromCode('composed'), NewsPromptMode.composed);
      expect(
        NewsPromptMode.fromCode('advancedOverride'),
        NewsPromptMode.advancedOverride,
      );
      expect(NewsPromptMode.fromCode('somethingElse'), isNull);
      expect(NewsPromptLanguage.fromCode('en'), NewsPromptLanguage.english);
      expect(NewsPromptLanguage.fromCode('fr'), isNull);
    });
  });

  group('状态对象的解析（界面展示与实际请求用同一份）', () {
    test('组合模式下 resolvedPrompt 就是组合结果', () {
      const NewsConfigState state = NewsConfigState(
        globalEnabled: true,
        requiredSites: <NewsRequiredSite>[],
        keywords: <String>['AI'],
        blockedQueryTerms: <String>[],
        excludedTopics: <String>[],
        mode: NewsPromptMode.composed,
        taskInstruction: '',
        outputSpec: '',
        advancedPrompt: '这段不该被用',
        versions: <NewsPromptVersion>[],
      );
      expect(state.resolvedPrompt, state.composed.text);
      expect(state.resolvedPrompt, isNot(contains('这段不该被用')));
    });

    test('高级模式下 resolvedPrompt = 用户文本 + 协议段', () {
      const NewsConfigState state = NewsConfigState(
        globalEnabled: true,
        requiredSites: <NewsRequiredSite>[],
        keywords: <String>[],
        blockedQueryTerms: <String>[],
        excludedTopics: <String>[],
        mode: NewsPromptMode.advancedOverride,
        taskInstruction: '',
        outputSpec: '',
        advancedPrompt: '只写标题。',
        versions: <NewsPromptVersion>[],
      );
      expect(state.resolvedPrompt, contains('只写标题。'));
      expect(state.resolvedPrompt, contains(kNewsCitationProtocolZh));
    });

    test('effectiveQueries 反映禁词过滤（界面显示的就是实际会发的）', () {
      const NewsConfigState state = NewsConfigState(
        globalEnabled: true,
        requiredSites: <NewsRequiredSite>[],
        keywords: <String>['股市', 'AI'],
        blockedQueryTerms: <String>['股市'],
        excludedTopics: <String>[],
        mode: NewsPromptMode.composed,
        taskInstruction: '',
        outputSpec: '',
        advancedPrompt: '',
        versions: <NewsPromptVersion>[],
      );
      expect(state.effectiveQueries, <String>['AI']);
    });
  });
}
