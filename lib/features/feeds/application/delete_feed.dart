// 删除订阅/分组的用例（T018；架构 4.1「删除订阅」段、5.3 清理规则、SET-081）。
//
// 为什么把「影响预览」做成一个**独立于删除**的用例方法：
//   架构 4.1 与 D-11 要求清理范围在操作**之前**可见。若预览与删除共用同一次调用
//   （例如「先删了再报告影响」），那么「先看看影响」这个动作本身就成了一次删除，
//   而用户此时还没有做任何决定。因此 [DeleteFeedUseCase.preview] 是纯读、
//   [DeleteFeedUseCase.confirm] 才写。
//
// 为什么「保留收藏」是参数而不是设置：SET-081 的取值是「每次询问、默认选保留」。
//   也就是说默认值是**对话框的初始勾选状态**，而每一次删除都要由用户当次确认。
//   若这一层自己去读设置，用户取消勾选的意图会被一个更早写入的偏好覆盖——那是一类
//   很难察觉的错误删除（用户以为取消了保留，结果文章都留下了；或者相反）。
library;

import 'package:flux/core/core.dart';

/// 删除订阅的用例。
final class DeleteFeedUseCase {
  /// 构造用例。
  const DeleteFeedUseCase({
    required this.catalog,
    this.diagnostics = const NoopDiagnosticSink(),
  });

  /// 订阅读写端口。
  final FeedCatalogStore catalog;

  /// 诊断记录。
  final DiagnosticSink diagnostics;

  /// 读取一次删除的**影响范围**（只读，不改写任何数据）。
  ///
  /// 返回收藏数、其他文章数（含 later）与其中的 later 数。三个数字都要给：
  /// 用户要回答的是「要不要保留收藏」，因此他必须同时看到保留会留下几篇、其余有多少
  /// 会被清掉，以及自己标记过的「稍后再读」是否在其中——架构 4.1 明写 later 属于清理
  /// 范围，把这一点藏在一个总数里，用户就无从判断。
  Future<Result<FeedDeletionPreview>> preview(int feedId) async {
    return catalog.previewFeedDeletion(feedId);
  }

  /// 按用户当次的选择执行删除。
  ///
  /// [keepFavorites] 为真：非收藏文章（**含 later**）全部清理；收藏文章保留并脱离源
  /// （feedId 置空 + 冻结来源快照）。为假：全部清理。两种分支都会留下墓碑事件。
  ///
  /// 存储层在单个事务内完成，因此失败即整批回滚。用例层额外做的两件事：
  ///   1) 删除前**再确认这个源存在**（并顺带拿到它的名字写进诊断）——对一条已被别的
  ///      路径删掉的源报告「删除成功」会让界面显示一个并未发生的操作；
  ///   2) 把结果写进诊断日志（tag `feed.delete`），使「界面上点了删除」与「数据真的
  ///      删了」在排查时可对照。日志只记数量与源名，不记正文。
  Future<Result<FeedDeletionOutcome>> confirm({
    required int feedId,
    required bool keepFavorites,
  }) async {
    final Result<FeedRecord?> found = await catalog.findFeedById(feedId);
    if (found.isErr) {
      return Err<FeedDeletionOutcome>(found.errorOrNull!);
    }
    if (found.valueOrNull == null) {
      return Err<FeedDeletionOutcome>(
        StorageError(
          operation: 'deleteFeed',
          detail: '订阅 $feedId 不存在',
          isMissing: true,
        ),
      );
    }

    final Result<FeedDeletionOutcome> deleted = await catalog.deleteFeed(
      feedId: feedId,
      keepFavorites: keepFavorites,
    );
    if (deleted.isErr) {
      return deleted;
    }
    final FeedDeletionOutcome outcome = deleted.unwrap();
    diagnostics.info(
      '已删除订阅「${outcome.feedName}」：清理 ${outcome.deletedArticles} 篇，'
      '保留收藏 ${outcome.keptFavorites} 篇（${keepFavorites ? '保留' : '不保留'}）',
      tag: 'feed.delete',
    );
    return Ok<FeedDeletionOutcome>(outcome);
  }
}

/// 删除分组的用例。
///
/// 与 [ManageGroupsUseCase.delete] 的分工：那个用例是 T014 交付的分组管理入口，本
/// 用例补上 T018 的**保留收藏**参数与影响预览。两者都走同一条存储路径
/// （[FeedCatalogStore.deleteGroupWithFeeds]），因此规则只有一份。
final class DeleteGroupUseCase {
  /// 构造用例。
  const DeleteGroupUseCase({
    required this.catalog,
    this.diagnostics = const NoopDiagnosticSink(),
  });

  /// 订阅读写端口。
  final FeedCatalogStore catalog;

  /// 诊断记录。
  final DiagnosticSink diagnostics;

  /// 读取「删除其中订阅」分支的影响范围：组内全部订阅的收藏数与其他文章数。
  ///
  /// 逐条累加而不是另写一条聚合查询：单源预览与分组预览必须给出**同一套数字**，两套
  /// 实现迟早会在 later 这一类上分歧，而那时用户会看到「单源说有 3 篇稍后再读，分组
  /// 却说 0 篇」——一个无法判断哪边可信的界面。
  Future<Result<GroupDeletionPreview>> preview({
    required int groupId,
    required String groupName,
  }) async {
    final Result<List<FeedRecord>> feeds = await catalog.listFeeds();
    if (feeds.isErr) {
      return Err<GroupDeletionPreview>(feeds.errorOrNull!);
    }
    final List<FeedRecord> members = feeds.valueOrNull!
        .where((FeedRecord feed) => feed.groupId == groupId)
        .toList(growable: false);

    int favorites = 0;
    int others = 0;
    int laters = 0;
    for (final FeedRecord member in members) {
      final Result<FeedDeletionPreview> preview = await catalog
          .previewFeedDeletion(member.id);
      if (preview.isErr) {
        return Err<GroupDeletionPreview>(preview.errorOrNull!);
      }
      final FeedDeletionPreview perFeed = preview.unwrap();
      favorites += perFeed.favoriteCount;
      others += perFeed.otherCount;
      laters += perFeed.laterCount;
    }

    return Ok<GroupDeletionPreview>(
      GroupDeletionPreview(
        groupId: groupId,
        groupName: groupName,
        feedCount: members.length,
        favoriteCount: favorites,
        otherCount: others,
        laterCount: laters,
      ),
    );
  }

  /// 执行分组删除。
  Future<Result<GroupDeletionOutcome>> confirm({
    required int groupId,
    required GroupDeletionMode mode,
    required bool keepFavorites,
  }) async {
    final Result<GroupDeletionOutcome> result = await catalog
        .deleteGroupWithFeeds(
          groupId: groupId,
          mode: mode,
          keepFavorites: keepFavorites,
        );
    if (result.isErr) {
      return result;
    }
    final GroupDeletionOutcome outcome = result.unwrap();
    diagnostics.info(
      mode == GroupDeletionMode.moveToUncategorized
          ? '已删除分组：${outcome.movedFeedCount} 条订阅移动到未分类'
          : '已删除分组及其 ${outcome.deletedFeedCount} 条订阅：'
                '清理 ${outcome.deletedArticles} 篇，保留收藏 ${outcome.keptFavorites} 篇',
      tag: 'group.delete',
    );
    return Ok<GroupDeletionOutcome>(outcome);
  }
}
