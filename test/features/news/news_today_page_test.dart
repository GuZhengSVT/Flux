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

  /// 一条**没有摘录**的材料：正文已被清理的本机引用（架构 5.3 的「只释放正文」）。
  NewsMaterial clearedMaterial() => NewsMaterial(
    sourceId: 'rss.1',
    accessMethod: CitationAccessMethod.rss,
    title: '本机文章标题',
    url: 'https://example.com/1',
    excerpt: '',
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
    List<NewsMaterial> materials = const <NewsMaterial>[],
    TaskStatus status = TaskStatus.succeeded,
    NewsRunStage? stage,
    String? errorKind,
  }) async {
    final DriftNewsRunStore store = DriftNewsRunStore(db);
    await store.append(
      NewsRunRecord(
        localDate: '2026-09-22',
        timeZone: 'Asia/Shanghai',
        version: version,
        status: status,
        snapshot: snapshot(),
        siteResults: sites,
        materials: materials.isEmpty ? <NewsMaterial>[material()] : materials,
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
        stage: stage,
        errorKind: errorKind,
      ),
    );
  }

  Widget wrap(Widget child, {SettingsReader? reader}) => wrapFluxApp(
    // 包一层 Scaffold：删除版本的回执是 SnackBar，而 SnackBar 需要一个 Scaffold
    // 祖先才能真正显示出来（否则断言会在「没有可展示的 Scaffold」上失败）。
    child: Scaffold(body: child),
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

    testWidgets('近 7 天条带显示今天并标出有记录的日期，点击可切换', (WidgetTester tester) async {
      await seed(version: 1, current: true);
      await tester.pumpWidget(wrap(const NewsTodayPage()));
      await tester.pumpAndSettle();

      expect(find.text('近 7 天'), findsOneWidget);
      expect(find.text('今天'), findsWidgets);
      // 条带上 09-21 在（近 7 天）；今天那一格用「今天」而不是数字标出。
      expect(find.text('09-21'), findsOneWidget);

      await tester.tap(find.text('09-21'));
      await tester.pumpAndSettle();
      expect(find.text('2026-09-21'), findsWidgets);
      // 历史日期要说明时区归属（架构 4.4）。
      expect(find.textContaining('正在查看历史日期'), findsOneWidget);
    });

    testWidgets('历史日期面包屑说明「按生成当时的时区归属」', (WidgetTester tester) async {
      await tester.pumpWidget(wrap(const NewsTodayPage()));
      await tester.pumpAndSettle();
      // 条带上最早的一格（09-16）就在「近 7 天」里，点击即切到历史日期。
      await tester.tap(find.text('09-16'));
      await tester.pumpAndSettle();

      expect(find.textContaining('2026-09-16'), findsWidgets);
      expect(find.textContaining('不会因现在换时区而改写'), findsOneWidget);
    });
  });

  group('版本管理（T039）', () {
    testWidgets('版本条目含时间与模型，且提供删除入口', (WidgetTester tester) async {
      await seed(version: 1, current: false);
      await seed(
        version: 2,
        current: true,
        verificationMethod: 'search=yes queries=1 results=3',
      );
      await tester.pumpWidget(wrap(const NewsTodayPage()));
      await tester.pumpAndSettle();

      expect(find.textContaining('版本 1'), findsOneWidget);
      expect(find.textContaining('2026-09-22'), findsWidgets);
      expect(find.textContaining('deepseek/deepseek-chat'), findsWidgets);
      expect(find.byTooltip('删除这个历史版本（当前展示的版本不能删）'), findsOneWidget);
    });

    testWidgets('删除历史版本先弹确认框；确认后列表里少一版', (WidgetTester tester) async {
      await seed(version: 1, current: false);
      await seed(version: 2, current: true);
      await tester.pumpWidget(wrap(const NewsTodayPage()));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('删除这个历史版本（当前展示的版本不能删）'));
      await tester.pumpAndSettle();
      expect(find.text('删除版本 1？'), findsOneWidget);
      expect(find.textContaining('当前展示的版本不会被删除'), findsOneWidget);

      await tester.tap(find.text('删除').last);
      await tester.pumpAndSettle();
      expect(find.textContaining('已删除版本 1'), findsOneWidget);
      expect(find.textContaining('版本 1 '), findsNothing);
    });

    testWidgets('确认框里取消则不删除', (WidgetTester tester) async {
      await seed(version: 1, current: false);
      await seed(version: 2, current: true);
      await tester.pumpWidget(wrap(const NewsTodayPage()));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('删除这个历史版本（当前展示的版本不能删）'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      expect(find.textContaining('版本 1'), findsOneWidget);
      expect(find.textContaining('已删除'), findsNothing);
    });
  });

  group('状态完备（T039 的每页状态矩阵）', () {
    testWidgets('有失败记录但没有成功版本时，显示失败原因与中止阶段', (WidgetTester tester) async {
      final DriftNewsRunStore store = DriftNewsRunStore(db);
      await store.append(
        NewsRunRecord(
          localDate: '2026-09-22',
          timeZone: 'Asia/Shanghai',
          version: 1,
          status: TaskStatus.failed,
          snapshot: snapshot(),
          siteResults: const <NewsSiteFetchResult>[],
          materials: const <NewsMaterial>[],
          items: const <NewsDraftItem>[],
          createdAt: DateTime.utc(2026, 9, 22, 13),
          errorKind: 'validation',
          stage: NewsRunStage.save,
        ),
      );
      await tester.pumpWidget(wrap(const NewsTodayPage()));
      await tester.pumpAndSettle();

      expect(find.text('本次生成状态'), findsOneWidget);
      expect(find.textContaining('材料不足'), findsOneWidget);
      expect(find.textContaining('保存版本'), findsOneWidget);
      expect(find.text('这一天还没有新闻'), findsNothing);
    });

    testWidgets('取消的记录显示「已取消」，不谎称生成过内容', (WidgetTester tester) async {
      await seed(
        version: 1,
        current: false,
        status: TaskStatus.cancelled,
        stage: NewsRunStage.search,
      );
      await tester.pumpWidget(wrap(const NewsTodayPage()));
      await tester.pumpAndSettle();

      expect(find.textContaining('已取消'), findsWidgets);
      expect(find.textContaining('中止于'), findsOneWidget);
    });

    testWidgets('中断的记录说明「不会自动重发」', (WidgetTester tester) async {
      await seed(
        version: 1,
        current: false,
        status: TaskStatus.interrupted,
        stage: NewsRunStage.generate,
      );
      await tester.pumpWidget(wrap(const NewsTodayPage()));
      await tester.pumpAndSettle();

      expect(find.textContaining('不会自动重发'), findsOneWidget);
    });

    testWidgets('等待配置的记录说明「没有发出任何请求」', (WidgetTester tester) async {
      await seed(
        version: 1,
        current: false,
        status: TaskStatus.waitingConfiguration,
      );
      await tester.pumpWidget(wrap(const NewsTodayPage()));
      await tester.pumpAndSettle();

      expect(find.textContaining('没有发出任何请求'), findsOneWidget);
    });

    testWidgets('等待网络的记录说明「任务暂停后结束」', (WidgetTester tester) async {
      await seed(version: 1, current: false, status: TaskStatus.waitingNetwork);
      await tester.pumpWidget(wrap(const NewsTodayPage()));
      await tester.pumpAndSettle();

      expect(find.textContaining('任务暂停后结束'), findsOneWidget);
    });
  });

  group('引用与已清理内容（T039）', () {
    testWidgets('引用缺摘录时说明「原文已清理，只保留最小摘录」', (WidgetTester tester) async {
      await seed(
        version: 1,
        current: true,
        materials: <NewsMaterial>[clearedMaterial()],
      );
      await tester.pumpWidget(wrap(const NewsTodayPage()));
      await tester.pumpAndSettle();

      final Finder chip = find.textContaining('RSS·rss.1');
      expect(chip, findsOneWidget);
      await tester.longPress(chip);
      await tester.pumpAndSettle();
      expect(find.textContaining('原文已清理，只保留最小摘录'), findsWidgets);
    });
  });
}
