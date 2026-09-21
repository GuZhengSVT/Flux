// 订阅管理页控制器（T014）。
//
// 职责：把用例与界面接起来，并持有页面状态。三条设计约束：
//
//   1) 写操作返回 Result，不吞掉错误也不自己弹提示。对话框自己决定怎么显示失败
//      （有些失败是字段级校验，往输入框下面写一行比弹全局提示更合适）；
//   2) 写入成功后**重读数据**而不是在内存里打补丁。订阅管理页的可信度来自
//      「看到的就是库里的」；打补丁会在写入部分成功（例如移动了订阅但删分组失败）
//      时显示一个库中不存在的状态；
//   3) 折叠状态与刷新策略**不重读**（见 FeedManagerState 的说明），它们与订阅数据无关。
//
// 为什么用 AsyncNotifier：首次加载要走数据库（分组 + 订阅 + 未读数 + 设置 + 本机折叠
// 状态五处读取），让 Riverpod 承载 loading/error，页面就不必自己写「还没读到显示什么」。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flux/core/core.dart';
import 'package:flux/features/settings/application/settings_controller.dart';
import 'package:flux/features/settings/application/settings_store.dart';

import '../application/add_feed.dart';
import '../application/edit_feed.dart';
import '../application/feed_manager_state.dart';
import '../application/feed_overview.dart';
import '../application/feed_ports.dart';
import '../application/manage_groups.dart';

/// 订阅管理页控制器。
final class FeedManagerController extends AsyncNotifier<FeedManagerState> {
  /// 读模型。
  FeedOverviewReader get _reader => FeedOverviewReader(
    catalog: ref.read(feedCatalogProvider),
    diagnostics: ref.read(diagnosticSinkProvider),
  );

  /// 添加订阅用例。
  AddFeedUseCase get _addFeed => AddFeedUseCase(
    fetcher: ref.read(feedFetcherProvider),
    catalog: ref.read(feedCatalogProvider),
    articles: ref.read(feedArticleStoreProvider),
    diagnostics: ref.read(diagnosticSinkProvider),
  );

  /// 编辑用例。
  EditFeedUseCase get _edit =>
      EditFeedUseCase(catalog: ref.read(feedCatalogProvider));

  /// 分组用例。
  ManageGroupsUseCase get _groups =>
      ManageGroupsUseCase(catalog: ref.read(feedCatalogProvider));

  @override
  Future<FeedManagerState> build() async {
    // 用 watch 读端口：端口被替换时（组合根注入、测试替换）控制器应重新构建。
    ref.watch(feedCatalogProvider);
    ref.watch(groupCollapseStoreProvider);
    ref.watch(settingsStoreProvider);

    final Result<FeedOverview> overview = await _reader.read();
    if (overview.isErr) {
      // 读失败向上抛：页面渲染成 AsyncError 并给出明确的失败说明，而不是显示一个
      // 空列表让人以为「订阅都没了」。
      throw overview.errorOrNull!;
    }

    final (RefreshPolicy policy, bool policyFailed) = await readRefreshPolicy(
      ref.read(settingsStoreProvider),
    );
    final Result<Map<String, bool>> collapsed = await ref
        .read(groupCollapseStoreProvider)
        .readAll();

    return FeedManagerState(
      overview: overview.unwrap(),
      collapsed: collapsed.getOrElse(const <String, bool>{}),
      policy: policy,
      policyReadFailed: policyFailed,
      collapseReadFailed: collapsed.isErr,
    );
  }

  /// 重新读取分组与订阅（写入后调用）。
  Future<void> reload() async {
    final Result<FeedOverview> overview = await _reader.read();
    final FeedManagerState? current = state.value;
    if (overview.isErr) {
      state = AsyncError<FeedManagerState>(
        overview.errorOrNull!,
        StackTrace.current,
      );
      return;
    }
    state = AsyncData<FeedManagerState>(
      (current ?? _emptyState()).copyWith(overview: overview.unwrap()),
    );
  }

  // ---------------------------------------------------------------------
  // 添加订阅
  // ---------------------------------------------------------------------

  /// 抓取并解析地址，产出预览（不写数据）。
  Future<Result<FeedPreview>> previewFeed(String url) => _addFeed.preview(url);

  /// 用预览结果入库。
  Future<Result<AddFeedOutcome>> confirmFeed({
    required FeedPreview preview,
    required String name,
    int? groupId,
  }) async {
    final Result<AddFeedOutcome> result = await _addFeed.confirm(
      preview: preview,
      name: name,
      groupId: groupId,
    );
    if (result.isOk) {
      await reload();
    }
    return result;
  }

  // ---------------------------------------------------------------------
  // 单条订阅编辑（SET-022/023）
  // ---------------------------------------------------------------------

  /// 改显示名。
  Future<Result<FeedRecord>> renameFeed({
    required int feedId,
    required String name,
  }) async {
    final Result<FeedRecord> result = await _edit.rename(
      feedId: feedId,
      name: name,
    );
    if (result.isOk) {
      await reload();
    }
    return result;
  }

  /// 移动到分组（null 表示不归入任何分组）。
  Future<Result<FeedRecord>> moveFeed({
    required int feedId,
    int? groupId,
  }) async {
    final Result<FeedRecord> result = await _edit.moveToGroup(
      feedId: feedId,
      groupId: groupId,
    );
    if (result.isOk) {
      await reload();
    }
    return result;
  }

  /// 启用/停用该源的自动刷新（SET-022）。
  Future<Result<FeedRecord>> setFeedEnabled({
    required int feedId,
    required bool enabled,
  }) async {
    final Result<FeedRecord> result = await _edit.setEnabled(
      feedId: feedId,
      enabled: enabled,
    );
    if (result.isOk) {
      await reload();
    }
    return result;
  }

  /// 加精/取消加精（SET-023）。
  Future<Result<FeedRecord>> setFeedFavorite({
    required int feedId,
    required bool favorite,
  }) async {
    final Result<FeedRecord> result = await _edit.setFavorite(
      feedId: feedId,
      favorite: favorite,
    );
    if (result.isOk) {
      await reload();
    }
    return result;
  }

  /// 设置该源刷新间隔（null 表示继承全局）。
  Future<Result<FeedRecord>> setFeedInterval({
    required int feedId,
    int? minutes,
  }) async {
    final Result<FeedRecord> result = await _edit.setRefreshInterval(
      feedId: feedId,
      minutes: minutes,
    );
    if (result.isOk) {
      await reload();
    }
    return result;
  }

  // ---------------------------------------------------------------------
  // 分组（SET-024）
  // ---------------------------------------------------------------------

  /// 新建分组。
  Future<Result<GroupRecord>> createGroup(String name) async {
    final Result<GroupRecord> result = await _groups.create(name: name);
    if (result.isOk) {
      await reload();
    }
    return result;
  }

  /// 重命名分组（保留组会被用例层拒绝）。
  Future<Result<GroupRecord>> renameGroup({
    required int groupId,
    required String name,
  }) async {
    final Result<GroupRecord> result = await _groups.rename(
      groupId: groupId,
      name: name,
    );
    if (result.isOk) {
      await reload();
    }
    return result;
  }

  /// 置顶/取消置顶。
  Future<Result<GroupRecord>> setGroupPinned({
    required int groupId,
    required bool pinned,
  }) async {
    final Result<GroupRecord> result = await _groups.setPinned(
      groupId: groupId,
      pinned: pinned,
    );
    if (result.isOk) {
      await reload();
    }
    return result;
  }

  /// 删除分组。
  Future<Result<GroupDeletionReport>> deleteGroup({
    required int groupId,
    required String groupName,
    GroupDeletionMode mode = GroupDeletionMode.moveToUncategorized,
  }) async {
    final Result<GroupDeletionOutcome> result = await _groups.delete(
      groupId,
      mode: mode,
    );
    if (result.isErr) {
      return Err<GroupDeletionReport>(result.errorOrNull!);
    }
    await reload();
    return Ok<GroupDeletionReport>(
      GroupDeletionReport(outcome: result.unwrap(), groupName: groupName),
    );
  }

  /// 整段重排分组。
  Future<Result<List<GroupRecord>>> reorderGroups(List<int> orderedIds) async {
    final Result<List<GroupRecord>> result = await _groups.reorder(orderedIds);
    if (result.isOk) {
      await reload();
    }
    return result;
  }

  /// 重排某个分组内的订阅。
  ///
  /// 把「上移/下移一位」也算在这里：界面上的键盘操作与拖动最终都归约为「新的完整
  /// 顺序」，因此只有一条写入路径，不存在两套排序语义。
  Future<Result<void>> reorderFeeds({
    required int groupId,
    required List<int> orderedIds,
  }) async {
    final Result<void> result = await ref
        .read(feedCatalogProvider)
        .reorderFeedsInGroup(groupId: groupId, feedIdsInOrder: orderedIds);
    if (result.isOk) {
      await reload();
    }
    return result;
  }

  // ---------------------------------------------------------------------
  // 本机展示状态与刷新策略
  // ---------------------------------------------------------------------

  /// 记忆某个分组的折叠状态（SET-025）。
  ///
  /// 先更新内存状态再写存储：折叠是即时视觉反馈，等一次数据库往返会让开关有明显
  /// 延迟。写失败只影响「下次启动是否记得」，因此不回滚内存状态，但把失败记进
  /// [FeedManagerState.collapseReadFailed]，界面据此说明。
  Future<void> setCollapsed({
    required int groupId,
    required bool collapsed,
  }) async {
    final FeedManagerState? current = state.value;
    if (current == null) {
      return;
    }
    final Map<String, bool> next = Map<String, bool>.of(current.collapsed);
    next['$groupId'] = collapsed;
    state = AsyncData<FeedManagerState>(current.copyWith(collapsed: next));

    final Result<void> written = await ref
        .read(groupCollapseStoreProvider)
        .write(groupId: groupId, collapsed: collapsed);
    if (written.isErr) {
      state = AsyncData<FeedManagerState>(
        (state.value ?? current).copyWith(collapseReadFailed: true),
      );
    }
  }

  /// 写 SET-020 的全局开关与间隔、SET-021 的启动时刷新。
  ///
  /// 走设置页同一个 [SettingsStore]：写入成功后本地更新，不重读全部设置
  /// （那会把一次开关变成一次全表读取）。
  Future<Result<RefreshPolicy>> setRefreshPolicy({
    bool? autoRefreshEnabled,
    String? intervalSetting,
    bool? refreshOnLaunch,
  }) async {
    final FeedManagerState? current = state.value;
    if (current == null) {
      return Err<RefreshPolicy>(
        StorageError(operation: 'setRefreshPolicy', detail: '状态尚未加载'),
      );
    }
    final RefreshPolicy target = current.policy.copyWith(
      autoRefreshEnabled: autoRefreshEnabled,
      intervalSetting: intervalSetting,
      refreshOnLaunch: refreshOnLaunch,
    );

    final SettingsStore settings = ref.read(settingsStoreProvider);
    // 两项分开写：任一项失败时另一项已写入的值必须保留，因此逐项判定并把第一处
    // 失败的类型化错误返回给界面。
    final Result<Object?> auto = await settings.writeSetting(
      SettingId.set020,
      <String, Object?>{
        'enabled': target.autoRefreshEnabled,
        'intervalMinutes': target.intervalSetting,
      },
    );
    if (auto.isErr) {
      return Err<RefreshPolicy>(auto.errorOrNull!);
    }
    final Result<Object?> launch = await settings.writeSetting(
      SettingId.set021,
      target.refreshOnLaunch,
    );
    if (launch.isErr) {
      return Err<RefreshPolicy>(launch.errorOrNull!);
    }

    state = AsyncData<FeedManagerState>(
      current.copyWith(policy: target, policyReadFailed: false),
    );
    return Ok<RefreshPolicy>(target);
  }

  /// 状态尚未加载时的占位（[reload] 在首帧之前被调用时使用）。
  static FeedManagerState _emptyState() => const FeedManagerState(
    overview: FeedOverview(sections: <FeedGroupSection>[], totalFeeds: 0),
    collapsed: <String, bool>{},
    policy: RefreshPolicy.defaults,
  );
}

/// 订阅管理页控制器的 Provider。
final AsyncNotifierProvider<FeedManagerController, FeedManagerState>
feedManagerControllerProvider =
    AsyncNotifierProvider<FeedManagerController, FeedManagerState>(
      FeedManagerController.new,
    );

/// 订阅概览（分组 + 订阅 + 未读数）。
///
/// 从 [feedManagerControllerProvider] 派生而不是另起一次查询：T017 的阅读页需要
/// 「有没有订阅」来决定空态文案（架构第 7 节要求「无订阅」与「筛选无结果」分别
/// 提示），而订阅管理页已经读过同一份数据。派生出来可以保证两页对「有没有订阅」的
/// 判断来自同一个读模型。
final Provider<AsyncValue<FeedOverview>> feedOverviewProvider =
    Provider<AsyncValue<FeedOverview>>((Ref ref) {
      return ref
          .watch(feedManagerControllerProvider)
          .whenData((FeedManagerState state) => state.overview);
    });
