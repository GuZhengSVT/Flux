// AI 模型记录的 SQLite 实现（T025；端口在 features/ai/domain/ai_model_store.dart）。
//
// 「数据库不含秘密」在这里是**结构性**的：本文件没有任何一处读写 Key，表里也没有
// 对应的列。凭据只在 Keychain（SET-031），因此明文备份 flux.sqlite 不会泄漏 Key。
//
// 别名冲突（ux_ai_models_alias）翻译成 [ValidationError]：界面需要把它显示在「别名」
// 字段旁并保留用户输入，而底层 SqliteException 的文案既不稳定也不面向用户。
library;

import 'package:drift/drift.dart';

import 'package:flux/core/core.dart';
import 'package:flux/features/ai/domain/ai_model.dart';
import 'package:flux/features/ai/domain/ai_model_store.dart';
import 'package:flux/features/ai/domain/ai_protocol.dart';
import 'package:flux/features/ai/domain/model_capability.dart';

import 'database.dart';
import 'tables/ai_tables.dart';

/// drift 实现。
final class DriftAiModelStore implements AiModelStore {
  /// 绑定一个已打开的数据库。
  const DriftAiModelStore(this._db);

  final AppDatabase _db;

  @override
  Future<Result<List<AiModel>>> loadAll() async {
    try {
      final List<AiModelRecord> rows =
          await (_db.select(_db.aiModelRecords)
                ..orderBy(<OrderClauseGenerator<AiModelRecords>>[
                  (AiModelRecords t) => OrderingTerm.asc(t.sortOrder),
                  (AiModelRecords t) => OrderingTerm.asc(t.id),
                ]))
              .get();
      return Ok<List<AiModel>>(rows.map(_toDomain).toList(growable: false));
    } on Exception catch (error, stackTrace) {
      return Err<List<AiModel>>(
        StorageError(
          operation: 'aiModel.loadAll',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  @override
  Future<Result<AiModel>> insert(AiModel model) async {
    try {
      final int id = await _db
          .into(_db.aiModelRecords)
          .insert(_toCompanion(model));
      return Ok<AiModel>(model.copyWith(id: id));
    } on Exception catch (error, stackTrace) {
      return Err<AiModel>(_translate(error, model, stackTrace));
    }
  }

  @override
  Future<Result<AiModel>> update(AiModel model) async {
    final int? id = model.id;
    if (id == null) {
      return Err<AiModel>(
        ValidationError(field: 'SET-032', reason: '更新需要已落库的模型记录'),
      );
    }
    try {
      final int changed =
          await (_db.update(_db.aiModelRecords)
                ..where((AiModelRecords t) => t.id.equals(id)))
              .write(_toCompanion(model));
      if (changed == 0) {
        return Err<AiModel>(
          StorageError(
            operation: 'aiModel.update',
            detail: '模型记录不存在（id=$id）',
            isMissing: true,
          ),
        );
      }
      return Ok<AiModel>(model);
    } on Exception catch (error, stackTrace) {
      return Err<AiModel>(_translate(error, model, stackTrace));
    }
  }

  @override
  Future<Result<void>> delete(int id) async {
    try {
      final int removed = await (_db.delete(
        _db.aiModelRecords,
      )..where((AiModelRecords t) => t.id.equals(id))).go();
      if (removed == 0) {
        return Err<void>(
          StorageError(
            operation: 'aiModel.delete',
            detail: '模型记录不存在（id=$id）',
            isMissing: true,
          ),
        );
      }
      return okUnit();
    } on Exception catch (error, stackTrace) {
      return Err<void>(
        StorageError(
          operation: 'aiModel.delete',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  @override
  Future<Result<void>> saveOrder(List<int> idsInOrder) async {
    try {
      // 一个事务里写完：中途失败会留下「两条相同序号」的中间状态，界面顺序与故障
      // 转移顺序就不一致了；而这是用户一次拖动产生的一组写入，全部成功或全部不做。
      await _db.transaction(() async {
        for (int index = 0; index < idsInOrder.length; index++) {
          await (_db.update(
            _db.aiModelRecords,
          )..where((AiModelRecords t) => t.id.equals(idsInOrder[index]))).write(
            AiModelRecordsCompanion(
              sortOrder: Value<int>(index),
              updatedAt: Value<DateTime>(DateTime.now().toUtc()),
            ),
          );
        }
      });
      return okUnit();
    } on Exception catch (error, stackTrace) {
      return Err<void>(
        StorageError(
          operation: 'aiModel.saveOrder',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  @override
  Future<Result<void>> setDefaultForTasks(
    int id, {
    required bool isDefault,
  }) async {
    try {
      await _db.transaction(() async {
        // 先清掉其它记录的默认标记，再设置目标：顺序反过来会在事务中间留下一段
        // 「两个默认」的状态，虽然事务回滚能兜住，但把「唯一」表达成先清后设更直白。
        await _db
            .update(_db.aiModelRecords)
            .write(
              const AiModelRecordsCompanion(
                isDefaultForTasks: Value<bool>(false),
              ),
            );
        if (isDefault) {
          final int changed =
              await (_db.update(
                _db.aiModelRecords,
              )..where((AiModelRecords t) => t.id.equals(id))).write(
                AiModelRecordsCompanion(
                  isDefaultForTasks: const Value<bool>(true),
                  updatedAt: Value<DateTime>(DateTime.now().toUtc()),
                ),
              );
          if (changed == 0) {
            // 抛进事务里让「清默认」一起回滚：否则用户点了「设为默认」却只是把
            // 原来的默认清掉了，得到一个谁都不是默认的库。
            throw StorageError(
              operation: 'aiModel.setDefaultForTasks',
              detail: '模型记录不存在（id=$id）',
              isMissing: true,
            );
          }
        }
      });
      return okUnit();
    } on AppError catch (error) {
      return Err<void>(error);
    } on Exception catch (error, stackTrace) {
      return Err<void>(
        StorageError(
          operation: 'aiModel.setDefaultForTasks',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  /// 把数据库行还原为领域对象。
  ///
  /// 协议标识无法识别时**不**静默挑一个默认协议：那会把一条未知协议的记录当成
  /// Chat Completions 发出去，而请求体形状可能是错的。协议列由本工程写入，非法值
  /// 只可能来自手工改库或版本回退，因此这里抛 [StorageError] 让问题立刻可见，
  /// 而不是让它在一次真实付费调用里以「400 参数错误」的形式暴露。
  AiModel _toDomain(AiModelRecord row) {
    final AiProtocol? protocol = AiProtocol.fromId(row.protocolId);
    if (protocol == null) {
      throw StorageError(operation: 'aiModel.loadAll', detail: '未知协议标识（手工改库？）');
    }
    return AiModel(
      id: row.id,
      alias: row.alias,
      preset: row.preset,
      protocol: protocol,
      baseUrl: row.baseUrl,
      modelId: row.modelId,
      enabled: row.enabled,
      sortOrder: row.sortOrder,
      isDefaultForTasks: row.isDefaultForTasks,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
      capability: ModelCapability(
        text: row.capabilityText,
        vision: row.capabilityVision,
        streaming: row.capabilityStreaming,
        tools: row.capabilityTools,
        structured: row.capabilityStructured,
        contextWindow: row.contextWindow,
        maxOutput: row.outputBudget,
      ),
    );
  }

  AiModelRecordsCompanion _toCompanion(AiModel model) {
    final ModelCapability capability = model.capability;
    return AiModelRecordsCompanion(
      alias: Value<String>(model.alias),
      preset: Value<String?>(model.preset),
      protocolId: Value<String>(model.protocol.id),
      baseUrl: Value<String>(model.baseUrl),
      modelId: Value<String>(model.modelId),
      enabled: Value<bool>(model.enabled),
      sortOrder: Value<int>(model.sortOrder),
      capabilityText: Value<bool>(capability.text),
      capabilityVision: Value<bool>(capability.vision),
      capabilityStreaming: Value<bool>(capability.streaming),
      capabilityTools: Value<bool>(capability.tools),
      capabilityStructured: Value<bool>(capability.structured),
      contextWindow: Value<int?>(capability.contextWindow),
      outputBudget: Value<int?>(capability.maxOutput),
      isDefaultForTasks: Value<bool>(model.isDefaultForTasks),
      updatedAt: Value<DateTime>(DateTime.now().toUtc()),
    );
  }

  /// 把底层异常翻译成类型化错误。
  ///
  /// 只翻译**唯一别名**冲突：它是用户可修正的输入问题（换一个别名）。其它异常保持
  /// 为 [StorageError] 且不带原始 SQL 文本——SQL 文本里可能带上别名，而别名是用户
  /// 输入的自由文本。
  AppError _translate(Object error, AiModel model, StackTrace stackTrace) {
    final String text = error.toString().toLowerCase();
    // 命中条件同时看表名与**索引名**：drift/SQLite 在不同版本下报的可能是
    // "UNIQUE constraint failed: ai_model_records.alias"，也可能带上索引名
    // （ux_ai_models_alias）。只认一种会让「别名重复」在某些路径上退化成
    // 「存储失败」，用户就看不到「换一个别名」这个可执行的建议。
    final bool isUnique =
        text.contains('unique') || text.contains('constraint failed');
    if (isUnique &&
        (text.contains('ai_model_records') ||
            text.contains('ux_ai_models_alias') ||
            text.contains('alias'))) {
      return ValidationError(
        field: 'SET-030.alias',
        reason: '别名已被占用，请换一个',
        value: model.alias,
      );
    }
    return StorageError(
      operation: 'aiModel.save',
      cause: error,
      stackTrace: stackTrace,
    );
  }
}
