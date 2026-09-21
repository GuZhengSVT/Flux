// 刷新结果的用户可见文案（T016）。
//
// 单独一个文件（而不是写在按钮回调里）是因为结果分类有五条容易写错的边界，
// 它们都来自架构 4.1 对「区分 304、没有新文章、部分解析失败、网络失败」的要求：
//
//   1) 源没有再更新（304）与「检查了但没有新文章」在用户看来是一件事，可以说成同一句
//      （都是「暂无更新」），但两者都**不等于失败**；
//   2) 离线与计费网络守卫**不是失败**：一个字节都没发出去，说「刷新失败」会让用户去
//      检查订阅地址；
//   3) 部分失败必须说清「旧内容已保留」——否则用户以为失败的源把文章清空了；
//   4) 一个源都没跑到时要区分原因（被守卫拦下 vs 没有启用的源），两者的下一步动作不同；
//   5) 新增数量为 0 但有失败时不能报成功。
//
// 放在 presentation 而不是 application：它只做「对哪种情况说哪句话」的映射，
// 用的是 l10n 资源，因此属于展示层。
library;

import 'package:flux/features/feeds/application/refresh_providers.dart';
import 'package:flux/features/feeds/application/refresh_scheduler.dart';
import 'package:flux/core/core.dart';
import 'package:flux/l10n/l10n.dart';

/// 把一次刷新的结果翻译成一句用户能核对的话。
String describeRefreshOutcome(AppLocalizations l10n, RefreshStatus status) {
  if (status.lastError case final AppError error) {
    return l10n.readingRefreshFailed(error.message);
  }
  final RefreshRunReport? report = status.lastReport;
  if (report == null) {
    return l10n.readingRefreshNotModified(0);
  }
  if (report.attempted == 0) {
    // 一个源都没跑到：被守卫拦下时说网络原因（用户能自己处理），否则说明没有
    // 启用的源——两种情况的下一个动作完全不同，不能共用一句话。
    for (final FeedRefreshSkip skip in report.skipped) {
      switch (skip.deferral) {
        case FeedRefreshDeferral.meteredNetwork:
          return l10n.readingRefreshMetered;
        case FeedRefreshDeferral.offline:
          return l10n.readingRefreshOffline;
        case null:
          continue;
      }
    }
    return l10n.readingRefreshNotModified(0);
  }
  // 全部源都因未联网而延迟：这是延迟，不是失败。
  if (report.deferredCount == report.attempted) {
    return l10n.readingRefreshOffline;
  }
  if (report.failedCount > 0) {
    return l10n.readingRefreshPartial(report.insertedTotal, report.failedCount);
  }
  if (report.insertedTotal > 0) {
    return l10n.readingRefreshDone(report.insertedTotal, report.attempted);
  }
  return l10n.readingRefreshNotModified(report.attempted);
}
