// 真实源端到端最小验证（T013 第 7 条；用户已授权从 chinese-independent-blogs 列表验证）。
//
// 这是本任务**唯一**联网的测试，因此按手册 6.2 的约定单独标记：
//   - 默认**跳过**，只有显式带 `--dart-define=FLUX_LIVE_FEED=1` 时才执行，
//     避免 CI 与日常 `flutter test` 依赖外部网络（那会让「测试通过」变得不可复现）；
//   - 串行、带项目 UA（礼貌抓取，不并发压源站）；
//   - 只断言结构性事实（文章数 > 0、二次抓取 304 或幂等无重复），**不**断言具体内容：
//     源会更新，把内容写进断言等于让测试随外部世界随机变红。
//
// 实测记录（2026-09-21，本机 macOS）见 docs/Flux_AI开发手册.md 的 T013 条目。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:flux/core/core.dart';
import 'package:flux/features/feeds/application/refresh_feed.dart';
import 'package:flux/infrastructure/local/database.dart';
import 'package:flux/infrastructure/local/feed_store_adapter.dart';
import 'package:flux/infrastructure/network/feed_fetcher.dart';

/// 是否执行联网验证（默认关闭）。
///
/// 用 String.fromEnvironment 而不是 bool.fromEnvironment：后者只认字面量 'true'/'false'，
/// 传 `--dart-define=FLUX_LIVE_FEED=1` 会被**静默**当成 false，测试照旧跳过——
/// 那种「以为跑了其实没跑」是这里最不该出现的状态。
const String _liveFlag = String.fromEnvironment('FLUX_LIVE_FEED');

/// 是否已显式开启联网验证。
bool get _live => _liveFlag == '1' || _liveFlag.toLowerCase() == 'true';

/// 从 chinese-independent-blogs 列表挑的源（T003 已人工验证过可访问）。
const List<String> _sources = <String>[
  'https://blog.t9t.io/atom.xml',
  'https://reorx.com/feed.xml',
];

void main() {
  group('真实源端到端（需 --dart-define=FLUX_LIVE_FEED=1）', () {
    for (final String source in _sources) {
      test('抓取→解析→清洗→入库：$source', () async {
        if (!_live) {
          markTestSkipped('未设置 FLUX_LIVE_FEED=1，跳过联网验证');
          return;
        }

        final AppDatabase db = AppDatabase.memory();
        await db.customSelect('SELECT 1').get();
        addTearDown(db.close);

        final int feedId = await db
            .into(db.feeds)
            .insert(
              FeedsCompanion.insert(
                syncId: 'live-$source',
                normalizedUrl: source,
                name: '真实源',
              ),
            );

        // 串行、单请求（并发上限设为 1，明确表达「不压源站」）。
        final FeedFetcher fetcher = HttpFeedFetcher(
          config: const FeedFetchConfig(
            maxConcurrency: 1,
            timeout: Duration(seconds: 30),
          ),
        );
        final RefreshFeedUseCase useCase = RefreshFeedUseCase(
          fetcher: fetcher,
          store: DriftFeedArticleStore(db),
        );

        // ---- 第一次抓取 -------------------------------------------------
        final FeedRefreshResult first = await useCase(
          FeedRefreshRequest(
            feedId: feedId,
            url: Uri.parse(source),
            feedName: '真实源',
          ),
        );
        expect(first.error, isNull, reason: '抓取失败：${first.error?.message}');
        expect(
          first.outcome,
          isNot(FeedRefreshOutcome.networkFailed),
          reason: '网络失败：${first.error?.message}',
        );
        expect(first.fetchedEntries, greaterThan(0), reason: '源应有条目');
        expect(first.inserted, greaterThan(0), reason: '首次抓取应入库文章');

        final List<Article> afterFirst = await db.select(db.articles).get();
        expect(afterFirst, isNotEmpty);
        // 至少要有一篇有正文（源只给摘要时摘要也算内容）。
        expect(
          afterFirst.any(
            (Article a) =>
                (a.body != null && a.body!.isNotEmpty) ||
                (a.summary != null && a.summary!.isNotEmpty),
          ),
          isTrue,
          reason: '入库文章应有可见内容（正文或摘要）',
        );
        // 身份必须有依据：GUID、规范化链接或指纹之一。
        for (final Article article in afterFirst) {
          final bool hasIdentity =
              (article.guid != null && article.guid!.isNotEmpty) ||
              (article.normalizedLink != null &&
                  article.normalizedLink!.isNotEmpty) ||
              (article.fallbackFingerprint != null &&
                  article.fallbackFingerprint!.isNotEmpty);
          expect(hasIdentity, isTrue, reason: '每篇文章都应有身份依据');
        }

        // ---- 第二次抓取：必须 304 或幂等（不产生重复） ---------------------
        final Feed feed = (await db.select(db.feeds).get()).single;
        final FeedRefreshResult second = await useCase(
          FeedRefreshRequest(
            feedId: feedId,
            url: Uri.parse(source),
            feedName: '真实源',
            etag: feed.httpEtag,
            lastModified: feed.httpLastModified,
          ),
        );
        expect(second.error, isNull, reason: '第二次抓取失败');

        final List<Article> afterSecond = await db.select(db.articles).get();
        expect(
          afterSecond.length,
          afterFirst.length,
          reason:
              '二次抓取产生了重复行：结果=${second.outcome.name} '
              'inserted=${second.inserted}（既非 304 也非幂等）',
        );
        // 明确记录到底走了哪条路径，便于人工核对。
        stdout.writeln(
          '[T013 实测] $source 首次=${first.outcome.name}/'
          '${afterFirst.length} 篇；二次=${second.outcome.name}/'
          '${afterSecond.length} 篇；etag=${feed.httpEtag != null}',
        );
      });
    }
  });
}
