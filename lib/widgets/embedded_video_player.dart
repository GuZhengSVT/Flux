import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:url_launcher/url_launcher.dart';

import '../media/media_kit_init.dart';
import '../services/media_cache.dart';

/// 内嵌视频播放器。
///
/// 使用 `package:media_kit` + `package:media_kit_video` 在阅读器内直接播放
/// RSS 正文中出现的视频地址（mp4 / webm / m3u8 / mov / avi 等）。
///
/// 特性：
/// - 第一个视频帧渲染前显示 loading 指示；
/// - 悬停/展开控制条，提供播放 / 暂停；
/// - 播放失败（网络错误、格式不支持、平台无播放器实现等）时，
///   自动回退到“外部播放器”占位，可点击用系统播放器打开。
///
/// 说明：demo 仅暴露 `url` / `width` / `height` / `fit`，加载与释放的
/// 时机由本组件自行管理，调用方无需关心。
class EmbeddedVideoPlayer extends StatefulWidget {
  const EmbeddedVideoPlayer({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
    this.useCache = false,
  });

  /// 视频地址（http/https 等 `Player.open` 支持的 URI）。
  final String url;

  /// 播放器视口宽度，[null] 表示宽度自适应父级约束。
  final double? width;

  /// 播放器视口高度。
  final double? height;

  /// 视频在视口内的适配方式。
  final BoxFit fit;

  /// 是否先缓存到本地再播放（视频缓存保留 1 天）。
  final bool useCache;

  @override
  State<EmbeddedVideoPlayer> createState() => _EmbeddedVideoPlayerState();
}

class _EmbeddedVideoPlayerState extends State<EmbeddedVideoPlayer> {
  late final Player _player;
  late final VideoController _controller;

  bool _ready = false;
  bool _playing = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    // 兜底初始化：即便 main() 尚未接入 ensureMediaKitInitialized 也能工作。
    ensureMediaKitInitialized();
    _player = Player();
    _controller = VideoController(_player);

    _player.stream.error.listen((message) {
      if (message.trim().isEmpty) return;
      if (mounted && !_ready) {
        setState(() => _failed = true);
      }
    });

    _player.stream.playing.listen((playing) {
      if (mounted && _playing != playing) {
        setState(() {
          _playing = playing;
          if (playing) _ready = true;
        });
      }
    });

    _open();
  }

  Future<void> _open() async {
    try {
      if (widget.useCache && MediaCache.instance.isConfigured) {
        try {
          final file = await MediaCache.instance.videos.getSingleFile(
            widget.url,
          );
          if (!mounted) return;
          await _player.open(Media(file.path), play: false);
        } catch (_) {
          // 缓存失败时回退到网络直连播放。
          if (!mounted) return;
          await _player.open(Media(widget.url), play: false);
        }
      } else {
        await _player.open(Media(widget.url), play: false);
      }
      if (!mounted) return;
      setState(() => _ready = true);
      await _player.play();
    } catch (_) {
      if (mounted) {
        setState(() => _failed = true);
      }
    }
  }

  Future<void> _playOrPause() async {
    if (_failed) {
      await _openExternal();
      return;
    }
    if (!_ready) return;
    try {
      await _player.playOrPause();
    } catch (_) {
      if (mounted) {
        setState(() => _failed = true);
      }
    }
  }

  Future<void> _openExternal() async {
    final uri = Uri.tryParse(widget.url);
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = widget.width;
    final height = widget.height ?? 160.0;

    if (_failed) {
      return SizedBox(
        width: width,
        height: height,
        child: _ExternalPlayerFallback(onOpen: _openExternal),
      );
    }

    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Video(
            controller: _controller,
            width: double.infinity,
            height: height,
            fit: widget.fit,
            controls: NoVideoControls,
            wakelock: true,
          ),
          // 悬停/点击时显示的简易控制层。
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _playOrPause,
              child: AnimatedOpacity(
                opacity: _playing ? 0.0 : 1.0,
                duration: const Duration(milliseconds: 200),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.3),
                  ),
                  child: Center(
                    child: _ready
                        ? _playOrPauseIcon
                        : const CircularProgressIndicator(color: Colors.white),
                  ),
                ),
              ),
            ),
          ),
          // 失败回退按钮：即使视频流迟迟不可用，也能直接走外部播放器。
          if (_ready && !_playing)
            Positioned(
              right: 8,
              top: 8,
              child: _ControlChip(
                icon: Icons.open_in_new,
                tooltip: '用外部播放器打开',
                onTap: _openExternal,
              ),
            ),
        ],
      ),
    );
  }

  Icon get _playOrPauseIcon => Icon(
    _playing ? Icons.pause_circle_filled : Icons.play_circle_fill,
    color: Colors.white,
    size: 52,
  );
}

/// 播放失败时的“外部播放器”占位。
class _ExternalPlayerFallback extends StatelessWidget {
  const _ExternalPlayerFallback({required this.onOpen});

  final Future<void> Function() onOpen;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onOpen,
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(2),
          border: Border.all(color: Theme.of(context).colorScheme.error),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.play_circle_fill,
              size: 56,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 8),
            Text(
              '视频加载失败，点击用外部播放器打开',
              style: Theme.of(context).textTheme.labelLarge,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// 半透明小控制按钮。
class _ControlChip extends StatelessWidget {
  const _ControlChip({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.black.withValues(alpha: 0.5),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(icon, color: Colors.white, size: 17),
          ),
        ),
      ),
    );
  }
}
