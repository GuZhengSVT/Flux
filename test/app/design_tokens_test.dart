// 设计 token 与主题生成的断言（T011，架构第 7 节）。
//
// 这些断言逐条对照架构说明书的 token 表与正文数值。它们的存在意义不是「覆盖率」，
// 而是让一次「顺手微调颜色」的改动必然触发失败：token 表是产品口径，
// 改了它必须同时改文档，而不是让实现悄悄漂移。
library;

import 'dart:math' show pow;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flux/app/theme/flux_theme.dart';
import 'package:flux/core/design/design_tokens.dart';

/// 把 token 整数还原为 Color。
Color _c(int value) => Color(value);

void main() {
  group('配色 token（架构第 7 节 token 表）', () {
    test('浅色 token 与文档逐项一致', () {
      const FluxPalette p = FluxPalette.light;
      expect(p.brightnessName, 'light');
      expect(_c(p.background), const Color(0xFFF6F7F9));
      expect(_c(p.surface), const Color(0xFFFFFFFF));
      expect(_c(p.textPrimary), const Color(0xFF20242B));
      expect(_c(p.textSecondary), const Color(0xFF596273));
      expect(_c(p.border), const Color(0xFFD9DEE7));
      expect(_c(p.accent), const Color(0xFF315E52));
      expect(_c(p.selectedSurface), const Color(0xFFE8F0EC));
      expect(_c(p.danger), const Color(0xFFB42318));
      expect(_c(p.warning), const Color(0xFF8A5700));
      expect(_c(p.readingPaper), const Color(0xFFF4EEDC));
    });

    test('深色 token 与文档逐项一致', () {
      const FluxPalette p = FluxPalette.dark;
      expect(p.brightnessName, 'dark');
      expect(_c(p.background), const Color(0xFF15181C));
      expect(_c(p.surface), const Color(0xFF1C2127));
      expect(_c(p.textPrimary), const Color(0xFFE7EBF0));
      expect(_c(p.textSecondary), const Color(0xFFA7B0BE));
      expect(_c(p.border), const Color(0xFF39424F));
      expect(_c(p.accent), const Color(0xFF8EC9B1));
      expect(_c(p.selectedSurface), const Color(0xFF233A32));
      expect(_c(p.danger), const Color(0xFFFF9F94));
      expect(_c(p.warning), const Color(0xFFE8BE6F));
      expect(_c(p.readingPaper), const Color(0xFF20221F));
    });

    test('按名称取配色：未知名称回退浅色，不抛异常', () {
      expect(FluxPalette.byName('dark').brightnessName, 'dark');
      expect(FluxPalette.byName('light').brightnessName, 'light');
      expect(FluxPalette.byName('unknown').brightnessName, 'light');
    });
  });

  group('间距/圆角/断点/排版常量（架构第 7 节正文）', () {
    test('间距阶梯为 4/8/12/16/24/32/48', () {
      expect(FluxSpacing.scale, <double>[4, 8, 12, 16, 24, 32, 48]);
      expect(FluxSpacing.phoneGutter, 16);
      expect(FluxSpacing.desktopGutterMin, 24);
      expect(FluxSpacing.desktopGutterMax, 32);
    });

    test('圆角为 8/12/16', () {
      expect(FluxRadius.scale, <double>[8, 12, 16]);
    });

    test('布局断点与栏宽符合文档', () {
      expect(FluxBreakpoints.twoColumn, 600);
      expect(FluxBreakpoints.threeColumn, 1100);
      expect(FluxBreakpoints.sourcePaneMin, 220);
      expect(FluxBreakpoints.sourcePaneMax, 240);
      expect(FluxBreakpoints.sourcePaneWidth, 220);
      expect(FluxBreakpoints.listPaneWidth, 300);
      expect(FluxBreakpoints.bodyPaneMin, 560);
      expect(FluxBreakpoints.minWindowWidth, 720);
      expect(FluxBreakpoints.minWindowHeight, 560);
      expect(FluxBreakpoints.maxBodyWidth, 720);
    });

    test('正文字号为 18、行高 1.7、段间距 0.8em', () {
      expect(FluxTypography.bodyFontSize, 18);
      expect(FluxTypography.bodyLineHeight, 1.7);
      expect(FluxTypography.paragraphSpacingEm, 0.8);
      expect(FluxTypography.paragraphSpacing, closeTo(14.4, 1e-9));
      expect(FluxTypography.detailTitleMin, 28);
      expect(FluxTypography.detailTitleMax, 32);
      expect(FluxTypography.cardTitleDesktop, 17);
      expect(FluxTypography.cardTitleMobile, 18);
    });

    test('动效时长落在 120–200ms', () {
      expect(FluxMotion.min.inMilliseconds, 120);
      expect(FluxMotion.max.inMilliseconds, 200);
      expect(FluxMotion.standard.inMilliseconds, inInclusiveRange(120, 200));
    });
  });

  group('ThemeData 生成', () {
    test('浅色主题：配 token 一致，扩展已挂载', () {
      final ThemeData theme = FluxTheme.light();
      expect(theme.brightness, Brightness.light);
      expect(theme.colorScheme.brightness, Brightness.light);
      final FluxColors colors = theme.extension<FluxColors>()!;
      expect(colors.background, _c(FluxPalette.light.background));
      expect(colors.accent, _c(FluxPalette.light.accent));
      expect(colors.readingPaper, _c(FluxPalette.light.readingPaper));
      expect(theme.colorScheme.primary, _c(FluxPalette.light.accent));
      expect(theme.scaffoldBackgroundColor, _c(FluxPalette.light.background));
      // 浅色主按钮：深绿底白字。
      expect(theme.colorScheme.onPrimary, const Color(0xFFFFFFFF));
    });

    test('深色主题：浅绿底深字', () {
      final ThemeData theme = FluxTheme.dark();
      expect(theme.brightness, Brightness.dark);
      final FluxColors colors = theme.extension<FluxColors>()!;
      expect(colors.background, _c(FluxPalette.dark.background));
      expect(colors.accent, _c(FluxPalette.dark.accent));
      expect(theme.colorScheme.onPrimary, const Color(0xFF15181C));
    });

    test('正文样式使用 18/1.7', () {
      final ThemeData theme = FluxTheme.light();
      expect(theme.textTheme.bodyLarge!.fontSize, 18);
      expect(theme.textTheme.bodyLarge!.height, 1.7);
    });

    test('卡片圆角为 12，按钮圆角为 8', () {
      final ThemeData theme = FluxTheme.light();
      final RoundedRectangleBorder cardShape =
          theme.cardTheme.shape! as RoundedRectangleBorder;
      expect(cardShape.borderRadius, BorderRadius.circular(12));
      final RoundedRectangleBorder buttonShape =
          theme.filledButtonTheme.style!.shape!.resolve(<WidgetState>{})!
              as RoundedRectangleBorder;
      expect(buttonShape.borderRadius, BorderRadius.circular(8));
    });

    test('SET-002 解析：system/light/dark，未知值回退 system', () {
      expect(
        FluxTheme.resolveMode(
          setting: 'light',
          platformBrightness: Brightness.dark,
        ),
        ThemeMode.light,
      );
      expect(
        FluxTheme.resolveMode(
          setting: 'dark',
          platformBrightness: Brightness.light,
        ),
        ThemeMode.dark,
      );
      // system 交给 Flutter 依据 platformBrightness 解析：这里必须返回 system，
      // 而不是自己预判一个亮度（否则「各设备独立解析」就失效了）。
      expect(
        FluxTheme.resolveMode(
          setting: 'system',
          platformBrightness: Brightness.dark,
        ),
        ThemeMode.system,
      );
      expect(
        FluxTheme.resolveMode(
          setting: 'bogus',
          platformBrightness: Brightness.dark,
        ),
        ThemeMode.system,
      );
    });
  });

  group('文字对比度（架构第 7 节：普通文字至少 4.5:1）', () {
    test('两套配色下正文与底色、次要文字与表面色都达标', () {
      for (final FluxPalette palette in <FluxPalette>[
        FluxPalette.light,
        FluxPalette.dark,
      ]) {
        final double primaryOnBackground = _contrast(
          _c(palette.textPrimary),
          _c(palette.background),
        );
        final double primaryOnSurface = _contrast(
          _c(palette.textPrimary),
          _c(palette.surface),
        );
        final double secondaryOnBackground = _contrast(
          _c(palette.textSecondary),
          _c(palette.background),
        );
        // 正文与标题都要达到 4.5:1。
        expect(
          primaryOnBackground,
          greaterThanOrEqualTo(4.5),
          reason: '${palette.brightnessName}: textPrimary/background',
        );
        expect(
          primaryOnSurface,
          greaterThanOrEqualTo(4.5),
          reason: '${palette.brightnessName}: textPrimary/surface',
        );
        // 次要文字是说明性文字，仍按普通文字标准要求。
        expect(
          secondaryOnBackground,
          greaterThanOrEqualTo(4.5),
          reason: '${palette.brightnessName}: textSecondary/background',
        );
      }
    });
  });
}

/// WCAG 相对亮度对比度（普通文字 4.5:1 的判定依据）。
///
/// 公式来自 WCAG 2.x：相对亮度 L = 0.2126R + 0.7152G + 0.0722B，
/// 通道先做 sRGB 线性化；对比度 = (L_亮 + 0.05) / (L_暗 + 0.05)。
double _contrast(Color a, Color b) {
  final double la = _relativeLuminance(a);
  final double lb = _relativeLuminance(b);
  final double lighter = la > lb ? la : lb;
  final double darker = la > lb ? lb : la;
  return (lighter + 0.05) / (darker + 0.05);
}

double _relativeLuminance(Color color) {
  double channel(double value) => value <= 0.03928
      ? value / 12.92
      : pow((value + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(color.r) +
      0.7152 * channel(color.g) +
      0.0722 * channel(color.b);
}
