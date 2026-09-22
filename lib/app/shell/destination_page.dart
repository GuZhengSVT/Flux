// 顶层去向 → 页面的分发（T011 引入，T038 收窄为纯分发）。
//
// 为什么现在只剩分发：T011 的三个去向都曾是占位面板，因此当时有一个「壳层占位页」
// 负责画标题、占位标记与 1/2/3 栏占位结构。到 T038 为止，三个去向都已经是真实页面
// （今日新闻 / RSS 阅读 / 设置），继续渲染那套占位结构就会变成**用一个假界面盖住真功能**：
// 界面上写着「占位、无数据」，而它下面其实是能用的页面。那段代码与它用到的文案已随之删除。
//
// 「按宽度呈现 1/2/3 栏」这条架构第 7 节的规则没有丢：判定逻辑仍在 shell_layout.dart，
// 由 test/app/shell_layout_test.dart 逐点钉住（599/600/1099/1100），真实页各自消费它。
library;

import 'package:flutter/material.dart';

import 'package:flux/features/articles/presentation/reading_page.dart';
import 'package:flux/features/news/presentation/news_today_page.dart';
import 'package:flux/features/settings/presentation/settings_page.dart';

import 'app_destination.dart';

/// 按去向渲染对应页面。
class DestinationPage extends StatelessWidget {
  /// 构造分发页。
  const DestinationPage({super.key, required this.destination});

  /// 当前去向。
  final AppDestination destination;

  @override
  Widget build(BuildContext context) => switch (destination) {
    // 今日新闻（T038 起为最小可用页面：日期、生成、进度、结果条目与引用跳转、
    // 证据标签、历史版本）。产品化打磨属 T039，定时执行属 T040。
    AppDestination.today => const NewsTodayPage(),
    // RSS 阅读（T017 起为真实页面；分栏布局与卡片形态属 T019）。
    AppDestination.reading => const ReadingPage(),
    // 我的/设置（T011 起为真实页面）。
    AppDestination.mine => const SettingsPage(),
  };
}
