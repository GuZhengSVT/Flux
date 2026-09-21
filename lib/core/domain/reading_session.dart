// 阅读会话的统计语义（T023；架构 5.3「清理、备份和统计」）。
//
// 架构口径原文：「统计首发本机有效阅读时长：前台可见且活跃时累计，失焦/锁屏/后台
// 暂停，5 分钟无交互暂停；按会话时区跨午夜拆分。它是估计，不是精确阅读证明。」
//
// 本文件只放**纯函数与值类型**（core 不带 Flutter/drift 依赖）：把「一次阅读期间的
// 哪些时间算数」与「这些时间如何归属到某个本地日期」这两件事从数据库与界面里剥出来，
// 使它们可以用假时钟与假时区做确定性验证。
//
// 三个刻意的设计：
//   1) **有效时间按区间（interval）表达，而不是一个秒数累加器**。空闲暂停要求
//      「最后交互后最多再算阈值那一段」，暂停后恢复又要重新起一段；用累加器写会把
//      「暂停发生在哪一刻」丢掉，也就无法正确处理跨午夜的拆分（跨夜时被暂停的区间
//      不能被算成连续时间）；
//   2) **归属日期在写入时算好并落库**（reading_sessions.local_date）。首发不做跨设备
//      相加，而用户旅行后历史会话必须仍归属当时的本地日期，因此归属依据是**会话发生
//      时的时区**，不是查询时的时区。查询端于是只剩一个按 local_date 的分组；
//   3) **时区是注入的**（SessionLocalZone），不是直接读设备。测试要能在不改动进程
//      时区的前提下验证跨午夜与跨天行为，而 DateTime.toLocal 只能取进程时区。
library;

/// 会话时区：把 UTC 与会话发生地的当地读数互转。
///
/// 为什么需要它，而不是直接用 DateTime.toLocal：设备时区是**进程级**的，测试无法在
/// 不改变整个进程的前提下构造「会话发生在 UTC+8、查询发生在别处」这类场景；而跨午夜
/// 拆分正是 T023 的必测项。把时区做成参数之后，「跨午夜」这件事就有了确定性的验证方式。
///
/// **读数的编码约定**（两个方法都必须遵守，否则跨时区测试会静默算错）：
/// 本接口传递的「当地读数」是一个**用 UTC 编码的日历字段**——只看它的年月日时分秒，
/// 不看它的时区标记。例如「UTC+8 的 2026-09-22 00:30」编码为
/// DateTime.utc(2026, 9, 22, 0, 30)。
///
/// 为什么不用「本地 DateTime」来表达读数：DateTime(y, m, d) 会被按**进程时区**解释。
/// 测试里用 FixedOffsetZone(UTC-5) 而进程在 UTC+8 时，两次解释叠加会得出错误偏移，
/// 而这类错误不会崩、只会把会话记到错误的日期上。用字段编码把「读数」与「时刻」分开，
/// 换算是唯一的、可断言的。
abstract interface class SessionLocalZone {
  /// IANA 名称（例如 Asia/Shanghai），随会话一起落库，便于解释历史归属。
  String get ianaName;

  /// UTC 时刻 → 该时区的当地读数（按上面的约定用 UTC 编码）。
  DateTime toLocal(DateTime utc);

  /// 当地读数（按上面的约定用 UTC 编码）→ UTC 时刻。
  ///
  /// 真实设备的实现必须处理夏令时：当地日期的零点在当地并不总是同一个 UTC 偏移，
  /// 因此拆分与归属都以「当地读数」为准，由本方法换算回 UTC。
  DateTime toUtc(DateTime wallClock);
}

/// 把一个时刻的日历字段重新编码为 UTC（丢掉时区标记，只保留读数）。
DateTime wallClockOf(DateTime instant) => DateTime.utc(
  instant.year,
  instant.month,
  instant.day,
  instant.hour,
  instant.minute,
  instant.second,
  instant.millisecond,
  instant.microsecond,
);

/// 固定偏移时区（测试与「设备时区不可读」时的兜底）。
///
/// 用**固定偏移**而不是查时区数据库：本工程不引入时区库依赖（架构 2.1 的依赖白名单），
/// 而真实的设备时区由平台实现提供；对无夏令时地区（中国大陆即如此），两者行为一致。
final class FixedOffsetZone implements SessionLocalZone {
  /// 按偏移构造。
  const FixedOffsetZone(this.offset, {this.ianaName = 'UTC'});

  /// 相对 UTC 的偏移。
  final Duration offset;

  @override
  final String ianaName;

  @override
  DateTime toLocal(DateTime utc) {
    // add 不会改动 isUtc 标记，因此把结果重新编码一次：得到的字段就是当地读数，
    // 与进程时区无关。
    return wallClockOf(utc.toUtc().add(offset));
  }

  @override
  DateTime toUtc(DateTime wallClock) => wallClock.subtract(offset);
}

/// 一段**已经算过是否活跃**的连续有效时间（UTC）。
///
/// 「有效」是调用方（tracker）的判定结果：失焦/后台/空闲超阈的时间既不会进入本类型，
/// 也不会以别的形式进入统计——不统计就是没有区间，而不是记一个 0。
final class ReadingInterval {
  /// 构造区间；结束必须晚于开始。
  ReadingInterval({required this.start, required this.end})
    : assert(end.isAfter(start), '有效区间的结束必须晚于开始');

  /// 开始（UTC）。
  final DateTime start;

  /// 结束（UTC）。
  final DateTime end;

  /// 时长。
  Duration get duration => end.difference(start);

  @override
  String toString() =>
      'ReadingInterval('
      '${start.toIso8601String()}..${end.toIso8601String()})';
}

/// 一条待落库的会话记录（已按本地日期拆好）。
final class ReadingSessionDraft {
  /// 构造草案。
  const ReadingSessionDraft({
    required this.articleId,
    required this.startedAt,
    required this.endedAt,
    required this.effectiveSeconds,
    required this.timeZone,
    required this.localDate,
  });

  /// 文章 id（会话仍以文章为单位，架构 5.1）。
  final int articleId;

  /// 本段开始（UTC）。
  final DateTime startedAt;

  /// 本段结束（UTC）。
  final DateTime endedAt;

  /// 有效秒数（只含活跃时间；空闲/失焦区间不在其中，因此可能小于跨度）。
  final int effectiveSeconds;

  /// 统计时区（IANA 名称）。
  final String timeZone;

  /// 设备本地日期键（Y-M-D，按 timeZone 计算）。
  final String localDate;

  @override
  String toString() =>
      'ReadingSessionDraft(article=$articleId, '
      '$localDate, ${effectiveSeconds}s)';
}

/// 一个本地日期键（YYYY-MM-DD）。
String localDateKey(DateTime localWallClock) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${localWallClock.year}-${two(localWallClock.month)}-'
      '${two(localWallClock.day)}';
}

/// 会话时区下一个「本地午夜」对应的 UTC 时刻。
///
/// 用「本地日期加一天的零点」而不是「加 24 小时」：夏令时切换日的时长不是 24 小时，
/// 而午夜边界要按**当地读数**定义，否则在切换日会把两天的会话算进同一天。
DateTime nextLocalMidnight(DateTime afterUtc, SessionLocalZone zone) {
  final DateTime local = zone.toLocal(afterUtc);
  // 日期加一天由 DateTime.utc 归一化（例如 9 月 30 日加一天是 10 月 1 日），
  // 这里只需要「下一天的零点」这个读数。
  return zone.toUtc(DateTime.utc(local.year, local.month, local.day + 1));
}

/// 把一个区间按本地午夜切成若干段（每段完全落在同一个本地日期内）。
///
/// 返回段按时间升序，且每段非空。区间跨 n 个午夜就切成 n+1 段。
List<({DateTime start, DateTime end})> splitIntervalByLocalMidnight(
  ReadingInterval interval,
  SessionLocalZone zone,
) {
  final List<({DateTime start, DateTime end})> parts =
      <({DateTime start, DateTime end})>[];
  DateTime cursor = interval.start;
  // 上限保护：即使时区实现异常（午夜不前移）也不会无限循环。
  int guard = 0;
  while (cursor.isBefore(interval.end)) {
    final DateTime midnight = nextLocalMidnight(cursor, zone);
    final DateTime partEnd = midnight.isBefore(interval.end)
        ? midnight
        : interval.end;
    if (partEnd.isAfter(cursor)) {
      parts.add((start: cursor, end: partEnd));
      cursor = partEnd;
    } else {
      // 午夜没有前移：把剩余时间作为最后一段收尾，而不是产出海量空行。
      parts.add((start: cursor, end: interval.end));
      cursor = interval.end;
    }
    guard++;
    if (guard > 3660) {
      break;
    }
  }
  return parts;
}

/// 把若干有效区间拆成待落库的会话行（同一本地日期合并为一行）。
///
/// 为什么按本地日期**合并**而不是每段一行：空闲暂停会让一次阅读产生很多短区间，
/// 逐段落库会把「读了一篇文章 20 分钟」写成几十行，既浪费空间也让按文章查看历史时
/// 难以阅读。合并保留「最早开始 / 最晚结束 / 有效秒数之和」，信息不丢——
/// 这正是 effectiveSeconds 与跨度分开存的意义。
List<ReadingSessionDraft> buildSessionDrafts({
  required int articleId,
  required List<ReadingInterval> intervals,
  required SessionLocalZone zone,
}) {
  final Map<String, ReadingSessionDraft> merged =
      <String, ReadingSessionDraft>{};
  for (final ReadingInterval interval in intervals) {
    for (final ({DateTime start, DateTime end}) part
        in splitIntervalByLocalMidnight(interval, zone)) {
      final int seconds = part.end.difference(part.start).inSeconds;
      if (seconds <= 0) {
        // 亚秒级区间不产生行：一行 0 秒的会话在热力图上不可见，却会让「按文章的
        // 历史」多出一条噪声。
        continue;
      }
      final String date = localDateKey(zone.toLocal(part.start));
      final ReadingSessionDraft? existing = merged[date];
      if (existing == null) {
        merged[date] = ReadingSessionDraft(
          articleId: articleId,
          startedAt: part.start,
          endedAt: part.end,
          effectiveSeconds: seconds,
          timeZone: zone.ianaName,
          localDate: date,
        );
        continue;
      }
      merged[date] = ReadingSessionDraft(
        articleId: articleId,
        startedAt: existing.startedAt.isBefore(part.start)
            ? existing.startedAt
            : part.start,
        endedAt: existing.endedAt.isAfter(part.end)
            ? existing.endedAt
            : part.end,
        effectiveSeconds: existing.effectiveSeconds + seconds,
        timeZone: zone.ianaName,
        localDate: date,
      );
    }
  }
  return merged.values.toList()..sort(
    (ReadingSessionDraft a, ReadingSessionDraft b) =>
        a.localDate.compareTo(b.localDate),
  );
}

/// 一次有效阅读时间被算到了「最后交互 + 空闲阈值」为止。
///
/// 抽成纯函数是为了让「空闲暂停」这条规则只有一处实现：tracker 的计时、周期性 flush、
/// 会话结束时的收尾都调用它，三处各写一遍必然漂移。
/// 语义：活动时间从某一点开始，最晚只算到「最后交互 + 阈值」；在那之前 `now` 就是
/// 终点。返回 null 只表示**阈值非正**（没有任何空闲概念，因而不存在有效区间）。
///
/// 为什么不是「now 不晚于 lastActive 就返回 null」：那正是本实现第一版写错的地方。
/// 交互刚发生的那一刻（now == lastActive）是**完全有效**的一段时间的终点——如果在那里
/// 返回 null，所有「读完就停手」的会话都会被整段丢掉（实测被 tracker 的用例抓到）。
DateTime? effectiveActiveEnd({
  required DateTime lastActive,
  required DateTime now,
  required Duration idleThreshold,
}) {
  if (idleThreshold <= Duration.zero) {
    return null;
  }
  final DateTime deadline = lastActive.add(idleThreshold);
  return now.isBefore(deadline) ? now : deadline;
}
