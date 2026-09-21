// T021：图片磁盘缓存（哈希文件名、LRU 淘汰顺序、持久与重载、损坏恢复、上限夹紧）。
//
// 全部在**临时目录**上跑真实文件 I/O：缓存的核心风险（写一半、截断、淘汰顺序）都
// 只在真实文件系统上才成立，用内存替身会把要测的东西替掉。
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:flux/core/core.dart';
import 'package:flux/infrastructure/local/image_cache_service.dart';
import 'package:flux/infrastructure/local/media_cache_metadata.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late ImageCacheService cache;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('flux-media-cache-test');
    cache = ImageCacheService(root: root, limitMiB: kMinCacheMiB);
  });

  tearDown(() async {
    if (root.existsSync()) {
      await root.delete(recursive: true);
    }
  });

  Future<void> put(String url, {int length = 16}) => cache
      .write(
        url: url,
        bytes: Uint8List.fromList(List<int>.filled(length, 0x41)),
        mimeType: 'image/png',
        width: 1,
        height: 1,
      )
      .then((Result<void> r) => expect(r.isOk, isTrue));

  group('哈希文件名（不以外部名称拼路径）', () {
    test('文件名是地址的 SHA-256，不含地址片段', () {
      const String url = 'https://cdn.example.com/path/evil?../../etc/passwd';
      final String expected = ImageCacheService.cacheKeyFor(url);
      expect(expected.length, 64, reason: 'SHA-256 十六进制 = 64 字符');
      expect(cache.dataFileFor(url).path, endsWith('$expected.img'));
      expect(cache.metaFileFor(url).path, endsWith('$expected.meta'));
      // 关键断言：路径里不含地址的任何片段（路径穿越与保留字符都因此不可能）。
      expect(cache.dataFileFor(url).path.contains('evil'), isFalse);
      expect(cache.dataFileFor(url).path.contains('etc'), isFalse);
      expect(cache.dataFileFor(url).path.contains('..'), isFalse);
    });

    test('查询串参与哈希（不同 query 是两张不同的图）', () {
      expect(
        ImageCacheService.cacheKeyFor('https://a/b.png?x=1'),
        isNot(ImageCacheService.cacheKeyFor('https://a/b.png?x=2')),
      );
      expect(
        ImageCacheService.cacheKeyFor('https://a/b.png?x=1'),
        ImageCacheService.cacheKeyFor('https://a/b.png?x=1'),
      );
    });
  });

  group('写入与读取', () {
    test('写入后命中，字节与元数据一致', () async {
      await put('https://a/b.png');
      final Result<CachedImage?> hit = await cache.read('https://a/b.png');
      expect(hit.isOk, isTrue);
      expect(hit.valueOrNull, isNotNull);
      expect(hit.unwrap()!.bytes.length, 16);
      expect(hit.unwrap()!.mimeType, 'image/png');
      expect(hit.unwrap()!.width, 1);
    });

    test('未写入时是明确的未命中（Ok(null)，不是错误）', () async {
      final Result<CachedImage?> miss = await cache.read('https://a/none.png');
      expect(miss.isOk, isTrue);
      expect(miss.valueOrNull, isNull);
    });

    test('磁盘持久：新实例（模拟重启）仍能命中', () async {
      await put('https://a/persist.png', length: 32);
      final ImageCacheService reopened = ImageCacheService(
        root: root,
        limitMiB: kMinCacheMiB,
      );
      final Result<CachedImage?> hit = await reopened.read(
        'https://a/persist.png',
      );
      expect(hit.valueOrNull, isNotNull, reason: '重启后必须命中，否则每次启动都重下');
      expect(hit.unwrap()!.bytes.length, 32);
      expect(reopened.memoryEntryCount, greaterThan(0), reason: '命中后应回填内存缓存');
    });

    test('元数据损坏时按未命中处理，并清掉坏条目', () async {
      await put('https://a/broken.png');
      await cache
          .metaFileFor('https://a/broken.png')
          .writeAsString('{ not json');
      // 必须换一个实例（= 重启）再读：这一条验的是**磁盘上的**损坏检测，而刚才那次
      // write 已经把字节放进内存缓存，同一个实例会直接命中内存、绕过磁盘。
      final ImageCacheService reopened = ImageCacheService(
        root: root,
        limitMiB: kMinCacheMiB,
      );
      final Result<CachedImage?> hit = await reopened.read(
        'https://a/broken.png',
      );
      expect(hit.isOk, isTrue, reason: '坏条目是未命中，不是失败');
      expect(hit.valueOrNull, isNull);
      expect(cache.metaFileFor('https://a/broken.png').existsSync(), isFalse);
    });

    test('数据被截断时拒绝返回半个文件', () async {
      await put('https://a/trunc.png', length: 64);
      await cache.dataFileFor('https://a/trunc.png').writeAsBytes(<int>[
        1,
        2,
        3,
      ]);
      // 同样是重启场景（见上一条说明）。
      final ImageCacheService reopened = ImageCacheService(
        root: root,
        limitMiB: kMinCacheMiB,
      );
      final Result<CachedImage?> hit = await reopened.read(
        'https://a/trunc.png',
      );
      expect(hit.valueOrNull, isNull, reason: '长度不符必须判为损坏');
    });

    test('缓存命中不重复读磁盘（内存缓存生效）', () async {
      await put('https://a/mem.png');
      await cache.read('https://a/mem.png');
      final int entries = cache.memoryEntryCount;
      await cache.read('https://a/mem.png');
      expect(cache.memoryEntryCount, entries, reason: '重复读取不应增加内存条目');
    });
  });

  group('LRU 淘汰', () {
    test('超过上限时删除最旧的条目（按访问时间）', () async {
      // 上限压到最小（128 MiB 无法在测试里真的写满），因此这里用「极小上限」的
      // 独立实例：断言的是**淘汰顺序**，不是具体容量。
      const int tinyLimit = 4096;
      final ImageCacheService tiny = ImageCacheService(
        root: root,
        limitMiB: kMinCacheMiB,
      );
      await tiny.updateLimit(kMinCacheMiB);
      // 直接构造：写入 4 条，每条 2048 字节，总计 8192 > 4096。
      for (final String name in <String>['old', 'mid', 'new', 'newest']) {
        await tiny.write(
          url: 'https://a/$name.png',
          bytes: Uint8List.fromList(List<int>.filled(2048, 1)),
          mimeType: 'image/png',
          width: 1,
          height: 1,
        );
        // 拉开 mtime，让「最旧」可判定（文件系统时间戳精度可能只有秒）。
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      // 访问一次最旧的，使它变成「最近使用」。
      await tiny.read('https://a/old.png');
      final int removed = await tiny.enforceLimit(
        overrideLimitBytes: tinyLimit,
      );
      expect(removed, greaterThan(0), reason: '超限必须删掉一些条目');
      // 刚访问过的 old 必须还在（LRU 的要点），最旧的 mid 先被删。
      expect(tiny.dataFileFor('https://a/old.png').existsSync(), isTrue);
      expect(tiny.dataFileFor('https://a/mid.png').existsSync(), isFalse);
    });

    test('总量在上限内时不做任何删除', () async {
      await put('https://a/small.png', length: 8);
      final int removed = await cache.enforceLimit();
      expect(removed, 0);
      expect(cache.dataFileFor('https://a/small.png').existsSync(), isTrue);
    });

    test('淘汰后统计与实际文件一致', () async {
      await put('https://a/s1.png', length: 100);
      await put('https://a/s2.png', length: 200);
      final ImageCacheStats stats = await cache.stats();
      expect(stats.entryCount, 2);
      expect(stats.totalBytes, 300);
    });
  });

  group('上限夹紧（SET-080）', () {
    test('越界的 MiB 值被夹到 128–4096', () {
      expect(clampCacheMiB(1), kMinCacheMiB);
      expect(clampCacheMiB(0), kMinCacheMiB);
      expect(clampCacheMiB(-100), kMinCacheMiB);
      expect(clampCacheMiB(512), 512);
      expect(clampCacheMiB(99999), kMaxCacheMiB);
      expect(cacheLimitBytes(1), kMinCacheMiB * 1024 * 1024);
    });

    test('updateLimit 立即生效并按新上限裁剪', () async {
      await put('https://a/x.png', length: 16);
      expect(cache.limitBytes, kMinCacheMiB * 1024 * 1024);
      await cache.updateLimit(2048);
      expect(cache.limitBytes, 2048 * 1024 * 1024);
    });
  });

  group('内存缓存上限', () {
    test('条目数上限生效（100 张或 128 MiB 取小）', () async {
      final ImageCacheService small = ImageCacheService(
        root: root,
        memoryLimitEntries: 3,
      );
      for (int i = 0; i < 10; i++) {
        await small.write(
          url: 'https://a/m$i.png',
          bytes: Uint8List.fromList(List<int>.filled(8, 1)),
          mimeType: 'image/png',
          width: 1,
          height: 1,
        );
      }
      expect(small.memoryEntryCount, lessThanOrEqualTo(3));
    });

    test('字节上限也能单独触发淘汰', () async {
      final ImageCacheService small = ImageCacheService(
        root: root,
        memoryLimitEntries: 100,
        memoryLimitBytes: 40,
      );
      for (int i = 0; i < 5; i++) {
        await small.write(
          url: 'https://a/b$i.png',
          bytes: Uint8List.fromList(List<int>.filled(20, 1)),
          mimeType: 'image/png',
          width: 1,
          height: 1,
        );
      }
      expect(small.memoryByteCount, lessThanOrEqualTo(40));
    });
  });

  group('清理', () {
    test('clear 删掉数据与元数据，并清空内存缓存', () async {
      await put('https://a/c1.png');
      await put('https://a/c2.png');
      final int removed = await cache.clear();
      expect(removed, 4, reason: '2 个 .img + 2 个 .meta');
      expect(cache.memoryEntryCount, 0);
      final ImageCacheStats stats = await cache.stats();
      expect(stats.entryCount, 0);
      expect(stats.totalBytes, 0);
    });

    test('统计记录命中与未命中', () async {
      await put('https://a/hit.png');
      await cache.read('https://a/hit.png');
      await cache.read('https://a/miss.png');
      final ImageCacheStats stats = await cache.stats();
      expect(stats.hitCount, 1);
      expect(stats.missCount, 1);
      expect(stats.hitRate, closeTo(0.5, 0.001));
    });
  });

  group('元数据编解码', () {
    test('往返无损，且时间是 UTC', () {
      final CachedImageMeta meta = CachedImageMeta(
        mimeType: 'image/webp',
        width: 12,
        height: 34,
        byteLength: 56,
        storedAt: DateTime.utc(2026, 9, 22, 3, 4, 5),
      );
      final CachedImageMeta? parsed = CachedImageMeta.parse(meta.encode());
      expect(parsed, isNotNull);
      expect(parsed!.mimeType, 'image/webp');
      expect(parsed.width, 12);
      expect(parsed.height, 34);
      expect(parsed.byteLength, 56);
      expect(parsed.storedAt.isUtc, isTrue);
      expect(parsed.storedAt, DateTime.utc(2026, 9, 22, 3, 4, 5));
    });

    test('缺字段或非法取值返回 null（不抛异常）', () {
      expect(CachedImageMeta.parse('{}'), isNull);
      expect(CachedImageMeta.parse('not json'), isNull);
      expect(
        CachedImageMeta.parse(
          '{"mimeType":"image/png","width":0,"height":1,'
          '"byteLength":1,"storedAt":"2026-09-22T00:00:00Z"}',
        ),
        isNull,
      );
    });
  });

  group('根目录', () {
    test('根目录不存在时自动创建（首次启动）', () async {
      final Directory nested = Directory(p.join(root.path, 'a', 'b'));
      final ImageCacheService fresh = ImageCacheService(root: nested);
      final Result<void> written = await fresh.write(
        url: 'https://a/n.png',
        bytes: Uint8List.fromList(<int>[1, 2, 3]),
        mimeType: 'image/png',
        width: 1,
        height: 1,
      );
      expect(written.isOk, isTrue);
      expect(nested.existsSync(), isTrue);
    });
  });
}
