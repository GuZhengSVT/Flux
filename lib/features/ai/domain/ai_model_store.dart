// AI 模型记录的持久化端口（T025；架构 2.2「用例层依赖接口」）。
//
// 端口只描述「存/取/改/删」，不描述实现介质（本工程是 SQLite；将来同步阶段会在
// 同一端口后面再套一层合并逻辑）。所有方法返回 [Result]，不抛异常：唯一的冲突
// 是**别名重复**，它是可预期的用户输入问题，需要变成表单提示而不是崩溃。
library;

import 'package:flux/core/core.dart';

import 'ai_model.dart';

/// 模型记录的持久化端口。
abstract interface class AiModelStore {
  /// 载入全部模型（按故障转移顺序升序，其次按 id 稳定排序）。
  Future<Result<List<AiModel>>> loadAll();

  /// 插入一条新记录，返回带 id 的记录。
  ///
  /// 别名冲突时必须返回 [ValidationError]（field: SET-030.alias），而不是覆盖已有
  /// 记录：覆盖会把另一个模型的凭据引用悄悄接到新配置上。
  Future<Result<AiModel>> insert(AiModel model);

  /// 按 id 更新一条记录（别名冲突同样返回 [ValidationError]）。
  Future<Result<AiModel>> update(AiModel model);

  /// 按 id 删除一条记录；不存在时返回 `Err(StorageError(isMissing: true))`。
  Future<Result<void>> delete(int id);

  /// 批量写入排序（按列表位置赋 sortOrder）；用于「依排序故障转移」（SET-032）。
  ///
  /// 放在存储层而不是「循环调用 update」：排序是一次用户动作产生的**一组**写入，
  /// 中途失败会留下两个序号相同或跳号的中间状态，界面上的顺序与故障转移顺序就不一致了。
  Future<Result<void>> saveOrder(List<int> idsInOrder);

  /// 把某条记录设为唯一默认（同时清除其它记录的默认标记）。
  ///
  /// 唯一性由存储层在一个事务里保证：「两个默认模型」这种状态一旦落库，之后任何
  /// 一处「取默认」的代码都会变得不确定（取决于查询顺序）。
  Future<Result<void>> setDefaultForTasks(int id, {required bool isDefault});
}
