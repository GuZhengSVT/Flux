import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// 全局媒体缓存管理。
///
/// 缓存策略：
/// - 图片缓存默认保留 7 天，视频缓存默认保留 1 天；
/// - 超过 [maxCacheItems] 后，`flutter_cache_manager` 会自动按“最久未使用”清理；
/// - 文本清理由 [StorageCleanupService] 负责，不占用媒体缓存。
class MediaCache {
  MediaCache._();

  static final MediaCache instance = MediaCache._();

  CacheManager? _images;
  CacheManager? _videos;

  CacheManager get images {
    final manager = _images;
    if (manager == null) {
      throw StateError('MediaCache.configure() must be called before use');
    }
    return manager;
  }

  CacheManager get videos {
    final manager = _videos;
    if (manager == null) {
      throw StateError('MediaCache.configure() must be called before use');
    }
    return manager;
  }

  bool get isConfigured => _images != null && _videos != null;

  /// 根据设置创建/重建图片与视频缓存管理器。
  ///
  /// 设置变化时调用此方法，旧的 CacheManager 会被释放。
  void configure({
    required int imageRetentionDays,
    required int videoRetentionDays,
    required int maxCacheItems,
  }) {
    final oldImages = _images;
    final oldVideos = _videos;

    _images = CacheManager(
      Config(
        'flux_images',
        stalePeriod: Duration(days: imageRetentionDays),
        maxNrOfCacheObjects: maxCacheItems,
      ),
    );
    _videos = CacheManager(
      Config(
        'flux_videos',
        stalePeriod: Duration(days: videoRetentionDays),
        // 视频体积远大于图片，单独给一个较小的上限。
        maxNrOfCacheObjects: (maxCacheItems / 10).ceil().clamp(10, 1000),
      ),
    );

    oldImages?.dispose();
    oldVideos?.dispose();
  }

  /// 清空全部媒体缓存（用于“立即清理”按钮）。
  Future<void> clearAll() async {
    if (isConfigured) {
      await images.emptyCache();
      await videos.emptyCache();
    }
  }
}