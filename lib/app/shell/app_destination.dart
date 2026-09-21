// 顶层去向（T011，架构第 3 节功能树）。
//
// 为什么用枚举而不是一个可扩展列表：架构第 3 节把顶层结构固定为**三个**去向
// （首次启动是引导流程、不占导航位）。用枚举可以让「导航项与页面」在编译期一一
// 对应，新增去向必须显式改这里，不会出现「加了导航项但忘了页面」。
library;

import 'package:flux/l10n/l10n.dart';
import 'package:flux/ui/ui.dart';

/// 顶层导航去向。
enum AppDestination {
  /// 今日新闻（架构第 3 节；生成与核验属 T036–T040）。
  today,

  /// RSS 阅读（列表、三态、正文；属 T013–T024）。
  reading,

  /// 我的/设置（无 Flux 账号；属 T011 起、其余各任务逐步补齐）。
  mine;

  /// 导航图标（T012 交付的原创 SVG）。
  ///
  /// T011 曾用 Material 内置图标占位并注明「T012 落地时替换本方法即可」，这里
  /// 正是那次替换：调用点（app_shell.dart）不需要改动，因为类型换成了 FluxIcon
  /// 之后由同一个 FluxSvgIcon 控件渲染。
  FluxIcon get icon => switch (this) {
    AppDestination.today => FluxIcon.today,
    AppDestination.reading => FluxIcon.rss,
    AppDestination.mine => FluxIcon.sliders,
  };

  /// 选中态图标。
  ///
  /// 与 [icon] 是同一个字形。**不**刻意造一个「实心版」来假装有选中态：这三个
  /// 图标是线条几何图形（日记本 / 同心波 / 滑杆），没有合理的实心变体，硬填色
  /// 会让线条糊成一团。选中状态由主题的指示底色（selectedSurface）与强调色共同
  /// 表达——两者都由 FluxTheme 按 token 生成，视觉差异足够明显。
  FluxIcon get selectedIcon => icon;

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
