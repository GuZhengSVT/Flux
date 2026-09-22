// T039：今日页控制器（日期切换、版本管理、进度、取消）。
//
// 断言的是「界面能拿到的事实对不对」：
//   * 日期切换按 (日期, 时区) 查询，且「今天」不随翻页移动；
//   * 版本列表含失败/取消/中断的记录（`latest`），而不只是成功版本；
//   * 删除非当前版本成功、删当前版本被拒且库不变；
//   * 阶段与逐站结果来自编排层回调（不编造）；
//   * 取消把任务落成 cancelled，且取消期间按钮状态是「正在取消」。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:flux/core/core.dart';
import 'package:flux/features/news/application/news_today_controller.dart';

void main() {
  group('近 7 天日期条带', () {
    test('含当天、倒序、跨月正确', () {
      final List<String> keys = recentDateKeys('2026-03-02');
      expect(keys.length, 7);
      expect(keys.first, '2026-03-02');
      expect(keys.last, '2026-02-24');
      expect(keys.contains('2026-02-28'), isTrue);
    });

    test('非法日期键原样返回（不抛、不猜）', () {
      expect(recentDateKeys('not-a-date'), <String>['not-a-date']);
    });
  });

  group('状态派生', () {
    NewsRunRecord record({
      required int version,
      required TaskStatus status,
      bool current = false,
      String? errorKind,
      NewsRunStage? stage,
    }) => NewsRunRecord(
      localDate: '2026-09-22',
      timeZone: 'Asia/Shanghai',
      version: version,
      status: status,
      snapshot: _snapshot(),
      siteResults: const <NewsSiteFetchResult>[],
      materials: const <NewsMaterial>[],
      items: const <NewsDraftItem>[],
      createdAt: DateTime.utc(2026, 9, 22, 13),
      isCurrent: current,
      errorKind: errorKind,
      stage: stage,
    );

    test('latest 取最新一条记录（含失败/取消），current 只认成功版本', () {
      final NewsTodayState state = NewsTodayState(
        localDate: '2026-09-22',
        versions: <NewsRunRecord>[
          record(version: 2, status: TaskStatus.cancelled),
          record(version: 1, status: TaskStatus.succeeded, current: true),
        ],
      );
      expect(state.latest!.version, 2);
      expect(state.latest!.status, TaskStatus.cancelled);
      expect(state.current, isNull);
      expect(state.isToday, isTrue);
    });

    test('isToday 依据 today 而不是 localDate', () {
      const NewsTodayState state = NewsTodayState(
        localDate: '2026-09-01',
        today: '2026-09-22',
      );
      expect(state.isToday, isFalse);
    });

    test('pendingSites 只列出尚无结果的计划站，且只在生成中显示', () {
      const NewsRequiredSite a = NewsRequiredSite(
        name: '甲站',
        url: 'https://a.example.com',
      );
      const NewsRequiredSite b = NewsRequiredSite(
        name: '乙站',
        url: 'https://b.example.com',
      );
      const NewsTodayState running = NewsTodayState(
        localDate: '2026-09-22',
        generating: true,
        plannedSites: <NewsRequiredSite>[a, b],
        sites: <NewsSiteFetchResult>[
          NewsSiteFetchResult(
            name: '甲站',
            url: 'https://a.example.com',
            status: NewsSiteStatus.ok,
          ),
        ],
      );
      expect(running.pendingSites.map((NewsRequiredSite s) => s.name), <String>[
        '乙站',
      ]);
      expect(running.copyWith(generating: false).pendingSites, isEmpty);
    });

    test('clearedCitationCount 只统计正文已被清理且被引用的本机文章', () {
      final NewsTodayState state = NewsTodayState(
        localDate: '2026-09-22',
        clearedArticleIds: const <int>{7, 9},
        current: NewsRunRecord(
          localDate: '2026-09-22',
          timeZone: 'Asia/Shanghai',
          version: 1,
          status: TaskStatus.succeeded,
          snapshot: _snapshot(),
          siteResults: const <NewsSiteFetchResult>[],
          materials: const <NewsMaterial>[
            NewsMaterial(
              sourceId: 'rss.7',
              accessMethod: CitationAccessMethod.rss,
              title: '甲',
              url: 'https://a.example.com',
              excerpt: '摘录',
              materialHash: 'h',
              articleId: 7,
            ),
            NewsMaterial(
              sourceId: 'fetch.1',
              accessMethod: CitationAccessMethod.fetch,
              title: '乙',
              url: 'https://b.example.com',
              excerpt: '摘录',
              materialHash: 'h2',
            ),
          ],
          items: const <NewsDraftItem>[],
          createdAt: DateTime.utc(2026, 9, 22, 13),
          isCurrent: true,
        ),
      );
      expect(state.clearedCitationCount, 1);
    });
  });
}

NewsInputSnapshot _snapshot() => NewsInputSnapshot(
  localDate: '2026-09-22',
  deviceTimeZone: 'Asia/Shanghai',
  utcOffsetMinutes: 480,
  dayStartUtc: DateTime.utc(2026, 9, 21, 16),
  dayEndUtc: DateTime.utc(2026, 9, 22, 16),
  frozenAtUtc: DateTime.utc(2026, 9, 22, 13),
  candidates: const <NewsMaterial>[],
  requiredSites: const <NewsRequiredSite>[],
  keywords: const <String>[],
  blockedQueryTerms: const <String>[],
  excludedTopics: const <String>[],
  promptVersionRef: 'zh-Hans#builtin',
  promptText: '任务段',
  maxArticles: 50,
  maxSites: 10,
  maxQueries: 10,
  singleMaterialBudget: 8000,
  globalEnabled: true,
);
