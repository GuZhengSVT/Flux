// 订阅管理页的状态与操作入口（T014）。
//
// 分层：本文件是**用例编排**（读模型 + 若干写入方法），不碰任何 widget；页面只负责
// 把这里的状态画出来、把用户动作转发进来。这样做的直接好处是「添加/改名/排序/置顶」
// 这些行为的正确性可以用纯 Dart 测试验证（不需要 pump widget），widget 测试只需覆盖
// 「界面确实把状态画对了、确实把动作转发了」。
//
// 状态里同时含两类东西，它们的刷新时机不同：
//   - [overview]（分组 + 订阅 + 未读数）：每次写入后重读；
//   - [collapsed]（本机折叠状态）与 [refreshPolicy]（SET-020/021）：只在加载时读一次，
//     写入后本地更新，不重读——它们与订阅数据无关，重读只是多两次查询。
library;

import 'package:flux/core/core.dart';

import 'package:flux/features/settings/application/settings_store.dart';

import 'feed_overview.dart';

/// 全局刷新策略（SET-020 全局开关与间隔、SET-021 启动时刷新）。
///
/// 三项都是**设置**，本轮不做后台调度（T016 落地）：界面必须如实说明这一点，
/// 否则用户会以为开启后应用会在后台自动联网。
class RefreshPolicy {
  /// 构造策略。
  const RefreshPolicy({
    required this.autoRefreshEnabled,
    required this.intervalSetting,
    required this.refreshOnLaunch,
  });

  /// SET-020 的全局开关。
  final bool autoRefreshEnabled;

  /// SET-020 的间隔取值（'manual' / '15' / '30' / '60' / '120'）。
  ///
  /// 保存的是注册表口径的**字符串**而不是 int：注册表用 EnumSpec 约束取值，
  /// 在这里转成 int 再转回去会引入一次「非法值怎么表示」的判断，而那个判断
  /// 属于注册表。
  final String intervalSetting;

  /// SET-021 启动时刷新。
  final bool refreshOnLaunch;

  /// 默认值（与 SET-020/021 的文档口径一致：开 / 60 分钟 / 开）。
  static const RefreshPolicy defaults = RefreshPolicy(
    autoRefreshEnabled: true,
    intervalSetting: '60',
    refreshOnLaunch: true,
  );

  /// 复制并覆盖部分字段。
  RefreshPolicy copyWith({
    bool? autoRefreshEnabled,
    String? intervalSetting,
    bool? refreshOnLaunch,
  }) => RefreshPolicy(
    autoRefreshEnabled: autoRefreshEnabled ?? this.autoRefreshEnabled,
    intervalSetting: intervalSetting ?? this.intervalSetting,
    refreshOnLaunch: refreshOnLaunch ?? this.refreshOnLaunch,
  );
}

/// 订阅管理页的完整状态。
class FeedManagerState {
  /// 构造状态。
  const FeedManagerState({
    required this.overview,
    required this.collapsed,
    required this.policy,
    this.policyReadFailed = false,
    this.collapseReadFailed = false,
  });

  /// 分组与订阅。
  final FeedOverview overview;

  /// 分组折叠状态（键为分组 id 的字符串形式）。
  final Map<String, bool> collapsed;

  /// 全局刷新策略。
  final RefreshPolicy policy;

  /// 策略读取是否失败（失败时用的是注册表默认值，界面需要说明）。
  final bool policyReadFailed;

  /// 折叠状态读取是否失败（失败时全部按展开渲染）。
  final bool collapseReadFailed;

  /// 某个分组是否处于折叠状态（未知按展开，与 SET-025 默认值一致）。
  bool isCollapsed(int groupId) => collapsed['$groupId'] ?? false;

  /// 复制并覆盖部分字段。
  FeedManagerState copyWith({
    FeedOverview? overview,
    Map<String, bool>? collapsed,
    RefreshPolicy? policy,
    bool? policyReadFailed,
    bool? collapseReadFailed,
  }) => FeedManagerState(
    overview: overview ?? this.overview,
    collapsed: collapsed ?? this.collapsed,
    policy: policy ?? this.policy,
    policyReadFailed: policyReadFailed ?? this.policyReadFailed,
    collapseReadFailed: collapseReadFailed ?? this.collapseReadFailed,
  );
}

/// 一次删除分组操作的结果（供界面选择提示文案）。
class GroupDeletionReport {
  /// 构造报告。
  const GroupDeletionReport({required this.outcome, required this.groupName});

  /// 用例的结果。
  final GroupDeletionOutcome outcome;

  /// 被删除分组的名称（提示文案需要它，而此时分组已不在状态里）。
  final String groupName;
}

/// 折叠状态与刷新策略的读取端口集合（把三个端口收成一个，便于测试替换）。
class FeedManagerPorts {
  /// 构造端口集合。
  const FeedManagerPorts({required this.collapseStore, required this.settings});

  /// 本机折叠状态。
  final GroupCollapseStore collapseStore;

  /// 设置读写（SET-020/021）。
  final SettingsStore settings;
}

/// 从注册表口径解析 SET-020/021，读不到时回退默认值并标记失败。
Future<(RefreshPolicy, bool)> readRefreshPolicy(SettingsStore settings) async {
  final Result<Object?> auto = await settings.readSetting(SettingId.set020);
  final Result<Object?> launch = await settings.readSetting(SettingId.set021);
  if (auto.isErr || launch.isErr) {
    return (RefreshPolicy.defaults, true);
  }
  final Object? autoValue = auto.valueOrNull;
  final bool enabled = autoValue is Map<Object?, Object?>
      ? (autoValue['enabled'] is bool ? autoValue['enabled']! as bool : true)
      : true;
  final String interval = autoValue is Map<Object?, Object?>
      ? (autoValue['intervalMinutes'] is String
            ? autoValue['intervalMinutes']! as String
            : '60')
      : '60';
  final Object? launchValue = launch.valueOrNull;
  return (
    RefreshPolicy(
      autoRefreshEnabled: enabled,
      intervalSetting: interval,
      refreshOnLaunch: launchValue is bool ? launchValue : true,
    ),
    false,
  );
}
