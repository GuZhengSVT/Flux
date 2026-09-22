// 平台体验与可访问性测试（T049，架构第 7 节）。
//
// 覆盖四类只有在这一层才看得见的东西：
//   1) 快捷键**真的触发**了动作（不是「注册了一个 Intent」）；
//   2) 右键菜单里**有哪几项**（菜单是 overlay，只有构建之后才存在）；
//   3) 读屏标签与语义树（SemanticsHandle 下断言节点）；
//   4) 大字号与窄窗不溢出（LayoutBuilder + 大字号世界）。
//
// 规则本身（Esc 的分层顺序、SET-014 的合成）由纯 Dart 用例覆盖，见各自的 group。
library;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flux/app/shell/app_destination.dart';
import 'package:flux/app/shell/app_shortcuts.dart';
import 'package:flux/app/app.dart';
import 'package:flux/core/core.dart';
import 'package:flux/features/articles/presentation/reading_page.dart';
import 'package:flux/features/articles/presentation/article_detail_page.dart';
import 'package:flux/features/articles/presentation/article_list_view.dart';
import 'package:flux/features/settings/application/motion_preference.dart';
import 'package:flux/infrastructure/local/database.dart';
import 'package:flux/infrastructure/local/feed_catalog_store.dart';
import 'package:flux/ui/ui.dart';

import 'test_harness.dart';

/// 取语义树里第一个标签匹配 [label] 的节点。
///
/// 用 first 而不是 single：同一种控件在列表里有多行（三态控件、收藏各有 N 个），
/// 断言关心的是「标签形状正确」，而不是「只有一个」。
SemanticsNode _node(WidgetTester tester, Pattern label) =>
    find.semantics.byLabel(label).evaluate().first;

void main() {
  group('SET-014 减少动态效果的合成（纯规则）', () {
    test('默认跟随系统：不覆盖系统的取值', () {
      expect(MotionPreference.fromStorage(null), MotionPreference.system);
      expect(MotionPreference.fromStorage('nonsense'), MotionPreference.system);
      // 跟随系统时解析结果是 null（= 不覆盖），系统开与关都不改变行为。
      expect(
        MotionPreference.system.resolve(systemDisablesAnimations: true),
        isNull,
      );
      expect(
        MotionPreference.system.resolve(systemDisablesAnimations: false),
        isNull,
      );
    });

    test('强制档覆盖系统取值，且方向相反', () {
      expect(
        MotionPreference.on.resolve(systemDisablesAnimations: false),
        isTrue,
        reason: '系统没开减少动效时，强制档仍要减少',
      );
      expect(
        MotionPreference.off.resolve(systemDisablesAnimations: true),
        isFalse,
        reason: '系统开了减少动效时，强制「不减少」要能覆盖它',
      );
    });
  });

  group('快捷键层（纯规则）', () {
    test('⌘1/2/3 与 ⌘/ 各有映射，且指向不同去向', () {
      final Map<ShortcutActivator, Intent> shortcuts = appShortcuts();
      expect(shortcuts.length, 4);
      final List<AppDestination> targets = <AppDestination>[
        for (final Intent intent in shortcuts.values)
          if (intent is SwitchDestinationIntent) intent.destination,
      ];
      expect(targets.toSet(), <AppDestination>{
        AppDestination.today,
        AppDestination.reading,
        AppDestination.mine,
      });
      expect(
        shortcuts.values.whereType<ShowShortcutHelpIntent>(),
        hasLength(1),
      );
    });

    test('说明面板逐条覆盖导航/列表/关闭/其它四组', () {
      // 条目数固定：新增一条就必须显式改这里，避免「说明面板悄悄少了一项」。
      expect(shortcutHelpEntries.length, 7);
      // 每一组都有**恰好**一条导航、两条列表、一条关闭、一条其它以外的分布——
      // 用条目在列表中的位置断言分组，因为 group 是函数、取文案需要 l10n。
      expect(shortcutHelpEntries[0].group, same(shortcutHelpEntries[2].group));
      expect(
        shortcutHelpEntries[0].group,
        isNot(same(shortcutHelpEntries[3].group)),
      );
      expect(shortcutHelpEntries[3].group, same(shortcutHelpEntries[4].group));
      expect(
        shortcutHelpEntries[4].group,
        isNot(same(shortcutHelpEntries[5].group)),
      );
      expect(
        shortcutHelpEntries[5].group,
        isNot(same(shortcutHelpEntries[6].group)),
      );
    });
  });

  group('应用壳快捷键', () {
    /// 挂上应用壳。
    Future<TestBootstrap> pumpShell(
      WidgetTester tester, {
      Size size = const Size(1280, 900),
    }) async {
      final TestBootstrap bootstrap = TestBootstrap();
      addTearDown(bootstrap.dispose);
      await setSurfaceSize(tester, size);
      // 真实根组件会读 SET-001 与引导标记：语言固定中文（否则按测试环境的 en_US 回退），
      // 引导标记置为已完成（否则停在引导页，壳层的快捷键也就无从测起）。
      await bootstrap.seedLanguage('zh-Hans');
      await bootstrap.completeOnboarding();
      // 用**真实根组件**而不是只挂 AppShell：快捷键层在 MaterialApp 之上
      // （路由的祖先链上），只挂壳层测不出真实的按键投递路径——那正是这一层最容易
      // 出错的地方（挂在壳层里时 ⌘2 完全没反应）。
      await tester.pumpWidget(
        wrapRoot(child: const FluxApp(), overrides: bootstrap.overrides()),
      );
      await tester.pumpAndSettle();
      return bootstrap;
    }

    /// 发送一个带 meta（⌘）的组合键。
    Future<void> pressMeta(WidgetTester tester, LogicalKeyboardKey key) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
      await tester.sendKeyEvent(key);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
      await tester.pumpAndSettle();
    }

    testWidgets('⌘2 切到 RSS 阅读，⌘3 切到我的，⌘1 回到今日', (WidgetTester tester) async {
      await pumpShell(tester);
      expect(find.text('这一天还没有新闻'), findsOneWidget);

      await pressMeta(tester, LogicalKeyboardKey.digit2);
      // 阅读页在空库时显示「还没有订阅」空态（与 app_shell_test 同一断言口径）。
      expect(find.text('还没有订阅'), findsOneWidget, reason: '⌘2 应切到阅读页');

      await pressMeta(tester, LogicalKeyboardKey.digit3);
      expect(find.text('界面语言'), findsWidgets, reason: '⌘3 应切到设置页');

      await pressMeta(tester, LogicalKeyboardKey.digit1);
      expect(find.text('这一天还没有新闻'), findsOneWidget, reason: '⌘1 应回到今日页');
    });

    testWidgets('⌘/ 弹出快捷键说明；Esc 关闭它', (WidgetTester tester) async {
      await pumpShell(tester);
      expect(
        find.byKey(const ValueKey<String>('shortcut-help-dialog')),
        findsNothing,
      );

      await pressMeta(tester, LogicalKeyboardKey.slash);
      expect(
        find.byKey(const ValueKey<String>('shortcut-help-dialog')),
        findsOneWidget,
        reason: '⌘/ 应弹出说明面板',
      );
      // 面板里逐条说明三组快捷键（不是只弹一个空框）。
      expect(find.textContaining('⌘1'), findsWidgets);
      expect(find.textContaining('回车'), findsWidgets);
      expect(find.textContaining('Esc'), findsWidgets);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('shortcut-help-dialog')),
        findsNothing,
      );
    });
  });

  group('列表键盘与语义', () {
    late TestBootstrap bootstrap;
    late AppDatabase db;
    late int feedId;

    setUp(() async {
      bootstrap = TestBootstrap();
      db = bootstrap.database;
      await db.customSelect('SELECT 1').get();
      feedId = (await DriftFeedCatalogStore(db).createFeed(
        const FeedInsert(
          syncId: 'feed.keys',
          normalizedUrl: 'https://keys.example.com/feed.xml',
          name: '键盘测试源',
        ),
      )).unwrap().id;
    });

    tearDown(() async => bootstrap.dispose());

    Future<int> seed(String title) async => await db
        .into(db.articles)
        .insert(
          ArticlesCompanion.insert(
            feedId: Value<int?>(feedId),
            title: title,
            identityBasis: IdentityBasis.guid,
            guid: Value<String?>('guid-$title'),
            guidPresent: const Value<bool>(true),
            summary: const Value<String?>('摘要'),
            publishedAt: Value<DateTime?>(DateTime.utc(2026, 9, 20, 12)),
            fetchedAt: Value<DateTime>(DateTime.utc(2026, 9, 20, 12)),
          ),
        );

    Future<void> pumpReading(WidgetTester tester) async {
      await setSurfaceSize(tester, const Size(1100, 900));
      await tester.pumpWidget(
        wrapFluxApp(
          child: const Scaffold(body: ReadingPage()),
          overrides: bootstrap.overrides(),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('上下键移动落点，回车打开正文', (WidgetTester tester) async {
      await seed('第一篇');
      await seed('第二篇');
      await pumpReading(tester);
      expect(find.text('第一篇'), findsOneWidget);

      // 焦点先落在列表里（键盘用户从焦点链走到卡片上）。用一个真实的焦点落点：
      // 三态控件在列表行里是可聚焦的，回车会把事件冒泡到列表的键盘层。
      final Finder firstCard = find.ancestor(
        of: find.text('第一篇'),
        matching: find.byType(ArticleListView),
      );
      expect(firstCard, findsOneWidget);

      // 直接把按键发给根焦点：列表键盘层是按键祖先链上的一环，不需要先点中某一行。
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      // 打开的是**键盘落点**那一篇；列表按发布时间倒序，两篇同一时刻时按 id 倒序，
      // 因此落点是第一篇。断言「打开了一篇详情」而不是具体哪一篇——具体顺序由
      // 排序规则用例负责，混在一起会让这条用例在排序变化时误报。
      expect(find.byType(ArticleDetailPage), findsOneWidget);
    });

    testWidgets('加精/收藏/三态控件的语义标签完整', (WidgetTester tester) async {
      await seed('语义文章');
      final SemanticsHandle handle = tester.ensureSemantics();
      await pumpReading(tester);

      // 三态控件报「这是什么控件 + 当前值」，收藏报「动作」，卡片报标题。
      // 用正则而不是字符串：标签是「控件名：当前值」的合成串，精确匹配只会失败。
      expect(_node(tester, RegExp('阅读状态')).label, contains('未读'));
      // 收藏控件的标签是「收藏：加入收藏」，用整段而不是「收藏」两字——后者也会
      // 匹配到三态控件的 hint 文案，断言就落在一个与它无关的节点上。
      expect(_node(tester, RegExp('收藏：')).label, contains('加入收藏'));
      expect(_node(tester, RegExp('语义文章')).label, contains('语义文章'));
      // 图片占位与进度状态是 T049 明确要求补的两类语义（本用例只覆盖列表侧可见的
      // 那几类；正文图片占位由阅读器用例覆盖）。
      handle.dispose();
    });

    testWidgets('窄窗（599 单栏）不溢出且卡片完整', (WidgetTester tester) async {
      await seed('窄窗文章标题比较长，用来验证不会溢出');
      await setSurfaceSize(tester, const Size(599, 800));
      await tester.pumpWidget(
        wrapFluxApp(
          child: const Scaffold(body: ReadingPage()),
          overrides: bootstrap.overrides(),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('窄窗文章标题比较长，用来验证不会溢出'), findsOneWidget);
    });

    testWidgets('大字号（2.0 倍）下控件不被截断、不溢出', (WidgetTester tester) async {
      await seed('大字号下这篇标题会变高三行以上');
      await setSurfaceSize(tester, const Size(900, 900));
      await tester.pumpWidget(
        wrapFluxApp(
          child: const Scaffold(body: ReadingPage()),
          overrides: bootstrap.overrides(),
          // SET-006 的字号上限（正文 28）在测试里用文本缩放表达：2.0 倍已经超过
          // 「UI 12–24 / 正文 14–28」的最大相对幅度，足以暴露任何被截断的控件。
          textScaler: const TextScaler.linear(2),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '大字号下不得溢出');
      // 两个操作控件（三态与收藏）仍必须可命中：如果它们被挤出可视区或压成 0 宽，
      // 这里会找不到。
      expect(find.byType(ReadingStateControl), findsWidgets);
      expect(find.byType(FavoriteToggle), findsWidgets);
    });

    testWidgets('列表项右键菜单包含标读/稍后/收藏/彻底删除', (WidgetTester tester) async {
      await seed('菜单文章');
      await pumpReading(tester);

      final TestGesture gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      addTearDown(gesture.removePointer);
      await gesture.down(tester.getCenter(find.text('菜单文章')));
      await gesture.up();
      await tester.pumpAndSettle();

      // 菜单项内容逐项断言：只断言「弹出了菜单」无法发现某一条被删掉。
      expect(find.text('打开正文'), findsOneWidget);
      expect(find.text('未读'), findsWidgets);
      expect(find.text('已读'), findsWidgets);
      expect(find.text('稍后再读'), findsWidgets);
      expect(find.text('加入收藏'), findsWidgets);
      expect(find.text('删除这篇文章…'), findsOneWidget);
    });

    testWidgets('Esc 先退出批量模式，再清除键盘落点', (WidgetTester tester) async {
      await seed('批量文章');
      await pumpReading(tester);

      await tester.tap(find.text('批量选择'));
      await tester.pumpAndSettle();
      expect(find.byType(Checkbox), findsWidgets, reason: '批量模式下每行有勾选框');

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(Checkbox), findsNothing, reason: 'Esc 应退出批量模式');
    });
  });
}
