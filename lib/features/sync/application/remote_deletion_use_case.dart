// 远端破坏性删除的预览与应用用例（T045；架构 5.2「未批准不自动清除本地内容」、
// 4.1「删除订阅」段、手册 6.3「删除」节的「远端删除先预览」）。
//
// 这个文件把 T043 登记下来的 [SyncDeletion] 变成两件事：
//   1) [preview]：**只读**地算出「如果确认了，会失去什么」——订阅名/文章数/收藏数；
//   2) [applyConfirmed]：用户确认之后，按 T018 的**同一套**规则真的删掉本机数据。
//
// 为什么必须是两个方法（而不是「apply 顺便返回影响」）：架构 5.2 明确「未批准不自动清除
// 本地内容」。若只有一个方法，那么「先看看影响」这个动作本身就成了一次删除，而用户此时还
// 没有做任何决定——这正是 T018 把 preview 与 confirm 分开的同一条理由。
//
// 为什么确认后的删除走 FeedCatalogStore 而不是自己写 SQL：删除规则（保留收藏、非收藏
// **含 later** 清理、收藏脱离源并冻结来源快照、单事务回滚、墓碑事件）只能有一份实现。
// 这里多写一份，就会在 later 这一类上漂移，而那时用户会看到「本机删的留下了 later、远端
// 确认删的没留下」这种自相矛盾的结果。
library;

import 'package:flux/core/core.dart';

/// 远端删除的预览与应用用例。
final class RemoteDeletionUseCase {
  /// 构造用例。
  const RemoteDeletionUseCase({
    required this.catalog,
    this.diagnostics = const NoopDiagnosticSink(),
  });

  /// 订阅读写端口（删除规则住在存储层的事务里）。
  final FeedCatalogStore catalog;

  /// 诊断记录。
  final DiagnosticSink diagnostics;

  /// 读取一条远端删除在本机的**影响范围**（只读，不改写任何数据）。
  ///
  /// 返回的 impact 可能带 blockedReason（本机没有对齐到这条订阅/分组，或类别不认识）：
  /// 调用方据此把它显示成「不可应用」，而不是猜一个目标去删。
  Future<Result<RemoteDeletionImpact>> preview(SyncDeletion deletion) async {
    final RemoteDeletionTarget target = remoteDeletionTargetOf(deletion.kind);
    switch (target) {
      case RemoteDeletionTarget.feed:
        final Result<FeedRecord?> found = await _findFeedBySyncId(deletion.key);
        if (found.isErr) {
          return Err<RemoteDeletionImpact>(found.errorOrNull!);
        }
        final FeedRecord? feed = found.valueOrNull;
        if (feed == null) {
          return Ok<RemoteDeletionImpact>(
            RemoteDeletionImpact.unsupported(
              deletion: deletion,
              reason: 'feedNotAligned',
            ),
          );
        }
        final Result<FeedDeletionPreview> feedPreview = await catalog
            .previewFeedDeletion(feed.id);
        if (feedPreview.isErr) {
          return Err<RemoteDeletionImpact>(feedPreview.errorOrNull!);
        }
        return Ok<RemoteDeletionImpact>(
          RemoteDeletionImpact.forFeed(
            deletion: deletion,
            preview: feedPreview.unwrap(),
          ),
        );
      case RemoteDeletionTarget.group:
        final Result<GroupRecord?> group = await catalog.findGroupBySyncId(
          deletion.key,
        );
        if (group.isErr) {
          return Err<RemoteDeletionImpact>(group.errorOrNull!);
        }
        final GroupRecord? found = group.valueOrNull;
        if (found == null) {
          return Ok<RemoteDeletionImpact>(
            RemoteDeletionImpact.unsupported(
              deletion: deletion,
              reason: 'groupNotAligned',
            ),
          );
        }
        final Result<List<FeedRecord>> feeds = await catalog.listFeeds();
        if (feeds.isErr) {
          return Err<RemoteDeletionImpact>(feeds.errorOrNull!);
        }
        // 分组内订阅的文章影响范围逐条累加：复用单源预览，数字因此与「先删组内每个源」
        // 完全一致（两套聚合迟早会在 later 这一类上分歧）。
        int favorites = 0;
        int others = 0;
        int laters = 0;
        for (final FeedRecord feed in feeds.unwrap()) {
          if (feed.groupId != found.id) {
            continue;
          }
          final Result<FeedDeletionPreview> perFeed = await catalog
              .previewFeedDeletion(feed.id);
          if (perFeed.isErr) {
            return Err<RemoteDeletionImpact>(perFeed.errorOrNull!);
          }
          final FeedDeletionPreview value = perFeed.unwrap();
          favorites += value.favoriteCount;
          others += value.otherCount;
          laters += value.laterCount;
        }
        return Ok<RemoteDeletionImpact>(
          RemoteDeletionImpact.forGroup(
            deletion: deletion,
            preview: GroupDeletionPreview(
              groupId: found.id,
              groupName: found.name,
              feedCount: feeds
                  .unwrap()
                  .where((FeedRecord feed) => feed.groupId == found.id)
                  .length,
              favoriteCount: favorites,
              otherCount: others,
              laterCount: laters,
            ),
          ),
        );
      case RemoteDeletionTarget.unsupported:
        // 未知类别（例如将来新增的实体、或远端送来的畸形数据）：**不猜**。猜一个目标去删
        // 是不可撤销的错误，而它的表现是「另一条订阅消失了」。
        return Ok<RemoteDeletionImpact>(
          RemoteDeletionImpact.unsupported(
            deletion: deletion,
            reason: 'unsupportedEntityKind',
          ),
        );
    }
  }

  /// 读取一批远端删除的影响范围（界面一次列全，用户一次看完）。
  Future<Result<List<RemoteDeletionImpact>>> previewAll(
    Iterable<SyncDeletion> deletions,
  ) async {
    final List<RemoteDeletionImpact> impacts = <RemoteDeletionImpact>[];
    for (final SyncDeletion deletion in deletions) {
      final Result<RemoteDeletionImpact> previewed = await preview(deletion);
      if (previewed.isErr) {
        return Err<List<RemoteDeletionImpact>>(previewed.errorOrNull!);
      }
      impacts.add(previewed.unwrap());
    }
    return Ok<List<RemoteDeletionImpact>>(
      List<RemoteDeletionImpact>.unmodifiable(impacts),
    );
  }

  /// 应用一条**已被用户确认**的远端删除。
  ///
  /// [keepFavorites] 是本机这次的选择（不是远端当时的选择）：远端的那一份只用于设置确认框
  /// 的默认勾选状态（见 RemoteDeletionImpact.defaultKeepFavorites），本机确认时按用户当次
  /// 看到的影响范围决定。这次选择会被写进墓碑事件与待同步标记，因此**别的设备**下次同步时
  /// 看到的就是它。
  ///
  /// 拒绝「不可应用」的目标（本机不认识这条删除）：返回类型化失败而不是当作成功——
  /// 假成功会让界面把这条从待确认列表里划掉，而本机数据其实一行没动。
  Future<Result<RemoteDeletionApplication>> applyConfirmed({
    required RemoteDeletionImpact impact,
    required bool keepFavorites,
  }) async {
    if (!impact.applicable) {
      return Err<RemoteDeletionApplication>(
        ValidationError(
          field: 'remoteDeletion',
          reason: '不支持或无法对齐的远端删除：${impact.blockedReason ?? 'unknown'}',
          value: impact.deletion.key,
        ),
      );
    }
    final int? targetId = impact.localTargetId;
    if (targetId == null) {
      return Err<RemoteDeletionApplication>(
        ValidationError(
          field: 'remoteDeletion',
          reason: '缺少本机目标 id',
          value: impact.deletion.key,
        ),
      );
    }

    switch (impact.target) {
      case RemoteDeletionTarget.feed:
        final Result<FeedDeletionOutcome> deleted = await catalog.deleteFeed(
          feedId: targetId,
          keepFavorites: keepFavorites,
        );
        if (deleted.isErr) {
          return Err<RemoteDeletionApplication>(deleted.errorOrNull!);
        }
        final FeedDeletionOutcome outcome = deleted.unwrap();
        diagnostics.info(
          '已应用远端删除（订阅「${outcome.feedName}」）：'
          '清理 ${outcome.deletedArticles} 篇，保留收藏 ${outcome.keptFavorites} 篇',
          tag: 'sync.remoteDeletion',
        );
        return Ok<RemoteDeletionApplication>(
          RemoteDeletionApplication(
            deletion: impact.deletion,
            target: impact.target,
            displayName: outcome.feedName,
            keepFavorites: keepFavorites,
            deletedArticles: outcome.deletedArticles,
            keptFavorites: outcome.keptFavorites,
          ),
        );
      case RemoteDeletionTarget.group:
        // 远端把整个分组删掉了：本机按「删除其中订阅」处理（T018 的 deleteFeeds 分支），
        // 因为这才是「远端那些订阅也不在了」的对应含义。若远端那次删除其实只是**移动**
        // 分组（操作元数据里没有 keepFavorites），本机按保留订阅的移动分支处理。
        final GroupDeletionMode mode = impact.deletion.keepFavorites == null
            ? GroupDeletionMode.moveToUncategorized
            : GroupDeletionMode.deleteFeeds;
        final Result<GroupDeletionOutcome> deleted = await catalog
            .deleteGroupWithFeeds(
              groupId: targetId,
              mode: mode,
              keepFavorites: keepFavorites,
            );
        if (deleted.isErr) {
          return Err<RemoteDeletionApplication>(deleted.errorOrNull!);
        }
        final GroupDeletionOutcome outcome = deleted.unwrap();
        diagnostics.info(
          '已应用远端删除（分组「${impact.displayName}」）：'
          '${mode == GroupDeletionMode.moveToUncategorized ? '订阅移入未分类' : '删除 ${outcome.deletedFeedCount} 条订阅'}',
          tag: 'sync.remoteDeletion',
        );
        return Ok<RemoteDeletionApplication>(
          RemoteDeletionApplication(
            deletion: impact.deletion,
            target: impact.target,
            displayName: impact.displayName,
            keepFavorites: keepFavorites,
            deletedArticles: outcome.deletedArticles,
            keptFavorites: outcome.keptFavorites,
          ),
        );
      case RemoteDeletionTarget.unsupported:
        return Err<RemoteDeletionApplication>(
          ValidationError(
            field: 'remoteDeletion',
            reason: '不支持的远端删除目标',
            value: impact.deletion.key,
          ),
        );
    }
  }

  /// 按 syncId 找本机订阅（不用 findFeedById：远端只知道跨设备标识）。
  Future<Result<FeedRecord?>> _findFeedBySyncId(String syncId) async {
    final Result<List<FeedRecord>> feeds = await catalog.listFeeds();
    if (feeds.isErr) {
      return Err<FeedRecord?>(feeds.errorOrNull!);
    }
    for (final FeedRecord feed in feeds.unwrap()) {
      if (feed.syncId == syncId) {
        return Ok<FeedRecord?>(feed);
      }
    }
    return const Ok<FeedRecord?>(null);
  }
}
