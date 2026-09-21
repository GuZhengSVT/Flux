// 分段翻译的 SQLite 实现（T035；端口在 core/domain/article_translation.dart）。
//
// 「原文始终保留」在这里是**结构性**的：本文件没有任何一处写 articles 的列——译文只写
// article_translation_records 与 translation_segment_records 两张表。即使调用方传进来一份
// 与正文不符的段落集，源正文列也不会被触碰。
//
// 写入是一整个**事务**（删旧段落 + 写新段落 + 更新译文行）：分步写会在中途失败时留下
// 「译文行说完成，段落却缺了几条」这种自相矛盾的状态，而界面上表现为「进度 5/8 但点重试
// 没有失败段可重试」——一个无法解释的卡死。事务让读到的永远是某一个完整版本。
library;

import 'package:drift/drift.dart';

import 'package:flux/core/core.dart';

import 'database.dart';
import 'tables/translation_tables.dart';

/// drift 实现。
final class DriftArticleTranslationStore implements ArticleTranslationStore {
  /// 绑定一个已打开的数据库。
  const DriftArticleTranslationStore(this._db);

  final AppDatabase _db;

  @override
  Future<Result<ArticleTranslation?>> find({
    required int articleId,
    required String targetLanguage,
  }) async {
    try {
      final ArticleTranslationRecord? row =
          await (_db.select(_db.articleTranslationRecords)
                ..where(
                  (ArticleTranslationRecords t) =>
                      t.articleId.equals(articleId) &
                      t.targetLanguage.equals(targetLanguage),
                )
                ..limit(1))
              .getSingleOrNull();
      if (row == null) {
        return const Ok<ArticleTranslation?>(null);
      }
      final List<TranslationSegmentRecord> segmentRows =
          await (_db.select(_db.translationSegmentRecords)
                ..where(
                  (TranslationSegmentRecords t) =>
                      t.translationId.equals(row.id),
                )
                ..orderBy(<OrderClauseGenerator<TranslationSegmentRecords>>[
                  (TranslationSegmentRecords t) =>
                      OrderingTerm.asc(t.segmentIndex),
                ]))
              .get();
      return Ok<ArticleTranslation?>(
        _toDomain(row, segmentRows.map(_toDomainSegment).toList()),
      );
    } on Exception catch (error, stackTrace) {
      return Err<ArticleTranslation?>(
        _storage('translation.find', error, stackTrace),
      );
    }
  }

  @override
  Future<Result<ArticleTranslation>> save(
    ArticleTranslation translation,
  ) async {
    try {
      final ArticleTranslation saved = await _db.transaction(() async {
        // 先把这一段的目标行找出来（或建出来），再整体替换它的段落。
        final ArticleTranslationRecord? existing =
            await (_db.select(_db.articleTranslationRecords)
                  ..where(
                    (ArticleTranslationRecords t) =>
                        t.articleId.equals(translation.articleId) &
                        t.targetLanguage.equals(translation.targetLanguage),
                  )
                  ..limit(1))
                .getSingleOrNull();
        final DateTime now = DateTime.now().toUtc();
        final int id;
        if (existing == null) {
          id = await _db
              .into(_db.articleTranslationRecords)
              .insert(
                ArticleTranslationRecordsCompanion.insert(
                  articleId: translation.articleId,
                  targetLanguage: translation.targetLanguage,
                  sourceDigest: translation.sourceDigest,
                  sourceLength: Value<int>(translation.sourceLength),
                  modelLabel: Value<String?>(translation.modelLabel),
                  createdAt: Value<DateTime>(translation.createdAt ?? now),
                  updatedAt: Value<DateTime>(now),
                ),
              );
        } else {
          id = existing.id;
          await (_db.update(
            _db.articleTranslationRecords,
          )..where((ArticleTranslationRecords t) => t.id.equals(id))).write(
            ArticleTranslationRecordsCompanion(
              sourceDigest: Value<String>(translation.sourceDigest),
              sourceLength: Value<int>(translation.sourceLength),
              modelLabel: Value<String?>(translation.modelLabel),
              updatedAt: Value<DateTime>(now),
            ),
          );
        }
        // 段落整体替换：逐条 update 会留下「上一次留下的多余段落」——正文变短时
        // 那些段落仍然存在，并按旧顺序回填到新正文的段上。
        await (_db.delete(_db.translationSegmentRecords)..where(
              (TranslationSegmentRecords t) => t.translationId.equals(id),
            ))
            .go();
        for (final TranslationSegment segment in translation.segments) {
          await _db
              .into(_db.translationSegmentRecords)
              .insert(
                TranslationSegmentRecordsCompanion.insert(
                  translationId: id,
                  segmentIndex: segment.index,
                  blockKind: segment.kind.name,
                  level: Value<int>(segment.level),
                  sourceDigest: segment.sourceDigest,
                  sourceText: segment.sourceText,
                  status: segment.status.name,
                  translatedText: Value<String?>(segment.translatedText),
                  sourceTruncated: Value<bool>(segment.sourceTruncated),
                  updatedAt: Value<DateTime>(now),
                ),
              );
        }
        return ArticleTranslation(
          id: id,
          articleId: translation.articleId,
          targetLanguage: translation.targetLanguage,
          sourceDigest: translation.sourceDigest,
          sourceLength: translation.sourceLength,
          segments: translation.segments,
          modelLabel: translation.modelLabel,
          createdAt: existing?.createdAt ?? translation.createdAt ?? now,
          updatedAt: now,
        );
      });
      return Ok<ArticleTranslation>(saved);
    } on Exception catch (error, stackTrace) {
      return Err<ArticleTranslation>(
        _storage('translation.save', error, stackTrace),
      );
    }
  }

  @override
  Future<Result<void>> deleteAll(int articleId) async {
    try {
      final List<ArticleTranslationRecord> rows =
          await (_db.select(_db.articleTranslationRecords)..where(
                (ArticleTranslationRecords t) => t.articleId.equals(articleId),
              ))
              .get();
      for (final ArticleTranslationRecord row in rows) {
        // 段落由外键 CASCADE 清理；这里显式删父行即可（与 v13 的 onDelete 一致）。
        await (_db.delete(
          _db.articleTranslationRecords,
        )..where((ArticleTranslationRecords t) => t.id.equals(row.id))).go();
      }
      return okUnit();
    } on Exception catch (error, stackTrace) {
      return Err<void>(_storage('translation.deleteAll', error, stackTrace));
    }
  }

  static ArticleTranslation _toDomain(
    ArticleTranslationRecord row,
    List<TranslationSegment> segments,
  ) => ArticleTranslation(
    id: row.id,
    articleId: row.articleId,
    targetLanguage: row.targetLanguage,
    sourceDigest: row.sourceDigest,
    sourceLength: row.sourceLength,
    segments: segments,
    modelLabel: row.modelLabel,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
  );

  static TranslationSegment _toDomainSegment(TranslationSegmentRecord row) =>
      TranslationSegment(
        index: row.segmentIndex,
        kind: _kindFrom(row.blockKind),
        level: row.level,
        sourceDigest: row.sourceDigest,
        sourceText: row.sourceText,
        status: _statusFrom(row.status),
        translatedText: row.translatedText,
        sourceTruncated: row.sourceTruncated,
      );

  /// 未知角色按「段落」处理（旧版本写下的新角色）：宁可把它当普通段落渲染，也不要
  /// 让整份译文因为一个无法识别的枚举值而读不出来。
  static TranslationBlockKind _kindFrom(String name) {
    for (final TranslationBlockKind kind in TranslationBlockKind.values) {
      if (kind.name == name) {
        return kind;
      }
    }
    return TranslationBlockKind.paragraph;
  }

  /// 未知状态按 failed 处理：**不**按 pending 或 translated 处理。
  ///
  /// 两个方向的错误后果不对称：按 pending 会让界面显示「未完成」并允许重试（安全），
  /// 但按 translated 且没有译文文本时界面会显示一段空白——看起来像模型返回了空结果；
  /// 而 failed 是明确可解释的（「这一段需要重试」），且**不会**把坏状态当成成功。
  static TranslationSegmentStatus _statusFrom(String name) {
    for (final TranslationSegmentStatus status
        in TranslationSegmentStatus.values) {
      if (status.name == name) {
        return status;
      }
    }
    return TranslationSegmentStatus.failed;
  }

  static StorageError _storage(
    String operation,
    Object error,
    StackTrace stackTrace,
  ) => StorageError(
    operation: operation,
    detail: error.runtimeType.toString(),
    cause: error,
    stackTrace: stackTrace,
  );
}

/// 数据库不可用时的译文端口（T035 的降级启动路径）。
///
/// 与非降级实现同一个口径：**读返回 Ok(null)**（本次运行确实没有可读的译文），
/// **写明确失败**（不假装保存成功）。读返回 null 而不是抛错，是因为「没有译文」在降级
/// 模式下是一个真实答案——界面上表现为「还没有译文，且这一版翻译不会保存」。
final class DegradedArticleTranslationStore implements ArticleTranslationStore {
  /// 构造降级实现。
  const DegradedArticleTranslationStore();

  @override
  Future<Result<ArticleTranslation?>> find({
    required int articleId,
    required String targetLanguage,
  }) async => const Ok<ArticleTranslation?>(null);

  @override
  Future<Result<ArticleTranslation>> save(
    ArticleTranslation translation,
  ) async => Err<ArticleTranslation>(
    StorageError(operation: 'translation.save', detail: '本次运行数据库不可用，译文不会保存'),
  );

  @override
  Future<Result<void>> deleteAll(int articleId) async => Err<void>(
    StorageError(operation: 'translation.deleteAll', detail: '本次运行数据库不可用'),
  );
}
