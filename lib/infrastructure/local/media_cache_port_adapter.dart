// 媒体缓存端口适配（T047；端口在 features/settings/application/cleanup_ports.dart）。
//
// 这一层只做一件事：把 T021 的 [ImageCacheService]（文件系统上的磁盘缓存）翻译成端口形状，
// 并把它的失败收敛成类型化错误。**没有任何清空之外的删除决策**——「哪些算到期」的判定住在
// core 的纯函数与 ImageCacheService 的 mtime 比较里，这里不重复一套。
//
// 为什么适配而不是让 ImageCacheService 直接实现端口：那个类住在「图片加载」这条路径上（被
// ArticleImageLoader 使用），而端口的调用方是设置页的存储清理。让缓存服务 import 一个设置页
// 端口会把「图片加载」与「存储设置」耦在一起，而两者的失败语义不同（前者失败要画占位，后者
// 失败要给用户一个可解释的提示）。
library;

import 'package:flux/core/core.dart';
import 'package:flux/features/settings/application/cleanup_ports.dart';

import 'image_cache_service.dart';

/// 基于 [ImageCacheService] 的媒体缓存端口实现。
final class ImageCacheMediaPort implements MediaCachePort {
  /// 绑定一个磁盘缓存。
  const ImageCacheMediaPort(this._cache);

  final ImageCacheService _cache;

  @override
  Future<Result<({int entries, int bytes})>> stats() async {
    try {
      final ImageCacheStats stats = await _cache.stats();
      return Ok<({int entries, int bytes})>((
        entries: stats.entryCount,
        bytes: stats.totalBytes,
      ));
    } on Exception catch (error, stackTrace) {
      return Err<({int entries, int bytes})>(
        _storage('mediaCache.stats', error, stackTrace),
      );
    }
  }

  @override
  Future<
    Result<({int entryCount, int imageBytes, int metaBytes, int tempBytes})>
  >
  diskUsage() async {
    try {
      final ({int entryCount, int imageBytes, int metaBytes, int tempBytes})
      usage = await _cache.diskUsage();
      return Ok<
        ({int entryCount, int imageBytes, int metaBytes, int tempBytes})
      >(usage);
    } on Exception catch (error, stackTrace) {
      return Err<
        ({int entryCount, int imageBytes, int metaBytes, int tempBytes})
      >(_storage('mediaCache.diskUsage', error, stackTrace));
    }
  }

  @override
  Future<Result<({int entries, int bytes})>> expiredUsage({
    required DateTime cutoffUtc,
  }) async {
    try {
      return Ok<({int entries, int bytes})>(
        await _cache.expiredUsage(cutoffUtc: cutoffUtc),
      );
    } on Exception catch (error, stackTrace) {
      return Err<({int entries, int bytes})>(
        _storage('mediaCache.expiredUsage', error, stackTrace),
      );
    }
  }

  @override
  Future<Result<({int entries, int bytes})>> deleteExpired({
    required DateTime cutoffUtc,
  }) async {
    try {
      return Ok<({int entries, int bytes})>(
        await _cache.deleteExpired(cutoffUtc: cutoffUtc),
      );
    } on Exception catch (error, stackTrace) {
      return Err<({int entries, int bytes})>(
        _storage('mediaCache.deleteExpired', error, stackTrace),
      );
    }
  }

  @override
  Future<Result<int>> clearAll() async {
    try {
      return Ok<int>(await _cache.clear());
    } on Exception catch (error, stackTrace) {
      return Err<int>(_storage('mediaCache.clear', error, stackTrace));
    }
  }

  @override
  Future<Result<int>> enforceLimit() async {
    try {
      return Ok<int>(await _cache.enforceLimit());
    } on Exception catch (error, stackTrace) {
      return Err<int>(_storage('mediaCache.enforceLimit', error, stackTrace));
    }
  }

  @override
  Future<Result<void>> applyLimitMiB(int limitMiB) async {
    try {
      await _cache.updateLimit(limitMiB);
      return okUnit();
    } on Exception catch (error, stackTrace) {
      return Err<void>(_storage('mediaCache.applyLimit', error, stackTrace));
    }
  }

  static StorageError _storage(
    String operation,
    Object error,
    StackTrace stackTrace,
  ) => StorageError(
    operation: operation,
    detail: error.runtimeType.toString(),
    cause: error,
    stackTrace: stackTrace,
  );
}
