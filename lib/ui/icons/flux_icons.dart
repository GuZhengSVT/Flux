// 原创 SVG 图标集（T012，架构第 7 节）。
//
// 设计约束（写在代码里，便于评审时逐条核对，而不是只靠人眼看图）：
//   1) 每个图标只有**几何线条**，无渐变、无阴影、无位图；低饱和极简风格要求
//      图标在浅深两套底色上都能被看清，因此素材本身不带颜色，靠 currentColor
//      继承文本/强调色（见 FluxSvgIcon）；
//   2) 20 与 24 两套逻辑尺寸，各自的线宽不同（1.5 / 1.75），**不是把 24 缩放成 20**：
//      直接缩放会让 20 尺寸的线条变细到 <1.5，看起来比同排图标淡；
//   3) 三态（unread/read/later）与收藏（star）是**两组不同语义**的图标，这直接
//      对应架构第 7 节「状态三选一占一个控件位置，收藏单独星形」；
//   4) 加精徽标用盾形而不是星形：加精是来源属性（SET-023），收藏是文章操作，
//      两者若共用星形，用户会以为它们是同一件事。
//
// 素材许可：每个 SVG 顶部都有 `Original artwork for Flux, MIT License
// (c) 2025 GuZhengSVT`，与仓库根 LICENSE 一致；测试会逐文件校验该声明存在。
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'package:flux/core/design/design_tokens.dart';

/// 图标的逻辑尺寸档位（架构第 7 节：20/24 两套）。
enum FluxIconSize {
  /// 20：移动端与紧凑列表。
  small(FluxIconTokens.sizeSmall, '20'),

  /// 24：桌面导航与工具栏。
  regular(FluxIconTokens.sizeRegular, '24');

  const FluxIconSize(this.logicalSize, this.assetSuffix);

  /// 逻辑边长。
  final double logicalSize;

  /// 资源文件名后缀（`-20` / `-24`）。
  final String assetSuffix;
}

/// 本工程交付的原创图标。
///
/// 用枚举而不是裸字符串路径：图标名拼错会在编译期暴露，而不是在运行时渲染成
/// 一个缺失占位（那在深色主题下几乎看不出来）。
enum FluxIcon {
  /// 今日（日记本 + 太阳）：今日新闻去向。
  today('today'),

  /// RSS（圆点 + 同心波）：RSS 阅读去向。
  rss('rss'),

  /// 设置（三条滑杆）：我的/设置去向。
  sliders('sliders'),

  /// 未读（空心环 + 实心点）。
  stateUnread('state-unread'),

  /// 已读（空心环 + 对勾）。
  stateRead('state-read'),

  /// 稍后再读（空心环 + 时钟）。
  stateLater('state-later'),

  /// 收藏（描边星形）。
  star('star'),

  /// 收藏（实心星形，与描边版共用同一路径）。
  starFilled('star-filled'),

  /// 加精徽标（盾形 + 小星）。
  featuredBadge('badge-featured'),

  /// 空态图形（收件盘）。
  inboxEmpty('inbox-empty'),

  /// 信息提示（圆圈 + i），状态横幅用。
  alertInfo('alert-info'),

  /// 警告提示（三角 + !），状态横幅用。
  alertWarning('alert-warning'),

  /// 错误提示（圆圈 + ×），状态横幅与失败态用。
  alertError('alert-error'),

  /// 成功标记（对勾），成功态用。
  markCheck('mark-check');

  const FluxIcon(this.fileBaseName);

  /// 资源文件的基础名（不含尺寸后缀与扩展名）。
  final String fileBaseName;

  /// 指定尺寸下的资源路径。
  String assetPath(FluxIconSize size) =>
      'assets/icons/$fileBaseName-${size.assetSuffix}.svg';

  /// 两套尺寸的资源路径（供资源清单测试逐项校验存在性）。
  List<String> get allAssetPaths =>
      FluxIconSize.values.map(assetPath).toList(growable: false);

  /// 该图标的两套尺寸线宽（SVG 内已画好，这里用于测试与自绘场合）。
  double strokeWidthFor(FluxIconSize size) => switch (size) {
    FluxIconSize.small => FluxIconTokens.strokeSmall,
    FluxIconSize.regular => FluxIconTokens.strokeRegular,
  };
}

/// 原创 SVG 图标的渲染控件。
///
/// 为什么用 `colorFilter: srcIn` 而不是给 SVG 填死颜色：
///   - 素材用 `stroke="currentColor"`，本控件把 SVG 的 `currentColor` 解析为传入的
///     [color]（通过 SvgTheme），因此图标天然跟随主题与控件状态（悬停/禁用/错误）
///     变色，不需要为每个状态准备一份素材；
///   - 保留 float 缩放：矢量在任何 DPR 下都清晰，不使用位图缓存。
///
/// [semanticsLabel] 必填：架构第 7 节要求「图标有读屏标签」。刻意不提供默认值，
/// 迫使调用方想清楚这个图标对读屏用户意味着什么；纯装饰性图标用 [excludeFromSemantics]。
class FluxSvgIcon extends StatelessWidget {
  /// 构造图标。
  const FluxSvgIcon(
    this.icon, {
    super.key,
    this.size = FluxIconSize.regular,
    this.color,
    this.semanticsLabel,
    this.excludeFromSemantics = false,
  });

  /// 使用的图标。
  final FluxIcon icon;

  /// 尺寸档位。
  final FluxIconSize size;

  /// 颜色；为空时继承当前 IconTheme（与 Material 图标的行为一致）。
  final Color? color;

  /// 读屏标签。
  final String? semanticsLabel;

  /// 是否作为装饰从语义树中排除（此时 [semanticsLabel] 被忽略）。
  final bool excludeFromSemantics;

  @override
  Widget build(BuildContext context) {
    final Color resolved =
        color ?? IconTheme.of(context).color ?? const Color(0xFF000000);
    return SvgPicture.asset(
      icon.assetPath(size),
      width: size.logicalSize,
      height: size.logicalSize,
      // currentColor 由 SvgTheme 提供；素材里的 stroke="currentColor" 因此跟随
      // 传入颜色，无需为每个状态准备单独的素材文件。
      theme: SvgTheme(currentColor: resolved),
      colorFilter: ColorFilter.mode(resolved, BlendMode.srcIn),
      semanticsLabel: semanticsLabel,
      excludeFromSemantics: excludeFromSemantics,
    );
  }
}
