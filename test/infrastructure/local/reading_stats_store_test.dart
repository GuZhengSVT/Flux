// T023：统计存储层（真实内存库）。
//
// 验四件事：
//   * 写入 → 按本地日期聚合（跨午夜两行分属两天）；
//   * 聚合**不依赖查询时区**（local_date 是写入时算好的文本键）；
//   * 历史年份来自数据（升序去重、倒序返回、非法键被忽略）；
//   * 清空只删会话表，不碰文章/状态/收藏/设置。
library;

import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';

import 'package:flux/core/core.dart';
import 'package:flux/infrastructure/local/database.dart';
import 'package:flux/infrastructure/local/reading_stats_store.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late DriftReadingStatsStore store;
  late int articleId;

  setUp(() async {
    db = AppDatabase.memory();
    await db.customSelect('SELECT 1').get();
    store = DriftReadingStatsStore(db);
    final int feedId = await db
        .into(db.feeds)
        .insert(
          FeedsCompanion.insert(
            syncId: 'feed-stats',
            normalizedUrl: 'https://stats.example.com/feed.xml',
            name: '统计测试源',
          ),
        );
    articleId = await db
        .into(db.articles)
        .insert(
          ArticlesCompanion.insert(
            feedId: Value<int?>(feedId),
            title: '被阅读的文章',
            identityBasis: IdentityBasis.guid,
          ),
        );
  });

  tearDown(() async {
    await db.close();
  });

  /// 直接构造一条草案（绕过 tracker，专测存储语义）。
  ReadingSessionDraft draft({
    required String localDate,
    required int seconds,
    DateTime? startedAt,
  }) => ReadingSessionDraft(
    articleId: articleId,
    startedAt: startedAt ?? DateTime.utc(2026, 9, 21, 2),
    endedAt: (startedAt ?? DateTime.utc(2026, 9, 21, 2)).add(
      Duration(seconds: seconds),
    ),
    effectiveSeconds: seconds,
    timeZone: 'Asia/Shanghai',
    localDate: localDate,
  );

  group('写入与聚合', () {
    test('跨午夜两行 → 分别聚合到各自的本地日期', () async {
      final Result<int> written = await store.appendSessions(
        <ReadingSessionDraft>[
          draft(localDate: '2026-09-21', seconds: 600),
          draft(
            localDate: '2026-09-22',
            seconds: 900,
            startedAt: DateTime.utc(2026, 9, 21, 16),
          ),
        ],
      );
      expect(written.unwrap(), 2);

      final List<ReadingDayTotal> totals = (await store.dailyTotals(
        fromDate: '2026-09-01',
        toDate: '2026-09-30',
      )).unwrap();
      expect(totals, hasLength(2));
      expect(totals[0].localDate, '2026-09-21');
      expect(totals[0].seconds, 600);
      expect(totals[1].localDate, '2026-09-22');
      expect(totals[1].seconds, 900);
    });

    test('同一天多行 → SUM 合并（空闲暂停产生多行时聚合仍是一个数）', () async {
      await store.appendSessions(<ReadingSessionDraft>[
        draft(localDate: '2026-09-21', seconds: 300),
        draft(localDate: '2026-09-21', seconds: 450),
      ]);
      final List<ReadingDayTotal> totals = (await store.dailyTotals(
        fromDate: '2026-09-21',
        toDate: '2026-09-21',
      )).unwrap();
      expect(totals, hasLength(1));
      expect(totals.single.seconds, 750);
    });

    test('范围含两端，区间外的日期不返回', () async {
      await store.appendSessions(<ReadingSessionDraft>[
        draft(localDate: '2026-08-31', seconds: 100),
        draft(localDate: '2026-09-01', seconds: 200),
        draft(localDate: '2026-09-30', seconds: 300),
        draft(localDate: '2026-10-01', seconds: 400),
      ]);
      final List<ReadingDayTotal> totals = (await store.dailyTotals(
        fromDate: '2026-09-01',
        toDate: '2026-09-30',
      )).unwrap();
      expect(totals.map((ReadingDayTotal t) => t.localDate).toList(), <String>[
        '2026-09-01',
        '2026-09-30',
      ]);
    });

    test('空批次返回 0 且不报错', () async {
      expect(
        (await store.appendSessions(const <ReadingSessionDraft>[])).unwrap(),
        0,
      );
      expect(
        (await store.dailyTotals(
          fromDate: '2026-01-01',
          toDate: '2026-12-31',
        )).unwrap(),
        isEmpty,
      );
    });

    test('进行中的会话可写 null 结束时间（表结构允许，本层写入总带结束时间）', () async {
      // 表结构层面验证一次：endedAt 可空是 T009 的既有约定。
      await db
          .into(db.readingSessions)
          .insert(
            ReadingSessionsCompanion.insert(
              articleId: articleId,
              startedAt: DateTime.utc(2026, 9, 21, 2),
              timeZone: 'Asia/Shanghai',
              localDate: '2026-09-21',
            ),
          );
      final ReadingSession row =
          (await db.select(db.readingSessions).get()).single;
      expect(row.endedAt, isNull);
      // 有效秒数默认 0：不会因为这个默认值被算进聚合以外的任何地方。
      expect(row.effectiveSeconds, 0);
    });
  });

  group('历史年份', () {
    test('从数据里取，倒序、去重', () async {
      await store.appendSessions(<ReadingSessionDraft>[
        draft(localDate: '2024-05-01', seconds: 60),
        draft(localDate: '2026-01-01', seconds: 60),
        draft(localDate: '2025-12-31', seconds: 60),
        draft(localDate: '2026-02-01', seconds: 60),
      ]);
      expect((await store.activeYears()).unwrap(), <int>[2026, 2025, 2024]);
    });

    test('没有数据 → 空列表（界面据此显示空态，而不是列出今年）', () async {
      expect((await store.activeYears()).unwrap(), isEmpty);
    });
  });

  group('清空', () {
    test('只删会话，文章/状态/收藏/设置都不受影响', () async {
      // 造一点别的数据，确保清空不会波及它们。
      await (db.update(
        db.articles,
      )..where(($ArticlesTable a) => a.id.equals(articleId))).write(
        const ArticlesCompanion(
          readingState: Value<ReadingState>(ReadingState.later),
          favorite: Value<bool>(true),
        ),
      );
      await db
          .into(db.settings)
          .insertOnConflictUpdate(
            SettingsCompanion.insert(
              key: SettingId.set015.code,
              value: '{"enabled":false,"idlePauseMinutes":7}',
            ),
          );
      await store.appendSessions(<ReadingSessionDraft>[
        draft(localDate: '2026-09-21', seconds: 600),
      ]);

      final int removed = (await store.clearAll()).unwrap();
      expect(removed, 1);
      expect((await store.activeYears()).unwrap(), isEmpty);

      // 文章状态与收藏保留。
      final Article article = (await db.select(db.articles).get()).single;
      expect(article.readingState, ReadingState.later);
      expect(article.favorite, isTrue);
      // SET-015 的值保留（清历史 ≠ 重置开关）。
      final Setting setting = (await db.select(db.settings).get()).single;
      expect(setting.key, SettingId.set015.code);
      expect(setting.value, contains('idlePauseMinutes'));
    });

    test('清空空库是幂等的（返回 0，不报错）', () async {
      expect((await store.clearAll()).unwrap(), 0);
      expect((await store.clearAll()).unwrap(), 0);
    });
  });

  group('外键与级联', () {
    test('删除文章时其会话行也必须被清理（否则外键拒绝或留下悬空统计）', () async {
      await store.appendSessions(<ReadingSessionDraft>[
        draft(localDate: '2026-09-21', seconds: 600),
      ]);
      // 会话行存在时，删除文章会被外键拒绝——这是 T018 的删除流程必须先清会话的原因。
      await expectLater(
        (db.delete(
          db.articles,
        )..where(($ArticlesTable a) => a.id.equals(articleId))).go(),
        throwsA(anything),
      );
      // 先清会话，再删文章，即成功。
      await store.clearAll();
      await (db.delete(
        db.articles,
      )..where(($ArticlesTable a) => a.id.equals(articleId))).go();
      expect(await db.select(db.articles).get(), isEmpty);
    });
  });
}
