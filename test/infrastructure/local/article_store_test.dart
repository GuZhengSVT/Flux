// T009：文章身份规则与幂等导入事务。
//
// 对应手册 6.3 必测用例「身份」：两个 Feed 的相同 GUID 不合并、同一 Feed/GUID
// 重复导入不新增、带参数 URL 不损坏、正文更新不丢状态。
import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flux/core/core.dart';
import 'package:flux/infrastructure/local/article_store.dart';
import 'package:flux/infrastructure/local/database.dart';
import 'package:flux/infrastructure/local/tables/article_tables.dart';

/// 构造一条带 GUID 的导入项。
ArticleImport _byGuid({
  required int feedId,
  required String guid,
  String title = '标题',
  String? body,
  String? bodyHash,
  String? normalizedLink,
  String? sourceUrl,
}) {
  return ArticleImport(
    feedId: feedId,
    title: title,
    identityBasis: IdentityBasis.guid,
    guid: guid,
    guidPresent: true,
    normalizedLink: normalizedLink,
    sourceUrl: sourceUrl,
    body: body,
    bodyHash: bodyHash,
  );
}

Future<List<Article>> _allArticles(AppDatabase db) =>
    (db.select(db.articles)..orderBy(<OrderClauseGenerator<$ArticlesTable>>[
          (Articles t) => OrderingTerm(expression: t.id),
        ]))
        .get();

void main() {
  late AppDatabase db;
  late int feedA;
  late int feedB;

  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  setUp(() async {
    db = AppDatabase.memory();
    await db.customSelect('SELECT 1').get();

    feedA = await db
        .into(db.feeds)
        .insert(
          FeedsCompanion.insert(
            syncId: 'feed-a',
            normalizedUrl: 'https://a.example.com/feed.xml',
            name: 'A',
          ),
        );
    feedB = await db
        .into(db.feeds)
        .insert(
          FeedsCompanion.insert(
            syncId: 'feed-b',
            normalizedUrl: 'https://b.example.com/feed.xml',
            name: 'B',
          ),
        );
  });

  tearDown(() async {
    await db.close();
  });

  group('身份规则（架构 4.1）', () {
    test('同一 Feed + 同一 GUID 重复导入不新增行', () async {
      final Result<ArticleImportOutcome> first = await db.upsertArticles(
        <ArticleImport>[_byGuid(feedId: feedA, guid: 'g-1', title: '第一版')],
      );
      expect(first.isOk, isTrue);
      expect(first.unwrap().inserted, 1);

      final Result<ArticleImportOutcome> second = await db.upsertArticles(
        <ArticleImport>[_byGuid(feedId: feedA, guid: 'g-1', title: '第一版')],
      );
      // 内容完全相同：不改库、不推进 updatedAt。
      expect(second.unwrap().inserted, 0);
      expect(second.unwrap().unchanged, 1);
      expect(second.unwrap().updated, 0);

      expect(await _allArticles(db), hasLength(1));
    });

    test('两个 Feed 的相同 GUID 不合并', () async {
      await db.upsertArticles(<ArticleImport>[
        _byGuid(feedId: feedA, guid: 'shared-guid'),
      ]);
      await db.upsertArticles(<ArticleImport>[
        _byGuid(feedId: feedB, guid: 'shared-guid'),
      ]);

      final List<Article> all = await _allArticles(db);
      expect(all, hasLength(2));
      expect(all.map((Article a) => a.feedId).toSet(), <int>{feedA, feedB});
    });

    test('无 GUID 时按规范化链接识别；不同链接是不同文章', () async {
      final ArticleImport one = ArticleImport(
        feedId: feedA,
        title: '无 GUID 一',
        identityBasis: IdentityBasis.normalizedLink,
        normalizedLink: 'https://a.example.com/post/1',
      );
      await db.upsertArticles(<ArticleImport>[one]);

      // 同链接再次导入：命中同一行。
      await db.upsertArticles(<ArticleImport>[one]);
      expect(await _allArticles(db), hasLength(1));

      // 另一个链接：新增。
      await db.upsertArticles(<ArticleImport>[
        ArticleImport(
          feedId: feedA,
          title: '无 GUID 二',
          identityBasis: IdentityBasis.normalizedLink,
          normalizedLink: 'https://a.example.com/post/2',
        ),
      ]);
      expect(await _allArticles(db), hasLength(2));
    });

    test('既无 GUID 也无链接时按来源/标题/时间指纹兜底，并保留可靠度诊断', () async {
      final ArticleImport fp = ArticleImport(
        feedId: feedA,
        title: '指纹文章',
        identityBasis: IdentityBasis.fingerprint,
        fallbackFingerprint: 'a.example.com|指纹文章|2026-09-01T00:00:00Z',
        fingerprintReliability: FingerprintReliability.reliable,
      );
      await db.upsertArticles(<ArticleImport>[fp]);
      await db.upsertArticles(<ArticleImport>[fp]);
      expect(await _allArticles(db), hasLength(1));

      // 不可靠指纹（发布时间缺失）同样能入库，但可靠度被记录，供同步阶段避免误合并。
      final Result<ArticleImportOutcome> unreliable = await db.upsertArticles(
        <ArticleImport>[
          ArticleImport(
            feedId: feedA,
            title: '另一个指纹文章',
            identityBasis: IdentityBasis.fingerprint,
            fallbackFingerprint: 'a.example.com|另一个指纹文章|',
            fingerprintReliability: FingerprintReliability.unreliable,
          ),
        ],
      );
      expect(unreliable.isOk, isTrue);

      final Article stored = (await _allArticles(db)).last;
      expect(stored.fingerprintReliability, FingerprintReliability.unreliable);
    });

    test('无 GUID/链接的行不会因为 null 互相冲突', () async {
      for (int i = 0; i < 3; i++) {
        final Result<ArticleImportOutcome> result = await db.upsertArticles(
          <ArticleImport>[
            ArticleImport(
              feedId: feedA,
              title: '指纹空值 $i',
              identityBasis: IdentityBasis.fingerprint,
              fallbackFingerprint: 'fp-$i',
            ),
          ],
        );
        expect(result.isOk, isTrue, reason: result.errorOrNull?.message);
      }
      expect(await _allArticles(db), hasLength(3));
    });

    test('带查询参数的原始链接被完整保留，不被规范化结果覆盖', () async {
      const String raw =
          'https://a.example.com/post/1?utm_source=rss&id=42&sig=abc';
      await db.upsertArticles(<ArticleImport>[
        ArticleImport(
          feedId: feedA,
          title: '带参数',
          identityBasis: IdentityBasis.guid,
          guid: 'g-params',
          guidPresent: true,
          normalizedLink: 'https://a.example.com/post/1?id=42',
          sourceUrl: raw,
        ),
      ]);

      final Article stored = (await _allArticles(db)).single;
      expect(stored.sourceUrl, raw, reason: '外开链接必须保留源参数');
      expect(stored.normalizedLink, 'https://a.example.com/post/1?id=42');
    });
  });

  group('幂等导入与状态保留', () {
    test('正文哈希变化才更新正文，且保留阅读状态与收藏', () async {
      await db.upsertArticles(<ArticleImport>[
        _byGuid(
          feedId: feedA,
          guid: 'g-rev',
          title: '修订测试',
          body: '原始正文',
          bodyHash: 'hash-1',
        ),
      ]);

      // 用户把它标为 later 并收藏。
      final Article before = (await _allArticles(db)).single;
      await (db.update(
        db.articles,
      )..where((Articles t) => t.id.equals(before.id))).write(
        const ArticlesCompanion(
          readingState: Value<ReadingState>(ReadingState.later),
          favorite: Value<bool>(true),
        ),
      );

      // 同一哈希再次导入：正文不重写。
      final Result<ArticleImportOutcome> sameHash = await db.upsertArticles(
        <ArticleImport>[
          _byGuid(
            feedId: feedA,
            guid: 'g-rev',
            title: '修订测试',
            body: '原始正文',
            bodyHash: 'hash-1',
          ),
        ],
      );
      expect(sameHash.unwrap().bodyUpdated, 0);

      // 哈希变化：正文被替换。
      final Result<ArticleImportOutcome> changed = await db.upsertArticles(
        <ArticleImport>[
          _byGuid(
            feedId: feedA,
            guid: 'g-rev',
            title: '修订测试（更新）',
            body: '更新后的正文',
            bodyHash: 'hash-2',
          ),
        ],
      );
      expect(changed.unwrap().bodyUpdated, 1);

      final Article after = (await _allArticles(db)).single;
      expect(after.body, '更新后的正文');
      expect(after.bodyHash, 'hash-2');
      expect(after.title, '修订测试（更新）');
      // 身份规则：正文更新**不丢状态**；later 不会被刷回 unread。
      expect(after.readingState, ReadingState.later);
      expect(after.favorite, isTrue);
    });

    test('导入不携带正文哈希时不擦除已存正文（只有摘要的刷新场景）', () async {
      await db.upsertArticles(<ArticleImport>[
        _byGuid(
          feedId: feedA,
          guid: 'g-keep',
          title: '保留正文',
          body: '完整正文',
          bodyHash: 'hash-x',
        ),
      ]);

      // 后续刷新只拿到标题与摘要（hash 为 null）：正文必须保留。
      await db.upsertArticles(<ArticleImport>[
        ArticleImport(
          feedId: feedA,
          title: '保留正文',
          identityBasis: IdentityBasis.guid,
          guid: 'g-keep',
          guidPresent: true,
          summary: '仅有摘要',
          bodyCompleteness: BodyCompleteness.summaryOnly,
        ),
      ]);

      final Article stored = (await _allArticles(db)).single;
      expect(stored.body, '完整正文');
      expect(stored.bodyHash, 'hash-x');
      expect(stored.summary, '仅有摘要');
    });

    test('新增行的阅读状态与收藏使用默认值', () async {
      await db.upsertArticles(<ArticleImport>[
        _byGuid(feedId: feedA, guid: 'g-default'),
      ]);
      final Article stored = (await _allArticles(db)).single;
      expect(stored.readingState, ReadingState.unread);
      expect(stored.favorite, isFalse);
      expect(stored.bodyCompleteness, BodyCompleteness.unknown);
    });

    test('重复导入同一批次是幂等的（行数与状态都不变）', () async {
      final List<ArticleImport> batch = <ArticleImport>[
        _byGuid(feedId: feedA, guid: 'b-1', title: '一', bodyHash: 'h1'),
        _byGuid(feedId: feedA, guid: 'b-2', title: '二', bodyHash: 'h2'),
        ArticleImport(
          feedId: feedA,
          title: '三',
          identityBasis: IdentityBasis.normalizedLink,
          normalizedLink: 'https://a.example.com/post/3',
        ),
      ];

      final Result<ArticleImportOutcome> first = await db.upsertArticles(batch);
      expect(first.unwrap().inserted, 3);

      final List<Article> snapshot = await _allArticles(db);
      final Result<ArticleImportOutcome> again = await db.upsertArticles(batch);
      expect(again.unwrap().inserted, 0);
      expect(again.unwrap().unchanged, 3);
      expect(again.unwrap().updated, 0);

      final List<Article> after = await _allArticles(db);
      expect(after, hasLength(3));
      // updatedAt 未被推进：证明“无变化就不写”。
      for (int i = 0; i < after.length; i++) {
        expect(after[i].updatedAt, snapshot[i].updatedAt);
      }
    });

    test('批次中任一条失败则整批回滚（事务原子性）', () async {
      const int nonExistentFeed = 999999;
      final Result<ArticleImportOutcome> result = await db.upsertArticles(
        <ArticleImport>[
          _byGuid(feedId: feedA, guid: 'ok-1'),
          // 外键约束会拒绝这一条；整批必须回滚，不能留下半批数据。
          _byGuid(feedId: nonExistentFeed, guid: 'bad-1'),
        ],
      );

      expect(result.isErr, isTrue);
      expect(result.errorOrNull, isA<StorageError>());
      expect(await _allArticles(db), isEmpty, reason: '失败批次不得留下部分数据');
    });
  });
}
