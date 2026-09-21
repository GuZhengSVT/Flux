// 正文渲染的排版与配色（T019；架构第 7 节的 token 表与正文排版口径）。
//
// 为什么单独一个文件而不是直接用 ThemeData：正文有**自己的**口径——正文 18、行高 1.7、
// 段间距 0.8em、正文最大宽 720、代码用等宽字体并带 CJK 回退。把这些从 Material 主题里
// 推导出来会让两件事耦合：动一次控件主题就会改到文章排版，而架构把「正文阅读」与
// 「控件外观」列成两套独立的口径。
//
// 配色取自架构第 7 节 token 表（FluxPalette），不在此另立一套颜色。
//
// 等宽字体的 CJK 回退不是装饰：Flux 渲染中英混排文档，而常见的等宽字体没有中文字形。
// 缺了这条回退，代码块里的中文注释会渲染成方框。CJK 字体排在拉丁字体**之后**，
// 因此拉丁字符保持等宽外观，只有等宽字体缺的字形才落到 CJK 字体上。
library;

import 'package:flutter/material.dart';

import 'package:flux/core/design/design_tokens.dart';

/// 阅读面的配色。
class DocTheme {
  /// 构造配色。
  const DocTheme({
    required this.background,
    required this.surface,
    required this.textPrimary,
    required this.textSecondary,
    required this.border,
    required this.accent,
    required this.selectedSurface,
    required this.danger,
    required this.warningSurface,
    required this.codeBackground,
    required this.readingPaper,
    required this.brightness,
  });

  /// 页面底色。
  final Color background;

  /// 面板底色。
  final Color surface;

  /// 主要文字。
  final Color textPrimary;

  /// 次要文字。
  final Color textSecondary;

  /// 边框。
  final Color border;

  /// 强调色。
  final Color accent;

  /// 选中底色。
  final Color selectedSurface;

  /// 危险色。
  final Color danger;

  /// 警告底色。
  final Color warningSurface;

  /// 代码底色。
  final Color codeBackground;

  /// 阅读纸张底色（SET-007）。
  final Color readingPaper;

  /// 亮度。
  final Brightness brightness;

  /// 由架构第 7 节的 token 表构造。
  factory DocTheme.fromPalette(FluxPalette palette) => DocTheme(
    background: Color(palette.background),
    surface: Color(palette.surface),
    textPrimary: Color(palette.textPrimary),
    textSecondary: Color(palette.textSecondary),
    border: Color(palette.border),
    accent: Color(palette.accent),
    selectedSurface: Color(palette.selectedSurface),
    danger: Color(palette.danger),
    // token 表只有 danger/warning 的**前景**色，没有警告底色。这里用 danger 的极低
    // 透明度叠在面上得到一块可辨的底：新造一个常量会让「配色来自 token 表」不再成立。
    warningSurface: Color(palette.danger).withValues(alpha: 0.08),
    // 代码底色同样从 token 表推导：浅色下用 border 的淡化版本（比 surface 深一点），
    // 深色下用 surface（比 background 浅一点）。这样不引入表外的色值。
    codeBackground: palette.brightnessName == 'dark'
        ? Color(palette.surface)
        : Color(palette.border).withValues(alpha: 0.35),
    readingPaper: Color(palette.readingPaper),
    brightness: palette.brightnessName == 'dark'
        ? Brightness.dark
        : Brightness.light,
  );

  /// 浅色阅读面。
  static final DocTheme light = DocTheme.fromPalette(FluxPalette.light);

  /// 深色阅读面。
  static final DocTheme dark = DocTheme.fromPalette(FluxPalette.dark);
}

/// 正文排版。
class DocTypography {
  /// 构造排版。
  const DocTypography({required this.baseSize, required this.theme});

  /// 正文字号（架构第 7 节：正文 18）。
  final double baseSize;

  /// 阅读面配色。
  final DocTheme theme;

  /// 正文样式。
  TextStyle get body => TextStyle(
    fontSize: baseSize,
    height: FluxTypography.bodyLineHeight,
    color: theme.textPrimary,
  );

  /// 次要文字（图片说明、元信息）。
  TextStyle get secondary => TextStyle(
    fontSize: baseSize * 0.85,
    height: 1.5,
    color: theme.textSecondary,
  );

  /// 标题样式（h1–h6）。
  TextStyle heading(int level) {
    final double multiplier = switch (level) {
      1 => 1.75,
      2 => 1.5,
      3 => 1.3,
      4 => 1.15,
      5 => 1.05,
      _ => 1.0,
    };
    return TextStyle(
      fontSize: baseSize * multiplier,
      height: 1.35,
      fontWeight: FontWeight.w600,
      color: theme.textPrimary,
    );
  }

  /// 代码块样式。
  TextStyle get code => TextStyle(
    fontFamily: kMonoFontFamily,
    fontFamilyFallback: kMonoFontFallback,
    fontSize: FluxTypography.codeFontSize,
    height: 1.5,
    color: theme.textPrimary,
  );

  /// 行内代码样式。
  TextStyle get inlineCode => TextStyle(
    fontFamily: kMonoFontFamily,
    fontFamilyFallback: kMonoFontFallback,
    fontSize: baseSize * 0.88,
    color: theme.textPrimary,
  );
}

/// 首选等宽字族。
const String kMonoFontFamily = 'Menlo';

/// 等宽字体的回退链（见文件头关于 CJK 的说明）。
const List<String> kMonoFontFallback = <String>[
  'SF Mono',
  'Courier New',
  'PingFang SC',
  'Hiragino Sans GB',
  'Heiti SC',
  'Songti SC',
  'Arial Unicode MS',
  'monospace',
];
