// T035：分段全文翻译（段落切分/映射、逐段调用、取消保留完成段、只重试失败段、原文不变、
// 段落级缓存、summaryOnly 标记）。
//
// 这一组用例盯的是三件用户可见的事：
//   1) **译文与原文按段落关联**：切分与回填必须是同一份遍历，否则译文会错位；
//   2) **取消与部分成功都不丢已完成的工作**：取消保留已完成段，失败段可单独重试；
//   3) **原文始终保留**：所有写入都只落在译文结构上，源正文一个字都不动。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:flux/core/core.dart';
import 'package:flux/features/ai/application/ai_task_budget.dart';
import 'package:flux/features/ai/application/ai_task_runner.dart';
import 'package:flux/features/ai/domain/ai_message.dart';
import 'package:flux/features/ai/domain/ai_model.dart';
import 'package:flux/features/ai/domain/ai_protocol.dart';
import 'package:flux/features/articles/application/article_translation_tasks.dart';
import 'package:flux/features/articles/domain/markdown_to_document.dart';

import '../ai/ai_runner_support.dart';
import 'translation_test_support.dart';

void main() {
  late FakeClock clock;
  late RecordingSink sink;
  late FakeTranslationCache cache;

  setUp(() {
    clock = FakeClock(start: DateTime.utc(2026, 9, 22, 4));
    sink = RecordingSink();
    cache = FakeTranslationCache();
  });

  AiModel model() => const AiModel(
    alias: 'main',
    protocol: AiProtocol.openAiChatCompletions,
    baseUrl: 'https://main.example.com',
    modelId: 'main-model',
  );

  /// 一个脚本化工厂：第 N 次调用产出 `译文N`。
  ScriptedAiFactory happyFactory({int segments = 99}) =>
      ScriptedAiFactory(<String, List<AiAttemptScript>>{
        'main': <AiAttemptScript>[
          for (int i = 0; i < segments; i++)
            ScriptSuccess(deltas: <String>['译文', (i + 1).toString()]),
        ],
      });

  TranslationService service(ScriptedAiFactory factory) => TranslationService(
    runner: AiTaskRunner(
      credentials: const AlwaysCredentialStore(),
      factory: factory,
      diagnostics: sink,
      budget: const AiTaskBudget(),
      clock: clock,
    ),
    cache: cache,
    clock: clock,
    diagnostics: sink,
  );

  group('段落切分与映射（架构 4.2「译文与原文按段落关联」）', () {
    test('标题/段落/列表项各为一段，且顺序与层级保留', () {
      final DocDocument document = parseMarkdownToDocument(
        '# 标题一\n\n第一段。\n\n- 项目甲\n- 项目乙\n\n## 小标题\n\n最后一段。',
      );
      final List<TranslationUnit> units = splitTranslationUnits(document);
      expect(units.map((TranslationUnit u) => u.sourceText).toList(), <String>[
        '标题一',
        '第一段。',
        '项目甲',
        '项目乙',
        '小标题',
        '最后一段。',
      ]);
      expect(units[0].kind, TranslationBlockKind.heading);
      expect(units[0].level, 1, reason: '标题层级保留（h1）');
      expect(units[1].kind, TranslationBlockKind.paragraph);
      expect(units[2].kind, TranslationBlockKind.listItem);
      expect(units[2].level, 1, reason: '列表项层级 = 嵌套深度');
      expect(units[4].level, 2, reason: 'h2 的层级保留');
    });

    test('代码块/公式/分隔线/图片不产生翻译单元（宁可少翻，不可翻错）', () {
      final DocDocument document = parseMarkdownToDocument(
        '正文一段。\n\n```dart\nvoid main() {}\n```\n\n---\n\n最后一段。',
      );
      final List<TranslationUnit> units = splitTranslationUnits(document);
      expect(units, hasLength(2));
      expect(units[0].sourceText, '正文一段。');
      expect(units[1].sourceText, '最后一段。');
      expect(
        units.any((TranslationUnit u) => u.sourceText.contains('void main')),
        isFalse,
        reason: '代码块不交给模型改写',
      );
    });

    test('回填只替换有译文的段，而且落在**对应的**那一段上', () {
      final DocDocument document = parseMarkdownToDocument(
        '# 标题一\n\n第一段。\n\n第二段。',
      );
      final List<TranslationUnit> units = splitTranslationUnits(document);
      // 只给第 2 段（下标 1，即「第一段。」）一份译文，第 3 段不给。
      final ArticleTranslation translation = ArticleTranslation(
        articleId: 1,
        targetLanguage: 'en',
        sourceDigest: 'd',
        segments: <TranslationSegment>[
          TranslationSegment(
            index: 1,
            kind: units[1].kind,
            level: units[1].level,
            sourceDigest: units[1].sourceDigest,
            sourceText: units[1].sourceText,
            status: TranslationSegmentStatus.translated,
            translatedText: 'First paragraph.',
          ),
        ],
      );
      final DocDocument applied = applyTranslation(document, translation);
      final List<String> plain = <String>[
        for (final DocNode node in applied.children)
          node is DocHeading
              ? docInlinePlainText(node.children)
              : docInlinePlainText((node as DocParagraph).children),
      ];
      expect(plain[0], '标题一', reason: '没有译文的标题显示原文');
      expect(plain[1], 'First paragraph.', reason: '译文落在它自己的那一段上');
      expect(plain[2], '第二段。', reason: '没有译文的段显示原文');
    });

    test('回填不猜段落：段数与译文顺序都对不上时该段保持原文', () {
      final DocDocument document = parseMarkdownToDocument('只有一段。');
      const ArticleTranslation translation = ArticleTranslation(
        articleId: 1,
        targetLanguage: 'en',
        sourceDigest: 'd',
        segments: <TranslationSegment>[
          TranslationSegment(
            index: 7,
            kind: TranslationBlockKind.paragraph,
            level: 0,
            sourceDigest: 'x',
            sourceText: '别的段',
            status: TranslationSegmentStatus.translated,
            translatedText: 'Not this one.',
          ),
        ],
      );
      final DocDocument applied = applyTranslation(document, translation);
      expect(
        docInlinePlainText((applied.children.single as DocParagraph).children),
        '只有一段。',
      );
    });
  });

  group('逐段调用与进度', () {
    test('逐段各发一次请求，并按段回报进度', () async {
      final DocDocument document = parseMarkdownToDocument(
        '第一段。\n\n第二段。\n\n第三段。',
      );
      final ScriptedAiFactory factory = happyFactory();
      final List<TranslationProgress> progress = <TranslationProgress>[];
      final TranslationOutcome outcome = await service(factory).translate(
        articleId: 1,
        document: document,
        targetLanguage: 'en',
        models: <AiModel>[model()],
        sourceDigest: translationDigestOf('正文'),
        sourceLength: 9,
        onProgress: progress.add,
      );
      expect(factory.totalIssued, 3, reason: '三段各一次调用');
      expect(outcome.requestsIssued, 3);
      expect(outcome.translation!.translatedCount, 3);
      expect(
        progress.map((TranslationProgress p) => p.translated).toList(),
        <int>[1, 2, 3],
        reason: '进度是逐段递增的',
      );
      expect(progress.last.isComplete, isTrue);
    });

    test('段落级缓存命中时一个请求都不发，但该段算已完成', () async {
      final DocDocument document = parseMarkdownToDocument('第一段。\n\n第二段。');
      final ScriptedAiFactory factory = happyFactory();
      // 先跑一次把两段的缓存键写进去。
      await service(factory).translate(
        articleId: 1,
        document: document,
        targetLanguage: 'en',
        models: <AiModel>[model()],
        sourceDigest: translationDigestOf('正文'),
        sourceLength: 6,
      );
      expect(factory.totalIssued, 2);
      final ScriptedAiFactory second = happyFactory();
      final TranslationOutcome outcome = await service(second).translate(
        articleId: 1,
        document: document,
        targetLanguage: 'en',
        models: <AiModel>[model()],
        sourceDigest: translationDigestOf('正文'),
        sourceLength: 6,
      );
      expect(second.totalIssued, 0, reason: '命中缓存时不得发出请求');
      expect(outcome.cacheHits, 2);
      expect(outcome.translation!.translatedCount, 2);
    });

    test('缓存键按段落文本区分（换了一段文字就是另一个键）', () async {
      final DocDocument document = parseMarkdownToDocument('甲段。\n\n乙段。');
      final ScriptedAiFactory factory = happyFactory();
      await service(factory).translate(
        articleId: 1,
        document: document,
        targetLanguage: 'en',
        models: <AiModel>[model()],
        sourceDigest: translationDigestOf('正文'),
        sourceLength: 6,
      );
      final List<String> keys = cache.queried.toSet().toList();
      expect(keys, hasLength(2), reason: '两段文字 → 两个不同的缓存键');
    });

    test('目标语言进缓存键：切成英文与切成中文是两个键', () async {
      final DocDocument document = parseMarkdownToDocument('同一段。');
      final TranslationService svc = service(happyFactory());
      await svc.translate(
        articleId: 1,
        document: document,
        targetLanguage: 'en',
        models: <AiModel>[model()],
        sourceDigest: 'd',
        sourceLength: 4,
      );
      final String englishKey = cache.queried.last;
      await svc.translate(
        articleId: 1,
        document: document,
        targetLanguage: 'zh-Hans',
        models: <AiModel>[model()],
        sourceDigest: 'd',
        sourceLength: 4,
      );
      final String chineseKey = cache.queried.last;
      expect(englishKey, isNot(chineseKey));
    });
  });

  group('取消、部分成功与只重试失败段', () {
    test('取消保留已完成段，未完成的段显示原文（pending）', () async {
      final DocDocument document = parseMarkdownToDocument('一。\n\n二。\n\n三。');
      final AiCancellation cancellation = AiCancellation();
      // 第 2 段开始前取消。
      final ScriptedAiFactory factory = ScriptedAiFactory(
        <String, List<AiAttemptScript>>{
          'main': <AiAttemptScript>[
            ScriptSuccess(onStart: () {}),
            ScriptSuccess(onStart: cancellation.cancel),
          ],
        },
        scriptClock: clock,
      );
      final TranslationOutcome outcome = await service(factory).translate(
        articleId: 1,
        document: document,
        targetLanguage: 'en',
        models: <AiModel>[model()],
        sourceDigest: translationDigestOf('正文'),
        sourceLength: 6,
        cancellation: cancellation,
      );
      final ArticleTranslation translation = outcome.translation!;
      expect(
        translation.translatedCount,
        greaterThanOrEqualTo(1),
        reason: '已完成的那一段必须被保留',
      );
      expect(translation.translatedCount, lessThan(3));
      expect(translation.pendingCount, greaterThan(0));
      // 未完成的段在结构上是 pending（渲染时显示原文）。
      for (final TranslationSegment segment in translation.segments) {
        if (!segment.isTranslated) {
          expect(segment.status, TranslationSegmentStatus.pending);
          expect(segment.translatedText, isNull);
        }
      }
    });

    test('单段失败不回滚整份译文，失败段可单独重试且不重跑已完成段', () async {
      final DocDocument document = parseMarkdownToDocument('一。\n\n二。\n\n三。');
      // 第 2 次调用失败（第三段用最后一条剧本重放 → 也失败）。
      final ScriptedAiFactory factory = ScriptedAiFactory(
        <String, List<AiAttemptScript>>{
          'main': <AiAttemptScript>[
            const ScriptSuccess(deltas: <String>['一']),
            ScriptFailure(
              error: ProviderError(
                provider: 'main',
                kind: 'server',
                detail: 'x',
              ),
            ),
          ],
        },
      );
      final TranslationService svc = service(factory);
      final TranslationOutcome first = await svc.translate(
        articleId: 1,
        document: document,
        targetLanguage: 'en',
        models: <AiModel>[model()],
        sourceDigest: translationDigestOf('正文'),
        sourceLength: 6,
      );
      final ArticleTranslation partial = first.translation!;
      expect(partial.translatedCount, 1);
      expect(partial.failedCount, 2, reason: '其余两段标失败');

      // 只重试失败段：已完成那一版不再发请求。
      final ScriptedAiFactory retry = happyFactory();
      final Set<int> failed = <int>{
        for (final TranslationSegment segment in partial.segments)
          if (segment.status == TranslationSegmentStatus.failed) segment.index,
      };
      final TranslationOutcome second = await service(retry).translate(
        articleId: 1,
        document: document,
        targetLanguage: 'en',
        models: <AiModel>[model()],
        sourceDigest: translationDigestOf('正文'),
        sourceLength: 6,
        existing: partial,
        onlyFailed: failed,
      );
      expect(retry.totalIssued, 2, reason: '只重跑失败的 2 段，不重跑全部 3 段');
      expect(second.translation!.translatedCount, 3);
      expect(second.translation!.failedCount, 0);
    });

    test('已有译文与当前段文字不一致时不被复用（正文改过）', () async {
      final DocDocument document = parseMarkdownToDocument('新的一段。');
      final ScriptedAiFactory factory = happyFactory();
      final TranslationOutcome outcome = await service(factory).translate(
        articleId: 1,
        document: document,
        targetLanguage: 'en',
        models: <AiModel>[model()],
        sourceDigest: translationDigestOf('正文'),
        sourceLength: 5,
        existing: const ArticleTranslation(
          articleId: 1,
          targetLanguage: 'en',
          sourceDigest: 'old',
          segments: <TranslationSegment>[
            TranslationSegment(
              index: 0,
              kind: TranslationBlockKind.paragraph,
              level: 0,
              sourceDigest: 'different-digest',
              sourceText: '旧的一段。',
              status: TranslationSegmentStatus.translated,
              translatedText: 'Stale translation.',
            ),
          ],
        ),
      );
      expect(factory.totalIssued, 1, reason: '段落文字变了必须重新翻译');
      expect(
        outcome.translation!.segments.single.translatedText,
        isNot('Stale translation.'),
      );
    });
  });

  group('summaryOnly 与超长段（架构 4.2、SET-061）', () {
    test('summaryOnly 不提供全文翻译', () async {
      final DocDocument document = parseMarkdownToDocument('这段其实只是源摘要。');
      final ScriptedAiFactory factory = happyFactory();
      final TranslationOutcome outcome = await service(factory).translate(
        articleId: 1,
        document: document,
        targetLanguage: 'en',
        models: <AiModel>[model()],
        sourceDigest: 'd',
        sourceLength: 10,
        completeness: BodyCompleteness.summaryOnly,
      );
      expect(outcome.skippedReason, TranslationSkipReason.summaryOnly);
      expect(outcome.translation, isNull);
      expect(factory.totalIssued, 0, reason: '跳过时一个请求都不发');
    });

    test('translationBlockReason 先判 summaryOnly（顺序有语义）', () {
      expect(
        translationBlockReason(
          completeness: BodyCompleteness.summaryOnly,
          hasBody: true,
          hasTranslatableParagraphs: true,
        ),
        TranslationSkipReason.summaryOnly,
      );
      expect(
        translationBlockReason(
          completeness: BodyCompleteness.sourceBody,
          hasBody: false,
          hasTranslatableParagraphs: false,
        ),
        TranslationSkipReason.noBody,
      );
      expect(
        translationBlockReason(
          completeness: BodyCompleteness.sourceBody,
          hasBody: true,
          hasTranslatableParagraphs: false,
        ),
        TranslationSkipReason.noTranslatableText,
      );
      expect(
        translationBlockReason(
          completeness: BodyCompleteness.extracted,
          hasBody: true,
          hasTranslatableParagraphs: true,
        ),
        isNull,
      );
    });

    test('超长段标截断而不分块（一次点击不变成 N 次计费）', () {
      final String long = '字' * 20000;
      final TranslationSegmentInput prepared = prepareTranslationSegment(long);
      expect(prepared.text.runes.length, kTranslationSegmentCharBudget);
      expect(prepared.originalLength, 20000);
      expect(prepared.truncated, isTrue);
    });

    test('截断在 rune 边界（不切坏代理对）', () {
      final TranslationSegmentInput prepared = prepareTranslationSegment(
        '🙂' * 100,
        budget: 50,
      );
      expect(prepared.text.runes.length, 50);
      expect(prepared.truncated, isTrue);
    });

    test('截断说明写进用户消息（否则模型把半段当整段）', () {
      final TranslationSegmentInput prepared = prepareTranslationSegment(
        '字' * 20000,
      );
      final String message = buildTranslationUserMessage(
        prepared,
        const TranslationUnit(
          index: 0,
          path: <int>[0],
          kind: TranslationBlockKind.paragraph,
          level: 0,
          sourceText: 'x',
          sourceDigest: 'd',
        ),
      );
      expect(message, contains('已截断'));
      expect(message, contains('20000'));
    });

    test('截断的段被记在译文结构里（界面据此说明）', () async {
      final String long = '字' * 20000;
      final DocDocument document = parseMarkdownToDocument(long);
      final ScriptedAiFactory factory = happyFactory();
      final TranslationOutcome outcome = await service(factory).translate(
        articleId: 1,
        document: document,
        targetLanguage: 'en',
        models: <AiModel>[model()],
        sourceDigest: 'd',
        sourceLength: 20000,
      );
      expect(outcome.translation!.hasTruncatedSource, isTrue);
    });

    test('没有可用模型时跳过并给原因（不发请求）', () async {
      final DocDocument document = parseMarkdownToDocument('一段。');
      final ScriptedAiFactory factory = happyFactory();
      final TranslationOutcome outcome = await service(factory).translate(
        articleId: 1,
        document: document,
        targetLanguage: 'en',
        models: const <AiModel>[],
        sourceDigest: 'd',
        sourceLength: 3,
      );
      expect(outcome.skippedReason, TranslationSkipReason.noModel);
      expect(factory.totalIssued, 0);
    });

    test('目标语言不在 SET-011 取值域内时跳过（不猜一个语言）', () async {
      final DocDocument document = parseMarkdownToDocument('一段。');
      final ScriptedAiFactory factory = happyFactory();
      final TranslationOutcome outcome = await service(factory).translate(
        articleId: 1,
        document: document,
        targetLanguage: 'fr',
        models: <AiModel>[model()],
        sourceDigest: 'd',
        sourceLength: 3,
      );
      expect(outcome.skippedReason, TranslationSkipReason.unsupportedLanguage);
      expect(factory.totalIssued, 0);
    });
  });

  group('原文始终保留（结构性）', () {
    test('译文结构里没有源正文的写入路径：只有段落与状态', () async {
      final DocDocument document = parseMarkdownToDocument('# 标题\n\n正文一段。');
      final ScriptedAiFactory factory = happyFactory();
      final TranslationOutcome outcome = await service(factory).translate(
        articleId: 42,
        document: document,
        targetLanguage: 'en',
        models: <AiModel>[model()],
        sourceDigest: 'source-digest',
        sourceLength: 12,
      );
      final ArticleTranslation translation = outcome.translation!;
      expect(translation.articleId, 42);
      expect(translation.targetLanguage, 'en');
      // 译文结构携带的是**源文本**（用于对照与缓存判据），而不是对源正文的引用或复制。
      expect(translation.segments.first.sourceText, '标题');
      expect(translation.sourceDigest, 'source-digest');
    });

    test('译文的 sourceDigest 与正文不一致时被判为过期', () {
      const ArticleTranslation translation = ArticleTranslation(
        articleId: 1,
        targetLanguage: 'en',
        sourceDigest: 'old-digest',
        segments: <TranslationSegment>[],
      );
      expect(translation.isStaleFor('new-digest'), isTrue);
      expect(translation.isStaleFor('old-digest'), isFalse);
    });
  });

  group('译文存储替身（与真实实现同一语义）', () {
    test('按文章 + 语言存取，写入失败不返回成功', () async {
      final FakeTranslationStore store = FakeTranslationStore();
      const ArticleTranslation translation = ArticleTranslation(
        articleId: 1,
        targetLanguage: 'en',
        sourceDigest: 'd',
        segments: <TranslationSegment>[],
      );
      expect((await store.save(translation)).isOk, isTrue);
      expect(
        (await store.find(articleId: 1, targetLanguage: 'en')).valueOrNull,
        isNotNull,
      );
      expect(
        (await store.find(articleId: 1, targetLanguage: 'zh-Hans')).valueOrNull,
        isNull,
        reason: '中英两份译文互不覆盖',
      );
      store.failSave = true;
      expect((await store.save(translation)).isErr, isTrue);
    });
  });
}
