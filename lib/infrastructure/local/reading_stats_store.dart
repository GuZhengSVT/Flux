// 阅读会话的持久化（T023；架构 5.1 的 ReadingSession、5.3 的统计口径）。
//
// 职责边界：本文件只做**写入已拆好的行**与**按本地日期聚合**。午夜拆分、时区归属、
// 空闲判定的规则全在 core/domain/reading_session.dart（纯函数，有确定性测试）；这一层
// 再实现一遍等于把同一条规则写两处，而它正是最容易悄悄漂移的一处。
//
// 两个刻意的实现选择：
//   1) 批量写入在**一个事务**内完成：跨午夜会产出两行，它们描述的是同一次阅读。
//      只写进去一半会让「读了多久」在热力图上少一块，而界面没有任何线索；
//   2) 聚合按 local_date 文本范围做，**不按 UTC 时间范围**：归属日期在写入时已经
//      按会话当时的时区算好，查询端不再做时区换算，历史归属因此不会因为用户旅行
//      或查询端时区变化而漂移（架构 5.3 明确「按会话时区跨午夜拆分」）。
library;

import 'package:drift/drift.dart';

import 'package:flux/core/core.dart';

import 'database.dart';

/// 阅读统计数据层。
final class DriftReadingStatsStore implements ReadingStatsStore {
  /// 绑定一个已打开的数据库。
  const DriftReadingStatsStore(this._db);

  final AppDatabase _db;

  @override
  Future<Result<int>> appendSessions(List<ReadingSessionDraft> drafts) async {
    if (drafts.isEmpty) {
      // 空批次不是错误，也不开事务：调用方在一次 flush 里没有任何有效时间
      // （例如刚打开就失焦）是正常情况。
      return const Ok<int>(0);
    }
    try {
      await _db.transaction(() async {
        for (final ReadingSessionDraft draft in drafts) {
          await _db
              .into(_db.readingSessions)
              .insert(
                ReadingSessionsCompanion.insert(
                  articleId: draft.articleId,
                  startedAt: draft.startedAt,
                  // endedAt 是 NOT NULL 语义之外的列吗？不是：表定义里 endedAt 可空
                  // （进行中的会话为 null）。本层写入的永远是**已结束的一段**，
                  // 因此总是带上结束时间；「进行中」的语义由 tracker 在内存里持有，
                  // 不落库——落一条没有结束时间的行会让「有效秒数」在崩溃后无法解释。
                  endedAt: Value<DateTime?>(draft.endedAt),
                  effectiveSeconds: Value<int>(draft.effectiveSeconds),
                  timeZone: draft.timeZone,
                  localDate: draft.localDate,
                ),
              );
        }
      });
      return Ok<int>(drafts.length);
    } on Exception catch (error, stackTrace) {
      return Err<int>(
        StorageError(
          operation: 'appendSessions',
          detail: error.runtimeType.toString(),
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  @override
  Future<Result<List<ReadingDayTotal>>> dailyTotals({
    required String fromDate,
    required String toDate,
  }) async {
    try {
      final List<QueryRow> rows = await _db
          .customSelect(
            'SELECT local_date AS d, SUM(effective_seconds) AS s '
            'FROM reading_sessions WHERE local_date >= ? AND local_date <= ? '
            'GROUP BY local_date ORDER BY local_date',
            variables: <Variable<Object>>[
              Variable<String>(fromDate),
              Variable<String>(toDate),
            ],
            readsFrom: <ResultSetImplementation<Object, Object>>{
              _db.readingSessions,
            },
          )
          .get();
      return Ok<List<ReadingDayTotal>>(<ReadingDayTotal>[
        for (final QueryRow row in rows)
          ReadingDayTotal(
            localDate: row.read<String>('d'),
            seconds: row.read<int>('s'),
          ),
      ]);
    } on Exception catch (error, stackTrace) {
      return Err<List<ReadingDayTotal>>(
        StorageError(
          operation: 'dailyTotals',
          detail: error.runtimeType.toString(),
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  @override
  Future<Result<List<int>>> activeYears() async {
    try {
      // 年份从日期键里取：local_date 是定长的 YYYY-MM-DD，因此前四位就是年份，
      // 不需要解析成日期（解析会把「按本地日期归属」这件事重新拖回时区里）。
      final List<QueryRow> rows = await _db
          .customSelect(
            'SELECT DISTINCT substr(local_date, 1, 4) AS y '
            'FROM reading_sessions '
            'ORDER BY y DESC',
            readsFrom: <ResultSetImplementation<Object, Object>>{
              _db.readingSessions,
            },
          )
          .get();
      return Ok<List<int>>(<int>[
        for (final QueryRow row in rows)
          if (int.tryParse(row.read<String>('y')) case final int year) year,
      ]);
    } on Exception catch (error, stackTrace) {
      return Err<List<int>>(
        StorageError(
          operation: 'activeYears',
          detail: error.runtimeType.toString(),
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  @override
  Future<Result<int>> clearAll() async {
    try {
      // 只删会话表：文章、阅读状态、收藏、设置都不在删除范围内（架构 5.3 的
      // 「清缓存/清历史不删状态与订阅」同一条规则）。
      final int removed = await _db.delete(_db.readingSessions).go();
      return Ok<int>(removed);
    } on Exception catch (error, stackTrace) {
      return Err<int>(
        StorageError(
          operation: 'clearReadingStats',
          detail: error.runtimeType.toString(),
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }
}
