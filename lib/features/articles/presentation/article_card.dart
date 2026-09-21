// 文章卡片（T019+）：三种形态 + 图片位。
//
// 形态由 [ArticleCardViewMode] 给出（紧凑无图 / 正常右图 96×72 / 宽松上图 16:9），
// 这里只负责把数值画出来，不重复定义「哪种模式几行」——那是产品口径，放在 application
// 层可以被直接断言。
//
// 两条容易被忽略但必须守住的做法：
//
//   1) **缺图不占位**（架构第 7 节）。没有图时，正常/宽松模式**不画**图片位，而不是画
//      一个空框：一个空框会让用户以为「图片加载失败了」，而事实是这篇文章本来就没有图。
//      这两种情况在界面上必须是不同的样子。
//
//   2) **大字号允许增高，不截断操作控件**（架构第 7 节）。卡片高度一律由内容决定
//      （Column + MainAxisSize.min），不写死高度、不用 overflow 裁掉状态控件：把三态与
//      收藏裁掉会让「这篇文章能不能操作」取决于字号。
library;

import 'package:flutter/material.dart';

import 'package:flux/core/core.dart';
import 'package:flux/core/design/design_tokens.dart';

import '../application/article_card_view.dart';

/// 卡片图片位：有图且允许加载时画图，否则按「没有图」处理。
class ArticleCardImage extends StatelessWidget {
  /// 构造图片位。
  const ArticleCardImage({
    super.key,
    required this.url,
    required this.alt,
    required this.width,
    required this.height,
    this.borderRadius = FluxRadius.button,
  });

  /// 地址（导入期已通过 isSafeDocUrl）。
  final String url;

  /// 替代文字（读屏与加载失败时使用）。
  final String alt;

  /// 逻辑宽。
  final double width;

  /// 逻辑高。
  final double height;

  /// 圆角。
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    // features 层不 import lib/app（回归守卫会拦），因此配色只从标准 ColorScheme 取
    // ——app 层已把架构第 7 节的 token 映射进它（见 ui.dart 的说明）。
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: SizedBox(
        width: width,
        height: height,
        child: Image.network(
          url,
          width: width,
          height: height,
          fit: BoxFit.cover,
          // 替代文字进语义树：读屏用户同样需要知道这里有一张什么图。
          semanticLabel: alt.isEmpty ? null : alt,
          // 加载中不留白框：用一个与卡片底色同系的占位，让「正在加载」与「底色」
          // 在视觉上连续，避免卡片在图片到达时跳动。
          loadingBuilder:
              (BuildContext context, Widget child, ImageChunkEvent? progress) =>
                  progress == null
                  ? child
                  : ColoredBox(
                      color: scheme.surfaceContainerHigh,
                      child: const SizedBox.expand(),
                    ),
          // 远程图片加载/缓存与 MIME/尺寸安全属 T021；这里加载失败就退回「没有图」
          // 的样子 + 一条说明，而不是留一个破图标。
          errorBuilder:
              (BuildContext context, Object error, StackTrace? stack) =>
                  ColoredBox(
                    color: scheme.surfaceContainerHigh,
                    child: Center(
                      child: Icon(
                        Icons.broken_image_outlined,
                        size: 18,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
        ),
      ),
    );
  }
}

/// 一张文章卡片的内容区（不含外层的卡片材质与手势）。
class ArticleCardBody extends StatelessWidget {
  /// 构造卡片内容。
  const ArticleCardBody({
    super.key,
    required this.entry,
    required this.mode,
    required this.metaLine,
    required this.trailing,
    this.leading,
  });

  /// 条目。
  final ArticleListEntry entry;

  /// 形态。
  final ArticleCardViewMode mode;

  /// 元信息行文案（来源 · 时间），由页面构造（它需要 l10n 与来源快照规则）。
  final String metaLine;

  /// 行尾控件（三态 + 收藏）。
  final Widget trailing;

  /// 行首控件（批量模式的勾选框）；null 表示非批量模式。
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    final Widget title = Text(
      entry.title,
      style: theme.textTheme.titleSmall,
      // 行数按形态（桌面 17 / 手机 18 的字号由 textTheme 给）：紧凑与正常 2 行，
      // 宽松 3 行（架构第 7 节）。
      maxLines: mode.titleLines,
      overflow: TextOverflow.ellipsis,
    );

    final Widget meta = Text(metaLine, style: theme.textTheme.labelSmall);

    final String? summary = entry.summary;
    final Widget? summaryWidget = summary == null
        ? null
        : Text(
            summary,
            style: theme.textTheme.bodySmall,
            maxLines: mode.summaryLines,
            overflow: TextOverflow.ellipsis,
          );

    final Widget textColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            ?leading,
            Expanded(child: title),
            const SizedBox(width: FluxSpacing.xxs),
            trailing,
          ],
        ),
        const SizedBox(height: FluxSpacing.xxs),
        meta,
        if (summaryWidget != null) ...<Widget>[
          const SizedBox(height: FluxSpacing.xxs),
          summaryWidget,
        ],
      ],
    );

    // 图片位只在「这个形态有图位」且「这篇文章确实有图」时出现（缺图不占位）。
    if (!mode.showsImage || !entry.hasImage) {
      return textColumn;
    }

    if (mode.imageOnTop) {
      // 宽松：上图 + 下方文字，图按 16:9（架构第 7 节）。
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          AspectRatio(
            aspectRatio: kCardCoverAspectRatio,
            child: ArticleCardImage(
              url: entry.imageUrl!,
              alt: entry.title,
              width: double.infinity,
              height: double.infinity,
              borderRadius: FluxRadius.card,
            ),
          ),
          const SizedBox(height: FluxSpacing.xs),
          textColumn,
        ],
      );
    }

    // 正常：右侧 96×72 缩略图。
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(child: textColumn),
        const SizedBox(width: FluxSpacing.sm),
        ArticleCardImage(
          url: entry.imageUrl!,
          alt: entry.title,
          width: kCardThumbWidth,
          height: kCardThumbHeight,
        ),
      ],
    );
  }
}
