// 数据库不可用时的任务与缓存存储（T030）。
//
// 与 degraded_ai_model_store 同一口径（T025 的既定做法）：
//   - 读返回**空**并明确说明：本次运行确实没有任何可读的任务记录，空集合是真实的答案；
//   - 写一律返回类型化失败：不落盘却报成功会让用户以为任务已经保存，重启后记录消失
//     而中间没有任何提示。
//
// 为什么不在这里抛异常：数据库不可用是**可诊断的正常状态**（启动降级），抛异常会让
// 任务列表页直接崩掉，而它本来是可以显示「本次运行不保存记录」的。
library;

import 'package:flux/core/core.dart';
import 'package:flux/features/ai/domain/ai_task_record.dart';
import 'package:flux/features/ai/domain/ai_task_store.dart';

/// 降级任务存储：读空、写失败。
final class DegradedAiTaskStore implements AiTaskStore {
  /// 构造降级存储。
  const DegradedAiTaskStore();

  @override
  Future<Result<void>> save(AiTaskRecord record) async => Err<void>(
    StorageError(operation: 'aiTask.save', detail: '本次运行数据库不可用，任务记录不会保存'),
  );

  @override
  Future<Result<AiTaskRecord?>> findById(String taskId) async =>
      const Ok<AiTaskRecord?>(null);

  @override
  Future<Result<List<AiTaskRecord>>> loadAll() async =>
      const Ok<List<AiTaskRecord>>(<AiTaskRecord>[]);

  /// 标中断在降级模式下是**空操作且成功**：没有库就没有历史活跃任务，
  /// 「标记了 0 条」是真实的答案（不是失败）。
  @override
  Future<Result<int>> markActiveAsInterrupted({required DateTime at}) async =>
      const Ok<int>(0);

  @override
  Future<Result<void>> delete(String taskId) async =>
      Err<void>(StorageError(operation: 'aiTask.delete', detail: '本次运行数据库不可用'));
}

/// 降级结果缓存：永不命中、写入明确失败。
///
/// 同时实现 [AiResultCacheMaintenance]：降级下「占用 0 条、0 字节」是**真实**答案（本次运行
/// 确实没有缓存），而淘汰是空操作且成功——与 [clear] 同一口径。给维护能力返回失败会让设置页
/// 在有缓存关联的每一处都显示一条与用户无关的错误。
final class DegradedAiResultCache
    implements AiResultCache, AiResultCacheMaintenance {
  /// 构造降级缓存。
  const DegradedAiResultCache();

  /// 读返回「未命中」是**真实**答案（本次运行确实没有缓存可用），因此返回 Ok(null)
  /// 而不是 Err：上层据此照常发起真实请求，功能不会因为缓存不可用而停摆。
  @override
  Future<Result<AiResultCacheEntry?>> find(String key) async =>
      const Ok<AiResultCacheEntry?>(null);

  @override
  Future<Result<void>> save(AiResultCacheEntry entry) async => Err<void>(
    StorageError(
      operation: 'aiResultCache.save',
      detail: '本次运行数据库不可用，结果不会写入缓存',
    ),
  );

  @override
  Future<Result<void>> delete(String key) async => Err<void>(
    StorageError(operation: 'aiResultCache.delete', detail: '本次运行数据库不可用'),
  );

  /// 清空在降级模式下是空操作且成功：没有库就没有缓存可清（与「清空失败」不同）。
  @override
  Future<Result<void>> clear() async => okUnit();

  /// 降级下没有缓存，因此占用为 0——这是诚实的答案，不是「读取失败」。
  @override
  Future<Result<({int entries, int bytes})>> usage() async =>
      const Ok<({int entries, int bytes})>((entries: 0, bytes: 0));

  /// 没有缓存可淘汰：返回 0 条（与 clear 的「空操作且成功」同一口径）。
  @override
  Future<Result<int>> enforceLimits(AiCacheLimits limits) async =>
      const Ok<int>(0);
}
