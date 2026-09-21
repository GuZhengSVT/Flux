// OPML 导入/导出用例（T015；架构 4.1、SET-026/027）。
//
// 本文件实现架构 4.1 对 OPML 的四条契约：
//   - 导入可选「保留分组 / 全部未分类」，默认未分类以延续原交互（SET-026）；
//   - **预览**重复、无效和成功项，逐项取消/重试，不因一个失败源撤销全部结果；
//   - 重复导入按**规范地址**匹配已有订阅，不重置其状态；
//   - 导出交换标准订阅地址、名称及分组，不导出内部 ID、加精/刷新偏好或阅读状态。
//
// 三个刻意的设计选择：
//   1) 导入的每一步都是**独立条目**的结果（OpmlImportItemResult），不存在「整批
//      成功/整批失败」。架构 4.1 明确要求「不因一个失败源撤销全部结果」；
//   2) 预览阶段**不写任何数据**，因此用户可以反复看、反复取消；
//   3) 重试只针对失败项（retryFailed），不重跑已成功的条目——重跑会让「已成功」
//      的项多一次网络请求，而它们的成功与失败项的原因无关。
library;

import 'package:flux/core/core.dart';

import '../domain/article_identity.dart';
import '../domain/opml.dart';
import 'add_feed.dart';

/// 导入分组策略（SET-026）。
enum OpmlGroupStrategy {
  /// 全部放入未分类（文档口径的**默认值**）。
  uncategorized,

  /// 保留文件里的分组结构（按 OpmlEntry.groupPath 建组）。
  keepFileGroups,
}

/// 一个条目在预览里的状态。
enum OpmlPreviewStatus {
  /// 新订阅：导入会创建它。
  added,

  /// 已有订阅：导入会**跳过并保留其状态**（架构 4.1 要求不重置）。
  duplicate,

  /// 无效：文件里的地址不可用（缺 xmlUrl 或不是 http(s)）。
  invalid,
}

/// 预览里的一条明细。
class OpmlPreviewItem {
  /// 构造预览项。
  const OpmlPreviewItem({
    required this.index,
    required this.status,
    required this.title,
    this.url = '',
    this.groupPath = const <String>[],
    this.reason,
    this.existingFeedId,
  });

  /// 在文件中的 outline 序号（与解析层一致，便于用户在文件里定位）。
  final int index;

  /// 预览状态。
  final OpmlPreviewStatus status;

  /// 显示名。
  final String title;

  /// 文件里的原始地址（无效项可能为空）。
  final String url;

  /// 所属分组路径。
  final List<String> groupPath;

  /// 被判无效的原因（invalid 时非空）。
  final String? reason;

  /// 匹配到的已有订阅 id（duplicate 时非空）。
  final int? existingFeedId;
}

/// 一次导入预览。
class OpmlPreview {
  /// 构造预览。
  const OpmlPreview({
    required this.items,
    required this.document,
    required this.strategy,
    this.fileTitle,
  });

  /// 明细（顺序与文件一致）。
  final List<OpmlPreviewItem> items;

  /// 原始文档：确认导入时**复用**它，不再让用户重新选文件。
  final String document;

  /// 采用的策略。
  final OpmlGroupStrategy strategy;

  /// 文件标题。
  final String? fileTitle;

  /// 新增条目数。
  int get addedCount => items
      .where((OpmlPreviewItem i) => i.status == OpmlPreviewStatus.added)
      .length;

  /// 重复条目数。
  int get duplicateCount => items
      .where((OpmlPreviewItem i) => i.status == OpmlPreviewStatus.duplicate)
      .length;

  /// 无效条目数。
  int get invalidCount => items
      .where((OpmlPreviewItem i) => i.status == OpmlPreviewStatus.invalid)
      .length;

  /// 是否没有任何可导入项。
  bool get hasNothingToImport => addedCount == 0;
}

/// 单个条目的导入结果。
enum OpmlItemOutcome {
  /// 新建成功。
  imported,

  /// 已存在，跳过（不重置状态）。
  duplicate,

  /// 失败（带类型化原因，可重试）。
  failed,

  /// 文件里就无效（不可重试：地址本身不合法，重试不会变好）。
  invalid,
}

/// 一条明细的导入结果。
class OpmlImportItemResult {
  /// 构造结果。
  const OpmlImportItemResult({
    required this.index,
    required this.title,
    required this.url,
    required this.outcome,
    this.importedArticles = 0,
    this.error,
    this.feedId,
    this.groupPath = const <String>[],
  });

  /// 文件中的 outline 序号。
  final int index;

  /// 显示名。
  final String title;

  /// 地址。
  final String url;

  /// 结果类别。
  final OpmlItemOutcome outcome;

  /// 导入的文章数（imported 时有效）。
  final int importedArticles;

  /// 失败原因（failed 时非空）。
  final AppError? error;

  /// 涉及的订阅 id（成功或重复时非空）。
  final int? feedId;

  /// 该条目在文件里的分组路径。
  ///
  /// 结果页需要它：重试失败项时要按同一条路径落回原来的分组，否则「重试」会把订阅
  /// 从用户文件里的分组挪到未分类——一个看起来只是重试的动作实际改了归属。
  final List<String> groupPath;

  /// 是否可重试：只有「失败」值得重试。
  ///
  /// 「无效」不重试：地址本身不合法，重试的结果必然相同；把它算进可重试项会让
  /// 用户反复点击却永远清不掉。
  bool get isRetryable => outcome == OpmlItemOutcome.failed;
}

/// 一次导入的结果。
class OpmlImportResult {
  /// 构造结果。
  const OpmlImportResult({required this.items});

  /// 逐项结果（顺序与文件一致）。
  final List<OpmlImportItemResult> items;

  /// 成功导入数。
  int get importedCount => items
      .where((OpmlImportItemResult i) => i.outcome == OpmlItemOutcome.imported)
      .length;

  /// 重复跳过数。
  int get duplicateCount => items
      .where((OpmlImportItemResult i) => i.outcome == OpmlItemOutcome.duplicate)
      .length;

  /// 失败数（可重试）。
  int get failedCount => items
      .where((OpmlImportItemResult i) => i.outcome == OpmlItemOutcome.failed)
      .length;

  /// 文件中判定无效的条目数。
  int get invalidCount => items
      .where((OpmlImportItemResult i) => i.outcome == OpmlItemOutcome.invalid)
      .length;

  /// 导入的文章总数。
  int get importedArticleCount => items.fold(
    0,
    (int sum, OpmlImportItemResult i) => sum + i.importedArticles,
  );

  /// 是否有可重试的失败项。
  bool get hasRetryableFailures =>
      items.any((OpmlImportItemResult i) => i.isRetryable);

  /// 只保留可重试失败项的集合（供 retryFailed 使用）。
  List<OpmlImportItemResult> get retryableFailures => items
      .where((OpmlImportItemResult i) => i.isRetryable)
      .toList(growable: false);
}

/// OPML 导入用例。
class ImportOpmlUseCase {
  /// 构造用例。
  const ImportOpmlUseCase({
    required this.addFeed,
    required this.catalog,
    this.parserLimits = const OpmlParserLimits(),
  });

  /// 单源添加能力（T014 交付，复用其「抓取 → 解析 → 入库」与重复判定）。
  final AddFeedUseCase addFeed;

  /// 订阅/分组端口。
  final FeedCatalogStore catalog;

  /// OPML 解析限制。
  final OpmlParserLimits parserLimits;

  /// 解析 OPML 并生成预览；**不写任何数据**。
  ///
  /// 分组策略只影响预览里展示的归属提示与后续导入的落点，不改变「哪些是重复、
  /// 哪些无效」的判断——那是地址层面的匹配，与分组无关。
  Future<Result<OpmlPreview>> preview(
    String document, {
    OpmlGroupStrategy strategy = OpmlGroupStrategy.uncategorized,
  }) async {
    final Result<ParsedOpml> parsed = parseOpml(
      document,
      source: 'opml.import',
      limits: parserLimits,
    );
    if (parsed.isErr) {
      return Err<OpmlPreview>(parsed.errorOrNull!);
    }
    final ParsedOpml opml = parsed.unwrap();

    final List<OpmlPreviewItem> items = <OpmlPreviewItem>[];

    // 无效项与可用项要按**文件顺序**交错，用户看到的明细才与文件一致。
    // 解析层把两者分开返回，但共享同一套 outline 序号，这里按序号归并。
    final Map<int, OpmlEntry> entriesByIndex = <int, OpmlEntry>{
      for (final OpmlEntry entry in opml.entries) entry.outlineIndex: entry,
    };
    final Map<int, OpmlSkippedEntry> skippedByIndex = <int, OpmlSkippedEntry>{
      for (final OpmlSkippedEntry entry in opml.skipped) entry.index: entry,
    };
    final List<int> allIndexes = <int>[
      ...entriesByIndex.keys,
      ...skippedByIndex.keys,
    ]..sort();

    for (final int outlineIndex in allIndexes) {
      final OpmlSkippedEntry? skipped = skippedByIndex[outlineIndex];
      if (skipped != null) {
        items.add(
          OpmlPreviewItem(
            index: outlineIndex,
            status: OpmlPreviewStatus.invalid,
            title: skipped.title ?? '',
            url: skipped.xmlUrl ?? '',
            groupPath: skipped.groupPath,
            reason: describeOpmlIssue(skipped.reason),
          ),
        );
        continue;
      }
      final OpmlEntry entry = entriesByIndex[outlineIndex]!;
      final String normalized = normalizeLink(entry.xmlUrl) ?? entry.xmlUrl;
      final Result<FeedRecord?> existing = await catalog
          .findFeedByNormalizedUrl(normalized);
      if (existing.isErr) {
        return Err<OpmlPreview>(existing.errorOrNull!);
      }
      final FeedRecord? duplicate = existing.valueOrNull;
      items.add(
        OpmlPreviewItem(
          index: outlineIndex,
          status: duplicate == null
              ? OpmlPreviewStatus.added
              : OpmlPreviewStatus.duplicate,
          title: entry.title,
          url: entry.xmlUrl,
          groupPath: strategy == OpmlGroupStrategy.keepFileGroups
              ? entry.groupPath
              : const <String>[],
          existingFeedId: duplicate?.id,
        ),
      );
    }

    return Ok<OpmlPreview>(
      OpmlPreview(
        items: items,
        document: document,
        strategy: strategy,
        fileTitle: opml.title,
      ),
    );
  }

  /// 按预览结果逐项导入。
  ///
  /// 单源失败**不中断其余**条目：每条独立走一次「抓取 → 解析 → 入库」，失败只记在
  /// 该条的结果里。这正是架构 4.1「不因一个失败源撤销全部结果」的落地方式。
  Future<Result<OpmlImportResult>> import(
    OpmlPreview preview, {
    DateTime? now,
  }) async {
    final Result<Map<String, int>> groups =
        preview.strategy == OpmlGroupStrategy.keepFileGroups
        ? await ensureOpmlGroups(catalog, preview.items)
        : const Ok<Map<String, int>>(<String, int>{});
    if (groups.isErr) {
      return Err<OpmlImportResult>(groups.errorOrNull!);
    }
    final Map<String, int> resolved = groups.unwrap();

    final List<OpmlImportItemResult> results = <OpmlImportItemResult>[];
    for (final OpmlPreviewItem item in preview.items) {
      results.add(await _importOne(item, resolved, now: now));
    }
    return Ok<OpmlImportResult>(OpmlImportResult(items: results));
  }

  /// 只重跑失败项，并返回**合并后**的完整结果。
  ///
  /// 已成功/重复/无效的项原样保留在返回结果里：调用方（结果页）拿到的始终是一份
  /// 完整清单，不必自己合并两份结果——合并逻辑写两遍就迟早不一致。
  Future<Result<OpmlImportResult>> retryFailed(
    OpmlImportResult previous, {
    DateTime? now,
  }) async {
    final List<OpmlImportItemResult> retryable = previous.retryableFailures;
    if (retryable.isEmpty) {
      return Ok<OpmlImportResult>(previous);
    }

    // 重试的分组归属按各自的分组路径解析：结果项里保留了 groupPath，因此不需要
    // 让调用方再传一次预览。复用同一份 ensureOpmlGroups 保证与首次导入一致。
    final List<OpmlPreviewItem> asPreview = retryable
        .map(
          (OpmlImportItemResult item) => OpmlPreviewItem(
            index: item.index,
            status: OpmlPreviewStatus.added,
            title: item.title,
            url: item.url,
            groupPath: item.groupPath,
          ),
        )
        .toList(growable: false);
    final Result<Map<String, int>> groups =
        asPreview.any((OpmlPreviewItem i) => i.groupPath.isNotEmpty)
        ? await ensureOpmlGroups(catalog, asPreview)
        : const Ok<Map<String, int>>(<String, int>{});
    if (groups.isErr) {
      return Err<OpmlImportResult>(groups.errorOrNull!);
    }
    final Map<String, int> resolved = groups.unwrap();

    final Map<int, OpmlImportItemResult> updated =
        <int, OpmlImportItemResult>{};
    for (final OpmlPreviewItem item in asPreview) {
      updated[item.index] = await _importOne(item, resolved, now: now);
    }

    return Ok<OpmlImportResult>(
      OpmlImportResult(
        items: previous.items
            .map((OpmlImportItemResult item) => updated[item.index] ?? item)
            .toList(growable: false),
      ),
    );
  }

  /// 导入单独一条。
  Future<OpmlImportItemResult> _importOne(
    OpmlPreviewItem item,
    Map<String, int> groups, {
    DateTime? now,
  }) async {
    if (item.status == OpmlPreviewStatus.invalid) {
      return OpmlImportItemResult(
        index: item.index,
        title: item.title,
        url: item.url,
        groupPath: item.groupPath,
        outcome: OpmlItemOutcome.invalid,
        error: ValidationError(
          field: 'opml.entry.${item.index}',
          reason: item.reason ?? '无效条目',
        ),
      );
    }

    final Result<Uri> parsedUrl = AddFeedUseCase.parseFeedUrl(item.url);
    if (parsedUrl.isErr) {
      return OpmlImportItemResult(
        index: item.index,
        title: item.title,
        url: item.url,
        groupPath: item.groupPath,
        outcome: OpmlItemOutcome.invalid,
        error: parsedUrl.errorOrNull,
      );
    }

    final int? groupId = item.groupPath.isEmpty
        ? null
        : groups[item.groupPath.join('/')];

    final Result<FeedPreview> preview = await addFeed.preview(
      item.url,
      now: now,
    );
    if (preview.isErr) {
      // 抓取/解析失败：可重试（网络可能恢复，源可能修好）。
      return OpmlImportItemResult(
        index: item.index,
        title: item.title,
        url: item.url,
        groupPath: item.groupPath,
        outcome: OpmlItemOutcome.failed,
        error: preview.errorOrNull,
      );
    }
    final FeedPreview fetched = preview.unwrap();

    if (fetched.isDuplicate) {
      return OpmlImportItemResult(
        index: item.index,
        title: item.title,
        url: item.url,
        groupPath: item.groupPath,
        outcome: OpmlItemOutcome.duplicate,
        feedId: fetched.duplicateOf?.id,
      );
    }

    final Result<AddFeedOutcome> confirmed = await addFeed.confirm(
      preview: fetched,
      // 文件里的名字优先；它是用户在别的阅读器里取的名字。
      name: item.title.isEmpty ? item.url : item.title,
      groupId: groupId,
      now: now,
    );
    if (confirmed.isErr) {
      return OpmlImportItemResult(
        index: item.index,
        title: item.title,
        url: item.url,
        groupPath: item.groupPath,
        outcome: OpmlItemOutcome.failed,
        error: confirmed.errorOrNull,
      );
    }
    final AddFeedOutcome outcome = confirmed.unwrap();
    return OpmlImportItemResult(
      index: item.index,
      title: item.title,
      url: item.url,
      groupPath: item.groupPath,
      outcome: outcome.isDuplicate
          ? OpmlItemOutcome.duplicate
          : OpmlItemOutcome.imported,
      importedArticles: outcome.imported?.inserted ?? 0,
      feedId: outcome.feed.id,
    );
  }
}

/// 按「保留文件分组」策略建好全部需要的分组，返回「路径 → 分组 id」。
///
/// 一次性建全而不是在逐条导入时按需建组：同名分组可能出现在不同路径下
/// （Tech/News 与 Life/News），按需建组时只有「最后一段名字」可用，会把它们混成
/// 同一个组。
///
/// 幂等：已存在同名分组直接复用，因此重复导入同一份 OPML 不会每次新建一堆组。
Future<Result<Map<String, int>>> ensureOpmlGroups(
  FeedCatalogStore catalog,
  List<OpmlPreviewItem> items,
) async {
  final Result<List<GroupRecord>> existing = await catalog.listGroups();
  if (existing.isErr) {
    return Err<Map<String, int>>(existing.errorOrNull!);
  }
  final Map<String, int> byPath = <String, int>{};
  final Map<String, int> byName = <String, int>{
    for (final GroupRecord group in existing.unwrap()) group.name: group.id,
  };

  for (final OpmlPreviewItem item in items) {
    if (item.groupPath.isEmpty) {
      continue;
    }
    final String path = item.groupPath.join('/');
    if (byPath.containsKey(path)) {
      continue;
    }
    final int? matched = byName[item.groupPath.last];
    if (matched != null) {
      byPath[path] = matched;
      continue;
    }
    final Result<GroupRecord> created = await catalog.createGroup(
      syncId: newGroupSyncId(sequence: byPath.length),
      name: item.groupPath.last,
    );
    if (created.isErr) {
      return Err<Map<String, int>>(created.errorOrNull!);
    }
    byPath[path] = created.unwrap().id;
    byName[item.groupPath.last] = created.unwrap().id;
  }
  return Ok<Map<String, int>>(byPath);
}

/// OPML 导出用例。
/// 一次导出的结果。
class OpmlExportResult {
  /// 构造结果。
  const OpmlExportResult({
    required this.document,
    required this.entries,
    required this.strippedSecretParams,
  });

  /// OPML 文档全文。
  final String document;

  /// 导出的订阅数。
  final int entries;

  /// 因命中秘密参数名而被移除的参数名（去重）。
  ///
  /// 非空时界面**必须**提示用户：这些订阅在目标设备上需要补填凭据，否则用户会
  /// 以为「导出＝完整迁移」，导入后发现若干源不可用却找不到原因（架构 5.2 明确
  /// 要求「其他设备提示补填」）。
  final List<String> strippedSecretParams;
}

class ExportOpmlUseCase {
  /// 构造用例。
  const ExportOpmlUseCase({
    required this.catalog,
    this.clock = const SystemClock(),
  });

  /// 订阅/分组端口。
  final FeedCatalogStore catalog;

  /// 时钟（dateCreated）。
  final Clock clock;

  /// 导出一份标准 OPML 文档。
  ///
  /// **秘密排除（SET-027）**：写进文件的地址经过两道处理：
  ///   1) 用 [FeedRecord.normalizedUrl]（匹配与去重的稳定标识），它已经剥掉了明确的
  ///      跟踪参数；
  ///   2) 再走一次 [stripUrlSecrets]，把**明确的秘密参数名**（token/api_key/password/
  ///      auth 等，与日志脱敏同一份清单）连同它们的值一起移除。
  ///
  /// 第 2 步是必要的：规范化**刻意保留**非跟踪参数（架构 4.1 要求不随意剥离查询
  /// 参数），因此一个 token 参数会原样留在 normalizedUrl 里；若直接导出，用户的
  /// 凭据就随文件离开了本机。移除而不是替换成占位符：见 url_secrets.dart 的说明。
  ///
  /// 其余业务参数**一律保留**：它们是地址的一部分，剥掉会让订阅失效。
  Future<Result<OpmlExportResult>> export({
    String title = 'Flux Subscriptions',
    DateTime? now,
  }) async {
    final Result<List<FeedRecord>> feeds = await catalog.listFeeds();
    if (feeds.isErr) {
      return Err<OpmlExportResult>(feeds.errorOrNull!);
    }
    final Result<List<GroupRecord>> groups = await catalog.listGroups();
    if (groups.isErr) {
      return Err<OpmlExportResult>(groups.errorOrNull!);
    }
    final Map<int, String> groupNames = <int, String>{
      for (final GroupRecord group in groups.unwrap()) group.id: group.name,
    };

    final List<OpmlExportEntry> entries = <OpmlExportEntry>[];
    final List<String> stripped = <String>[];
    for (final FeedRecord feed in feeds.unwrap()) {
      final int? groupId = feed.groupId;
      final String? groupName = groupId == null ? null : groupNames[groupId];
      // 移除明确的秘密参数（SET-027）。规范化保留业务参数，因此这一步不能省。
      final UrlSecretStripResult safe = stripUrlSecrets(feed.normalizedUrl);
      for (final String name in safe.removed) {
        if (!stripped.contains(name)) {
          stripped.add(name);
        }
      }
      entries.add(
        OpmlExportEntry(
          title: feed.name,
          xmlUrl: safe.url,
          // 库里没有保存站点主页地址（Feed 表没有 htmlUrl 列），因此这里**留空**
          // 而不是把订阅地址当主页写进去——那会让用户在别的阅读器里点「访问网站」
          // 时打开 XML 而不是网页。
          groupPath: groupName == null ? const <String>[] : <String>[groupName],
        ),
      );
    }

    return Ok<OpmlExportResult>(
      OpmlExportResult(
        document: buildOpml(
          entries: entries,
          title: title,
          createdAt: now ?? clock.now(),
        ),
        entries: entries.length,
        strippedSecretParams: stripped,
      ),
    );
  }
}
