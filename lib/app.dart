import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers/refresh_provider.dart';
import 'providers/settings_provider.dart';
import 'screens/home_screen.dart';
import 'theme/flux_theme.dart';
import 'widgets/flux_art_background.dart';

class FluxApp extends ConsumerWidget {
  const FluxApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final backgroundOpacity = settings.backgroundOpacity;
    // 首次进入应用即启动后台定时刷新调度器。
    ref.watch(refreshSchedulerProvider);
    return MaterialApp(
      title: 'Flux',
      debugShowCheckedModeBanner: false,
      theme: FluxTheme.light,
      darkTheme: FluxTheme.dark,
      themeMode: settings.themeMode,
      builder: (context, child) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return Stack(
          textDirection: TextDirection.ltr,
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: FluxArtBackground(
                  dark: isDark,
                  seed: 42,
                  opacity: backgroundOpacity,
                ),
              ),
            ),
            ?child,
          ],
        );
      },
      home: const HomeScreen(),
    );
  }
}
