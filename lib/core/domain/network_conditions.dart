// 网络状况查询端口（T016；架构 4.1「计费网络遵守 SET-013」、SET-028）。
//
// 为什么把「当前网络是否计费/是否离线」做成端口而不是让调度直接调平台 API：
//   - features 层不得 import infrastructure（架构 2.2，测试会实际拦截），而
//     刷新调度必须在上网**之前**知道这件事——先发一次请求再判断「不该发」已经
//     产生了流量；
//   - 测试要能确定性地构造「当前是计费网络」「当前无网络」两种世界；
//   - 桌面与移动的判定能力差别很大（macOS 没有公开的计费网络 API），因此需要
//     一个可以各自实现、并且**允许如实回答「不知道」**的入口。
//
// 两条实现约定（非常重要，写在这里而不是只写在实现里）：
//   1) 两个方法**永不抛异常**。探测失败是正常情况（权限、平台不支持），实现内部
//      捕获后回答 false（= 未知/不阻塞）。
//   2) false 的语义是「没有证据表明受限」，不是「确认不受限」。因此守卫的方向
//      永远是**放行**：宁可多一次会在连接层失败并留痕的请求，也不要因为探测不到
//      就把刷新永久停住——那是用户看不懂的「刷新坏了」。
library;

/// 网络状况查询端口。
abstract interface class NetworkConditionPort {
  /// 当前连接是否被判定为计费网络（蜂窝/热点计费）。
  ///
  /// 桌面实现返回 false：macOS 没有公开的 API 能可靠回答这个问题，而在没有证据时
  /// 回答「计费」会让 SET-013 在桌面上变成「默认禁止刷新」。真正的计费判定能力
  /// （Android 的 ConnectivityManager）在 Android 阶段接在同一个端口上。
  Future<bool> isMetered();

  /// 当前是否确定无网络（没有任何可用的非回环网络接口）。
  ///
  /// 这是**尽力而为**的判断：回答 false 不代表一定有网。真正权威的信号是抓取
  /// 层返回的连接级失败（见 [FeedRefreshOutcome.waitingNetwork] 的说明）。
  Future<bool> isOffline();
}

/// 一个总是回答「不受限」的端口（测试与无探测能力的场合使用）。
///
/// 默认放行是刻意的：这个实现不会让任何刷新被守卫拦住，因此它不会把「未实现探测」
/// 伪装成「已确认可用」——它只回答「没有证据表明受限」。
final class PermissiveNetworkConditions implements NetworkConditionPort {
  /// 构造放行实现。
  const PermissiveNetworkConditions();

  @override
  Future<bool> isMetered() async => false;

  @override
  Future<bool> isOffline() async => false;
}
