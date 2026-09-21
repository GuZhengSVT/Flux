// 目录与邻篇快照（T019；架构 4.1「上下篇基于进入详情时的筛选/排序快照」）。
//
// 目录只取 h1–h3：架构第 7 节把「目录（h1-h3 提取侧栏，桌面宽窗显示）」写成产品口径。
// h4 及以下不进目录——它们会让侧栏变成一份重复的正文缩略，而读者用它是为了跳转，不是
// 为了看结构有多深。
//
// 邻篇快照在**打开详情那一刻**固定：用户进入阅读后可能改筛选（虽然此时他在另一页），
// 也可能有后台刷新插入新文章。若上下篇每次都按当前筛选重算，读者点「下一篇」可能落到一篇
// 与进来时完全无关的文章上——那是「返回锚点」这类功能最典型的失败形态。
library;

import 'package:flux/core/core.dart';

/// 目录里的一项。
class ReaderOutlineEntry {
  /// 构造目录项。
  const ReaderOutlineEntry({
    required this.level,
    required this.label,
    required this.blockIndex,
  });

  /// 标题层级（1–3）。
  final int level;

  /// 标题文字。
  final String label;

  /// 在文档顶层块里的下标（跳转锚点用）。
  final int blockIndex;

  @override
  String toString() => 'ReaderOutlineEntry(L$level, "$label", #$blockIndex)';
}

/// 从文档里提取目录（h1–h3，按文档顺序）。
List<ReaderOutlineEntry> extractOutline(DocDocument document) {
  final List<ReaderOutlineEntry> out = <ReaderOutlineEntry>[];
  for (int i = 0; i < document.children.length; i++) {
    final DocNode node = document.children[i];
    if (node is! DocHeading || node.level > 3) {
      continue;
    }
    final String label = docInlinePlainText(node.children).trim();
    if (label.isEmpty) {
      // 空标题不进目录：一个点不动也看不见的条目会让人以为目录坏了。
      continue;
    }
    out.add(ReaderOutlineEntry(level: node.level, label: label, blockIndex: i));
  }
  return out;
}

/// 打开详情时的阅读快照：当前筛选下的文章顺序与所在位置。
class ReaderSnapshot {
  /// 构造快照。
  const ReaderSnapshot({
    required this.orderedIds,
    required this.index,
    required this.filter,
    required this.feedId,
  });

  /// 进入详情时的筛选结果顺序（本机 id）。
  final List<int> orderedIds;

  /// 当前文章在该顺序里的下标；不在其中时为 -1。
  final int index;

  /// 进入时的筛选（界面据此说明「上一篇/下一篇依据什么」）。
  final ArticleFilter filter;

  /// 进入时的来源限定。
  final int? feedId;

  /// 上一篇的 id；已是第一篇时为 null。
  int? get previousId =>
      index > 0 && index <= orderedIds.length ? orderedIds[index - 1] : null;

  /// 下一篇的 id；已是最后一篇时为 null。
  int? get nextId => index >= 0 && index + 1 < orderedIds.length
      ? orderedIds[index + 1]
      : null;

  /// 在有边界的快照里能否向前。
  bool get hasPrevious => previousId != null;

  /// 在有边界的快照里能否向后。
  bool get hasNext => nextId != null;
}
