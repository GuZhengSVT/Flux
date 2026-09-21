// 诊断记录端口（T013）。
//
// 为什么需要一个 **port** 而不是直接让 features 调 DiagnosticLog：
//   features 层不得 import infrastructure（架构 2.2，测试会拦截），而刷新流程必须记录
//   「解析失败 / 网络失败 / 丢掉了什么」这类信息。把「能记一条日志」这一件事抽成最小接口，
//   由 infrastructure 的 DiagnosticLog 实现，features 只依赖这个接口。
//
// 为什么只暴露三个方法与一个级别枚举，而不直接给「任意日志对象」：
//   刷新的诊断需求是固定的（出错、部分失败、丢弃内容），收窄接口可以避免 features 顺手
//   把正文或凭据写进日志——它拿不到更宽的写入口。
library;

/// 诊断级别（与 infrastructure 的 DiagnosticLevel 语义一致，但不是同一个类型）。
///
/// 刻意分成两层类型：core 是纯 Dart 层，不能依赖 infrastructure 的实现细节；两者通过
/// 一个薄的适配器连接（见 lib/app/app_bootstrap.dart）。
enum DiagnosticSeverity {
  /// 错误：功能失败。
  error,

  /// 警告：功能受限但有降级结果。
  warning,

  /// 信息：正常流程的补充说明。
  info,
}

/// 诊断记录端口。
abstract interface class DiagnosticSink {
  /// 记录一条诊断。
  ///
  /// [message] 不需要调用方预先脱敏——实现负责脱敏（这是「不靠调用方自觉」的落点）。
  /// [tag] 是短分类标签（例如 'feed.fetch'、'feed.parse'），便于筛读。
  void record(DiagnosticSeverity severity, String message, {String? tag});

  /// 记录错误。
  ///
  /// 声明为抽象而不给默认实现：Dart 的 interface class 里写具体方法体
  /// 不会被 implements 继承，写成默认实现会让每个实现类都必须重复它。
  void error(String message, {String? tag});

  /// 记录警告。
  void warning(String message, {String? tag});

  /// 记录信息。
  void info(String message, {String? tag});
}

/// 一个丢弃全部记录的实现（测试与「不需要日志」的场合使用）。
///
/// 提供它是为了少写一堆 null 判断：调用方总是有一个可用的 sink，因此可以无条件记录。
final class NoopDiagnosticSink implements DiagnosticSink {
  /// 构造空 sink。
  const NoopDiagnosticSink();

  @override
  void record(DiagnosticSeverity severity, String message, {String? tag}) {}

  @override
  void error(String message, {String? tag}) {}

  @override
  void warning(String message, {String? tag}) {}

  @override
  void info(String message, {String? tag}) {}
}
