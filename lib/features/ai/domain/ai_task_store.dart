// 持久任务与结果缓存的端口（T030；架构 2.2「用例层依赖接口」、4.5）。
//
// 两个端口合在一个文件里，因为它们的**生命周期是同一件事的两面**：一次任务的写入
// （任务行 + 成功结果缓存）必须同步发生，否则会出现「任务成功但缓存没写」或
// 「缓存有结果但任务显示失败」这类互相矛盾的状态；把它们放在同一个实现上、
// 由用例层在同一个调用里完成，是最容易审计的形状。
//
// 所有方法返回 [Result]，不抛异常：「库里没这条记录」与「读取失败」是两件事
// （前者返回 Ok(null)，后者返回 Err(storage)），把它们混成一个 null 会让
// 「缓存命中判定」在存储故障时静默变成「没命中」。
library;

import 'package:flux/core/core.dart';

import 'ai_task_record.dart';

/// 持久任务的读写端口。
abstract interface class AiTaskStore {
  /// 写入或整体覆盖一条任务记录（以 taskId 为主键）。
  Future<Result<void>> save(AiTaskRecord record);

  /// 按 taskId 读取；不存在时返回 Ok(null)。
  Future<Result<AiTaskRecord?>> findById(String taskId);

  /// 列出全部任务（按创建时间倒序，其次按 taskId 稳定排序）。
  Future<Result<List<AiTaskRecord>>> loadAll();

  /// 把「上次进程结束时仍在进行中」的任务一次性标成 interrupted。
  ///
  /// 返回被标记的条数（供诊断与界面提示「有 N 个任务被中断」）。
  ///
  /// 为什么必须**批量一次**完成而不是逐个读改写：逐个处理时若中途再崩溃，会留下
  /// 一部分 interrupted、一部分仍是 running 的混合状态，而下一次启动无法区分
  /// 「真的还在跑」与「上次没标完」。
  Future<Result<int>> markActiveAsInterrupted({required DateTime at});

  /// 彻底删除一条任务记录（用户主动清理）。
  Future<Result<void>> delete(String taskId);
}

/// 结果缓存的读写端口。
abstract interface class AiResultCache {
  /// 按缓存键读取；不存在时返回 Ok(null)。
  Future<Result<AiResultCacheEntry?>> find(String key);

  /// 写入（或替换）一条缓存记录。
  ///
  /// 约定：**只允许写入成功产出**。失败结果不写缓存（架构 4.5），否则一次网络抖动
  /// 会被固化成之后所有同输入任务的结果。
  Future<Result<void>> save(AiResultCacheEntry entry);

  /// 删除一条缓存（输入/模型/语言变化后由用例层显式失效时使用）。
  Future<Result<void>> delete(String key);

  /// 清空全部缓存（设置页的「清缓存」；不删任务状态，见 T047）。
  Future<Result<void>> clear();
}

/// 结果缓存的**维护能力**（T047：容量统计与淘汰）。
///
/// 为什么单独一个接口而不是往 [AiResultCache] 上加两个方法：那几个方法的调用方是**任务
/// 执行路径**（读写一条具体缓存），而这两个是**资源维护**（看总量、按上限淘汰）。分开之后：
///   * 任务路径拿到的接口里没有「按上限删一批」这种能力，因此一次任务执行不可能顺手清掉
///     别人的缓存；
///   * 已有的缓存替身（测试里的 FakeResultCache / FakeTranslationCache）只需实现它们真正
///     参与的那一半，不必为维护能力写一个「不会被调用」的空实现——那种空实现会在将来某次
///     真正的维护调用里返回假数据。
///
/// 生产实现（drift）同时实现两个接口，因此「写入后自动淘汰」与「按需统计」用的是同一份数据。
abstract interface class AiResultCacheMaintenance {
  /// 当前条目数与占用字节。
  Future<Result<({int entries, int bytes})>> usage();

  /// 按上限淘汰，返回本次删除的条数。
  ///
  /// 判定住在 core 的纯函数 [planAiCacheEviction] 里，这里只负责执行——因此「淘汰顺序
  /// 确定」「不删刚写入的那条」这些性质可以在不碰数据库的情况下被逐条断言。
  Future<Result<int>> enforceLimits(AiCacheLimits limits);
}
