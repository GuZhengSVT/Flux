// 阅读状态与收藏的用例（T017；架构 4.1、手册 6.3）。
//
// 三个用例，各自把一条产品规则变成**用例层**的可验证行为（数据库 CHECK 是最后一层
// 保险，不是唯一一层）：
//
//   1) SetReadingStateUseCase：三值互斥。数据库的 CHECK 会拒绝非法取值，但非法
//      取值在到达数据库之前就会先成为一个「类型化失败」——因为本用例接受的是
//      ReadingState 枚举，构造一个非法值在**编译期**就不可能。这里额外做的是
//      「写入前先确认文章存在」：对一条已删除的文章报告成功，会让界面显示一个
//      并不存在的状态。
//
//   2) ToggleFavoriteUseCase：收藏独立。它**只**改 favorite，不接受阅读状态参数
//      ——接口形状上就拿不到三态，因此不可能「顺手」改掉（架构 4.1：
//      「收藏 favorite 独立，不改变阅读状态」）。
//
//   3) MarkReadOnOpenUseCase：SET-010 的自动标已读。规则有三条，都在这里：
//        - SET-010 关闭 → 什么都不做；
//        - 当前是 unread → read；
//        - 当前是 read 或 **later → 不动**（later 打开后仍为 later，用户点
//          「标为已读」才变 read）。
//      实现走存储的**条件写** ArticleCatalogStore.markReadIfUnread，因此即使在
//      「读出状态」与「写入」之间有并发修改，也不会把 later 改成 read。
//
// 为什么这些放在 features/articles 而不是 feeds：它们操作的是**文章**（列表与阅读），
// 而订阅（feeds）负责抓取与来源。跨模块共享的接口与 DTO 在 core（见
// core/domain/article_catalog.dart），这里只放业务规则。
library;

import 'package:flux/core/core.dart';

/// 一次状态写入的结果。
class ArticleStateChange {
  /// 构造结果。
  const ArticleStateChange({
    required this.articleId,
    required this.changed,
    this.error,
  });

  /// 文章 id。
  final int articleId;

  /// 是否确实产生了写入（false 可能因为文章不存在、或状态本就相同）。
  final bool changed;

  /// 失败原因；成功时为 null。
  final AppError? error;

  /// 是否成功（含「无需改动」）。
  bool get succeeded => error == null;
}

/// 设置阅读状态（三态之一）。
///
/// 参数类型是 [ReadingState] 而不是字符串：非法值在编译期就不可能被传入。
/// 存储层的 CHECK 约束是第二道（防的是别的写入路径与手工改库），不是唯一一道。
final class SetReadingStateUseCase {
  /// 构造用例。
  const SetReadingStateUseCase({
    required this.articles,
    this.diagnostics = const NoopDiagnosticSink(),
  });

  /// 文章端口。
  final ArticleCatalogStore articles;

  /// 诊断记录。
  final DiagnosticSink diagnostics;

  /// 把一篇文章设为 ${state}。
  Future<Result<ArticleStateChange>> call({
    required int articleId,
    required ReadingState state,
  }) async {
    final Result<ArticleListEntry?> found = await articles.findArticle(
      articleId,
    );
    if (found.isErr) {
      return Err<ArticleStateChange>(found.errorOrNull!);
    }
    final ArticleListEntry? entry = found.valueOrNull;
    if (entry == null) {
      // 文章不存在时不报告成功：界面会据此显示一个并不存在的状态。
      return Err<ArticleStateChange>(
        StorageError(
          operation: 'setReadingState',
          detail: '文章 $articleId 不存在',
          isMissing: true,
        ),
      );
    }
    if (entry.readingState == state) {
      // 已经是目标状态：不写、不推进 updatedAt。「点了一下没反应」在这一层是
      // 正确行为——界面不需要因为一次无变化的点击而重绘或播报错误。
      return Ok<ArticleStateChange>(
        ArticleStateChange(articleId: articleId, changed: false),
      );
    }

    final Result<int> written = await articles.setReadingState(
      articleIds: <int>[articleId],
      state: state,
    );
    if (written.isErr) {
      return Err<ArticleStateChange>(written.errorOrNull!);
    }
    final int changedRows = written.valueOrNull ?? 0;
    if (changedRows == 0) {
      // 读取之后、写入之前文章被删掉了（T018 的删除、或同步落地）。
      // 如实报告失败，而不是把 0 行当成成功。
      return Err<ArticleStateChange>(
        StorageError(
          operation: 'setReadingState',
          detail: '文章 $articleId 在写入前已不存在',
          isMissing: true,
        ),
      );
    }
    diagnostics.info(
      '阅读状态改为 ${state.name}（文章 $articleId）',
      tag: 'article.state',
    );
    return Ok<ArticleStateChange>(
      ArticleStateChange(articleId: articleId, changed: true),
    );
  }
}

/// 切换/设置收藏。
///
/// 接口中**没有**阅读状态参数：收藏是独立布尔，本用例不可能改变三态
/// （架构 4.1「收藏独立，不改变阅读状态」）。
final class ToggleFavoriteUseCase {
  /// 构造用例。
  const ToggleFavoriteUseCase({
    required this.articles,
    this.diagnostics = const NoopDiagnosticSink(),
  });

  /// 文章端口。
  final ArticleCatalogStore articles;

  /// 诊断记录。
  final DiagnosticSink diagnostics;

  /// 显式设置收藏值。
  Future<Result<ArticleStateChange>> call({
    required int articleId,
    required bool favorite,
  }) async {
    final Result<ArticleListEntry?> found = await articles.findArticle(
      articleId,
    );
    if (found.isErr) {
      return Err<ArticleStateChange>(found.errorOrNull!);
    }
    if (found.valueOrNull == null) {
      return Err<ArticleStateChange>(
        StorageError(
          operation: 'toggleFavorite',
          detail: '文章 $articleId 不存在',
          isMissing: true,
        ),
      );
    }
    if (found.valueOrNull!.favorite == favorite) {
      return Ok<ArticleStateChange>(
        ArticleStateChange(articleId: articleId, changed: false),
      );
    }
    final Result<int> written = await articles.setFavorite(
      articleIds: <int>[articleId],
      favorite: favorite,
    );
    if (written.isErr) {
      return Err<ArticleStateChange>(written.errorOrNull!);
    }
    if ((written.valueOrNull ?? 0) == 0) {
      return Err<ArticleStateChange>(
        StorageError(
          operation: 'toggleFavorite',
          detail: '文章 $articleId 在写入前已不存在',
          isMissing: true,
        ),
      );
    }
    diagnostics.info(
      '${favorite ? '加入' : '取消'}收藏（文章 $articleId）',
      tag: 'article.favorite',
    );
    return Ok<ArticleStateChange>(
      ArticleStateChange(articleId: articleId, changed: true),
    );
  }

  /// 翻转当前值。
  Future<Result<ArticleStateChange>> toggle(int articleId) async {
    final Result<ArticleListEntry?> found = await articles.findArticle(
      articleId,
    );
    if (found.isErr) {
      return Err<ArticleStateChange>(found.errorOrNull!);
    }
    final ArticleListEntry? entry = found.valueOrNull;
    if (entry == null) {
      return Err<ArticleStateChange>(
        StorageError(
          operation: 'toggleFavorite',
          detail: '文章 $articleId 不存在',
          isMissing: true,
        ),
      );
    }
    return call(articleId: articleId, favorite: !entry.favorite);
  }
}

/// 打开正文时的自动标已读（SET-010）。
final class MarkReadOnOpenUseCase {
  /// 构造用例。
  const MarkReadOnOpenUseCase({
    required this.articles,
    this.diagnostics = const NoopDiagnosticSink(),
  });

  /// 文章端口。
  final ArticleCatalogStore articles;

  /// 诊断记录。
  final DiagnosticSink diagnostics;

  /// 按 SET-010 的规则处理「用户成功看到了正文」这件事。
  ///
  /// [autoMarkEnabled] 来自 SET-010。返回是否真的改动了状态——界面据此决定要不要
  /// 重读列表（改成 read 会让「未读」筛选里少掉一行）。
  Future<Result<ArticleStateChange>> call({
    required int articleId,
    required bool autoMarkEnabled,
  }) async {
    if (!autoMarkEnabled) {
      // SET-010 关闭：打开文章不改任何状态。这里**不预读**文章行，因此关闭状态下
      // 打开正文不会因为一次多余的查询而失败。
      return Ok<ArticleStateChange>(
        ArticleStateChange(articleId: articleId, changed: false),
      );
    }

    // 条件写：只有 unread 会被改成 read。later 与 read 都不受影响
    // （架构 4.1「later 打开后仍为 later」）。这里**不需要**先把文章读出来判断——
    // 那个判断在 SQL 条件里更可靠（见实现说明）。
    final Result<int> written = await articles.markReadIfUnread(articleId);
    if (written.isErr) {
      return Err<ArticleStateChange>(written.errorOrNull!);
    }
    final int changedRows = written.valueOrNull ?? 0;
    if (changedRows > 0) {
      diagnostics.info('打开正文自动标已读（文章 $articleId）', tag: 'article.state');
    }
    return Ok<ArticleStateChange>(
      ArticleStateChange(articleId: articleId, changed: changedRows > 0),
    );
  }
}
