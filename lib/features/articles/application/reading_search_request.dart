// 「用一段文字去检索」的跨页请求（T049；架构第 3 节「选词复制/查询」在正文里的入口）。
//
// 为什么需要它：用户在**正文**里选中一段文字并点「在库中检索」，而检索框住在 RSS 阅读
// 页。正文页不能直接切去向（去向状态住在 lib/app，features 不得 import app，架构 2.2 的
// 守卫会拦），因此与 T020 的「去设置」用同一条路线：正文页置一个请求，壳层 watch 它、
// 把去向切到阅读页，阅读页再消费这个请求把查询词填进检索框。
//
// 为什么不是一条注入的回调端口：回调要在装配处接到真正的去向切换与检索控制器上，而装配
// 是同步的纯函数，拿不到 ProviderContainer（与 settings_navigation 同一理由）。
//
// 完成语义：**消费者清空**。留着它会让用户之后每次切到阅读页都被重新检索一次同一段
// 文字——一个只该发生一次的意图变成了持续状态（这正是 T020 记录过的坑）。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 待执行的检索请求。
final class ReadingSearchRequest extends Notifier<String?> {
  @override
  String? build() => null;

  /// 请求用 [query] 去检索。
  void request(String query) {
    final String trimmed = query.trim();
    if (trimmed.isEmpty) {
      // 空选区没有检索语义：置空等于「没有请求」，而不是「检索空字符串」。
      return;
    }
    state = trimmed;
  }

  /// 消费后清空（由阅读页调用）。
  void consume() {
    if (state != null) {
      state = null;
    }
  }
}

/// 检索请求 Provider。
final NotifierProvider<ReadingSearchRequest, String?>
readingSearchRequestProvider = NotifierProvider<ReadingSearchRequest, String?>(
  ReadingSearchRequest.new,
);
