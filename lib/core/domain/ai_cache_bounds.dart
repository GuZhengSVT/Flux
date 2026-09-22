// AI 结果缓存的容量上限与淘汰顺序（T047；补 T030 的遗留「缓存没有上限与淘汰策略」）。
//
// 为什么需要上限：结果缓存是**付费产出**的副本，但它同时也是磁盘上的增长源——一篇长文
// 的翻译、一次每日新闻的初稿都可能几万字符，而缓存键会随「输入/模型/语言/温度」任一变化
// 而新增一条。没有上限时它只增不减，最终表现为「用了半年之后数据目录几十 MB，而用户
// 从界面上完全看不出这部分是什么」。
//
// 为什么上限是**条数 + 字节两个条件**（与 T021 的图片缓存同一口径）：
//   * 只限条数挡不住「200 条各 200 KB 的翻译」；
//   * 只限字节在全是小条目时会让条目数无限增长（每条都要一次索引查找与一次淘汰扫描）。
// 两个条件都成立才算「在上限内」，因此取两者的**较小**约束。
//
// 为什么淘汰顺序是**最近使用**（LRU）而不是创建时间：结果的复用模式是「同一份输入反复
// 出现」（同一篇新闻重跑、同一段译文重译），最近用过的条目最可能被再用一次；按创建时间
// 淘汰会把「每天都在用、但第一次生成是半年前」的那条删掉。
library;

/// 结果缓存的容量上限。
///
/// 这两个数值是**本次合并确定的可调基线**（架构第 6 节末尾的口径：未由开发者指定的数值
/// 不代表性能实测结论）。它们没有对应的 SET 编号——架构第 6 节的 SET 表是产品设置清单，
/// 为用户可配置项预留；缓存上限属于内部资源策略，因此写成常量而不是伪装成一个设置项
/// （一个没有界面、只能靠改代码生效的「设置」比常量更容易误导）。
final class AiCacheLimits {
  /// 构造上限。
  const AiCacheLimits({required this.maxEntries, required this.maxBytes});

  /// 默认上限：200 条、128 MiB（取两者中更紧的那个作为实际约束）。
  static const AiCacheLimits defaults = AiCacheLimits(
    maxEntries: 200,
    maxBytes: 128 * 1024 * 1024,
  );

  /// 条目数上限。
  final int maxEntries;

  /// 字节上限。
  final int maxBytes;

  /// 把**无意义**的值（0 / 负数）回退到默认上限。
  ///
  /// 为什么回退到默认值而不是夹到 1：夹到 1 会让「上限是 0」的坏值变成「几乎清空缓存」，
  /// 而那正是最贵的后果——每一条缓存都没了，接下来所有同样输入的任务都会真实请求一次、
  /// 每次都付费。回退到默认值是一个可解释的结果（「这个值不可用，按默认的来」），并且不会
  /// 因为一个坏数字产生大量付费调用。
  ///
  /// 正的小值**不**夹紧：它是合法的（且测试需要它来验证字节上限单独生效时不必真的写 128 MiB）。
  AiCacheLimits clamped() => AiCacheLimits(
    maxEntries: maxEntries < 1 ? AiCacheLimits.defaults.maxEntries : maxEntries,
    maxBytes: maxBytes < 1 ? AiCacheLimits.defaults.maxBytes : maxBytes,
  );
}

/// 一条待淘汰判定的缓存条目（只带判定需要的两个事实）。
///
/// 刻意不带文本：淘汰是**只看元数据**的决策，把正文传进来会让「淘汰」这一步有能力顺手
/// 读到用户内容，而它不需要。
final class AiCacheEntryFact {
  /// 构造事实。
  const AiCacheEntryFact({
    required this.key,
    required this.byteLength,
    required this.createdAt,
    this.lastUsedAt,
  });

  /// 缓存键。
  final String key;

  /// 文本字节长度（UTF-8，与落库口径一致）。
  final int byteLength;

  /// 写入时刻（UTC）。
  final DateTime createdAt;

  /// 最近一次被读到的时刻（UTC）；从未被读过为 null。
  final DateTime? lastUsedAt;

  /// 淘汰排序用的时刻：最近使用优先，从未使用过的按写入时刻。
  ///
  /// 为什么用「从未使用 → 按写入时刻」而不是把它排到最后或最前：一条刚写入、还没被任何
  /// 任务读到的缓存**必须**参与淘汰（否则「批量写入 1000 条新缓存」时它们全是 null，会让
  /// 淘汰退化成「只删旧的、留下刚写的一千条」，上限等于失效）。用写入时刻是它唯一诚实的
  /// 时间原点。
  DateTime get effectiveLastUsedAt => (lastUsedAt ?? createdAt).toUtc();
}

/// 一次淘汰的判定结果。
final class AiCacheEvictionPlan {
  /// 构造计划。
  const AiCacheEvictionPlan({
    required this.keysToDelete,
    required this.totalBytes,
    required this.retainedCount,
  });

  /// 需要删除的键（按淘汰顺序；调用方逐个删除或一次批量删）。
  final List<String> keysToDelete;

  /// 淘汰前占用的总字节。
  final int totalBytes;

  /// 淘汰后**保留**的条目数（供界面显示「清掉 N 条、留下 M 条」）。
  final int retainedCount;

  /// 是否什么都不用删。
  bool get isEmpty => keysToDelete.isEmpty;
}

/// 计算淘汰计划（纯函数）。
///
/// 判定顺序：先看是否两个上限都满足（都满足就一条都不删），否则按最近使用升序删除，
/// **每一步都重新检查两个条件**——只按条数判断会在「删够了条数但字节仍超限」时停手，
/// 只按字节判断则相反。
///
/// [extra] 表示「本次还要写入的一条」：它在计划里被计入总量，因此调用方能在**写入前**
/// 得到正确的淘汰集合（先写再淘汰会有一段超限的时间窗口，而且那一刻磁盘上确实多占了）。
AiCacheEvictionPlan planAiCacheEviction({
  required List<AiCacheEntryFact> entries,
  required AiCacheLimits limits,
  AiCacheEntryFact? extra,
}) {
  final AiCacheLimits effective = limits.clamped();
  final List<AiCacheEntryFact> all = <AiCacheEntryFact>[...entries, ?extra];
  int total = all.fold<int>(
    0,
    (int sum, AiCacheEntryFact entry) => sum + entry.byteLength,
  );
  int count = all.length;
  if (count <= effective.maxEntries && total <= effective.maxBytes) {
    return AiCacheEvictionPlan(
      keysToDelete: const <String>[],
      totalBytes: total,
      retainedCount: count,
    );
  }

  final List<AiCacheEntryFact> ordered = List<AiCacheEntryFact>.of(all)
    ..sort((AiCacheEntryFact a, AiCacheEntryFact b) {
      final int byTime = a.effectiveLastUsedAt.compareTo(b.effectiveLastUsedAt);
      // 同一时刻时按键排序：淘汰顺序必须**确定**，否则「同样两份数据、两次运行删掉的
      // 是不同条目」会让排查与断言都失去意义。
      return byTime != 0 ? byTime : a.key.compareTo(b.key);
    });

  final List<String> doomed = <String>[];
  for (final AiCacheEntryFact entry in ordered) {
    if (count <= effective.maxEntries && total <= effective.maxBytes) {
      break;
    }
    // 本次要写入的那条不参与淘汰：删除一条刚刚成功产出的结果等于让这次缓存写入白做
    // （下一次同样的输入还会真实请求一次并再付一次费）。极端情况（单条就超过字节上限）
    // 下会保留它并让上限被短暂突破，这是刻意的取舍：正确性优先于上限的严格性。
    if (identical(entry, extra) || (extra != null && entry.key == extra.key)) {
      continue;
    }
    doomed.add(entry.key);
    total -= entry.byteLength;
    count -= 1;
  }
  return AiCacheEvictionPlan(
    keysToDelete: List<String>.unmodifiable(doomed),
    totalBytes: total,
    retainedCount: count,
  );
}

/// 文本的 UTF-8 字节长度。
///
/// 与落库口径一致（SQLite 的 TEXT 以 UTF-8 存储），因此「字节上限」与「磁盘占用」是同一个
/// 东西；用 `String.length`（UTF-16 码元数）会低估中日韩文本约三分之一。
int utf8ByteLength(String text) {
  int bytes = 0;
  for (final int unit in text.codeUnits) {
    if (unit < 0x80) {
      bytes += 1;
    } else if (unit < 0x800) {
      bytes += 2;
    } else if (unit >= 0xD800 && unit <= 0xDBFF) {
      // 代理对的高位：整对占 4 字节，低位的迭代会再贡献 0（见下）。
      bytes += 4;
    } else if (unit >= 0xDC00 && unit <= 0xDFFF) {
      // 代理对的低位：已在高位计过，跳过。
      continue;
    } else {
      bytes += 3;
    }
  }
  return bytes;
}
