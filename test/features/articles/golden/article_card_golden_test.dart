// 卡片形态 golden（T019+：正常模式卡片，浅深两套）。
//
// 为什么值得入库：三种卡片形态的差异正是「一眼看不出但确实错」的那类东西——右图是否
// 真的 96×72、标题与摘要的行数是否符合架构第 7 节、行尾两个状态控件与缩略图是否挤在
// 一起。像素差异比断言更能暴露这类回归。
//
// 注意：测试环境使用 Ahem 字体（方块字形），因此这里断言的是**布局与配色结构**，
// 不是文案本身；文案正确性由 article_list_modes_test 与 l10n 测试负责。
//
// 更新方式：flutter test --update-goldens test/features/articles/golden/article_card_golden_test.dart
// 更新前必须人工确认截图符合架构第 7 节，而不是「跑一下让它变成绿的」。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flux/core/core.dart';
import 'package:flux/features/articles/application/article_card_view.dart';
import 'package:flux/features/articles/presentation/article_card.dart';
import 'package:flux/ui/ui.dart';
import 'package:flux/core/design/design_tokens.dart';

import '../../../app/test_harness.dart';

/// 固定的一张卡片数据（含图地址，因此正常形态会画出右图位）。
///
/// 时间用**同一个确定时刻**而不是 DateTime.now()：golden 一旦依赖运行时间就会每天
/// 产出不同的图，diff 会变成噪声。
final ArticleListEntry _entry = ArticleListEntry(
  id: 1,
  feedId: 1,
  feedName: 'Example Blog',
  title: 'A card headline that is long enough to wrap onto a second line',
  readingState: ReadingState.unread,
  favorite: false,
  publishedAt: DateTime.utc(2026, 9, 20, 12),
  fetchedAt: DateTime.utc(2026, 9, 20, 12),
  summary:
      'A summary line that also wraps, so the two-line limit from the '
      'spec is actually visible in the golden image.',
  imageUrl: 'https://cdn.example.com/cover.png',
);

void main() {
  // 卡片是纯展示，不读数据库也不写状态；这里仍然走真实的 ProviderScope 装配
  // （与页面一致），因为控件会读 ColorScheme 与 l10n，用真实的装配路径才能保证
  // golden 反映的正是产品里会出现的那套主题。
  late TestBootstrap bootstrap;

  setUp(() => bootstrap = TestBootstrap());
  tearDown(() => bootstrap.dispose());

  Future<void> pump(
    WidgetTester tester, {
    required ThemeMode mode,
    required ArticleCardViewMode view,
  }) async {
    await setSurfaceSize(tester, const Size(420, 220));
    await tester.pumpWidget(
      wrapFluxApp(
        overrides: bootstrap.overrides(),
        localeOverride: const Locale('en'),
        themeMode: mode,
        child: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(FluxSpacing.md),
              child: ArticleCardBody(
                entry: _entry,
                mode: view,
                metaLine: 'Example Blog · 2026-09-20 12:00',
                trailing: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    ReadingStateControl(
                      state: ReadingState.unread,
                      size: FluxIconSize.small,
                    ),
                    FavoriteToggle(favorite: false, size: FluxIconSize.small),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    // 图片位在测试里不会真的完成网络加载（_errorBuilder 会接手），因此这里只推进
    // 有限帧，不使用 pumpAndSettle（那会等一个永远不会到达的网络响应）。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  group('卡片形态 golden', () {
    testWidgets('正常模式（右图 96×72）浅色', (WidgetTester tester) async {
      await pump(
        tester,
        mode: ThemeMode.light,
        view: ArticleCardViewMode.normal,
      );
      await expectLater(
        find.byType(ArticleCardBody),
        matchesGoldenFile('article_card_normal_light_en.png'),
      );
    });

    testWidgets('正常模式（右图 96×72）深色', (WidgetTester tester) async {
      await pump(
        tester,
        mode: ThemeMode.dark,
        view: ArticleCardViewMode.normal,
      );
      await expectLater(
        find.byType(ArticleCardBody),
        matchesGoldenFile('article_card_normal_dark_en.png'),
      );
    });
  });
}
