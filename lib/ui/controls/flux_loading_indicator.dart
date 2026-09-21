// 加载指示器（T012）。
//
// 为什么不用 CircularProgressIndicator：它的线宽与直径是框架自己的一套数值
// （线宽 4、无外径参数），放在 20/24 的图标位上要么太大要么太粗，与原创图标的
// 1.5–1.75 线宽明显不一致，一排图标里会立刻看出来。
//
// 这里画一个开口圆弧，线宽与直径都取自 token：[FluxControlTokens.loadingStrokeWidth]
// 与 [FluxControlTokens.loadingIndicatorScale]。
//
// 不确定进度的旋转是**唯一**合适的表达：架构第 7 节明确「生成中显示真实阶段不做
// 假百分比」，因此本组件不提供 0.0–1.0 的进度参数——没有真实进度时不该伪造。
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:flux/core/design/design_tokens.dart';

/// 不确定进度的加载指示器（旋转开口圆弧）。
class FluxLoadingIndicator extends StatefulWidget {
  /// 构造指示器。
  const FluxLoadingIndicator({
    super.key,
    this.size = FluxIconTokens.sizeRegular,
    this.color,
    this.semanticsLabel,
    this.debugTurns,
  });

  /// 外径（与图标同尺寸，保证替换图标时不发生布局跳动）。 */
  final double size;

  /// 颜色；为空时继承 IconTheme。 */
  final Color? color;

  /// 读屏标签（例如「正在加载」）。 */
  final String? semanticsLabel;

  /// 测试/截图用：把旋转角钉在指定值（单位：圈）。
  ///
  /// 动画在 golden 里是不稳定的（截图时刻不确定），因此截图用例用它固定相位；
  /// 生产代码不得传。
  final double? debugTurns;

  @override
  State<FluxLoadingIndicator> createState() => _FluxLoadingIndicatorState();
}

class _FluxLoadingIndicatorState extends State<FluxLoadingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    if (widget.debugTurns == null) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(FluxLoadingIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    final bool shouldSpin = widget.debugTurns == null;
    if (shouldSpin && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!shouldSpin && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color resolved =
        widget.color ?? IconTheme.of(context).color ?? const Color(0xFF000000);
    final Widget painter = CustomPaint(
      size: Size.square(widget.size),
      painter: _ArcPainter(
        color: resolved,
        turns: widget.debugTurns,
        animation: _controller,
      ),
    );
    if (widget.semanticsLabel case final String label) {
      // 用 liveRegion 让读屏在状态变化时主动播报，否则加载开始可能完全不被察觉。
      return Semantics(
        label: label,
        liveRegion: true,
        child: ExcludeSemantics(child: painter),
      );
    }
    return ExcludeSemantics(child: painter);
  }
}

/// 开口圆弧：连续旋转 + 弧度呼吸，避免看起来像「卡住的静止圆环」。
class _ArcPainter extends CustomPainter {
  _ArcPainter({required this.color, required this.animation, this.turns})
    : super(repaint: animation);

  final Color color;
  final Animation<double> animation;
  final double? turns;

  @override
  void paint(Canvas canvas, Size size) {
    const double stroke = FluxControlTokens.loadingStrokeWidth;
    final double radius = (size.shortestSide - stroke) / 2;
    final double rotation = (turns ?? animation.value) * 2 * math.pi;
    // 弧长在 0.18–0.82 圈之间变化：固定弧长在慢速旋转下容易被看成静止。
    final double sweep =
        (0.18 + 0.64 * (0.5 + 0.5 * math.sin(rotation * 1.7))) * 2 * math.pi;

    if (size.shortestSide <= 0) {
      // 尺寸为 0 时不绘制：drawArc 用负半径会画出反向弧，在极窄布局里会看到
      // 一个莫名其妙的半环。
      return;
    }
    final Paint paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: size.center(Offset.zero), radius: radius),
      rotation - math.pi / 2,
      sweep,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(_ArcPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.turns != turns;
}
