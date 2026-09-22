// 存储清理用例（T047；架构 5.3 的清理段、SET-077/078/079/080）。
//
// 这个用例把「清理」拆成**三类互不相同**的动作，因为它们的后果完全不同：
//
//   1) **一键清缓存**（[clearRegenerable]）：只删可再生内容——媒体缓存、AI 结果缓存、
//      失败任务草稿。付费成功结果（新闻总结、成功任务的产出）**不在**它的范围内；
//   2) **自动清理**（[runAutoCleanup]）：按 SET-077 的三个独立开关与天数，在保护规则
//      （SET-078 的收藏/later）下执行。三个开关默认全关，因此默认路径不删任何东西；
//   3) **彻底删除**（[purgeArticle]）：用户显式删除一篇文章，连带清理它的一切关联，
//      **不留隐藏副本**。这是唯一会删用户数据的路径，因此它先给出关联范围再执行。
//
// 三条不变量贯穿全部动作：
//   * **阅读状态、收藏、订阅、prompt、秘密永不参与清理**。前四个在接口层面就不可表达
//     （没有任何方法能改它们），秘密则根本不住在库里（SET-071/SET-027 只进 Keychain）；
//   * **预览与执行共用同一种影响结构**，因此「预览说释放 3 MiB、实际释放 3 MiB」可以被断言；
//   * **只释放正文时保留身份**：正文置空但行、GUID、同步键、状态与收藏都在原处，因此下一次
//     刷新按同样的身份规则匹配到**这一行**，而不是为同一篇文章插出一行新的未读。
library;

import 'package:flux/core/core.dart';

import 'cleanup_ports.dart';

/// 一次孤儿快照 GC 的结论。
final class SnapshotGcResult {
  /// 构造结论。
  const SnapshotGcResult({
    required this.considered,
    required this.collected,
    this.skippedForMissingTime = 0,
  });

  /// 远端快照总数。
  final int considered;

  /// 实际回收的名字。
  final List<String> collected;

  /// 因为没有最后修改时间而**跳过**的数量（服务器不返回 getlastmodified 时的正常结果）。
  final int skippedForMissingTime;
}

/// 存储清理用例。
final class CleanupService {
  /// 构造用例。
  const CleanupService({
    required this.store,
    required this.mediaCache,
    this.snapshotGc,
    this.diagnostics = const NoopDiagnosticSink(),
    this.clock = const SystemClock(),
  });

  /// 存储清理数据端口。
  final StorageCleanupStore store;

  /// 媒体缓存端口（图片磁盘缓存）。
  final MediaCachePort mediaCache;

  /// 远端快照 GC 端口；null 表示未配置同步（GC 无目标）。
  final SnapshotGcPort? snapshotGc;

  /// 诊断记录（只记类别与计数，不记标题与正文）。
  final DiagnosticSink diagnostics;

  /// 时钟（测量时刻与到期判定）。
  final Clock clock;

  /// 分类占用统计（设置 → 存储页）。
  ///
  /// [mediaLimitMiB] 来自 SET-080：统计里要显示「512 MiB 上限、已用 40 MiB」，因为一个没有
  /// 参照的绝对值无法让用户判断「这算不算大」。
  ///
  /// 媒体那一类在这里补上：它住在文件系统（媒体端口），而其余四类是数据库行的统计。合并时
  /// **媒体端口失败不导致整次统计失败**——其余四类仍然可读，而「看不到任何分类」比「少一类」
  /// 对用户更糟。失败的那一类按 0 显示，并在诊断里留一条结构性记录。
  Future<Result<StorageUsageReport>> measure({
    required int mediaLimitMiB,
  }) async {
    final DateTime measuredAt = clock.now().toUtc();
    final Result<StorageUsageReport> db = await store.measureDatabase(
      measuredAt: measuredAt,
    );
    if (db.isErr) {
      return db;
    }
    final Result<
      ({int entryCount, int imageBytes, int metaBytes, int tempBytes})
    >
    usage = await mediaCache.diskUsage();
    int mediaBytes = 0;
    int mediaEntries = 0;
    if (usage.isOk) {
      // 把元数据与半成品的字节也算进「媒体缓存」这一类：它们确实占着磁盘，而用户看到的
      // 「分类占用」应当能与他看到的目录大小对得上（只报图片字节会偏小）。
      mediaBytes =
          usage.unwrap().imageBytes +
          usage.unwrap().metaBytes +
          usage.unwrap().tempBytes;
      mediaEntries = usage.unwrap().entryCount;
    } else {
      diagnostics.warning(
        '媒体缓存占用读取失败：${usage.errorOrNull!.kind}',
        tag: 'cleanup.measure',
      );
    }
    final List<StorageCategoryUsage> categories = <StorageCategoryUsage>[
      StorageCategoryUsage(
        category: StorageCategory.mediaCache,
        byteCount: mediaBytes,
        itemCount: mediaEntries,
      ),
      for (final StorageCategoryUsage item in db.unwrap().categories)
        if (item.category != StorageCategory.mediaCache) item,
    ];
    return Ok<StorageUsageReport>(
      StorageUsageReport(
        categories: categories,
        measuredAt: measuredAt,
        mediaLimitBytes: cacheLimitBytes(mediaLimitMiB),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // 一键清缓存（SET-079）
  // -------------------------------------------------------------------------

  /// 预览「一键清缓存」会释放什么（**只读**，用户确认前的依据）。
  ///
  /// 这是 SET-079「清理预览」的落点：没有预览的清理按钮等于让用户闭着眼睛删。
  Future<Result<CleanupImpact>> previewClearRegenerable() async {
    final Result<({int entries, int bytes})> media = await mediaCache.stats();
    if (media.isErr) {
      return Err<CleanupImpact>(media.errorOrNull!);
    }
    final Result<({int entries, int bytes})> ai = await store.aiCacheUsage();
    if (ai.isErr) {
      return Err<CleanupImpact>(ai.errorOrNull!);
    }
    final Result<({int entries, int bytes})> drafts = await store
        .failedTaskDraftUsage();
    if (drafts.isErr) {
      return Err<CleanupImpact>(drafts.errorOrNull!);
    }
    return Ok<CleanupImpact>(
      CleanupImpact(
        mediaEntries: media.unwrap().entries,
        mediaBytes: media.unwrap().bytes,
        aiCacheEntries: ai.unwrap().entries,
        aiCacheBytes: ai.unwrap().bytes,
        failedTaskDrafts: drafts.unwrap().entries,
      ),
    );
  }

  /// 执行一键清缓存：媒体缓存全清、AI 结果缓存全清、失败任务草稿清理。
  ///
  /// 三件事都**只删可再生内容**：
  ///   * 媒体缓存：图片可以从源重新下载（架构 4.2 的按需缓存）；
  ///   * AI 结果缓存：命中缓存只是省一次请求，删掉之后下一次同样输入会真实请求一次；
  ///   * 失败任务草稿：失败/取消/中断的任务行不是产出，用户看到它们只是为了知道「跑过」；
  ///     成功与进行中的任务行**不动**（前者是付费结果，后者可能还在跑）。
  ///
  /// 明确**不**动的：新闻总结版本（付费结果）、成功任务的产出、阅读状态、收藏、订阅、
  /// prompt 与秘密。界面在确认页里说明这一点，并提示付费结果需要单独处理。
  Future<Result<CleanupImpact>> clearRegenerable() async {
    // **先读后删**：删除之后再统计只能得到 0，而回执里的「释放了 X MB」是一个用户要看的
    // 真实数字。三个读数都在删除之前取，因此它们描述的是「这次动作释放了什么」。
    final Result<({int entries, int bytes})> mediaBefore = await mediaCache
        .stats();
    if (mediaBefore.isErr) {
      return Err<CleanupImpact>(mediaBefore.errorOrNull!);
    }
    final Result<({int entries, int bytes})> aiBefore = await store
        .aiCacheUsage();
    if (aiBefore.isErr) {
      return Err<CleanupImpact>(aiBefore.errorOrNull!);
    }
    final Result<({int entries, int bytes})> draftsBefore = await store
        .failedTaskDraftUsage();
    if (draftsBefore.isErr) {
      return Err<CleanupImpact>(draftsBefore.errorOrNull!);
    }

    final Result<int> media = await mediaCache.clearAll();
    if (media.isErr) {
      return Err<CleanupImpact>(media.errorOrNull!);
    }
    final Result<({int entries, int bytes})> ai = await store
        .clearAiResultCache();
    if (ai.isErr) {
      return Err<CleanupImpact>(ai.errorOrNull!);
    }
    final Result<({int entries, int bytes})> drafts = await store
        .clearFailedTaskDrafts();
    if (drafts.isErr) {
      return Err<CleanupImpact>(drafts.errorOrNull!);
    }
    diagnostics.info(
      '一键清缓存：媒体 ${media.unwrap()} 个文件、AI 结果 ${aiBefore.unwrap().entries} 条、失败草稿 ${draftsBefore.unwrap().entries} 条',
      tag: 'cleanup.manual',
    );
    return Ok<CleanupImpact>(
      CleanupImpact(
        mediaEntries: mediaBefore.unwrap().entries,
        mediaBytes: mediaBefore.unwrap().bytes,
        aiCacheEntries: aiBefore.unwrap().entries,
        aiCacheBytes: aiBefore.unwrap().bytes,
        failedTaskDrafts: draftsBefore.unwrap().entries,
      ),
    );
  }

  // -------------------------------------------------------------------------
  // 自动清理（SET-077 / SET-078）
  // -------------------------------------------------------------------------

  /// 预览自动清理的影响（**只读**）。
  ///
  /// 三个开关都关闭时直接返回空影响并**不访问存储**：这是默认状态，而「默认什么都不做」
  /// 应当是一条不依赖任何 I/O 的短路（否则每次启动都要为一件不会发生的事扫一遍库与缓存）。
  Future<Result<CleanupImpact>> previewAutoCleanup(
    AutoCleanupPolicy policy,
  ) async {
    if (policy.isFullyDisabled) {
      return const Ok<CleanupImpact>(CleanupImpact());
    }
    final DateTime nowUtc = clock.now().toUtc();
    int mediaEntries = 0;
    int mediaBytes = 0;
    if (policy.mediaEnabled) {
      final Result<({int entries, int bytes})> expired = await mediaCache
          .expiredUsage(
            cutoffUtc: cleanupCutoff(days: policy.mediaDays, nowUtc: nowUtc),
          );
      if (expired.isErr) {
        return Err<CleanupImpact>(expired.errorOrNull!);
      }
      mediaEntries = expired.unwrap().entries;
      mediaBytes = expired.unwrap().bytes;
    }
    int bodies = 0;
    int bodyBytes = 0;
    int protectedArticles = 0;
    if (policy.articleEnabled) {
      final Result<({CleanupImpact impact, List<int> articleIds})> planned =
          await store.planArticleBodyRelease(
            cutoffUtc: cleanupCutoff(days: policy.articleDays, nowUtc: nowUtc),
            includeFavorite: policy.includeFavorite,
            includeLater: policy.includeLater,
          );
      if (planned.isErr) {
        return Err<CleanupImpact>(planned.errorOrNull!);
      }
      bodies = planned.unwrap().impact.articleBodies;
      bodyBytes = planned.unwrap().impact.articleBodyBytes;
      protectedArticles = planned.unwrap().impact.protectedArticles;
    }
    int summaries = 0;
    int summaryBytes = 0;
    if (policy.summaryEnabled) {
      final Result<({CleanupImpact impact, List<int> runIds})> planned =
          await store.planSummaryCleanup(
            cutoffUtc: cleanupCutoff(days: policy.summaryDays, nowUtc: nowUtc),
          );
      if (planned.isErr) {
        return Err<CleanupImpact>(planned.errorOrNull!);
      }
      summaries = planned.unwrap().impact.summaryRuns;
      summaryBytes = planned.unwrap().impact.summaryBytes;
    }
    return Ok<CleanupImpact>(
      CleanupImpact(
        mediaEntries: mediaEntries,
        mediaBytes: mediaBytes,
        articleBodies: bodies,
        articleBodyBytes: bodyBytes,
        summaryRuns: summaries,
        summaryBytes: summaryBytes,
        protectedArticles: protectedArticles,
      ),
    );
  }

  /// 执行自动清理；返回**实际**影响。
  ///
  /// 顺序是媒体 → 正文 → 总结，与预览的顺序一致：某一步失败时前面的步骤已经生效，因此
  /// 调用方拿到的是一个部分完成的结果（而不是一个「全失败」）。这是刻意的——把三步包成
  /// 一个「全或无」会让一次磁盘错误阻止所有类别的清理，而它们之间本来没有依赖。
  Future<Result<CleanupImpact>> runAutoCleanup(AutoCleanupPolicy policy) async {
    if (policy.isFullyDisabled) {
      return const Ok<CleanupImpact>(CleanupImpact());
    }
    final DateTime nowUtc = clock.now().toUtc();

    int mediaEntries = 0;
    int mediaBytes = 0;
    if (policy.mediaEnabled) {
      final Result<({int entries, int bytes})> removed = await mediaCache
          .deleteExpired(
            cutoffUtc: cleanupCutoff(days: policy.mediaDays, nowUtc: nowUtc),
          );
      if (removed.isErr) {
        return Err<CleanupImpact>(removed.errorOrNull!);
      }
      mediaEntries = removed.unwrap().entries;
      mediaBytes = removed.unwrap().bytes;
    }

    int articles = 0;
    int bodyBytes = 0;
    int protectedArticles = 0;
    if (policy.articleEnabled) {
      final Result<({CleanupImpact impact, List<int> articleIds})> planned =
          await store.planArticleBodyRelease(
            cutoffUtc: cleanupCutoff(days: policy.articleDays, nowUtc: nowUtc),
            includeFavorite: policy.includeFavorite,
            includeLater: policy.includeLater,
          );
      if (planned.isErr) {
        return Err<CleanupImpact>(planned.errorOrNull!);
      }
      protectedArticles = planned.unwrap().impact.protectedArticles;
      final Result<({int articles, int bytes})> released = await store
          .releaseArticleBodies(articleIds: planned.unwrap().articleIds);
      if (released.isErr) {
        return Err<CleanupImpact>(released.errorOrNull!);
      }
      articles = released.unwrap().articles;
      bodyBytes = released.unwrap().bytes;
    }

    int summaries = 0;
    int summaryBytes = 0;
    if (policy.summaryEnabled) {
      final Result<({CleanupImpact impact, List<int> runIds})> planned =
          await store.planSummaryCleanup(
            cutoffUtc: cleanupCutoff(days: policy.summaryDays, nowUtc: nowUtc),
          );
      if (planned.isErr) {
        return Err<CleanupImpact>(planned.errorOrNull!);
      }
      final Result<({int runs, int bytes})> removed = await store
          .deleteSummaryRuns(runIds: planned.unwrap().runIds);
      if (removed.isErr) {
        return Err<CleanupImpact>(removed.errorOrNull!);
      }
      summaries = removed.unwrap().runs;
      summaryBytes = removed.unwrap().bytes;
    }

    final CleanupImpact impact = CleanupImpact(
      mediaEntries: mediaEntries,
      mediaBytes: mediaBytes,
      articleBodies: articles,
      articleBodyBytes: bodyBytes,
      summaryRuns: summaries,
      summaryBytes: summaryBytes,
      protectedArticles: protectedArticles,
    );
    if (!impact.isEmpty) {
      diagnostics.info(
        '自动清理：媒体 ${impact.mediaEntries} 个、正文 ${impact.articleBodies} 篇、总结 ${impact.summaryRuns} 版（保护跳过 ${impact.protectedArticles} 篇）',
        tag: 'cleanup.auto',
      );
    }
    return Ok<CleanupImpact>(impact);
  }

  /// 按 SET-080 的新上限裁剪媒体缓存（设置页改上限后调用）。
  ///
  /// 返回该动作本身的结果而不是「删了几条」：上限变更的**效果**是「此后的写入会按新上限
  /// 淘汰」，而它是否当场删掉了东西取决于当时占用，不是这个动作的结论。界面若要显示释放量，
  /// 在调用前后各读一次 [measure] 即可（两处用同一份统计，不会出现两套口径）。
  Future<Result<void>> applyMediaLimit(int limitMiB) =>
      mediaCache.applyLimitMiB(limitMiB);

  // -------------------------------------------------------------------------
  // 彻底删除（架构 5.3）
  // -------------------------------------------------------------------------

  /// 列出彻底删除一篇文章会连带清理什么（**只读**，确认页的依据）。
  Future<Result<ArticlePurgeImpact>> previewArticlePurge(int articleId) =>
      store.articlePurgeImpact(articleId);

  /// 彻底删除一篇文章与其关联（架构 5.3「不能留下隐藏副本」）。
  ///
  /// 与「按正文释放」完全不同：释放保身份（行仍在，刷新能匹配上），彻底删除把行也删掉，
  /// 因此同步层会把这次删除当作一次需要传播的事实（墓碑由同步层的既有规则处理）。
  Future<Result<ArticlePurgeImpact>> purgeArticle(int articleId) async {
    final Result<ArticlePurgeImpact> purged = await store.purgeArticle(
      articleId,
    );
    if (purged.isErr) {
      return purged;
    }
    diagnostics.info(
      '彻底删除文章 id=$articleId：引用 ${purged.unwrap().citations}、译文 ${purged.unwrap().translations}、会话 ${purged.unwrap().readingSessions}',
      tag: 'cleanup.purge',
    );
    return purged;
  }

  // -------------------------------------------------------------------------
  // 孤儿快照 GC（T042 遗留）
  // -------------------------------------------------------------------------

  /// 回收远端孤儿快照（既不是当前版本、也没有被引用、且超过保留天数）。
  ///
  /// 未配置同步（[snapshotGc] 为 null）时返回 `Ok(null)`：**这不是失败**，而是「无事可做」。
  /// 把它做成错误会让设置页在未配置同步的设备上显示一条与用户无关的报错。
  ///
  /// 判定所需的「被引用集合」由调用方给出（本机当前基线版本 + 远端 manifest 指向的名字）：
  /// 上一版仍可能被别的设备当作合并基线使用，因此**不能**只按「不是当前版本」删。
  Future<Result<SnapshotGcResult?>> collectOrphanSnapshots({
    required Set<String> referencedNames,
    int retentionDays = kOrphanSnapshotRetentionDays,
    bool dryRun = false,
  }) async {
    final SnapshotGcPort? gc = snapshotGc;
    if (gc == null) {
      return const Ok<SnapshotGcResult?>(null);
    }
    final Result<List<RemoteSnapshotFact>> listed = await gc.listSnapshots();
    if (listed.isErr) {
      return Err<SnapshotGcResult?>(listed.errorOrNull!);
    }
    final List<RemoteSnapshotFact> facts = listed.unwrap();
    final Map<String, DateTime> timestamps = <String, DateTime>{
      for (final RemoteSnapshotFact fact in facts)
        if (fact.lastModified != null) fact.name: fact.lastModified!.toUtc(),
    };
    final int skippedForMissingTime = facts
        .where(
          (RemoteSnapshotFact fact) =>
              fact.lastModified == null && !referencedNames.contains(fact.name),
        )
        .length;
    final List<String> orphans = orphanSnapshotsToCollect(
      remoteSnapshotNames: facts
          .map((RemoteSnapshotFact fact) => fact.name)
          .toList(growable: false),
      referencedNames: referencedNames,
      lastModifiedByName: timestamps,
      retentionDays: retentionDays,
      nowUtc: clock.now().toUtc(),
    );
    final List<String> collected = <String>[];
    if (!dryRun) {
      for (final String name in orphans) {
        final Result<bool> deleted = await gc.deleteSnapshot(name);
        if (deleted.isErr) {
          // 单个删除失败不中断整轮：远端 GC 是维护动作，一次权限错误（某个文件被别的
          // 客户端锁住）不该让其余的孤儿一直留着。失败项在下一轮还会被再次判定。
          diagnostics.warning(
            '孤儿快照删除失败：${deleted.errorOrNull!.kind}',
            tag: 'cleanup.snapshot',
          );
          continue;
        }
        if (deleted.unwrap()) {
          collected.add(name);
        }
      }
    }
    return Ok<SnapshotGcResult?>(
      SnapshotGcResult(
        considered: facts.length,
        collected: List<String>.unmodifiable(dryRun ? orphans : collected),
        skippedForMissingTime: skippedForMissingTime,
      ),
    );
  }
}
