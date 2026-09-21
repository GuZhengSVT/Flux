// Flux AI 任务状态枚举（T007，对应手册 6.4 与 SET-056/059）。
//
// 为什么单独成文件：状态值被状态机、数据库实体（T009 的 AITask）和 UI 同时
// 引用；把它放在 core 里让三层共享同一份定义，避免字符串漂移。
library;

/// AI 任务的生命周期状态。
///
/// 语义说明：
/// - [queued]：已创建、尚未开始（例如等待调度或等待用户确认费用）。
/// - [running]：正在执行，占用预算与并发额度。
/// - [waitingConfiguration]：缺少必要配置（未配置 AI/搜索、未确认费用告知）。
///   此时**不发网络请求**（D-08、SET-056）。
/// - [waitingNetwork]：配置就绪但当前无网络，等待恢复；可被取消。
/// - [succeeded]：产出通过校验并已保存为成功版本。
/// - [partial]：产出不完整但已保存（例如部分必访站失败、部分引用无法核验）。
/// - [failed]：执行失败且无可接受的产出。
/// - [cancelled]：用户或上层主动取消。
/// - [interrupted]：进程被终止/崩溃留下，**不由旧任务自行恢复**；恢复由新任务
///   承接，旧任务保持 [interrupted] 作为事实记录（T030）。
enum TaskStatus {
  queued,
  running,
  waitingConfiguration,
  waitingNetwork,
  succeeded,
  partial,
  failed,
  cancelled,
  interrupted;

  /// 是否为终态：终态不允许再迁移。
  ///
  /// [interrupted] 也是终态——它是“旧任务到此为止”的记录，恢复走新任务。
  bool get isTerminal => switch (this) {
    TaskStatus.succeeded ||
    TaskStatus.partial ||
    TaskStatus.failed ||
    TaskStatus.cancelled ||
    TaskStatus.interrupted => true,
    TaskStatus.queued ||
    TaskStatus.running ||
    TaskStatus.waitingConfiguration ||
    TaskStatus.waitingNetwork => false,
  };

  /// 是否处于“活跃/进行中”状态：仍占用调度槽位、可被取消。
  bool get isActive => !isTerminal;

  /// 是否已完成（成功或部分成功），此时应存在可用产出。
  bool get isCompleted =>
      this == TaskStatus.succeeded || this == TaskStatus.partial;

  /// 该状态是否要求“网络中”语义（用于 UI 显示与网络策略判断）。
  bool get isWaiting =>
      this == TaskStatus.waitingConfiguration ||
      this == TaskStatus.waitingNetwork;
}
