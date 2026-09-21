// 文章导入事务（T009 数据层；业务/网络流程见 T013）。
//
// 本文件只做**数据层**的幂等写入：给定已解析好的文章，按身份规则匹配并合并，
// 保留用户已产生的阅读状态与收藏。它不下载、不解析、不判定正文完整性，
// 也不做调度——那些属于 T013/T016。
//
// 幂等语义（架构 4.1）：
//   - 身份：同 Feed 内按 GUID → 规范化链接 → 来源/标题/时间指纹依次匹配；
//   - 重复导入不新增行，只更新内容字段；
//   - 正文只在**正文哈希变化**时更新（正文哈希只判修订，不判身份）；
//   - readingState 与 favorite 永不被导入覆盖（later 不会被刷成 unread）。
library;

import 'package:drift/drift.dart';

import 'package:flux/core/core.dart';

import 'database.dart';
import 'tables/article_tables.dart';

// 导入 DTO（ArticleImport / ArticleImportOutcome）自 T012 起定义在
// lib/core/domain/article_import.dart：解析层（features）要产出它们，而 features
// 不得 import infrastructure。这里不再重复声明，避免出现两份形状接近的定义。

/// 文章数据层操作。
extension ArticleStore on AppDatabase {
  /// 幂等批量导入：整个批次在**单个事务**内完成，任一条失败则整批回滚。
  ///
  /// 返回 [Result]，使导入流程无需捕获底层异常：数据库错误统一成为
  /// [StorageError]（架构 2.2、T007 错误体系）。
  Future<Result<ArticleImportOutcome>> upsertArticles(
    List<ArticleImport> imports,
  ) async {
    try {
      final ArticleImportOutcome outcome = await transaction(() async {
        int inserted = 0;
        int updated = 0;
        int bodyUpdated = 0;
        int unchanged = 0;

        for (final ArticleImport incoming in imports) {
          final Article? existing = await _findByIdentity(incoming);

          if (existing == null) {
            await into(articles).insert(_toCompanion(incoming));
            inserted++;
            continue;
          }

          // 正文替换条件：本次解析**确实带了正文与新哈希**，且哈希与库里不同。
          // 两个刻意的保守选择：
          //   - incoming.bodyHash 为 null 时不动正文，避免“解析失败/只有摘要”
          //     的刷新把已存全文擦成空；
          //   - 哈希相同即视为同一修订，不重写大字段。
          final bool bodyChanged =
              incoming.bodyHash != null &&
              incoming.bodyHash != existing.bodyHash;

          final ArticlesCompanion patch = ArticlesCompanion(
            title: Value<String>(incoming.title),
            author: Value<String?>(incoming.author),
            publishedAt: Value<DateTime?>(incoming.publishedAt),
            fetchedAt: Value<DateTime>(
              incoming.fetchedAt ?? DateTime.now().toUtc(),
            ),
            summary: Value<String?>(incoming.summary),
            bodyCompleteness: Value<BodyCompleteness>(
              incoming.bodyCompleteness,
            ),
            // 链接与兜底指纹可能在后续抓取中才拿到，补齐空缺但不覆盖已有值。
            normalizedLink: Value<String?>(
              existing.normalizedLink ?? incoming.normalizedLink,
            ),
            sourceUrl: Value<String?>(existing.sourceUrl ?? incoming.sourceUrl),
            guid: Value<String?>(existing.guid ?? incoming.guid),
            guidPresent: Value<bool>(
              existing.guidPresent || incoming.guidPresent,
            ),
            fallbackFingerprint: Value<String?>(
              existing.fallbackFingerprint ?? incoming.fallbackFingerprint,
            ),
            fingerprintReliability: Value<FingerprintReliability?>(
              existing.fingerprintReliability ??
                  incoming.fingerprintReliability,
            ),
            body: bodyChanged
                ? Value<String?>(incoming.body)
                : const Value.absent(),
            bodyHash: bodyChanged
                ? Value<String?>(incoming.bodyHash)
                : const Value.absent(),
            updatedAt: Value<DateTime>(DateTime.now().toUtc()),
            // readingState / favorite / createdAt / id 有意不出现在补丁里：
            // 导入不得改变用户状态（later 打开后仍为 later 的数据基础）。
          );

          // 真正落库前先判断是否**确有内容变化**；完全相同就不写、也不推进
          // updatedAt，使“同一份 feed 反复导入”在数据上可证明是幂等的。
          if (!_hasContentChange(
            existing,
            incoming,
            bodyChanged: bodyChanged,
          )) {
            unchanged++;
            continue;
          }

          await (update(
            articles,
          )..where((Articles t) => t.id.equals(existing.id))).write(patch);

          if (bodyChanged) {
            bodyUpdated++;
          }
          updated++;
        }

        return ArticleImportOutcome(
          inserted: inserted,
          updated: updated,
          bodyUpdated: bodyUpdated,
          unchanged: unchanged,
        );
      });

      return Ok<ArticleImportOutcome>(outcome);
    } on AppError catch (error, stackTrace) {
      return Err<ArticleImportOutcome>(
        error is StorageError
            ? error
            : StorageError(
                operation: 'upsertArticles',
                detail: error.message,
                cause: error,
                stackTrace: stackTrace,
              ),
      );
    } on Exception catch (error, stackTrace) {
      return Err<ArticleImportOutcome>(
        StorageError(
          operation: 'upsertArticles',
          detail: error.runtimeType.toString(),
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  /// 比较“导入内容”与“已有行”是否产生了需要写入的差异。
  ///
  /// 有意**不**比较：readingState、favorite、createdAt、id（导入无权改动），
  /// 以及 updatedAt（它是写入结果而非内容）。这样重复导入同一份 feed 时
  /// 判定为无变化，不产生多余写入。
  static bool _hasContentChange(
    Article existing,
    ArticleImport incoming, {
    required bool bodyChanged,
  }) {
    if (bodyChanged) {
      return true;
    }

    if (existing.title != incoming.title ||
        existing.author != incoming.author ||
        existing.publishedAt != incoming.publishedAt ||
        existing.summary != incoming.summary ||
        existing.bodyCompleteness != incoming.bodyCompleteness ||
        existing.identityBasis != incoming.identityBasis) {
      return true;
    }

    // 这些字段只在“原本为空”时才会被补上，因此仅当已有值为空而导入有值才算变化。
    if (existing.normalizedLink == null && incoming.normalizedLink != null) {
      return true;
    }
    if (existing.sourceUrl == null && incoming.sourceUrl != null) {
      return true;
    }
    if (existing.guid == null && incoming.guid != null) {
      return true;
    }
    if (!existing.guidPresent && incoming.guidPresent) {
      return true;
    }
    if (existing.fallbackFingerprint == null &&
        incoming.fallbackFingerprint != null) {
      return true;
    }
    if (existing.fingerprintReliability == null &&
        incoming.fingerprintReliability != null) {
      return true;
    }

    return false;
  }

  /// 按架构 4.1 的顺序查找已有文章：GUID → 规范化链接 → 兜底指纹。
  ///
  /// 只使用**本行实际提供**的标识，避免用空值参与匹配而把不相关文章并到一起。
  Future<Article?> _findByIdentity(ArticleImport incoming) async {
    final String? guid = incoming.guidPresent ? incoming.guid : null;

    if (guid != null && guid.isNotEmpty) {
      final Article? byGuid =
          await (select(articles)
                ..where(
                  (Articles t) =>
                      t.feedId.equals(incoming.feedId) & t.guid.equals(guid),
                )
                ..limit(1))
              .getSingleOrNull();
      if (byGuid != null) {
        return byGuid;
      }
    }

    final String? link = incoming.normalizedLink;
    if (link != null && link.isNotEmpty) {
      final Article? byLink =
          await (select(articles)
                ..where(
                  (Articles t) =>
                      t.feedId.equals(incoming.feedId) &
                      t.normalizedLink.equals(link),
                )
                ..limit(1))
              .getSingleOrNull();
      if (byLink != null) {
        return byLink;
      }
    }

    final String? fingerprint = incoming.fallbackFingerprint;
    if (fingerprint != null && fingerprint.isNotEmpty) {
      return (select(articles)
            ..where(
              (Articles t) =>
                  t.feedId.equals(incoming.feedId) &
                  t.fallbackFingerprint.equals(fingerprint),
            )
            ..limit(1))
          .getSingleOrNull();
    }

    return null;
  }

  /// 构造新增行；阅读状态与收藏使用默认值（unread / false）。
  ArticlesCompanion _toCompanion(ArticleImport incoming) {
    return ArticlesCompanion.insert(
      feedId: incoming.feedId,
      title: incoming.title,
      identityBasis: incoming.identityBasis,
      guid: Value<String?>(incoming.guid),
      guidPresent: Value<bool>(incoming.guidPresent),
      normalizedLink: Value<String?>(incoming.normalizedLink),
      sourceUrl: Value<String?>(incoming.sourceUrl),
      fallbackFingerprint: Value<String?>(incoming.fallbackFingerprint),
      fingerprintReliability: Value<FingerprintReliability?>(
        incoming.fingerprintReliability,
      ),
      author: Value<String?>(incoming.author),
      publishedAt: Value<DateTime?>(incoming.publishedAt),
      fetchedAt: Value<DateTime>(incoming.fetchedAt ?? DateTime.now().toUtc()),
      body: Value<String?>(incoming.body),
      bodyCompleteness: Value<BodyCompleteness>(incoming.bodyCompleteness),
      bodyHash: Value<String?>(incoming.bodyHash),
      summary: Value<String?>(incoming.summary),
      readingState: const Value<ReadingState>(ReadingState.unread),
    );
  }
}
