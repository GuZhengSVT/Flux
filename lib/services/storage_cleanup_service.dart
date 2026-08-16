import '../data/app_database.dart';
import '../providers/settings_provider.dart';

/// 存储清理服务。
///
/// 目前负责文本（文章）的保留期清理；图片/视频缓存由
/// `MediaCache` + `flutter_cache_manager` 按 `stalePeriod` 和 LRU 自动清理。
class StorageCleanupService {
  const StorageCleanupService();

  /// 清理过期文章。
  ///
  /// 返回删除的文章数。
  int cleanupText(AppDatabase database, int retentionDays) {
    if (retentionDays < 1) {
      return 0;
    }
    return database.deleteArticlesOlderThan(Duration(days: retentionDays));
  }

  /// 按当前设置执行一次完整清理。
  Future<void> run(AppDatabase database, SettingsState settings) async {
    cleanupText(database, settings.textRetentionDays);
    // 媒体缓存由 CacheManager 的 stalePeriod / maxNrOfCacheObjects 自动管理。
  }
}