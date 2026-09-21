// lib/app：启动、导航、主题、国际化与依赖组装（架构第 2.2 节）。
//
// T011 起本文件是应用根组件：MaterialApp（主题 + locale）+ 首次引导/应用壳的分支。
//
// 关键状态都在 Provider 里（组合根见 app_providers.dart），因此这里保持无状态：
//   - 语言（SET-001）与主题（SET-002）由 settingsControllerProvider 提供，
//     写入后界面立即重建——这就是「语言/主题即时切换」的实现方式；
//   - 首次引导是否完成由 onboardingCompletedProvider 提供，完成后直接进主页。
//
// 界面语言切换**不触碰**任何文章、总结或 AI 输出：本文件只改变 UI 文案的解析，
// 历史 AI 结果保持原语言（架构第 7 节末句）。真正的「中英切换不改原文」属于
// T035 的翻译切换，本期只保证 UI 即时切换。
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flux/features/onboarding/application/onboarding_state.dart';
import 'package:flux/features/onboarding/presentation/onboarding_page.dart';
import 'package:flux/features/settings/application/settings_controller.dart';
import 'package:flux/l10n/l10n.dart';

import 'shell/app_shell.dart';
import 'theme/flux_theme.dart';

/// 应用根组件。
class FluxApp extends ConsumerWidget {
  /// 构造应用根组件。
  const FluxApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final SettingsState settings =
        ref.watch(settingsControllerProvider).value ?? SettingsState.initial();
    final AsyncValue<bool> onboarding = ref.watch(onboardingCompletedProvider);

    return MaterialApp(
      onGenerateTitle: (BuildContext context) =>
          AppLocalizations.of(context).appName,
      debugShowCheckedModeBanner: false,
      theme: FluxTheme.light(),
      darkTheme: FluxTheme.dark(),
      // SET-002：system/light/dark。system 时不固定亮度，由 Flutter 依据
      // 当前平台的 platformBrightness 解析（各设备独立解析）。
      themeMode: FluxTheme.resolveMode(
        setting: settings.theme,
        platformBrightness: MediaQuery.platformBrightnessOf(context),
      ),
      // SET-001：system 时传 null，交给系统语言解析；显式选择则固定 locale。
      locale: AppLanguageSetting.resolveLocale(settings.language),
      supportedLocales: supportedLocales,
      localizationsDelegates: const <LocalizationsDelegate<Object>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      // 无匹配语言时回退英文（SET-001）。
      localeResolutionCallback: (Locale? locale, Iterable<Locale> supported) {
        if (locale == null) {
          return fallbackLocale;
        }
        for (final Locale candidate in supported) {
          if (candidate.languageCode == locale.languageCode) {
            return candidate;
          }
        }
        return fallbackLocale;
      },
      home: _rootPage(onboarding),
    );
  }

  /// 首次引导或应用壳。
  ///
  /// 读取失败（例如存储读不出来）时按「未完成」处理：宁可让用户多看一次说明，
  /// 也不要在读不到状态时直接落到一个没有任何解释的空主页。
  static Widget _rootPage(AsyncValue<bool> onboarding) {
    return onboarding.when(
      loading: () => const _ShellSplash(),
      error: (Object error, StackTrace stackTrace) => const OnboardingPage(),
      data: (bool completed) =>
          completed ? const AppShell() : const OnboardingPage(),
    );
  }
}

/// 引导状态读取期间的启动画面。
///
/// 这一帧通常只持续一次数据库往返；用最小实现而不是加动画，避免在慢磁盘上
/// 出现一个与后续界面不连贯的过渡。
class _ShellSplash extends StatelessWidget {
  const _ShellSplash();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}
