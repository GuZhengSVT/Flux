// 搜索服务记录的 SQLite 实现（T031；端口在 features/ai/domain/search_service_store.dart）。
//
// 「数据库不含秘密」在这里是**结构性**的：本文件没有任何一处读写 Key，表里也没有
// 对应的列。凭据只在 Keychain（SET-039），因此明文备份 flux.sqlite 不会泄漏 Key。
//
// 名字冲突（ux_search_service_label）翻译成 [ValidationError]：界面需要把它显示在
// 「服务名」字段旁并保留用户输入，而底层 SqliteException 的文案既不稳定也不面向用户。
library;

import 'package:drift/drift.dart';

import 'package:flux/core/core.dart';
import 'package:flux/features/ai/domain/search_protocol.dart';
import 'package:flux/features/ai/domain/search_service.dart';
import 'package:flux/features/ai/domain/search_service_store.dart';

import 'database.dart';
import 'tables/ai_tables.dart';

/// drift 实现。
final class DriftSearchServiceStore implements SearchServiceStore {
  /// 绑定一个已打开的数据库。
  const DriftSearchServiceStore(this._db);

  final AppDatabase _db;

  @override
  Future<Result<List<SearchService>>> loadAll() async {
    try {
      final List<SearchServiceRecord> rows =
          await (_db.select(_db.searchServiceRecords)
                ..orderBy(<OrderClauseGenerator<SearchServiceRecords>>[
                  (SearchServiceRecords t) => OrderingTerm.asc(t.sortOrder),
                  (SearchServiceRecords t) => OrderingTerm.asc(t.id),
                ]))
              .get();
      return Ok<List<SearchService>>(
        rows.map(_toDomain).toList(growable: false),
      );
    } on Exception catch (error, stackTrace) {
      return Err<List<SearchService>>(
        StorageError(
          operation: 'searchService.loadAll',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  @override
  Future<Result<SearchService>> insert(SearchService service) async {
    try {
      final int id = await _db
          .into(_db.searchServiceRecords)
          .insert(_toCompanion(service));
      return Ok<SearchService>(service.copyWith(id: id));
    } on Exception catch (error, stackTrace) {
      return Err<SearchService>(_translate(error, service, stackTrace));
    }
  }

  @override
  Future<Result<SearchService>> update(SearchService service) async {
    final int? id = service.id;
    if (id == null) {
      return Err<SearchService>(
        ValidationError(field: 'SET-038', reason: '更新需要已落库的搜索服务记录'),
      );
    }
    try {
      final int changed =
          await (_db.update(_db.searchServiceRecords)
                ..where((SearchServiceRecords t) => t.id.equals(id)))
              .write(_toCompanion(service));
      if (changed == 0) {
        return Err<SearchService>(
          StorageError(
            operation: 'searchService.update',
            detail: '搜索服务记录不存在（id=$id）',
            isMissing: true,
          ),
        );
      }
      return Ok<SearchService>(service);
    } on Exception catch (error, stackTrace) {
      return Err<SearchService>(_translate(error, service, stackTrace));
    }
  }

  @override
  Future<Result<void>> delete(int id) async {
    try {
      final int removed = await (_db.delete(
        _db.searchServiceRecords,
      )..where((SearchServiceRecords t) => t.id.equals(id))).go();
      if (removed == 0) {
        return Err<void>(
          StorageError(
            operation: 'searchService.delete',
            detail: '搜索服务记录不存在（id=$id）',
            isMissing: true,
          ),
        );
      }
      return okUnit();
    } on Exception catch (error, stackTrace) {
      return Err<void>(
        StorageError(
          operation: 'searchService.delete',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  @override
  Future<Result<void>> saveOrder(List<int> idsInOrder) async {
    try {
      // 一个事务里写完：中途失败会留下「两条相同序号」的中间状态，服务选择顺序
      // 就变得不确定了；而这是用户一次拖动产生的一组写入，全部成功或全部不做。
      await _db.transaction(() async {
        for (int index = 0; index < idsInOrder.length; index++) {
          await (_db.update(_db.searchServiceRecords)..where(
                (SearchServiceRecords t) => t.id.equals(idsInOrder[index]),
              ))
              .write(
                SearchServiceRecordsCompanion(
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
          operation: 'searchService.saveOrder',
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
        // 「两个默认」的状态，虽然事务能回滚，但把「唯一」表达成先清后设更直白。
        await _db
            .update(_db.searchServiceRecords)
            .write(
              const SearchServiceRecordsCompanion(
                isDefaultForTasks: Value<bool>(false),
              ),
            );
        if (isDefault) {
          final int changed =
              await (_db.update(
                _db.searchServiceRecords,
              )..where((SearchServiceRecords t) => t.id.equals(id))).write(
                SearchServiceRecordsCompanion(
                  isDefaultForTasks: const Value<bool>(true),
                  updatedAt: Value<DateTime>(DateTime.now().toUtc()),
                ),
              );
          if (changed == 0) {
            // 抛进事务里让「清默认」一起回滚：否则用户点了「设为默认」却只是把
            // 原来的默认清掉了，得到一个谁都不是默认的库。
            throw StorageError(
              operation: 'searchService.setDefaultForTasks',
              detail: '搜索服务记录不存在（id=$id）',
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
          operation: 'searchService.setDefaultForTasks',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  /// 把数据库行还原为领域对象。
  ///
  /// 协议标识无法识别时**不**静默挑一个默认协议：那会把一条未知协议的记录当成
  /// Tavily 发出去，而请求形状可能是错的（甚至把 Key 用错误的认证头发给错误的端点）。
  /// 协议列由本工程写入，非法值只可能来自手工改库或版本回退，因此这里抛
  /// [StorageError] 让问题立刻可见。
  SearchService _toDomain(SearchServiceRecord row) {
    final SearchProtocol? protocol = SearchProtocol.fromId(row.protocolId);
    if (protocol == null) {
      throw StorageError(
        operation: 'searchService.loadAll',
        detail: '未知搜索协议标识（手工改库？）',
      );
    }
    return SearchService(
      id: row.id,
      label: row.label,
      protocol: protocol,
      baseUrl: row.baseUrl,
      enabled: row.enabled,
      sortOrder: row.sortOrder,
      maxResults: row.maxResults,
      timeoutSeconds: row.timeoutSeconds,
      allowPrivateEndpoint: row.allowPrivateEndpoint,
      isDefaultForTasks: row.isDefaultForTasks,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
    );
  }

  SearchServiceRecordsCompanion _toCompanion(SearchService service) {
    return SearchServiceRecordsCompanion(
      label: Value<String>(service.label),
      protocolId: Value<String>(service.protocol.id),
      baseUrl: Value<String>(service.baseUrl),
      enabled: Value<bool>(service.enabled),
      sortOrder: Value<int>(service.sortOrder),
      maxResults: Value<int>(service.maxResults),
      timeoutSeconds: Value<int>(service.timeoutSeconds),
      allowPrivateEndpoint: Value<bool>(service.allowPrivateEndpoint),
      isDefaultForTasks: Value<bool>(service.isDefaultForTasks),
      updatedAt: Value<DateTime>(DateTime.now().toUtc()),
    );
  }

  /// 把底层异常翻译成类型化错误。
  ///
  /// 只翻译**唯一名字**冲突：它是用户可修正的输入问题（换一个名字）。其它异常保持
  /// 为 [StorageError] 且不带原始 SQL 文本——SQL 文本里可能带上名字（用户输入的自由文本）。
  AppError _translate(
    Object error,
    SearchService service,
    StackTrace stackTrace,
  ) {
    final String text = error.toString().toLowerCase();
    final bool isUnique =
        text.contains('unique') || text.contains('constraint failed');
    if (isUnique &&
        (text.contains('search_service_records') ||
            text.contains('ux_search_service_label') ||
            text.contains('label'))) {
      return ValidationError(
        field: 'SET-038.label',
        reason: '服务名已被占用，请换一个',
        value: service.label,
      );
    }
    return StorageError(
      operation: 'searchService.save',
      cause: error,
      stackTrace: stackTrace,
    );
  }
}
