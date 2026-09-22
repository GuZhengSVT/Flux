// 每日新闻任务的 Provider（T037）。
//
// 与 T036 的新闻配置 Provider 同一做法：端口与装配分开，端口默认抛错（漏接线立刻暴露），
// 组合根负责把 infrastructure 的实现接上来。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flux/core/core.dart';
import 'package:flux/features/ai/application/search_manager.dart';
import 'package:flux/features/ai/application/search_manager_controller.dart';
import 'package:flux/features/ai/domain/search_service.dart';

import 'news_run_service.dart';

/// 选材候选读取端口（实现住 infrastructure/local 的 DriftNewsCandidateStore）。
final Provider<NewsCandidateStore> newsCandidateStoreProvider =
    Provider<NewsCandidateStore>(
      (Ref ref) => throw StateError(
        'newsCandidateStoreProvider 未被组合根覆盖：见 lib/app/app_providers.dart',
      ),
    );

/// 新闻任务版本存储端口（实现住 infrastructure/local 的 DriftNewsRunStore）。
final Provider<NewsRunStore> newsRunStoreProvider = Provider<NewsRunStore>(
  (Ref ref) => throw StateError(
    'newsRunStoreProvider 未被组合根覆盖：见 lib/app/app_providers.dart',
  ),
);

/// 一次任务的编排服务构造器（把「按当前设置造一个服务」做成可注入的函数）。
///
/// 为什么是构造器而不是一个现成的 [NewsRunService] 实例：上限（SET-060/061/062/063）与
/// 总时限（SET-059）要**异步**读设置，而 Provider 的构造是同步的；更要紧的是每次生成都
/// 必须拿到**一份新的**工具次数预算，否则同一天里的第二次生成会继承第一次的已用次数。
///
/// 返回值是异步的：读设置本身是异步的，而「读设置」与「按设置造服务」必须是同一件事——
/// 分成两步会让调用点有机会用上一次读到的旧值去造这一次的服务。
typedef NewsRunServiceBuilder = Future<NewsRunService> Function({
  required SessionLocalZone zone,
  void Function(NewsRunStage stage)? onStage,
  void Function(NewsSiteFetchResult result)? onSiteResult,
});

/// 编排服务构造器（组合根提供实现）。
final Provider<NewsRunServiceBuilder> newsRunServiceBuilderProvider =
    Provider<NewsRunServiceBuilder>(
      (Ref ref) => throw StateError(
        'newsRunServiceBuilderProvider 未被组合根覆盖：见 lib/app/app_providers.dart',
      ),
    );

/// 检索可用性（由 SearchManager 转接）。
///
/// 单独一层而不是直接用 SearchManager：新闻链路只关心「有没有启用的搜索服务」这一个
/// 布尔事实，把它暴露成窄接口可以让「未联网核验」标签的判定与搜索服务管理的其余能力
/// （保存、删除、测试）解耦。
final Provider<NewsSearchAvailability> newsSearchAvailabilityProvider =
    Provider<NewsSearchAvailability>(
      (Ref ref) =>
          SearchManagerNewsAvailability(ref.watch(searchManagerProvider)),
    );

/// 由 [SearchManager] 实现的检索可用性。
final class SearchManagerNewsAvailability implements NewsSearchAvailability {
  /// 构造实现。
  const SearchManagerNewsAvailability(this._manager);

  final SearchManager _manager;

  @override
  Future<Result<bool>> hasEnabledService() async {
    // 只关心「有没有启用的服务」这一个事实，因此读到的列表**不离开**这一层：
    // 把服务记录透出去会让上层有机会顺手拿它做别的事（保存/删除），而本端口的存在
    // 意义正是把新闻链路限制在「知道能不能联网核验」这一件事上。
    final Result<List<SearchService>> enabled = await _manager
        .loadEnabledServices();
    if (enabled.isErr) {
      return Err<bool>(enabled.errorOrNull!);
    }
    return Ok<bool>(enabled.valueOrNull!.isNotEmpty);
  }
}
