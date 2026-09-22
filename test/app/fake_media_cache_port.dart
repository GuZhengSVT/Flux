// 组件测试用的内存媒体缓存端口（T047/T048）。
//
// 为什么组件层用它而不是真实 [ImageCacheMediaPort]：
//   `testWidgets` 的 body 跑在 FakeAsync 区域，而真实实现做的是同步/异步文件 I/O。同步部分
//   能工作，但**任何真正异步的文件操作都不会在 FakeAsync 里完成**——表现为 `pumpAndSettle`
//   超时（没有失败信息、只是「一直没结束」），排查起来很贵。
//
// 「文件真的被删掉/统计对了吗」由用例层（test/features/settings/cleanup_test.dart）在真实临时
// 目录上验证；组件层要验的是「页面把预览、确认、回执与开关串对了」，因此一个可设定的内存端口
// 才是正确的替身。
library;

import 'package:flux/core/core.dart';
import 'package:flux/features/settings/application/cleanup_ports.dart';

/// 内存媒体缓存端口。
final class FakeMediaCachePort implements MediaCachePort {
  /// 构造端口（可给定初始条目数与字节数）。
  FakeMediaCachePort({this.entries = 0, this.bytes = 0});

  /// 条目数。
  int entries;

  /// 字节数。
  int bytes;

  /// 清空被调用的次数（断言「清缓存真的执行了」）。
  int clearCalls = 0;

  @override
  Future<Result<({int entries, int bytes})>> stats() async =>
      Ok<({int entries, int bytes})>((entries: entries, bytes: bytes));

  @override
  Future<
    Result<({int entryCount, int imageBytes, int metaBytes, int tempBytes})>
  >
  diskUsage() async =>
      Ok<({int entryCount, int imageBytes, int metaBytes, int tempBytes})>((
        entryCount: entries,
        imageBytes: bytes,
        metaBytes: 0,
        tempBytes: 0,
      ));

  @override
  Future<Result<({int entries, int bytes})>> expiredUsage({
    required DateTime cutoffUtc,
  }) async => Ok<({int entries, int bytes})>((entries: entries, bytes: bytes));

  @override
  Future<Result<({int entries, int bytes})>> deleteExpired({
    required DateTime cutoffUtc,
  }) async {
    final ({int entries, int bytes}) removed = (entries: entries, bytes: bytes);
    entries = 0;
    bytes = 0;
    return Ok<({int entries, int bytes})>(removed);
  }

  @override
  Future<Result<int>> clearAll() async {
    clearCalls++;
    final int removed = entries;
    entries = 0;
    bytes = 0;
    return Ok<int>(removed);
  }

  @override
  Future<Result<int>> enforceLimit() async => const Ok<int>(0);

  @override
  Future<Result<void>> applyLimitMiB(int limitMiB) async => okUnit();
}
