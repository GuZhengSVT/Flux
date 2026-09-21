// 共享控件 golden（T012 验收：浅深 × 三态 × favorite 的精选组合入库）。
//
// 为什么只做「精选组合」而不是逐个状态截图：
//   八类状态的**行为**由 test/ui/flux_controls_test.dart 断言（回调、语义、
//   拦截），截图无法证明这些。截图要证明的是另一件事：颜色、线宽、间距在
//   浅深两套主题下**整体**是否成立——例如「焦点环在深色下看不清」「禁用态
//   在浅色下几乎与正常态一致」这类问题只有看图才发现。
//
// 因此这里固定的是：
//   - 三态控件的三个取值（图标必须能互相区分）；
//   - 收藏的 on/off（描边与实心）；
//   - 浅色与深色（token 两套）；
//   - 一行八类状态对照（用 debugStatusOverride 把状态钉住，让同一张图能复核
//     全部状态的视觉差异；真实指针悬停/按下无法在一张静态图里同时呈现）。
//
// 更新方式：flutter test --update-goldens test/ui/golden/controls_golden_test.dart
// 更新前必须人工确认符合架构第 7 节（低饱和、线宽 1.5–2、状态可区分）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flux/core/core.dart';
import 'package:flux/ui/ui.dart';

import '../control_harness.dart';

void main() {
  group('三态与收藏（浅/深 × unread/read/later × favorite）', () {
    for (final (String name, ThemeMode mode) in <(String, ThemeMode)>[
      ('light', ThemeMode.light),
      ('dark', ThemeMode.dark),
    ]) {
      testWidgets('$name：三态三值 + 收藏 on/off + 加精徽标', (WidgetTester tester) async {
        await tester.pumpWidget(
          wrapControl(
            const _GalleryGrid(),
            themeMode: mode,
            surfaceSize: const Size(560, 320),
          ),
        );
        await tester.pumpAndSettle();

        await expectLater(
          find.byType(_GalleryGrid),
          matchesGoldenFile('controls_states_$name.png'),
        );
      });
    }
  });

  group('八类状态对照（同一张图内可复核）', () {
    for (final (String name, ThemeMode mode) in <(String, ThemeMode)>[
      ('light', ThemeMode.light),
      ('dark', ThemeMode.dark),
    ]) {
      testWidgets('$name：八类状态视觉', (WidgetTester tester) async {
        // 真实视口也要放大：只改 MediaQuery 的声明尺寸不会改变渲染视口，
        // 8 行状态在默认 800×600 下会溢出（测试视为失败）。
        await setControlSurfaceSize(tester, const Size(560, 640));
        await tester.pumpWidget(
          wrapControl(
            const _StatusMatrix(),
            themeMode: mode,
            // 8 行 × (48 命中区 + 行标题) 约 560，留出余量避免 RenderFlex 溢出。
            surfaceSize: const Size(560, 640),
          ),
        );
        await tester.pumpAndSettle();

        await expectLater(
          find.byType(_StatusMatrix),
          matchesGoldenFile('controls_status_matrix_$name.png'),
        );
      });
    }
  });

  group('通用控件（空态/横幅/卡片）', () {
    testWidgets('浅色中文：空态、三档横幅、卡片', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrapControl(
          const _CommonWidgetsGallery(),
          surfaceSize: const Size(560, 620),
        ),
      );
      await tester.pumpAndSettle();

      await expectLater(
        find.byType(_CommonWidgetsGallery),
        matchesGoldenFile('common_widgets_light_zh.png'),
      );
    });

    testWidgets('深色英文：空态、三档横幅、卡片', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrapControl(
          const _CommonWidgetsGallery(),
          themeMode: ThemeMode.dark,
          locale: const Locale('en'),
          surfaceSize: const Size(560, 620),
        ),
      );
      await tester.pumpAndSettle();

      await expectLater(
        find.byType(_CommonWidgetsGallery),
        matchesGoldenFile('common_widgets_dark_en.png'),
      );
    });
  });
}

/// 三态 × 收藏 × 加精 / 两种图标尺寸的对照网格。
class _GalleryGrid extends StatelessWidget {
  const _GalleryGrid();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (final FluxIconSize size in FluxIconSize.values) ...<Widget>[
            _RowLabel(text: 'size=${size.logicalSize.toInt()}'),
            Row(
              children: <Widget>[
                for (final ReadingState state in ReadingState.values)
                  ReadingStateControl(
                    state: state,
                    size: size,
                    onChanged: (_) {},
                  ),
                FavoriteToggle(favorite: false, size: size, onChanged: (_) {}),
                FavoriteToggle(favorite: true, size: size, onChanged: (_) {}),
                const SizedBox(width: 8),
                if (size == FluxIconSize.regular)
                  const FeaturedBadge(showLabel: true)
                else
                  const FeaturedBadge(),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// 八类状态矩阵（状态由 debugStatusOverride 钉住，便于同图对照）。
class _StatusMatrix extends StatelessWidget {
  const _StatusMatrix();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (final FluxControlStatus status
              in FluxControlStatus.values) ...<Widget>[
            _RowLabel(text: status.name),
            Row(
              children: <Widget>[
                ReadingStateControl(
                  state: ReadingState.unread,
                  debugStatusOverride: status,
                  // 相位钉住：加载指示器在动，golden 必须是确定性画面。
                  debugLoadingTurns: 0.15,
                  onChanged: (_) {},
                ),
                FavoriteToggle(
                  favorite: false,
                  debugStatusOverride: status,
                  debugLoadingTurns: 0.15,
                  onChanged: (_) {},
                ),
                const SizedBox(width: 8),
                ReadingStateControl(
                  state: ReadingState.later,
                  showLabel: true,
                  debugStatusOverride: status,
                  debugLoadingTurns: 0.15,
                  onChanged: (_) {},
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// 空态、三档横幅与卡片的组合。
class _CommonWidgetsGallery extends StatelessWidget {
  const _CommonWidgetsGallery();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const StatusBanner(
            severity: StatusBannerSeverity.info,
            message: '信息：本地优先，数据不离开你的设备。',
          ),
          const SizedBox(height: 8),
          const StatusBanner(
            severity: StatusBannerSeverity.warning,
            message: '警告：尚未配置 AI 与搜索服务，今日新闻暂不可用。',
          ),
          const SizedBox(height: 8),
          const StatusBanner(
            severity: StatusBannerSeverity.error,
            title: '抓取失败',
            message: '订阅源返回 503，已保留上一次成功的内容。',
          ),
          const SizedBox(height: 16),
          FluxCard(
            selected: true,
            semanticsLabel: '示例卡片',
            onTap: () {},
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('统一卡片容器', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  '卡片圆角与边框由 token 决定，列表的三种卡片形态共用它。',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const SizedBox(
            height: 200,
            child: FluxEmptyState(
              title: '还没有订阅',
              body: '添加订阅或导入 OPML 之后，文章会出现在这里。',
              secondaryNote: '计划任务：T013–T016',
              tone: EmptyStateTone.positive,
            ),
          ),
        ],
      ),
    );
  }
}

/// 对照网格的行标题。
class _RowLabel extends StatelessWidget {
  const _RowLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Text(text, style: Theme.of(context).textTheme.labelSmall),
  );
}
