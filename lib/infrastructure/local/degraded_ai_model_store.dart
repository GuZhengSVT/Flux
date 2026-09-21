// 数据库不可用时的模型存储（T025）。
//
// 读返回空列表但**带上明确说明**、写一律返回类型化失败：与
// degraded_article_catalog_store / degraded_reading_stats_store 同一口径。
//
// 为什么读不失败而写要失败：本次运行确实「没有任何模型可用」，返回空列表是**真实的**
// 答案（界面会显示「尚未配置模型」并说明降级状态）；而写入不落盘却报成功，会让用户
// 以为配置好了，重启后配置消失且中间没有任何提示。
library;

import 'package:flux/core/core.dart';
import 'package:flux/features/ai/domain/ai_model.dart';
import 'package:flux/features/ai/domain/ai_model_store.dart';

/// 降级实现。
final class DegradedAiModelStore implements AiModelStore {
  /// 构造降级存储。
  const DegradedAiModelStore();

  @override
  Future<Result<List<AiModel>>> loadAll() async =>
      const Ok<List<AiModel>>(<AiModel>[]);

  @override
  Future<Result<AiModel>> insert(AiModel model) async =>
      Err<AiModel>(_unavailable('aiModel.insert'));

  @override
  Future<Result<AiModel>> update(AiModel model) async =>
      Err<AiModel>(_unavailable('aiModel.update'));

  @override
  Future<Result<void>> delete(int id) async => Err<void>(
    StorageError(operation: 'aiModel.delete', detail: '本次运行数据库不可用'),
  );

  @override
  Future<Result<void>> saveOrder(List<int> idsInOrder) async =>
      Err<void>(_unavailable('aiModel.saveOrder'));

  @override
  Future<Result<void>> setDefaultForTasks(
    int id, {
    required bool isDefault,
  }) async => Err<void>(_unavailable('aiModel.setDefaultForTasks'));

  StorageError _unavailable(String operation) =>
      StorageError(operation: operation, detail: '本次运行数据库不可用，模型配置不会保存');
}
