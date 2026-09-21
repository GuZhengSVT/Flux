// T024：提取正文的数据层（真实内存库）。
//
// 四条与产品规则直接对应的断言：
//   * 保存后能读回（标题/图片/时间/hash 都在）；
//   * 保存**不改**阅读状态、收藏、源正文与正文哈希（阅读状态不变是 T024 的明确要求）；
//   * 哈希未变时不重写大字段（但更新时间）；
//   * 清除只清提取列，源正文仍在（可切回原文）。
library;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';

import 'package:flux/core/core.dart';
import 'package:flux/infrastructure/local/article_extraction_store.dart';
import 'package:flux/infrastructure/local/database.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late DriftArticleExtractionStore store;
  late int articleId;

  setUp(() async {
    db = AppDatabase.memory();
    await db.customSelect('SELECT 1').get();
    store = DriftArticleExtractionStore(db);
    final int feedId = await db
        .into(db.feeds)
        .insert(
          FeedsCompanion.insert(
            syncId: 'feed-ex',
            normalizedUrl: 'https://ex.example.com/feed.xml',
            name: '提取测试源',
          ),
        );
    articleId = await db
        .into(db.articles)
        .insert(
          ArticlesCompanion.insert(
            feedId: Value<int?>(feedId),
            title: '文章标题',
            identityBasis: IdentityBasis.guid,
            body: const Value<String?>('源内正文'),
            bodyHash: const Value<String?>('source-hash'),
            readingState: const Value<ReadingState>(ReadingState.later),
            favorite: const Value<bool>(true),
          ),
        );
  });

  tearDown(() async {
    await db.close();
  });

  ExtractedArticleBody body({
    String text = '提取到的正文',
    String hash = 'h1',
    String title = '原站标题',
    List<String> images = const <String>['https://cdn.example.com/a.png'],
  }) => ExtractedArticleBody(
    body: text,
    bodyHash: hash,
    title: title,
    imageUrls: images,
    extractedAt: DateTime.utc(2026, 9, 22, 3),
  );

  group('保存与读取', () {
    test('保存后可读回全部字段', () async {
      await store.saveExtraction(articleId: articleId, extraction: body());
      final ExtractedArticleBody? read = (await store.readExtraction(articleId))
          .unwrap();
      expect(read, isNotNull);
      expect(read!.body, '提取到的正文');
      expect(read.bodyHash, 'h1');
      expect(read.title, '原站标题');
      expect(read.imageUrls, <String>['https://cdn.example.com/a.png']);
      expect(read.extractedAt, DateTime.utc(2026, 9, 22, 3));
    });

    test('从未提取过 → null（界面据此显示「获取原站全文」而不是「重新获取」）', () async {
      expect((await store.readExtraction(articleId)).unwrap(), isNull);
    });

    test('不存在的文章 → 读取返回 null、保存返回失败（不假装成功）', () async {
      expect((await store.readExtraction(99999)).unwrap(), isNull);
      final Result<void> saved = await store.saveExtraction(
        articleId: 99999,
        extraction: body(),
      );
      expect(saved.isErr, isTrue);
      expect(saved.errorOrNull, isA<StorageError>());
    });

    test('多个图片地址往返无损（换行分隔）', () async {
      await store.saveExtraction(
        articleId: articleId,
        extraction: body(
          images: const <String>[
            'https://cdn.example.com/a.png',
            'https://cdn.example.com/b.png',
            'https://cdn.example.com/c.png',
          ],
        ),
      );
      final ExtractedArticleBody read = (await store.readExtraction(articleId))
          .unwrap()!;
      expect(read.imageUrls, hasLength(3));
      expect(read.imageUrls.last, 'https://cdn.example.com/c.png');
    });

    test('没有图片 → 空列表（不是含一个空串的列表）', () async {
      await store.saveExtraction(
        articleId: articleId,
        extraction: body(images: const <String>[]),
      );
      final ExtractedArticleBody read = (await store.readExtraction(articleId))
          .unwrap()!;
      expect(read.imageUrls, isEmpty);
    });
  });

  group('不触碰用户状态与源正文', () {
    test('保存提取正文后：阅读状态、收藏、源正文与正文哈希都不变', () async {
      await store.saveExtraction(articleId: articleId, extraction: body());
      final Article row = (await db.select(db.articles).get()).single;
      expect(row.readingState, ReadingState.later, reason: '获取全文不是一次阅读事件');
      expect(row.favorite, isTrue, reason: '收藏不得被提取改写');
      expect(row.body, '源内正文', reason: '源正文必须保留（用于对照）');
      expect(row.bodyHash, 'source-hash', reason: '源正文哈希不得被提取的哈希覆盖');
      expect(
        row.bodyCompleteness,
        BodyCompleteness.unknown,
        reason: '提取不改变源正文的完整性判定',
      );
    });

    test('清除提取正文后：源正文与状态仍在', () async {
      await store.saveExtraction(articleId: articleId, extraction: body());
      await store.clearExtraction(articleId);
      expect((await store.readExtraction(articleId)).unwrap(), isNull);
      final Article row = (await db.select(db.articles).get()).single;
      expect(row.body, '源内正文');
      expect(row.readingState, ReadingState.later);
      expect(row.favorite, isTrue);
    });
  });

  group('修订判定（哈希）', () {
    test('哈希未变 → 不重写正文，但更新时间', () async {
      await store.saveExtraction(
        articleId: articleId,
        extraction: body(text: '第一版正文', hash: 'h1'),
      );
      // 第二次：同一个哈希，但时间不同。
      await store.saveExtraction(
        articleId: articleId,
        extraction: ExtractedArticleBody(
          body: '第一版正文',
          bodyHash: 'h1',
          title: '原站标题',
          imageUrls: const <String>[],
          extractedAt: DateTime.utc(2026, 9, 23, 5),
        ),
      );
      final ExtractedArticleBody read = (await store.readExtraction(articleId))
          .unwrap()!;
      expect(read.body, '第一版正文');
      expect(
        read.extractedAt,
        DateTime.utc(2026, 9, 23, 5),
        reason: '时间应当更新（用户确实又检查了一次）',
      );
    });

    test('哈希变化 → 正文与哈希一起更新（不会出现哈希与正文不一致）', () async {
      await store.saveExtraction(
        articleId: articleId,
        extraction: body(text: '第一版正文', hash: 'h1'),
      );
      await store.saveExtraction(
        articleId: articleId,
        extraction: body(text: '修订后的正文', hash: 'h2'),
      );
      final Article row = (await db.select(db.articles).get()).single;
      expect(row.extractedBody, '修订后的正文');
      expect(row.extractedBodyHash, 'h2');
      final ExtractedArticleBody read = (await store.readExtraction(articleId))
          .unwrap()!;
      expect(read.body, '修订后的正文');
      expect(read.bodyHash, 'h2');
    });

    test('只有时间没有正文的行视为「未提取」（不会显示一条空记录）', () async {
      // 直接构造：只写时间，正文为 null。
      await (db.update(
        db.articles,
      )..where(($ArticlesTable a) => a.id.equals(articleId))).write(
        ArticlesCompanion(
          extractedAt: Value<DateTime?>(DateTime.utc(2026, 9, 22)),
        ),
      );
      expect((await store.readExtraction(articleId)).unwrap(), isNull);
    });
  });
}
