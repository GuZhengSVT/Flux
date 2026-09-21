// 订阅抓取结果类别（T013；架构 4.1「区分 304、没有新文章、部分解析失败和网络失败」）。
//
// 为什么必须是**四类以上**而不是布尔「成功/失败」：
//   - 「304 未修改」不是失败，也不该显示成成功抓取到内容；
//   - 「有新内容」与「成功但源里没有新文章」对用户是两件事（前者要提示数量，
//     后者应安静）；
//   - 「部分解析失败」意味着**已保留旧内容**且部分条目被拒绝，用户需要知道
//     有什么东西没进来，这既不是完整成功也不是整体失败。
// 布尔无法表达这四种语义，硬压会直接导致界面说谎。
library;

/// 一次订阅抓取的结果类别（存入 feeds.lastRefreshResult）。
enum FeedRefreshOutcome {
  /// 有新内容并已入库。
  updated,

  /// 请求成功、解析成功，但源里没有新条目（全部已存在且无变化）。
  unchanged,

  /// 条件请求返回 304：源未修改，**不更新任何文章**，只记录检查时间。
  notModified,

  /// 部分条目解析失败：已保留旧内容，成功条目照常入库。
  partial,

  /// 网络或 HTTP 层失败（连接、超时、非 2xx、重定向超限、响应过大）。
  networkFailed,

  /// 响应体无法解析（畸形 XML、含 DTD/外部实体被拒、结构不符合 RSS/Atom）。
  parseFailed,

  /// 当前无网络（连接层失败）：**没有发起有效请求也没有内容可写**，等网络恢复
  /// 后在下次触发时重试。
  ///
  /// 为什么与 [networkFailed] 分开：两者对用户的含义与对调度的含义都不同。
  /// [networkFailed] 是「请求发出去了但失败」（源站 5xx、超时、重定向超限），
  /// 指向源的问题；本值是「整机没网」，指向环境的问题，且**不应该**推进
  /// 「上次检查时间」——否则用户切回网络后会因为「刚检查过」而白等一个间隔。
  waitingNetwork,

  /// 计费网络守卫拦下（SET-013 关闭，且当前网络被判定为计费）。
  ///
  /// 与 [waitingNetwork] 同为「未执行的等待态」：不推进检查时间，不写文章。
  skippedMetered;

  /// 是否值得在界面上明显提示（失败类需要用户注意）。
  bool get isFailure =>
      this == FeedRefreshOutcome.networkFailed ||
      this == FeedRefreshOutcome.parseFailed;

  /// 是否属于「本次未联网」的延迟态（离线/计费网络守卫）。
  ///
  /// 界面据此显示「等待网络」而不是「失败」：用户没有做错任何事，源也没有坏，
  /// 把它显示成失败会诱导用户去检查订阅地址。
  bool get isDeferred =>
      this == FeedRefreshOutcome.waitingNetwork ||
      this == FeedRefreshOutcome.skippedMetered;

  /// 是否需要在界面上明确提示（失败或未联网都算）。
  bool get needsAttention => isFailure || isDeferred;

  /// 本次抓取是否产生了新的已入库内容。
  bool get hasNewContent => this == FeedRefreshOutcome.updated;

  /// 从持久化文本还原；未知/缺失值回退 [networkFailed] 之外的保守取值。
  ///
  /// 回退到 [unchanged] 而不是抛错：该列是运行时诊断，一个来自更新版本写的
  /// 未知类别不应该让界面崩掉。回退成「无变化」也不冒充任何一次真实抓取结果。
  static FeedRefreshOutcome? fromName(String? name) {
    if (name == null || name.isEmpty) {
      return null;
    }
    for (final FeedRefreshOutcome value in FeedRefreshOutcome.values) {
      if (value.name == name) {
        return value;
      }
    }
    return null;
  }
}

/// 调度层**在上网之前**拦下一次刷新的原因（T016）。
///
/// 为什么需要它，而不是「先请求、失败了再分类」：
///   - 计费网络守卫（SET-013）命中时**根本不允许发出请求**——先发一次再报「不该发」
///     已经产生了流量与费用，事后分类无法撤销；
///   - 拦下之后仍然要**如实记录结果**（[FeedRefreshOutcome.skippedMetered] /
///     [FeedRefreshOutcome.waitingNetwork]），否则界面会显示一个静止的「上次检查」
///     时间，看起来像调度坏了。
///
/// 与「失败」的区别：这不是源的问题，也不是请求的问题，用户没有做错任何事。
enum FeedRefreshDeferral {
  /// SET-013（默认关）：当前网络被判定为计费，且用户没有允许后台请求。
  meteredNetwork,

  /// 调度层已确认无网络（例如上一次检查刚失败）。等待网络恢复，不写任何数据。
  offline;

  /// 该原因对应的记录结果。
  FeedRefreshOutcome get outcome => switch (this) {
    FeedRefreshDeferral.meteredNetwork => FeedRefreshOutcome.skippedMetered,
    FeedRefreshDeferral.offline => FeedRefreshOutcome.waitingNetwork,
  };

  /// 该原因对应的错误类别（写入 feeds.lastRefreshErrorKind）。
  ///
  /// 用稳定的英文类别名而不是文案：它进普通列，界面文案走 l10n。
  String get errorKind => switch (this) {
    FeedRefreshDeferral.meteredNetwork => 'meteredNetwork',
    FeedRefreshDeferral.offline => 'offline',
  };
}
