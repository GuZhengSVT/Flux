// 每日定时总结的**时间规则**（T040；架构 4.4「定时默认每天设备当地时间 20:00、启用开关默认开；
// 后台尽力执行，不要求系统精确定时；错过计划后在下一次可运行时仅补当日一次，不补跑所有历史
// 日期；当天成功版本存在则不重复自动收费」、D-08、SET-056/057）。
//
// 这一层是**纯函数与纯数据**：它只回答「现在该不该跑、为什么、下一次什么时候」。真正出网、
// 读库、跑任务的部分住在 features/news/application 的调度器里。这样切分的理由与 T037 的
// 输入快照同一条：定时规则最容易出错的地方全是**时间边界**（到点、错过、跨日、换时区），
// 而这些边界必须能用假时钟逐秒断言，不能靠「等一个真实的 20:00」。
library;

import 'reading_session.dart';

/// SET-057 的默认执行时间（设备当地时间 20:00）。
const String kNewsDefaultDailyTime = '20:00';

/// 定时的「到点」判定里，把多晚算作「补跑」而不是「准点」的窗口。
///
/// 一分钟是调度器的检查周期：在周期内到达算准点，越过后就是一次错过的补跑。这个区别只
/// 影响界面文案与诊断（「按计划运行」vs「补跑今天错过的计划」），不改变动作。
const Duration kNewsScheduledOnTimeWindow = Duration(minutes: 1);

/// 定时总结的**策略**（来自 SET-056 的设备开关、SET-057 的时间与当前设备时区）。
final class DailyNewsPolicy {
  /// 构造策略。
  const DailyNewsPolicy({
    required this.enabled,
    required this.timeOfDayMinutes,
    required this.zone,
  });

  /// SET-056：本设备是否自动定时总结（默认**开**）。
  final bool enabled;

  /// SET-057 的执行时间（当天的第几分钟；20:00 = 1200）。
  final int timeOfDayMinutes;

  /// 当前设备时区（每次评估时取一次，因此用户换时区后下一次评估就按新时区算）。
  final SessionLocalZone zone;

  /// `HH:mm` 形态的时间（界面显示与 SET-057 的写回都用它）。
  String get timeOfDayLabel => formatTimeOfDay(timeOfDayMinutes);

  /// 复制并覆盖部分字段。
  DailyNewsPolicy copyWith({
    bool? enabled,
    int? timeOfDayMinutes,
    SessionLocalZone? zone,
  }) => DailyNewsPolicy(
    enabled: enabled ?? this.enabled,
    timeOfDayMinutes: timeOfDayMinutes ?? this.timeOfDayMinutes,
    zone: zone ?? this.zone,
  );

  @override
  String toString() =>
      'DailyNewsPolicy(enabled=$enabled, at=$timeOfDayLabel, '
      'tz=${zone.ianaName})';
}

/// 本次评估的结论。
enum DailyNewsDueKind {
  /// SET-056 关闭：不做任何事（**保留**默认开启的偏好，只是这台设备现在不跑）。
  disabled,

  /// 缺少必要配置或首次费用告知未完成：显示「等待配置」，**不发任何请求**（D-08）。
  waitingConfiguration,

  /// 还没到点：只算出下一次时间，不做任何事。
  notDue,

  /// 到点（或今天已经过点且今天还没成功过）：应当运行一次。
  due,

  /// 今天已经有成功版本：**不重复自动收费**（手动重新生成不受此限）。
  alreadyGeneratedToday;

  /// 是否应当发起一次运行。
  bool get shouldRun => this == DailyNewsDueKind.due;
}

/// 一次评估的完整结论（界面与诊断都用它，不在别处重算时间）。
final class DailyNewsDue {
  /// 构造结论。
  const DailyNewsDue({
    required this.kind,
    required this.localDate,
    required this.timeZone,
    this.nextRunUtc,
    this.scheduledAtUtc,
    this.catchUp = false,
    this.waitingReason,
  });

  /// 结论。
  final DailyNewsDueKind kind;

  /// 评估时的设备本地日期键（运行归属它）。
  final String localDate;

  /// 评估时的设备时区（IANA 名称）。
  final String timeZone;

  /// 下一次应当运行的时刻（UTC）；关闭时为 null。
  final DateTime? nextRunUtc;

  /// 今天计划运行的时刻（UTC）；关闭时为 null。
  final DateTime? scheduledAtUtc;

  /// 本次是否为「错过后补跑今天这一次」（而不是准点触发）。
  final bool catchUp;

  /// 等待配置的具体原因（结构标识，不进 UI 文案）。
  final String? waitingReason;

  @override
  String toString() =>
      'DailyNewsDue(${kind.name} $localDate/$timeZone '
      'next=${nextRunUtc?.toIso8601String()} catchUp=$catchUp)';
}

/// 解析 `HH:mm` 为「当天的第几分钟」；非法输入返回 null（**不猜**默认值）。
///
/// 不猜的理由：用户把 20:00 改成一个手误的值时，静默回退到 20:00 会让界面显示一个
/// 用户从未设置过的时间，而真正出问题的是那次写入。SET-057 的注册表已经用正则约束了
/// 取值域，这里再解析一次是为了让「库里有一个不合规的历史值」这件事有一个明确的答案。
int? parseTimeOfDayMinutes(String? raw) {
  final String? text = raw?.trim();
  if (text == null || text.isEmpty) {
    return null;
  }
  final List<String> parts = text.split(':');
  if (parts.length != 2) {
    return null;
  }
  final int? hour = int.tryParse(parts[0]);
  final int? minute = int.tryParse(parts[1]);
  if (hour == null || minute == null) {
    return null;
  }
  if (hour < 0 || hour > 23 || minute < 0 || minute > 59) {
    return null;
  }
  return hour * 60 + minute;
}

/// 把「当天的第几分钟」格式化为 `HH:mm`（越界值先归一到 0–1439）。
String formatTimeOfDay(int minutes) {
  final int clamped = minutes < 0 ? 0 : (minutes > 1439 ? 1439 : minutes);
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(clamped ~/ 60)}:${two(clamped % 60)}';
}

/// 评估「现在该不该跑这次定时总结」。
///
/// 判定顺序是刻意的，每一步都对应一处文档要求：
///
///   1) **关闭优先**：SET-056 关掉时连「等待配置」都不显示（用户已经明确说这台设备不要
///      自动跑，还去提示他配置缺失是打扰）；
///   2) **等待配置先于到点判定**：未配置时任务状态是 `waitingConfiguration`，它**不是**一次
///      失败的运行，因此不能等到点了才去检查——否则界面在 20:00 之前一直显示「按计划运行」，
///      到点那一刻才变成「等待配置」，用户会以为配置是刚刚坏的；
///   3) **今天已成功则不再自动跑**（当天成功版本存在则不重复自动收费）。判定用「今天」
///      而不是「最近一次运行」，因此昨天成功过不影响今天；
///   4) **到点即跑**：用 `now >= 计划时刻` 而不是「恰好等于」。这一条同时实现了两件事——
///      运行中每分钟检查到点，以及应用被关掉后启动时补跑当天错过的那个时点；
///   5) **跨日不补**：昨天错过就放弃。它不是靠额外的「昨天」判断，而是靠「今天还没到点且
///      今天没成功过 → notDue」自然成立：昨天的那次机会已经随着日期键翻页消失了。
DailyNewsDue evaluateDailyNewsDue({
  required DateTime nowUtc,
  required DailyNewsPolicy policy,
  required bool ready,
  String? waitingReason,
  String? completedLocalDate,
  DateTime? lastAttemptUtc,
}) {
  final DateTime utc = nowUtc.toUtc();
  final DateTime local = policy.zone.toLocal(utc);
  final String today = localDateKey(local);
  if (!policy.enabled) {
    return DailyNewsDue(
      kind: DailyNewsDueKind.disabled,
      localDate: today,
      timeZone: policy.zone.ianaName,
    );
  }
  if (!ready) {
    return DailyNewsDue(
      kind: DailyNewsDueKind.waitingConfiguration,
      localDate: today,
      timeZone: policy.zone.ianaName,
      nextRunUtc: _scheduledUtc(local, policy.timeOfDayMinutes, policy.zone),
      scheduledAtUtc: _scheduledUtc(
        local,
        policy.timeOfDayMinutes,
        policy.zone,
      ),
      waitingReason: waitingReason,
    );
  }
  final DateTime scheduled = _scheduledUtc(
    local,
    policy.timeOfDayMinutes,
    policy.zone,
  );
  if (completedLocalDate == today) {
    return DailyNewsDue(
      kind: DailyNewsDueKind.alreadyGeneratedToday,
      localDate: today,
      timeZone: policy.zone.ianaName,
      // 今天已经跑过：下一次是**明天**的同一个时点。
      nextRunUtc: _scheduledUtc(
        local.add(const Duration(days: 1)),
        policy.timeOfDayMinutes,
        policy.zone,
      ),
      scheduledAtUtc: scheduled,
    );
  }
  if (utc.isBefore(scheduled)) {
    return DailyNewsDue(
      kind: DailyNewsDueKind.notDue,
      localDate: today,
      timeZone: policy.zone.ianaName,
      nextRunUtc: scheduled,
      scheduledAtUtc: scheduled,
    );
  }
  final Duration late = utc.difference(scheduled);
  return DailyNewsDue(
    kind: DailyNewsDueKind.due,
    localDate: today,
    timeZone: policy.zone.ianaName,
    nextRunUtc: scheduled,
    scheduledAtUtc: scheduled,
    catchUp:
        late > kNewsScheduledOnTimeWindow ||
        (lastAttemptUtc != null && lastAttemptUtc.isBefore(scheduled)),
  );
}

/// 当天的计划时刻（当地 `HH:mm`）对应的 UTC 时刻。
///
/// 用「当地读数的年月日 + 时分」交给 [SessionLocalZone.toUtc] 换算，因此夏令时切换日的
/// 偏移由时区实现决定，而不是由这里写死的偏移算出来。
DateTime _scheduledUtc(
  DateTime localWallClock,
  int timeOfDayMinutes,
  SessionLocalZone zone,
) => zone
    .toUtc(
      DateTime.utc(
        localWallClock.year,
        localWallClock.month,
        localWallClock.day,
        timeOfDayMinutes ~/ 60,
        timeOfDayMinutes % 60,
      ),
    )
    .toUtc();
