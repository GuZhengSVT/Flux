// 性能验收集的构造（T050；架构第 8 节「100 个订阅、50000 条文章、100000 字符长文」）。
//
// 为什么放在 infrastructure 而不是 tool/ 或测试里：
//   数据集是**真实的库内容**——它必须经过与生产完全相同的表结构、索引与 FTS 触发器，
//   否则测出来的数字（索引规模、MATCH 命中、页面读取）与实际运行的不是一回事。
//   放在 local 层意味着任何驱动（tool 脚本、组件测试、将来的集成测试）都能复用同一份
//   生成逻辑，而不会各自造一份「差不多」的假数据。
//
// 为什么是**确定性**的（固定种子 + 纯函数）：
//   性能基线要能与下一次比较。随机数据会让「这次快了 5%」无法区分是优化还是运气。
//   因此这里用线性同余发生器按固定种子产出所有可变字段，两次生成得到完全相同的库。
//
// 边界（如实说明）：生成的是**合成文本**，不是真实抓取的订阅内容。它足以覆盖
// 「50000 行、索引规模、长正文、来源名检索」这些与性能相关的形状，但不代表真实中文
// 语料的词频分布——检索耗时会随命中数变化，这一点在手册的基线记录里标注。
library;

import 'dart:math' as math;

import 'package:drift/drift.dart';

import 'package:flux/core/core.dart' show IdentityBasis, ReadingState;

import 'database.dart';

/// 验收集的规模。
final class PerfDatasetSpec {
  /// 构造规模。
  const PerfDatasetSpec({
    this.feedCount = 100,
    this.articleCount = 50000,
    this.longArticleCharacters = 100000,
    this.seed = 20260922,
  });

  /// 订阅数（架构第 8 节：100）。
  final int feedCount;

  /// 文章数（架构第 8 节：50000）。
  final int articleCount;

  /// 最长一篇文章的正文字符数（架构第 8 节：100000）。
  final int longArticleCharacters;

  /// 随机种子（固定值让两次生成得到同一个库）。
  final int seed;
}

/// 生成结果：用于在报告里如实写出「这次到底造了多少」。
final class PerfDatasetReport {
  /// 构造报告。
  const PerfDatasetReport({
    required this.feeds,
    required this.articles,
    required this.longArticleId,
    required this.longArticleCharacters,
  });

  /// 订阅数。
  final int feeds;

  /// 文章数。
  final int articles;

  /// 长文的文章 id（供「打开一篇十万字文章」的用例定位它）。
  final int longArticleId;

  /// 长文实际字符数。
  final int longArticleCharacters;
}

/// 把验收集写入 [db]。
///
/// 写入分批（每批 500 行一个事务）：50000 条逐条插入会慢到几分钟，而**批量插入同样
/// 会执行 FTS 触发器**（触发器是表级行为，与插入方式无关），因此索引是真实建起来的。
Future<PerfDatasetReport> seedPerfDataset(
  AppDatabase db, {
  PerfDatasetSpec spec = const PerfDatasetSpec(),
  void Function(int done, int total)? onProgress,
}) async {
  final _Rng rng = _Rng(spec.seed);

  // 订阅：名字里带可检索的词，供「按来源名检索」的场景使用。
  final List<int> feedIds = <int>[];
  for (int i = 0; i < spec.feedCount; i++) {
    final int id = await db
        .into(db.feeds)
        .insert(
          FeedsCompanion.insert(
            syncId: 'perf.feed.$i',
            normalizedUrl: 'https://perf-$i.example.com/feed.xml',
            name: '性能测试源 $i 科技',
          ),
        );
    feedIds.add(id);
  }

  // 文章：分批插入，每批一个事务。
  const int batch = 500;
  int inserted = 0;
  final DateTime base = DateTime.utc(2026, 9, 20, 12);
  while (inserted < spec.articleCount) {
    final int end = math.min(inserted + batch, spec.articleCount);
    await db.transaction(() async {
      for (int i = inserted; i < end; i++) {
        final int feedId = feedIds[i % feedIds.length];
        await db
            .into(db.articles)
            .insert(
              ArticlesCompanion.insert(
                feedId: Value<int?>(feedId),
                title: '性能文章 $i 关于离线阅读与缓存设计',
                identityBasis: IdentityBasis.guid,
                guid: Value<String?>('perf-guid-$i'),
                guidPresent: const Value<bool>(true),
                normalizedLink: Value<String?>(
                  'https://perf-${i % feedIds.length}.example.com/a/$i',
                ),
                author: Value<String?>('作者 ${i % 37}'),
                // 摘要里放一个**常见**词与一个**稀有**词，让检索耗时的两种形态
                // （命中很多 / 命中很少）都能被同一份数据覆盖。
                summary: Value<String?>(
                  i % 3 == 0
                      ? '摘要：本文讨论离线缓存的实现，第 $i 篇。'
                      : '摘要：第 $i 篇的一般性说明，涉及「稀有词条$i」的表述。',
                ),
                body: Value<String?>(_bodyFor(i, rng)),
                publishedAt: Value<DateTime?>(
                  base.subtract(Duration(minutes: i)),
                ),
                fetchedAt: Value<DateTime>(base.subtract(Duration(minutes: i))),
                readingState: Value<ReadingState>(
                  i % 4 == 0 ? ReadingState.read : ReadingState.unread,
                ),
                favorite: Value<bool>(i % 50 == 0),
              ),
            );
      }
    });
    inserted = end;
    onProgress?.call(inserted, spec.articleCount);
  }

  // 长文：单独一篇，正文恰为 100000 个字符（架构第 8 节的验收集要求）。
  final String longBody = _longBody(spec.longArticleCharacters);
  final int longId = await db
      .into(db.articles)
      .insert(
        ArticlesCompanion.insert(
          feedId: Value<int?>(feedIds.first),
          title: '超长文章（十万字）性能样本',
          identityBasis: IdentityBasis.guid,
          guid: const Value<String?>('perf-guid-long'),
          guidPresent: const Value<bool>(true),
          summary: const Value<String?>('摘要：十万字长文，用于排版与滚动基线。'),
          body: Value<String?>(longBody),
          publishedAt: Value<DateTime?>(base),
          fetchedAt: Value<DateTime>(base),
        ),
      );

  return PerfDatasetReport(
    feeds: spec.feedCount,
    articles: spec.articleCount + 1,
    longArticleId: longId,
    longArticleCharacters: longBody.length,
  );
}

/// 一篇普通文章的正文（含可检索的中文片段与一段代码）。
String _bodyFor(int index, _Rng rng) {
  final StringBuffer buffer = StringBuffer()
    ..writeln('## 正文 $index')
    ..writeln()
    ..writeln('本文说明离线阅读与缓存设计的第 $index 节。')
    ..writeln();
  for (int i = 0; i < 6; i++) {
    buffer
      ..writeln(
        '第 ${i + 1} 段：离线缓存需要在网络恢复后合并改动，'
        '编号 ${rng.nextInt(100000)} 的记录说明了这一点。',
      )
      ..writeln();
  }
  buffer
    ..writeln('```dart')
    ..writeln('// 代码块也进入检索索引')
    ..writeln('final cache = OfflineCache(limit: ${rng.nextInt(4096)});')
    ..writeln('```');
  return buffer.toString();
}

/// 十万字长文：分成标题与段落，保证能被解析成正常文档树。
String _longBody(int characters) {
  final StringBuffer buffer = StringBuffer();
  int section = 0;
  while (buffer.length < characters) {
    section++;
    buffer
      ..writeln('## 第 $section 节 长文结构')
      ..writeln()
      ..writeln(
        '这是第 $section 段的正文，用来构成一篇足够长的文档，'
        '覆盖排版、图像占位与代码块折叠等路径。',
      )
      ..writeln();
    if (section % 7 == 0) {
      buffer
        ..writeln('| 列 A | 列 B |')
        ..writeln('| --- | --- |')
        ..writeln('| $section | 值 |')
        ..writeln();
    }
  }
  // 按字符截断到严格的目标长度（架构第 8 节要求的是「100000 字符」这个量级）。
  return buffer.toString().substring(0, characters);
}

/// 确定性线性同余发生器。
///
/// 不用 dart:math 的 Random(seed)：它的算法实现细节是库的私有约定，跨 Dart 版本
/// 可能变化；基线要能与下一次比较，因此这里自带一个固定算法。
final class _Rng {
  _Rng(int seed) : _state = seed & 0x7fffffff;

  int _state;

  int nextInt(int max) {
    _state = (_state * 1103515245 + 12345) & 0x7fffffff;
    return _state % max;
  }
}
