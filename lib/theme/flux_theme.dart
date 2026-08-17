import 'package:flutter/material.dart';

/// Flux 视觉 token。
///
/// 参考 mockup 文件夹中的工业/构成主义示例：
/// - 铁灰导航栏、新闻纸色侧栏、骨白主内容
/// - 红色功能强调色、硬朗直角边框
/// - 低圆角、清晰的描边层次
abstract final class FluxColors {
  // 主色
  static const red = Color(0xFFD62828);
  static const redAccent = Color(0xFFFF6F61);
  static const wireGold = Color(0xFFC5A849);

  // 中性色
  static const ink = Color(0xFF1A1A1A);
  static const steel = Color(0xFF3D3D3D);
  static const steelLight = Color(0xFF4A4A4A);
  static const concrete = Color(0xFFB8B5AD);
  static const concreteLight = Color(0xFFD4D1C9);
  static const bone = Color(0xFFF0EDE6);
  static const newsprint = Color(0xFFE4E0D8);
  static const newsprintDark = Color(0xFFD8D4CC);

  // 兼容旧引用
  static const black = Color(0xFF111111);
  static const paper = bone;
  static const gray = concrete;
  static const line = Color(0x331A1A1A);

  // Dark mode
  static const darkBg = Color(0xFF0D0D0F);
  static const darkSurface = Color(0xFF161619);
  static const darkRaised = Color(0xFF202024);
  static const darkText = Color(0xFFF2EFE9);
  static const darkMuted = Color(0xFF9B9B9E);
  static const darkLine = Color(0x29F2EFE9);
}

abstract final class FluxTheme {
  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final surface = isDark
        ? FluxColors.darkSurface.withValues(alpha: 0.55)
        : FluxColors.bone.withValues(alpha: 0.55);
    final text = isDark ? FluxColors.darkText : FluxColors.ink;
    final muted = isDark ? FluxColors.darkMuted : FluxColors.concrete;
    final line = isDark ? FluxColors.darkLine : FluxColors.line;

    final scheme = ColorScheme(
      brightness: brightness,
      primary: FluxColors.red,
      onPrimary: Colors.white,
      secondary: isDark ? FluxColors.redAccent : FluxColors.ink,
      onSecondary: isDark ? Colors.black : Colors.white,
      error: isDark ? const Color(0xFFFF6B6B) : const Color(0xFFB3261E),
      onError: Colors.white,
      surface: surface,
      onSurface: text,
      outline: isDark ? FluxColors.darkLine : FluxColors.concreteLight,
      outlineVariant: isDark ? FluxColors.darkLine : FluxColors.concreteLight,
      shadow: Colors.black,
      surfaceContainerHighest: isDark
          ? FluxColors.darkRaised.withValues(alpha: 0.55)
          : FluxColors.newsprint.withValues(alpha: 0.55),
      surfaceContainerHigh: isDark
          ? FluxColors.darkRaised.withValues(alpha: 0.55)
          : FluxColors.newsprint.withValues(alpha: 0.55),
      surfaceContainer: isDark
          ? FluxColors.darkSurface.withValues(alpha: 0.55)
          : const Color(0xFFE9E5DD).withValues(alpha: 0.55),
      surfaceContainerLow: isDark
          ? FluxColors.darkSurface.withValues(alpha: 0.60)
          : const Color(0xFFEFEBE3).withValues(alpha: 0.60),
      surfaceContainerLowest: isDark
          ? const Color(0xFF0A0A0C).withValues(alpha: 0.60)
          : Colors.white.withValues(alpha: 0.60),
      onSurfaceVariant: muted,
      inverseSurface: isDark ? FluxColors.paper : FluxColors.ink,
      onInverseSurface: isDark ? FluxColors.ink : Colors.white,
      inversePrimary: isDark ? FluxColors.redAccent : FluxColors.red,
    );

    final baseTextTheme = ThemeData(brightness: brightness).textTheme;
    final textTheme = baseTextTheme.copyWith(
      displayLarge: baseTextTheme.displayLarge?.copyWith(
        fontWeight: FontWeight.w900,
        letterSpacing: 1.2,
        color: text,
      ),
      displayMedium: baseTextTheme.displayMedium?.copyWith(
        fontWeight: FontWeight.w900,
        letterSpacing: 0.8,
        color: text,
      ),
      headlineLarge: baseTextTheme.headlineLarge?.copyWith(
        fontWeight: FontWeight.w900,
        letterSpacing: 0.6,
        color: text,
      ),
      headlineMedium: baseTextTheme.headlineMedium?.copyWith(
        fontWeight: FontWeight.w900,
        letterSpacing: 0.4,
        color: text,
      ),
      titleLarge: baseTextTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w900,
        color: text,
      ),
      titleMedium: baseTextTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w800,
        color: text,
      ),
      bodyLarge: baseTextTheme.bodyLarge?.copyWith(
        fontSize: 16,
        height: 1.55,
        color: text,
      ),
      bodyMedium: baseTextTheme.bodyMedium?.copyWith(height: 1.5, color: text),
      labelLarge: baseTextTheme.labelLarge?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: 0.6,
      ),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: Colors.transparent,
      canvasColor: Colors.transparent,
      splashFactory: InkSparkle.splashFactory,
      dividerColor: line,
      appBarTheme: AppBarTheme(
        backgroundColor: isDark
            ? FluxColors.darkSurface.withValues(alpha: 0.65)
            : FluxColors.bone.withValues(alpha: 0.65),
        foregroundColor: text,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        shape: Border(
          bottom: BorderSide(
            color: isDark ? const Color(0xFF3D3D3D) : FluxColors.ink,
            width: 1.5,
          ),
        ),
        titleTextStyle: textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w900,
          letterSpacing: 1.5,
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: isDark
            ? FluxColors.darkSurface.withValues(alpha: 0.78)
            : FluxColors.steel.withValues(alpha: 0.78),
        indicatorColor: FluxColors.red.withValues(alpha: 0.28),
        selectedIconTheme: const IconThemeData(color: Colors.white),
        unselectedIconTheme: IconThemeData(
          color: isDark ? FluxColors.darkMuted : FluxColors.concreteLight,
        ),
        selectedLabelTextStyle: TextStyle(
          color: isDark ? FluxColors.darkText : Colors.white,
          fontWeight: FontWeight.w800,
        ),
        unselectedLabelTextStyle: TextStyle(
          color: isDark ? FluxColors.darkMuted : FluxColors.concreteLight,
          fontWeight: FontWeight.w700,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: isDark
            ? FluxColors.darkSurface.withValues(alpha: 0.78)
            : FluxColors.steel.withValues(alpha: 0.78),
        indicatorColor: FluxColors.red.withValues(alpha: 0.36),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? Colors.white
                : isDark
                ? FluxColors.darkMuted
                : FluxColors.concreteLight,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            color: states.contains(WidgetState.selected)
                ? Colors.white
                : isDark
                ? FluxColors.darkMuted
                : FluxColors.concreteLight,
            fontWeight: FontWeight.w800,
            fontSize: 11,
            letterSpacing: 0.3,
          ),
        ),
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: isDark
            ? FluxColors.darkSurface.withValues(alpha: 0.55)
            : FluxColors.newsprint.withValues(alpha: 0.55),
        shape: const RoundedRectangleBorder(),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(2),
          side: BorderSide(color: line),
        ),
      ),
      listTileTheme: ListTileThemeData(
        textColor: text,
        iconColor: muted,
        selectedColor: FluxColors.red,
        selectedTileColor: isDark
            ? FluxColors.darkRaised
            : FluxColors.red.withValues(alpha: 0.10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
      ),
      dividerTheme: DividerThemeData(color: line, thickness: 1, space: 1),
      popupMenuTheme: PopupMenuThemeData(
        color: isDark ? FluxColors.darkRaised : FluxColors.bone,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.black54,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(2),
          side: BorderSide(color: line),
        ),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(
            isDark ? FluxColors.darkRaised : FluxColors.bone,
          ),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          shadowColor: const WidgetStatePropertyAll(Colors.black54),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(2),
              side: BorderSide(color: line),
            ),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark
            ? FluxColors.darkRaised.withValues(alpha: 0.65)
            : FluxColors.newsprint.withValues(alpha: 0.65),
        labelStyle: TextStyle(color: muted),
        helperStyle: TextStyle(color: muted),
        hintStyle: TextStyle(color: muted),
        border: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(2)),
          borderSide: BorderSide(color: FluxColors.ink),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(2)),
          borderSide: BorderSide(color: FluxColors.concreteLight),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(2)),
          borderSide: BorderSide(color: FluxColors.red, width: 2),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: FluxColors.red,
        foregroundColor: Colors.white,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(2),
          side: const BorderSide(color: FluxColors.ink, width: 2),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: isDark ? FluxColors.darkRaised : FluxColors.ink,
        contentTextStyle: TextStyle(
          color: isDark ? FluxColors.darkText : Colors.white,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(2),
          side: BorderSide(color: line),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? FluxColors.red : muted,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? FluxColors.red.withValues(alpha: 0.35)
              : line,
        ),
      ),
      textTheme: textTheme,
    );
  }
}
