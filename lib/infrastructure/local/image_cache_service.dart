// 远程图片磁盘缓存（T021；架构 4.2「图片按需缓存」、5.1「不以外部标题直接拼路径」、
// SET-080「媒体缓存上限 512 MiB，允许 128–4096」）。
//
// 四个必须在这里成立的规则：
//
//   1) **文件名是内容地址的哈希，不是地址本身**。用 URL 拼路径会同时踩三个坑：
//      路径穿越（../..）、保留字符（?&% 在文件系统里的语义）、以及长度上限
//      （长查询串的地址能超过文件名上限）。哈希之后所有地址都映射到一个定长、
//      只含十六进制字符的名字，以上三个问题在结构上不存在。
//      用 SHA-256 而不是 hashCode：后者在 Dart 里对 String 的取值不保证跨进程稳定，
//      重启后缓存**全部失效**（表现为每次启动都重新下载所有图片）。
//
//   2) **LRU 是「按访问时间 + 大小总量」两个条件**。只按条数淘汰挡不住「缓存 100 张
//      各 4 MiB 的图」把磁盘吃满；只按总量淘汰而不看访问时间会淘汰刚看过的图。
//      这里读一次就更新文件的修改时间（访问时间戳落在 mtime 上：POSIX atime 默认
//      是 relatime/noatime，不可依赖），超限时按 mtime 升序删到低于上限。
//
//   3) **上限来自 SET-080**，默认 512 MiB 并夹紧到 128–4096（见 media_cache.dart）。
//
//   4) **失败不产生半个文件**。先写临时文件再 rename：进程在写一半时被杀掉，
//      留下的是一个 `.part` 文件而不是一个「长度不对但看起来正常」的缓存条目。
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'package:flux/core/core.dart';

import 'media_cache_metadata.dart';

/// 缓存条目（一次命中的结果）。
final class CachedImage {
  /// 构造条目。
  const CachedImage({
    required this.bytes,
    required this.mimeType,
    required this.width,
    required this.height,
  });

  /// 字节（原样，与下载时一致）。
  final Uint8List bytes;

  /// MIME（下载时已校验）。
  final String mimeType;

  /// 宽（下载时从头读取）。
  final int width;

  /// 高。
  final int height;
}

/// 缓存统计（界面与清理预览用）。
final class ImageCacheStats {
  /// 构造统计。
  const ImageCacheStats({
    required this.entryCount,
    required this.totalBytes,
    required this.limitBytes,
    required this.hitCount,
    required this.missCount,
  });

  /// 条目数。
  final int entryCount;

  /// 占用字节。
  final int totalBytes;

  /// 上限字节（来自 SET-080）。
  final int limitBytes;

  /// 本次进程内的命中次数。
  final int hitCount;

  /// 未命中次数。
  final int missCount;

  /// 命中率（无访问时为 0，而不是 NaN）。
  double get hitRate {
    final int total = hitCount + missCount;
    return total == 0 ? 0 : hitCount / total;
  }
}

/// 图片磁盘缓存。
final class ImageCacheService {
  /// 构造缓存。
  ///
  /// [root] 是缓存根目录（生产由装配层按 SET-080 与数据目录决定；测试用临时目录）。
  /// [limitMiB] 是 SET-080 的原始 MiB 值，内部会夹紧。
  ImageCacheService({
    required this.root,
    this.limitMiB = kDefaultCacheMiB,
    this.memoryLimitEntries = kDefaultMemoryCacheEntries,
    this.memoryLimitBytes = kDefaultMemoryCacheBytes,
    this.clock = const SystemClock(),
  });

  /// 内存缓存的默认条目上限。
  static const int kDefaultMemoryCacheEntries = 100;

  /// 内存缓存的默认字节上限：128 MiB。
  static const int kDefaultMemoryCacheBytes = 128 * 1024 * 1024;

  /// 缓存根目录。
  final Directory root;

  /// SET-080 的原始 MiB 值（读取时夹紧到 128–4096）。
  int limitMiB;

  /// 时钟（元数据里的写入时间）。
  final Clock clock;

  /// 内存缓存条目上限（「100 张或 128 MiB 取小」，两个条件都要满足）。
  final int memoryLimitEntries;

  /// 内存缓存字节上限。
  final int memoryLimitBytes;

  /// 内存缓存（LRU：LinkedHashMap 的插入顺序即使用顺序，命中后重插到末尾）。
  final Map<String, CachedImage> _memory = <String, CachedImage>{};
  int _memoryBytes = 0;

  int _hits = 0;
  int _misses = 0;
  bool _initialized = false;

  /// 当前生效的上限（字节）。
  int get limitBytes => cacheLimitBytes(limitMiB);

  /// 更新上限（设置变化时调用），并立即按新上限裁剪。
  Future<void> updateLimit(int limitMiB) async {
    this.limitMiB = limitMiB;
    await enforceLimit();
  }

  /// 缓存键：地址的 SHA-256（十六进制）。
  ///
  /// 用整个地址（含查询串）作输入：同一个路径带不同 query 可能是两张不同的图，
  /// 只哈希路径会把它们混成一条（表现为「图片串了」）。
  static String cacheKeyFor(String url) => sha256HexOfString(url);

  /// 条目的数据文件路径（哈希 + `.img` 后缀）。
  File dataFileFor(String url) =>
      File(p.join(root.path, '${cacheKeyFor(url)}.img'));

  /// 条目的元数据文件路径。
  File metaFileFor(String url) =>
      File(p.join(root.path, '${cacheKeyFor(url)}.meta'));

  /// 读取缓存（命中时同时刷新访问时间）。
  ///
  /// 命中判定分两层：内存缓存优先（避免磁盘 I/O），其次磁盘。磁盘命中后回填内存，
  /// 因此「滚动列表反复经过同一张图」不会反复读盘。
  Future<Result<CachedImage?>> read(String url) async {
    try {
      await _ensureRoot();
      final String key = cacheKeyFor(url);
      final CachedImage? fromMemory = _memory.remove(key);
      if (fromMemory != null) {
        _memory[key] = fromMemory; // 重插到末尾 = 标记为最近使用
        _hits++;
        await _touch(dataFileFor(url));
        return Ok<CachedImage?>(fromMemory);
      }

      final File data = dataFileFor(url);
      final File meta = metaFileFor(url);
      if (!data.existsSync() || !meta.existsSync()) {
        _misses++;
        return const Ok<CachedImage?>(null);
      }

      final CachedImageMeta? parsed;
      try {
        parsed = CachedImageMeta.parse(await meta.readAsString());
      } on Exception {
        // 元数据损坏（半写、手工改动）：删掉这一条并按未命中处理，而不是抛错。
        // 一张图看不到是小事，一个坏缓存条目让整篇文章的图片都失败是大事。
        await _deleteQuietly(data);
        await _deleteQuietly(meta);
        _misses++;
        return const Ok<CachedImage?>(null);
      }
      if (parsed == null) {
        await _deleteQuietly(data);
        await _deleteQuietly(meta);
        _misses++;
        return const Ok<CachedImage?>(null);
      }

      final Uint8List bytes = await data.readAsBytes();
      if (bytes.length != parsed.byteLength) {
        // 长度与元数据不符：写入过程中断或文件被截断。不返回半个图。
        await _deleteQuietly(data);
        await _deleteQuietly(meta);
        _misses++;
        return const Ok<CachedImage?>(null);
      }

      final CachedImage entry = CachedImage(
        bytes: bytes,
        mimeType: parsed.mimeType,
        width: parsed.width,
        height: parsed.height,
      );
      _hits++;
      await _touch(data);
      _rememberInMemory(key, entry);
      return Ok<CachedImage?>(entry);
    } on Exception catch (error, stackTrace) {
      return Err<CachedImage?>(
        StorageError(
          operation: 'imageCache.read',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  /// 写入缓存（已通过 MIME/体积/魔数校验的字节）。
  Future<Result<void>> write({
    required String url,
    required Uint8List bytes,
    required String mimeType,
    required int width,
    required int height,
  }) async {
    try {
      await _ensureRoot();
      final File data = dataFileFor(url);
      final File meta = metaFileFor(url);

      // 先写 .part 再 rename：崩溃留下的是一眼可辨的临时文件，而不是一个长度不对的
      // 正式条目（后者会被 read() 当成损坏并删除，虽然结果一样，但「写一半的正式文件」
      // 在人工排查时会误导）。
      final File tmpData = File('${data.path}.part');
      await tmpData.writeAsBytes(bytes, flush: true);
      await tmpData.rename(data.path);
      await meta.writeAsString(
        CachedImageMeta(
          mimeType: mimeType,
          width: width,
          height: height,
          byteLength: bytes.length,
          storedAt: clock.now(),
        ).encode(),
        flush: true,
      );

      _rememberInMemory(
        cacheKeyFor(url),
        CachedImage(
          bytes: bytes,
          mimeType: mimeType,
          width: width,
          height: height,
        ),
      );
      await enforceLimit();
      return const Ok<void>(null);
    } on Exception catch (error, stackTrace) {
      return Err<void>(
        StorageError(
          operation: 'imageCache.write',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  /// 按上限淘汰（读盘统计总量，按 mtime 升序删除）。
  ///
  /// 返回本次删除的条目数。
  ///
  /// [overrideLimitBytes] 只给测试用：生产上限最小也有 128 MiB，在单测里真的写满
  /// 不现实，而这个方法的**淘汰顺序**逻辑恰恰是最该被测的部分。传入之后只影响这一次
  /// 计算的阈值，不改实例的上限。
  Future<int> enforceLimit({int? overrideLimitBytes}) async {
    await _ensureRoot();
    final List<File> entries = _listEntryFiles();
    int total = 0;
    final List<(File, DateTime)> dated = <(File, DateTime)>[];
    for (final File file in entries) {
      final FileStat stat = file.statSync();
      total += stat.size;
      dated.add((file, stat.modified));
    }
    final int limit = overrideLimitBytes ?? limitBytes;
    if (total <= limit) {
      return 0;
    }
    // 最旧的先删（访问时间更新过 mtime，因此这是真正的 LRU）。
    dated.sort((a, b) => a.$2.compareTo(b.$2));
    int removed = 0;
    for (final (File file, DateTime _) in dated) {
      if (total <= limit) {
        break;
      }
      final int size = file.statSync().size;
      if (await _deleteQuietly(file)) {
        total -= size;
        removed++;
      }
      // 连带删除同名 meta（哈希相同即同一 URL）。
      final String base = file.path.substring(0, file.path.length - 4);
      await _deleteQuietly(File('$base.meta'));
    }
    // 内存缓存按**实际上限**裁剪（overrideLimitBytes 只是测试用的临时阈值，
    // 不该让它永久改变内存缓存的容量）。
    _pruneMemoryToLimit();
    return removed;
  }

  /// 统计。
  Future<ImageCacheStats> stats() async {
    await _ensureRoot();
    int total = 0;
    int count = 0;
    for (final File file in _listEntryFiles()) {
      total += file.statSync().size;
      count++;
    }
    return ImageCacheStats(
      entryCount: count,
      totalBytes: total,
      limitBytes: limitBytes,
      hitCount: _hits,
      missCount: _misses,
    );
  }

  /// 清空缓存（SET-079 的「一键清缓存」入口；本任务先提供能力，界面属 T047）。
  Future<int> clear() async {
    await _ensureRoot();
    int removed = 0;
    for (final File file in root.listSync().whereType<File>()) {
      if (file.path.endsWith('.img') ||
          file.path.endsWith('.meta') ||
          file.path.endsWith('.part')) {
        if (await _deleteQuietly(file)) {
          removed++;
        }
      }
    }
    _memory.clear();
    _memoryBytes = 0;
    return removed;
  }

  /// 磁盘实际占用（条目 + 元数据 + 半成品 .part 文件）。
  ///
  /// 与 [stats] 的区别：那个只数 `.img`（条目数与**图片**字节，用于命中率与上限判定），这个把
  /// 元数据与半成品也数进去。存储页要显示的是「这部分在磁盘上占了多少」，而元数据文件与一次被
  /// 中断的下载同样占着磁盘——只报图片字节会让「分类占用」比实际小，用户看到的总和与系统
  /// 显示的目录大小对不上。
  Future<({int entryCount, int imageBytes, int metaBytes, int tempBytes})>
  diskUsage() async {
    await _ensureRoot();
    int images = 0;
    int metas = 0;
    int temps = 0;
    int entries = 0;
    for (final File file in root.listSync().whereType<File>()) {
      final String path = file.path;
      final int size = file.statSync().size;
      if (path.endsWith('.img')) {
        images += size;
        entries++;
      } else if (path.endsWith('.meta')) {
        metas += size;
      } else if (path.endsWith('.part')) {
        temps += size;
      }
    }
    return (
      entryCount: entries,
      imageBytes: images,
      metaBytes: metas,
      tempBytes: temps,
    );
  }

  /// 按**最后访问时间**统计到期条目（`mtime` 早于 [cutoffUtc] 的 `.img` 及其元数据）。
  ///
  /// 只统计不删除：自动清理必须先预览再执行（架构 5.3 的清理预览），而「枚举」与「删除」
  /// 分成两个方法时，「预览说 12 条、实际删了 30 条」这种偏差在结构上不可能发生。
  ///
  /// 用 mtime 而不是文件创建时间：读取一次会 [_touch] 更新 mtime，因此它就是**最后访问**
  /// 时间（POSIX 的 atime 默认不可靠，见类顶部说明）。
  ///
  /// `.part` 半成品按**同一规则**参与判定：一次被中断的写入不会自己恢复，因此任何超过保留期
  /// 的半成品都是垃圾；但它**不计入** [expiredUsage] 的条目数（它不是一条缓存条目），只计入
  /// 将被释放的字节——否则界面会说「删 12 张图」，而其中一条其实是个损坏的半成品。
  Future<({int entries, int bytes})> expiredUsage({
    required DateTime cutoffUtc,
  }) async {
    await _ensureRoot();
    int entries = 0;
    int bytes = 0;
    for (final File file in _expiredFiles(cutoffUtc)) {
      bytes += file.statSync().size;
      if (file.path.endsWith('.img')) {
        entries++;
        // 元数据与它同生共死：删了图片留下 .meta 只会在下一次统计里变成一条永远删不掉的
        // 「元数据垃圾」（它不是条目，因此既不会被淘汰也不会被计入占用）。
        final File meta = File(
          '${file.path.substring(0, file.path.length - 4)}.meta',
        );
        if (meta.existsSync()) {
          bytes += meta.statSync().size;
        }
      }
    }
    return (entries: entries, bytes: bytes);
  }

  /// 删除到期条目；返回实际删除的条目数与字节（含元数据与半成品）。
  Future<({int entries, int bytes})> deleteExpired({
    required DateTime cutoffUtc,
  }) async {
    await _ensureRoot();
    int entries = 0;
    int bytes = 0;
    for (final File file in _expiredFiles(cutoffUtc)) {
      final bool isEntry = file.path.endsWith('.img');
      final File meta = File(
        '${file.path.substring(0, file.path.length - 4)}.meta',
      );
      int freed = file.statSync().size;
      if (isEntry && meta.existsSync()) {
        freed += meta.statSync().size;
      }
      if (await _deleteQuietly(file)) {
        if (isEntry) {
          await _deleteQuietly(meta);
          // 已删除的条目必须从内存缓存里移除：否则它仍在内存里命中，表现为「刚清完又能读到」，
          // 而磁盘上已经没有它了（下一次重启才「真的消失」）。
          _forgetInMemory(file.path);
        }
        bytes += freed;
        if (isEntry) {
          entries++;
        }
      }
    }
    return (entries: entries, bytes: bytes);
  }

  /// 列出到期文件（`.img` 与 `.part`，按 mtime 早于截止时刻判定）。
  List<File> _expiredFiles(DateTime cutoffUtc) {
    if (!root.existsSync()) {
      return const <File>[];
    }
    final DateTime cutoff = cutoffUtc.toUtc();
    return root
        .listSync()
        .whereType<File>()
        .where(
          (File f) =>
              (f.path.endsWith('.img') || f.path.endsWith('.part')) &&
              f.statSync().modified.toUtc().isBefore(cutoff),
        )
        .toList(growable: false);
  }

  /// 从内存缓存里按**数据文件路径**移除一条（哈希文件名 → 键即去掉扩展名）。
  void _forgetInMemory(String dataFilePath) {
    final String fileName = p.basename(dataFilePath);
    final String key = fileName.endsWith('.img')
        ? fileName.substring(0, fileName.length - 4)
        : fileName;
    final CachedImage? removed = _memory.remove(key);
    if (removed != null) {
      _memoryBytes -= removed.bytes.length;
    }
  }

  Future<void> _ensureRoot() async {
    if (_initialized) {
      return;
    }
    if (!root.existsSync()) {
      await root.create(recursive: true);
    }
    _initialized = true;
  }

  /// 列出所有条目的数据文件（`.part` 与 `.meta` 不算条目）。
  List<File> _listEntryFiles() {
    if (!root.existsSync()) {
      return const <File>[];
    }
    return root
        .listSync()
        .whereType<File>()
        .where((File f) => f.path.endsWith('.img'))
        .toList(growable: false);
  }

  /// 更新 mtime（= 访问时间）。
  ///
  /// 失败不报错：更新访问时间失败不该让一次成功的读取变成失败。
  Future<void> _touch(File file) async {
    try {
      if (file.existsSync()) {
        file.setLastModifiedSync(DateTime.now());
      }
    } on Exception {
      // 忽略：见上。
    }
  }

  Future<bool> _deleteQuietly(File file) async {
    try {
      if (file.existsSync()) {
        await file.delete();
        return true;
      }
    } on Exception {
      // 删除失败（被占用、只读）不抛：调用方按「没删掉」处理，下一次还会尝试。
    }
    return false;
  }

  void _rememberInMemory(String key, CachedImage entry) {
    final CachedImage? previous = _memory.remove(key);
    if (previous != null) {
      _memoryBytes -= previous.bytes.length;
    }
    _memory[key] = entry;
    _memoryBytes += entry.bytes.length;
    // 两个上限都要满足：先按条数，再按字节（取小 = 两个条件都成立）。
    while (_memory.length > memoryLimitEntries) {
      final String oldest = _memory.keys.first;
      _memoryBytes -= _memory.remove(oldest)!.bytes.length;
    }
    while (_memoryBytes > memoryLimitBytes && _memory.isNotEmpty) {
      final String oldest = _memory.keys.first;
      _memoryBytes -= _memory.remove(oldest)!.bytes.length;
    }
  }

  void _pruneMemoryToLimit() {
    while (_memory.length > memoryLimitEntries && _memory.isNotEmpty) {
      final String oldest = _memory.keys.first;
      _memoryBytes -= _memory.remove(oldest)!.bytes.length;
    }
    while (_memoryBytes > memoryLimitBytes && _memory.isNotEmpty) {
      final String oldest = _memory.keys.first;
      _memoryBytes -= _memory.remove(oldest)!.bytes.length;
    }
  }

  /// 内存缓存当前条目数（测试与统计用）。
  int get memoryEntryCount => _memory.length;

  /// 内存缓存当前字节数。
  int get memoryByteCount => _memoryBytes;
}

// describeBytes 自 T047 起住在 lib/core/domain/media_cache.dart：存储页（features）要显示
// 人类可读的占用，而 features 不得 import infrastructure（架构 2.2 的守卫会拦）。这里不再
// 重复定义，调用方从 core 取（core.dart 已经转出它）。
