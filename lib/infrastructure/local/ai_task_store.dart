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
///
/// 除读写一条缓存（[AiResultCache]）外，它还实现 [AiResultCacheMaintenance]：统计与按上限
/// 淘汰。**每次成功写入后自动执行一次淘汰**（见 [save] 的说明），因此上限不需要任何后台任务
/// 或启动钩子来维持——「忘了调淘汰」这件事在结构上不可能发生。
final class DriftAiResultCache
    implements AiResultCache, AiResultCacheMaintenance {
  /// 绑定一个已打开的数据库。
  ///
  /// [limits] 是容量上限。给它一个构造参数而不是写死常量，是为了让装配层能把「这是内部资源
  /// 策略」这一事实放在一处（见 AiCacheLimits 的说明：它不是 SET 项）。
  const DriftAiResultCache(
    this._db, {
    this.limits = AiCacheLimits.defaults,
    this.clock = const SystemClock(),
  });

  final AppDatabase _db;

  /// 容量上限（条数 + 字节）。
  final AiCacheLimits limits;

  /// 时钟（记录命中时刻；不参与任何判定）。
  final Clock clock;

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
      // 命中即是**一次使用**：LRU 需要这个事实，否则淘汰退化成 FIFO，而 FIFO 会删掉
      // 「每天都在用、第一次生成在很久之前」的条目——那恰恰是最该留的。
      //
      // 这一步失败不影响本次读取：拿到结果比记准使用时间重要（一个读不出来的日志字段不该
      // 让一次成功的缓存命中变成失败）。因此这里吞掉错误，只让命中本身成立。
      await _touchLastUsed(key);
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
              // 字节数在**写入时**算好：让统计与淘汰不必把全部结果文本读进内存（上限本身
              // 是 128 MiB，全读一遍等于每次写入都扫 128 MiB 的正文）。
              byteLength: Value<int>(utf8ByteLength(entry.text)),
              // 刚写入即算「刚用过」：它是当前这次任务刚刚产出的结果，最可能被下一步复用。
              lastUsedAt: Value<DateTime?>(clock.now().toUtc()),
            ),
          );
      // 写入后立刻按上限淘汰。放在成功写入之后（而不是之前）是为了让判定看到**真实的**当前
      // 占用；与此同时「本次刚写入的条目不被删」由核心判定保证（extra 不参与淘汰）。
      await enforceLimits(limits);
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

  @override
  Future<Result<({int entries, int bytes})>> usage() async {
    try {
      // 用一条聚合 SQL 而不是「读出行再在 Dart 里求和」：缓存上限是 128 MiB，把全部结果文本
      // 读进内存只为了求和，会让一次统计变成一次上百 MB 的读盘与分配。COUNT/SUM 只回一行。
      //
      // `COALESCE(SUM(...), 0)`：空表时 SUM 是 NULL，而 NULL 在 Dart 侧会被读成 null；用
      // COALESCE 让「空缓存 = 0 字节」成为 SQL 给的事实，而不是调用方补的一个默认值。
      final QueryRow row = await _db
          .customSelect(
            'SELECT COUNT(*) AS c, '
            'COALESCE(SUM(byte_length), 0) AS b '
            'FROM ai_result_cache_records',
          )
          .getSingle();
      return Ok<({int entries, int bytes})>((
        entries: row.read<int>('c'),
        bytes: row.read<int>('b'),
      ));
    } on Exception catch (error, stackTrace) {
      return Err<({int entries, int bytes})>(
        StorageError(
          operation: 'aiResultCache.usage',
          detail: error.runtimeType.toString(),
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  @override
  Future<Result<int>> enforceLimits(AiCacheLimits limits) async {
    try {
      final List<AiCacheEntryFact> facts = await _cacheFacts();
      final AiCacheEvictionPlan plan = planAiCacheEviction(
        entries: facts,
        limits: limits,
      );
      if (plan.isEmpty) {
        return const Ok<int>(0);
      }
      // 一条 DELETE ... IN (...) 而不是逐个删：逐个删在中途失败时会留下「一部分已淘汰、
      // 一部分仍超限」的混合状态，而下一次写入又会从头算一遍——两次淘汰之间用户看到的占用
      // 与上限对不上。
      await (_db.delete(_db.aiResultCacheRecords)..where(
            ($AiResultCacheRecordsTable t) =>
                t.cacheKey.isIn(plan.keysToDelete),
          ))
          .go();
      return Ok<int>(plan.keysToDelete.length);
    } on Exception catch (error, stackTrace) {
      return Err<int>(
        StorageError(
          operation: 'aiResultCache.enforceLimits',
          detail: error.runtimeType.toString(),
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  /// 读全部条目的**元数据**（键、字节数、时间），不读结果文本。
  ///
  /// 显式列出四列而不是 `select(aiResultCacheRecords)`：后者会把 result_text 一起读出来，
  /// 而淘汰只需要元数据。上限是 128 MiB，把全部正文读进内存只为决定删哪几条，会让一次
  /// 「省空间」的动作本身成为一次上百 MB 的分配。
  Future<List<AiCacheEntryFact>> _cacheFacts() async {
    final List<QueryRow> rows = await _db
        .customSelect(
          'SELECT cache_key AS k, byte_length AS b, '
          'created_at AS c, last_used_at AS u '
          'FROM ai_result_cache_records',
        )
        .get();
    return rows
        .map(
          (QueryRow row) => AiCacheEntryFact(
            key: row.read<String>('k'),
            // 旧行（v17 之前写入、迁移未回填到的情况）字节数为 0：按 0 处理会让它们在上限判定
            // 里被当成不占空间，但它们确实占着。迁移已经回填过，因此这里的 0 只可能是「结果文本
            // 本身为空」或「迁移尚未跑到」，两者按 0 都不会删错东西（只是暂时少算一点）。
            byteLength: row.read<int>('b'),
            // 时间是 ISO-8601 文本（build.yaml 的 store_date_time_values_as_text），因此
            // 用 DateTime.parse 而不是让 drift 的类型化读取器处理——这条 SQL 是手写的，
            // 没有列的转换器可用。
            createdAt: DateTime.parse(row.read<String>('c')).toUtc(),
            lastUsedAt: switch (row.read<String?>('u')) {
              final String raw => DateTime.parse(raw).toUtc(),
              null => null,
            },
          ),
        )
        .toList(growable: false);
  }

  /// 更新一条缓存的最近使用时刻；失败静默（见 [find] 的说明）。
  Future<void> _touchLastUsed(String key) async {
    try {
      await (_db.update(
        _db.aiResultCacheRecords,
      )..where(($AiResultCacheRecordsTable t) => t.cacheKey.equals(key))).write(
        AiResultCacheRecordsCompanion(
          lastUsedAt: Value<DateTime?>(clock.now().toUtc()),
        ),
      );
    } on Exception {
      // 忽略：见 find 的说明。
    }
  }
}
