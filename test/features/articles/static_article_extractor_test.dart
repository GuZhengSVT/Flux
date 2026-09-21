// T024：静态网页正文抽取（fixture HTML，离线）。
//
// 覆盖验收条件点名的四类页面与三条边界：
//   * 正常文章：抽到标题、正文、图片引用；噪音区块（script/nav/aside/footer）不进正文；
//   * JS 站：没有可用正文时归类为 empty（界面提示「可能需要脚本渲染」）；
//   * 付费墙迹象：给出提示但**仍然抽取**（提示 ≠ 阻止）；
//   * 超长/畸形：截断与宽容解析都不产出「看起来成功但其实是垃圾」的结果；
//   * 危险内容：script 内容与 javascript: 链接一律不出现在结果里（清洗器是唯一判据）。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:flux/features/articles/domain/static_article_extractor.dart';

String _fixture(String name) => File('test/fixtures/$name').readAsStringSync();

void main() {
  group('正常文章', () {
    test('抽到标题、正文与图片引用，且正文不含噪音区块', () {
      final StaticExtraction result = extractStaticArticle(
        _fixture('static_page_normal.html'),
      );
      expect(result.outcome, StaticExtractionOutcome.ok);
      expect(result.isUsable, isTrue);
      // 标题取 title 的第一段（去掉「 - 站点名」后缀）。
      expect(result.title, '离线阅读的实现细节');
      // 正文包含文章内容。
      expect(result.text, contains('本地优先的阅读器'));
      expect(result.text, contains('丢弃策略'));
      // 噪音区块的内容不进正文。
      expect(result.text, isNot(contains('should not appear')));
      expect(result.text, isNot(contains('var tracking')));
      expect(result.text, isNot(contains('侧栏推荐')));
      expect(result.text, isNot(contains('版权所有')));
      expect(result.text, isNot(contains('console.log')));
      // 命中的是语义容器。
      expect(result.usedRegion, 'article');
    });

    test('图片引用被记录且**不去下载**（只是地址）', () {
      final StaticExtraction result = extractStaticArticle(
        _fixture('static_page_normal.html'),
      );
      expect(
        result.imageUrls,
        containsAll(<String>[
          'https://cdn.example.com/one.png',
          'https://cdn.example.com/two.png',
        ]),
      );
    });

    test('没有付费墙迹象', () {
      final StaticExtraction result = extractStaticArticle(
        _fixture('static_page_normal.html'),
      );
      expect(result.hasPaywallSignal, isFalse);
    });

    test('链接保留在正文文本里（不静默丢弃）', () {
      final StaticExtraction result = extractStaticArticle(
        _fixture('static_page_normal.html'),
      );
      expect(result.text, contains('规范链接'));
    });
  });

  group('纯 JS 渲染的站点', () {
    test('没有可用正文 → empty，并保持没有正文（不编造内容）', () {
      final StaticExtraction result = extractStaticArticle(
        _fixture('static_page_js_only.html'),
      );
      // 脚本内容不会被执行，因此 `#app` 是空的。
      expect(result.text, isNot(contains('rendered by script only')));
      expect(result.isUsable, isFalse);
      expect(
        result.outcome,
        anyOf(StaticExtractionOutcome.empty, StaticExtractionOutcome.noContent),
      );
    });
  });

  group('付费墙迹象（提示不阻止）', () {
    test('识别 meta 与 class 类迹象', () {
      final StaticExtraction result = extractStaticArticle(
        _fixture('static_page_paywall.html'),
      );
      expect(result.hasPaywallSignal, isTrue);
      expect(
        result.paywallSignals,
        containsAll(<PaywallSignal>[
          PaywallSignal.meta,
          PaywallSignal.className,
        ]),
      );
    });

    test('有付费墙迹象**仍然抽取**可见正文（提示 ≠ 阻止）', () {
      final StaticExtraction result = extractStaticArticle(
        _fixture('static_page_paywall.html'),
      );
      // 试读部分是真实可见的文字，应当被抽出来交给用户判断。
      expect(result.text, contains('本文为订阅专享内容'));
      expect(result.hasPaywallSignal, isTrue);
    });

    test('正文里出现「付费」字样不算迹象（避免误报）', () {
      final StaticExtraction result = extractStaticArticle(
        '<html><head><title>t</title></head><body><article>'
        '<p>本文讨论付费墙的商业模式与它对读者的影响，这一段文字本身并不是付费墙。</p>'
        '<p>${'补充若干文字以超过可用阈值。' * 20}</p>'
        '</article></body></html>',
      );
      expect(
        result.paywallSignals,
        isNot(contains(PaywallSignal.className)),
        reason: '类名只能在标签属性里匹配',
      );
    });
  });

  group('畸形与超长', () {
    test('缺闭合标签的页面仍能抽出正文', () {
      final StaticExtraction result = extractStaticArticle(
        _fixture('static_page_malformed.html'),
      );
      expect(result.text, contains('这段 HTML 没有闭合的标题'));
      expect(result.text, contains('宽容解析的目标'));
    });

    test('超过输入上限时被截断，且截断不产生「假成功」', () {
      final String oversized = _fixture('static_page_oversized.html');
      final StaticExtraction truncated = extractStaticArticle(
        oversized,
        limits: const StaticExtractionLimits(maxInputLength: 2000),
      );
      // 截断后仍然有正文（前缀里就有内容），但长度明显小于全文。
      expect(truncated.text, isNotEmpty);
      expect(truncated.text.length, lessThan(oversized.length));
      expect(truncated.text, contains('长度上限'));
    });

    test('空 HTML 与纯空白 → 没有正文', () {
      expect(
        extractStaticArticle('').outcome,
        StaticExtractionOutcome.noContent,
      );
      expect(
        extractStaticArticle('   \n  ').outcome,
        StaticExtractionOutcome.noContent,
      );
    });

    test('图片地址数量有上限（防超大页面塞入海量引用）', () {
      final StringBuffer builder = StringBuffer()
        ..write('<html><head><title>t</title></head><body><article>');
      for (int i = 0; i < 50; i++) {
        builder.write('<img src="https://cdn.example.com/$i.png">');
      }
      builder
        ..write('<p>${'正文文字。' * 60}</p>')
        ..write('</article></body></html>');
      final String many = builder.toString();
      final StaticExtraction result = extractStaticArticle(
        many,
        limits: const StaticExtractionLimits(maxImageUrls: 5),
      );
      expect(result.imageUrls, hasLength(5));
    });
  });

  group('危险内容不进结果（清洗器是唯一判据）', () {
    test('script 内容与事件属性不会出现在正文里', () {
      final StaticExtraction result = extractStaticArticle(
        '<html><head><title>t</title></head><body><article>'
        '<h1>标题</h1>'
        '<p onclick="steal()">${'正常正文。' * 60}</p>'
        '<script>alert(1)</script>'
        '<iframe src="https://evil.example.com/"></iframe>'
        '</article></body></html>',
      );
      expect(result.text, contains('正常正文。'));
      expect(result.text, isNot(contains('alert(1)')));
      expect(result.text, isNot(contains('steal')));
    });

    test('javascript: 链接不会被记录为图片地址', () {
      final StaticExtraction result = extractStaticArticle(
        '<html><head><title>t</title></head><body><article>'
        '<img src="javascript:alert(1)" alt="bad">'
        '<p>${'正常正文。' * 60}</p>'
        '</article></body></html>',
      );
      expect(result.imageUrls, isEmpty);
    });
  });

  group('标题回退', () {
    test('没有 title 时用正文里的第一个 h1', () {
      final StaticExtraction result = extractStaticArticle(
        '<html><body><article><h1>只有正文里的标题</h1>'
        '<p>${'正文文字。' * 60}</p></article></body></html>',
      );
      expect(result.title, '只有正文里的标题');
    });

    test('title 去掉站点后缀', () {
      final StaticExtraction result = extractStaticArticle(
        '<html><head><title>文章标题 | 某某新闻</title></head><body><main>'
        '<p>${'正文文字。' * 60}</p></main></body></html>',
      );
      expect(result.title, '文章标题');
      expect(result.usedRegion, 'main');
    });

    test('HTML 实体在标题里被解码', () {
      final StaticExtraction result = extractStaticArticle(
        '<html><head><title>A &amp; B &mdash; 站点</title></head><body><main>'
        '<p>${'正文文字。' * 60}</p></main></body></html>',
      );
      expect(result.title, 'A & B');
    });
  });

  group('正文区域选择', () {
    test('没有语义标签时挑文字最多的块', () {
      final StaticExtraction result = extractStaticArticle(
        '<html><body>'
        '<div class="tiny"><p>短。</p></div>'
        '<div class="big"><p>${'这是最长的一块正文内容，应当被选中。' * 20}</p></div>'
        '</body></html>',
      );
      expect(result.text, contains('应当被选中'));
      // 短块的内容也在这棵树上（它在外层 div 里），但选中的块必须是大的那块。
      expect(result.usedRegion, 'largest');
    });

    test('什么都没有时回退整页并标注 body', () {
      final StaticExtraction result = extractStaticArticle(
        '<html><body><span>${'一句很短的文字。' * 40}</span></body></html>',
      );
      expect(result.usedRegion, 'body');
      expect(result.text, contains('一句很短的文字'));
    });
  });
}
