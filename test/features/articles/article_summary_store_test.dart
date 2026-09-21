// T034：AI 摘要与源摘要独立、缺摘要兜底（SET-037）与当天计数的落库口径。
//
// 三组断言：
//   1) **显示优先级**（纯函数）：AI 摘要 → 源摘要 → 截取正文；关闭兜底时不显示；
//   2) **落库独立性**（真实 drift 内存库）：写 AI 摘要**不动**源摘要、正文与三态收藏；
//      「缺摘要」候选的判定是「源摘要与 AI 摘要都为空」；
//   3) **当天计数**（真实 drift 内存库）：按日期键累加、跨日期互不影响、坏值 fail-closed。
library;

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'package:flux/core/core.dart';
import 'package:flux/infrastructure/local/article_catalog_store.dart';
import 'package:flux/infrastructure/local/daily_summary_counter_store.dart';
import 'package:flux/infrastructure/local/database.dart';

void main() {
  group('显示的摘要来源优先级（SET-037 的兜底规则）', () {
    test('AI 摘要优先于源摘要（两者都在时显示 AI 并标注来源）', () {
      final DisplaySummary? summary = resolveDisplaySummary(
        aiSummary: 'AI 写的',
        sourceSummary: '源写的',
      );
      expect(summary!.text, 'AI 写的');
      expect(summary.origin, SummaryOrigin.ai);
    });

    test('没有 AI 摘要时用源摘要（不因为 AI 缺席就退到截取）', () {
      final DisplaySummary? summary = resolveDisplaySummary(
        sourceSummary: '源写的',
        body: '正文内容',
      );
      expect(summary!.text, '源写的');
      expect(summary.origin, SummaryOrigin.source);
    });

    test('两者都缺时截取正文作兜底，并标记为 excerpt', () {
      final DisplaySummary? summary = resolveDisplaySummary(
        body: '这是一篇没有摘要的文章的正文，需要被截取成一小段。',
      );
      expect(summary!.origin, SummaryOrigin.excerpt);
      expect(summary.text, contains('这是一篇'));
    });

    test('关掉兜底时不显示任何摘要（不制造一段假摘要）', () {
      expect(resolveDisplaySummary(body: '正文', allowExcerpt: false), isNull);
    });

    test('空白的 AI/源摘要视为缺失（空串不是摘要）', () {
      final DisplaySummary? summary = resolveDisplaySummary(
        aiSummary: '   ',
        sourceSummary: '',
        body: '正文内容',
      );
      expect(summary!.origin, SummaryOrigin.excerpt);
    });

    test('截取在字符边界、超长时加省略号', () {
      final DisplaySummary short = excerptSummaryFrom('短文。')!;
      expect(short.text, '短文。');
      expect(short.text, isNot(contains('…')));

      final DisplaySummary long = excerptSummaryFrom('字' * 500)!;
      expect(long.text.runes.length, kSummaryExcerptLength + 1);
      expect(long.text, endsWith('…'));
    });

    test('空白正文不产生截取（调用方给「没有可显示的摘要」）', () {
      expect(excerptSummaryFrom('   \n\t '), isNull);
      expect(excerptSummaryFrom(null), isNull);
    });
  });

  group('AI 摘要落库（与源摘要独立）', () {
    late AppDatabase db;
    late DriftArticleCatalogStore store;
    late int feedId;
    late int articleId;

    setUp(() async {
      db = AppDatabase.memory();
      await db.customSelect('SELECT 1').get();
      store = DriftArticleCatalogStore(db);
      feedId = await db
          .into(db.feeds)
          .insert(
            FeedsCompanion.insert(
              syncId: 'feed-1',
              normalizedUrl: 'https://a.example.com/feed.xml',
              name: '源',
            ),
          );
      articleId = await db
          .into(db.articles)
          .insert(
            ArticlesCompanion.insert(
              feedId: Value<int?>(feedId),
              title: '文章',
              identityBasis: IdentityBasis.guid,
              body: const Value<String?>('这是正文内容。'),
              summary: const Value<String?>('源摘要'),
            ),
          );
    });

    tearDown(() async => db.close());

    test('写 AI 摘要只改 ai_summary 三列：源摘要、正文、三态、收藏都不动', () async {
      // 先把三态与收藏设成非默认值，确保它们不会被顺手改掉。
      await store.setReadingState(
        articleIds: <int>[articleId],
        state: ReadingState.later,
      );
      await store.setFavorite(articleIds: <int>[articleId], favorite: true);

      final Result<void> saved = await store.saveAiSummary(
        articleId: articleId,
        summary: AiSummaryRecord(
          text: 'AI 生成的摘要',
          generatedAt: DateTime.utc(2026, 9, 22, 4),
          modelLabel: 'main/main-model',
        ),
      );
      expect(saved.isOk, isTrue);

      final Article row = (await db.select(db.articles).get()).single;
      expect(row.aiSummary, 'AI 生成的摘要');
      expect(row.aiSummaryAt, DateTime.utc(2026, 9, 22, 4));
      expect(row.aiSummaryModel, 'main/main-model');
      expect(row.summary, '源摘要', reason: '源摘要不得被覆盖（架构 4.2）');
      expect(row.body, '这是正文内容。', reason: '正文不得被改动');
      expect(row.readingState.name, 'later', reason: '三态不得被改动');
      expect(row.favorite, isTrue, reason: '收藏不得被改动');
    });

    test('读回 AI 摘要带着生成元数据（模型标识与时刻）', () async {
      await store.saveAiSummary(
        articleId: articleId,
        summary: AiSummaryRecord(
          text: '摘要文本',
          generatedAt: DateTime.utc(2026, 9, 22, 5),
          modelLabel: 'main/main-model',
        ),
      );
      final AiSummaryRecord record = (await store.readAiSummary(articleId))
          .unwrap()!;
      expect(record.text, '摘要文本');
      expect(record.modelLabel, 'main/main-model');
      expect(record.generatedAt, DateTime.utc(2026, 9, 22, 5));
      expect(record.modelLabelText, 'main/main-model');
    });

    test('从未生成过时返回 null（不是空记录）', () async {
      expect((await store.readAiSummary(articleId)).unwrap(), isNull);
    });

    test('只有文本没有时间视为「没有 AI 摘要」（无法说明何时生成）', () async {
      await (db.update(db.articles)..where((t) => t.id.equals(articleId)))
          .write(const ArticlesCompanion(aiSummary: Value<String?>('孤儿摘要')));
      expect((await store.readAiSummary(articleId)).unwrap(), isNull);
    });

    test('缺摘要候选 = 源摘要与 AI 摘要都为空', () async {
      // 这篇有源摘要：不是候选。
      expect(
        (await store.listArticlesMissingSummary(limit: 10)).unwrap(),
        isEmpty,
      );
      final int other = await db
          .into(db.articles)
          .insert(
            ArticlesCompanion.insert(
              feedId: Value<int?>(feedId),
              title: '另一篇',
              identityBasis: IdentityBasis.guid,
              summary: const Value<String?>(null),
            ),
          );
      final List<int> missing = (await store.listArticlesMissingSummary(
        limit: 10,
      )).unwrap();
      expect(missing, <int>[other]);

      // 给这一篇写入 AI 摘要后它就不再是候选（不该重复花钱）。
      await store.saveAiSummary(
        articleId: other,
        summary: AiSummaryRecord(
          text: 'AI',
          generatedAt: DateTime.utc(2026, 9, 22),
        ),
      );
      expect(
        (await store.listArticlesMissingSummary(limit: 10)).unwrap(),
        isEmpty,
      );
    });

    test('只有空白的源摘要也算缺（空 <description> 不是摘要）', () async {
      final int blank = await db
          .into(db.articles)
          .insert(
            ArticlesCompanion.insert(
              feedId: Value<int?>(feedId),
              title: '空白摘要',
              identityBasis: IdentityBasis.guid,
              summary: const Value<String?>('   '),
            ),
          );
      final List<int> missing = (await store.listArticlesMissingSummary(
        limit: 10,
      )).unwrap();
      expect(missing, contains(blank));
    });
  });

  group('当天自动摘要计数（SET-064 的落库形态）', () {
    late AppDatabase db;
    late SettingsDailySummaryCounter counter;

    setUp(() async {
      db = AppDatabase.memory();
      await db.customSelect('SELECT 1').get();
      counter = SettingsDailySummaryCounter(db);
    });

    tearDown(() async => db.close());

    test('未记录时读作 0；累加后读回累加值', () async {
      expect((await counter.readUsed('2026-09-22')).unwrap(), 0);
      await counter.addUsed('2026-09-22', 1);
      await counter.addUsed('2026-09-22', 2);
      expect((await counter.readUsed('2026-09-22')).unwrap(), 3);
    });

    test('不同日期互不影响（跨午夜不需要重置逻辑）', () async {
      await counter.addUsed('2026-09-22', 50);
      expect((await counter.readUsed('2026-09-23')).unwrap(), 0);
    });

    test('计数存在 device. 命名空间里（不占用 SET 编号、不参与同步）', () async {
      await counter.addUsed('2026-09-22', 1);
      final Setting row = (await db.select(db.settings).get()).single;
      expect(
        row.key,
        startsWith('device.autoSummaryUsed.'),
        reason: '这一项是本机运行计数，不是用户偏好',
      );
      expect(row.key, endsWith('2026-09-22'), reason: '键里带日期，跨天自动归零');
    });

    test('计数值损坏时按上限兜底（方向保守：今天不再跑）', () async {
      await db
          .into(db.settings)
          .insert(
            SettingsCompanion.insert(
              key: '${kAutoSummaryUsedPrefix}2026-09-22',
              value: 'not-a-number',
            ),
          );
      final int used = (await counter.readUsed('2026-09-22')).unwrap();
      expect(
        used,
        greaterThanOrEqualTo(1 << 20),
        reason: '坏数据必须让剩余额度算成 0，而不是从 0 开始花',
      );
    });

    test('addUsed(0) 不写库（不制造无意义的行）', () async {
      await counter.addUsed('2026-09-22', 0);
      expect(await db.select(db.settings).get(), isEmpty);
    });
  });
}
