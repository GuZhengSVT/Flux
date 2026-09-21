// T023：阅读会话与统计的领域规则（纯函数，假时钟/假时区）。
//
// 这一层是「跨午夜拆分」「空闲封顶」「按本地日期归属」三条规则的唯一实现处，
// 因此这里逐条钉住它们：
//   * 跨午夜拆分（含三时段、正好落在午夜、跨多天）；
//   * 空闲封顶（阈值内全算、超阈只算到阈值、无交互不算）；
//   * 归属（按**会话时区**而不是进程时区；用户旅行后历史不漂移）；
//   * 聚合（同一本地日期合并、亚秒区间丢弃、日期键格式）。
//
// 时区用 FixedOffsetZone 注入：这让我们能在**不改动进程时区**的前提下验证一个
// UTC-5 的会话如何落到本地日期上——直接依赖 DateTime.toLocal 做不到这一点。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:flux/core/core.dart';

/// UTC+8（Asia/Shanghai，无夏令时）。
const SessionLocalZone shanghai = FixedOffsetZone(
  Duration(hours: 8),
  ianaName: 'Asia/Shanghai',
);

/// UTC-5（无夏令时的固定偏移）。
const SessionLocalZone minusFive = FixedOffsetZone(
  Duration(hours: -5),
  ianaName: 'UTC-05',
);

void main() {
  group('时区换算（读数的编码约定）', () {
    test('UTC → 当地读数：字段即当地墙钟，与进程时区无关', () {
      final DateTime local = shanghai.toLocal(
        DateTime.utc(2026, 9, 21, 16, 30),
      );
      // 16:30 UTC 在上海是次日 00:30。
      expect(local.year, 2026);
      expect(local.month, 9);
      expect(local.day, 22);
      expect(local.hour, 0);
      expect(local.minute, 30);
    });

    test('当地读数 → UTC：与 toLocal 互逆', () {
      final DateTime instant = DateTime.utc(2026, 9, 21, 16, 30);
      final DateTime roundTrip = shanghai.toUtc(shanghai.toLocal(instant));
      expect(roundTrip, instant);
    });

    test('负偏移同样正确（UTC-5 的当天与 UTC 不同日）', () {
      // 2026-09-22 02:00 UTC 在 UTC-5 是 9 月 21 日 21:00。
      final DateTime local = minusFive.toLocal(DateTime.utc(2026, 9, 22, 2));
      expect(local.day, 21);
      expect(local.hour, 21);
    });
  });

  group('跨午夜拆分', () {
    test('一个区间跨一次午夜 → 两段，分属两个本地日期', () {
      // 上海当地 23:30 → 次日 00:30。
      final ReadingInterval interval = ReadingInterval(
        start: DateTime.utc(2026, 9, 21, 15, 30),
        end: DateTime.utc(2026, 9, 21, 16, 30),
      );
      final List<({DateTime start, DateTime end})> parts =
          splitIntervalByLocalMidnight(interval, shanghai);
      expect(parts, hasLength(2));
      // 第一段在当地 21 日，第二段在 22 日。
      expect(localDateKey(shanghai.toLocal(parts[0].start)), '2026-09-21');
      expect(localDateKey(shanghai.toLocal(parts[1].start)), '2026-09-22');
      // 拼起来正好是原区间（不丢不重）。
      expect(parts.first.start, interval.start);
      expect(parts.last.end, interval.end);
      expect(parts[0].end, parts[1].start);
    });

    test('跨两天的区间 → 三段', () {
      final ReadingInterval interval = ReadingInterval(
        start: DateTime.utc(2026, 9, 21, 15, 0), // 当地 23:00 (21 日)
        end: DateTime.utc(2026, 9, 22, 17, 0), // 当地次日 01:00 (23 日)
      );
      final List<({DateTime start, DateTime end})> parts =
          splitIntervalByLocalMidnight(interval, shanghai);
      expect(parts, hasLength(3));
      expect(
        parts
            .map(
              (({DateTime start, DateTime end}) p) =>
                  localDateKey(shanghai.toLocal(p.start)),
            )
            .toList(),
        <String>['2026-09-21', '2026-09-22', '2026-09-23'],
      );
    });

    test('区间正好在午夜开始 → 不产生前一日的空段', () {
      // 当地 22 日 00:00 开始（= 21 日 16:00 UTC）。
      final ReadingInterval interval = ReadingInterval(
        start: DateTime.utc(2026, 9, 21, 16),
        end: DateTime.utc(2026, 9, 21, 17),
      );
      final List<({DateTime start, DateTime end})> parts =
          splitIntervalByLocalMidnight(interval, shanghai);
      expect(parts, hasLength(1));
      expect(localDateKey(shanghai.toLocal(parts.single.start)), '2026-09-22');
    });

    test('完全在同一天内 → 单段', () {
      final ReadingInterval interval = ReadingInterval(
        start: DateTime.utc(2026, 9, 21, 2),
        end: DateTime.utc(2026, 9, 21, 3),
      );
      final List<({DateTime start, DateTime end})> parts =
          splitIntervalByLocalMidnight(interval, shanghai);
      expect(parts, hasLength(1));
      expect(localDateKey(shanghai.toLocal(parts.single.start)), '2026-09-21');
    });
  });

  group('会话草案（拆日 + 同日合并）', () {
    test('跨午夜产生两行，各带自己的 local_date 与秒数', () {
      final List<ReadingSessionDraft> drafts = buildSessionDrafts(
        articleId: 7,
        intervals: <ReadingInterval>[
          ReadingInterval(
            start: DateTime.utc(2026, 9, 21, 15, 30),
            end: DateTime.utc(2026, 9, 21, 16, 30),
          ),
        ],
        zone: shanghai,
      );
      expect(drafts, hasLength(2));
      expect(drafts[0].localDate, '2026-09-21');
      expect(drafts[0].effectiveSeconds, 30 * 60);
      expect(drafts[1].localDate, '2026-09-22');
      expect(drafts[1].effectiveSeconds, 30 * 60);
      // 两行都记同一篇文章与同一时区。
      expect(drafts.every((ReadingSessionDraft d) => d.articleId == 7), isTrue);
      expect(
        drafts.every((ReadingSessionDraft d) => d.timeZone == 'Asia/Shanghai'),
        isTrue,
      );
    });

    test('同一本地日期的多个区间合并为一行（空闲暂停不制造碎片行）', () {
      final List<ReadingSessionDraft> drafts = buildSessionDrafts(
        articleId: 1,
        intervals: <ReadingInterval>[
          ReadingInterval(
            start: DateTime.utc(2026, 9, 21, 2),
            end: DateTime.utc(2026, 9, 21, 2, 10),
          ),
          // 中间空闲 20 分钟（不计入），恢复后再读 5 分钟。
          ReadingInterval(
            start: DateTime.utc(2026, 9, 21, 2, 30),
            end: DateTime.utc(2026, 9, 21, 2, 35),
          ),
        ],
        zone: shanghai,
      );
      expect(drafts, hasLength(1), reason: '同一天只应有一行');
      expect(drafts.single.effectiveSeconds, 15 * 60);
      // 跨度是「最早开始 → 最晚结束」，但有效秒数只含活跃时间。
      expect(drafts.single.startedAt, DateTime.utc(2026, 9, 21, 2));
      expect(drafts.single.endedAt, DateTime.utc(2026, 9, 21, 2, 35));
      expect(drafts.single.effectiveSeconds, lessThan(35 * 60));
    });

    test('没有区间 → 没有行（关闭统计或不活跃时不写 0 值行）', () {
      expect(
        buildSessionDrafts(
          articleId: 1,
          intervals: const <ReadingInterval>[],
          zone: shanghai,
        ),
        isEmpty,
      );
    });

    test('亚秒区间被丢弃（不产生 0 秒的噪声行）', () {
      final List<ReadingSessionDraft> drafts = buildSessionDrafts(
        articleId: 1,
        intervals: <ReadingInterval>[
          ReadingInterval(
            start: DateTime.utc(2026, 9, 21, 2, 0, 0),
            end: DateTime.utc(2026, 9, 21, 2, 0, 0, 500),
          ),
        ],
        zone: shanghai,
      );
      expect(drafts, isEmpty);
    });
  });

  group('空闲封顶', () {
    const Duration threshold = Duration(minutes: 5);

    test('阈值内的等待全算', () {
      final DateTime last = DateTime.utc(2026, 9, 21, 2);
      final DateTime? end = effectiveActiveEnd(
        lastActive: last,
        now: last.add(const Duration(minutes: 3)),
        idleThreshold: threshold,
      );
      expect(end, last.add(const Duration(minutes: 3)));
    });

    test('超过阈值只算到 lastActive + 阈值（超出的那段时间不算）', () {
      final DateTime last = DateTime.utc(2026, 9, 21, 2);
      final DateTime? end = effectiveActiveEnd(
        lastActive: last,
        now: last.add(const Duration(minutes: 40)),
        idleThreshold: threshold,
      );
      expect(end, last.add(threshold));
    });

    test('now 恰等于 lastActive → 返回 now（交互刚发生，这段仍有效）', () {
      final DateTime last = DateTime.utc(2026, 9, 21, 2);
      // 这一条是实测抓到的缺陷：第一版在 now == lastActive 时返回 null，于是所有
      // 「读完就停手」的会话都被整段丢掉。
      expect(
        effectiveActiveEnd(
          lastActive: last,
          now: last,
          idleThreshold: threshold,
        ),
        last,
      );
    });

    test('阈值为 0 或负 → 完全不算', () {
      final DateTime last = DateTime.utc(2026, 9, 21, 2);
      expect(
        effectiveActiveEnd(
          lastActive: last,
          now: last.add(const Duration(minutes: 1)),
          idleThreshold: Duration.zero,
        ),
        isNull,
      );
    });
  });

  group('本地日期键', () {
    test('个位数月日补零（字典序即时间序）', () {
      expect(localDateKey(DateTime.utc(2026, 1, 5)), '2026-01-05');
      expect(localDateKey(DateTime.utc(2026, 12, 31)), '2026-12-31');
    });

    test('字典序与时间序一致', () {
      final List<String> keys = <String>[
        localDateKey(DateTime.utc(2026, 9, 9)),
        localDateKey(DateTime.utc(2026, 9, 10)),
        localDateKey(DateTime.utc(2026, 10, 1)),
      ];
      final List<String> sorted = keys.toList()..sort();
      expect(sorted, keys);
    });
  });

  group('nextLocalMidnight', () {
    test('返回的是下一个当地午夜对应的 UTC 时刻', () {
      // 当地 21 日 23:30 → 下一个午夜是 22 日 00:00（当地）= 21 日 16:00 UTC。
      final DateTime midnight = nextLocalMidnight(
        DateTime.utc(2026, 9, 21, 15, 30),
        shanghai,
      );
      expect(midnight, DateTime.utc(2026, 9, 21, 16));
    });

    test('跨月末/年末正确（日期归一化）', () {
      // 当地 12 月 31 日 22:00 → 次年 1 月 1 日 00:00 当地。
      final DateTime midnight = nextLocalMidnight(
        DateTime.utc(2026, 12, 31, 14),
        shanghai,
      );
      expect(midnight, DateTime.utc(2026, 12, 31, 16));
      expect(localDateKey(shanghai.toLocal(midnight)), '2027-01-01');
    });
  });
}
