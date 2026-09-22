// 块级控件（T019）：代码块（静态高亮/折叠/复制）、图片占位、表格、未解析回退块。
//
// 从渲染器主体拆出来，使「代码块的折叠与复制」与「表格的列对齐」这两处最容易出错的细节
// 各自独立可读，而不是埋在一条几百行的 switch 里。本文件不解释标记——它只画已知节点。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flux/core/core.dart';
import 'package:flux/core/design/design_tokens.dart';
import 'package:flux/l10n/l10n.dart';
import 'package:flux/ui/ui.dart';

import 'code_highlighter.dart';
import 'doc_inline.dart';
import 'doc_theme.dart';
import 'article_image_view.dart';

/// 无序列表的圆点标记。
const String bulletMarker = '\u2022';

/// 一个列表项：标记（序号 / 圆点 / 勾选框）+ 内容。
class ListItemView extends StatelessWidget {
  /// 构造列表项。
  const ListItemView({
    super.key,
    required this.marker,
    required this.item,
    required this.typography,
    required this.blocksBuilder,
  });

  /// 标记文本（有序列表的序号或圆点）。
  final String marker;

  /// 列表项。
  final DocListItem item;

  /// 排版。
  final DocTypography typography;

  /// 渲染项内块级内容的构造器。
  ///
  /// 用回调而不是直接 import 渲染器：渲染器要画列表项，列表项又要画块，直接互相持有
  /// 会让两个文件成为事实上的一个（改一个必须同时改另一个）。回调把「谁来画子块」这个
  /// 决定留在渲染器里。
  final Widget Function(DocNode node) blocksBuilder;

  @override
  Widget build(BuildContext context) {
    final bool? checked = item.checked;
    final Widget markerWidget = checked != null
        ? Icon(
            checked ? Icons.check_box : Icons.check_box_outline_blank,
            size: typography.baseSize * 0.95,
            color: checked
                ? typography.theme.accent
                : typography.theme.textSecondary,
          )
        : SizedBox(
            width: typography.baseSize * 1.4,
            child: Text(marker, style: typography.body),
          );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: EdgeInsets.only(right: 6, top: checked != null ? 3 : 0),
          child: markerWidget,
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              for (final DocNode child in item.children)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: blocksBuilder(child),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 围栏代码块：语言标签 + 复制 + 折叠 + 静态高亮。
class CodeBlockView extends StatefulWidget {
  /// 构造代码块。
  const CodeBlockView({
    super.key,
    required this.code,
    required this.language,
    required this.typography,
  });

  /// 代码原文。
  final String code;

  /// 语言标识；null 或未知时按纯文本显示。
  final String? language;

  /// 排版。
  final DocTypography typography;

  @override
  State<CodeBlockView> createState() => _CodeBlockViewState();
}

class _CodeBlockViewState extends State<CodeBlockView> {
  bool _expanded = false;

  int get _lineCount => widget.code.split('\n').length;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final DocTheme theme = widget.typography.theme;
    final bool long = _lineCount > FluxTypography.codeCollapseThresholdLines;
    final bool collapsed = long && !_expanded;
    // 未知语言按纯文本显示：界面显示「纯文本」而不是一个我们其实不认识的语言名，
    // 避免出现「标着 dart 却完全没有颜色」这种自相矛盾的标注。
    final String label = isHighlightableLanguage(widget.language)
        ? widget.language!
        : l10n.readingCodePlainText;
    final List<HighlightSpan> spans = highlightCode(
      widget.code,
      widget.language,
    );

    return Container(
      decoration: BoxDecoration(
        color: theme.codeBackground,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 6, 0),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: widget.typography.baseSize * 0.7,
                      color: theme.textSecondary,
                    ),
                  ),
                ),
                if (long)
                  TextButton(
                    onPressed: () => setState(() => _expanded = !_expanded),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    child: Text(
                      collapsed
                          ? l10n.readingCodeExpand(_lineCount)
                          : l10n.readingCodeCollapse,
                    ),
                  ),
                CopyCodeButton(code: widget.code),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: collapsed
                    ? widget.typography.baseSize * 12
                    : double.infinity,
              ),
              child: ClipRect(
                child: SingleChildScrollView(
                  // 长代码在**块内**横向滚动（架构第 7 节），因此一行很长的代码不会把
                  // 整个阅读栏撑宽。
                  scrollDirection: Axis.horizontal,
                  child: SingleChildScrollView(
                    child: SelectableText.rich(
                      TextSpan(
                        style: widget.typography.code,
                        children: <InlineSpan>[
                          for (final HighlightSpan span in spans)
                            TextSpan(
                              text: span.text,
                              style: _styleFor(span.kind, widget.typography),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 类别 → 样式。颜色全部由 token 派生，不新造色值。
  static TextStyle _styleFor(HighlightKind kind, DocTypography typography) {
    final DocTheme theme = typography.theme;
    final TextStyle base = typography.code;
    final bool dark = theme.brightness == Brightness.dark;
    return switch (kind) {
      HighlightKind.plain => base,
      // 关键字：强调色 + 中等字重（在深浅两套底色上都有足够对比度）。
      HighlightKind.keyword => base.copyWith(
        color: theme.accent,
        fontWeight: FontWeight.w600,
      ),
      // 字符串：次要文字色。刻意不用绿色系——它不在 token 表里，而自造一个色值会让
      // 「配色来自架构第 7 节」这条约束在某一个文件里失效。
      HighlightKind.string => base.copyWith(color: theme.textSecondary),
      HighlightKind.comment => base.copyWith(
        color: theme.textSecondary,
        fontStyle: FontStyle.italic,
      ),
      HighlightKind.number => base.copyWith(
        color: dark ? theme.accent : theme.textPrimary,
        fontWeight: FontWeight.w600,
      ),
      HighlightKind.type => base.copyWith(
        color: dark ? theme.textPrimary : theme.accent,
      ),
    };
  }
}

/// 复制代码块的按钮。
class CopyCodeButton extends StatelessWidget {
  /// 构造按钮。
  const CopyCodeButton({super.key, required this.code});

  /// 待复制的代码。
  final String code;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Tooltip(
      message: l10n.readingCodeCopy,
      child: TextButton.icon(
        onPressed: () async {
          final ScaffoldMessengerState messenger = ScaffoldMessenger.of(
            context,
          );
          await Clipboard.setData(ClipboardData(text: code));
          // 复制反馈放在 SnackBar 而不是就地改按钮文案：就地改会让按钮宽度跳动，
          // 而代码块顶栏的宽度变化会连带整段代码位移。
          messenger.hideCurrentSnackBar();
          messenger.showSnackBar(
            SnackBar(content: Text(l10n.readingCodeCopied)),
          );
        },
        icon: const Icon(Icons.copy, size: 14),
        label: Text(l10n.readingCodeCopy),
        style: TextButton.styleFrom(
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 8),
        ),
      ),
    );
  }
}

/// 图片位（T020 可点开查看器；T021 起走受控缓存管线）。
///
/// 四条与产品规则对应的选择：
///   1) **保留版位**（架构 4.2）：一张没有加载的图仍然占住它该占的位置，并显示替代
///      文字与地址，使正文不会莫名其妙地断掉；
///   2) **SET-012 关闭时不自动加载**（架构 4.2 的「远端图片开关」）：画占位框而不是
///      发起请求，并说明「点击可单独下载」——关掉自动加载不等于不能看这一张；
///   3) **可点**：无论是否加载了图，点击都打开查看器（全屏可缩放、可保存）；
///   4) **失败不阻塞文章**（T021）：加载失败只画这一张的占位与重试按钮，正文其余
///      部分与其它图片继续渲染。
class ImageBlockView extends StatelessWidget {
  /// 构造图片占位。
  const ImageBlockView({
    super.key,
    required this.url,
    required this.alt,
    required this.typography,
    this.autoLoad = true,
    this.onTap,
  });

  /// 地址（已通过 [isSafeDocUrl]）。
  final String url;

  /// 替代文字。
  final String alt;

  /// 排版。
  final DocTypography typography;

  /// 是否自动加载远程图片（SET-012）。false 时只画占位框，但**仍然可点**。
  final bool autoLoad;

  /// 点击回调（打开查看器）。
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final DocTheme theme = typography.theme;
    final Widget framed = Container(
      width: double.infinity,
      height: 140,
      decoration: BoxDecoration(
        color: theme.codeBackground,
        border: Border.all(color: theme.border),
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.center,
      clipBehavior: Clip.antiAlias,
      child: autoLoad
          // 真实加载：经 T021 的受控缓存管线（MIME/体积/魔数/私网校验 + 磁盘 LRU）。
          // 失败时退回占位的内容（图标 + 替代文字 + 说明）与重试按钮，而不是破图标。
          ? ArticleImageView(
              url: url,
              alt: alt,
              width: double.infinity,
              height: 140,
              fit: BoxFit.cover,
              // 正文图最多显示到约 720 逻辑宽（架构第 7 节的正文最大宽），按它解码
              // 即可覆盖常见缩放；更大的解码只白占内存。
              decodeTargetWidth: 720,
              // 加载中仍显示替代文字（叠加一个进度指示），而不是只给一个转圈：
              // 一块没有文字的空框会让读者以为这张图没有说明，而替代文字在图片
              // 到达之前正是他判断「这里是什么」的唯一依据。
              loadingBuilder: (BuildContext context) => Stack(
                alignment: Alignment.center,
                children: <Widget>[
                  _placeholder(l10n, theme, failed: false),
                  const FluxLoadingIndicator(size: 16),
                ],
              ),
              errorBuilder: (BuildContext context) =>
                  _placeholder(l10n, theme, failed: true),
            )
          : _placeholder(l10n, theme, failed: false),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        // 可点：整块图片位是一个按钮的热区（手机上 140 高足够大；桌面上鼠标任意位置
        // 都能点中）。用 InkWell 而不是 GestureDetector：需要焦点与键盘可达。
        //
        // 自带一层透明 Material：渲染器是**纯映射**，不该要求宿主必须提供 Material
        // 祖先——golden 与组件测试直接挂 DocDocumentView，没有 Material 时 InkWell 会
        // 直接断言失败（实测）。自带之后，谁挂这段渲染都能得到同样的行为。
        Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(8),
            child: framed,
          ),
        ),
        const SizedBox(height: 4),
        SelectableText(
          // 关闭自动加载时说明「点击可单独下载」，而不是说「属 T021」——T021 是缓存
          // 与安全，与「这一张能不能看」是两件事。
          autoLoad ? l10n.readingImageNotice : l10n.readingImageAutoLoadOff,
          style: typography.secondary.copyWith(
            fontSize: typography.baseSize * 0.7,
          ),
        ),
        SelectableText(
          autoLoad ? url : '${l10n.readingImageTapToDownload} · $url',
          style: typography.secondary.copyWith(
            fontSize: typography.baseSize * 0.7,
          ),
        ),
      ],
    );
  }

  /// 占位内容（未加载或加载失败时）。
  Widget _placeholder(
    AppLocalizations l10n,
    DocTheme theme, {
    required bool failed,
  }) => Semantics(
    // 整块作为一个语义节点播报：内部是图标 + 替代文字 + 失败说明三段，分开播报会
    // 变成「图片 说明 图片加载失败」这样一串碎片，而用户需要的是「这里本该有一张图，
    // 它叫什么」。
    label: l10n.a11yImagePlaceholder(
      alt.isEmpty ? l10n.readingImagePlaceholder : alt,
    ),
    container: true,
    child: ExcludeSemantics(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            failed ? Icons.broken_image_outlined : Icons.image_outlined,
            color: theme.textSecondary,
          ),
          const SizedBox(height: 6),
          Text(
            alt.isEmpty ? l10n.readingImagePlaceholder : alt,
            style: typography.secondary,
            textAlign: TextAlign.center,
          ),
          if (failed) ...<Widget>[
            const SizedBox(height: 4),
            Text(
              l10n.readingImageLoadFailed,
              style: typography.secondary,
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    ),
  );
}

/// 表格：按列对齐，宽表在块内横向滚动。
class TableView extends StatelessWidget {
  /// 构造表格。
  const TableView({
    super.key,
    required this.table,
    required this.typography,
    this.onOpenLink,
    this.onCopyLink,
  });

  /// 表格节点。
  final DocTable table;

  /// 排版。
  final DocTypography typography;

  /// 链接回调。
  final void Function(String url)? onOpenLink;

  /// 复制链接回调。
  final void Function(String url)? onCopyLink;

  @override
  Widget build(BuildContext context) {
    final DocTheme theme = typography.theme;
    final List<TableRow> rows = <TableRow>[
      TableRow(
        decoration: BoxDecoration(color: theme.codeBackground),
        children: <Widget>[
          for (int i = 0; i < table.header.length; i++)
            _cell(table.header[i], i, bold: true),
        ],
      ),
      for (final List<List<DocInline>> row in table.rows)
        TableRow(
          children: <Widget>[
            for (int i = 0; i < row.length; i++) _cell(row[i], i, bold: false),
          ],
        ),
    ];
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: theme.border),
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        // 宽表在**自己的框内**横向滚动，因此它永远不会把阅读栏撑得比窗口还宽。
        scrollDirection: Axis.horizontal,
        child: Table(
          defaultColumnWidth: const IntrinsicColumnWidth(),
          border: TableBorder.symmetric(
            inside: BorderSide(color: theme.border, width: 0.5),
          ),
          children: rows,
        ),
      ),
    );
  }

  Widget _cell(List<DocInline> inlines, int column, {required bool bold}) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: InlineRichText(
        nodes: inlines,
        typography: typography,
        baseStyle: bold
            ? typography.body.copyWith(fontWeight: FontWeight.w600)
            : typography.body,
        textAlign: alignFor(table.alignments, column),
        onOpenLink: onOpenLink,
        onCopyLink: onCopyLink,
      ),
    );
  }
}

/// 列对齐名 → TextAlign。
TextAlign alignFor(List<String?> alignments, int index) {
  if (index >= alignments.length) {
    return TextAlign.start;
  }
  return switch (alignments[index]) {
    'center' => TextAlign.center,
    'right' => TextAlign.end,
    _ => TextAlign.start,
  };
}

/// 未能解析成受控节点的块：显示原文与原因，而不是让它消失。
class FallbackBlockView extends StatelessWidget {
  /// 构造回退块。
  const FallbackBlockView({
    super.key,
    required this.text,
    required this.reason,
    required this.typography,
  });

  /// 原文。
  final String text;

  /// 原因。
  final String reason;

  /// 排版。
  final DocTypography typography;

  @override
  Widget build(BuildContext context) {
    final DocTheme theme = typography.theme;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: theme.warningSurface,
        border: Border.all(color: theme.danger.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            reason,
            style: TextStyle(
              fontSize: typography.baseSize * 0.72,
              color: theme.danger,
            ),
          ),
          const SizedBox(height: 4),
          SelectableText(
            text,
            style: typography.code.copyWith(color: theme.textPrimary),
          ),
        ],
      ),
    );
  }
}
