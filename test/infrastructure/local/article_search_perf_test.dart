// T022：全文检索的性能烟测（10000 行文章，P95 < 1s）。
//
// 这个门限是**烟测**而不是性能承诺：它只用来发现「结构性退化」——例如索引没建上
// （退化成全表扫描）、或者 MATCH 路径被换回 LIKE 全扫。绝对耗时随机器差异很大
// （本机 M4 / 16 GiB / debug 模式），因此断言写的是宽松的门限，并在报告里如实记录
// 环境与实测值，不宣称「绝对 1 秒」这种跨环境结论。
library;

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'package:flux/core/core.dart';
import 'package:flux/infrastructure/local/article_search_store.dart';
import 'package:flux/infrastructure/local/database.dart';

/// 数据集规模（手册要求 10000 行）。
const int kArticleCount = 10000;

/// P95 门限。
const Duration kP95Threshold = Duration(seconds: 1);

void main() {
  late AppDatabase db;
  late DriftArticleSearchStore search;

  setUpAll(() async {
    db = AppDatabase.memory();
    await db.customSelect('SELECT 1').get();
    search = DriftArticleSearchStore(db);

    final int feedId = await db
        .into(db.feeds)
        .insert(
          FeedsCompanion.insert(
            syncId: 'bench',
            normalizedUrl: 'https://bench.example.com/feed.xml',
            name: '压测源',
          ),
        );

    // 批量插入放在一个事务里：10000 次单条插入的事务开销会让建索引时间失真。
    // 触发器仍然逐行触发（这正是被测路径：写入时同步索引）。
    final DateTime start = DateTime.now();
    await db.transaction(() async {
      for (int i = 0; i < kArticleCount; i++) {
        await db
            .into(db.articles)
            .insert(
              ArticlesCompanion.insert(
                feedId: Value<int?>(feedId),
                title: '文章 $i 离线阅读与 AI 摘要',
                identityBasis: IdentityBasis.guid,
                guid: Value<String?>('guid-$i'),
                guidPresent: const Value<bool>(true),
                summary: Value<String?>('摘要 $i 关于离线缓存'),
                body: Value<String?>(
                  '正文 $i：本文说明离线阅读的完整实现方式，包含 AI 摘要与缓存设计。'
                  'Offline reading implementation notes for article $i.',
                ),
              ),
            );
      }
    });
    // ignore: avoid_print
    print(
      'PERF build $kArticleCount rows + index: '
      '${DateTime.now().difference(start).inMilliseconds} ms',
    );
  });

  tearDownAll(() async => db.close());

  /// 跑一次检索并返回耗时。
  Future<Duration> timed(String text) async {
    final DateTime start = DateTime.now();
    final Result<SearchPage> result = await search.search(
      SearchQuery(text: text, limit: 50),
    );
    final Duration elapsed = DateTime.now().difference(start);
    expect(result.isOk, isTrue, reason: result.errorOrNull?.message);
    return elapsed;
  }

  test('索引确实建上了（不是空索引）', () async {
    final SearchPage page = await search
        .search(const SearchQuery(text: '离线阅读的完整实现'))
        .then((Result<SearchPage> r) => r.unwrap());
    expect(page.total, kArticleCount, reason: '每篇正文都含这个片段');
  });

  test('MATCH 路径 P95 < 1s（10 次计时）', () async {
    final List<int> samples = <int>[];
    for (int i = 0; i < 10; i++) {
      samples.add((await timed('离线阅读的完整实现')).inMicroseconds);
    }
    samples.sort();
    final double p95 =
        samples[(samples.length * 0.95).floor().clamp(0, samples.length - 1)] /
        1000;
    // ignore: avoid_print
    print(
      'PERF match p95=${p95.toStringAsFixed(1)} ms median=${(samples[5] / 1000).toStringAsFixed(1)} ms',
    );
    expect(p95, lessThan(kP95Threshold.inMilliseconds.toDouble()));
  });

  test('LIKE 路径（短词）P95 < 1s', () async {
    final List<int> samples = <int>[];
    for (int i = 0; i < 10; i++) {
      samples.add((await timed('离线')).inMicroseconds);
    }
    samples.sort();
    final double p95 =
        samples[(samples.length * 0.95).floor().clamp(0, samples.length - 1)] /
        1000;
    // ignore: avoid_print
    print(
      'PERF like p95=${p95.toStringAsFixed(1)} ms median=${(samples[5] / 1000).toStringAsFixed(1)} ms',
    );
    expect(p95, lessThan(kP95Threshold.inMilliseconds.toDouble()));
  });

  test('分页取第二页同样在门限内（offset 不退化）', () async {
    final DateTime start = DateTime.now();
    final Result<SearchPage> result = await search.search(
      const SearchQuery(text: '离线阅读的完整实现', limit: 50, offset: 5000),
    );
    final Duration elapsed = DateTime.now().difference(start);
    // ignore: avoid_print
    print('PERF offset5000 => ${elapsed.inMilliseconds} ms');
    expect(result.isOk, isTrue);
    expect(result.unwrap().hits, hasLength(50));
    expect(elapsed, lessThan(kP95Threshold));
  });

  test('来源名搜索（现查 feeds.name）在门限内', () async {
    final DateTime start = DateTime.now();
    final Result<SearchPage> result = await search.search(
      const SearchQuery(text: '压测源', limit: 50),
    );
    final Duration elapsed = DateTime.now().difference(start);
    // ignore: avoid_print
    print('PERF feedName => ${elapsed.inMilliseconds} ms');
    expect(result.isOk, isTrue);
    expect(elapsed, lessThan(kP95Threshold));
  });
}
