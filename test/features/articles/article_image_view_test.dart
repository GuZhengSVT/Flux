// T021：图片位的组件行为（失败不阻塞、重试可用、SET-012 关时不请求、查看器走同一管线）。
//
// 图片位用替身加载器驱动：这里验的是**界面行为**（占位、重试、点击打开查看器），
// 网络与缓存的行为已由 infrastructure 层的用例覆盖。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flux/core/core.dart';
import 'package:flux/features/articles/application/article_image_ports.dart';
import 'package:flux/features/articles/domain/markdown_to_document.dart';
import 'package:flux/features/articles/presentation/reader/doc_renderer.dart';
import 'package:flux/features/articles/presentation/reader/doc_theme.dart';
import 'package:flux/features/articles/presentation/reader/link_panel.dart';

import '../../app/fake_article_image_loader.dart';
import '../../app/test_harness.dart';

/// 按地址返回成功或失败的加载器。
final class _SelectiveLoader implements ArticleImageLoader {
  _SelectiveLoader({required this.failing});

  /// 这些地址加载失败，其余成功。
  final Set<String> failing;

  /// 每个地址被请求的次数。
  final Map<String, int> calls = <String, int>{};

  @override
  Future<Result<LoadedImage>> load(String url) async {
    calls[url] = (calls[url] ?? 0) + 1;
    if (failing.contains(url)) {
      return Err<LoadedImage>(NetworkError(uri: url, reason: '测试替身：故意失败'));
    }
    return Ok<LoadedImage>(
      LoadedImage(
        bytes: kTestPngBytes,
        mimeType: 'image/png',
        width: 1,
        height: 1,
      ),
    );
  }

  @override
  Future<Result<int>> saveToPath({
    required String url,
    required String targetPath,
  }) async => const Ok<int>(4);

  @override
  Future<void> applyCacheLimitMiB(int limitMiB) async {}
}

/// 测试排版（浅色 token 表；与 article_reader_test 同一份口径）。
const DocTypography kTestTypography = DocTypography(
  baseSize: 18,
  theme: DocTheme(
    background: Color(0xFFF6F7F9),
    surface: Color(0xFFFFFFFF),
    textPrimary: Color(0xFF20242B),
    textSecondary: Color(0xFF596273),
    border: Color(0xFFD9DEE7),
    accent: Color(0xFF315E52),
    selectedSurface: Color(0xFFE8F0EC),
    danger: Color(0xFFB42318),
    warningSurface: Color(0xFFFFF4E5),
    codeBackground: Color(0xFFF2F4F7),
    readingPaper: Color(0xFFF4EEDC),
    brightness: Brightness.light,
  ),
);

/// 一段含两张图（一张会失败）的 Markdown。
const String kTwoImageMarkdown =
    '![好图](https://cdn.example.com/good.png)\n\n'
    '![坏图](https://cdn.example.com/bad.png)';

void main() {
  late TestBootstrap bootstrap;

  setUp(() => bootstrap = TestBootstrap());
  tearDown(() async => bootstrap.dispose());

  /// 逐块渲染（与详情页同路径，因此能用 BlockView 的 autoLoadImages 开关）。
  Future<void> pumpDoc(
    WidgetTester tester, {
    required ArticleImageLoader loader,
    bool autoLoad = true,
    void Function(String url, String alt)? onOpenImage,
  }) async {
    final DocDocument doc = parseMarkdownToDocument(kTwoImageMarkdown);
    await setSurfaceSize(tester, const Size(900, 900));
    await tester.pumpWidget(
      wrapFluxApp(
        overrides: bootstrap.overrides(articleImageLoader: loader),
        localeOverride: const Locale('zh'),
        child: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                for (final DocNode node in doc.children)
                  Padding(
                    padding: blockPadding(node, kTestTypography),
                    child: BlockView(
                      node: node,
                      typography: kTestTypography,
                      autoLoadImages: autoLoad,
                      onOpenImage: onOpenImage,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  group('失败不阻塞文章（架构 4.2）', () {
    testWidgets('一张图失败时，另一张与两张的替代文字照常渲染', (WidgetTester tester) async {
      final _SelectiveLoader loader = _SelectiveLoader(
        failing: <String>{'https://cdn.example.com/bad.png'},
      );
      await pumpDoc(tester, loader: loader);

      expect(find.textContaining('好图'), findsWidgets);
      expect(find.textContaining('坏图'), findsWidgets);
      expect(find.textContaining('图片加载失败'), findsWidgets);
      expect(loader.calls.length, 2, reason: '一张失败不得阻止另一张被请求');
    });

    testWidgets('失败时提供重试入口；重试会真的重新请求', (WidgetTester tester) async {
      final _SelectiveLoader loader = _SelectiveLoader(
        failing: <String>{'https://cdn.example.com/bad.png'},
      );
      await pumpDoc(tester, loader: loader);
      final int before = loader.calls['https://cdn.example.com/bad.png'] ?? 0;
      expect(before, greaterThan(0));

      final Finder retry = find.byTooltip('重新加载这张图片');
      expect(retry, findsWidgets, reason: '失败必须给一条出路');
      await tester.tap(retry.first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(
        loader.calls['https://cdn.example.com/bad.png'],
        greaterThan(before),
        reason: '重试必须真的重新加载（不能命中旧的失败缓存）',
      );
    });

    testWidgets('SET-012 关闭时不发起任何图片请求，但仍说明可点选下载', (WidgetTester tester) async {
      final _SelectiveLoader loader = _SelectiveLoader(failing: <String>{});
      await pumpDoc(tester, loader: loader, autoLoad: false);

      expect(loader.calls, isEmpty, reason: '关掉自动加载就不得产生请求');
      expect(find.textContaining('自动加载远程图片已关闭'), findsWidgets);
      expect(find.textContaining('点击下载这张图片'), findsWidgets);
    });

    testWidgets('图片位仍可点击打开查看器', (WidgetTester tester) async {
      final _SelectiveLoader loader = _SelectiveLoader(
        failing: <String>{'https://cdn.example.com/bad.png'},
      );
      final List<String> opened = <String>[];
      await pumpDoc(
        tester,
        loader: loader,
        onOpenImage: (String url, String alt) => opened.add(url),
      );
      await tester.tap(find.textContaining('好图').first);
      // 不用 pumpAndSettle：成功加载的那张图在解码期间会有持续旋转的加载指示器，
      // pumpAndSettle 会等一个永不静止的动画而超时（这不是被测行为的问题）。
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(opened, <String>['https://cdn.example.com/good.png']);
    });
  });

  group('查看器走同一管线（T021 修复 T020 的旁路）', () {
    testWidgets('查看器经加载端口取图，而不是直接 Image.network', (WidgetTester tester) async {
      final _SelectiveLoader loader = _SelectiveLoader(failing: <String>{});
      await tester.pumpWidget(
        wrapFluxApp(
          overrides: bootstrap.overrides(articleImageLoader: loader),
          localeOverride: const Locale('zh'),
          child: ImageViewerPage(
            url: 'https://cdn.example.com/good.png',
            alt: '好图',
            onSave: () async {},
            onShare: () async {},
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(
        loader.calls.containsKey('https://cdn.example.com/good.png'),
        isTrue,
        reason: '查看器必须经加载端口取图（否则绕过了 MIME/体积/私网校验）',
      );
    });

    testWidgets('查看器加载失败时显示失败说明，不崩', (WidgetTester tester) async {
      final _SelectiveLoader loader = _SelectiveLoader(
        failing: <String>{'https://cdn.example.com/bad.png'},
      );
      await tester.pumpWidget(
        wrapFluxApp(
          overrides: bootstrap.overrides(articleImageLoader: loader),
          localeOverride: const Locale('zh'),
          child: ImageViewerPage(
            url: 'https://cdn.example.com/bad.png',
            alt: '坏图',
            onSave: () async {},
            onShare: () async {},
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.textContaining('图片加载失败'), findsWidgets);
    });
  });
}
