// 每日新闻任务的输入快照、事件聚合产物、引用校验与版本记录（T037；架构 4.4、SET-050–063）。
//
// 这一层是**纯数据与纯函数**：快照怎么固化、材料怎么排序与截断、模型输出怎么解析、
// 引用怎么被拒绝，都在这里定义，因此都可以在没有网络、没有模型、没有数据库的情况下
// 逐条断言。真正出网的部分（抓取、检索、模型调用）住在 features/news/application 与
// infrastructure。
//
// 四条与验收条件一一对应的设计：
//
//   1) **设备时区与日期区间在任务开始时固化**（架构 4.4「日界线和展示采用设备时区，
//      任务中途不改变」）。快照里存的是「本地日期 + 当时的偏移 + 对应的 UTC 区间」，
//      因此用户旅行之后旧记录仍归属当时的本地日期，重新计算不会把历史日期改写；
//   2) **材料集合是引用校验的唯一依据**（架构 4.4「引用只可使用真实获取的 sourceId」）。
//      解析出的每个 `[sourceId]` 必须在本次材料集合里存在，否则该条目被**退回**——
//      把模型编造的网址当证据写进结果是本任务最需要避免的失败；
//   3) **单材料预算（SET-061）在进入材料时就生效并标注截断**。不标注截断会让模型把
//      半篇文章当全文总结，而用户看到的结论没有任何线索指向材料不全；
//   4) **成功版本不被草稿覆盖**（架构 4.4/4.5）。版本号只增，`isCurrent` 只允许出现在
//      succeeded/partial 的行上，且这条规则在数据库层也有 CHECK（见 news_tables.dart）。
library;

import '../digest/sha256.dart';
import '../result.dart';
import '../task/task_status.dart';

import 'citation_access.dart';
import 'news_prompt.dart';

/// 一次新闻任务的阶段（界面进度栏按它显示当前做到哪一步）。
///
/// 阶段的**顺序就是实际执行顺序**，因此界面不需要另写一份顺序表：多一份顺序表就
/// 会在插入新阶段时漂移，而漂移的表现是进度条先后顺序与真实执行不一致。
enum NewsRunStage {
  /// 固化输入快照（时区、日期区间、选材）。
  snapshot,

  /// 逐站抓取必访问网站。
  requiredSites,

  /// 联网检索。
  search,

  /// 生成初稿。
  generate,

  /// 独立来源核验（T038）。
  verify,

  /// 保存版本。
  save;

  /// 展示名（界面按语言取本地化文案，这里只给结构标识）。
  String get code => name;
}

/// 一条材料的获取方式（架构 4.4：摘要/全文/搜索片段分别标明）。
///
/// 直接复用 [CitationAccessMethod]（rss/fetch/search）：材料与引用是同一件事的两面，
/// 再造一个同取值的枚举只会让「这两处说的是不是一个意思」变成需要核对的问题。
extension NewsMaterialAccess on CitationAccessMethod {
  /// 该方式是否代表「客户端亲自联网取回」的证据（用于「未联网核验」标签的判定）。
  bool get isOnlineEvidence => this != CitationAccessMethod.rss;
}

/// 一条进入本次任务的材料（RSS 摘要/正文、抓取的网页正文、检索片段）。
final class NewsMaterial {
  /// 构造材料。
  const NewsMaterial({
    required this.sourceId,
    required this.accessMethod,
    required this.title,
    required this.url,
    required this.excerpt,
    required this.materialHash,
    this.publishedAt,
    this.accessedAt,
    this.truncated = false,
    this.contentLength = 0,
    this.articleId,
    this.feedName,
  });

  /// 稳定材料标识（模型在 `[sourceId]` 里引用的就是它）。
  ///
  /// RSS 材料用 `rss.<本机文章 id>`，抓取材料用 `fetch.<最终地址摘要>`，检索材料用
  /// T031 适配器给出的 `searchResultSourceId`（协议 + 序号摘要，见该函数的说明）。
  /// 三者的**取值规则不同是有理由的**：文章有本机身份、网页的身份是它的最终地址、
  /// 检索结果的地址会被服务商改写（因此只能用位置）。
  final String sourceId;

  /// 获取方式（rss / fetch / search）。
  final CitationAccessMethod accessMethod;

  /// 标题。
  final String title;

  /// 地址（已过地址守卫；检索结果的地址由 T031 适配器负责守卫）。
  final String url;

  /// 材料时间（源声明，UTC）；未知为 null。
  final DateTime? publishedAt;

  /// 本机实际获取该材料的时刻（UTC）。
  final DateTime? accessedAt;

  /// 最小摘录（已按 SET-061 的单材料预算截断并清洗空白）。
  final String excerpt;

  /// 材料哈希（引用校验与「同一材料」判定用）。
  final String materialHash;

  /// 摘录是否被截断。
  final bool truncated;

  /// 截断前的字符数（让用户与模型知道原文更长）。
  final int contentLength;

  /// 本机文章 id（RSS 材料的引用可跳本地文章）；外部来源为 null。
  final int? articleId;

  /// 来源显示名（RSS 材料的订阅名）；无则 null。
  final String? feedName;

  /// 是否可以跳回本机文章（界面据此决定「跳本地」还是「外开」）。
  bool get hasLocalArticle => articleId != null;

  /// 展示用短标识（界面徽章与模型输出里都可见）。
  String get shortId => sourceId;

  /// 落库/落快照形态。
  Map<String, Object?> toJson() => <String, Object?>{
    'sourceId': sourceId,
    'accessMethod': accessMethod.name,
    'title': title,
    'url': url,
    if (publishedAt != null) 'publishedAt': publishedAt!.toIso8601String(),
    if (accessedAt != null) 'accessedAt': accessedAt!.toIso8601String(),
    'excerpt': excerpt,
    'materialHash': materialHash,
    'truncated': truncated,
    'contentLength': contentLength,
    if (articleId != null) 'articleId': articleId,
    if (feedName != null) 'feedName': feedName,
  };

  /// 从落库形态还原；结构不符时返回 null（调用方按「快照损坏」处理，不猜内容）。
  static NewsMaterial? fromJson(Map<Object?, Object?> json) {
    final Object? sourceId = json['sourceId'];
    final Object? title = json['title'];
    final Object? url = json['url'];
    final Object? excerpt = json['excerpt'];
    if (sourceId is! String || title is! String || url is! String) {
      return null;
    }
    if (excerpt is! String) {
      return null;
    }
    return NewsMaterial(
      sourceId: sourceId,
      accessMethod: _accessMethod(json['accessMethod']),
      title: title,
      url: url,
      publishedAt: _date(json['publishedAt']),
      accessedAt: _date(json['accessedAt']),
      excerpt: excerpt,
      materialHash: json['materialHash'] is String
          ? json['materialHash']! as String
          : materialHashOf(sourceId: sourceId, url: url, excerpt: excerpt),
      truncated: json['truncated'] == true,
      contentLength: json['contentLength'] is int
          ? json['contentLength']! as int
          : excerpt.length,
      articleId: json['articleId'] is int ? json['articleId']! as int : null,
      feedName: json['feedName'] is String ? json['feedName']! as String : null,
    );
  }

  @override
  String toString() =>
      'NewsMaterial($sourceId ${accessMethod.name} ${excerpt.length} chars)';
}

/// 计算材料哈希（只由「材料身份 + 地址 + 摘录」决定，不含获取时刻）。
String materialHashOf({
  required String sourceId,
  required String url,
  required String excerpt,
}) => sha256HexOfString('$sourceId\u0000$url\u0000$excerpt').substring(0, 32);

/// 必访问网站的逐站执行结果（SET-051「记录逐站获取结果」）。
final class NewsSiteFetchResult {
  /// 构造结果。
  const NewsSiteFetchResult({
    required this.name,
    required this.url,
    required this.status,
    this.detailKind,
    this.sourceId,
    this.charCount = 0,
  });

  /// 站点显示名（来自快照）。
  final String name;

  /// 站点地址（来自快照）。
  final String url;

  /// 执行状态。
  final NewsSiteStatus status;

  /// 失败类别（结构性标识，例如 `network` / `deadlineExceeded`）；成功为 null。
  /// **不含**错误正文与页面内容（架构第 8 节）。
  final String? detailKind;

  /// 成功时产出的材料标识。
  final String? sourceId;

  /// 成功时正文的字符数。
  final int charCount;

  /// 是否成功取回。
  bool get ok => status == NewsSiteStatus.ok;

  /// 失败是否可见（界面与验收都要求「必访失败可见」）。
  bool get failed => status != NewsSiteStatus.ok;

  /// 落库形态。
  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'url': url,
    'status': status.name,
    if (detailKind != null) 'detailKind': detailKind,
    if (sourceId != null) 'sourceId': sourceId,
    'charCount': charCount,
  };

  /// 从落库形态还原。
  static NewsSiteFetchResult? fromJson(Map<Object?, Object?> json) {
    final Object? name = json['name'];
    final Object? url = json['url'];
    if (name is! String || url is! String) {
      return null;
    }
    return NewsSiteFetchResult(
      name: name,
      url: url,
      status: NewsSiteStatus.fromName(json['status']),
      detailKind: json['detailKind'] is String
          ? json['detailKind']! as String
          : null,
      sourceId: json['sourceId'] is String ? json['sourceId']! as String : null,
      charCount: json['charCount'] is int ? json['charCount']! as int : 0,
    );
  }
}

/// 必访问网站的逐站状态。
///
/// 「超时」与「失败」分开：两者的**下一步动作**不同（超时可重试、地址被守卫拒绝重试
/// 也没用），而把两者合成一个「失败」会让用户看不出该不该再点一次。
enum NewsSiteStatus {
  /// 成功取回。
  ok,

  /// 抓取失败（网络/解析/被守卫拒绝）。
  failed,

  /// 超时（总时限或抓取超时）。
  timeout,

  /// 本次未执行（站点停用，或工具次数预算已用尽）。
  skipped;

  /// 由稳定名还原；未知值按「失败」处理（不假装成功）。
  static NewsSiteStatus fromName(Object? name) {
    for (final NewsSiteStatus value in NewsSiteStatus.values) {
      if (value.name == name) {
        return value;
      }
    }
    return NewsSiteStatus.failed;
  }
}

/// 本次任务的输入快照（任务开始时固化，之后不再改变）。
final class NewsInputSnapshot {
  /// 构造快照。
  const NewsInputSnapshot({
    required this.localDate,
    required this.deviceTimeZone,
    required this.utcOffsetMinutes,
    required this.dayStartUtc,
    required this.dayEndUtc,
    required this.frozenAtUtc,
    required this.candidates,
    required this.requiredSites,
    required this.keywords,
    required this.blockedQueryTerms,
    required this.excludedTopics,
    required this.promptVersionRef,
    required this.promptText,
    required this.maxArticles,
    required this.maxSites,
    required this.maxQueries,
    required this.singleMaterialBudget,
    required this.globalEnabled,
    this.language = NewsPromptLanguage.chinese,
  });

  /// 设备本地日期键（YYYY-MM-DD）。
  final String localDate;

  /// 任务开始时的设备时区（IANA 名称）。
  final String deviceTimeZone;

  /// 固化时的 UTC 偏移（分钟）。历史记录的解释依据，不随时区变化重写。
  final int utcOffsetMinutes;

  /// 当日 00:00（本地）对应的 UTC 时刻。
  final DateTime dayStartUtc;

  /// 次日 00:00（本地）对应的 UTC 时刻。
  final DateTime dayEndUtc;

  /// 快照固化时刻（UTC）。
  final DateTime frozenAtUtc;

  /// 选材结果（已去重、已排序、已按 SET-060 截断，仅含当日发布的文章）。
  final List<NewsMaterial> candidates;

  /// 必访问网站快照（只含启用项，按用户顺序）。
  final List<NewsRequiredSite> requiredSites;

  /// 联网搜索关键词快照（SET-052）。
  final List<String> keywords;

  /// 禁止发送的查询词快照（SET-053 之一）。
  final List<String> blockedQueryTerms;

  /// 排除的内容主题快照（SET-053 之二）。
  final List<String> excludedTopics;

  /// prompt 版本引用（`<语言>#<版本>` 或 `<语言>#builtin`）。
  final String promptVersionRef;

  /// 本次实际会发送的 prompt 文本（含不可删的引用协议段）。
  final String promptText;

  /// SET-060 的上限（快照固化，任务中途不因用户改设置而变）。
  final int maxArticles;

  /// SET-060 的必访站上限。
  final int maxSites;

  /// SET-060 的查询上限。
  final int maxQueries;

  /// SET-061 的单材料字符预算。
  final int singleMaterialBudget;

  /// SET-050 的总开关在任务开始时的取值。
  final bool globalEnabled;

  /// 生成语言。
  final NewsPromptLanguage language;

  /// 选材篇数。
  int get candidateCount => candidates.length;

  /// 快照哈希（同一输入重复生成时据此判断缓存是否失效）。
  String get hash => sha256HexOfString(_canonical()).substring(0, 32);

  /// 复制并覆盖部分字段。
  ///
  /// 目前只有 [promptVersionRef] / [promptText] 需要被替换：T038 的核验会在同一份输入
  /// 上追加核验指令，届时它必须能**如实记录**实际发出去的 prompt 版本，而不是把核验
  /// 也记成初稿那一次。
  NewsInputSnapshot copyWith({
    String? promptVersionRef,
    String? promptText,
    List<NewsMaterial>? candidates,
  }) => NewsInputSnapshot(
    localDate: localDate,
    deviceTimeZone: deviceTimeZone,
    utcOffsetMinutes: utcOffsetMinutes,
    dayStartUtc: dayStartUtc,
    dayEndUtc: dayEndUtc,
    frozenAtUtc: frozenAtUtc,
    candidates: candidates ?? this.candidates,
    requiredSites: requiredSites,
    keywords: keywords,
    blockedQueryTerms: blockedQueryTerms,
    excludedTopics: excludedTopics,
    promptVersionRef: promptVersionRef ?? this.promptVersionRef,
    promptText: promptText ?? this.promptText,
    maxArticles: maxArticles,
    maxSites: maxSites,
    maxQueries: maxQueries,
    singleMaterialBudget: singleMaterialBudget,
    globalEnabled: globalEnabled,
    language: language,
  );

  /// 落库形态。
  Map<String, Object?> toJson() => <String, Object?>{
    'localDate': localDate,
    'deviceTimeZone': deviceTimeZone,
    'utcOffsetMinutes': utcOffsetMinutes,
    'dayStartUtc': dayStartUtc.toIso8601String(),
    'dayEndUtc': dayEndUtc.toIso8601String(),
    'frozenAtUtc': frozenAtUtc.toIso8601String(),
    'candidates': <Object?>[
      for (final NewsMaterial material in candidates) material.toJson(),
    ],
    'requiredSites': <Object?>[
      for (final NewsRequiredSite site in requiredSites)
        <String, Object?>{
          'name': site.name,
          'url': site.url,
          'sortOrder': site.sortOrder,
        },
    ],
    'keywords': keywords,
    'blockedQueryTerms': blockedQueryTerms,
    'excludedTopics': excludedTopics,
    'promptVersionRef': promptVersionRef,
    'promptText': promptText,
    'maxArticles': maxArticles,
    'maxSites': maxSites,
    'maxQueries': maxQueries,
    'singleMaterialBudget': singleMaterialBudget,
    'globalEnabled': globalEnabled,
    'language': language.code,
  };

  /// 从落库形态还原；结构不符时返回 null。
  static NewsInputSnapshot? fromJson(Map<Object?, Object?> json) {
    final DateTime? dayStart = _date(json['dayStartUtc']);
    final DateTime? dayEnd = _date(json['dayEndUtc']);
    final DateTime? frozenAt = _date(json['frozenAtUtc']);
    final Object? localDate = json['localDate'];
    final Object? timeZone = json['deviceTimeZone'];
    if (dayStart == null ||
        dayEnd == null ||
        frozenAt == null ||
        localDate is! String ||
        timeZone is! String) {
      return null;
    }
    final List<NewsMaterial> candidates = <NewsMaterial>[];
    final Object? rawCandidates = json['candidates'];
    if (rawCandidates is List<Object?>) {
      for (final Object? item in rawCandidates) {
        if (item is! Map<Object?, Object?>) {
          continue;
        }
        final NewsMaterial? material = NewsMaterial.fromJson(item);
        if (material != null) {
          candidates.add(material);
        }
      }
    }
    final List<NewsRequiredSite> sites = <NewsRequiredSite>[];
    final Object? rawSites = json['requiredSites'];
    if (rawSites is List<Object?>) {
      for (final Object? item in rawSites) {
        if (item is! Map<Object?, Object?>) {
          continue;
        }
        final Object? name = item['name'];
        final Object? url = item['url'];
        if (name is! String || url is! String) {
          continue;
        }
        sites.add(
          NewsRequiredSite(
            name: name,
            url: url,
            sortOrder: item['sortOrder'] is int
                ? item['sortOrder']! as int
                : sites.length,
          ),
        );
      }
    }
    return NewsInputSnapshot(
      localDate: localDate,
      deviceTimeZone: timeZone,
      utcOffsetMinutes: json['utcOffsetMinutes'] is int
          ? json['utcOffsetMinutes']! as int
          : 0,
      dayStartUtc: dayStart,
      dayEndUtc: dayEnd,
      frozenAtUtc: frozenAt,
      candidates: candidates,
      requiredSites: sites,
      keywords: _stringList(json['keywords']),
      blockedQueryTerms: _stringList(json['blockedQueryTerms']),
      excludedTopics: _stringList(json['excludedTopics']),
      promptVersionRef: json['promptVersionRef'] is String
          ? json['promptVersionRef']! as String
          : 'builtin',
      promptText: json['promptText'] is String
          ? json['promptText']! as String
          : '',
      maxArticles: json['maxArticles'] is int
          ? json['maxArticles']! as int
          : kNewsDefaultMaxArticles,
      maxSites: json['maxSites'] is int
          ? json['maxSites']! as int
          : kNewsDefaultMaxSites,
      maxQueries: json['maxQueries'] is int
          ? json['maxQueries']! as int
          : kNewsDefaultMaxQueries,
      singleMaterialBudget: json['singleMaterialBudget'] is int
          ? json['singleMaterialBudget']! as int
          : kNewsDefaultSingleMaterialBudget,
      globalEnabled: json['globalEnabled'] != false,
      language:
          NewsPromptLanguage.fromCode(
            json['language'] is String ? json['language']! as String : null,
          ) ??
          NewsPromptLanguage.chinese,
    );
  }

  String _canonical() {
    final StringBuffer buffer = StringBuffer()
      ..write(localDate)
      ..write('|')
      ..write(deviceTimeZone)
      ..write('|')
      ..write(dayStartUtc.toIso8601String())
      ..write('|')
      ..write(dayEndUtc.toIso8601String())
      ..write('|')
      ..write(promptVersionRef)
      ..write('|');
    for (final NewsMaterial material in candidates) {
      buffer
        ..write(material.sourceId)
        ..write(':')
        ..write(material.materialHash)
        ..write(';');
    }
    buffer
      ..write('|')
      ..write(keywords.join(','))
      ..write('|')
      ..write(requiredSites.map((NewsRequiredSite s) => s.url).join(','));
    return buffer.toString();
  }
}

/// SET-060 的上限默认值（与设置注册表的默认值一致）。
const int kNewsDefaultMaxArticles = 50;

/// SET-060 的必访站上限默认值。
const int kNewsDefaultMaxSites = 10;

/// SET-060 的查询上限默认值。
const int kNewsDefaultMaxQueries = 10;

/// SET-061 的单材料字符预算默认值。
const int kNewsDefaultSingleMaterialBudget = 8000;

/// 一次事件的聚合结果（选材 + 必访站逐站结果 + 检索结果）。
final class NewsAggregationResult {
  /// 构造结果。
  const NewsAggregationResult({
    required this.materials,
    required this.siteResults,
    required this.issuedQueries,
    this.searchResultCount = 0,
    this.blockedQueryCount = 0,
    this.shortfall,
  });

  /// 全部材料（RSS + 抓取 + 检索；已去重、已按预算截断）。
  final List<NewsMaterial> materials;

  /// 必访问网站逐站结果（顺序与快照一致）。
  final List<NewsSiteFetchResult> siteResults;

  /// 实际发出的查询词（可能少于快照里的关键词：禁词与重复会在此被拦掉）。
  final List<String> issuedQueries;

  /// 检索返回的结果条数。
  final int searchResultCount;

  /// 因禁词被拦下的查询数（界面据此说明「有些查询没有发出去」）。
  final int blockedQueryCount;

  /// 输入不足的说明；有输入时为 null。
  final String? shortfall;

  /// 是否有可用的输入材料。
  bool get hasInput => materials.isNotEmpty;

  /// 必访失败（或超时）的站点。
  List<NewsSiteFetchResult> get failedSites => siteResults
      .where((NewsSiteFetchResult r) => r.failed)
      .toList(growable: false);

  /// 按 sourceId 索引材料（引用校验用）。
  Map<String, NewsMaterial> get bySourceId => <String, NewsMaterial>{
    for (final NewsMaterial material in materials) material.sourceId: material,
  };
}

/// 模型产出的一个条目的处理结果。
enum NewsItemStatus {
  /// 保留（引用都在材料集合里）。
  kept,

  /// 退回：引用了不存在的 sourceId（模型编造引用）。
  rejectedUnknownCitation,

  /// 退回：没有任何引用。
  rejectedMissingCitation,
}

/// 一条证据标签（架构 4.4 的四类）。
///
/// **没有「已证实」这一项**：架构 4.4 明确「不可声称保证真实性或输出模型自报的概率」。
/// 四类标签描述的都是「客户端做了什么与看到了什么」，不是「这件事是真的」。
enum NewsEvidenceLabel {
  /// 来源单一：只有一条独立来源支持（转载不算第二条）。
  singleSource,

  /// 材料不足：核验没有拿到可用结果。
  insufficientMaterial,

  /// 来源冲突：第二条来源明确否定该陈述。
  sourceConflict,

  /// 未联网核验：没有配置可用的搜索服务（只读 RSS 的输出）。
  notVerifiedOnline,
}

/// 初稿里的一个条目。
final class NewsDraftItem {
  /// 构造条目。
  const NewsDraftItem({
    required this.index,
    required this.text,
    required this.sourceIds,
    required this.status,
    this.unknownSourceIds = const <String>[],
    this.labels = const <NewsEvidenceLabel>[],
    this.independentSourceCount = 0,
    this.verificationNote,
  });

  /// 条目序号（1 起，按模型输出顺序）。
  final int index;

  /// 条目文本（**已剥离** `[sourceId]` 标记的正文）。
  final String text;

  /// 条目声明的引用。
  final List<String> sourceIds;

  /// 处理结果。
  final NewsItemStatus status;

  /// 不存在的引用（被拒绝时列出，供界面如实说明）。
  final List<String> unknownSourceIds;

  /// 证据标签（T038 的核验结果；核验前为空列表）。
  final List<NewsEvidenceLabel> labels;

  /// 核验后认定的**独立来源**条数（转载聚类之后）。
  final int independentSourceCount;

  /// 核验方法的记录（启发式与阈值，供用户核对判定依据）。
  final String? verificationNote;

  /// 是否保留。
  bool get kept => status == NewsItemStatus.kept;

  /// 是否至少声明了引用。
  bool get hasCitation => sourceIds.isNotEmpty;

  /// 复制并覆盖部分字段（T038 在核验后写标签）。
  NewsDraftItem copyWith({
    List<NewsEvidenceLabel>? labels,
    int? independentSourceCount,
    String? verificationNote,
  }) => NewsDraftItem(
    index: index,
    text: text,
    sourceIds: sourceIds,
    status: status,
    unknownSourceIds: unknownSourceIds,
    labels: labels ?? this.labels,
    independentSourceCount:
        independentSourceCount ?? this.independentSourceCount,
    verificationNote: verificationNote ?? this.verificationNote,
  );

  /// 落库形态。
  Map<String, Object?> toJson() => <String, Object?>{
    'index': index,
    'text': text,
    'sourceIds': sourceIds,
    'status': status.name,
    if (unknownSourceIds.isNotEmpty) 'unknownSourceIds': unknownSourceIds,
    if (labels.isNotEmpty)
      'labels': <Object?>[for (final NewsEvidenceLabel l in labels) l.name],
    'independentSourceCount': independentSourceCount,
    if (verificationNote != null) 'verificationNote': verificationNote,
  };

  /// 从落库形态还原。
  static NewsDraftItem? fromJson(Map<Object?, Object?> json) {
    final Object? text = json['text'];
    if (text is! String) {
      return null;
    }
    return NewsDraftItem(
      index: json['index'] is int ? json['index']! as int : 0,
      text: text,
      sourceIds: _stringList(json['sourceIds']),
      status: _itemStatus(json['status']),
      unknownSourceIds: _stringList(json['unknownSourceIds']),
      labels: _labels(json['labels']),
      independentSourceCount: json['independentSourceCount'] is int
          ? json['independentSourceCount']! as int
          : 0,
      verificationNote: json['verificationNote'] is String
          ? json['verificationNote']! as String
          : null,
    );
  }

  @override
  String toString() =>
      'NewsDraftItem(#$index ${status.name} refs=${sourceIds.join(',')})';
}

/// 初稿解析结果。
final class NewsDraftParseResult {
  /// 构造结果。
  const NewsDraftParseResult({
    required this.items,
    required this.headings,
    required this.unknownSourceIds,
    this.failureReason,
  });

  /// 全部条目（含被退回的，界面要如实显示「这几条没有保留」）。
  final List<NewsDraftItem> items;

  /// 未带引用的标题行（模型按输出规范给的主题分组标题）。
  final List<String> headings;

  /// 本次输出里出现过的、不在材料集合里的引用（去重，按出现顺序）。
  final List<String> unknownSourceIds;

  /// 整稿失败原因；有可用条目时为 null。
  final String? failureReason;

  /// 保留的条目。
  List<NewsDraftItem> get keptItems =>
      items.where((NewsDraftItem item) => item.kept).toList(growable: false);

  /// 被退回的条目。
  List<NewsDraftItem> get rejectedItems =>
      items.where((NewsDraftItem item) => !item.kept).toList(growable: false);

  /// 是否可用（至少一条被保留）。
  bool get ok => keptItems.isNotEmpty;

  /// 是否出现了编造引用。
  bool get hasFabricatedCitation => unknownSourceIds.isNotEmpty;
}

/// 引用标记的匹配：`[sourceId]`。
///
/// **排除 markdown 链接**（`[文字](地址)`）：模型偶尔会写成链接形态，把它当成一次
/// 「引用了不存在的 sourceId」会让一个格式小偏差表现成「编造引用」。判据是方括号之后
/// 紧跟 `(`。括号内出现方括号本身也不匹配（那是嵌套结构，不是引用）。
final RegExp _citationPattern = RegExp(r'\[([^\[\]\(\)]{1,64})\]');

/// 解析模型产出为条目列表，并用材料集合校验引用（架构 4.4）。
///
/// 规则（每条都有用例）：
///   * 带引用的行 → 条目；引用全部有效 → 保留，否则**退回**该条目；
///   * 无引用的行：长度 <= 40 且不含句末标点 → 视为标题；否则作为「缺引用」条目退回；
///   * 至少一条被保留 → 解析成功；一条都没有 → 整稿失败（`failureReason`）。
NewsDraftParseResult parseNewsDraft({
  required String text,
  required Set<String> knownSourceIds,
}) {
  final List<NewsDraftItem> items = <NewsDraftItem>[];
  final List<String> headings = <String>[];
  final List<String> unknown = <String>[];
  int index = 0;
  for (final String rawLine in text.split('\n')) {
    final String line = rawLine.trim();
    if (line.isEmpty) {
      continue;
    }
    final List<String> cited = <String>[];
    for (final RegExpMatch match in _citationPattern.allMatches(line)) {
      final int end = match.end;
      if (end < line.length && line[end] == '(') {
        // markdown 链接：不是引用标记。
        continue;
      }
      cited.add(match.group(1)!.trim());
    }
    // 条目正文：剥离引用标记之后的部分。
    final String body = line
        .replaceAllMapped(
          _citationPattern,
          (Match match) => match.end < line.length && line[match.end] == '('
              ? match.group(0)!
              : '',
        )
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .trim();
    if (cited.isEmpty) {
      if (body.length <= kNewsHeadingMaxLength &&
          !_endsWithSentencePunctuation(body)) {
        headings.add(body);
      } else {
        index++;
        items.add(
          NewsDraftItem(
            index: index,
            text: body,
            sourceIds: const <String>[],
            status: NewsItemStatus.rejectedMissingCitation,
          ),
        );
      }
      continue;
    }
    final List<String> resolved = <String>[];
    final List<String> bad = <String>[];
    for (final String id in cited) {
      if (knownSourceIds.contains(id)) {
        if (!resolved.contains(id)) {
          resolved.add(id);
        }
      } else {
        if (!bad.contains(id)) {
          bad.add(id);
        }
        if (!unknown.contains(id)) {
          unknown.add(id);
        }
      }
    }
    index++;
    items.add(
      NewsDraftItem(
        index: index,
        text: body,
        sourceIds: resolved,
        status: bad.isEmpty
            ? NewsItemStatus.kept
            : NewsItemStatus.rejectedUnknownCitation,
        unknownSourceIds: bad,
      ),
    );
  }
  final List<NewsDraftItem> kept = items
      .where((NewsDraftItem item) => item.kept)
      .toList(growable: false);
  return NewsDraftParseResult(
    items: items,
    headings: headings,
    unknownSourceIds: unknown,
    failureReason: kept.isEmpty
        ? _failureReasonFor(items: items, unknown: unknown)
        : null,
  );
}

/// 标题行的长度上限。
const int kNewsHeadingMaxLength = 40;

/// 整稿失败的原因说明（结构性，不含模型正文）。
String _failureReasonFor({
  required List<NewsDraftItem> items,
  required List<String> unknown,
}) {
  if (items.isEmpty) {
    return 'emptyOutput';
  }
  if (unknown.isNotEmpty &&
      items.every(
        (NewsDraftItem item) =>
            item.status == NewsItemStatus.rejectedUnknownCitation,
      )) {
    return 'fabricatedCitations';
  }
  return 'noUsableItem';
}

bool _endsWithSentencePunctuation(String text) {
  if (text.isEmpty) {
    return false;
  }
  const String punctuation = '。！？.!?;；:';
  return punctuation.contains(text[text.length - 1]);
}

/// 一次新闻任务的完整记录（落 news_runs 表）。
final class NewsRunRecord {
  /// 构造记录。
  const NewsRunRecord({
    required this.localDate,
    required this.timeZone,
    required this.version,
    required this.status,
    required this.snapshot,
    required this.siteResults,
    required this.materials,
    required this.items,
    required this.createdAt,
    this.id,
    this.isCurrent = false,
    this.draftText,
    this.providerAlias,
    this.modelId,
    this.consumedTokens = 0,
    this.attemptCount = 0,
    this.errorKind,
    this.verificationMethod,
    this.stage,
  });

  /// 本机自增 id；尚未落库时为 null。
  final int? id;

  /// 本地日期键。
  final String localDate;

  /// 任务时区。
  final String timeZone;

  /// 版本号（同一日期 + 时区下从 1 开始单调递增）。
  final int version;

  /// 任务状态九态（core 的任务状态机，与落库文本一致）。
  final TaskStatus status;

  /// 输入快照。
  final NewsInputSnapshot snapshot;

  /// 必访站逐站结果。
  final List<NewsSiteFetchResult> siteResults;

  /// 材料清单。
  final List<NewsMaterial> materials;

  /// 条目列表（含被退回的与证据标签）。
  final List<NewsDraftItem> items;

  /// 创建时刻（UTC）。
  final DateTime createdAt;

  /// 是否为当前展示版本（只有 succeeded/partial 允许为真）。
  final bool isCurrent;

  /// 初稿全文（未经条目拆分，保留原始输出以便核对）。
  final String? draftText;

  /// 产出它的提供商别名。
  final String? providerAlias;

  /// 产出它的模型 ID。
  final String? modelId;

  /// 累计消耗 token。
  final int consumedTokens;

  /// HTTP 尝试次数。
  final int attemptCount;

  /// 失败类别（结构标识）；成功为 null。
  final String? errorKind;

  /// 本次版本的核验方法记录（T038）。
  final String? verificationMethod;

  /// 中断时的阶段（`interrupted` 状态说明卡在哪一步）。
  final NewsRunStage? stage;

  /// 是否有可用产出。
  bool get hasResult =>
      (status == TaskStatus.succeeded || status == TaskStatus.partial) &&
      items.any((NewsDraftItem item) => item.kept);

  /// 复制并覆盖部分字段。
  NewsRunRecord copyWith({
    int? id,
    bool? isCurrent,
    List<NewsDraftItem>? items,
    String? verificationMethod,
    String? errorKind,
  }) => NewsRunRecord(
    id: id ?? this.id,
    localDate: localDate,
    timeZone: timeZone,
    version: version,
    status: status,
    snapshot: snapshot,
    siteResults: siteResults,
    materials: materials,
    items: items ?? this.items,
    createdAt: createdAt,
    isCurrent: isCurrent ?? this.isCurrent,
    draftText: draftText,
    providerAlias: providerAlias,
    modelId: modelId,
    consumedTokens: consumedTokens,
    attemptCount: attemptCount,
    errorKind: errorKind ?? this.errorKind,
    verificationMethod: verificationMethod ?? this.verificationMethod,
    stage: stage,
  );

  @override
  String toString() =>
      'NewsRunRecord($localDate/$timeZone v$version ${status.name} '
      'items=${items.length})';
}

/// 选材候选（来自本机文章的窄查询，仅含参与新闻的源）。
final class NewsCandidateArticle {
  /// 构造候选。
  const NewsCandidateArticle({
    required this.articleId,
    required this.feedId,
    required this.feedName,
    required this.title,
    required this.fetchedAt,
    this.summary,
    this.body,
    this.publishedAt,
    this.sourceUrl,
    this.guid,
    this.normalizedLink,
    this.favorite = false,
  });

  /// 本机文章 id。
  final int articleId;

  /// 所属订阅 id。
  final int feedId;

  /// 订阅显示名。
  final String feedName;

  /// 标题。
  final String title;

  /// 源摘要。
  final String? summary;

  /// 正文（可能为 null：源只给了摘要）。
  final String? body;

  /// 发布时间（UTC）；null 表示源未提供。
  final DateTime? publishedAt;

  /// 抓取时间（UTC）。
  final DateTime fetchedAt;

  /// 原始链接（保留查询参数）。
  final String? sourceUrl;

  /// 源内 GUID（仅在同一订阅范围内标识同一篇文章，架构 4.1）。
  ///
  /// 选材去重需要它：同一篇稿子在同一源里可能以两条（GUID 不同、链接相同）出现，
  /// 而「同一稿件不同 URL（镜像/重定向/跟踪参数）」只能靠规范化链接识别。
  final String? guid;

  /// 规范化链接（T013 的 normalizeLink 产物；仅用于匹配）。
  final String? normalizedLink;

  /// 是否加精（**不影响选材与排序权重**，SET-050/023）。
  final bool favorite;

  /// 参与排序与归属判定的有效时间：发布时间优先，缺失时用抓取时间（架构 4.1）。
  DateTime get effectiveTime => publishedAt ?? fetchedAt;

  /// 发布时间是否缺失（材料里要如实标注）。
  bool get publishedAtMissing => publishedAt == null;
}

/// 选材候选的读取端口（实现住 infrastructure/local）。
abstract interface class NewsCandidateStore {
  /// 读取 [startUtc, endUtc) 区间内、来自参与新闻的源的文章（按有效时间倒序）。
  ///
  /// [limit] 是**上限提示**：实现可以多取一点用于去重后截断，但不得无界读取。
  Future<Result<List<NewsCandidateArticle>>> loadCandidates({
    required DateTime startUtc,
    required DateTime endUtc,
    required int limit,
  });
}

/// 新闻任务记录的读写端口。
abstract interface class NewsRunStore {
  /// 追加一个版本（版本号由实现按「同日期同时区最大值 + 1」分配）。
  ///
  /// 只有 succeeded/partial 的追加会把 `isCurrent` 移到新版本上；失败/取消/中断的
  /// 追加保留上一版为当前版本（架构 4.4「保留上一次成功总结」）。
  Future<Result<NewsRunRecord>> append(NewsRunRecord record);

  /// 读某一天某个时区的全部版本（版本号倒序）。
  Future<Result<List<NewsRunRecord>>> loadVersions({
    required String localDate,
    required String timeZone,
  });

  /// 读当前展示版本；没有成功版本时返回 Ok(null)。
  Future<Result<NewsRunRecord?>> loadCurrent({
    required String localDate,
    required String timeZone,
  });

  /// 把某个历史版本切为当前展示版本（用户手动回退）。
  ///
  /// 实现必须拒绝把非成功版本设为当前（数据库 CHECK 也会拒绝）。
  Future<Result<void>> setCurrentVersion({
    required String localDate,
    required String timeZone,
    required int version,
  });

  /// 删除一个**非当前**的历史版本（T039 的版本管理）。
  ///
  /// 两条拒绝规则，都是「删掉之后能不能解释」的问题：
  ///   * **当前展示版本不可删**：它在界面上就是「这一天的总结」。直接删掉会让用户看到
  ///     「今天没有总结」——而用户的本意是清理旧稿，不是丢弃今天的结果。要先切到别的版本；
  ///   * **不存在的版本报错而不是静默成功**：静默成功会让界面显示「已删除」而库里什么都没变，
  ///     用户下次打开又看到它。
  Future<Result<void>> deleteVersion({
    required String localDate,
    required String timeZone,
    required int version,
  });

  /// 列出有记录的本地日期（日期倒序），供历史列表使用。
  Future<Result<List<String>>> listDates();

  /// 列出有记录的「日期 + 时区」组合（日期倒序），供历史切换使用。
  ///
  /// 为什么不能只用 [listDates] 再由界面猜时区：历史记录归属**当时的**时区（架构 4.4
  /// 「旅行后可查旧记录而不重写日期」），拿当前设备时区去查一条在别处生成的记录会查不到，
  /// 而界面只能显示「这一天没有记录」——用户会以为自己丢了那天的总结。
  Future<Result<List<NewsRunDateRef>>> listDateRefs();
}

/// 一条历史记录的定位（本地日期 + 当时的时区）。
final class NewsRunDateRef {
  /// 构造定位。
  const NewsRunDateRef({required this.localDate, required this.timeZone});

  /// 本地日期键。
  final String localDate;

  /// 当时的设备时区（IANA 名称）。
  final String timeZone;

  @override
  String toString() => 'NewsRunDateRef($localDate/$timeZone)';
}

/// 新闻任务缺少输入的说明文案标识（界面按语言映射，不在 domain 拼中文）。
enum NewsInputShortfall {
  /// 没有选中任何文章、没有关键词、必访站也全部失败。
  noInputAtAll,

  /// 总开关关闭且没有其它输入。
  globalDisabled,
}

/// 判断本次聚合是否属于「缺少输入」（架构 4.4：不编造新闻）。
///
/// 判据刻意要求**三处都空**：只要有任何一个可靠输入（文章、关键词、成功抓回的必访站），
/// 就不算缺输入——把「必访站失败但有 30 篇文章」判成缺输入会让用户看不到本来能生成的总结。
NewsInputShortfall? detectInputShortfall({
  required NewsAggregationResult aggregation,
  required NewsInputSnapshot snapshot,
}) {
  if (aggregation.materials.isNotEmpty) {
    return null;
  }
  if (aggregation.issuedQueries.isNotEmpty) {
    // 有查询要发（即使结果为空）：这不是「缺输入」，而是「检索没有命中」，
    // 两者的界面提示与下一步动作都不同。
    return null;
  }
  if (snapshot.candidates.isEmpty &&
      snapshot.keywords.isEmpty &&
      snapshot.requiredSites.isEmpty) {
    return snapshot.globalEnabled
        ? NewsInputShortfall.noInputAtAll
        : NewsInputShortfall.globalDisabled;
  }
  return NewsInputShortfall.noInputAtAll;
}

CitationAccessMethod _accessMethod(Object? raw) {
  for (final CitationAccessMethod value in CitationAccessMethod.values) {
    if (value.name == raw) {
      return value;
    }
  }
  return CitationAccessMethod.rss;
}

NewsItemStatus _itemStatus(Object? raw) {
  for (final NewsItemStatus value in NewsItemStatus.values) {
    if (value.name == raw) {
      return value;
    }
  }
  return NewsItemStatus.rejectedMissingCitation;
}

List<NewsEvidenceLabel> _labels(Object? raw) {
  if (raw is! List<Object?>) {
    return const <NewsEvidenceLabel>[];
  }
  final List<NewsEvidenceLabel> out = <NewsEvidenceLabel>[];
  for (final Object? item in raw) {
    for (final NewsEvidenceLabel value in NewsEvidenceLabel.values) {
      if (value.name == item) {
        out.add(value);
      }
    }
  }
  return out;
}

List<String> _stringList(Object? raw) => raw is List<Object?>
    ? <String>[
        for (final Object? item in raw)
          if (item is String) item,
      ]
    : const <String>[];

DateTime? _date(Object? raw) {
  if (raw is! String) {
    return null;
  }
  return DateTime.tryParse(raw)?.toUtc();
}

/// 由候选构造一条 RSS 材料（按 SET-061 截断并标注）。
NewsMaterial buildRssMaterial({
  required NewsCandidateArticle candidate,
  required int charBudget,
  required DateTime accessedAt,
}) {
  // 摘录优先用正文，没有正文时退到源摘要：正文比摘要更接近「材料」，而两者都缺时
  // 仍然给出标题作为最后手段（模型需要看到「有这篇文章」而不是一条空材料）。
  final String raw =
      _firstNonEmpty(<String?>[candidate.body, candidate.summary]) ?? '';
  final String cleaned = _cleanMaterialText(raw);
  final bool truncated = cleaned.length > charBudget;
  final String excerpt = truncated ? cleaned.substring(0, charBudget) : cleaned;
  final String sourceId = 'rss.${candidate.articleId}';
  return NewsMaterial(
    sourceId: sourceId,
    accessMethod: CitationAccessMethod.rss,
    title: candidate.title,
    url: candidate.sourceUrl ?? '',
    publishedAt: candidate.publishedAt,
    accessedAt: accessedAt,
    excerpt: excerpt,
    materialHash: materialHashOf(
      sourceId: sourceId,
      url: candidate.sourceUrl ?? '',
      excerpt: excerpt,
    ),
    truncated: truncated,
    contentLength: cleaned.length,
    articleId: candidate.articleId,
    feedName: candidate.feedName,
  );
}

/// 由抓取结果构造一条材料（正文已按 SET-061 截断）。
NewsMaterial buildFetchedMaterial({
  required String siteName,
  required String finalUri,
  required String title,
  required String text,
  required int originalLength,
  required bool truncated,
  required DateTime accessedAt,
}) {
  final String sourceId =
      'fetch.${sha256HexOfString(finalUri).substring(0, 16)}';
  return NewsMaterial(
    sourceId: sourceId,
    accessMethod: CitationAccessMethod.fetch,
    title: title.isEmpty ? siteName : title,
    url: finalUri,
    accessedAt: accessedAt,
    excerpt: text,
    materialHash: materialHashOf(
      sourceId: sourceId,
      url: finalUri,
      excerpt: text,
    ),
    truncated: truncated,
    contentLength: originalLength,
    feedName: siteName,
  );
}

String? _firstNonEmpty(List<String?> values) {
  for (final String? value in values) {
    if (value != null && value.trim().isNotEmpty) {
      return value;
    }
  }
  return null;
}

/// 清洗材料文本：折叠空白并去掉控制字符（材料进 prompt，不能带不可见噪声）。
String _cleanMaterialText(String raw) => raw
    .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// 摘录长度上限（界面展示引用摘录用；与 SET-061 的单材料预算不同）。
const int kNewsCitationExcerptMaxLength = 200;

/// 生成引用的最小摘录（从材料快照取，架构 4.4「最小摘录」）。
String citationExcerptOf(
  NewsMaterial material, {
  int limit = kNewsCitationExcerptMaxLength,
}) => material.excerpt.length <= limit
    ? material.excerpt
    : material.excerpt.substring(0, limit);

/// 从材料集合里取材料；未知 sourceId 返回 null。
NewsMaterial? findMaterial(List<NewsMaterial> materials, String sourceId) {
  for (final NewsMaterial material in materials) {
    if (material.sourceId == sourceId) {
      return material;
    }
  }
  return null;
}
