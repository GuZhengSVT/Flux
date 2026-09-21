// 链接面板与图片查看器（T020）。
//
// 为什么外链要先出一个面板而不是直接打开：架构 4.2 要求「外链先显示网址及复制/打开
// 按钮」。读者在文章里点一个链接时，链接文字与真实地址经常不是一回事（短链、跟踪
// 参数、伪装域名），把地址摆出来是让用户能在打开之前判断。
//
// 图片查看器同样收在这里：两者都是「从正文里跳出来的浮层」，且都必须处理同一个安全
// 问题——浮层上显示的仍然是来自源内容的地址。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flux/core/design/design_tokens.dart';
import 'package:flux/l10n/l10n.dart';
import 'package:flux/ui/ui.dart';

/// 链接动作（面板上由按钮触发）。
enum LinkPanelAction {
  /// 复制地址。
  copy,

  /// 用外部浏览器打开。
  open,
}

/// 链接面板的返回值。
class LinkPanelResult {
  /// 构造结果。
  const LinkPanelResult({required this.action, required this.url});

  /// 用户选择的动作。
  final LinkPanelAction action;

  /// 被操作的地址。
  final String url;
}

/// 链接面板：显示完整地址 + 复制/打开两个按钮。
///
/// 用对话框而不是 popup menu：地址可能很长，需要换行显示与可选中复制；菜单项做不了
/// 这两件事。安全判定在**调用方**（详情页）完成——这里只画与转发，不做决定。
class LinkPanel extends StatelessWidget {
  /// 构造面板。
  const LinkPanel({super.key, required this.url, this.blockedReason});

  /// 地址（可能不被允许打开，见 [blockedReason]）。
  final String url;

  /// 非空表示这个地址被安全判定拒绝，只允许复制、不允许打开。
  ///
  /// 为什么仍然显示并允许复制：读者需要看得出原文想链接到哪里（架构 4.2 的「不静默
  /// 丢弃」）。拒绝的是**打开**，不是知情。
  final String? blockedReason;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool blocked = blockedReason != null;
    return AlertDialog(
      title: Text(l10n.readingLinkPanelTitle),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SelectableText(url, style: Theme.of(context).textTheme.bodySmall),
          if (blocked) ...<Widget>[
            const SizedBox(height: FluxSpacing.sm),
            Text(
              l10n.readingLinkBlocked(blockedReason!),
              style: Theme.of(context).textTheme.labelSmall
                  ?.copyWith(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () =>
              Navigator.of(context)
                  .pop(LinkPanelResult(action: LinkPanelAction.copy, url: url)),
          child: Text(l10n.readingLinkCopyAction),
        ),
        FilledButton(
          // 被拦下的地址连按钮都禁用：留一个可点的「打开」会让用户以为点击失败是 bug，
          // 而实际上这是我们**有意**不做的事。
          onPressed: blocked
              ? null
              : () => Navigator.of(
                  context,
                ).pop(LinkPanelResult(action: LinkPanelAction.open, url: url)),
          child: Text(l10n.readingLinkOpenAction),
        ),
      ],
    );
  }
}

/// 图片查看器：全屏、可缩放、Esc 关闭。
class ImageViewerPage extends StatefulWidget {
  /// 构造查看器。
  const ImageViewerPage({
    super.key,
    required this.url,
    required this.alt,
    required this.onSave,
    required this.onShare,
    this.saveEnabled = true,
  });

  /// 图片地址。
  final String url;

  /// 替代文字（标题与语义标签用）。
  final String alt;

  /// 保存回调（下载 + 选位置）。
  final Future<void> Function() onSave;

  /// 分享回调。
  final Future<void> Function() onShare;

  /// 是否允许保存。
  ///
  /// 为 false 的场景：远程图片开关关闭时，用户点选某一张仍然允许查看与下载（架构
  /// 4.2 的「关时占位 + 点选下载」），但是否可保存由**当前这条路径**决定，因此由
  /// 调用方显式传入而不是在这里读设置。
  final bool saveEnabled;

  @override
  State<ImageViewerPage> createState() => _ImageViewerPageState();
}

class _ImageViewerPageState extends State<ImageViewerPage> {
  final TransformationController _transform = TransformationController();
  bool _busy = false;

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  /// 双击缩放：在「适应窗口」与 2.5 倍之间切换。
  ///
  /// 用双击而不是只靠捏合：桌面（macOS）没有捏合手势，只做缩放的话桌面用户根本改不了
  /// 缩放；而架构第 7 节要求桌面与手机都要能用。
  void _toggleZoom(TapDownDetails details) {
    if (_transform.value != Matrix4.identity()) {
      _transform.value = Matrix4.identity();
      return;
    }
    const double scale = 2.5;
    final Offset focal = details.localPosition;
    _transform.value = Matrix4.identity()
      ..translateByDouble(
        -focal.dx * (scale - 1),
        -focal.dy * (scale - 1),
        0,
        1,
      )
      ..scaleByDouble(scale, scale, scale, 1);
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Scaffold(
      // 全屏查看用深底：浅底会让图片边缘与背景糊在一起，读者分不清图片到哪里为止。
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          widget.alt.isEmpty ? l10n.readingImageViewerTitle : widget.alt,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        // Esc 关闭：桌面用户的习惯动作（架构第 7 节的键盘可达要求）。用 Shortcuts
        // 而不是只靠 AppBar 的返回按钮：全屏查看时用户的手在键盘上。
        leading: IconButton(
          tooltip: l10n.readingImageCloseAction,
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        actions: <Widget>[
          if (widget.saveEnabled)
            IconButton(
              tooltip: l10n.readingImageSaveAction,
              icon: _busy
                  ? const FluxLoadingIndicator(size: 16)
                  : const Icon(Icons.download),
              onPressed: () => _run(widget.onSave),
            ),
          IconButton(
            tooltip: l10n.readingImageShareAction,
            icon: const Icon(Icons.ios_share),
            onPressed: () => _run(widget.onShare),
          ),
          const SizedBox(width: FluxSpacing.xxs),
        ],
      ),
      // Esc 关闭：桌面用户的习惯动作（架构第 7 节的键盘可达要求）。
      //
      // 层次有讲究，顺序不能颠倒：Shortcuts/Actions 必须**是**拿到焦点的那个结点的
      // 祖先。按键事件从焦点结点沿祖先链向上找处理者，把 Shortcuts 放在 autofocus
      // 的 Focus **内部**时，事件还没走到它就已经到了根（实测表现为 Esc 完全没反应）。
      //
      // 自带 autofocus 的 Focus 也是必需的：全屏查看器里没有任何输入框会自己抢焦点，
      // 没有这一层就没有焦点结点，快捷键也就没有投递起点。
      body: Shortcuts(
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
        },
        child: Actions(
          actions: <Type, Action<Intent>>{
            DismissIntent: CallbackAction<DismissIntent>(
              onInvoke: (DismissIntent _) {
                Navigator.of(context).maybePop();
                return null;
              },
            ),
          },
          child: Focus(
            autofocus: true,
            child: GestureDetector(
              // 双击缩放（桌面与手机都能用）。
              onDoubleTapDown: _toggleZoom,
              onDoubleTap: () {},
              child: InteractiveViewer(
                transformationController: _transform,
                minScale: 0.5,
                maxScale: 6,
                child: Center(
                  child: Image.network(
                    widget.url,
                    fit: BoxFit.contain,
                    semanticLabel: widget.alt.isEmpty ? null : widget.alt,
                    loadingBuilder:
                        (
                          BuildContext context,
                          Widget child,
                          ImageChunkEvent? progress,
                        ) => progress == null
                        ? child
                        : const Center(child: FluxLoadingIndicator()),
                    errorBuilder:
                        (
                          BuildContext context,
                          Object error,
                          StackTrace? stack,
                        ) => Center(
                          child: Text(
                            l10n.readingImageLoadFailed,
                            style: const TextStyle(color: Colors.white70),
                          ),
                        ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
