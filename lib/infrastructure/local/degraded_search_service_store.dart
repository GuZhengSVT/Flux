// 数据库不可用时的搜索服务存储（T031）。
//
// 读返回空列表但**带上明确说明**、写一律返回类型化失败：与 DegradedAiModelStore
// 同一口径。
//
// 为什么读不失败而写要失败：本次运行确实「没有任何搜索服务可用」，返回空列表是
// **真实的**答案（界面会显示「尚未配置搜索服务」并说明降级状态）；而写入不落盘却
// 报成功，会让用户以为配置好了，重启后配置消失且中间没有任何提示。
library;

import 'package:flux/core/core.dart';
import 'package:flux/features/ai/domain/search_service.dart';
import 'package:flux/features/ai/domain/search_service_store.dart';

/// 降级实现。
final class DegradedSearchServiceStore implements SearchServiceStore {
  /// 构造降级存储。
  const DegradedSearchServiceStore();

  @override
  Future<Result<List<SearchService>>> loadAll() async =>
      const Ok<List<SearchService>>(<SearchService>[]);

  @override
  Future<Result<SearchService>> insert(SearchService service) async =>
      Err<SearchService>(_unavailable('searchService.insert'));

  @override
  Future<Result<SearchService>> update(SearchService service) async =>
      Err<SearchService>(_unavailable('searchService.update'));

  @override
  Future<Result<void>> delete(int id) async =>
      Err<void>(_unavailable('searchService.delete'));

  @override
  Future<Result<void>> saveOrder(List<int> idsInOrder) async =>
      Err<void>(_unavailable('searchService.saveOrder'));

  @override
  Future<Result<void>> setDefaultForTasks(
    int id, {
    required bool isDefault,
  }) async => Err<void>(_unavailable('searchService.setDefaultForTasks'));

  StorageError _unavailable(String operation) =>
      StorageError(operation: operation, detail: '本次运行数据库不可用，搜索服务配置不会保存');
}
