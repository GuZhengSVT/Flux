// 独立来源核验、引用校验与版本保存（T038；架构 4.4 的「生成带候选引用的条目 → 独立来源
// 核对/冲突记录 → 结构与引用校验 → 保存新版本/保留上个成功版本」）。
//
// 与 T037 的分工：T037 产出**初稿**（带候选引用的条目），T038 在初稿之上做核验并追加一个
// **新版本**。两者都落同一张 news_runs 表，因此「初稿」与「核验后的版本」在历史里是两条
// 可对照的记录，而不是一份被就地改写的内容。
//
// 四条刻意的设计：
//
//   1) **核验只对重要事实做，且每条只发一个派生查询**。核验是要花钱的（每次检索都是一次
//      调用），「每个条目无限追问」会让一次生成的成本随条目数线性增长。因此派生查询用条目
//      关键词拼（而不是整句），并且受 [NewsVerificationBudget] 的条数与查询数上限约束。
//   2) **禁词对派生查询同样生效**（SET-053）。核验查询是**新发出去的查询**，绕过禁词就等于
//      在一条新路径上把本地规则作废。这里复用 T036 的 buildNewsSearchQueries，因此命中的
//      查询根本不会出现在发送列表里。
//   3) **核验失败不清空初稿**。检索失败、超时、工具次数用尽都只是让标签变成「材料不足」，
//      条目文本与引用原样保留：把核验失败变成一次数据损失，会让用户在网络抖动时丢掉当天
//      唯一一份总结。
//   4) **引用的最小摘录从材料快照取**（架构 4.4）。摘录不由模型给（模型会「顺手改写」），
//      也不由核验结果给（那会把检索片段混进 RSS 引用的摘录里）。
library;

import 'package:flux/core/core.dart';
import 'package:flux/features/ai/application/tool_executor.dart';
import 'package:flux/features/ai/domain/search_result.dart';
import 'package:flux/features/ai/domain/tool_call.dart';
import 'package:flux/features/ai/domain/ai_message.dart';

/// 一次核验的资源上限。
///
/// 做成显式对象而不是散在循环里的常量：核验成本随条目数增长，而这个上限是**费用边界**，
/// 必须能被一次任务开始时冻结并整体检查（与 T029 的 AiTaskBudget 同一条理由）。
final class NewsVerificationBudget {
  /// 构造上限。
  const NewsVerificationBudget({
    this.maxItemsVerified = 10,
    this.maxQueries = 10,
    this.maxResultsPerQuery = 10,
  });

  /// 最多核验多少条条目（按条目顺序取前 N 条，即当天最重要的事实）。
  final int maxItemsVerified;

  /// 最多发出多少个核验查询（所有条目共享）。
  final int maxQueries;

  /// 每个查询接纳多少条结果作为候选来源。
  final int maxResultsPerQuery;
}

/// 一次核验的产出。
final class NewsVerificationOutcome {
  /// 构造产出。
  const NewsVerificationOutcome({
    required this.items,
    required this.method,
    this.verifiedItemCount = 0,
    this.candidateCount = 0,
    this.insufficientItemCount = 0,
    this.conflictItemCount = 0,
    this.failed = false,
    this.error,
  });

  /// 核验后的条目（顺序与初稿一致，被核验的带标签）。
  final List<NewsDraftItem> items;

  /// 本次核验的方法记录（随版本落库）。
  final NewsVerificationMethod method;

  /// 实际核验过的条目数。
  final int verifiedItemCount;

  /// 看过的候选来源数。
  final int candidateCount;

  /// 标为「材料不足」的条目数。
  final int insufficientItemCount;

  /// 标为「来源冲突」的条目数。
  final int conflictItemCount;

  /// 核验过程本身是否失败（检索不可用/超时）。
  ///
  /// **失败不等于没有产出**：条目原样返回（标签按未胜出处理），调用方仍然可以保存版本。
  final bool failed;

  /// 失败原因（结构性）。
  final AppError? error;

  /// 是否存在需要用户注意的标签（少源/不足/冲突）。
  bool get hasWarnings =>
      items.any((NewsDraftItem item) => item.labels.isNotEmpty);
}

/// 独立来源核验服务。
final class NewsVerificationService {
  /// 构造服务。
  const NewsVerificationService({
    required this.buildTools,
    required this.diagnostics,
    this.budget = const NewsVerificationBudget(),
  });

  /// 受控工具执行器的构造（检索是唯一出口；理由同 T037 的 buildTools）。
  final ToolExecutor Function() buildTools;

  /// 诊断记录。
  final DiagnosticSink diagnostics;

  /// 本次核验的上限（冻结值）。
  final NewsVerificationBudget budget;

  /// 核验一批条目。
  ///
  /// [searchConfigured] 为 false 表示没有可用的搜索服务：此时**一个查询都不发**，全部条目
  /// 标「未联网核验」（架构 4.4 的「只读 RSS 标未联网核验」）。
  Future<NewsVerificationOutcome> verify({
    required List<NewsDraftItem> items,
    required List<NewsMaterial> materials,
    required List<String> blockedQueryTerms,
    required bool searchConfigured,
    AiCancellation? cancellation,
  }) async {
    final List<NewsDraftItem> kept = items
        .where((NewsDraftItem item) => item.kept)
        .take(budget.maxItemsVerified)
        .toList(growable: false);
    final Map<int, NewsItemVerification> results =
        <int, NewsItemVerification>{};
    int queriesIssued = 0;
    int resultsSeen = 0;
    String? provider;
    bool failed = false;
    AppError? failure;

    if (!searchConfigured) {
      // 未联网：不发任何查询，标「未联网核验」。
      for (final NewsDraftItem item in kept) {
        results[item.index] = NewsItemVerification(
          itemIndex: item.index,
          outcome: VerificationOutcome.notVerifiedOnline,
          independentSourceCount: item.sourceIds.length,
          candidateClusters: item.sourceIds.length,
          labels: const <NewsEvidenceLabel>[
            NewsEvidenceLabel.notVerifiedOnline,
          ],
        );
      }
      return NewsVerificationOutcome(
        items: _apply(items, results),
        method: const NewsVerificationMethod(
          usedSearch: false,
          queriesIssued: 0,
          resultsSeen: 0,
        ),
        verifiedItemCount: kept.length,
        insufficientItemCount: kept.length,
      );
    }

    final ToolExecutor tools = buildTools();
    for (final NewsDraftItem item in kept) {
      if (cancellation?.isCancelled ?? false) {
        break;
      }
      final NewsClaim claim = NewsClaim.of(item.text);
      // 派生查询与用户关键词走**同一条禁词规则**（SET-053）：命中的查询不会出现在
      // 返回值里，因此「实际发送的查询符合本地规则」在这一层同样是结构性的。
      final List<String> queries = buildNewsSearchQueries(
        keywords: const <String>[],
        derivedQueries: <String>[claim.query],
        blockedQueryTerms: blockedQueryTerms,
        maxQueries: 1,
      );
      if (queries.isEmpty) {
        // 派生查询命中禁词：不发查询，如实标「材料不足」（而不是假装核验过）。
        results[item.index] = NewsItemVerification(
          itemIndex: item.index,
          outcome: VerificationOutcome.insufficientMaterial,
          independentSourceCount: item.sourceIds.length,
          candidateClusters: item.sourceIds.length,
          labels: const <NewsEvidenceLabel>[
            NewsEvidenceLabel.insufficientMaterial,
          ],
        );
        continue;
      }
      if (queriesIssued >= budget.maxQueries) {
        results[item.index] = NewsItemVerification(
          itemIndex: item.index,
          outcome: VerificationOutcome.insufficientMaterial,
          independentSourceCount: item.sourceIds.length,
          candidateClusters: item.sourceIds.length,
          labels: const <NewsEvidenceLabel>[
            NewsEvidenceLabel.insufficientMaterial,
          ],
        );
        continue;
      }
      queriesIssued++;
      final ToolResult result = await tools.execute(
        ToolCall(
          id: 'news-verify-$queriesIssued',
          rawName: ToolName.search.wireName,
          args: <String, Object?>{'query': queries.first},
        ),
      );
      final ToolPayload? payload = result.payload;
      if (payload is! SearchToolPayload) {
        // 检索失败/次数用尽：如实标「材料不足」，条目本身照常保留（见文件头第 3 条）。
        failed = true;
        failure ??= result.error;
        diagnostics.warning(
          '核验检索未返回结果 itemIndex=${item.index} '
          'kind=${result.reason?.name ?? 'failed'}',
          tag: 'news.verify',
        );
        results[item.index] = NewsItemVerification(
          itemIndex: item.index,
          outcome: VerificationOutcome.insufficientMaterial,
          independentSourceCount: item.sourceIds.length,
          candidateClusters: item.sourceIds.length,
          labels: const <NewsEvidenceLabel>[
            NewsEvidenceLabel.insufficientMaterial,
          ],
        );
        continue;
      }
      provider ??= payload.provider;
      resultsSeen += payload.results.length;

      final List<NewsEvidenceCandidate> candidates = <NewsEvidenceCandidate>[
        for (final SearchResult hit in payload.results.take(
          budget.maxResultsPerQuery,
        ))
          NewsEvidenceCandidate(
            title: clampSearchText(hit.title, kSearchTitleMaxLength),
            text: clampSearchText(hit.snippet, kSearchSnippetMaxLength),
            url: hit.url,
            sourceId: hit.sourceId,
          ),
      ];

      // 条目自己引用的材料也进聚类：如果候选里出现的正是**同一篇稿子**（转载），它不能
      // 算成第二条独立来源（架构 4.4「转载同一稿件不能算两个证据」）。
      // 用材料的**真实地址与标题**（从本次任务的材料快照取），而不是 sourceId：
      // 拿 id 猜同稿会让该合并的没合、不该合的合了，而两种错都会改变「有几条独立来源」。
      final List<NewsEvidenceCandidate> ownSources = <NewsEvidenceCandidate>[
        for (final String sourceId in item.sourceIds)
          if (findMaterial(materials, sourceId) case final NewsMaterial found)
            NewsEvidenceCandidate(
              title: found.title,
              text: found.excerpt,
              url: found.url,
              sourceId: sourceId,
            ),
      ];
      final List<NewsSourceCluster> allClusters = clusterSyndicatedSources(
        <NewsEvidenceCandidate>[...candidates, ...ownSources],
      );
      final Set<String> ownClusterIds = <String>{
        for (final NewsEvidenceCandidate own in ownSources)
          clusterIdOf(url: own.url, title: own.title),
      };
      // 只有**不与自有引用同稿**的候选才可能构成第二条独立来源。
      final List<NewsEvidenceCandidate> independent = <NewsEvidenceCandidate>[
        for (final NewsEvidenceCandidate candidate in candidates)
          if (!sameClusterAsOwn(candidate, allClusters, ownClusterIds))
            candidate,
      ];

      final NewsItemVerification verification = verifyNewsItem(
        item: item,
        candidates: independent,
      );
      results[item.index] = verification;
      diagnostics.info(
        '核验结论 itemIndex=${item.index} outcome=${verification.outcome.name} '
        'independent=${verification.independentSourceCount} '
        'clusters=${verification.candidateClusters}',
        tag: 'news.verify',
      );
    }

    final List<NewsDraftItem> merged = _apply(items, results);
    final NewsVerificationMethod method = NewsVerificationMethod(
      usedSearch: true,
      queriesIssued: queriesIssued,
      resultsSeen: resultsSeen,
      searchProvider: provider,
    );
    return NewsVerificationOutcome(
      items: merged,
      method: method,
      verifiedItemCount: results.length,
      candidateCount: resultsSeen,
      insufficientItemCount: merged
          .where(
            (NewsDraftItem item) =>
                item.labels.contains(NewsEvidenceLabel.insufficientMaterial),
          )
          .length,
      conflictItemCount: merged
          .where(
            (NewsDraftItem item) =>
                item.labels.contains(NewsEvidenceLabel.sourceConflict),
          )
          .length,
      failed: failed,
      error: failure,
    );
  }

  /// 把核验结论写回条目（未核验的条目保持原样，**不**补标签）。
  static List<NewsDraftItem> _apply(
    List<NewsDraftItem> items,
    Map<int, NewsItemVerification> results,
  ) => <NewsDraftItem>[
    for (final NewsDraftItem item in items)
      results[item.index] == null
          ? item
          : item.copyWith(
              labels: results[item.index]!.labels,
              independentSourceCount:
                  results[item.index]!.independentSourceCount,
              verificationNote: results[item.index]!.outcome.name,
            ),
  ];
}

/// 一条条目在核验后的引用（含最小摘录与获取方式，架构 4.4）。
final class NewsVerifiedCitation {
  /// 构造引用。
  const NewsVerifiedCitation({
    required this.sourceId,
    required this.accessMethod,
    required this.title,
    required this.url,
    required this.excerpt,
    required this.materialHash,
    this.publishedAt,
    this.accessedAt,
    this.articleId,
    this.issue,
  });

  /// 材料标识。
  final String sourceId;

  /// 获取方式（rss / fetch / search）。
  final CitationAccessMethod accessMethod;

  /// 标题。
  final String title;

  /// 地址。
  final String url;

  /// 材料时间。
  final DateTime? publishedAt;

  /// 访问时刻。
  final DateTime? accessedAt;

  /// 最小摘录（从材料快照取）。
  final String excerpt;

  /// 材料哈希。
  final String materialHash;

  /// 本机文章 id（RSS 引用可跳本地文章）。
  final int? articleId;

  /// 完整性检查结果；完整时为 null。
  final NewsCitationIssue? issue;

  /// 是否完整（可被界面当作可核对的引用）。
  bool get complete => issue == null;

  @override
  String toString() =>
      'NewsVerifiedCitation($sourceId ${accessMethod.name} '
      '${complete ? 'complete' : 'missing=${issue!.missingFields.join(',')}'})';
}

/// 从材料快照构造一条引用（架构 4.4：摘录来自材料，不由模型给）。
NewsVerifiedCitation buildVerifiedCitation(
  NewsMaterial material, {
  int excerptLimit = kNewsCitationExcerptMaxLength,
}) => NewsVerifiedCitation(
  sourceId: material.sourceId,
  accessMethod: material.accessMethod,
  title: material.title,
  url: material.url,
  publishedAt: material.publishedAt,
  accessedAt: material.accessedAt,
  excerpt: citationExcerptOf(material, limit: excerptLimit),
  materialHash: material.materialHash,
  articleId: material.articleId,
  issue: citationIssueOf(material),
);

/// 把一批条目引用的材料解析成完整引用清单。
///
/// 返回顺序就是条目出现顺序、条目内按引用顺序；**未知 sourceId 会被列出**而不是静默丢弃
/// （那正是「模型编造引用」需要被用户看见的地方）。
final class NewsCitationResolution {
  /// 构造结果。
  const NewsCitationResolution({
    required this.citations,
    required this.unknown,
  });

  /// 解析成功的引用（按出现顺序去重）。
  final List<NewsVerifiedCitation> citations;

  /// 在材料集合里找不到的 sourceId（去重，按出现顺序）。
  final List<String> unknown;

  /// 是否有不完整的引用（缺 URL/时间/摘录）。
  bool get hasIncomplete =>
      citations.any((NewsVerifiedCitation c) => !c.complete);

  /// 是否出现了未知引用。
  bool get hasUnknown => unknown.isNotEmpty;
}

/// 解析条目列表的引用。
NewsCitationResolution resolveNewsCitations({
  required List<NewsDraftItem> items,
  required List<NewsMaterial> materials,
}) {
  final List<NewsVerifiedCitation> citations = <NewsVerifiedCitation>[];
  final List<String> unknown = <String>[];
  final Set<String> seen = <String>{};
  for (final NewsDraftItem item in items) {
    if (!item.kept) {
      continue;
    }
    for (final String sourceId in item.sourceIds) {
      if (!seen.add(sourceId)) {
        continue;
      }
      final NewsMaterial? material = findMaterial(materials, sourceId);
      if (material == null) {
        unknown.add(sourceId);
        continue;
      }
      citations.add(buildVerifiedCitation(material));
    }
  }
  return NewsCitationResolution(citations: citations, unknown: unknown);
}
