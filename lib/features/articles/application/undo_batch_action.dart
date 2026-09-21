// 批量操作的撤销（T017；架构第 7 节「危险操作显示影响和可用撤销」）。
//
// 为什么撤销必须是**按快照逐行恢复**而不是「反向执行一次批量操作」：
//   批量操作把一批可能混合着 unread/read/later 与收藏/未收藏的文章设成同一个值。
//   反向执行只能把整批再设成另一个**统一值**，那不是「回到操作之前」——用户看到的
//   会是「撤销之后我的收藏全没了」或「later 全变成未读」。因此 [BatchActionReport]
//   在写入前先取快照，撤销把每一行恢复成它当时的具体值。
//
// 为什么撤销只做一次（不可重做）：一次撤销之后，操作前的状态就是当前状态，再撤销
// 同一个句柄只会把同样的值再写一遍。重做属于编辑历史，本项目没有那个需求。
library;

import 'package:flux/core/core.dart';

import 'batch_article_actions.dart';

/// 撤销一次批量操作。
final class UndoBatchActionUseCase {
  /// 构造用例。
  const UndoBatchActionUseCase({
    required this.articles,
    this.diagnostics = const NoopDiagnosticSink(),
  });

  /// 文章端口。
  final ArticleCatalogStore articles;

  /// 诊断记录。
  final DiagnosticSink diagnostics;

  /// 按句柄恢复。
  ///
  /// 返回**实际恢复成功的行数**：界面据此说明「已撤销」而不是无条件宣称撤销成功
  /// （快照里的文章可能已被删除，例如 T018 的清理）。
  Future<Result<int>> call(BatchUndoHandle handle) async {
    if (handle.snapshots.isEmpty) {
      // 没有快照就没有可恢复的内容。这里返回 0 而不是错误：调用方可能是对一次
      // 「空范围」操作点了撤销（那种操作本来就没有改动过任何行）。
      return const Ok<int>(0);
    }
    final Result<int> restored = await articles.restoreArticleStates(
      handle.snapshots,
    );
    if (restored.isErr) {
      return Err<int>(restored.errorOrNull!);
    }
    final int count = restored.valueOrNull ?? 0;
    if (count == 0) {
      // 一行都没恢复：那批文章已经不在了。如实报告，而不是让界面显示「已撤销」。
      return Err<int>(
        StorageError(
          operation: 'undoBatchAction',
          detail: '快照里的文章已不存在，无法撤销',
          isMissing: true,
        ),
      );
    }
    diagnostics.info(
      '撤销批量操作「${handle.label}」：恢复 $count 篇',
      tag: 'article.batch.undo',
    );
    return Ok<int>(count);
  }
}
