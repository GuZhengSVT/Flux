// lib/app：启动、导航、主题、国际化与依赖组装（架构第 2.2 节）。
//
// T007 只建立目录与最小可运行入口，不实现业务页面：真实的导航/主题/l10n
// 在 T011/T012 落地。这里保留一个能编译、能挂 ProviderScope 的壳，
// 用来证明依赖方向与工具链在 M0 阶段就是通的。
library;

import 'package:flutter/material.dart';

/// 应用根组件。
///
/// 只负责最外层 MaterialApp；具体页面注入在 T011 由导航与用例层接管。
class FluxApp extends StatelessWidget {
  const FluxApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flux',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF315E52)),
        useMaterial3: true,
      ),
      home: const SkeletonHomePage(),
    );
  }
}

/// M0 阶段的占位首页：明确标注为骨架，避免被误当成已实现的“今日新闻”。
class SkeletonHomePage extends StatelessWidget {
  const SkeletonHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Flux')),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Flux M0 骨架已就绪（T007）。\n'
            '业务页面将在 T011 起实现。',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
