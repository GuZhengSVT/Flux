// 共享控件测试装配（T012）。
//
// 与 test/app/test_harness.dart 的分工：那个装配带 Riverpod 与真实设置仓储（用于
// T011 的页面行为）；共享控件不依赖任何 Provider，只需要「与生产一致的
// MaterialApp + 主题 + 本地化」。因此这里给一个更小的包装，避免控件测试被迫
// 引入数据库与 ProviderScope。
//
// 刻意复用 FluxTheme：控件测试要验证的正是「控件在真实主题 token 下的状态视觉」，
// 如果这里手写一个 ThemeData，测试通过也不能说明生产里的样子是对的。
library;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flux/app/theme/flux_theme.dart';
import 'package:flux/l10n/l10n.dart';

/// 把测试窗口设为指定逻辑尺寸（影响 LayoutBuilder 与断点的真实约束）。
///
/// 与 [wrapControl] 的 surfaceSize 分工不同：那个只改 MediaQuery 里的**声明值**，
/// 真实渲染视口仍是默认 800×600。只要被测内容会超过 600 高（例如状态矩阵），就
/// 必须用这个函数改真实视口，否则 RenderFlex 会在 600 处溢出——而溢出在测试里是
/// 断言失败，不是「看起来挤了一点」。
Future<void> setControlSurfaceSize(WidgetTester tester, Size size) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

/// 把被测控件包进与生产一致的 MaterialApp。
Widget wrapControl(
  Widget child, {
  Locale locale = const Locale('zh'),
  ThemeMode themeMode = ThemeMode.light,
  Brightness platformBrightness = Brightness.light,
  Size surfaceSize = const Size(720, 480),
}) {
  return MediaQuery(
    data: MediaQueryData(
      platformBrightness: platformBrightness,
      size: surfaceSize,
    ),
    child: MaterialApp(
      theme: FluxTheme.light(),
      darkTheme: FluxTheme.dark(),
      themeMode: themeMode,
      locale: locale,
      supportedLocales: supportedLocales,
      localizationsDelegates: const <LocalizationsDelegate<Object>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(body: Center(child: child)),
    ),
  );
}

/// 在测试窗口内移动鼠标到指定控件（触发真实的悬停/按下路径）。
///
/// 为什么不用 tester.tap 来测悬停：tap 只产生一次按下抬起，无法让控件停留在
/// hover 状态，也就测不出「悬停与默认视觉必须不同」。
Future<TestGesture> hoverOver(WidgetTester tester, Finder finder) async {
  final TestGesture gesture = await tester.createGesture(
    kind: PointerDeviceKind.mouse,
  );
  addTearDown(gesture.removePointer);
  await gesture.addPointer(location: Offset.zero);
  addTearDown(() => gesture.moveTo(Offset.zero));
  await gesture.moveTo(tester.getCenter(finder));
  await tester.pump();
  return gesture;
}
