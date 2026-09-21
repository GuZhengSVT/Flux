// 跨设备稳定标识的生成（T014；架构 5.1/5.2）。
//
// 为什么需要它、以及为什么**不用自增 id 充当**：
//   - 架构 5.2 规定跨设备文章键 = 共享 Feed syncId + 类型标记 + GUID/规范 URL，
//     因此 syncId 必须在**两台独立导入同一源的设备上尽量一致**，否则同步时无法
//     把同一条订阅对齐；自增 id 在两端必然不同（取决于导入顺序），拿来当 syncId
//     会制造「同一源在两端各成一条」的问题；
//   - OPML 往返、重复导入匹配、WebDAV 对齐都依赖它稳定且可复现。
//
// 生成策略（两条路径，都确定性可复现）：
//   1) 订阅：syncId = 'feed.' + SHA-256(规范化 URL) 前 32 位十六进制。
//      同一地址在任何设备上得到同一个 syncId，不依赖导入顺序，也不需要用户填写。
//   2) 分组：用户建的分组没有天然唯一键（同名可以存在，改名后也不该改变身份），
//      因此生成时掺入「随机数 + 当前时间 + 单调计数」，保证**本机唯一**；跨设备
//      对齐由同步阶段按名称/内容合并（架构 5.2 的「两端各自建组」场景），不属于
//      本任务。
//
// 本文件是纯 Dart、无 I/O，可在纯 Dart 测试中直接调用。
library;

import 'dart:math';

import '../digest/sha256.dart';

/// 稳定标识前缀：让「这是哪一类实体」在日志与同步包中一眼可见。
abstract final class StableIdPrefix {
  /// 订阅。
  static const String feed = 'feed.';

  /// 分组。
  static const String group = 'group.';
}

/// 由规范化 URL 生成订阅的稳定标识。
///
/// [normalizedUrl] 必须是 [normalizeLink] 的产物（同一条订阅的规范化结果是确定的），
/// 调用方不要传原始地址——原始地址里的跟踪参数会让同一个源算出两个 syncId。
String feedSyncIdFor(String normalizedUrl) =>
    '${StableIdPrefix.feed}${sha256HexOfString(normalizedUrl).substring(0, 32)}';

/// 生成一个新的分组稳定标识。
///
/// [random] 与 [now] 可注入，使测试能验证「同一输入得到同一标识」而不是依赖
/// 真实随机源；生产调用不传参数。
String newGroupSyncId({Random? random, DateTime? now, int sequence = 0}) {
  final Random source = random ?? Random.secure();
  final String timePart = (now ?? DateTime.now().toUtc()).toIso8601String();
  final String randomPart = List<String>.generate(
    8,
    (_) => source.nextInt(1 << 32).toRadixString(16).padLeft(8, '0'),
  ).join();
  final String material = '$timePart|$randomPart|$sequence';
  return '${StableIdPrefix.group}${sha256HexOfString(material).substring(0, 32)}';
}
