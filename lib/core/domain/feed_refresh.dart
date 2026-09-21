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
  parseFailed;

  /// 是否值得在界面上明显提示（失败类需要用户注意）。
  bool get isFailure =>
      this == FeedRefreshOutcome.networkFailed ||
      this == FeedRefreshOutcome.parseFailed;

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
