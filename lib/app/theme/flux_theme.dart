// 主题装配（T011，架构第 7 节）。
//
// 职责：把 lib/core/design/design_tokens.dart 的数值翻译成 Flutter 的 ThemeData，
// 并把品牌 token 以 FluxColors（ThemeExtension）暴露给控件层。
//
// 为什么不直接用 ColorScheme.fromSeed：
//   - 架构第 7 节给的是**逐 token 指定**的十六进制值，seed 生成会对它们做色调
//     映射，得到的是「接近但不等于」的颜色，无法通过色值与对比度断言；
//   - 这是低饱和极简风格，需要精确控制 background/surface/border 三者的差异，
//     seed 生成的容器色会额外引入一批未在文档中定义的中间色。
// 因此显式构造 ColorScheme，只把文档里存在的颜色放进主题。
//
// 动效：时长常量见 design_tokens.dart 的 FluxMotion；是否真正播放由使用者结合
// MediaQuery.disableAnimations（SET-014「减少动态效果」）决定，见 FluxMotionDurations。
library;

import 'package:flutter/material.dart';

import 'package:flux/core/design/design_tokens.dart';
// FluxMotionDurations 的实现已下移到 lib/ui：共享控件需要它，而 lib/ui 不得
// import lib/app（否则成环）。这里继续导出该符号，T011 已有的公开入口不变。
export 'package:flux/ui/flux_motion.dart' show FluxMotionDurations;

/// 主题 token 的 [ThemeExtension]：让控件拿到 token 表里的精确颜色。
///
/// ColorScheme 的槽位语义（primary/secondary/surfaceContainerLowest…）与架构
/// token 表并不是一一对应，硬塞会让「哪个颜色是 readingPaper」变成靠记忆的约定。
/// 这里显式给出一份带名字的扩展，控件层直接读语义名。
@immutable
final class FluxColors extends ThemeExtension<FluxColors> {
  /// 用逐项颜色构造。
  const FluxColors({
    required this.background,
    required this.surface,
    required this.textPrimary,
    required this.textSecondary,
    required this.border,
    required this.accent,
    required this.selectedSurface,
    required this.danger,
    required this.warning,
    required this.readingPaper,
  });

  /// 从 token 表构造。
  factory FluxColors.fromPalette(FluxPalette palette) => FluxColors(
    background: Color(palette.background),
    surface: Color(palette.surface),
    textPrimary: Color(palette.textPrimary),
    textSecondary: Color(palette.textSecondary),
    border: Color(palette.border),
    accent: Color(palette.accent),
    selectedSurface: Color(palette.selectedSurface),
    danger: Color(palette.danger),
    warning: Color(palette.warning),
    readingPaper: Color(palette.readingPaper),
  );

  /// 页面底色。
  final Color background;

  /// 卡片与面板底色。
  final Color surface;

  /// 主要文字。
  final Color textPrimary;

  /// 次要文字。
  final Color textSecondary;

  /// 边框与分隔线。
  final Color border;

  /// 强调色。
  final Color accent;

  /// 选中项底色。
  final Color selectedSurface;

  /// 危险操作。
  final Color danger;

  /// 警告与提醒。
  final Color warning;

  /// 阅读纸张背景。
  final Color readingPaper;

  /// 取当前主题的 token。
  ///
  /// 由 FluxTheme 装配的主题一定带本扩展，因此正常路径不会为空；用断言加非空
  /// 取值而不是给默认色，是为了让「忘了挂扩展」在开发期立刻暴露，而不是渲染出
  /// 一套没有来源的颜色。
  static FluxColors of(BuildContext context) {
    final FluxColors? colors = Theme.of(context).extension<FluxColors>();
    assert(colors != null, 'FluxColors 未挂到 ThemeData.extension，请使用 FluxTheme');
    return colors!;
  }

  @override
  FluxColors copyWith({
    Color? background,
    Color? surface,
    Color? textPrimary,
    Color? textSecondary,
    Color? border,
    Color? accent,
    Color? selectedSurface,
    Color? danger,
    Color? warning,
    Color? readingPaper,
  }) => FluxColors(
    background: background ?? this.background,
    surface: surface ?? this.surface,
    textPrimary: textPrimary ?? this.textPrimary,
    textSecondary: textSecondary ?? this.textSecondary,
    border: border ?? this.border,
    accent: accent ?? this.accent,
    selectedSurface: selectedSurface ?? this.selectedSurface,
    danger: danger ?? this.danger,
    warning: warning ?? this.warning,
    readingPaper: readingPaper ?? this.readingPaper,
  );

  @override
  FluxColors lerp(ThemeExtension<FluxColors>? other, double t) {
    if (other is! FluxColors) {
      return this;
    }
    return FluxColors(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      border: Color.lerp(border, other.border, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      selectedSurface: Color.lerp(selectedSurface, other.selectedSurface, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      readingPaper: Color.lerp(readingPaper, other.readingPaper, t)!,
    );
  }
}

/// 主题生成器：由架构第 7 节 token 表生成浅色与深色 [ThemeData]。
abstract final class FluxTheme {
  /// 浅色主题。
  static ThemeData light() => _build(FluxPalette.light, Brightness.light);

  /// 深色主题。
  static ThemeData dark() => _build(FluxPalette.dark, Brightness.dark);

  /// 按 ThemeMode 与系统亮度解析实际生效的主题。
  ///
  /// 单独抽出来是因为它不是「随便挑一个」：SET-002 的 system 选项要求跟随各设备
  /// 的 platformBrightness，主题切换时 Flutter 不会替我们做这件事，必须显式读取。
  /// 抽成纯函数让这条规则可以被测试直接钉住。
  static ThemeMode resolveMode({
    required String setting,
    required Brightness platformBrightness,
  }) {
    switch (setting) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      case 'system':
      default:
        // 未知取值按「跟随系统」处理：与 SET-002 默认值和最保守行为一致，
        // 避免一个损坏的设置值让界面停在错误的主题上。
        return ThemeMode.system;
    }
  }

  /// 指定亮度下的主题（供不经过 MaterialApp 的场合直接使用）。
  static ThemeData forBrightness(Brightness brightness) =>
      brightness == Brightness.dark ? dark() : light();

  /// 按一套 token 生成 ThemeData。
  static ThemeData _build(FluxPalette palette, Brightness brightness) {
    final FluxColors colors = FluxColors.fromPalette(palette);
    final ColorScheme scheme = ColorScheme(
      brightness: brightness,
      primary: colors.accent,
      onPrimary: brightness == Brightness.light
          ? colors.surface
          : const Color(0xFF15181C),
      primaryContainer: colors.selectedSurface,
      onPrimaryContainer: colors.textPrimary,
      secondary: colors.textSecondary,
      onSecondary: colors.surface,
      secondaryContainer: colors.selectedSurface,
      onSecondaryContainer: colors.textPrimary,
      // warning 没有对应的 ColorScheme 官方槽位，映射到 tertiary：这样 features
      // 层只读标准 ColorScheme 就能拿到全部 token，不必 import lib/app（否则
      // 「app 渲染 features、features 又 import app」会形成目录级循环）。
      tertiary: colors.warning,
      onTertiary: brightness == Brightness.light
          ? colors.surface
          : const Color(0xFF15181C),
      tertiaryContainer: colors.selectedSurface,
      onTertiaryContainer: colors.textPrimary,
      error: colors.danger,
      onError: brightness == Brightness.light
          ? colors.surface
          : const Color(0xFF15181C),
      errorContainer: colors.danger,
      onErrorContainer: colors.textPrimary,
      surface: colors.surface,
      // onSurface 用 textPrimary：标题与正文都以它为主色。
      onSurface: colors.textPrimary,
      onSurfaceVariant: colors.textSecondary,
      surfaceContainerLowest: colors.background,
      surfaceContainerLow: colors.background,
      surfaceContainer: colors.surface,
      surfaceContainerHigh: colors.selectedSurface,
      surfaceContainerHighest: colors.selectedSurface,
      outline: colors.border,
      outlineVariant: colors.border,
      inverseSurface: colors.textPrimary,
      onInverseSurface: colors.background,
      shadow: colors.border,
      // 不使用 M3 的表面着色叠加：token 表没有对应颜色，叠加会偏离指定色值。
      surfaceTint: const Color(0x00000000),
    );

    final TextTheme textTheme = _textTheme(colors);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: colors.background,
      canvasColor: colors.background,
      textTheme: textTheme,
      // 低饱和极简风格不使用大面积阴影，卡片靠边框与底色区分。
      dividerTheme: DividerThemeData(
        color: colors.border,
        thickness: 1,
        space: 1,
      ),
      cardTheme: CardThemeData(
        color: colors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(FluxRadius.card),
          side: BorderSide(color: colors.border),
        ),
      ),
      // 浅色主按钮深绿白字，深色浅绿深字（架构第 7 节）。
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: colors.accent,
          foregroundColor: scheme.onPrimary,
          minimumSize: const Size(0, 40),
          padding: const EdgeInsets.symmetric(
            horizontal: FluxSpacing.lg,
            vertical: FluxSpacing.sm,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(FluxRadius.button),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colors.textPrimary,
          side: BorderSide(color: colors.border),
          minimumSize: const Size(0, 40),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(FluxRadius.button),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: colors.accent),
      ),
      listTileTheme: ListTileThemeData(
        selectedColor: colors.accent,
        selectedTileColor: colors.selectedSurface,
        iconColor: colors.textSecondary,
        textColor: colors.textPrimary,
      ),
      // 桌面宽窗用侧边导航、窄窗用底部导航；两处都按 token 上色。
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: colors.background,
        indicatorColor: colors.selectedSurface,
        selectedIconTheme: IconThemeData(color: colors.accent),
        unselectedIconTheme: IconThemeData(color: colors.textSecondary),
        selectedLabelTextStyle: TextStyle(
          color: colors.textPrimary,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelTextStyle: TextStyle(
          color: colors.textSecondary,
          fontSize: 13,
        ),
        labelType: NavigationRailLabelType.all,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colors.surface,
        indicatorColor: colors.selectedSurface,
        elevation: 0,
        labelTextStyle: WidgetStateProperty.resolveWith<TextStyle>((
          Set<WidgetState> states,
        ) {
          final bool selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 12,
            color: selected ? colors.textPrimary : colors.textSecondary,
          );
        }),
      ),
      extensions: <ThemeExtension<dynamic>>[colors],
    );
  }

  /// 文字样式：正文 18、行高 1.7（架构第 7 节）。
  static TextTheme _textTheme(FluxColors colors) {
    final TextStyle base = TextStyle(color: colors.textPrimary);
    return TextTheme(
      // 正文：架构指定的 18 / 1.7。
      bodyLarge: base.copyWith(
        fontSize: FluxTypography.bodyFontSize,
        height: FluxTypography.bodyLineHeight,
      ),
      bodyMedium: base.copyWith(fontSize: 15, height: 1.5),
      bodySmall: base.copyWith(
        fontSize: 13,
        height: 1.45,
        color: colors.textSecondary,
      ),
      // 详情标题区间 28–32，取区间下界作为基础标题。
      headlineMedium: base.copyWith(
        fontSize: FluxTypography.detailTitleMin,
        height: 1.25,
        fontWeight: FontWeight.w600,
      ),
      titleLarge: base.copyWith(
        fontSize: 20,
        height: 1.3,
        fontWeight: FontWeight.w600,
      ),
      // 卡片标题：桌面 17 / 手机 18；壳层取桌面值，窄窗由调用方按断点调整。
      titleMedium: base.copyWith(
        fontSize: FluxTypography.cardTitleDesktop,
        height: 1.35,
        fontWeight: FontWeight.w600,
      ),
      titleSmall: base.copyWith(
        fontSize: 15,
        height: 1.35,
        fontWeight: FontWeight.w600,
        color: colors.textSecondary,
      ),
      labelLarge: base.copyWith(fontSize: 14, fontWeight: FontWeight.w500),
      labelMedium: base.copyWith(fontSize: 12, color: colors.textSecondary),
      labelSmall: base.copyWith(fontSize: 11, color: colors.textSecondary),
    );
  }
}
