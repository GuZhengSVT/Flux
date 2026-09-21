// 编辑订阅用例（T014；SET-022 名称/分组/启用、SET-023 加精）。
//
// 单条编辑被拆成**独立的小方法**（改名 / 移动分组 / 启用开关 / 加精 / 刷新间隔），
// 而不是一个「保存整个表单」的大方法。三个理由：
//   1) 每个动作在界面上是可独立回滚的（加精是一个开关，改名是一个输入框），
//      合成一个方法后，一次失败的加精写入会把整表单的其他字段一起回滚，用户
//      分不清哪一项没保存；
//   2) 加精只影响显示（架构 4.1），刷新间隔只影响调度，两者的授权与校验都不同；
//   3) 与 SET 注册表的粒度对齐（SET-022 与 SET-023 是两个编号），便于把
//      「哪个编号的行为已落地」逐条核对。
//
// 刻意**不**包含的操作：改订阅 URL。架构 4.1 的重复导入匹配以规范化 URL 为键，
// 而 URL 是订阅的身份；改 URL 会让已有文章落到另一个身份下（或撞上唯一索引），
// 正确的做法是「删除并重新添加」——那条路径需要 T018 的保留收藏规则。
library;

import 'package:flux/core/core.dart';

/// 编辑订阅用例。
class EditFeedUseCase {
  /// 构造用例。
  const EditFeedUseCase({required this.catalog});

  /// 订阅读写端口。
  final FeedCatalogStore catalog;

  /// 改显示名。
  ///
  /// 只改 [FeedRecord.name]，不动 [FeedRecord.sourceName]：源自带名称是抓取时的
  /// 事实，用户改名后仍应能在界面上看到「源自己的名字」（架构 5.1 明确要求
  /// 「显示名称与源名称分开」）。
  Future<Result<FeedRecord>> rename({
    required int feedId,
    required String name,
  }) {
    return _loadAndApply(
      feedId: feedId,
      validate: () => isValidFeedName(name)
          ? null
          : ValidationError(field: 'feedName', reason: '订阅名称不能为空'),
      apply: (FeedRecord feed) async {
        final Result<void> written = await catalog.renameFeed(
          feedId: feed.id,
          name: name.trim(),
        );
        return written.isErr
            ? Err<FeedRecord>(written.errorOrNull!)
            : Ok<FeedRecord>(feed.copyWith(name: name.trim()));
      },
    );
  }

  /// 移动到某个分组；[groupId] 为 null 表示移出分组（界面按「未分类」展示）。
  ///
  /// 分组存在性在这里校验：把订阅挂到一个不存在的分组 id 上，外键会拒绝写入；
  /// 但错误会是「存储失败」这种对用户无意义的说法，而我们其实知道原因是
  /// 「目标分组不存在」。
  Future<Result<FeedRecord>> moveToGroup({required int feedId, int? groupId}) {
    return _loadAndApply(
      feedId: feedId,
      validate: null,
      apply: (FeedRecord feed) async {
        if (groupId != null) {
          final Result<List<GroupRecord>> groups = await catalog.listGroups();
          if (groups.isErr) {
            return Err<FeedRecord>(groups.errorOrNull!);
          }
          final bool exists = groups.valueOrNull!.any(
            (GroupRecord group) => group.id == groupId,
          );
          if (!exists) {
            return Err<FeedRecord>(
              ValidationError(field: 'groupId', reason: '目标分组不存在'),
            );
          }
        }
        final Result<void> written = await catalog.moveFeedToGroup(
          feedId: feed.id,
          groupId: groupId,
        );
        return written.isErr
            ? Err<FeedRecord>(written.errorOrNull!)
            : Ok<FeedRecord>(
                feed.copyWith(groupId: groupId, clearGroup: groupId == null),
              );
      },
    );
  }

  /// 启用/禁用该源的自动刷新（SET-022）。
  ///
  /// 禁用**不删除**任何已有文章（架构 4.1：「保留旧内容」；禁用是「不要再联网」，
  /// 不是「把内容清掉」）。刷新调度侧读到 [FeedRecord.enabled] 为 false 时跳过该源，
  /// 那部分在 T016 落地；本任务只保证这个开关真实落库。
  Future<Result<FeedRecord>> setEnabled({
    required int feedId,
    required bool enabled,
  }) {
    return _loadAndApply(
      feedId: feedId,
      validate: null,
      apply: (FeedRecord feed) async {
        final Result<void> written = await catalog.setFeedEnabled(
          feedId: feed.id,
          enabled: enabled,
        );
        return written.isErr
            ? Err<FeedRecord>(written.errorOrNull!)
            : Ok<FeedRecord>(feed.copyWith(enabled: enabled));
      },
    );
  }

  /// 加精/取消加精（SET-023）。
  ///
  /// 加精**与选材无关**（架构 4.1 与 D-10）：它不改变刷新频率、不改变文章权重、
  /// 不进入新闻生成的材料选择。它只影响列表上的徽标与强调。这一条在这里是
  /// 结构性的——本方法除了写一个布尔列之外什么也不做。
  Future<Result<FeedRecord>> setFavorite({
    required int feedId,
    required bool favorite,
  }) {
    return _loadAndApply(
      feedId: feedId,
      validate: null,
      apply: (FeedRecord feed) async {
        final Result<void> written = await catalog.setFeedFavorite(
          feedId: feed.id,
          favorite: favorite,
        );
        return written.isErr
            ? Err<FeedRecord>(written.errorOrNull!)
            : Ok<FeedRecord>(feed.copyWith(favorite: favorite));
      },
    );
  }

  /// 设置该源的刷新间隔覆盖（SET-022）；null 表示继承全局（SET-020）。
  Future<Result<FeedRecord>> setRefreshInterval({
    required int feedId,
    int? minutes,
  }) {
    return _loadAndApply(
      feedId: feedId,
      validate: () {
        if (minutes == null) {
          return null;
        }
        // SET-020 的取值集合（手动 0 / 15 / 30 / 60 / 120）；0 表示手动。
        // 不在这里自造范围：注册表是权威口径，SET-022 的 refreshInterval 用
        // 「inherit + 同一组值」，因此这里只接受同一组值。
        const List<int> allowed = <int>[0, 15, 30, 60, 120];
        return allowed.contains(minutes)
            ? null
            : ValidationError(
                field: 'refreshInterval',
                reason: '只允许 ${allowed.join('/')} 分钟或继承全局',
              );
      },
      apply: (FeedRecord feed) async {
        final Result<void> written = await catalog.setFeedRefreshInterval(
          feedId: feed.id,
          minutes: minutes,
        );
        if (written.isErr) {
          return Err<FeedRecord>(written.errorOrNull!);
        }
        return Ok<FeedRecord>(
          feed.copyWith(
            refreshIntervalMinutes: minutes,
            clearRefreshInterval: minutes == null,
          ),
        );
      },
    );
  }

  /// 读回订阅、校验、执行写入，并把**写入后的记录**返回给调用方。
  ///
  /// 返回记录而不是 void：界面需要立即用新值重绘（例如刚打开开关的源），若只返回
  /// 成功/失败，界面必须再查一次库，于是出现「写完→查询」之间的竞态窗口。
  Future<Result<FeedRecord>> _loadAndApply({
    required int feedId,
    required AppError? Function()? validate,
    required Future<Result<FeedRecord>> Function(FeedRecord feed) apply,
  }) async {
    if (validate != null) {
      final AppError? rejection = validate();
      if (rejection != null) {
        return Err<FeedRecord>(rejection);
      }
    }
    final Result<FeedRecord?> loaded = await catalog.findFeedById(feedId);
    if (loaded.isErr) {
      return Err<FeedRecord>(loaded.errorOrNull!);
    }
    final FeedRecord? feed = loaded.valueOrNull;
    if (feed == null) {
      return Err<FeedRecord>(
        StorageError(
          operation: 'editFeed',
          detail: 'feed $feedId 不存在',
          isMissing: true,
        ),
      );
    }
    return apply(feed);
  }
}
