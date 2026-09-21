// T035 分段翻译测试的替身（端口级，不联网）。
library;

import 'package:flux/core/core.dart';
import 'package:flux/features/ai/domain/ai_task_record.dart';
import 'package:flux/features/ai/domain/ai_task_store.dart';

/// 段落级结果缓存替身。
///
/// 与 T034 的 FakeResultCache 同一做法（按任意键命中），但这里额外记录**被查询的键**：
/// 翻译的验收要证明「段落级缓存键」确实按段落文本区分，因此需要看到键的集合。
final class FakeTranslationCache implements AiResultCache {
  /// 键 → 文本。
  final Map<String, String> entries = <String, String>{};

  /// 被查询过的键（按顺序）。
  final List<String> queried = <String>[];

  /// 被写入的键（按顺序）。
  final List<String> written = <String>[];

  /// 让所有查询都命中同一段文本（验证「命中时不发请求」）。
  String? hitAll;

  /// 预置一条命中。
  void seed(String key, String text) => entries[key] = text;

  @override
  Future<Result<AiResultCacheEntry?>> find(String key) async {
    queried.add(key);
    final String? text = entries[key] ?? hitAll;
    if (text == null) {
      return const Ok<AiResultCacheEntry?>(null);
    }
    return Ok<AiResultCacheEntry?>(
      AiResultCacheEntry(
        key: key,
        text: text,
        providerAlias: 'main',
        modelId: 'main-model',
        createdAt: DateTime.utc(2026, 9, 22),
      ),
    );
  }

  @override
  Future<Result<void>> save(AiResultCacheEntry entry) async {
    written.add(entry.key);
    entries[entry.key] = entry.text;
    return okUnit();
  }

  @override
  Future<Result<void>> delete(String key) async {
    entries.remove(key);
    return okUnit();
  }

  @override
  Future<Result<void>> clear() async {
    entries.clear();
    return okUnit();
  }
}

/// 译文存储替身：只记录写入，读按 `seed` 返回。
final class FakeTranslationStore implements ArticleTranslationStore {
  /// 已写入的译文（按写入顺序）。
  final List<ArticleTranslation> saved = <ArticleTranslation>[];

  /// 预置的读取结果（按「文章 + 语言」）。
  final Map<String, ArticleTranslation> seeded = <String, ArticleTranslation>{};

  /// 写入是否失败（验证不谎报保存）。
  bool failSave = false;

  /// 键（与实现同一口径：文章 + 语言）。
  static String keyOf(int articleId, String language) => '$articleId|$language';

  /// 预置一份译文。
  void seed(ArticleTranslation translation) =>
      seeded[keyOf(translation.articleId, translation.targetLanguage)] =
          translation;

  @override
  Future<Result<ArticleTranslation?>> find({
    required int articleId,
    required String targetLanguage,
  }) async => Ok<ArticleTranslation?>(seeded[keyOf(articleId, targetLanguage)]);

  @override
  Future<Result<ArticleTranslation>> save(
    ArticleTranslation translation,
  ) async {
    if (failSave) {
      return Err<ArticleTranslation>(
        StorageError(operation: 'translation.save', detail: 'fixture'),
      );
    }
    saved.add(translation);
    seeded[keyOf(translation.articleId, translation.targetLanguage)] =
        translation;
    return Ok<ArticleTranslation>(translation);
  }

  @override
  Future<Result<void>> deleteAll(int articleId) async => okUnit();
}
