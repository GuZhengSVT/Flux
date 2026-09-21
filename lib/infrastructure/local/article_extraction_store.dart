// 提取正文的数据层（T024）。
//
// 只做一件事：把**已抽取好的**正文写进 articles 的提取列、或读出来。抽取本身是
// features/articles/domain 的纯函数，抓取是 infrastructure/network——三者分开之后，
// 「这个字段谁写」在类型层面就是确定的。
//
// 三条刻意的实现选择：
//   1) 写入**只改提取列**（extracted_* 五列 + updated_at），绝不触碰 body/body_hash/
//      reading_state/favorite。阅读状态不变是 T024 的明确要求：获取全文不是一次阅读事件；
//   2) 哈希未变时**不重写大字段**（与导入路径同一口径）：再次点「获取原站全文」而内容
//      没变时，不做一次无意义的整段文本写入；
//   3) 读取按需返回整段正文：提取正文与源正文一样是大字段，列表页不该把它读进内存。
library;

import 'package:drift/drift.dart';

import 'package:flux/core/core.dart';

import 'database.dart';

/// 提取正文的数据层。
final class DriftArticleExtractionStore implements ArticleExtractionStore {
  /// 绑定一个已打开的数据库。
  const DriftArticleExtractionStore(this._db);

  final AppDatabase _db;

  @override
  Future<Result<ExtractedArticleBody?>> readExtraction(int articleId) async {
    try {
      final Article? row =
          await (_db.select(_db.articles)
                ..where(($ArticlesTable t) => t.id.equals(articleId))
                ..limit(1))
              .getSingleOrNull();
      if (row == null) {
        return const Ok<ExtractedArticleBody?>(null);
      }
      final String? body = row.extractedBody;
      if (body == null || body.isEmpty || row.extractedAt == null) {
        // 正文或时间缺一即视为「没有提取过」：只有正文没有时间，界面无法说明它是
        // 什么时候取的；只有时间没有正文，那是一行没有内容可显示的记录。
        return const Ok<ExtractedArticleBody?>(null);
      }
      return Ok<ExtractedArticleBody?>(
        ExtractedArticleBody(
          body: body,
          bodyHash: row.extractedBodyHash ?? '',
          title: row.extractedTitle ?? '',
          imageUrls: _splitUrls(row.extractedImageUrls),
          extractedAt: row.extractedAt!,
        ),
      );
    } on Exception catch (error, stackTrace) {
      return Err<ExtractedArticleBody?>(
        StorageError(
          operation: 'readExtraction',
          detail: error.runtimeType.toString(),
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  @override
  Future<Result<void>> saveExtraction({
    required int articleId,
    required ExtractedArticleBody extraction,
  }) async {
    try {
      final Article? existing =
          await (_db.select(_db.articles)
                ..where(($ArticlesTable t) => t.id.equals(articleId))
                ..limit(1))
              .getSingleOrNull();
      if (existing == null) {
        return Err<void>(
          StorageError(
            operation: 'saveExtraction',
            detail: '文章 $articleId 不存在',
            isMissing: true,
          ),
        );
      }
      // 内容未变时不重写大字段，但仍然更新时间：用户确实又点了一次，
      // 「什么时候检查过」这个事实值得记录（与导入路径的「无变化不写」不同——那里是
      // 自动流程，没有人点过）。
      final bool bodyChanged =
          existing.extractedBodyHash != extraction.bodyHash;
      await (_db.update(
        _db.articles,
      )..where(($ArticlesTable t) => t.id.equals(articleId))).write(
        ArticlesCompanion(
          extractedBody: bodyChanged
              ? Value<String?>(extraction.body)
              : const Value<String?>.absent(),
          // 正文与哈希**必须一起更新**：只更新一个会让下一次比较用错误的基准，
          // 于是要么再也检测不到变化，要么界面显示的是与哈希不符的旧文本。
          extractedBodyHash: bodyChanged
              ? Value<String?>(extraction.bodyHash)
              : const Value<String?>.absent(),
          extractedTitle: Value<String?>(
            extraction.title.isEmpty ? null : extraction.title,
          ),
          extractedImageUrls: Value<String?>(
            extraction.imageUrls.isEmpty
                ? null
                : extraction.imageUrls.join('\n'),
          ),
          extractedAt: Value<DateTime?>(extraction.extractedAt),
          updatedAt: Value<DateTime>(DateTime.now().toUtc()),
        ),
      );
      return const Ok<void>(null);
    } on Exception catch (error, stackTrace) {
      return Err<void>(
        StorageError(
          operation: 'saveExtraction',
          detail: error.runtimeType.toString(),
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  @override
  Future<Result<void>> clearExtraction(int articleId) async {
    try {
      await (_db.update(
        _db.articles,
      )..where(($ArticlesTable t) => t.id.equals(articleId))).write(
        const ArticlesCompanion(
          extractedBody: Value<String?>(null),
          extractedBodyHash: Value<String?>(null),
          extractedTitle: Value<String?>(null),
          extractedImageUrls: Value<String?>(null),
          extractedAt: Value<DateTime?>(null),
        ),
      );
      return const Ok<void>(null);
    } on Exception catch (error, stackTrace) {
      return Err<void>(
        StorageError(
          operation: 'clearExtraction',
          detail: error.runtimeType.toString(),
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  /// 图片地址列表的存储形态：每行一个。
  static List<String> _splitUrls(String? raw) {
    if (raw == null || raw.isEmpty) {
      return const <String>[];
    }
    return raw.split('\n').where((String s) => s.isNotEmpty).toList();
  }
}
