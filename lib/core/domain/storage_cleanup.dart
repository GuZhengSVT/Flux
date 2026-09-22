// 存储清理的**纯规则**（T047；架构 5.3「清理、备份和统计」的清理段、SET-077/078/079/080）。
//
// 架构原话：「分类显示媒体、文章正文、新闻总结、设置/状态数据库、其他缓存与测量时间。清缓存
// 只删可再生内容，不删付费 AI 结果、状态、订阅、prompt 或秘密。」「自动媒体/正文/总结清理分别
// 有开关与天数；默认关闭。收藏默认保护，later 默认保护；主动删除订阅不受自动清理保护规则阻止，
// 必须在确认页说明。只释放正文时保留身份和状态，防止刷新把文章复活成未读。」「总结引用用最小
// 快照……用户彻底删除时列出关联摘要/引用/缓存并清理，不能留下隐藏副本。」
//
// 为什么这些规则不写在用例或存储实现里：它们全是**可断言的判定**（哪一类算占用、哪一篇文章
// 该被保护、天数边界怎么算、孤儿快照算不算可回收），用纯函数表达才能逐条钉住，而埋在文件系统
// 与 SQL 里就只能靠「造一堆真实文件再数一遍」去验证，既慢又容易被实现细节牵动。
library;

/// 存储占用的分类（架构 5.3 的分类显示口径）。
///
/// 每一类对应「清理它会不会丢东西」这一件事的判断：
///   * [mediaCache] 与 [otherCache] 是可再生的（图片能重下、AI 结果能重算）；
///   * [articleBody] 是**用户数据的一部分**（正文来自源，可重新抓取，但要保留身份与状态）；
///   * [newsSummary] 是花钱生成的结果，清理它必须由用户明确开启；
///   * [database] 是设置与状态本体，任何清理动作都不得触碰它。
enum StorageCategory {
  /// 媒体（图片）缓存。
  mediaCache,

  /// 文章正文（源正文与主动提取的正文）。
  articleBody,

  /// 新闻总结（每日新闻版本与它们的草稿）。
  newsSummary,

  /// 其他缓存（AI 结果缓存、失败任务草稿）。
  otherCache,

  /// 设置与状态数据库。
  database,
}

/// 一类的占用统计。
final class StorageCategoryUsage {
  /// 构造统计。
  const StorageCategoryUsage({
    required this.category,
    required this.byteCount,
    required this.itemCount,
  });

  /// 分类。
  final StorageCategory category;

  /// 字节数。
  final int byteCount;

  /// 条目数（媒体文件数、文章数、总结版本数、缓存行数；数据库类为 1）。
  final int itemCount;
}

/// 一次占用测量。
final class StorageUsageReport {
  /// 构造测量结果。
  const StorageUsageReport({
    required this.categories,
    required this.measuredAt,
    this.mediaLimitBytes,
  });

  /// 各类占用（顺序即界面展示顺序）。
  final List<StorageCategoryUsage> categories;

  /// 测量时刻（UTC；架构 5.3 要求显示测量时间——一个没有时间的数字，用户无法判断它
  /// 是否还对应得上当前状态）。
  final DateTime measuredAt;

  /// 媒体缓存上限字节（SET-080）；未知为 null。
  final int? mediaLimitBytes;

  /// 合计字节。
  int get totalBytes => categories.fold<int>(
    0,
    (int sum, StorageCategoryUsage usage) => sum + usage.byteCount,
  );

  /// 取某一类的占用；缺失时返回 0（而不是抛错：界面不该因为少一类就整页失败）。
  StorageCategoryUsage usageOf(StorageCategory category) =>
      categories.firstWhere(
        (StorageCategoryUsage usage) => usage.category == category,
        orElse: () => StorageCategoryUsage(
          category: category,
          byteCount: 0,
          itemCount: 0,
        ),
      );
}

/// 自动清理策略（SET-077 的三个独立开关与天数 + SET-078 的两个保护开关）。
///
/// 三个开关**默认全关**，因此「什么都没配」等于「不自动删任何东西」——把默认值写成
/// 开启会让一次升级后的首个启动就悄悄删掉用户的正文。
final class AutoCleanupPolicy {
  /// 构造策略。
  const AutoCleanupPolicy({
    required this.mediaEnabled,
    required this.mediaDays,
    required this.articleEnabled,
    required this.articleDays,
    required this.summaryEnabled,
    required this.summaryDays,
    required this.includeFavorite,
    required this.includeLater,
  });

  /// SET-077 的默认策略：全关 + 30/90/365 + 不包含收藏与 later。
  ///
  /// 默认值取自注册表口径而不是在这里另写一份常量：两处各写一份，迟早有一处漂移，
  /// 而症状是「界面上是关的、实际按开跑」。
  static const AutoCleanupPolicy defaults = AutoCleanupPolicy(
    mediaEnabled: false,
    mediaDays: 30,
    articleEnabled: false,
    articleDays: 90,
    summaryEnabled: false,
    summaryDays: 365,
    includeFavorite: false,
    includeLater: false,
  );

  /// 是否自动清理媒体缓存。
  final bool mediaEnabled;

  /// 媒体按「最后访问」保留的天数。
  final int mediaDays;

  /// 是否自动释放文章正文。
  final bool articleEnabled;

  /// 正文按「发布/抓取时间」保留的天数。
  final int articleDays;

  /// 是否自动清理新闻总结。
  final bool summaryEnabled;

  /// 总结按「创建时间」保留的天数。
  final int summaryDays;

  /// 自动清理是否包含收藏文章（SET-078，默认否）。
  final bool includeFavorite;

  /// 自动清理是否包含 later 文章（SET-078，默认否）。
  final bool includeLater;

  /// 三个自动开关是否全关。
  bool get isFullyDisabled =>
      !mediaEnabled && !articleEnabled && !summaryEnabled;

  /// 复制并覆盖部分字段。
  ///
  /// 界面每次改一个开关/天数时都用它构造下一个策略：复合设置项必须**整块写**（注册表按字段
  /// 校验一个 Map），因此只写被改的字段会让其余字段落回默认值（表现为「打开媒体清理把正文的
  /// 天数重置了」）。
  AutoCleanupPolicy copyWith({
    bool? mediaEnabled,
    int? mediaDays,
    bool? articleEnabled,
    int? articleDays,
    bool? summaryEnabled,
    int? summaryDays,
    bool? includeFavorite,
    bool? includeLater,
  }) => AutoCleanupPolicy(
    mediaEnabled: mediaEnabled ?? this.mediaEnabled,
    mediaDays: mediaDays ?? this.mediaDays,
    articleEnabled: articleEnabled ?? this.articleEnabled,
    articleDays: articleDays ?? this.articleDays,
    summaryEnabled: summaryEnabled ?? this.summaryEnabled,
    summaryDays: summaryDays ?? this.summaryDays,
    includeFavorite: includeFavorite ?? this.includeFavorite,
    includeLater: includeLater ?? this.includeLater,
  );

  /// 从设置值构造。
  ///
  /// 单个字段缺失/类型不对时**逐项回退**到默认值，而不是整体失败：一个被写坏的天数字段
  /// 不该让另外两个开关的意图一起失效。
  factory AutoCleanupPolicy.fromSettings(
    Map<String, Object?>? set077,
    Map<String, Object?>? set078,
  ) {
    bool flag(Map<String, Object?>? map, String key, bool fallback) {
      final Object? value = map?[key];
      return value is bool ? value : fallback;
    }

    int days(Map<String, Object?>? map, String key, int fallback) {
      final Object? value = map?[key];
      if (value is int && value >= 1) {
        return value;
      }
      return fallback;
    }

    const AutoCleanupPolicy d = AutoCleanupPolicy.defaults;
    return AutoCleanupPolicy(
      mediaEnabled: flag(set077, 'mediaEnabled', d.mediaEnabled),
      mediaDays: days(set077, 'mediaDays', d.mediaDays),
      articleEnabled: flag(set077, 'articleEnabled', d.articleEnabled),
      articleDays: days(set077, 'articleDays', d.articleDays),
      summaryEnabled: flag(set077, 'summaryEnabled', d.summaryEnabled),
      summaryDays: days(set077, 'summaryDays', d.summaryDays),
      includeFavorite: flag(set078, 'includeFavorite', d.includeFavorite),
      includeLater: flag(set078, 'includeLater', d.includeLater),
    );
  }
}

/// 天数的边界时刻：早于它即到期。
///
/// 用「now - days」而不是「本地日期减天数」：保留期是一个**时长**（「30 天前的图」），
/// 按本地日期算会在时区变化或夏令时切换时多留或少留一整天，而用户无法解释那个偏差。
DateTime cleanupCutoff({required int days, required DateTime nowUtc}) =>
    nowUtc.toUtc().subtract(Duration(days: days < 1 ? 1 : days));

/// 一个时间戳是否已到期（严格早于截止时刻）。
///
/// [at] 为 null 时返回 false（**不猜**）：没有时间戳的行不参与自动清理。用当前时间顶上
/// 去会让一次导入缺时间的旧文章立刻被删。
bool isCleanupExpired({required DateTime? at, required DateTime cutoffUtc}) =>
    at != null && at.toUtc().isBefore(cutoffUtc);

/// 一篇文章是否被保护规则挡住（SET-078）。
///
/// 收藏与 later **默认**被保护；只有对应开关打开时才参与自动清理。两个开关分开而不是
/// 一个「包含受保护文章」：用户可能只想清理已读的普通文章，却仍希望 later 队列里的东西
/// 一直留着（later 是待办清单，被自动清空比占几百 KB 严重得多）。
bool protectsFromAutoCleanup({
  required bool favorite,
  required bool later,
  required bool includeFavorite,
  required bool includeLater,
}) => (favorite && !includeFavorite) || (later && !includeLater);

/// 一次自动清理的**预估影响**（预览与执行结果共用同一形状，因此预览里的数字与执行后的
/// 数字可以直接比对；用两个结构表达会让「预览说 3 篇、实际删了 5 篇」无法被断言）。
final class CleanupImpact {
  /// 构造影响。
  const CleanupImpact({
    this.mediaEntries = 0,
    this.mediaBytes = 0,
    this.articleBodies = 0,
    this.articleBodyBytes = 0,
    this.summaryRuns = 0,
    this.summaryBytes = 0,
    this.aiCacheEntries = 0,
    this.aiCacheBytes = 0,
    this.failedTaskDrafts = 0,
    this.protectedArticles = 0,
  });

  /// 将被删除的媒体条目数。
  final int mediaEntries;

  /// 媒体字节。
  final int mediaBytes;

  /// 将被释放正文的文章数。
  final int articleBodies;

  /// 正文字节。
  final int articleBodyBytes;

  /// 将被删除的总结版本数。
  final int summaryRuns;

  /// 总结字节。
  final int summaryBytes;

  /// 将被删除的 AI 结果缓存条数。
  final int aiCacheEntries;

  /// AI 结果缓存字节。
  final int aiCacheBytes;

  /// 将被清理的失败任务草稿数。
  final int failedTaskDrafts;

  /// 因为保护规则（收藏/later）而**被跳过**的文章数。
  ///
  /// 它必须出现在预览里：用户勾选「包含收藏」前后，这个数字的变化正是他能看到的区别。
  /// 只报「将清理 N 篇」而不报「跳过了 M 篇」，用户无法判断保护规则是否真的生效。
  final int protectedArticles;

  /// 合计将释放的字节。
  int get totalBytes =>
      mediaBytes + articleBodyBytes + summaryBytes + aiCacheBytes;

  /// 是否什么都不动（界面据此禁用确认按钮并如实说明）。
  bool get isEmpty =>
      mediaEntries == 0 &&
      articleBodies == 0 &&
      summaryRuns == 0 &&
      aiCacheEntries == 0 &&
      failedTaskDrafts == 0;
}

/// 孤儿快照的可回收判定（T042 遗留：判据在 T042，GC 属 T047）。
///
/// 与 [orphanSnapshots] 的分工：那条规则回答「哪些名字不是当前版本」，这条再加上
/// **时间**维度——一个刚上传、manifest 还没写完的快照也是「不是当前版本」，立刻删它等于
/// 和另一个正在发布的设备赛跑（它马上就会写 manifest 指向那份快照）。因此只回收「既不是
/// 当前版本、也没有被引用、而且已经存在超过保留天数」的快照。
///
/// [lastModifiedByName] 缺失的名字**不回收**：拿不到时间就不猜，等到下一次能拿到时间时
/// 再处理（服务器不返回 getlastmodified 是正常情况）。
List<String> orphanSnapshotsToCollect({
  required List<String> remoteSnapshotNames,
  required Set<String> referencedNames,
  required Map<String, DateTime> lastModifiedByName,
  required int retentionDays,
  required DateTime nowUtc,
}) {
  final DateTime cutoff = cleanupCutoff(days: retentionDays, nowUtc: nowUtc);
  return remoteSnapshotNames
      .where((String name) => !referencedNames.contains(name))
      .where(
        (String name) =>
            isCleanupExpired(at: lastModifiedByName[name], cutoffUtc: cutoff),
      )
      .toList(growable: false);
}

/// 孤儿快照的默认保留天数。
///
/// 为什么是 90 天而不是几天：孤儿快照是**内容寻址**的（名字即内容），另一台设备可能在
/// 离线很久之后回来，把「历史上某一版」当成合并基线（架构 5.2 允许父版本链仍被引用）。
/// 90 天覆盖了「出差两个月回来同步一次」这种真实用法，而更长的保留期没有收益——真正的
/// 当前版本永远不会被这条规则碰到。
const int kOrphanSnapshotRetentionDays = 90;

/// 一把「彻底删除」的关联范围（架构 5.3「用户彻底删除时列出关联摘要/引用/缓存并清理，不能留下
/// 隐藏副本」）。
final class ArticlePurgeImpact {
  /// 构造范围。
  const ArticlePurgeImpact({
    required this.articleId,
    required this.title,
    this.citations = 0,
    this.aiSummaries = 0,
    this.translations = 0,
    this.readingSessions = 0,
    this.cachedMedia = 0,
    this.newsReferences = 0,
  });

  /// 文章 id。
  final int articleId;

  /// 标题（确认页要能说明「删的是哪一篇」，因此这里允许带展示用标题——它不是正文，也不是
  /// prompt，与墓碑的 displayName 同一口径）。
  final String title;

  /// 关联的引用条数（citations.article_id 会被置空而不是删除——架构 4.4 要求引用保留最小快照
  /// 作为历史总结的出处，而「指向本机文章」这个指针要断掉）。
  final int citations;

  /// 关联的 AI 摘要数（articles.ai_summary 三列）。
  final int aiSummaries;

  /// 关联的译文数（article_translation_records，级联删除）。
  final int translations;

  /// 关联的阅读会话数。
  final int readingSessions;

  /// 关联的媒体缓存条目数（正文图片的缓存文件按地址哈希命名，删除时一并回收）。
  final int cachedMedia;

  /// 被这条新闻引用记到的次数（news_runs 的引用指向本机文章时）。
  final int newsReferences;

  /// 是否有关联内容需要清理。
  bool get hasRelated =>
      citations > 0 ||
      aiSummaries > 0 ||
      translations > 0 ||
      readingSessions > 0 ||
      cachedMedia > 0 ||
      newsReferences > 0;
}
