// 持久任务与结果缓存的 SQLite 实现（T030；端口在 features/ai/domain/ai_task_store.dart）。
//
// 三条刻意的实现选择：
//
//   1) **失败不写缓存**。缓存表只由 [DriftAiResultCache.save] 写入，而它只被用例层在
//      「成功或部分成功」时调用。实现层不额外加判断：把这条规则放在用例层，是因为
//      「什么算成功」是任务语义（还要经过 T036 的引用校验），不是存储语义。
//
//   2) **标中断是一条批量 UPDATE**，不是读-改-写循环。逐个读改写在中途崩溃时会留下
//      「一部分 interrupted、一部分仍是 running」的混合状态，而下一次启动无法区分
//      「真的还在跑」与「上次没标完」。一条带 IN 条件的 UPDATE 在 SQLite 里是原子的。
//
//   3) **JSON 列解析失败按「没有这条记录」处理**而不是抛异常：一条损坏的快照不应该
//      让整个任务列表打不开。此时 findById 返回 Ok(null)、loadAll 跳过该行，
//      并在诊断里留一条结构性记录（taskId + 失败类别，不含内容）。
library;

import 'dart:convert';

import 'package:drift/drift.dart';

import 'package:flux/core/core.dart';
import 'package:flux/features/ai/domain/ai_task_record.dart';
import 'package:flux/features/ai/domain/ai_task_store.dart';

import 'database.dart';
import 'tables/ai_tables.dart';

/// 任务的 drift 实现。
final class DriftAiTaskStore implements AiTaskStore {
  /// 绑定一个已打开的数据库。
  ///
  /// [diagnostics] 可空：跳过损坏行这件事本身必须留痕（否则「任务列表少了一条」在
  /// 界面上完全没有线索），但存储层不该强迫调用方提供一个日志端口。
  const DriftAiTaskStore(this._db, {this.diagnostics});

  final AppDatabase _db;

  /// 诊断端口（跳过损坏行时记录一条结构性说明）。
  final DiagnosticSink? diagnostics;

  @override
  Future<Result<void>> save(AiTaskRecord record) async {
    try {
      await _db.into(_db.aiTasks).insertOnConflictUpdate(_toCompanion(record));
      return okUnit();
    } on Exception catch (error, stackTrace) {
      return Err<void>(
        StorageError(
          operation: 'aiTask.save',
          detail: error.runtimeType.toString(),
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  @override
  Future<Result<AiTaskRecord?>> findById(String taskId) async {
    try {
      final AiTask? row =
          await (_db.select(_db.aiTasks)
                ..where(($AiTasksTable t) => t.taskId.equals(taskId))
                ..limit(1))
              .getSingleOrNull();
      if (row == null) {
        return const Ok<AiTaskRecord?>(null);
      }
      final AiTaskRecord? record = _toDomain(row);
      if (record == null) {
        _logDecodeSkipped(taskId);
      }
      return Ok<AiTaskRecord?>(record);
    } on Exception catch (error, stackTrace) {
      return Err<AiTaskRecord?>(
        StorageError(
          operation: 'aiTask.findById',
          detail: error.runtimeType.toString(),
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  @override
  Future<Result<List<AiTaskRecord>>> loadAll() async {
    try {
      final List<AiTask> rows =
          await (_db.select(_db.aiTasks)
                ..orderBy(<OrderClauseGenerator<AiTasks>>[
                  (AiTasks t) => OrderingTerm.desc(t.createdAt),
                  (AiTasks t) => OrderingTerm.asc(t.taskId),
                ]))
              .get();
      final List<AiTaskRecord> records = <AiTaskRecord>[];
      for (final AiTask row in rows) {
        final AiTaskRecord? record = _toDomain(row);
        if (record == null) {
          // 损坏的快照：跳过该行而不是让整个列表打不开。只记结构事实。
          _logDecodeSkipped(row.taskId);
          continue;
        }
        records.add(record);
      }
      return Ok<List<AiTaskRecord>>(List<AiTaskRecord>.unmodifiable(records));
    } on Exception catch (error, stackTrace) {
      return Err<List<AiTaskRecord>>(
        StorageError(
          operation: 'aiTask.loadAll',
          detail: error.runtimeType.toString(),
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  @override
  Future<Result<int>> markActiveAsInterrupted({required DateTime at}) async {
    try {
      // 活跃态只有四个（queued/running/waitingConfiguration/waitingNetwork），
      // 显式列出而不是用 NOT IN（终态列表）：将来新增一个终态时，「NOT IN 旧列表」
      // 会把新终态误判成活跃态并覆盖掉它的真实结论。
      const List<String> active = <String>[
        'queued',
        'running',
        'waitingConfiguration',
        'waitingNetwork',
      ];
      final int changed =
          await (_db.update(
            _db.aiTasks,
          )..where(($AiTasksTable t) => t.status.isIn(active))).write(
            AiTasksCompanion(
              status: const Value<String>('interrupted'),
              updatedAt: Value<DateTime>(at.toUtc()),
            ),
          );
      return Ok<int>(changed);
    } on Exception catch (error, stackTrace) {
      return Err<int>(
        StorageError(
          operation: 'aiTask.markActiveAsInterrupted',
          detail: error.runtimeType.toString(),
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  @override
  Future<Result<void>> delete(String taskId) async {
    try {
      await (_db.delete(
        _db.aiTasks,
      )..where(($AiTasksTable t) => t.taskId.equals(taskId))).go();
      return okUnit();
    } on Exception catch (error, stackTrace) {
      return Err<void>(
        StorageError(
          operation: 'aiTask.delete',
          detail: error.runtimeType.toString(),
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  void _logDecodeSkipped(String taskId) {
    // 只记结构性事实（哪个任务被跳过），不记快照内容。
    diagnostics?.warning('AI 任务记录无法解析，已跳过 taskId=$taskId', tag: 'ai.task');
  }

  AiTasksCompanion _toCompanion(AiTaskRecord record) => AiTasksCompanion(
    taskId: Value<String>(record.taskId),
    kind: Value<String>(record.kind.id),
    inputSnapshot: Value<String>(jsonEncode(record.snapshot.toJson())),
    promptHash: Value<String>(record.snapshot.promptHash),
    modelAliases: Value<String>(jsonEncode(record.modelAliases)),
    routeModelIds: Value<String>(jsonEncode(record.modelAliases)),
    status: Value<String>(record.status.name),
    deadline: Value<DateTime?>(record.deadline?.toUtc()),
    consumedTokens: Value<int>(record.consumedTokens),
    attemptCount: Value<int>(record.attemptCount),
    resultText: Value<String?>(record.resultText),
    finishReason: Value<String?>(record.finishReason),
    errorKind: Value<String?>(record.errorKind),
    providerAlias: Value<String?>(record.providerAlias),
    cacheKey: Value<String?>(record.cacheKey),
    fromCache: Value<bool>(record.fromCache),
    createdAt: Value<DateTime>(record.createdAt.toUtc()),
    updatedAt: Value<DateTime>(record.updatedAt.toUtc()),
  );

  /// 行 → 领域对象；快照或状态损坏时返回 null（调用方按「没有这条记录」处理）。
  static AiTaskRecord? _toDomain(AiTask row) {
    final TaskStatus? status = _statusFrom(row.status);
    if (status == null) {
      return null;
    }
    final AiTaskKind? kind = AiTaskKind.fromId(row.kind);
    if (kind == null) {
      return null;
    }
    final Object? decoded = _decode(row.inputSnapshot);
    if (decoded is! Map<String, Object?>) {
      return null;
    }
    final AiInputSnapshot? snapshot = AiInputSnapshot.fromJson(decoded);
    if (snapshot == null) {
      return null;
    }
    return AiTaskRecord(
      taskId: row.taskId,
      kind: kind,
      snapshot: snapshot,
      modelAliases: _decodeStringList(row.modelAliases),
      status: status,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
      deadline: row.deadline,
      consumedTokens: row.consumedTokens,
      attemptCount: row.attemptCount,
      resultText: row.resultText,
      finishReason: row.finishReason,
      errorKind: row.errorKind,
      providerAlias: row.providerAlias,
      cacheKey: row.cacheKey,
      fromCache: row.fromCache,
    );
  }

  static TaskStatus? _statusFrom(String? name) {
    for (final TaskStatus status in TaskStatus.values) {
      if (status.name == name) {
        return status;
      }
    }
    return null;
  }

  static Object? _decode(String raw) {
    try {
      return jsonDecode(raw);
    } on FormatException {
      return null;
    }
  }

  static List<String> _decodeStringList(String raw) {
    final Object? decoded = _decode(raw);
    if (decoded is! List<Object?>) {
      return const <String>[];
    }
    return decoded.whereType<String>().toList(growable: false);
  }
}

/// 结果缓存的 drift 实现。
final class DriftAiResultCache implements AiResultCache {
  /// 绑定一个已打开的数据库。
  const DriftAiResultCache(this._db);

  final AppDatabase _db;

  @override
  Future<Result<AiResultCacheEntry?>> find(String key) async {
    try {
      final AiResultCacheRecord? row =
          await (_db.select(_db.aiResultCacheRecords)
                ..where(
                  ($AiResultCacheRecordsTable t) => t.cacheKey.equals(key),
                )
                ..limit(1))
              .getSingleOrNull();
      if (row == null) {
        return const Ok<AiResultCacheEntry?>(null);
      }
      // 行 → 领域对象：表里的列名与领域字段名刻意不同（result_text / cache_key），
      // 因此这里显式映射而不是直接把行对象当成领域对象返回。
      return Ok<AiResultCacheEntry?>(
        AiResultCacheEntry(
          key: row.cacheKey,
          text: row.text_,
          providerAlias: row.providerAlias,
          modelId: row.modelId,
          createdAt: row.createdAt,
        ),
      );
    } on Exception catch (error, stackTrace) {
      return Err<AiResultCacheEntry?>(
        StorageError(
          operation: 'aiResultCache.find',
          detail: error.runtimeType.toString(),
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  @override
  Future<Result<void>> save(AiResultCacheEntry entry) async {
    try {
      await _db
          .into(_db.aiResultCacheRecords)
          .insertOnConflictUpdate(
            AiResultCacheRecordsCompanion(
              cacheKey: Value<String>(entry.key),
              text_: Value<String>(entry.text),
              providerAlias: Value<String>(entry.providerAlias),
              modelId: Value<String>(entry.modelId),
              createdAt: Value<DateTime>(entry.createdAt.toUtc()),
            ),
          );
      return okUnit();
    } on Exception catch (error, stackTrace) {
      return Err<void>(
        StorageError(
          operation: 'aiResultCache.save',
          detail: error.runtimeType.toString(),
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  @override
  Future<Result<void>> delete(String key) async {
    try {
      await (_db.delete(
        _db.aiResultCacheRecords,
      )..where(($AiResultCacheRecordsTable t) => t.cacheKey.equals(key))).go();
      return okUnit();
    } on Exception catch (error, stackTrace) {
      return Err<void>(
        StorageError(
          operation: 'aiResultCache.delete',
          detail: error.runtimeType.toString(),
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  @override
  Future<Result<void>> clear() async {
    try {
      await _db.delete(_db.aiResultCacheRecords).go();
      return okUnit();
    } on Exception catch (error, stackTrace) {
      return Err<void>(
        StorageError(
          operation: 'aiResultCache.clear',
          detail: error.runtimeType.toString(),
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }
}
