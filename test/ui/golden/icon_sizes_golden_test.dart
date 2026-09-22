// 图标三档尺寸 golden（T051；架构第 7 节「应用图标先做小尺寸辨识验证」）。
//
// 为什么在**可断言的**辨识度测试（test/ui/icon_sizes_test.dart）之外还要一张 golden：
//   那个文件测的是「结构还在不在」（覆盖率区间、实心核心、成对可分），它不会因为
//   「某个图标在 16px 下变得难看但仍然可辨」而失败。审美与观感的复核只有看图能做，
//   而看图需要一个固定的对照物：这张 golden 把 28 个图标在 16/20/24 三档下并排钉住，
//   评审时一眼就能看出「哪个图标在小尺寸下明显弱于同排其他图标」。
//
// 每个尺寸档渲染两行：
//   1) **实际像素**行：16/20/24 的真实大小，看「用户实际看到的是什么」；
//   2) **放大复核**行：把同一份小尺寸渲染结果整体放大 4 倍，看「哪条线断了、哪个
//      形状糊了」。
// 两行都要：只看实际尺寸无法指出具体问题，只看放大图又会忘记它实际只有 16 个像素。
//
// 放大用 FittedBox 缩放**已渲染的小尺寸结果**，不是按大尺寸重画：重画会得到 24 档的
// 线宽与几何，那正是要避免的——要审的就是 16px 的效果。
//
// 更新方式：flutter test --update-goldens test/ui/golden/icon_sizes_golden_test.dart
// 更新前必须人工确认：16px 一栏里没有糊成实心块或细到快看不见的图标。
library;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flux/core/design/design_tokens.dart';
import 'package:flux/ui/ui.dart';

import '../control_harness.dart';

/// 对照表里使用的三档渲染尺寸。
///
/// 16 是 macOS 列表与工具栏的实际像素尺寸，也是本轮验证的目标；20/24 是图标集的
/// 设计尺寸（架构第 7 节）。同图并列才能看出「20 档的图形缩到 16 之后是否还成立」。
const List<double> kGoldenSizes = <double>[16, 20, 24];

/// 放大复核行的倍数。
const double kMagnify = 4;

void main() {
  testWidgets('28 个图标 × 16/20/24 三档尺寸对照（含放大复核）', (WidgetTester tester) async {
    await setControlSurfaceSize(tester, const Size(1600, 1000));
    await tester.pumpWidget(
      wrapControl(const IconSizeMatrix(), surfaceSize: const Size(1600, 1000)),
    );
    // flutter_svg 走异步解码；先等解码任务结束，再泵帧让位图进入图层。
    // 直接 pumpAndSettle 在解码未完成时等的是「帧」，实测会挂住。
    await tester.runAsync(vg.waitForPendingDecodes);
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(IconSizeMatrix),
      matchesGoldenFile('icon_sizes_three_steps.png'),
    );
  });
}

/// 图标 × 尺寸的对照网格。
class IconSizeMatrix extends StatelessWidget {
  /// 构造对照网格。
  const IconSizeMatrix({super.key});

  @override
  Widget build(BuildContext context) {
    final Color ink = Theme.of(context).colorScheme.onSurface;
    final TextStyle? labelStyle = Theme.of(context).textTheme.labelSmall;
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      padding: const EdgeInsets.all(FluxSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (final double step in kGoldenSizes) ...<Widget>[
            Text('${sizedLabel(step)}（实际像素）', style: labelStyle),
            const SizedBox(height: FluxSpacing.xxs),
            IconRow(size: step, color: ink),
            const SizedBox(height: FluxSpacing.xs),
            Text(
              '${sizedLabel(step)} ×${kMagnify.toInt()}（放大复核）',
              style: labelStyle,
            ),
            const SizedBox(height: FluxSpacing.xxs),
            IconRow(size: step * kMagnify, color: ink, sourceSize: step),
            const SizedBox(height: FluxSpacing.lg),
          ],
        ],
      ),
    );
  }
}

/// 一行图标。
///
/// [sourceSize] 不为空时是放大行：先按 [sourceSize] 渲染矢量，再整体放大到 [size]，
/// 因此放大图对应的是**真实小尺寸渲染结果**被放大，而不是换一套线宽重画。
class IconRow extends StatelessWidget {
  /// 构造一行图标。
  const IconRow({
    required this.size,
    required this.color,
    this.sourceSize,
    super.key,
  });

  /// 每个格子的边长（逻辑像素）。
  final double size;

  /// 图标颜色。
  final Color color;

  /// 放大行对应的真实尺寸；为空表示这是真实尺寸行。
  final double? sourceSize;

  @override
  Widget build(BuildContext context) {
    final double? source = sourceSize;
    final bool magnified = source != null;
    final double logical = source ?? size;
    // 用 Wrap 而不是 Row：放大行每格 64px，28 个图标会超出画布宽度（Row 直接
    // 溢出报错）。Wrap 让它在同一区域内折行，评审时仍按行阅读。
    return Wrap(
      spacing: magnified ? FluxSpacing.lg : FluxSpacing.sm,
      runSpacing: FluxSpacing.sm,
      children: <Widget>[
        for (final FluxIcon icon in FluxIcon.values)
          SizedBox(
            width: size,
            height: size,
            child: FittedBox(
              fit: BoxFit.contain,
              child: SizedBox(
                width: logical,
                height: logical,
                child: FittedBox(
                  fit: BoxFit.contain,
                  child: FluxSvgIcon(
                    icon,
                    size: FluxIconSize.regular,
                    color: color,
                    excludeFromSemantics: true,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// 尺寸标签文本（16.0 → "16px"）。
String sizedLabel(double step) => '${step.toInt()}px';
