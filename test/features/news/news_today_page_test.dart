// T038：今日页的界面（架构 4.4 的日期/进度/结果/版本与引用跳转）。
//
// 断言的是「界面有没有如实说出事实」：
//   - 没有版本时是空态而不是假条目；
//   - 未配置模型/搜索时的失败原因能被读出来；
//   - 证据标签与被退回的条目都出现在界面上（不隐藏对用户不利的信息）；
//   - 版本切换入口只在该日期真有多个版本时出现。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:flux/core/core.dart';
import 'package:flux/features/ai/application/ai_task_providers.dart';
import 'package:flux/features/ai/application/model_manager.dart'
    show SettingsReader;
import 'package:flux/features/articles/application/article_ai_providers.dart'
    show summaryZoneProvider;
import 'package:flux/features/news/application/news_run_providers.dart';
import 'package:flux/features/news/application/news_today_controller.dart';
import 'package:flux/features/news/presentation/news_today_page.dart';
import 'package:flux/infrastructure/local/database.dart';
import 'package:flux/infrastructure/local/news_run_store.dart';

import '../../app/test_harness.dart';

/// 固定 +8 时区（与其它新闻用例同一约定）。
const SessionLocalZone shanghai = FixedOffsetZone(
  Duration(hours: 8),
  ianaName: 'Asia/Shanghai',
);

/// 只读设置端口替身（费用确认要读 SET-060 的上限）。
final class FakeSettingsReader implements SettingsReader {
  @override
  Future<Result<Object?>> readSetting(SettingId id) async =>
      Ok<Object?>(SettingRegistry.findById(id)?.defaultValue);
}

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.memory();
    await db.customSelect('SELECT 1').get();
  });

  tearDown(() async {
    await db.close();
  });

  NewsInputSnapshot snapshot() => NewsInputSnapshot(
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
    promptText: '任务段\n\n引用协议',
    maxArticles: 50,
    maxSites: 10,
    maxQueries: 10,
    singleMaterialBudget: 8000,
    globalEnabled: true,
  );

  NewsMaterial material({String sourceId = 'rss.1'}) => NewsMaterial(
    sourceId: sourceId,
    accessMethod: CitationAccessMethod.rss,
    title: '本机文章标题',
    url: 'https://example.com/1',
    excerpt: '正文前段。',
    materialHash: 'h1',
    accessedAt: DateTime.utc(2026, 9, 22, 13),
    articleId: 1,
  );

  Future<void> seed({
    required int version,
    required bool current,
    List<NewsDraftItem> items = const <NewsDraftItem>[],
    List<NewsSiteFetchResult> sites = const <NewsSiteFetchResult>[],
    String? verificationMethod,
  }) async {
    final DriftNewsRunStore store = DriftNewsRunStore(db);
    await store.append(
      NewsRunRecord(
        localDate: '2026-09-22',
        timeZone: 'Asia/Shanghai',
        version: version,
        status: TaskStatus.succeeded,
        snapshot: snapshot(),
        siteResults: sites,
        materials: <NewsMaterial>[material()],
        items: items.isEmpty
            ? <NewsDraftItem>[
                NewsDraftItem(
                  index: 1,
                  text: '某地发生某事。',
                  sourceIds: const <String>['rss.1'],
                  status: NewsItemStatus.kept,
                  labels: verificationMethod == null
                      ? const <NewsEvidenceLabel>[]
                      : const <NewsEvidenceLabel>[
                          NewsEvidenceLabel.singleSource,
                        ],
                  independentSourceCount: 1,
                ),
              ]
            : items,
        createdAt: DateTime.utc(2026, 9, 22, 13, version),
        isCurrent: current,
        providerAlias: 'deepseek',
        modelId: 'deepseek-chat',
        verificationMethod: verificationMethod,
      ),
    );
  }

  Widget wrap(Widget child, {SettingsReader? reader}) => wrapFluxApp(
    child: Material(child: child),
    overrides: <Override>[
      newsRunStoreProvider.overrideWithValue(DriftNewsRunStore(db)),
      summaryZoneProvider.overrideWithValue(shanghai),
      aiTaskClockProvider.overrideWithValue(
        FakeClock(start: DateTime.utc(2026, 9, 22, 13)),
      ),
      newsSettingsReaderProvider.overrideWithValue(
        reader ?? FakeSettingsReader(),
      ),
    ],
    localeOverride: const Locale('zh'),
  );

  group('空态与失败（架构 4.4「不编造内容」）', () {
    testWidgets('没有版本时显示空态与「不会编造内容」说明', (WidgetTester tester) async {
      await tester.pumpWidget(wrap(const NewsTodayPage()));
      await tester.pumpAndSettle();

      expect(find.text('这一天还没有新闻'), findsOneWidget);
      expect(find.textContaining('不会编造内容'), findsOneWidget);
      // 日期显示与生成按钮都在（生成入口不能因为没内容而消失）。
      expect(find.text('2026-09-22'), findsWidgets);
      expect(find.text('生成今天的新闻'), findsOneWidget);
    });

    testWidgets('没有成功版本时按钮是「生成」，有版本时变成「再生成一次」', (WidgetTester tester) async {
      await seed(version: 1, current: true);
      await tester.pumpWidget(wrap(const NewsTodayPage()));
      await tester.pumpAndSettle();

      expect(find.text('再生成一次'), findsOneWidget);
      expect(find.text('生成今天的新闻'), findsNothing);
    });
  });

  group('结果条目与证据标签（架构 4.4）', () {
    testWidgets('条目文本与证据标签同时显示，标签说明通过提示给出', (WidgetTester tester) async {
      await seed(
        version: 1,
        current: true,
        verificationMethod: 'search=yes queries=1 results=3',
      );
      await tester.pumpWidget(wrap(const NewsTodayPage()));
      await tester.pumpAndSettle();

      expect(find.text('某地发生某事。'), findsOneWidget);
      expect(find.text('来源单一'), findsOneWidget);
      expect(find.textContaining('核验方法：search=yes'), findsOneWidget);
      expect(find.textContaining('模型：deepseek/deepseek-chat'), findsOneWidget);
    });

    testWidgets('被退回的条目如实列出，不隐藏「模型编造引用」这件事', (WidgetTester tester) async {
      await seed(
        version: 1,
        current: true,
        items: const <NewsDraftItem>[
          NewsDraftItem(
            index: 1,
            text: '假事。',
            sourceIds: <String>[],
            status: NewsItemStatus.rejectedUnknownCitation,
            unknownSourceIds: <String>['rss.999'],
          ),
        ],
      );
      await tester.pumpWidget(wrap(const NewsTodayPage()));
      await tester.pumpAndSettle();

      expect(find.textContaining('rss.999'), findsWidgets);
      expect(find.textContaining('相关条目已退回'), findsOneWidget);
    });

    testWidgets('必访站逐站状态显示成功与失败两种', (WidgetTester tester) async {
      await seed(
        version: 1,
        current: true,
        sites: const <NewsSiteFetchResult>[
          NewsSiteFetchResult(
            name: '甲站',
            url: 'https://a.example.com',
            status: NewsSiteStatus.ok,
            charCount: 1234,
          ),
          NewsSiteFetchResult(
            name: '乙站',
            url: 'https://b.example.com',
            status: NewsSiteStatus.timeout,
          ),
        ],
      );
      await tester.pumpWidget(wrap(const NewsTodayPage()));
      await tester.pumpAndSettle();

      expect(find.textContaining('甲站'), findsOneWidget);
      expect(find.textContaining('已获取（1234 字符）'), findsOneWidget);
      expect(find.textContaining('乙站'), findsOneWidget);
      expect(find.textContaining('超时未完成'), findsOneWidget);
    });

    testWidgets('引用条目带获取方式与本机文章跳转入口', (WidgetTester tester) async {
      await seed(version: 1, current: true);
      await tester.pumpWidget(wrap(const NewsTodayPage()));
      await tester.pumpAndSettle();

      expect(find.textContaining('RSS·rss.1'), findsOneWidget);
      expect(find.byIcon(Icons.article_outlined), findsWidgets);
    });
  });

  group('历史版本（架构 4.4）', () {
    testWidgets('只有一个版本时不显示版本切换区', (WidgetTester tester) async {
      await seed(version: 1, current: true);
      await tester.pumpWidget(wrap(const NewsTodayPage()));
      await tester.pumpAndSettle();

      expect(find.text('历史版本'), findsNothing);
    });

    testWidgets('多个版本时显示列表，并标出当前版本与切换入口', (WidgetTester tester) async {
      await seed(version: 1, current: false);
      await seed(
        version: 2,
        current: true,
        verificationMethod: 'search=yes queries=1 results=3',
      );
      await tester.pumpWidget(wrap(const NewsTodayPage()));
      await tester.pumpAndSettle();

      expect(find.text('历史版本'), findsOneWidget);
      expect(find.text('当前展示'), findsOneWidget);
      expect(find.text('切换到这一版'), findsOneWidget);
      // 初稿版本与核验后版本可分辨。
      expect(find.textContaining('初稿'), findsOneWidget);
      expect(find.textContaining('核验后'), findsOneWidget);
    });
  });

  group('费用与数据发送确认（SET-042/066）', () {
    testWidgets('点生成先弹确认框，说明上限、费用与数据发送；取消则不生成', (WidgetTester tester) async {
      await tester.pumpWidget(wrap(const NewsTodayPage()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('生成今天的新闻'));
      await tester.pumpAndSettle();

      expect(find.text('确认生成（会产生费用）'), findsOneWidget);
      expect(find.textContaining('可能产生费用'), findsOneWidget);
      expect(find.textContaining('真实的网络请求与数据发送'), findsOneWidget);

      await tester.tap(find.text('先不生成'));
      await tester.pumpAndSettle();
      expect(find.text('确认生成（会产生费用）'), findsNothing);
      // 取消后仍是空态：一次取消不得留下任何痕迹。
      expect(find.text('这一天还没有新闻'), findsOneWidget);
    });

    testWidgets('已有版本时确认框额外说明「再生成一次会再次产生费用」', (WidgetTester tester) async {
      await seed(version: 1, current: true);
      await tester.pumpWidget(wrap(const NewsTodayPage()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('再生成一次'));
      await tester.pumpAndSettle();

      expect(find.textContaining('再生成一次会新增一个版本'), findsOneWidget);
    });
  });

  group('日期切换', () {
    testWidgets('前一天/后一天按钮改变查询日期（不读系统时区）', (WidgetTester tester) async {
      await tester.pumpWidget(wrap(const NewsTodayPage()));
      await tester.pumpAndSettle();
      expect(find.text('2026-09-22'), findsWidgets);

      await tester.tap(find.byTooltip('前一天'));
      await tester.pumpAndSettle();
      expect(find.text('2026-09-21'), findsWidgets);

      await tester.tap(find.byTooltip('后一天'));
      await tester.pumpAndSettle();
      expect(find.text('2026-09-22'), findsWidgets);
    });
  });
}
