// 顶层去向（T011，架构第 3 节功能树）。
//
// 为什么用枚举而不是一个可扩展列表：架构第 3 节把顶层结构固定为**三个**去向
// （首次启动是引导流程、不占导航位）。用枚举可以让「导航项与页面」在编译期一一
// 对应，新增去向必须显式改这里，不会出现「加了导航项但忘了页面」。
library;

import 'package:flutter/material.dart';

import 'package:flux/l10n/l10n.dart';

/// 顶层导航去向。
enum AppDestination {
  /// 今日新闻（架构第 3 节；生成与核验属 T036–T040）。
  today,

  /// RSS 阅读（列表、三态、正文；属 T013–T024）。
  reading,

  /// 我的/设置（无 Flux 账号；属 T011 起、其余各任务逐步补齐）。
  mine;

  /// 导航图标。
  ///
  /// 使用 Material 内置图标而不是自绘 SVG：原创 SVG 图标集属 T012 的交付范围，
  /// 这里先给出可用的最小集合，T012 落地时替换本方法即可（调用点无需改动）。
  IconData get icon => switch (this) {
    AppDestination.today => Icons.article_outlined,
    AppDestination.reading => Icons.rss_feed_outlined,
    AppDestination.mine => Icons.person_outline,
  };

  /// 选中态图标。
  IconData get selectedIcon => switch (this) {
    AppDestination.today => Icons.article,
    AppDestination.reading => Icons.rss_feed,
    AppDestination.mine => Icons.person,
  };

  /// 导航标签（来自本地化资源，不硬编码文案）。
  String label(AppLocalizations l10n) => switch (this) {
    AppDestination.today => l10n.navToday,
    AppDestination.reading => l10n.navReading,
    AppDestination.mine => l10n.navMine,
  };

  /// 该去向当前对应的计划任务号（用于占位页明确说明「谁负责实现」）。
  String get plannedTasks => switch (this) {
    AppDestination.today => 'T036–T040',
    AppDestination.reading => 'T013–T024',
    AppDestination.mine => 'T011 起，其余见各 SET 项对应任务',
  };
}

/// 全部去向，顺序即导航顺序。
const List<AppDestination> appDestinations = <AppDestination>[
  AppDestination.today,
  AppDestination.reading,
  AppDestination.mine,
];
