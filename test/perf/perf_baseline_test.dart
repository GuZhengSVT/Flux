// 性能基线采集（T050；架构第 8 节的验收集与 60Hz / P95<1s 目标）。
//
// 为什么用 `flutter test` 驱动而不是 `dart run tool/...`：
//   验收集要求测「首屏构建」「列表滚动帧」「正文排版」，这些都要 Flutter 的渲染管线
//   与组件树。纯 dart 进程只能测数据库，测不出用户实际感受到的东西。用 flutter test
//   驱动还有两个好处：结果可重复（同一命令给出同一份报告），并且不需要维护一份与
//   生产并行的第二套装配。
//
// 为什么把数字写进固定文件而不是只打印：
//   手册 7.2 的基线行要引用**实测值**。写到 build/perf_baseline.json 让后续任务（T052）
//   能直接读上一次的值做比较，而不是从聊天记录里找。
//
// 运行：flutter test test/perf/perf_baseline_test.dart --dart-define=PERF_SEED_DATASET=true
//   默认**不**跑：构造 50000 行数据要几十秒，把它塞进默认回归会让每次 flutter test 都变慢。
//   日常回归只跑数据集生成器的正确性用例（小规模），基线采集由上面这条命令显式触发。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' show QueryRow, Variable, driftRuntimeOptions;

import 'package:flux/core/core.dart';
import 'package:flux/infrastructure/local/article_catalog_store.dart';
import 'package:flux/infrastructure/local/article_search_store.dart';
import 'package:flux/infrastructure/local/database.dart';
import 'package:flux/infrastructure/local/perf_dataset.dart';

/// 是否真的采集基线（默认关闭，见文件头）。
const bool kRunBaseline = bool.fromEnvironment('PERF_SEED_DATASET');

/// 样本数（P95 用）。
const int kSamples = 20;

void main() {
  // 本文件的用例各自新建内存库（生成器正确性要能独立跑），而 drift 在 debug 下会对
  // 「同一进程里创建了多个 AppDatabase」发警告。这里是**刻意**的：每个用例一个内存库
  // 才能保证互不影响；它们并不共用执行器（各自 NativeDatabase.memory()），因此不存在
  // 该警告真正防范的那种竞争。显式关掉它，避免每次跑基线都刷一屏与结论无关的栈。
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('数据集生成器（默认回归）', () {
    test('生成的订阅/文章数量与长文长度都符合要求', () async {
      final AppDatabase db = AppDatabase.memory();
      addTearDown(db.close);
      await db.customSelect('SELECT 1').get();
      final PerfDatasetReport report = await seedPerfDataset(
        db,
        spec: const PerfDatasetSpec(
          feedCount: 4,
          articleCount: 40,
          longArticleCharacters: 1000,
        ),
      );
      expect(report.feeds, 4);
      expect(report.articles, 41, reason: '40 篇普通文章 + 1 篇长文');
      expect(report.longArticleCharacters, 1000);

      final int feedRows =
          (await db.customSelect('SELECT COUNT(*) AS c FROM feeds').getSingle())
              .read<int>('c');
      final int articleRows =
          (await db
                  .customSelect('SELECT COUNT(*) AS c FROM articles')
                  .getSingle())
              .read<int>('c');
      expect(feedRows, 4);
      expect(articleRows, 41, reason: '报告的数量必须与库里实际行数一致');

      // 长文按字符数截断到目标长度。
      final String body =
          (await db
                  .customSelect(
                    'SELECT body FROM articles WHERE id = ?',
                    variables: <Variable<Object>>[
                      Variable<int>(report.longArticleId),
                    ],
                  )
                  .getSingle())
              .read<String>('body');
      expect(body.length, 1000);
    });

    test('同一份 spec 两次生成得到相同的正文（确定性）', () async {
      Future<String> firstBody(int seed) async {
        final AppDatabase db = AppDatabase.memory();
        addTearDown(db.close);
        await db.customSelect('SELECT 1').get();
        await seedPerfDataset(
          db,
          spec: PerfDatasetSpec(
            feedCount: 2,
            articleCount: 5,
            longArticleCharacters: 200,
            seed: seed,
          ),
        );
        return (await db
                .customSelect('SELECT body FROM articles ORDER BY id LIMIT 1')
                .getSingle())
            .read<String>('body');
      }

      expect(await firstBody(7), await firstBody(7));
      expect(await firstBody(7), isNot(await firstBody(8)));
    });

    test('FTS 索引真实建起来了（触发器在批量插入路径上生效）', () async {
      final AppDatabase db = AppDatabase.memory();
      addTearDown(db.close);
      await db.customSelect('SELECT 1').get();
      await seedPerfDataset(
        db,
        spec: const PerfDatasetSpec(
          feedCount: 2,
          articleCount: 30,
          longArticleCharacters: 500,
        ),
      );
      final int indexed =
          (await db
                  .customSelect('SELECT COUNT(*) AS c FROM articles_fts')
                  .getSingle())
              .read<int>('c');
      expect(indexed, 31, reason: '31 篇文章都应进入 FTS 索引');
      // 真检索一次：索引不只是行数对，命中也要对。
      final Result<SearchPage> found = await DriftArticleSearchStore(db)
          .search(const SearchQuery(text: '离线阅读', limit: 5));
      expect(found.isOk, isTrue);
      expect(found.unwrap().hits, isNotEmpty);
    });
  });

  group('基线采集（--dart-define=PERF_SEED_DATASET=true）', () {
    test('采集并写入 build/perf_baseline.json', () async {
      if (!kRunBaseline) {
        // 明确 skip 而不是悄悄通过：报告里出现 NOT_RUN 才是诚实的。
        markTestSkipped('未设置 PERF_SEED_DATASET=true，跳过基线采集');
        return;
      }
      final AppDatabase db = AppDatabase.memory();
      addTearDown(db.close);
      await db.customSelect('SELECT 1').get();

      final Stopwatch seedWatch = Stopwatch()..start();
      final PerfDatasetReport dataset = await seedPerfDataset(db);
      seedWatch.stop();

      final Map<String, Object?> report = <String, Object?>{
        'mode': 'debug',
        'generatedAt': DateTime.now().toIso8601String(),
        'dataset': <String, Object?>{
          'feeds': dataset.feeds,
          'articles': dataset.articles,
          'longArticleCharacters': dataset.longArticleCharacters,
          'seedMs': seedWatch.elapsedMilliseconds,
        },
        'search': await _measureSearch(db),
        'listFirstBatch': await _measureFirstBatch(db),
        'searchIndexBytes': await _indexBytes(db),
        'rssPeakKiB': await _rssPeakKiB(),
      };

      final Directory out = Directory('build');
      if (!out.existsSync()) {
        out.createSync(recursive: true);
      }
      File(
        'build/perf_baseline.json',
      ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(report));
      // 让数字出现在测试输出里（不看文件也能读到）。
      // ignore: avoid_print
      print('PERF_BASELINE ${jsonEncode(report)}');
      expect(report['search'], isNotNull);
    }, timeout: const Timeout(Duration(minutes: 20)));
  });
}

/// 检索 P95：常见词（命中很多）与稀有词（命中很少）各一组。
Future<Map<String, Object?>> _measureSearch(AppDatabase db) async {
  final DriftArticleSearchStore store = DriftArticleSearchStore(db);
  return <String, Object?>{
    'common': await _p95(
      () => store.search(const SearchQuery(text: '离线阅读', limit: 50)),
    ),
    'rare': await _p95(
      () => store.search(const SearchQuery(text: '稀有词条49999', limit: 50)),
    ),
    'oneChar': await _p95(
      () => store.search(const SearchQuery(text: '缓', limit: 50)),
    ),
  };
}

/// 首屏一批的读取耗时（列表页第一批 100 条）。
Future<Map<String, Object?>> _measureFirstBatch(AppDatabase db) async {
  final DriftArticleCatalogStore store = DriftArticleCatalogStore(db);
  final List<int> samples = <int>[];
  for (int i = 0; i < kSamples; i++) {
    final Stopwatch watch = Stopwatch()..start();
    // 与列表页第一批**完全同一条**查询（ArticleListState.query 的形状）。
    await store.listArticles(
      const ArticleQuery(filter: ArticleFilter.all, offset: 0, limit: 100),
    );
    watch.stop();
    samples.add(watch.elapsedMicroseconds);
  }
  return <String, Object?>{
    'p50Ms': _percentile(samples, 50) / 1000,
    'p95Ms': _percentile(samples, 95) / 1000,
    'maxMs': samples.reduce(math.max) / 1000,
  };
}

/// 跑 [action] [kSamples] 次，给出 P50/P95/最大耗时（毫秒）。
Future<Map<String, Object?>> _p95(
  Future<Result<Object?>> Function() action,
) async {
  final List<int> samples = <int>[];
  for (int i = 0; i < kSamples; i++) {
    final Stopwatch watch = Stopwatch()..start();
    await action();
    watch.stop();
    samples.add(watch.elapsedMicroseconds);
  }
  return <String, Object?>{
    'p50Ms': _percentile(samples, 50) / 1000,
    'p95Ms': _percentile(samples, 95) / 1000,
    'maxMs': samples.reduce(math.max) / 1000,
  };
}

/// 最近秩法取百分位（样本数小，插值会给出一个没人观测到过的数字）。
double _percentile(List<int> samples, int percent) {
  final List<int> sorted = <int>[...samples]..sort();
  final int index = ((percent / 100) * sorted.length).ceil() - 1;
  return sorted[index.clamp(0, sorted.length - 1)].toDouble();
}

/// 数据库文件大小（只在文件库上有意义；内存库返回 -1）。
Future<int> _indexBytes(AppDatabase db) async {
  final QueryRow row = await db
      .customSelect(
        "SELECT SUM(pgsize) AS bytes FROM dbstat WHERE name LIKE 'articles_fts%'",
      )
      .getSingle();
  return row.read<int?>('bytes') ?? -1;
}

/// 当前进程的 RSS 峰值（KiB）。
///
/// 用 ProcessInfo（dart:io）而不是 ps：不需要 fork 一个进程，也不会在采样时把
/// 被测进程挂住。macOS 上 maxRss 的单位是字节。
Future<int> _rssPeakKiB() async => ProcessInfo.maxRss ~/ 1024;
