// 存储清理的端口与 Provider 装配（T047；架构 5.3 的清理段、SET-077/078/079/080）。
//
// 为什么端口住在 features 而不是让用例直接读文件与数据库：features 不得 import
// infrastructure（架构 2.2，有回归守卫）。这里定义的是「清理需要外部提供什么」——分类占用
// 统计、可再生内容的清理、付费结果与关联范围的枚举、以及**不变量**（清理前后状态/订阅/秘密
// 一行的对照）——由基础设施实现。
//
// 三条刻意的设计：
//   1) **每一次清理动作都返回分类影响**（[CleanupImpact]），而不是一个「成功/失败」：
//      架构 5.3 要求清理预览与执行后的数字能对得上，因此预览与执行必须共用同一种形状；
//   2) **没有「清掉一切」的入口**。可删的东西按类别各有一个方法，因此「顺手把付费结果一起
//      删了」在接口上不可表达（与 T046 的备份白名单同一思路）；
//   3) **秘密不出现在任何签名里**。清理需要的一切都是文件计数与 id，因此「清理顺手读了
//      Keychain」这条路径不存在。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flux/core/core.dart';

import 'cleanup_service.dart';

/// 存储清理数据端口（由 infrastructure/local 实现）。
///
/// **媒体缓存不在这个端口里**：图片缓存住在文件系统（T021 的 ImageCacheService），而这里全是
/// 数据库行。让一个端口同时做两件事会把「清媒体失败」与「清数据库失败」合进同一个错误分支，
/// 而它们的处置完全不同（前者可以重试，后者可能已经部分完成）。两者的合并在用例层完成。
abstract interface class StorageCleanupStore {
  /// **数据库侧**的分类占用统计（媒体那一类由媒体端口提供，用例层合并）。
  Future<Result<StorageUsageReport>> measureDatabase({
    required DateTime measuredAt,
  });

  /// 枚举**将被释放正文**的文章（到期 + 保护规则）与**被保护而跳过**的篇数。
  Future<Result<({CleanupImpact impact, List<int> articleIds})>>
  planArticleBodyRelease({
    required DateTime cutoffUtc,
    required bool includeFavorite,
    required bool includeLater,
  });

  /// 释放指定文章的正文列（只置空正文相关列，**保留身份与状态**）。
  ///
  /// 返回实际释放的篇数与字节。
  Future<Result<({int articles, int bytes})>> releaseArticleBodies({
    required List<int> articleIds,
  });

  /// 枚举到期的新闻总结版本。
  Future<Result<({CleanupImpact impact, List<int> runIds})>>
  planSummaryCleanup({required DateTime cutoffUtc});

  /// 删除指定的总结版本（连带它们的引用行）。
  Future<Result<({int runs, int bytes})>> deleteSummaryRuns({
    required List<int> runIds,
  });

  /// AI 结果缓存现状（条数 + 字节）。
  Future<Result<({int entries, int bytes})>> aiCacheUsage();

  /// 清空 AI 结果缓存（**不删任务状态与订阅**；架构 5.3 的边界）。
  Future<Result<({int entries, int bytes})>> clearAiResultCache();

  /// 失败/取消/中断任务的**草稿**数（这些是「失败任务草稿」，与成功结果不同）。
  Future<Result<({int entries, int bytes})>> failedTaskDraftUsage();

  /// 清理失败任务的草稿（只清终态为失败/取消/中断的任务行，不动成功与进行中的任务）。
  Future<Result<({int entries, int bytes})>> clearFailedTaskDrafts();

  /// 一篇文章的彻底删除关联范围（架构 5.3：列出关联摘要/引用/缓存并清理）。
  Future<Result<ArticlePurgeImpact>> articlePurgeImpact(int articleId);

  /// 彻底删除一篇文章及其关联（引用置空、译文/会话/媒体缓存清理，正文与身份一并删除）。
  ///
  /// 返回实际清理的关联计数，供界面回执。
  Future<Result<ArticlePurgeImpact>> purgeArticle(int articleId);
}

/// 媒体缓存文件系统的窄端口（图片缓存的统计与清理;由 infrastructure/local 实现）。
///
/// 与 [StorageCleanupStore] 分开的原因：图片缓存是**文件系统**上的东西（T021 的
/// [ImageCacheService]），而其余部分是数据库行。让一个端口同时做两件事会让「清理媒体失败」
/// 与「清理数据库失败」落在同一个错误分支里，而它们的处置完全不同（前者可以重试，后者
/// 可能已经部分完成）。
abstract interface class MediaCachePort {
  /// 条目数与图片总字节（**不含**元数据与半成品，见 [diskUsage]）。
  ///
  /// 上限不在这里返回：它来自 SET-080 的设置读取（界面本来就要读它来做开关与编辑），
  /// 让缓存再报一遍会形成第二个来源，而两处迟早不一致。
  Future<Result<({int entries, int bytes})>> stats();

  /// 磁盘实际占用（含元数据与半成品 `.part`）。
  Future<
    Result<({int entryCount, int imageBytes, int metaBytes, int tempBytes})>
  >
  diskUsage();

  /// 按最后访问时间统计到期条目（只读）。
  Future<Result<({int entries, int bytes})>> expiredUsage({
    required DateTime cutoffUtc,
  });

  /// 删除到期条目；返回实际删除的条目数与字节。
  Future<Result<({int entries, int bytes})>> deleteExpired({
    required DateTime cutoffUtc,
  });

  /// 清空全部条目；返回被删除的文件数。
  Future<Result<int>> clearAll();

  /// 按上限淘汰（SET-080）；返回删除的条目数。
  Future<Result<int>> enforceLimit();

  /// 套用新的上限（MiB）并立即裁剪。
  Future<Result<void>> applyLimitMiB(int limitMiB);
}

/// 远端快照与它的最后修改时刻（服务器不给时为 null）。
final class RemoteSnapshotFact {
  /// 构造事实。
  const RemoteSnapshotFact({required this.name, this.lastModified});

  /// 文件名（含 `snapshot-` 前缀）。
  final String name;

  /// 最后修改时刻（UTC）；服务器不返回 `getlastmodified` 时为 null。
  final DateTime? lastModified;
}

/// 远端快照的 GC 端口（T042 遗留的孤儿快照清理）。
///
/// 只暴露「列出远端快照名与时间」与「删除一个快照」：判定（哪些该删）住在 core 的纯函数里。
abstract interface class SnapshotGcPort {
  /// 列出远端快照。
  ///
  /// 名字**全部**返回，时间可为 null：把「服务器不给时间」的名字从列表里丢掉，会让 GC 把
  /// 它当成「远端没有这个文件」，于是「列得出但删不掉」这件事在统计里完全不可见。
  Future<Result<List<RemoteSnapshotFact>>> listSnapshots();

  /// 删除一个远端快照；返回是否确实删掉了（不存在视为成功）。
  Future<Result<bool>> deleteSnapshot(String name);
}

/// 存储清理数据端口 Provider。
///
/// 默认**抛错**（与其余端口同一口径）：漏接线必须立刻暴露，而不是退化成一个「什么都不清」
/// 的空实现——那会让用户以为释放了空间，而磁盘上什么都没变。
final Provider<StorageCleanupStore> storageCleanupStoreProvider =
    Provider<StorageCleanupStore>(
      (Ref ref) => throw StateError(
        'storageCleanupStoreProvider 未被组合根覆盖：见 lib/app/app_providers.dart',
      ),
    );

/// 媒体缓存端口 Provider（默认抛错，理由同上）。
final Provider<MediaCachePort> mediaCachePortProvider =
    Provider<MediaCachePort>(
      (Ref ref) => throw StateError(
        'mediaCachePortProvider 未被组合根覆盖：见 lib/app/app_providers.dart',
      ),
    );

/// 远端快照 GC 端口 Provider。
///
/// **故意没有默认实现，也没有降级实现**：快照 GC 需要远端凭据与网络，而「未配置同步」是
/// 一个正常状态。因此它可空（null = 未配置同步，GC 直接报「无事可做」），而不是抛错——
/// 一个在未配置同步时抛错的端口会让设置页一打开就崩。
final Provider<SnapshotGcPort?> snapshotGcPortProvider =
    Provider<SnapshotGcPort?>((Ref ref) => null);

/// 存储清理用例（由上面三个端口组合，因此只有一处决定「清理由什么构成」）。
///
/// 组合写在端口文件里而不是界面里：界面若自己 new 一个 CleanupService，就会在「手动清缓存」
/// 与「自动清理」两条路径上各建一个实例，而它们本该共用同一份诊断与时钟。
final Provider<CleanupService> cleanupServiceProvider =
    Provider<CleanupService>((Ref ref) {
      final StorageCleanupStore store = ref.watch(storageCleanupStoreProvider);
      final MediaCachePort media = ref.watch(mediaCachePortProvider);
      return CleanupService(
        store: store,
        mediaCache: media,
        snapshotGc: ref.watch(snapshotGcPortProvider),
      );
    });
