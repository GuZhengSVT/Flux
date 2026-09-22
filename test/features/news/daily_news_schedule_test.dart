// T040：定时规则（架构 4.4、D-08、SET-056/057、手册 6.3「定时」节）。
//
// 手册点名的四条逐条断言：**默认开但初始不联网**、**允许后按时区运行**、**错过只补当日一次**、
// **应用终止不会伪称后台完成**；外加跨日不补、今日已成功不重复、换时区重算、时间解析边界。
//
// 时间规则是纯函数，因此这些断言不需要真实等待或真实网络。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:flux/core/core.dart';

/// 上海（固定 +8）。
const SessionLocalZone shanghai = FixedOffsetZone(
  Duration(hours: 8),
  ianaName: 'Asia/Shanghai',
);

/// 纽约（固定 -5，无夏令时——与工程「不引入时区库」的口径一致）。
const SessionLocalZone newYork = FixedOffsetZone(
  Duration(hours: -5),
  ianaName: 'America/New_York',
);

DailyNewsPolicy policy({
  bool enabled = true,
  int minutes = 20 * 60,
  SessionLocalZone zone = shanghai,
}) => DailyNewsPolicy(enabled: enabled, timeOfDayMinutes: minutes, zone: zone);

void main() {
  group('时间解析与格式化（SET-057、SET-058 的展示口径）', () {
    test('HH:mm 解析：合法值、边界值、非法值不猜', () {
      expect(parseTimeOfDayMinutes('20:00'), 1200);
      expect(parseTimeOfDayMinutes('00:00'), 0);
      expect(parseTimeOfDayMinutes('23:59'), 1439);
      expect(parseTimeOfDayMinutes(' 7:05 '), 425);
      // 非法值返回 null，**不**静默回退到默认时间（那会让界面显示一个用户从未设过的时间）。
      expect(parseTimeOfDayMinutes('24:00'), isNull);
      expect(parseTimeOfDayMinutes('12:60'), isNull);
      expect(parseTimeOfDayMinutes('2000'), isNull);
      expect(parseTimeOfDayMinutes('ab:cd'), isNull);
      expect(parseTimeOfDayMinutes(''), isNull);
      expect(parseTimeOfDayMinutes(null), isNull);
    });

    test('格式化补齐两位并在越界时归一到合法范围', () {
      expect(formatTimeOfDay(1200), '20:00');
      expect(formatTimeOfDay(0), '00:00');
      expect(formatTimeOfDay(425), '07:05');
      expect(formatTimeOfDay(1439), '23:59');
      expect(formatTimeOfDay(-10), '00:00');
      expect(formatTimeOfDay(99999), '23:59');
    });
  });

  group('默认开但初始不联网（D-08、SET-056）', () {
    test('SET-056 默认开，缺配置时是 waitingConfiguration 且不发请求', () {
      // 当地 2026-09-22 19:00（还没到 20:00，但缺配置优先）。
      final DailyNewsDue due = evaluateDailyNewsDue(
        nowUtc: DateTime.utc(2026, 9, 22, 11),
        policy: policy(),
        ready: false,
        waitingReason: 'noEnabledModel',
      );
      expect(due.kind, DailyNewsDueKind.waitingConfiguration);
      expect(due.kind.shouldRun, isFalse, reason: '未配置不发任何请求');
      expect(due.waitingReason, 'noEnabledModel');
      // 仍然给出下一次时间：界面要在「等待配置」的同时说清「配置好后会什么时候跑」。
      expect(due.nextRunUtc, DateTime.utc(2026, 9, 22, 12));
      expect(due.scheduledAtUtc, DateTime.utc(2026, 9, 22, 12));
    });

    test('等待配置先于到点判定：还没到点也是 waitingConfiguration，不是 notDue', () {
      final DailyNewsDue early = evaluateDailyNewsDue(
        nowUtc: DateTime.utc(2026, 9, 22, 1), // 当地 09:00
        policy: policy(),
        ready: false,
        waitingReason: 'costNotice',
      );
      // 若顺序反过来（先判到点），用户在 20:00 之前会看到「按计划运行」、到点那一刻才变成
      // 「等待配置」，从而以为配置是刚刚坏的。
      expect(early.kind, DailyNewsDueKind.waitingConfiguration);
    });

    test('SET-056 关闭时不显示等待配置（连提示都不打扰）', () {
      final DailyNewsDue due = evaluateDailyNewsDue(
        nowUtc: DateTime.utc(2026, 9, 22, 13),
        policy: policy(enabled: false),
        ready: false,
        waitingReason: 'costNotice',
      );
      expect(due.kind, DailyNewsDueKind.disabled);
      expect(due.nextRunUtc, isNull);
    });
  });

  group('允许后按时区运行（架构 4.4）', () {
    test('上海：当地 19:59 未到点，20:00 到点', () {
      final DailyNewsDue before = evaluateDailyNewsDue(
        nowUtc: DateTime.utc(2026, 9, 22, 11, 59),
        policy: policy(),
        ready: true,
      );
      expect(before.kind, DailyNewsDueKind.notDue);
      expect(before.nextRunUtc, DateTime.utc(2026, 9, 22, 12));

      final DailyNewsDue at = evaluateDailyNewsDue(
        nowUtc: DateTime.utc(2026, 9, 22, 12),
        policy: policy(),
        ready: true,
      );
      expect(at.kind, DailyNewsDueKind.due);
      expect(at.catchUp, isFalse, reason: '准点触发不是补跑');
    });

    test('同一时刻在两个时区给出不同的归属日期与计划时刻', () {
      // UTC 2026-09-22 01:00 = 上海 09:00（当天）、纽约 2026-09-21 20:00（前一天，且刚好到点）。
      final DateTime now = DateTime.utc(2026, 9, 22, 1);
      final DailyNewsDue inShanghai = evaluateDailyNewsDue(
        nowUtc: now,
        policy: policy(zone: shanghai),
        ready: true,
      );
      final DailyNewsDue inNewYork = evaluateDailyNewsDue(
        nowUtc: now,
        policy: policy(zone: newYork),
        ready: true,
      );
      expect(inShanghai.localDate, '2026-09-22');
      expect(inShanghai.kind, DailyNewsDueKind.notDue);
      expect(inNewYork.localDate, '2026-09-21');
      expect(inNewYork.kind, DailyNewsDueKind.due);
    });

    test('换时区后重算：同一次检查在新时区下到点', () {
      final DateTime now = DateTime.utc(2026, 9, 22, 1);
      expect(
        evaluateDailyNewsDue(
          nowUtc: now,
          policy: policy(zone: shanghai),
          ready: true,
        ).kind,
        DailyNewsDueKind.notDue,
      );
      expect(
        evaluateDailyNewsDue(
          nowUtc: now,
          policy: policy(zone: newYork),
          ready: true,
        ).kind,
        DailyNewsDueKind.due,
      );
    });

    test('自定义时间生效（SET-057 不是硬编码 20:00）', () {
      final DailyNewsDue due = evaluateDailyNewsDue(
        // 当地 07:00 = UTC 前一日 23:00。
        nowUtc: DateTime.utc(2026, 9, 21, 23),
        policy: policy(minutes: 7 * 60),
        ready: true,
      );
      expect(due.kind, DailyNewsDueKind.due);
      expect(due.localDate, '2026-09-22');
    });
  });

  group('错过只补当日一次（架构 4.4）', () {
    test('晚点很多时是补跑（catchUp 为真）', () {
      final DailyNewsDue due = evaluateDailyNewsDue(
        // 当地 22:30，错过 20:00。
        nowUtc: DateTime.utc(2026, 9, 22, 14, 30),
        policy: policy(),
        ready: true,
      );
      expect(due.kind, DailyNewsDueKind.due);
      expect(due.catchUp, isTrue);
    });

    test('跨日不补：昨日错过、今天还没到点 → notDue（不是补跑）', () {
      // 设备在 UTC+8，当地已是 2026-09-23 10:00（昨天 20:00 那次早就过了）。
      final DailyNewsDue due = evaluateDailyNewsDue(
        nowUtc: DateTime.utc(2026, 9, 23, 2),
        policy: policy(),
        ready: true,
      );
      expect(due.localDate, '2026-09-23');
      expect(due.kind, DailyNewsDueKind.notDue);
      // 今天的计划时刻，而不是昨天那次——昨天的机会随日期键翻页消失。
      expect(due.nextRunUtc, DateTime.utc(2026, 9, 23, 12));
    });

    test('只有次日已过点时才会补次日那一次（每天最多一次）', () {
      final DailyNewsDue due = evaluateDailyNewsDue(
        nowUtc: DateTime.utc(2026, 9, 23, 14), // 当地 22:00
        policy: policy(),
        ready: true,
      );
      expect(due.localDate, '2026-09-23');
      expect(due.kind, DailyNewsDueKind.due);
      expect(due.catchUp, isTrue);
    });
  });

  group('当天已成功不重复自动收费', () {
    test('今天有成功版本 → alreadyGeneratedToday，且下一次是明天', () {
      final DailyNewsDue due = evaluateDailyNewsDue(
        nowUtc: DateTime.utc(2026, 9, 22, 13), // 当地 21:00，已过点
        policy: policy(),
        ready: true,
        completedLocalDate: '2026-09-22',
      );
      expect(due.kind, DailyNewsDueKind.alreadyGeneratedToday);
      expect(due.kind.shouldRun, isFalse);
      expect(due.nextRunUtc, DateTime.utc(2026, 9, 23, 12));
    });

    test('昨天成功不影响今天（判定看日期键，不看「最近一次运行」）', () {
      final DailyNewsDue due = evaluateDailyNewsDue(
        nowUtc: DateTime.utc(2026, 9, 22, 13),
        policy: policy(),
        ready: true,
        completedLocalDate: '2026-09-21',
      );
      expect(due.kind, DailyNewsDueKind.due);
    });

    test('已成功优先于「到点」：不会因为到点就再跑一次', () {
      final DailyNewsDue due = evaluateDailyNewsDue(
        nowUtc: DateTime.utc(2026, 9, 22, 12),
        policy: policy(),
        ready: true,
        completedLocalDate: '2026-09-22',
      );
      expect(due.kind, DailyNewsDueKind.alreadyGeneratedToday);
    });
  });

  group('应用终止不伪称后台完成（手册 6.3）', () {
    // 时间规则层不做「上一次任务被终止」的判断（那是调度器与 store 的事）：这里断言的是
    // **不会**因为上一次尝试存在就把今天当成已完成——否则一次被终止的任务会让当天再也不会
    // 自动跑（用户以为它跑过了），或者反过来被当成成功而不再收费保护失效。
    test('上次尝试过但今天没有成功版本 → 仍按未完成处理（可再跑）', () {
      final DailyNewsDue due = evaluateDailyNewsDue(
        nowUtc: DateTime.utc(2026, 9, 22, 13),
        policy: policy(),
        ready: true,
        lastAttemptUtc: DateTime.utc(2026, 9, 22, 12, 5),
      );
      expect(due.kind, DailyNewsDueKind.due);
      expect(due.catchUp, isTrue, reason: '到点前尝试过，现在是一次补跑');
    });

    test('当天已成功时，即便有过一次失败尝试也不重复跑', () {
      final DailyNewsDue due = evaluateDailyNewsDue(
        nowUtc: DateTime.utc(2026, 9, 22, 13),
        policy: policy(),
        ready: true,
        completedLocalDate: '2026-09-22',
        lastAttemptUtc: DateTime.utc(2026, 9, 22, 12, 30),
      );
      expect(due.kind, DailyNewsDueKind.alreadyGeneratedToday);
    });
  });

  group('策略复制与展示', () {
    test('copyWith 只覆盖给定字段', () {
      final DailyNewsPolicy base = policy();
      expect(base.timeOfDayLabel, '20:00');
      final DailyNewsPolicy off = base.copyWith(enabled: false);
      expect(off.enabled, isFalse);
      expect(off.timeOfDayMinutes, 1200);
      expect(off.zone.ianaName, 'Asia/Shanghai');
    });
  });
}
