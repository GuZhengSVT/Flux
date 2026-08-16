import 'package:flutter/material.dart';

/// 简洁现代视觉 token。
abstract final class FluxColors {
  static const red = Color(0xFFE53935);
  static const redAccent = Color(0xFFFF6F61);
  static const black = Color(0xFF111111);
  static const ink = Color(0xFF1A1A1A);
  static const paper = Color(0xFFF7F4ED);
  static const gray = Color(0xFF8A8A8E);
  static const line = Color(0x1F111111);

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
    final base = isDark ? FluxColors.darkBg : FluxColors.paper;
    final surface = isDark ? FluxColors.darkSurface : Colors.white;
    final text = isDark ? FluxColors.darkText : FluxColors.black;
    final muted = isDark ? FluxColors.darkMuted : FluxColors.gray;
    final line = isDark ? FluxColors.darkLine : FluxColors.line;

    final scheme = ColorScheme(
      brightness: brightness,
      primary: FluxColors.red,
      onPrimary: Colors.white,
      secondary: isDark ? FluxColors.redAccent : FluxColors.black,
      onSecondary: isDark ? Colors.black : Colors.white,
      error: isDark ? const Color(0xFFFF6B6B) : const Color(0xFFB3261E),
      onError: Colors.white,
      surface: surface,
      onSurface: text,
      outline: line,
      outlineVariant: line,
      shadow: Colors.black,
      surfaceContainerHighest: isDark
          ? FluxColors.darkRaised
          : const Color(0xFFF0ECE3),
      surfaceContainerHigh: isDark
          ? FluxColors.darkRaised
          : const Color(0xFFF2EFE7),
      surfaceContainer: isDark
          ? FluxColors.darkSurface
          : const Color(0xFFF4F1EA),
      surfaceContainerLow: isDark
          ? FluxColors.darkSurface
          : const Color(0xFFF6F3ED),
      surfaceContainerLowest: isDark ? const Color(0xFF0A0A0C) : Colors.white,
      onSurfaceVariant: muted,
      inverseSurface: isDark ? FluxColors.paper : FluxColors.black,
      onInverseSurface: isDark ? FluxColors.black : Colors.white,
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
        fontWeight: FontWeight.w800,
        letterSpacing: 0.4,
        color: text,
      ),
      headlineMedium: baseTextTheme.headlineMedium?.copyWith(
        fontWeight: FontWeight.w800,
        color: text,
      ),
      titleLarge: baseTextTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w800,
        color: text,
      ),
      titleMedium: baseTextTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w700,
        color: text,
      ),
      bodyLarge: baseTextTheme.bodyLarge?.copyWith(
        fontSize: 16,
        height: 1.55,
        color: text,
      ),
      bodyMedium: baseTextTheme.bodyMedium?.copyWith(height: 1.5, color: text),
      labelLarge: baseTextTheme.labelLarge?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: 0.6,
      ),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: base,
      canvasColor: base,
      splashFactory: InkSparkle.splashFactory,
      dividerColor: line,
      appBarTheme: AppBarTheme(
        backgroundColor: base,
        foregroundColor: text,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w900,
          letterSpacing: 1.5,
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: base,
        indicatorColor: FluxColors.red.withValues(alpha: 0.16),
        selectedIconTheme: const IconThemeData(color: FluxColors.red),
        unselectedIconTheme: IconThemeData(color: muted),
        selectedLabelTextStyle: TextStyle(
          color: text,
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelTextStyle: TextStyle(color: muted),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
      ),
      dividerTheme: DividerThemeData(color: line, thickness: 1, space: 1),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? FluxColors.darkRaised : Colors.white,
        border: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(2)),
          borderSide: BorderSide(color: FluxColors.red),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(2)),
          borderSide: BorderSide(color: line),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(2)),
          borderSide: BorderSide(color: FluxColors.red, width: 2),
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
