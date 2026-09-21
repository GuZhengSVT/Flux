// 列表滚动锚点（T019+；架构 4.1「列表分页/虚拟化，重返时恢复位置」、
// 第 7 节 SET-009 的「返回位置按页面保留」）。
//
// 为什么不能只靠 ScrollController 自己记住位置：
//   ScrollController 的位置属于**它当前的 client**。列表被销毁重建（换去向再回来、
//   布局断点变化导致子树替换）时客户全部脱离，控制器上的偏移随之消失，而下一次挂载
//   用的是创建时的 initialScrollOffset。要真的「重返时恢复」，偏移必须存在列表控件
//   之外。
//
// 因此这里存两个东西，职责分开：
//   - [articleListScrollControllerProvider]：**同一个**控制器实例。它让「滚动中」的
//     位置天然连续（同一个 client 上不做任何跳转）；
//   - [articleListScrollAnchorProvider]：最后已知偏移。它让「重建之后」能跳回原处。
//
// 为什么不存成「第几篇的 id 然后按 id 找回来」：那需要一套「按 id 定位」的机制，而
// 虚拟列表里目标行可能还没被构建出来；偏移量是这个列表本来就有的坐标系，用它最直接。
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 列表共用的滚动控制器。
///
/// 随容器存活（不随页面销毁）：这正是「换去向再回来位置还在」所依赖的性质。
final Provider<ScrollController> articleListScrollControllerProvider =
    Provider<ScrollController>((Ref ref) {
      final ScrollController controller = ScrollController();
      ref.onDispose(controller.dispose);
      return controller;
    });

/// 最后一次已知的滚动偏移。
///
/// 由列表在滚动时写入、在重建后读取。筛选/排序/来源变化时被**重置为 0**：那时列表
/// 已经换了一批内容，停在原来的像素高度上会落到一篇与用户进来时无关的文章上
/// （SET-009 的「返回位置」说的是同一批内容的返回，不是换筛选之后的返回）。
///
/// 为什么是一个**普通可变对象**而不是 Notifier/StateProvider：它的每一次变化都只是
/// 「记下用户滚到哪了」，滚动时的每一帧都会写它。做成可被 watch 的状态意味着每帧触发
/// 一次列表重建——那是一个自找的抖动，而且与「锚点」这件事本身无关（没有任何界面需要
/// 对它的变化作出反应，它只在列表被重建的那一刻被读一次）。
final class ArticleListScrollAnchor {
  /// 最后已知的滚动偏移（逻辑像素）。
  double offset = 0;
}

/// 滚动锚点的 Provider（随容器存活）。
final Provider<ArticleListScrollAnchor> articleListScrollAnchorProvider =
    Provider<ArticleListScrollAnchor>((Ref ref) => ArticleListScrollAnchor());
