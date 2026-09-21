// 文章图片加载适配器（T021）：抓取 → 校验 → 缓存 → 交字节。
//
// 这是把 [HttpMediaFetcher] 与 [ImageCacheService] 接起来的那一层，因此它是唯一
// 知道「什么值得缓存」的地方。三条顺序上的讲究：
//
//   1) **先查缓存再发请求**。缓存命中时根本不联网，这是「离线可读」与「不重复计费」
//      的实现方式；
//   2) **写入缓存只在完整校验通过之后**。把未校验的字节先落盘再校验，等于给磁盘留了
//      一份永远不该存在的文件；
//   3) **缓存写失败不当作加载失败**。图已经在内存里了，写不进磁盘只是「这次没有缓存
//      下来」；把它报成失败会让一张显示得好好的图旁边出现「加载失败」。
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flux/core/core.dart';
import 'package:flux/features/articles/application/article_image_ports.dart';
import 'package:flux/infrastructure/network/media_fetcher.dart';

import 'image_cache_service.dart';

/// 基于磁盘缓存 + 受控抓取的图片加载器。
final class CachedArticleImageLoader implements ArticleImageLoader {
  /// 构造加载器。
  const CachedArticleImageLoader({
    required this.fetcher,
    this.cache,
    this.policy = const AllowAllMediaDownloads(),
  });

  /// 受控抓取（MIME/体积/魔数/重定向/守卫）。
  final HttpMediaFetcher fetcher;

  /// 磁盘 + 内存缓存；为 null 表示**不做磁盘缓存**（启动时数据目录不可用的降级
  /// 情形）。为 null 时图片仍然走完整的校验管线，只是每次都要重新取——降级运行的
  /// 正确语义是「本次运行不持久化」，而不是「图片功能不可用」。
  final ImageCacheService? cache;

  /// 计费网络守卫（SET-013）。默认放行：没有注入守卫时按「没有证据表明受限」处理，
  /// 与刷新调度那边 [PermissiveNetworkConditions] 的口径一致。
  final MediaDownloadPolicy policy;

  @override
  Future<Result<LoadedImage>> load(String url) async {
    if (!isSafeDocUrl(url)) {
      return Err<LoadedImage>(
        NetworkError(uri: url, reason: '图片地址协议不被允许', isRetryable: false),
      );
    }

    // 1) 缓存优先。
    final ImageCacheService? store = cache;
    if (store != null) {
      final Result<CachedImage?> cached = await store.read(url);
      if (cached.isErr) {
        // 缓存层读失败（权限、IO）不算致命：继续走网络，最差是这一张图没被缓存。
      } else if (cached.valueOrNull case final CachedImage hit) {
        return Ok<LoadedImage>(
          LoadedImage(
            bytes: hit.bytes,
            mimeType: hit.mimeType,
            width: hit.width,
            height: hit.height,
          ),
        );
      }
    }

    // 2) 网络取回（含守卫、DNS 复检、逐跳校验与字节校验）。
    //
    // 先问计费守卫：SET-013 关闭且当前是计费网络时**根本不允许发出这次请求**
    // （架构 4.1 的口径与 T016 一致：不是「先发一次再报不该发」）。缓存命中已经在
    // 上面返回了，因此这条守卫只影响真正要出网的路径——离线下已缓存的图仍可读。
    if (!await policy.allowsImageDownload()) {
      return Err<LoadedImage>(
        NetworkError(
          uri: url,
          reason: '计费网络下不允许下载图片（SET-013 关闭）',
          isRetryable: true,
        ),
      );
    }
    final Uri? uri = Uri.tryParse(url);
    if (uri == null) {
      return Err<LoadedImage>(
        NetworkError(uri: url, reason: '图片地址无法解析', isRetryable: false),
      );
    }
    final Result<MediaFetchResult> fetched = await fetcher.fetch(uri);
    if (fetched.isErr) {
      return Err<LoadedImage>(fetched.errorOrNull!);
    }
    final MediaFetchResult media = fetched.unwrap();

    // 3) 校验通过才落盘；写失败不影响这一次的显示。
    // 写失败不影响这一次的显示（见文件头说明），因此有意不检查返回值。
    await store?.write(
      url: url,
      bytes: media.bytes,
      mimeType: media.mimeType,
      width: media.dimensions.width,
      height: media.dimensions.height,
    );

    return Ok<LoadedImage>(
      LoadedImage(
        bytes: media.bytes,
        mimeType: media.mimeType,
        width: media.dimensions.width,
        height: media.dimensions.height,
      ),
    );
  }

  @override
  Future<Result<int>> saveToPath({
    required String url,
    required String targetPath,
  }) async {
    final Result<LoadedImage> loaded = await load(url);
    if (loaded.isErr) {
      return Err<int>(loaded.errorOrNull!);
    }
    final Uint8List bytes = loaded.unwrap().bytes;
    try {
      final File target = File(targetPath);
      await target.writeAsBytes(bytes, flush: true);
      return Ok<int>(bytes.length);
    } on FileSystemException catch (error, stackTrace) {
      return Err<int>(
        StorageError(
          operation: 'imageSave',
          detail: error.osError?.errorCode == 13 ? 'permission denied' : 'io',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    } on Exception catch (error, stackTrace) {
      return Err<int>(
        StorageError(
          operation: 'imageSave',
          detail: error.runtimeType.toString(),
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  @override
  Future<void> applyCacheLimitMiB(int limitMiB) async {
    // cache 为 null（不落盘）时无事可做：没有磁盘缓存也就没有上限可套用。
    await cache?.updateLimit(limitMiB);
  }
}
