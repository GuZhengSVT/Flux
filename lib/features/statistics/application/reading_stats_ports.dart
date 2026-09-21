// 统计功能的端口 Provider（T023）。
//
// 与 article_ports.dart / feed_ports.dart 同一条理由（架构 2.2：页面不直接碰数据库，
// 由组合根注入实现）：默认实现一律抛错，漏接线必须在使用时立刻暴露，而不是退化成一个
// 空实现把「没有数据」演得像真的一样。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flux/core/core.dart';

/// 阅读统计读写端口。
final Provider<ReadingStatsStore> readingStatsProvider =
    Provider<ReadingStatsStore>(
      (Ref ref) => throw StateError(
        'readingStatsProvider 未被组合根覆盖：见 lib/app/app_providers.dart',
      ),
    );

/// 会话时区（统计归属依据）。
///
/// 生产实现取设备当前时区在**会话开始时**的快照；测试注入固定偏移，从而在不改动
/// 进程时区的前提下验证跨午夜拆分。
final Provider<SessionLocalZone> sessionZoneProvider =
    Provider<SessionLocalZone>(
      (Ref ref) => throw StateError(
        'sessionZoneProvider 未被组合根覆盖：见 lib/app/app_providers.dart',
      ),
    );

/// 时钟（统计的时间来源；测试注入假时钟）。
final Provider<Clock> statsClockProvider = Provider<Clock>(
  (Ref ref) => throw StateError(
    'statsClockProvider 未被组合根覆盖：见 lib/app/app_providers.dart',
  ),
);
