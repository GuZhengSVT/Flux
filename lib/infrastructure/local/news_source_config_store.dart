// 新闻来源配置与版本化 prompt 的 SQLite 实现（T036；端口在 core/domain/news_config.dart）。
//
// 三条实现纪律：
//   * **列表读写是整体替换**：三个有序列表（关键词 / 禁词 / 主题）与必访站都按「用户给的
//     顺序整体写回」。逐条 update 会留下「删掉中间一项之后其余项的顺序出现空洞」的状态，
//     而唯一的 (kind, sort_order) 约束会让下一次写入撞上冲突；
//   * **类别未知时明确拒绝**：写入前校验类别（未知类别静默落到某一类会让两个列表互相污染）；
//   * **prompt 版本只增不改**：每次保存插入一行，版本号由调用方按现有最大值 +1 给出。
library;

import 'package:drift/drift.dart';

import 'package:flux/core/core.dart';

import 'database.dart';
import 'tables/news_tables.dart';

/// drift 实现。
final class DriftNewsSourceConfigStore implements NewsSourceConfigStore {
  /// 绑定一个已打开的数据库。
  const DriftNewsSourceConfigStore(this._db);

  final AppDatabase _db;

  // ---- 必访问网站（SET-051） ------------------------------------------------

  @override
  Future<Result<List<NewsRequiredSite>>> loadRequiredSites() async {
    try {
      final List<NewsRequiredSiteRecord> rows =
          await (_db.select(_db.newsRequiredSiteRecords)
                ..orderBy(<OrderClauseGenerator<NewsRequiredSiteRecords>>[
                  (NewsRequiredSiteRecords t) => OrderingTerm.asc(t.sortOrder),
                  (NewsRequiredSiteRecords t) => OrderingTerm.asc(t.id),
                ]))
              .get();
      return Ok<List<NewsRequiredSite>>(
        rows.map(_toSite).toList(growable: false),
      );
    } on Exception catch (error, stackTrace) {
      return Err<List<NewsRequiredSite>>(
        _storage('news.loadRequiredSites', error, stackTrace),
      );
    }
  }

  @override
  Future<Result<void>> replaceRequiredSites(
    List<NewsRequiredSite> sites,
  ) async {
    try {
      await _db.transaction(() async {
        await _db.delete(_db.newsRequiredSiteRecords).go();
        for (int index = 0; index < sites.length; index++) {
          final NewsRequiredSite site = sites[index];
          await _db
              .into(_db.newsRequiredSiteRecords)
              .insert(
                NewsRequiredSiteRecordsCompanion.insert(
                  name: site.name,
                  url: site.url,
                  enabled: Value<bool>(site.enabled),
                  // 顺序以**列表位置**为准：用户拖动后的顺序就是他要的顺序，
                  // 不接受调用方传一个与位置冲突的 sortOrder。
                  sortOrder: Value<int>(index),
                ),
              );
        }
      });
      return okUnit();
    } on Exception catch (error, stackTrace) {
      return Err<void>(
        _storage('news.replaceRequiredSites', error, stackTrace),
      );
    }
  }

  // ---- 三个有序字符串列表（SET-052/053） -----------------------------------

  @override
  Future<Result<List<String>>> loadList(String kind) async {
    final Result<List<NewsConfigEntryRecord>> rows = await _loadEntryRows(kind);
    if (rows.isErr) {
      return Err<List<String>>(rows.errorOrNull!);
    }
    return Ok<List<String>>(<String>[
      for (final NewsConfigEntryRecord row in rows.valueOrNull!) row.value,
    ]);
  }

  @override
  Future<Result<void>> replaceList(String kind, List<String> values) async {
    if (!NewsListCategory.isKnown(kind)) {
      return Err<void>(
        ValidationError(field: 'SET-053', reason: '未知的列表类别 $kind'),
      );
    }
    try {
      await _db.transaction(() async {
        await (_db.delete(
          _db.newsConfigEntryRecords,
        )..where((NewsConfigEntryRecords t) => t.kind.equals(kind))).go();
        for (int index = 0; index < values.length; index++) {
          await _db
              .into(_db.newsConfigEntryRecords)
              .insert(
                NewsConfigEntryRecordsCompanion.insert(
                  kind: kind,
                  value: values[index],
                  sortOrder: index,
                ),
              );
        }
      });
      return okUnit();
    } on Exception catch (error, stackTrace) {
      return Err<void>(_storage('news.replaceList', error, stackTrace));
    }
  }

  Future<Result<List<NewsConfigEntryRecord>>> _loadEntryRows(
    String kind,
  ) async {
    try {
      final List<NewsConfigEntryRecord> rows = await (_db.select(
        _db.newsConfigEntryRecords,
      )..where((NewsConfigEntryRecords t) => t.kind.equals(kind))).get();
      rows.sort((NewsConfigEntryRecord a, NewsConfigEntryRecord b) {
        final int byOrder = a.sortOrder.compareTo(b.sortOrder);
        return byOrder != 0 ? byOrder : a.id.compareTo(b.id);
      });
      return Ok<List<NewsConfigEntryRecord>>(rows);
    } on Exception catch (error, stackTrace) {
      return Err<List<NewsConfigEntryRecord>>(
        _storage('news.loadList', error, stackTrace),
      );
    }
  }

  // ---- prompt 版本（SET-055） ----------------------------------------------

  @override
  Future<Result<List<NewsPromptVersion>>> loadPromptVersions(
    String language,
  ) async {
    try {
      final List<NewsPromptVersionRecord> rows =
          await (_db.select(_db.newsPromptVersionRecords)..where(
                (NewsPromptVersionRecords t) => t.language.equals(language),
              ))
              .get();
      rows.sort(
        (NewsPromptVersionRecord a, NewsPromptVersionRecord b) =>
            b.version.compareTo(a.version),
      );
      return Ok<List<NewsPromptVersion>>(
        rows.map(_toVersion).toList(growable: false),
      );
    } on Exception catch (error, stackTrace) {
      return Err<List<NewsPromptVersion>>(
        _storage('news.loadPromptVersions', error, stackTrace),
      );
    }
  }

  @override
  Future<Result<NewsPromptVersion>> savePromptVersion(
    NewsPromptVersion version,
  ) async {
    try {
      await _db
          .into(_db.newsPromptVersionRecords)
          .insert(
            NewsPromptVersionRecordsCompanion.insert(
              language: version.language.code,
              version: version.version,
              mode: version.mode.code,
              taskInstruction: version.taskInstruction,
              outputSpec: version.outputSpec,
              advancedPrompt: version.advancedPrompt,
              note: Value<String?>(version.note),
              createdAt: Value<DateTime>(version.createdAt),
            ),
          );
      return Ok<NewsPromptVersion>(version);
    } on Exception catch (error, stackTrace) {
      return Err<NewsPromptVersion>(
        _storage('news.savePromptVersion', error, stackTrace),
      );
    }
  }

  @override
  Future<Result<void>> deletePromptVersion({
    required String language,
    required int version,
  }) async {
    try {
      await (_db.delete(_db.newsPromptVersionRecords)..where(
            (NewsPromptVersionRecords t) =>
                t.language.equals(language) & t.version.equals(version),
          ))
          .go();
      return okUnit();
    } on Exception catch (error, stackTrace) {
      return Err<void>(_storage('news.deletePromptVersion', error, stackTrace));
    }
  }

  static NewsRequiredSite _toSite(NewsRequiredSiteRecord row) =>
      NewsRequiredSite(
        id: row.id,
        name: row.name,
        url: row.url,
        enabled: row.enabled,
        sortOrder: row.sortOrder,
      );

  static NewsPromptVersion _toVersion(NewsPromptVersionRecord row) =>
      NewsPromptVersion(
        version: row.version,
        // 未知模式按「自动组合」处理：这比按高级覆盖安全——高级覆盖会把一段无法识别的
        // 用户文本当成总 prompt 发出去，而组合模式至少是完整的四条段落。
        mode: NewsPromptMode.fromCode(row.mode) ?? NewsPromptMode.composed,
        language:
            NewsPromptLanguage.fromCode(row.language) ??
            NewsPromptLanguage.chinese,
        taskInstruction: row.taskInstruction,
        outputSpec: row.outputSpec,
        advancedPrompt: row.advancedPrompt,
        createdAt: row.createdAt,
        note: row.note,
      );

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

/// 数据库不可用时的新闻来源配置端口（T036 的降级启动路径）。
///
/// 读返回**空配置**（本次运行确实没有任何配置可读：列表为空、prompt 走内置默认），
/// 写明确失败（不假装保存成功）。读空而不是抛错，是因为「还没有配置」在降级模式下是一个
/// 真实答案，界面表现为「列表为空 + 提示本次运行不保存改动」；而抛错会让设置页红屏。
final class DegradedNewsSourceConfigStore implements NewsSourceConfigStore {
  /// 构造降级实现。
  const DegradedNewsSourceConfigStore();

  @override
  Future<Result<List<NewsRequiredSite>>> loadRequiredSites() async =>
      const Ok<List<NewsRequiredSite>>(<NewsRequiredSite>[]);

  @override
  Future<Result<void>> replaceRequiredSites(
    List<NewsRequiredSite> sites,
  ) async => Err<void>(
    StorageError(operation: 'news.replaceRequiredSites', detail: '本次运行数据库不可用'),
  );

  @override
  Future<Result<List<String>>> loadList(String kind) async =>
      const Ok<List<String>>(<String>[]);

  @override
  Future<Result<void>> replaceList(String kind, List<String> values) async =>
      Err<void>(
        StorageError(operation: 'news.replaceList', detail: '本次运行数据库不可用'),
      );

  @override
  Future<Result<List<NewsPromptVersion>>> loadPromptVersions(
    String language,
  ) async => const Ok<List<NewsPromptVersion>>(<NewsPromptVersion>[]);

  @override
  Future<Result<NewsPromptVersion>> savePromptVersion(
    NewsPromptVersion version,
  ) async => Err<NewsPromptVersion>(
    StorageError(operation: 'news.savePromptVersion', detail: '本次运行数据库不可用'),
  );

  @override
  Future<Result<void>> deletePromptVersion({
    required String language,
    required int version,
  }) async => Err<void>(
    StorageError(operation: 'news.deletePromptVersion', detail: '本次运行数据库不可用'),
  );
}
