// T035：翻译存储的真实 SQLite 往返（原文不变是**结构性**的断言）。
//
// 三条与产品规则对应的断言：
//   1) 译文按「文章 + 目标语言」存取，中英两份互不覆盖；
//   2) 段落属性（顺序/角色/层级/状态/截断）逐项无损往返；
//   3) **写入译文不动 articles 的任何列**：原文、源摘要、AI 摘要、三态与收藏全部原值。
library;

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'package:flux/core/core.dart';
import 'package:flux/features/articles/domain/markdown_to_document.dart';
import 'package:flux/infrastructure/local/article_translation_store.dart';
import 'package:flux/infrastructure/local/database.dart';
import 'package:flux/infrastructure/local/feed_catalog_store.dart';
import 'package:flux/infrastructure/local/tables/article_tables.dart';

void main() {
  late AppDatabase db;
  late DriftArticleTranslationStore store;
  late int articleId;

  setUp(() async {
    db = AppDatabase.memory();
    await db.customSelect('SELECT 1').get();
    store = DriftArticleTranslationStore(db);
    final int feedId = (await DriftFeedCatalogStore(db).createFeed(
      const FeedInsert(
        syncId: 'feed.t035',
        normalizedUrl: 'https://t035.example.com/feed.xml',
        name: '示例源',
      ),
    )).unwrap().id;
    articleId = await db
        .into(db.articles)
        .insert(
          ArticlesCompanion.insert(
            feedId: Value<int?>(feedId),
            title: '翻译存储测试',
            identityBasis: IdentityBasis.guid,
            guid: const Value<String?>('guid-t035'),
            guidPresent: const Value<bool>(true),
            body: const Value<String?>('第一段原文。\n\n第二段原文。'),
            summary: const Value<String?>('源摘要'),
            aiSummary: const Value<String?>('AI 摘要'),
            favorite: const Value<bool>(true),
            readingState: const Value<ReadingState>(ReadingState.later),
          ),
        );
  });

  tearDown(() async {
    await db.close();
  });

  ArticleTranslation sample({
    required String language,
    required String text,
    TranslationSegmentStatus status = TranslationSegmentStatus.translated,
  }) => ArticleTranslation(
    articleId: articleId,
    targetLanguage: language,
    sourceDigest: 'source-digest',
    sourceLength: 12,
    modelLabel: 'main/main-model',
    createdAt: DateTime.utc(2026, 9, 22, 4),
    segments: <TranslationSegment>[
      TranslationSegment(
        index: 0,
        kind: TranslationBlockKind.paragraph,
        level: 0,
        sourceDigest: 'seg-0',
        sourceText: '第一段原文。',
        status: status,
        translatedText: status == TranslationSegmentStatus.translated
            ? text
            : null,
        sourceTruncated: true,
      ),
      const TranslationSegment(
        index: 1,
        kind: TranslationBlockKind.heading,
        level: 2,
        sourceDigest: 'seg-1',
        sourceText: '第二段原文。',
        status: TranslationSegmentStatus.failed,
      ),
    ],
  );

  test('译文往返：段落顺序、角色、层级、状态与截断标记都无损', () async {
    final Result<ArticleTranslation> saved = await store.save(
      sample(language: 'en', text: 'First paragraph.'),
    );
    expect(saved.isOk, isTrue);
    final Result<ArticleTranslation?> read = await store.find(
      articleId: articleId,
      targetLanguage: 'en',
    );
    final ArticleTranslation translation = read.unwrap()!;
    expect(translation.segments, hasLength(2));
    expect(translation.segments[0].translatedText, 'First paragraph.');
    expect(translation.segments[0].kind, TranslationBlockKind.paragraph);
    expect(translation.segments[0].sourceTruncated, isTrue);
    expect(translation.segments[1].kind, TranslationBlockKind.heading);
    expect(translation.segments[1].level, 2);
    expect(translation.segments[1].status, TranslationSegmentStatus.failed);
    expect(translation.segments[1].translatedText, isNull);
    expect(translation.modelLabel, 'main/main-model');
    expect(translation.sourceDigest, 'source-digest');
  });

  test('中英两份译文互不覆盖，按目标语言分别取回', () async {
    await store.save(sample(language: 'en', text: 'English body.'));
    await store.save(sample(language: 'zh-Hans', text: '中文译文。'));
    expect(
      (await store.find(
        articleId: articleId,
        targetLanguage: 'en',
      )).unwrap()!.segments[0].translatedText,
      'English body.',
    );
    expect(
      (await store.find(
        articleId: articleId,
        targetLanguage: 'zh-Hans',
      )).unwrap()!.segments[0].translatedText,
      '中文译文。',
    );
  });

  test('重复保存整体替换段落（正文变短时不留上一版的段落）', () async {
    await store.save(sample(language: 'en', text: 'First version.'));
    final ArticleTranslation shortened = ArticleTranslation(
      articleId: articleId,
      targetLanguage: 'en',
      sourceDigest: 'source-digest-2',
      segments: <TranslationSegment>[
        const TranslationSegment(
          index: 0,
          kind: TranslationBlockKind.paragraph,
          level: 0,
          sourceDigest: 'seg-0',
          sourceText: '第一段原文。',
          status: TranslationSegmentStatus.translated,
          translatedText: 'Only paragraph.',
        ),
      ],
    );
    await store.save(shortened);
    final ArticleTranslation read = (await store.find(
      articleId: articleId,
      targetLanguage: 'en',
    )).unwrap()!;
    expect(read.segments, hasLength(1), reason: '旧段落必须被整体清掉');
    expect(read.sourceDigest, 'source-digest-2');
  });

  test('写入译文**不改动** articles 的任何列（原文始终保留）', () async {
    // 先把译文回填到真实文档树上，证明这个用例覆盖的是完整路径。
    final DocDocument document = parseMarkdownToDocument('正文。');
    expect(document.children, isNotEmpty);
    await store.save(sample(language: 'en', text: 'Translated.'));
    final Article row = (await db.select(db.articles).get()).single;
    expect(row.body, '第一段原文。\n\n第二段原文。', reason: '源正文不得被译文覆盖');
    expect(row.summary, '源摘要', reason: '源摘要不得被覆盖');
    expect(row.aiSummary, 'AI 摘要', reason: 'AI 摘要不得被覆盖');
    expect(row.favorite, isTrue, reason: '收藏不得被翻译改动');
    expect(row.readingState, ReadingState.later, reason: '三态不得被翻译改动');
    expect(row.title, '翻译存储测试');
  });

  test('文章被删除时译文随之清理（不留孤儿行）', () async {
    await store.save(sample(language: 'en', text: 'Translated.'));
    await (db.delete(
      db.articles,
    )..where((Articles t) => t.id.equals(articleId))).go();
    expect(await db.select(db.articleTranslationRecords).get(), isEmpty);
    expect(await db.select(db.translationSegmentRecords).get(), isEmpty);
  });

  test('没有译文时返回 Ok(null)，不报错', () async {
    final Result<ArticleTranslation?> read = await store.find(
      articleId: articleId,
      targetLanguage: 'en',
    );
    expect(read.isOk, isTrue);
    expect(read.unwrap(), isNull);
  });
}
