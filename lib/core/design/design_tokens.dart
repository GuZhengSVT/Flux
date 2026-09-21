// 设计 token（T011，架构第 7 节「美术与 UI 标准」）。
//
// 为什么放在 lib/core/design 而不是 lib/app/theme：
//   - 配色、间距、圆角、字号是**产品口径**，T012 的通用控件、T019 的卡片与正文
//     排版、T051 的对比度审计都要引用同一份数值。放在 app 层会强迫控件层反向
//     依赖应用壳；
//   - core 不带 Flutter UI 依赖（见 architecture_layering_test），因此这里只放
//     「数值与色值」，FluxTheme 负责把它们翻译成 ThemeData。
//
// 数值来源：架构说明书第 7 节 token 表与正文段落，逐项对应，不自行改口径。
library;

/// 一套主题色（浅色或深色）。
///
/// 字段与架构第 7 节 token 表逐行对应；颜色用 0xAARRGGBB 整数保存，
/// 让 core 层不必依赖 dart:ui。
final class FluxPalette {
  /// 构造一套配色。
  const FluxPalette({
    required this.brightnessName,
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

  /// 亮度名称（light / dark），用于调试与测试断言，不参与绘制。
  final String brightnessName;

  /// 页面底色。
  final int background;

  /// 卡片与面板底色。
  final int surface;

  /// 主要文字。
  final int textPrimary;

  /// 次要文字（说明、时间戳、元数据）。
  final int textSecondary;

  /// 分隔线与边框。
  final int border;

  /// 强调色（主按钮、选中标记）。
  final int accent;

  /// 选中项底色。
  final int selectedSurface;

  /// 危险操作。
  final int danger;

  /// 警告与提醒。
  final int warning;

  /// 阅读纸张背景（SET-007 默认）。
  final int readingPaper;

  /// 浅色主题配色（架构第 7 节 token 表左列）。
  static const FluxPalette light = FluxPalette(
    brightnessName: 'light',
    background: 0xFFF6F7F9,
    surface: 0xFFFFFFFF,
    textPrimary: 0xFF20242B,
    textSecondary: 0xFF596273,
    border: 0xFFD9DEE7,
    accent: 0xFF315E52,
    selectedSurface: 0xFFE8F0EC,
    danger: 0xFFB42318,
    warning: 0xFF8A5700,
    readingPaper: 0xFFF4EEDC,
  );

  /// 深色主题配色（架构第 7 节 token 表右列）。
  static const FluxPalette dark = FluxPalette(
    brightnessName: 'dark',
    background: 0xFF15181C,
    surface: 0xFF1C2127,
    textPrimary: 0xFFE7EBF0,
    textSecondary: 0xFFA7B0BE,
    border: 0xFF39424F,
    accent: 0xFF8EC9B1,
    selectedSurface: 0xFF233A32,
    danger: 0xFFFF9F94,
    warning: 0xFFE8BE6F,
    readingPaper: 0xFF20221F,
  );

  /// 按名称取配色；未知名称回退浅色（壳层必须始终能显示，不抛异常）。
  static FluxPalette byName(String name) =>
      name == dark.brightnessName ? dark : light;
}

/// 间距阶梯（架构第 7 节：4/8/12/16/24/32/48）。
abstract final class FluxSpacing {
  /// 4。
  static const double xxs = 4;

  /// 8。
  static const double xs = 8;

  /// 12。
  static const double sm = 12;

  /// 16：手机左右边距。
  static const double md = 16;

  /// 24：桌面正文边距下界。
  static const double lg = 24;

  /// 32：桌面正文边距上界。
  static const double xl = 32;

  /// 48。
  static const double xxl = 48;

  /// 完整阶梯，供测试断言与控件遍历使用。
  static const List<double> scale = <double>[xxs, xs, sm, md, lg, xl, xxl];

  /// 手机左右边距。
  static const double phoneGutter = md;

  /// 桌面正文左右边距下界。
  static const double desktopGutterMin = lg;

  /// 桌面正文左右边距上界。
  static const double desktopGutterMax = xl;
}

/// 圆角（架构第 7 节：按钮/卡片/弹窗 8/12/16）。
abstract final class FluxRadius {
  /// 8：按钮与输入框。
  static const double button = 8;

  /// 12：卡片。
  static const double card = 12;

  /// 16：弹窗与面板。
  static const double dialog = 16;

  /// 完整阶梯。
  static const List<double> scale = <double>[button, card, dialog];
}

/// 布局断点（架构第 7 节）。
abstract final class FluxBreakpoints {
  /// 600：单栏转双栏，也是导航从底部栏切到侧边栏的阈值。
  static const double twoColumn = 600;

  /// 1100：双栏转三栏。
  static const double threeColumn = 1100;

  /// 双栏布局的来源栏宽度下界。
  static const double sourcePaneMin = 220;

  /// 双栏布局的来源栏宽度上界（架构第 7 节 220–240）。
  static const double sourcePaneMax = 240;

  /// 三栏布局的来源栏宽度。
  static const double sourcePaneWidth = 220;

  /// 三栏布局的列表栏宽度。
  static const double listPaneWidth = 300;

  /// 三栏布局正文栏最小宽度；不足时退回双栏。
  static const double bodyPaneMin = 560;

  /// 桌面窗口最小宽度（架构第 7 节：初值 720×560）。
  static const double minWindowWidth = 720;

  /// 桌面窗口最小高度。
  static const double minWindowHeight = 560;

  /// 正文最大宽度（架构第 7 节：正文最大宽 720）。
  static const double maxBodyWidth = 720;
}

/// 正文排版常量（架构第 7 节：正文 18、行高 1.7、段间距 0.8em）。
abstract final class FluxTypography {
  /// 正文字号。
  static const double bodyFontSize = 18;

  /// 正文行高倍数。
  static const double bodyLineHeight = 1.7;

  /// 段间距（以 em 计；0.8em 即 0.8 倍字号）。
  static const double paragraphSpacingEm = 0.8;

  /// 段间距绝对值（由字号换算，供排版直接使用）。
  static const double paragraphSpacing = bodyFontSize * paragraphSpacingEm;

  /// 详情页标题字号下界（架构第 7 节：详情标题 28–32）。
  static const double detailTitleMin = 28;

  /// 详情页标题字号上界。
  static const double detailTitleMax = 32;

  /// 卡片标题字号（桌面）。
  static const double cardTitleDesktop = 17;

  /// 卡片标题字号（手机）。
  static const double cardTitleMobile = 18;
}

/// 动效时长（架构第 7 节：动效 120–200ms）。
abstract final class FluxMotion {
  /// 动效时长下界。
  static const Duration min = Duration(milliseconds: 120);

  /// 动效时长上界。
  static const Duration max = Duration(milliseconds: 200);

  /// 默认过渡时长（阶梯内取值，页面切换与状态变化共用）。
  static const Duration standard = Duration(milliseconds: 160);
}
