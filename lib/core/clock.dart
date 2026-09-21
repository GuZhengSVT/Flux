// Flux 时钟抽象（T007）。
//
// 为什么需要它：预算是按“墙钟”计的（任务总时限 10 分钟、单次首响应 45 秒），
// 状态机还有“deadline 不得被推后”的规则。如果业务代码直接读 `DateTime.now()`，
// 这些规则就没法在测试里确定性地验证，只能靠真实等待。
//
// 约定：domain/application 只依赖 [Clock] 接口；production 注入 [SystemClock]，
// 测试注入 [FakeClock]。
library;

/// 时间来源。
abstract interface class Clock {
  /// 当前时刻。返回本地或 UTC 由实现决定；[SystemClock] 默认返回 UTC，
  /// 避免跨时区测试与存储不一致（架构第 5.1 节：时间按 UTC 存储）。
  DateTime now();

  /// 当前时刻的单调时间戳，仅用于计算耗时差；不用于跨进程/跨设备比较。
  Duration monotonic();
}

/// 生产实现：直接读取系统时钟。
final class SystemClock implements Clock {
  const SystemClock();

  /// 进程级单调计时锚点；第一次访问时启动，之后只读取累计耗时。
  static final Stopwatch _stopwatch = Stopwatch()..start();

  @override
  DateTime now() => DateTime.now().toUtc();

  @override
  Duration monotonic() => _stopwatch.elapsed;
}

/// 测试实现：手动推进时间，让超时/预算逻辑可确定性验证。
final class FakeClock implements Clock {
  /// 以 [start]（默认 2026-01-01T00:00:00Z）为起点创建可控时钟。
  FakeClock({DateTime? start})
    : _now = (start ?? DateTime.utc(2026, 1, 1)).toUtc();

  DateTime _now;
  Duration _elapsed = Duration.zero;

  /// 当前时刻（UTC）。
  DateTime get current => _now;

  @override
  DateTime now() => _now;

  @override
  Duration monotonic() => _elapsed;

  /// 向前推进 [delta]；负值会被忽略，以免误造成时光倒流。
  void advance(Duration delta) {
    if (delta <= Duration.zero) {
      return;
    }
    _now = _now.add(delta);
    _elapsed += delta;
  }

  /// 把时钟拨到指定时刻，并把单调时间同步推进相应差值。
  /// 用于模拟设备时钟被改动（负向跳变也应被上层显式处理）。
  void set(DateTime instant) {
    final DateTime target = instant.toUtc();
    _elapsed += target.difference(_now);
    _now = target;
  }
}
