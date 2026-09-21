// 搜索服务记录的持久化端口（T031；架构 2.2「用例层依赖接口」）。
//
// 端口只描述「存/取/改/删」，不描述实现介质（本工程是 SQLite；将来同步阶段会在同一
// 端口后面再套一层合并逻辑）。所有方法返回 [Result]，不抛异常：唯一的冲突是**名字
// 重复**，它是可预期的用户输入问题，需要变成表单提示而不是崩溃。
//
// 与 [AiModelStore] 分端口而不是合并成「AI 与搜索共用一个存储」：两者的字段与索引
// 不同，合并会让两边任一处新增字段都要动同一张表（并让「搜索服务名」与「模型别名」
// 争抢同一个唯一约束的语义）。
library;

import 'package:flux/core/core.dart';

import 'search_service.dart';

/// 搜索服务记录的持久化端口。
abstract interface class SearchServiceStore {
  /// 载入全部记录（按排序升序，其次按 id 稳定排序）。
  Future<Result<List<SearchService>>> loadAll();

  /// 插入一条新记录，返回带 id 的记录。
  ///
  /// 名字冲突时必须返回 [ValidationError]（field: SET-038.label），而不是覆盖已有
  /// 记录：覆盖会把另一个服务的凭据引用悄悄接到新配置上。
  Future<Result<SearchService>> insert(SearchService service);

  /// 按 id 更新一条记录（名字冲突同样返回 [ValidationError]）。
  Future<Result<SearchService>> update(SearchService service);

  /// 按 id 删除一条记录；不存在时返回 isMissing 的存储错误。
  Future<Result<void>> delete(int id);

  /// 批量写入排序（按列表位置赋 sortOrder）。
  ///
  /// 放在存储层而不是「循环调用 update」：排序是一次用户动作产生的**一组**写入，
  /// 中途失败会留下两个序号相同或跳号的中间状态（与 AiModelStore.saveOrder 同一理由）。
  Future<Result<void>> saveOrder(List<int> idsInOrder);

  /// 把某条记录设为唯一默认搜索服务（同时清除其它记录的默认标记）。
  Future<Result<void>> setDefaultForTasks(int id, {required bool isDefault});
}
