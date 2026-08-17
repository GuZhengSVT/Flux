import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/flux_theme.dart';

/// 无限拓展的构成主义风格程序化背景。
///
/// 使用“单元格 + 固定种子”的方式生成：每个单元格的内容只由它的坐标决定，
/// 因此窗口放大时只是出现更多单元格，不会拉伸或缩放原有图案。
class FluxArtBackground extends StatelessWidget {
  const FluxArtBackground({
    super.key,
    this.seed = 42,
    required this.dark,
    this.opacity = 1.0,
  });

  final int seed;
  final bool dark;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _FluxArtPainter(seed: seed, dark: dark, opacity: opacity),
      child: const SizedBox.expand(),
    );
  }
}

class _FluxArtPainter extends CustomPainter {
  _FluxArtPainter({
    required this.seed,
    required this.dark,
    required this.opacity,
  });

  final int seed;
  final bool dark;
  final double opacity;

  static const double _cell = 240;
  static const double _grid = 60;

  @override
  void paint(Canvas canvas, Size size) {
    final base = dark ? FluxColors.darkBg : FluxColors.bone;
    canvas.drawRect(Offset.zero & size, Paint()..color = base);

    _paintGrid(canvas, size);

    final maxCx = (size.width / _cell).ceil();
    final maxCy = (size.height / _cell).ceil();
    for (var cx = 0; cx <= maxCx; cx++) {
      for (var cy = 0; cy <= maxCy; cy++) {
        _paintCell(canvas, cx, cy);
      }
    }
  }

  void _paintGrid(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = (dark ? FluxColors.darkMuted : FluxColors.concreteLight)
          .withValues(alpha: _alpha(dark ? 0.22 : 0.32))
      ..strokeWidth = 0.6;

    for (double x = 0; x <= size.width; x += _grid) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y <= size.height; y += _grid) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  void _paintCell(Canvas canvas, int cx, int cy) {
    final rng = _Rng(_cellSeed(cx, cy));
    final left = cx * _cell;
    final top = cy * _cell;
    final cell = Rect.fromLTWH(left, top, _cell, _cell);

    _paintStructuralLines(canvas, rng, cell);
    _paintShapes(canvas, rng, cell);
    _paintCircles(canvas, rng, cell);
    _paintWedge(canvas, rng, cell);
    _paintDots(canvas, rng, cell);
    _paintCrosses(canvas, rng, cell);
    _paintDashedLines(canvas, rng, cell);
  }

  void _paintStructuralLines(Canvas canvas, _Rng rng, Rect cell) {
    final count = rng.nextInt(3);
    for (var i = 0; i < count; i++) {
      final start = Offset(
        cell.left + rng.nextDouble() * cell.width,
        cell.top + rng.nextDouble() * cell.height,
      );
      final angle = rng.pick(const [-0.6, -0.35, 0.35, 0.6, math.pi / 6]);
      final length = rng.range(120, cell.width * 1.4);
      final paint = Paint()
        ..color = _pickLineColor(rng)
            .withValues(alpha: _alpha(rng.range(0.25, 0.50)))
        ..strokeWidth = rng.range(1.0, 2.6);
      canvas.save();
      canvas.translate(start.dx, start.dy);
      canvas.rotate(angle);
      canvas.drawLine(Offset.zero, Offset(length, 0), paint);
      canvas.restore();
    }
  }

  void _paintShapes(Canvas canvas, _Rng rng, Rect cell) {
    final count = rng.nextInt(3) + 1;
    for (var i = 0; i < count; i++) {
      final center = Offset(
        cell.left + rng.range(cell.width * 0.2, cell.width * 0.8),
        cell.top + rng.range(cell.height * 0.2, cell.height * 0.8),
      );

      if (rng.nextDouble() < 0.5) {
        final sides = rng.nextIntBetween(3, 6);
        final radius = rng.range(12, 34);
        final rotation = rng.nextDouble() * math.pi * 2;
        final filled = rng.nextDouble() < 0.45;
        final fillPaint = Paint()
          ..style = PaintingStyle.fill
          ..color = _pickShapeFill(rng)
              .withValues(alpha: _alpha(rng.range(0.25, 0.45)));
        final strokePaint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = rng.range(1.0, 2.2)
          ..color = _pickShapeStroke(rng)
              .withValues(alpha: _alpha(rng.range(0.35, 0.60)));
        _drawPolygon(
          canvas,
          center,
          radius,
          sides,
          rotation,
          filled ? fillPaint : null,
          strokePaint,
        );
      } else {
        final width = rng.range(12, 40);
        final height = rng.range(10, 30);
        final angle = rng.pick(const [0.0, 0.15, -0.15, 0.3]);
        final filled = rng.nextDouble() < 0.4;
        final fillPaint = Paint()
          ..style = PaintingStyle.fill
          ..color = _pickShapeFill(rng)
              .withValues(alpha: _alpha(rng.range(0.25, 0.45)));
        final strokePaint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = rng.range(1.0, 2.0)
          ..color = _pickShapeStroke(rng)
              .withValues(alpha: _alpha(rng.range(0.35, 0.60)));

        canvas.save();
        canvas.translate(center.dx, center.dy);
        canvas.rotate(angle);
        final rect = Rect.fromCenter(
          center: Offset.zero,
          width: width,
          height: height,
        );
        if (filled) {
          canvas.drawRect(rect, fillPaint);
          canvas.drawRect(rect, strokePaint);
        } else {
          canvas.drawRect(rect, strokePaint);
        }
        canvas.restore();
      }
    }
  }

  void _paintCircles(Canvas canvas, _Rng rng, Rect cell) {
    final count = rng.nextInt(2) + 1;
    for (var i = 0; i < count; i++) {
      final center = Offset(
        cell.left + rng.nextDouble() * cell.width,
        cell.top + rng.nextDouble() * cell.height,
      );
      final radius = rng.range(10, 36);

      if (rng.nextDouble() < 0.45) {
        final strokePaint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = rng.range(1.0, 2.4)
          ..color = _pickShapeStroke(rng)
              .withValues(alpha: _alpha(rng.range(0.30, 0.50)));
        canvas.drawCircle(center, radius, strokePaint);

        if (rng.nextDouble() < 0.35) {
          final ringPaint = Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = rng.range(0.8, 1.6)
            ..color = FluxColors.red.withValues(
              alpha: _alpha(rng.range(0.30, 0.50)),
            );
          canvas.drawCircle(center, radius * rng.range(0.55, 0.8), ringPaint);
        }
      } else {
        final fillPaint = Paint()
          ..style = PaintingStyle.fill
          ..color = _pickCircleFill(rng)
              .withValues(alpha: _alpha(rng.range(0.25, 0.45)));
        canvas.drawCircle(center, radius, fillPaint);
      }
    }
  }

  void _paintWedge(Canvas canvas, _Rng rng, Rect cell) {
    if (rng.nextDouble() < 0.35) {
      final center = Offset(
        cell.left + rng.range(cell.width * 0.25, cell.width * 0.75),
        cell.top + rng.range(cell.height * 0.25, cell.height * 0.75),
      );
      final radius = rng.range(18, 42);
      final start = rng.nextDouble() * math.pi * 2;
      final sweep = rng.range(0.2, 0.9);
      final fill = Paint()
        ..style = PaintingStyle.fill
        ..color = FluxColors.red.withValues(
          alpha: _alpha(rng.range(0.30, 0.50)),
        );
      final stroke = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = rng.range(1.0, 1.8)
        ..color = (dark ? FluxColors.darkText : FluxColors.ink).withValues(
          alpha: rng.range(0.25, 0.50),
        );
      _drawSector(canvas, center, radius, start, start + sweep, fill, stroke);
    }
  }

  void _paintDots(Canvas canvas, _Rng rng, Rect cell) {
    final count = rng.nextInt(3) + 1;
    for (var i = 0; i < count; i++) {
      final center = Offset(
        cell.left + rng.nextDouble() * cell.width,
        cell.top + rng.nextDouble() * cell.height,
      );
      final radius = rng.range(1.0, 3.0);
      final color = rng.nextDouble() < 0.35
          ? FluxColors.red
          : dark
          ? FluxColors.darkMuted
          : rng.nextDouble() < 0.6
          ? FluxColors.ink
          : FluxColors.concrete;
      final paint = Paint()
        ..color = color.withValues(alpha: _alpha(rng.range(0.35, 0.60)));
      canvas.drawCircle(center, radius, paint);
    }
  }

  void _paintCrosses(Canvas canvas, _Rng rng, Rect cell) {
    if (rng.nextDouble() < 0.5) {
      final center = Offset(
        cell.left + rng.range(cell.width * 0.25, cell.width * 0.75),
        cell.top + rng.range(cell.height * 0.25, cell.height * 0.75),
      );
      final arm = rng.range(7, 16);
      final angle = rng.range(-0.3, 0.3);
      final paint = Paint()
        ..color =
            (rng.nextDouble() < 0.35
                    ? FluxColors.red
                    : dark
                    ? FluxColors.darkMuted
                    : FluxColors.ink)
                .withValues(alpha: _alpha(rng.range(0.35, 0.60)))
        ..strokeWidth = rng.range(1.2, 2.4);

      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(angle);
      canvas.drawLine(Offset(-arm, 0), Offset(arm, 0), paint);
      canvas.drawLine(Offset(0, -arm), Offset(0, arm), paint);
      canvas.restore();
    }
  }

  void _paintDashedLines(Canvas canvas, _Rng rng, Rect cell) {
    if (rng.nextDouble() < 0.45) {
      final start = Offset(
        cell.left + rng.nextDouble() * cell.width,
        cell.top + rng.nextDouble() * cell.height,
      );
      final angle = rng.pick(const [-0.7, -0.4, 0.4, 0.7]);
      final length = rng.range(40, 110);
      final paint = Paint()
        ..color = (dark ? FluxColors.darkMuted : FluxColors.concrete)
            .withValues(alpha: _alpha(rng.range(0.30, 0.55)))
        ..strokeWidth = rng.range(1.0, 1.6);
      final dash = rng.range(5, 10);
      final gap = rng.range(4, 8);

      canvas.save();
      canvas.translate(start.dx, start.dy);
      canvas.rotate(angle);
      final path = Path();
      var d = 0.0;
      var on = true;
      while (d < length) {
        final segment = math.min(on ? dash : gap, length - d);
        if (on) {
          path.moveTo(d, 0);
          path.lineTo(d + segment, 0);
        }
        d += segment;
        on = !on;
      }
      canvas.drawPath(path, paint);
      canvas.restore();
    }
  }

  Color _pickLineColor(_Rng rng) {
    if (dark) {
      final value = rng.nextDouble();
      if (value < 0.45) return FluxColors.darkText;
      if (value < 0.8) return FluxColors.darkMuted;
      return FluxColors.darkRaised;
    }
    return rng.nextDouble() < 0.4
        ? FluxColors.ink
        : rng.nextDouble() < 0.5
        ? FluxColors.steel
        : FluxColors.concrete;
  }

  Color _pickShapeFill(_Rng rng) {
    if (dark) {
      final value = rng.nextDouble();
      if (value < 0.3) return FluxColors.red;
      if (value < 0.55) return FluxColors.darkMuted;
      if (value < 0.8) return FluxColors.darkRaised;
      return FluxColors.newsprint;
    }
    final value = rng.nextDouble();
    if (value < 0.25) return FluxColors.red;
    if (value < 0.5) return FluxColors.ink;
    if (value < 0.7) return FluxColors.newsprint;
    return FluxColors.concrete;
  }

  Color _pickShapeStroke(_Rng rng) {
    if (dark) {
      final value = rng.nextDouble();
      if (value < 0.5) return FluxColors.darkText;
      if (value < 0.8) return FluxColors.darkMuted;
      return FluxColors.red;
    }
    final value = rng.nextDouble();
    if (value < 0.4) return FluxColors.ink;
    if (value < 0.7) return FluxColors.steel;
    if (value < 0.85) return FluxColors.red;
    return FluxColors.concrete;
  }

  Color _pickCircleFill(_Rng rng) {
    if (dark) {
      final value = rng.nextDouble();
      if (value < 0.3) return FluxColors.red;
      if (value < 0.55) return FluxColors.darkMuted;
      if (value < 0.8) return FluxColors.darkRaised;
      return FluxColors.newsprint;
    }
    final value = rng.nextDouble();
    if (value < 0.25) return FluxColors.red;
    if (value < 0.5) return FluxColors.ink;
    if (value < 0.75) return FluxColors.newsprint;
    return FluxColors.concrete;
  }

  void _drawPolygon(
    Canvas canvas,
    Offset center,
    double radius,
    int sides,
    double rotation,
    Paint? fill,
    Paint? stroke,
  ) {
    final path = Path();
    for (var i = 0; i <= sides; i++) {
      final angle = rotation + (math.pi * 2 * i) / sides;
      final offset = Offset(
        center.dx + math.cos(angle) * radius,
        center.dy + math.sin(angle) * radius,
      );
      if (i == 0) {
        path.moveTo(offset.dx, offset.dy);
      } else {
        path.lineTo(offset.dx, offset.dy);
      }
    }
    path.close();
    if (fill != null) canvas.drawPath(path, fill);
    if (stroke != null) canvas.drawPath(path, stroke);
  }

  void _drawSector(
    Canvas canvas,
    Offset center,
    double radius,
    double start,
    double end,
    Paint fill,
    Paint stroke,
  ) {
    final path = Path()
      ..moveTo(center.dx, center.dy)
      ..arcTo(
        Rect.fromCircle(center: center, radius: radius),
        start,
        end - start,
        false,
      )
      ..close();
    canvas.drawPath(path, fill);
    canvas.drawPath(path, stroke);
  }

  int _cellSeed(int cx, int cy) {
    var h = seed;
    h = (h ^ (cx * 0x9E3779B9)) & 0xFFFFFFFF;
    h = (h ^ (cy * 0x85EBCA6B)) & 0xFFFFFFFF;
    h = (h ^ (h >> 16)) & 0xFFFFFFFF;
    return h;
  }

  double _alpha(double value) => (value * opacity).clamp(0.0, 1.0);

  @override
  bool shouldRepaint(covariant _FluxArtPainter oldDelegate) {
    return oldDelegate.seed != seed ||
        oldDelegate.dark != dark ||
        oldDelegate.opacity != opacity;
  }
}

class _Rng {
  _Rng(int seed) : _state = seed & 0xFFFFFFFF;

  int _state;

  int _next() {
    _state = (_state * 1664525 + 1013904223) & 0xFFFFFFFF;
    return _state;
  }

  int nextInt(int max) => _next() % max;

  int nextIntBetween(int min, int max) => min + (_next() % (max - min + 1));

  double nextDouble() => _next() / 0xFFFFFFFF;

  double range(double a, double b) => a + nextDouble() * (b - a);

  double pick(List<double> values) => values[nextInt(values.length)];
}
