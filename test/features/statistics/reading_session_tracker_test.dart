// T023：阅读会话追踪器的行为（假时钟 + 假设置 + 记录用替身存储）。
//
// 这里验的是 tracker 的**判定**，不是数据库：
//   * SET-015 关闭 → 完全不记录（不写任何行）；
//   * 失焦/后台 → 立即暂停累计，且不补回离开的时间；
//   * 空闲超阈 → 只算到最后交互 + 阈值，恢复交互后继续累计；
//   * 周期 flush 与 stop 落库；
//   * 跨午夜的会话在**落库时**被拆成两行（与 domain 用例互补：这里验的是端到端
//     经过 tracker 之后仍是两行）；
//   * 写入失败不重复写（丢一段好过记重复）。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:flux/core/core.dart';
import 'package:flux/features/settings/application/settings_store.dart';
import 'package:flux/features/statistics/application/reading_session_tracker.dart';

/// 记录写入的替身存储。
final class _RecordingStore implements ReadingStatsStore {
  /// 已写入的草案（按写入顺序）。
  final List<ReadingSessionDraft> written = <ReadingSessionDraft>[];

  /// 每次 appendSessions 的批大小（用于断言「分几次写」）。
  final List<int> batches = <int>[];

  /// 为 true 时写入失败。
  bool failWrites = false;

  @override
  Future<Result<int>> appendSessions(List<ReadingSessionDraft> drafts) async {
    batches.add(drafts.length);
    if (failWrites) {
      return Err<int>(
        StorageError(operation: 'appendSessions', detail: '测试替身：故意失败'),
      );
    }
    written.addAll(drafts);
    return Ok<int>(drafts.length);
  }

  @override
  Future<Result<List<ReadingDayTotal>>> dailyTotals({
    required String fromDate,
    required String toDate,
  }) async => const Ok<List<ReadingDayTotal>>(<ReadingDayTotal>[]);

  @override
  Future<Result<List<int>>> activeYears() async => const Ok<List<int>>(<int>[]);

  @override
  Future<Result<int>> clearAll() async => const Ok<int>(0);
}

/// 只提供 SET-015 的替身设置端口。
final class _FixedSettings implements SettingsStore {
  _FixedSettings({
    required this.enabled,
    this.idleMinutes = 5,
    this.fail = false,
  });

  final bool enabled;
  final int idleMinutes;
  final bool fail;

  @override
  Future<Result<Object?>> readSetting(SettingId id) async {
    if (fail) {
      return Err<Object?>(
        StorageError(operation: 'readSetting', detail: '测试替身：故意失败'),
      );
    }
    if (id.code == SettingId.set015.code) {
      return Ok<Object?>(<String, Object?>{
        'enabled': enabled,
        'idlePauseMinutes': idleMinutes,
      });
    }
    return const Ok<Object?>(null);
  }

  @override
  Future<Result<Object?>> writeSetting(SettingId id, Object? value) async =>
      Ok<Object?>(value);

  @override
  Future<Result<Map<String, Object?>>> readEffectiveSettings() async =>
      const Ok<Map<String, Object?>>(<String, Object?>{});
}

const SessionLocalZone shanghai = FixedOffsetZone(
  Duration(hours: 8),
  ianaName: 'Asia/Shanghai',
);

/// 组装一个 tracker。
({ReadingSessionTracker tracker, _RecordingStore store, FakeClock clock})
_build({
  bool enabled = true,
  int idleMinutes = 5,
  Duration flushInterval = const Duration(seconds: 30),
  bool settingsFail = false,
}) {
  final _RecordingStore store = _RecordingStore();
  final FakeClock clock = FakeClock(start: DateTime.utc(2026, 9, 21, 2));
  final ReadingSessionTracker tracker = ReadingSessionTracker(
    articleId: 42,
    stats: store,
    settings: _FixedSettings(
      enabled: enabled,
      idleMinutes: idleMinutes,
      fail: settingsFail,
    ),
    clock: clock,
    zone: shanghai,
    flushInterval: flushInterval,
  );
  return (tracker: tracker, store: store, clock: clock);
}

void main() {
  group('SET-015 开关', () {
    test('关闭时完全不记录：不产生任何写入', () async {
      final result = _build(enabled: false);
      await result.tracker.start();
      result.clock.advance(const Duration(minutes: 10));
      await result.tracker.tick();
      await result.tracker.stop();
      expect(result.store.written, isEmpty, reason: '关闭时不得写任何会话行');
      expect(result.store.batches, isEmpty, reason: '连一次空写入都不该发生');
      expect(result.tracker.isRecording, isFalse);
    });

    test('设置读取失败按默认值（开）继续记录，而不是静默关闭', () async {
      final result = _build(settingsFail: true);
      await result.tracker.start();
      expect(result.tracker.isRecording, isTrue);
      result.clock.advance(const Duration(minutes: 1));
      await result.tracker.stop();
      expect(result.store.written, hasLength(1));
      expect(result.store.written.single.effectiveSeconds, 60);
    });
  });

  group('活跃与空闲', () {
    test('持续交互 → 全部时间计入', () async {
      final result = _build();
      await result.tracker.start();
      // 每 30 秒交互一次，持续 5 分钟。
      for (int i = 0; i < 10; i++) {
        result.clock.advance(const Duration(seconds: 30));
        result.tracker.onInteraction();
      }
      await result.tracker.stop();
      expect(result.store.written, hasLength(1));
      expect(result.store.written.single.effectiveSeconds, 5 * 60);
    });

    test('空闲超阈 → 只算到最后交互 + 阈值', () async {
      final result = _build(idleMinutes: 5);
      await result.tracker.start();
      // 先读 2 分钟（有交互）。
      result.clock.advance(const Duration(minutes: 2));
      result.tracker.onInteraction();
      // 然后离开 30 分钟，期间 tick 会先把区间收到「最后交互 + 5 分钟」。
      for (int i = 0; i < 30; i++) {
        result.clock.advance(const Duration(minutes: 1));
        await result.tracker.tick();
      }
      await result.tracker.stop();
      // 有效时长 = 2 分钟（到交互点）+ 5 分钟（阈值） = 7 分钟。
      final int total = result.store.written.fold<int>(
        0,
        (int sum, ReadingSessionDraft d) => sum + d.effectiveSeconds,
      );
      expect(total, 7 * 60, reason: '空闲超出阈值的时间不得计入');
    });

    test('空闲暂停后恢复交互 → 继续累计（不再补回暂停的时间）', () async {
      final result = _build(idleMinutes: 2);
      await result.tracker.start();
      result.clock.advance(const Duration(minutes: 1));
      result.tracker.onInteraction();
      // 空闲 10 分钟（超 2 分钟阈值）。
      result.clock.advance(const Duration(minutes: 10));
      await result.tracker.tick();
      // 恢复交互，再读 1 分钟。
      result.tracker.onInteraction();
      result.clock.advance(const Duration(minutes: 1));
      result.tracker.onInteraction();
      await result.tracker.stop();
      final int total = result.store.written.fold<int>(
        0,
        (int sum, ReadingSessionDraft d) => sum + d.effectiveSeconds,
      );
      // 1 分钟 + 2 分钟阈值 + 1 分钟 = 4 分钟。
      expect(total, 4 * 60);
    });

    test('打开后不移动鼠标 → 阈值内的静读仍算阅读（打开本身就是一次活跃）', () async {
      // 这一条把「活跃」的起点钉住：打开详情页是用户动作，因此前 5 分钟（默认阈值）
      // 内即使没有任何指针/键盘事件，也仍是在读。若要等到第一次鼠标移动才开始计时，
      // 「打开文章静静读五分钟」会被整段丢掉——而它正是最常见的阅读形态。
      final result = _build(idleMinutes: 5);
      await result.tracker.start();
      result.clock.advance(const Duration(minutes: 3));
      await result.tracker.tick();
      await result.tracker.stop();
      expect(result.store.written, hasLength(1));
      expect(result.store.written.single.effectiveSeconds, 3 * 60);
    });

    test('打开后一直不交互且超过阈值 → 只算到打开时刻 + 阈值', () async {
      final result = _build(idleMinutes: 5);
      await result.tracker.start();
      // 30 分钟内不碰它。
      for (int i = 0; i < 30; i++) {
        result.clock.advance(const Duration(minutes: 1));
        await result.tracker.tick();
      }
      await result.tracker.stop();
      final int total = result.store.written.fold<int>(
        0,
        (int sum, ReadingSessionDraft d) => sum + d.effectiveSeconds,
      );
      expect(total, 5 * 60, reason: '超过阈值的时间不得计入');
    });
  });

  group('前台可见性', () {
    test('失焦立即暂停，且不把离开的时间补回来', () async {
      final result = _build();
      await result.tracker.start();
      result.clock.advance(const Duration(minutes: 1));
      result.tracker.onInteraction();
      // 失焦：这一段时间到此为止。
      result.tracker.onVisibilityChanged(false);
      result.clock.advance(const Duration(minutes: 20));
      // 重新可见，再读 1 分钟。
      result.tracker.onVisibilityChanged(true);
      result.clock.advance(const Duration(minutes: 1));
      result.tracker.onInteraction();
      await result.tracker.stop();
      final int total = result.store.written.fold<int>(
        0,
        (int sum, ReadingSessionDraft d) => sum + d.effectiveSeconds,
      );
      expect(total, 2 * 60, reason: '离开的 20 分钟不得计入');
    });

    test('重复投递同一种可见性变化不产生重复时间', () async {
      final result = _build();
      await result.tracker.start();
      for (int i = 0; i < 5; i++) {
        result.clock.advance(const Duration(seconds: 10));
        result.tracker.onInteraction();
        result.tracker.onVisibilityChanged(true);
      }
      await result.tracker.stop();
      expect(result.store.written.single.effectiveSeconds, 50);
    });

    test('start 幂等：重复 start 不重置计时', () async {
      final result = _build();
      await result.tracker.start();
      result.clock.advance(const Duration(seconds: 40));
      await result.tracker.start();
      result.clock.advance(const Duration(seconds: 20));
      await result.tracker.stop();
      expect(result.store.written.single.effectiveSeconds, 60);
    });
  });

  group('落库时机', () {
    test('周期 flush：到间隔就把已结束的区间写出去', () async {
      final result = _build(flushInterval: const Duration(seconds: 30));
      await result.tracker.start();
      result.clock.advance(const Duration(seconds: 20));
      expect(await result.tracker.tick(), isFalse, reason: '未到间隔');
      expect(result.store.written, isEmpty);
      result.clock.advance(const Duration(seconds: 20));
      expect(await result.tracker.tick(), isTrue);
      expect(result.store.written, hasLength(1));
      expect(result.store.written.single.effectiveSeconds, 40);
      // flush 后继续累计，第二段仍会被写出来。
      result.clock.advance(const Duration(seconds: 20));
      await result.tracker.stop();
      final int total = result.store.written.fold<int>(
        0,
        (int sum, ReadingSessionDraft d) => sum + d.effectiveSeconds,
      );
      expect(total, 60);
    });

    test('stop 收尾：不足一个 flush 间隔的时间也会落库', () async {
      final result = _build(flushInterval: const Duration(hours: 1));
      await result.tracker.start();
      result.clock.advance(const Duration(seconds: 15));
      expect(await result.tracker.stop(), isTrue);
      expect(result.store.written.single.effectiveSeconds, 15);
    });

    test('stop 幂等：第二次 stop 不重复写', () async {
      final result = _build();
      await result.tracker.start();
      result.clock.advance(const Duration(seconds: 30));
      await result.tracker.stop();
      await result.tracker.stop();
      expect(result.store.written, hasLength(1));
    });

    test('写入失败后不重试同一段时间（丢一段好过记重复）', () async {
      final result = _build();
      await result.tracker.start();
      result.clock.advance(const Duration(minutes: 1));
      result.store.failWrites = true;
      expect(await result.tracker.stop(), isFalse);
      expect(result.store.written, isEmpty);
      // 再 flush 一次也不会把上一段重新写进去。
      result.store.failWrites = false;
      expect(await result.tracker.flush(), isFalse);
      expect(result.store.written, isEmpty);
    });
  });

  group('跨午夜（端到端）', () {
    test('一次跨越当地午夜的阅读被拆成两行，分属两天', () async {
      final _RecordingStore store = _RecordingStore();
      // 起点：当地 21 日 23:50（= 21 日 15:50 UTC）。
      final FakeClock clock = FakeClock(
        start: DateTime.utc(2026, 9, 21, 15, 50),
      );
      final ReadingSessionTracker tracker = ReadingSessionTracker(
        articleId: 9,
        stats: store,
        settings: _FixedSettings(enabled: true),
        clock: clock,
        zone: shanghai,
        flushInterval: const Duration(hours: 1),
      );
      await tracker.start();
      // 读 20 分钟（跨过当地午夜）。
      for (int i = 0; i < 4; i++) {
        clock.advance(const Duration(minutes: 5));
        tracker.onInteraction();
      }
      await tracker.stop();
      expect(store.written, hasLength(2), reason: '跨午夜必须拆成两行');
      expect(store.written[0].localDate, '2026-09-21');
      expect(store.written[0].effectiveSeconds, 10 * 60);
      expect(store.written[1].localDate, '2026-09-22');
      expect(store.written[1].effectiveSeconds, 10 * 60);
    });
  });
}
