// 选区/复制/图片/链接/分享（T020；架构 4.2 与第 7 节）。
//
// 六组断言对应任务验收里点名的六条：SelectionArea 单块选择与解释入口、复制全文的纯文本
// 拼接、链接面板拒绝危险协议、SET-012 关闭时点选下载、保存权限拒绝的提示、系统分享
// 不可用时回退复制。
//
// 断言的层次与 T017/T019 一致：这里验证「界面确实把动作转发了、把状态画对了」，纯函数
// 口径（全文拼接、选区上下文截断）由 reader_text_actions_test 用纯 Dart 验证。
library;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flux/core/core.dart';
import 'package:flux/features/articles/application/article_platform_ports.dart';
import 'package:flux/features/articles/presentation/article_detail_page.dart';
import 'package:flux/features/articles/presentation/reader/link_panel.dart';
import 'package:flux/infrastructure/local/database.dart';
import 'package:flux/infrastructure/local/feed_catalog_store.dart';

import '../../app/test_harness.dart';

/// 记录调用并返回预设结果的链接打开替身。
final class FakeLinkOpener implements ExternalLinkOpener {
  /// 被请求打开的地址（按调用顺序）。
  final List<String> opened = <String>[];

  @override
  Future<Result<bool>> openExternal(String url) async {
    opened.add(url);
    return const Ok<bool>(true);
  }
}

/// 图片保存替身。
final class FakeImageSaver implements ImageSaveService {
  /// 收到的保存请求（地址 + 建议文件名）。
  final List<(String, String)> requests = <(String, String)>[];

  /// 预设结果：Ok(null) 表示用户取消。
  Result<String?> result = const Ok<String?>('/tmp/saved.png');

  @override
  Future<Result<String?>> saveImage({
    required String url,
    required String suggestedName,
  }) async {
    requests.add((url, suggestedName));
    return result;
  }
}

/// 系统分享替身。
final class FakeShare implements SystemShareService {
  /// 是否报告可用。
  bool available = true;

  /// 被分享的文本。
  final List<String> shared = <String>[];

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<Result<bool>> shareText(String text) async {
    shared.add(text);
    return const Ok<bool>(true);
  }
}

void main() {
  late TestBootstrap bootstrap;
  late AppDatabase db;
  late int feedId;
  late FakeLinkOpener opener;
  late FakeImageSaver saver;
  late FakeShare share;

  setUp(() async {
    bootstrap = TestBootstrap();
    db = bootstrap.database;
    await db.customSelect('SELECT 1').get();
    feedId = (await DriftFeedCatalogStore(db).createFeed(
      const FeedInsert(
        syncId: 'feed.a',
        normalizedUrl: 'https://a.example.com/feed.xml',
        name: '示例源',
      ),
    )).unwrap().id;
    opener = FakeLinkOpener();
    saver = FakeImageSaver();
    share = FakeShare();
  });

  tearDown(() async {
    await bootstrap.dispose();
  });

  Future<int> seedArticle(String title, String body) => db
      .into(db.articles)
      .insert(
        ArticlesCompanion.insert(
          feedId: Value<int?>(feedId),
          title: title,
          identityBasis: IdentityBasis.guid,
          guid: Value<String?>('guid-$title'),
          guidPresent: const Value<bool>(true),
          body: Value<String?>(body),
          bodyCompleteness: const Value<BodyCompleteness>(
            BodyCompleteness.sourceBody,
          ),
        ),
      );

  /// 打开详情页（带 T020 三个平台端口的替身）。
  Future<void> pumpDetail(WidgetTester tester, {required int articleId}) async {
    await setSurfaceSize(tester, const Size(1000, 800));
    await tester.pumpWidget(
      wrapFluxApp(
        // 三个端口走**生产装配路径**的参数（与 feedFetcher/networkConditions 同一做法）：
        // Riverpod 不允许在同一容器里重复覆盖一个 Provider，因此替身必须在装配函数那
        // 一层注入，而不是测试自己再 override 一次。
        overrides: bootstrap.overrides(
          externalLinkOpener: opener,
          imageSaveService: saver,
          systemShareService: share,
        ),
        child: Scaffold(body: ArticleDetailPage(articleId: articleId)),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 拦下剪贴板写入，返回收集列表。
  List<MethodCall> captureClipboard(WidgetTester tester) {
    final List<MethodCall> calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall call) async {
        if (call.method == 'Clipboard.setData') {
          calls.add(call);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    return calls;
  }

  group('选区与复制全文（架构 4.2）', () {
    testWidgets('正文包在 SelectionArea 里，且挂了自定义选区菜单', (WidgetTester tester) async {
      final int id = await seedArticle('可选正文', '第一段文字。\n\n第二段文字。');
      await pumpDetail(tester, articleId: id);

      final SelectionArea area = tester.widget<SelectionArea>(
        find.byType(SelectionArea),
      );
      expect(
        area.contextMenuBuilder,
        isNotNull,
        reason: '需要自定义 contextMenuBuilder 才能追加「解释」入口',
      );
      expect(area.onSelectionChanged, isNotNull, reason: '需要拿到选区才能解释它');
    });

    testWidgets('复制全文按钮把纯文本拼好并写入剪贴板', (WidgetTester tester) async {
      final int id = await seedArticle('可复制', '# 标题行\n\n正文一。\n\n- 列表一\n- 列表二');
      await pumpDetail(tester, articleId: id);
      final List<MethodCall> clipboard = captureClipboard(tester);

      await tester.tap(find.byTooltip('复制全文'));
      await tester.pumpAndSettle();

      expect(clipboard, hasLength(1));
      final String copied =
          (clipboard.single.arguments as Map<Object?, Object?>)['text']!
              as String;
      expect(copied, contains('标题行'));
      expect(copied, contains('正文一。'));
      expect(copied, contains('列表一'));
      expect(copied, contains('\n\n'), reason: '段落之间是空行');
      expect(find.textContaining('全文已复制'), findsOneWidget);
    });

    testWidgets('没有正文时点复制全文如实说明，不谎报已复制', (WidgetTester tester) async {
      final int id = await seedArticle('无正文', '');
      await pumpDetail(tester, articleId: id);

      await tester.tap(find.byTooltip('复制全文'));
      await tester.pumpAndSettle();

      expect(find.textContaining('没有可复制的正文'), findsOneWidget);
      expect(find.textContaining('全文已复制'), findsNothing);
    });
  });

  group('链接面板与协议安全（危险协议拒绝）', () {
    testWidgets('https 链接：面板先显示完整地址，点「用浏览器打开」交给外开端口', (
      WidgetTester tester,
    ) async {
      final int id = await seedArticle(
        '带链接',
        // 只放链接本身：正文是 SelectableText（EditableText），点它的**几何中心**只会
        // 落在文字行的中间，而命中测试必须落在**链接那几个字**上。让这一段只有链接，
        // 命中点就必然在链接上（组件的命中测试是按字形走的，不是按控件边界）。
        '[外链甲](https://example.com/a?b=1)',
      );
      await pumpDetail(tester, articleId: id);

      // 点链接**字形**所在的位置。正文段落是通栏的（SelectableText 铺满可用宽度），
      // 组件的几何中心落在链接文字右侧的空白上；命中测试按字形走，因此必须点在左侧
      // 文字上。取左内边距之后一点点（链接是段首第一个元素）。
      final Rect linkLine = tester.getRect(find.textContaining('外链甲'));
      await tester.tapAt(Offset(linkLine.left + 12, linkLine.center.dy));
      await tester.pumpAndSettle();

      expect(find.text('外部链接'), findsOneWidget);
      expect(find.textContaining('https://example.com/a?b=1'), findsWidgets);
      await tester.pumpAndSettle();

      expect(find.text('外部链接'), findsOneWidget);
      expect(find.textContaining('https://example.com/a?b=1'), findsWidgets);

      await tester.tap(find.text('用浏览器打开'));
      await tester.pumpAndSettle();
      expect(opener.opened, <String>['https://example.com/a?b=1']);
    });

    testWidgets('危险协议（javascript/data/file）被拒绝打开，但仍可复制', (
      WidgetTester tester,
    ) async {
      for (final String url in <String>[
        'javascript:alert(1)',
        'data:text/html,<script>alert(1)</script>',
        'file:///etc/passwd',
      ]) {
        expect(
          isSafeDocUrl(url),
          isFalse,
          reason: '$url 必须被 isSafeDocUrl 拒绝（面板据此禁用打开）',
        );
        await tester.pumpWidget(
          wrapFluxApp(
            overrides: bootstrap.overrides(),
            child: Scaffold(
              body: LinkPanel(url: url, blockedReason: 'blocked'),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final FilledButton open = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, '用浏览器打开'),
        );
        expect(open.onPressed, isNull, reason: '$url 不得可打开');
        final TextButton copy = tester.widget<TextButton>(
          find.widgetWithText(TextButton, '复制地址'),
        );
        expect(copy.onPressed, isNotNull, reason: '读者需要知道原文想链接到哪里');
      }
    });

    testWidgets('https 允许，且面板提供打开', (WidgetTester tester) async {
      expect(isSafeDocUrl('https://example.com/a'), isTrue);
      await tester.pumpWidget(
        wrapFluxApp(
          overrides: bootstrap.overrides(),
          child: const Scaffold(body: LinkPanel(url: 'https://example.com/a')),
        ),
      );
      await tester.pumpAndSettle();
      final FilledButton open = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, '用浏览器打开'),
      );
      expect(open.onPressed, isNotNull);
    });

    testWidgets('正文里危险协议的链接不可点，且仍可见（不静默丢弃）', (WidgetTester tester) async {
      final int id = await seedArticle('危险链接', '[点我](javascript:alert(1))');
      await pumpDetail(tester, articleId: id);

      expect(find.textContaining('点我'), findsOneWidget);
      expect(find.textContaining('已拦截'), findsOneWidget);
      await tester.tap(find.textContaining('点我'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.text('外部链接'), findsNothing);
      expect(opener.opened, isEmpty);
    });
  });

  group('图片查看与保存（SET-012）', () {
    testWidgets('SET-012 关闭：只画占位框，点选后仍可查看与保存这一张', (WidgetTester tester) async {
      final Result<Object?> written = await bootstrap.settingsRepository.write(
        SettingId.set012,
        false,
      );
      expect(written.isOk, isTrue);

      final int id = await seedArticle(
        '带图片',
        '![说明文字](https://cdn.example.com/a.png)',
      );
      await pumpDetail(tester, articleId: id);

      expect(find.textContaining('自动加载远程图片已关闭'), findsOneWidget);
      expect(find.textContaining('点击下载这张图片'), findsOneWidget);
      expect(find.textContaining('说明文字'), findsWidgets);

      // 点占位框 → 查看器（关掉自动加载不等于不能看这一张）。
      await tester.tap(find.textContaining('说明文字').first);
      await tester.pumpAndSettle();
      expect(find.byType(ImageViewerPage), findsOneWidget);

      await tester.tap(find.byTooltip('保存图片'));
      await tester.pumpAndSettle();
      expect(saver.requests, hasLength(1));
      expect(saver.requests.single.$1, 'https://cdn.example.com/a.png');
      expect(saver.requests.single.$2, 'a.png', reason: '用地址末段做建议文件名');
    });

    testWidgets('SET-012 开启（默认）：图片位直接尝试加载，仍可点开查看器', (
      WidgetTester tester,
    ) async {
      final int id = await seedArticle(
        '带图片',
        '![说明文字](https://cdn.example.com/a.png)',
      );
      await pumpDetail(tester, articleId: id);

      expect(find.textContaining('远程图片加载与缓存属 T021'), findsOneWidget);
      await tester.tap(find.textContaining('说明文字').first);
      await tester.pumpAndSettle();
      expect(find.byType(ImageViewerPage), findsOneWidget);
    });

    testWidgets('保存失败（权限拒绝）：保留原因并如实提示', (WidgetTester tester) async {
      saver.result = Err<String?>(
        StorageError(operation: 'imageSave', detail: 'permission denied'),
      );
      final int id = await seedArticle(
        '带图片',
        '![说明](https://cdn.example.com/a.png)',
      );
      await pumpDetail(tester, articleId: id);
      await tester.tap(find.textContaining('说明').first);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('保存图片'));
      await tester.pumpAndSettle();
      // 提示条落在详情页上（查看器是独立页面，它的 messenger 会随它销毁）。
      // 用查看器的关闭按钮返回而不是 tester.pageBack()：后者要求页面有标准的 back
      // 按钮（CupertinoNavigationBarBackButton），而查看器的关闭键是自绘的 IconButton。
      await tester.tap(find.byTooltip('关闭（Esc）'));
      await tester.pumpAndSettle();
      expect(find.textContaining('保存失败'), findsOneWidget);
      expect(find.textContaining('permission denied'), findsOneWidget);
    });

    testWidgets('保存被取消：不提示失败（取消不是错误）', (WidgetTester tester) async {
      saver.result = const Ok<String?>(null);
      final int id = await seedArticle(
        '带图片',
        '![说明](https://cdn.example.com/a.png)',
      );
      await pumpDetail(tester, articleId: id);
      await tester.tap(find.textContaining('说明').first);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('保存图片'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('关闭（Esc）'));
      await tester.pumpAndSettle();
      expect(find.textContaining('保存失败'), findsNothing);
      expect(find.textContaining('图片已保存到'), findsNothing);
    });

    testWidgets('Esc 关闭图片查看器（桌面习惯动作）', (WidgetTester tester) async {
      final int id = await seedArticle(
        '带图片',
        '![说明](https://cdn.example.com/a.png)',
      );
      await pumpDetail(tester, articleId: id);
      await tester.tap(find.textContaining('说明').first);
      await tester.pumpAndSettle();
      expect(find.byType(ImageViewerPage), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(ImageViewerPage), findsNothing);
    });
  });

  group('系统分享（不可用时回退复制）', () {
    testWidgets('分享可用：走系统分享', (WidgetTester tester) async {
      final int id = await seedArticle(
        '带图片',
        '![说明](https://cdn.example.com/a.png)',
      );
      await pumpDetail(tester, articleId: id);
      await tester.tap(find.textContaining('说明').first);
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('分享'));
      await tester.pumpAndSettle();

      expect(share.shared, <String>['https://cdn.example.com/a.png']);
      expect(find.textContaining('已打开系统分享'), findsOneWidget);
    });

    testWidgets('分享不可用：回退复制并明确说明（架构 4.2）', (WidgetTester tester) async {
      share.available = false;
      final List<MethodCall> clipboard = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (MethodCall call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard.add(call);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      final int id = await seedArticle(
        '带图片',
        '![说明](https://cdn.example.com/a.png)',
      );
      await pumpDetail(tester, articleId: id);
      await tester.tap(find.textContaining('说明').first);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('分享'));
      await tester.pumpAndSettle();

      expect(share.shared, isEmpty, reason: '不可用时不调用分享');
      expect(clipboard, hasLength(1), reason: '回退为复制');
      expect(find.textContaining('系统分享不可用'), findsOneWidget);
    });
  });
}
