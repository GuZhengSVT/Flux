// 文章图片的加载视图（T021）：走缓存管线 + 失败占位 + 重试。
//
// 为什么要一个 [ImageProvider] 而不是在控件里 await 后画 Image.memory：
//   - 同一个地址可能同时出现在卡片与正文里，各自 await 会重复下载；交给 Flutter 的
//     ImageCache 统一去重与复用是它存在的意义；
//   - 解码结果的内存上限（条目数/字节数）由 ImageCache 统一管，控件不必自己记；
//   - 失败与加载中的中间态由 Image 的 errorBuilder/loadingBuilder 表达，这是框架既有
//     的约定，自造一套状态机会与它是两套语义。
//
// 三条与产品规则对应的选择：
//   1) **失败只影响这一张**（架构 4.2「失败不阻塞文章」）：错误落在这个控件内部，
//      画占位与重试按钮，正文其余部分与其它图片继续渲染；
//   2) **解码不超过原图**：用 [ResizeImage] 且 allowUpscaling: false，目标尺寸大于
//      原图时按原图解码，避免把一张 200×200 的小图放大成一张大位图占内存；
//   3) **重试必须真的重新取**：重试要先把这一条从 ImageCache 里驱逐，否则 ImageCache
//      会直接返回上一次的结果，点重试等于什么都没发生。
library;

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flux/core/core.dart';
import 'package:flux/features/articles/application/article_image_ports.dart';
import 'package:flux/features/articles/application/media_cache_settings.dart';
import 'package:flux/l10n/l10n.dart';
import 'package:flux/ui/ui.dart';

/// 按地址构造图片 Provider。
///
/// 不用 Riverpod 的 family：这个 Provider 实例本身就是 ImageCache 的键（见
/// [ArticleBytesImageProvider] 的相等性），再套一层 family 只会把同一份去重逻辑
/// 做第二遍，并让「重试要驱逐缓存」变成两处都要清。
ImageProvider<Object> imageProviderFor(ArticleImageLoader loader, String url) =>
    ArticleBytesImageProvider(loader: loader, url: url);

/// 基于 [ArticleImageLoader] 的图片 Provider。
///
/// 相等性只由「地址 + loader 身份」决定：同一个 loader 加载同一个地址必须命中
/// ImageCache 的同一个条目，否则每建一次控件就重新下载一遍。
class ArticleBytesImageProvider
    extends ImageProvider<ArticleBytesImageProvider> {
  /// 构造 Provider。
  ArticleBytesImageProvider({required this.loader, required this.url});

  /// 加载端口（抓取 + 缓存）。
  final ArticleImageLoader loader;

  /// 图片地址。
  final String url;

  @override
  Future<ArticleBytesImageProvider> obtainKey(
    ImageConfiguration configuration,
  ) => SynchronousFuture<ArticleBytesImageProvider>(this);

  @override
  ImageStreamCompleter loadImage(
    ArticleBytesImageProvider key,
    ImageDecoderCallback decode,
  ) {
    // 每次调用都新建一个 chunk 控制器，**不能**把它挂在 Provider 实例上。
    //
    // 为什么（实测踩出来的坑）：同一个 Provider 实例的 loadImage 会被调用多次——
    // 失败后 ImageCache 清掉该键、界面重新解析就会再调一次。而 StreamController 默认
    // 是**单订阅**流：第二次把同一个 stream 交给 completer 会在构造时抛
    // 「Stream has already been listened to」（StateError），表现为图片位直接崩掉，
    // 而不是显示占位与重试。每个 completer 各自拥有 chunk 流才是正确结构。
    final StreamController<ImageChunkEvent> chunkEvents =
        StreamController<ImageChunkEvent>();

    // 解码器必须一路传下去：ResizeImage 会在外层包一层，它需要拿到自己的
    // getTargetSize 回调才能做「不超过原图」的钳制。自己在这里直接调
    // ImageDescriptor.encoded 会让钳制完全失效，而「小图不被放大成大位图」正是
    // 这条路径要避免的。
    final ImageStreamCompleter completer = MultiFrameImageStreamCompleter(
      codec: _loadAndDecode(decode, chunkEvents),
      chunkEvents: chunkEvents.stream,
      scale: 1,
      debugLabel: url,
    );
    // 自带一个「错误已被处理」的守卫监听者，并在失败后驱逐缓存条目。
    //
    // 为什么必须有这一条（实测到的真实缺陷）：框架在 completer 报错时，只有**声明了
    // onError 的监听者**才算把错误接住；ImageCache 自己挂的那个内部监听者没有 onError，
    // 因此当某个 completer 恰好只被 ImageCache 持有（控件因「流 key 未变」而提前返回、
    // 没有把自己的监听者挂上来——导航动画期间的重解析就会走到这条路）时，这次失败会被
    // 判为**未处理异常**交给 FlutterError：组件测试直接失败，真机上多刷一条红屏报错，
    // 而 errorBuilder 其实照常画出了占位与重试按钮——也就是说一条已被处理的失败被重复
    // 报了一次。
    //
    // reportErrors: false 正是框架为此留的口子（见 ImageStreamCompleter.reportError：
    // 有过这种监听者就不再上抛）。守卫在首帧或首次错误后自行摘除，因此它不会让 completer
    // 因为「还有监听者」而无法释放（那是它唯一需要小心的地方）。
    //
    // 驱逐则是 [NetworkImage] 的既有做法：失败的条目不该留在 ImageCache 里当 pending，
    // 否则重试会拿到一个永远不会完成的 completer（表现为点了重试没反应）。
    late final ImageStreamListener guard;
    guard = ImageStreamListener(
      (ImageInfo info, bool synchronousCall) {
        completer.removeListener(guard);
      },
      onError: (Object exception, StackTrace? stackTrace) {
        completer.removeListener(guard);
        // 失败的条目不该留在 ImageCache 里当 pending，否则重试会拿到一个永远
        // 不会完成的 completer（表现为点了重试没反应）。
        scheduleMicrotask(() => PaintingBinding.instance.imageCache.evict(key));
      },
      reportErrors: false,
    );
    completer.addListener(guard);
    return completer;
  }

  Future<ui.Codec> _loadAndDecode(
    ImageDecoderCallback decode,
    StreamController<ImageChunkEvent> chunkEvents,
  ) async {
    try {
      final Result<LoadedImage> result = await loader.load(url);
      if (result.isErr) {
        // 类型化错误沿 ImageStream 的失败通道抛给 errorBuilder。
        throw result.errorOrNull!;
      }
      final LoadedImage image = result.unwrap();
      if (!chunkEvents.isClosed) {
        chunkEvents.add(
          ImageChunkEvent(
            cumulativeBytesLoaded: image.bytes.length,
            expectedTotalBytes: image.bytes.length,
          ),
        );
      }
      final ui.ImmutableBuffer buffer = await ui.ImmutableBuffer.fromUint8List(
        image.bytes,
      );
      return await decode(buffer);
    } finally {
      // 必须关闭：不关会让 ImageStream 的订阅永不结束，控件一直停在加载态。
      unawaited(chunkEvents.close());
    }
  }

  @override
  bool operator ==(Object other) =>
      other is ArticleBytesImageProvider &&
      other.url == url &&
      identical(other.loader, loader);

  @override
  int get hashCode => Object.hash(url, identityHashCode(loader));

  @override
  String toString() => 'ArticleBytesImageProvider("$url")';
}

/// 媒体缓存上限宿主（T021；SET-080）。
///
/// 不渲染任何东西，只做一件事：读到 SET-080 之后把上限套用到图片加载器。
///
/// 为什么放在界面层而不是装配层：与刷新调度同一条理由——设置读取是异步的，而装配必须
/// 同步完成；「观察到设置后立刻套用」是这里唯一能保证顺序的地方。
class MediaCacheLimitHost extends ConsumerStatefulWidget {
  /// 构造宿主。
  const MediaCacheLimitHost({required this.child, super.key});

  /// 子树。
  final Widget child;

  @override
  ConsumerState<MediaCacheLimitHost> createState() =>
      _MediaCacheLimitHostState();
}

class _MediaCacheLimitHostState extends ConsumerState<MediaCacheLimitHost> {
  int? _appliedMiB;

  @override
  Widget build(BuildContext context) {
    final AsyncValue<int> limit = ref.watch(mediaCacheLimitProvider);
    limit.whenData((int miB) {
      if (miB == _appliedMiB) {
        // 同一取值不重复套用：套用会触发一次全量上限裁剪（读遍缓存目录），
        // 在每次重建时都做一遍是纯粹的浪费。
        return;
      }
      _appliedMiB = miB;
      unawaited(ref.read(articleImageLoaderProvider).applyCacheLimitMiB(miB));
    });
    return widget.child;
  }
}

/// 一张远程图片（受缓存管线管理的图片位）。
///
/// 调用方（卡片、正文、查看器）只提供尺寸与两种中间态的外观；「要不要下载、能不能
/// 缓存、失败能不能重试」都由这一个控件负责，三处不会各写一遍。
class ArticleImageView extends ConsumerStatefulWidget {
  /// 构造图片视图。
  const ArticleImageView({
    super.key,
    required this.url,
    required this.alt,
    required this.errorBuilder,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.alignment = Alignment.center,
    this.semanticLabel,
    this.loadingBuilder,
    this.showRetry = true,
    this.decodeTargetWidth,
    this.decodeTargetHeight,
  });

  /// 图片地址（已通过 [isSafeDocUrl]）。
  final String url;

  /// 替代文字（语义标签与占位文案）。
  final String alt;

  /// 失败时的外观；重试入口由本控件叠加（见 [showRetry]）。
  final WidgetBuilder errorBuilder;

  /// 填充方式。
  final BoxFit fit;

  /// 宽（null 表示由父约束决定）。
  final double? width;

  /// 高。
  final double? height;

  /// 对齐。
  final Alignment alignment;

  /// 读屏用的标签（为空时用 [alt]）。
  final String? semanticLabel;

  /// 加载中的外观。
  final WidgetBuilder? loadingBuilder;

  /// 是否显示重试按钮。
  ///
  /// 卡片封面为 false：卡片自身可点进详情，在 96×72 的缩略图上再塞一个重试热区会
  /// 让两个意图抢同一个位置。正文图片位为 true——那里的失败需要一条明确出路。
  final bool showRetry;

  /// 解码目标宽（逻辑像素，内部乘 devicePixelRatio）。
  final double? decodeTargetWidth;

  /// 解码目标高。
  final double? decodeTargetHeight;

  @override
  ConsumerState<ArticleImageView> createState() => _ArticleImageViewState();
}

class _ArticleImageViewState extends ConsumerState<ArticleImageView> {
  /// 重试计数：每次重试自增，用于强制换一个 key 让 Image 重新解析。
  int _attempt = 0;

  ImageProvider<Object> _baseProvider() =>
      imageProviderFor(ref.read(articleImageLoaderProvider), widget.url);

  ImageProvider<Object> _provider() {
    final ImageProvider<Object> base = _baseProvider();
    final double scale = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1;
    // 非有限值必须当成「没有目标尺寸」：宽卡片会传 double.infinity（宽度由父约束
    // 决定），而 infinity.round() 会抛 UnsupportedError 并把整个卡片目录炸掉。
    final int? width = _targetPixels(widget.decodeTargetWidth, scale);
    final int? height = _targetPixels(widget.decodeTargetHeight, scale);
    if (width == null && height == null) {
      return base;
    }
    // allowUpscaling 默认 false：目标尺寸大于原图时按原图解码（架构 4.2 的
    // 「超原图缩放」——不把一张小图放大成一张大位图）。
    return ResizeImage(base, width: width, height: height);
  }

  /// 逻辑尺寸 → 解码像素；非有限值或非正值表示「不指定」。
  static int? _targetPixels(double? logical, double scale) {
    if (logical == null || !logical.isFinite || logical <= 0) {
      return null;
    }
    final int pixels = (logical * scale).round();
    return pixels > 0 ? pixels : null;
  }

  /// 重试：驱逐缓存并重建。
  Future<void> _retry() async {
    // 两层都要驱逐：外层是 ResizeImage 的条目，内层是字节 Provider 的条目。
    // 只清一层会让重试拿到另一层的旧结果（包括上一次的失败缓存）。
    await _provider().evict();
    await _baseProvider().evict();
    if (!mounted) {
      return;
    }
    setState(() => _attempt++);
  }

  @override
  Widget build(BuildContext context) {
    // 监听 loader：组合根换实现（测试注入替身）时必须重新取图，而不是继续用旧
    // loader 建的缓存条目。
    ref.watch(articleImageLoaderProvider);
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Image(
      key: ValueKey<int>(_attempt),
      image: _provider(),
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      alignment: widget.alignment,
      semanticLabel:
          widget.semanticLabel ?? (widget.alt.isEmpty ? null : widget.alt),
      loadingBuilder:
          (BuildContext context, Widget child, ImageChunkEvent? progress) =>
              progress == null
              ? child
              : widget.loadingBuilder?.call(context) ??
                    const Center(child: FluxLoadingIndicator(size: 16)),
      errorBuilder:
          (BuildContext context, Object error, StackTrace? stackTrace) => Stack(
            alignment: Alignment.center,
            children: <Widget>[
              Positioned.fill(child: widget.errorBuilder(context)),
              if (widget.showRetry)
                // 重试按钮叠在占位之上：占位说明「这里本该有一张图」，按钮是出路。
                Positioned(
                  right: 4,
                  bottom: 4,
                  child: IconButton(
                    iconSize: 16,
                    visualDensity: VisualDensity.compact,
                    tooltip: l10n.readingImageRetry,
                    onPressed: () => unawaited(_retry()),
                    icon: const Icon(Icons.refresh),
                  ),
                ),
            ],
          ),
    );
  }
}
