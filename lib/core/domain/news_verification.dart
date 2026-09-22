// 独立来源核验与引用校验（T038；架构 4.4「重要事实尝试至少两个独立来源；转载同一稿件不能
// 算两个证据。没有足够证据时标‘来源单一/材料不足’，不同来源矛盾标‘来源冲突’，只读 RSS 标
// ‘未联网核验’；不可声称保证真实性或输出模型自报的概率」「引用只可使用真实获取的 sourceId，
// 保存标题、URL、时间、最小摘录和材料哈希；摘要、全文、搜索片段分别标明」）。
//
// 本文件是**纯函数层**：关键词提取、相似度、支持/矛盾的判定、转载聚类与标签分配都不碰 IO。
// 因此「转载不当独立证据」「冲突保守标记」这些验收项可以在没有网络、没有模型的情况下逐条
// 断言——而它们恰恰是最容易被「看起来合理」的实现悄悄做错的部分。
//
// 五条刻意的设计：
//
//   1) **标签描述的是「客户端做了什么」，不是「这件事是真的」**。四类标签里没有「已证实」
//      这一项，因为架构 4.4 明确禁止声称保证真实性。用户看到的「来源单一」含义是「按这套
//      阈值没有找到第二条独立来源」，而不是「这件事是假的」——两者的差别决定这款产品会不会
//      被误信，因此判据（阈值、查询数、方法名）随标签一起记录。
//   2) **冲突是保守的**：无法确定就标「来源单一」，绝不标「来源冲突」。标错冲突的代价是
//      用户对一条真实报道产生怀疑，而漏标冲突只是少了一条提示；两个方向的代价不对称，
//      因此判据要求「明确否定」而不是「相似度低」。
//   3) **转载聚类是独立来源判定的前提**。同一稿件被多家站转载时 URL 不同、标题几乎相同，
//      不去重就会把「一份稿子」算成两份独立证据——这正是架构 4.4 点名禁止的。
//   4) **聚类用「规范化 URL 相同」或「标题高度相似」，不用「同域」**。同一个站可以发两条
//      不同事实的报道，按域合并会凭空制造「一条独立来源」；而标题相似度阈值（0.9）取得很
//      高，是为了避免把「同一事件的两家不同报道」错误合并（那会让第二条来源凭空消失）。
//   5) **引用字段完整性单独校验**（URL/时间/最小摘录/获取方式）：架构 4.4 要求引用可被
//      追溯，缺了时间或摘录的引用在界面上看起来与完整引用一样，但用户无法核对。
library;

import '../digest/sha256.dart';

import 'news_run.dart';

/// 一次核验使用的方法记录（随版本落库，用户可核对判定依据）。
final class NewsVerificationMethod {
  /// 构造方法记录。
  const NewsVerificationMethod({
    required this.usedSearch,
    required this.queriesIssued,
    required this.resultsSeen,
    this.supportThreshold = kNewsSupportOverlapThreshold,
    this.titleSimilarityThreshold = kNewsSyndicationTitleThreshold,
    this.searchProvider,
  });

  /// 本次核验是否真的联网检索过。
  ///
  /// false 表示「未联网核验」：没有配置搜索服务（架构 4.4 的「只读 RSS 标未联网核验」）。
  final bool usedSearch;

  /// 实际发出的派生查询数（用户可核对「核验了几个条目」）。
  final int queriesIssued;

  /// 看过的检索结果数。
  final int resultsSeen;

  /// 认定「支持」的关键词重叠度阈值。
  final double supportThreshold;

  /// 认定「同一稿件」的标题相似度阈值。
  final double titleSimilarityThreshold;

  /// 实际使用的搜索协议标识；未联网时为 null。
  final String? searchProvider;

  /// 落库用的方法说明文本（结构化，不含材料正文）。
  String describe() =>
      'search=${usedSearch ? 'yes' : 'no'} queries=$queriesIssued '
      'results=$resultsSeen support>=$supportThreshold '
      'syndication>=$titleSimilarityThreshold'
      '${searchProvider == null ? '' : ' provider=$searchProvider'}';

  /// 落库形态。
  Map<String, Object?> toJson() => <String, Object?>{
    'usedSearch': usedSearch,
    'queriesIssued': queriesIssued,
    'resultsSeen': resultsSeen,
    'supportThreshold': supportThreshold,
    'titleSimilarityThreshold': titleSimilarityThreshold,
    if (searchProvider != null) 'searchProvider': searchProvider,
  };

  /// 从落库形态还原；结构不符时返回 null（调用方按「未核验」处理）。
  static NewsVerificationMethod? fromJson(Map<Object?, Object?> json) {
    final Object? usedSearch = json['usedSearch'];
    if (usedSearch is! bool) {
      return null;
    }
    return NewsVerificationMethod(
      usedSearch: usedSearch,
      queriesIssued: json['queriesIssued'] is int
          ? json['queriesIssued']! as int
          : 0,
      resultsSeen: json['resultsSeen'] is int ? json['resultsSeen']! as int : 0,
      supportThreshold: json['supportThreshold'] is num
          ? (json['supportThreshold']! as num).toDouble()
          : kNewsSupportOverlapThreshold,
      titleSimilarityThreshold: json['titleSimilarityThreshold'] is num
          ? (json['titleSimilarityThreshold']! as num).toDouble()
          : kNewsSyndicationTitleThreshold,
      searchProvider: json['searchProvider'] is String
          ? json['searchProvider']! as String
          : null,
    );
  }
}

/// 认定「第二条来源支持同一事实」的关键词重叠度阈值。
///
/// 取值理由：条目文本与检索片段经常只是部分重叠（片段是摘要、条目是整理后的句子），
/// 阈值过高会让绝大多数真实支持被判成「材料不足」。0.34 意味着「条目关键词里约三分之一
/// 在来源里出现」即算支持——这是启发式，因此它随标签一起记录下来供用户核对。
const double kNewsSupportOverlapThreshold = 0.34;

/// 认定「同一稿件（转载）」的标题相似度阈值（架构 4.4「标题相似度 > 0.9 归同稿」）。
const double kNewsSyndicationTitleThreshold = 0.9;

/// 一条判定用的事实陈述。
final class NewsClaim {
  /// 构造陈述。
  const NewsClaim({required this.text, required this.keywords});

  /// 从条目文本构造（自动提取关键词）。
  factory NewsClaim.of(String text) =>
      NewsClaim(text: text, keywords: extractClaimKeywords(text));

  /// 条目文本。
  final String text;

  /// 关键词（提取规则见 [extractClaimKeywords]）。
  final List<String> keywords;

  /// 派生检索查询（用关键词拼查询，而不是把整句丢出去搜）。
  String get query => keywords.take(kNewsClaimQueryKeywordCount).join(' ');
}

/// 派生查询里使用的关键词个数。
const int kNewsClaimQueryKeywordCount = 6;

/// 提取一条陈述的关键词。
///
/// 两种文字取不同的切法：
///   * **CJK**：按**字符二元组**切（「央行/行降/降息」），因为中文没有词边界，按字符切会
///     让「央行」与「银行」共享「行」这类无意义的高频命中；
///   * **拉丁**：按非字母数字切词，只留长度 >= 3 的token，并丢弃常见停用词。
///
/// 结果是**纯启发式**，因此它随核验方法一起记录，而不是被当成客观关键词。
List<String> extractClaimKeywords(String text, {int maxKeywords = 24}) {
  final List<String> out = <String>[];
  final Set<String> seen = <String>{};
  final List<String> cjk = <String>[];
  final StringBuffer latin = StringBuffer();

  void flushLatin() {
    if (latin.isEmpty) {
      return;
    }
    final String token = latin.toString().toLowerCase();
    latin.clear();
    if (token.length >= 3 && !_stopWords.contains(token)) {
      if (seen.add(token)) {
        out.add(token);
      }
    }
  }

  for (final int rune in text.runes) {
    final String char = String.fromCharCode(rune);
    if (_isCjk(rune)) {
      flushLatin();
      cjk.add(char);
    } else if (_isAlnum(rune)) {
      latin.write(char);
    } else {
      flushLatin();
    }
  }
  flushLatin();

  for (int i = 0; i + 1 < cjk.length; i++) {
    final String bigram = '${cjk[i]}${cjk[i + 1]}';
    if (seen.add(bigram)) {
      out.add(bigram);
    }
  }
  return out.length <= maxKeywords ? out : out.sublist(0, maxKeywords);
}

const Set<String> _stopWords = <String>{
  'the',
  'and',
  'for',
  'with',
  'that',
  'this',
  'from',
  'have',
  'has',
  'was',
  'were',
  'are',
  'said',
  'says',
  'will',
  'but',
  'not',
  'its',
};

bool _isCjk(int rune) =>
    (rune >= 0x4E00 && rune <= 0x9FFF) ||
    (rune >= 0x3400 && rune <= 0x4DBF) ||
    (rune >= 0xF900 && rune <= 0xFAFF) ||
    (rune >= 0x3040 && rune <= 0x30FF);

bool _isAlnum(int rune) =>
    (rune >= 0x30 && rune <= 0x39) ||
    (rune >= 0x41 && rune <= 0x5A) ||
    (rune >= 0x61 && rune <= 0x7A) ||
    rune == 0x5F;

/// 关键词重叠度（命中数 / 关键词总数）。
///
/// 用「以条目为分母」而不是 Jaccard：来源文本（检索片段）比条目长得多，用两边的并集做分母
/// 会让一条真正支持的事实因为「来源还提到别的东西」而掉到阈值以下。分母固定为条目关键词数，
/// 语义也更直白：「这条陈述的多少关键词在来源里出现过」。
double claimOverlap({
  required List<String> claimKeywords,
  required String candidateText,
}) {
  if (claimKeywords.isEmpty) {
    return 0;
  }
  final String haystack = candidateText.toLowerCase();
  int hits = 0;
  for (final String keyword in claimKeywords) {
    if (haystack.contains(keyword.toLowerCase())) {
      hits++;
    }
  }
  return hits / claimKeywords.length;
}

/// 否定标记（中英各一组）。
///
/// 只收录**明确的否定词**，不含「可能」「据说」这类模糊表达：把模糊表达算成否定会让
/// 「来源冲突」在大量正常报道上被触发，而架构 4.4 要求这一项保守。
const List<String> kNewsNegationMarkers = <String>[
  '否认',
  '不实',
  '辟谣',
  '并未',
  '没有发生',
  '不属实',
  '假消息',
  '误传',
  'denied',
  'denies',
  'not true',
  'false',
  'no evidence',
  'debunked',
];

/// 标签（判定的最后一步）。
enum VerificationOutcome {
  /// 第二条来源支持同一事实（至少两条独立来源）。
  supported,

  /// 只有一条独立来源（含「来源是自己引用的那几条的转载」）。
  singleSource,

  /// 核验没有拿到可用结果（检索失败/没有结果/相似度不足）。
  insufficientMaterial,

  /// 第二条来源明确否定该陈述。
  conflict,

  /// 没有配置搜索服务（只读 RSS 路径）。
  notVerifiedOnline,

  /// 组件级证据（不需要独立来源：例如逐站状态说明）。
  notApplicable,
}

/// 把判定结果翻译成架构 4.4 的标签。
NewsEvidenceLabel? labelForOutcome(VerificationOutcome outcome) =>
    switch (outcome) {
      VerificationOutcome.supported => null,
      VerificationOutcome.singleSource => NewsEvidenceLabel.singleSource,
      VerificationOutcome.insufficientMaterial =>
        NewsEvidenceLabel.insufficientMaterial,
      VerificationOutcome.conflict => NewsEvidenceLabel.sourceConflict,
      VerificationOutcome.notVerifiedOnline =>
        NewsEvidenceLabel.notVerifiedOnline,
      VerificationOutcome.notApplicable => null,
    };

/// 一条候选证据（来自检索结果或其他材料）。
final class NewsEvidenceCandidate {
  /// 构造候选。
  const NewsEvidenceCandidate({
    required this.title,
    required this.text,
    required this.url,
    this.sourceId,
  });

  /// 标题。
  final String title;

  /// 片段（标题 + 摘要一起参与重叠度判定时用）。
  final String text;

  /// 地址。
  final String url;

  /// 材料标识（若有）。
  final String? sourceId;

  /// 标题 + 片段的合并文本（重叠度判定的输入）。
  String get combinedText => '$title $text';
}

/// 对一条陈述判定一次。
///
/// 判定顺序（顺序本身是产品规则，因此写在这里而不是散在调用点）：
///   1) 没有联网 → 未联网核验；
///   2) 有候选明确否定 → 来源冲突（**先于**支持判定：一条同时包含否定与关键词的来源
///      不能因为「重叠度高」被算成支持）；
///   3) 有候选重叠度达标 → 支持；
///   4) 有候选但都不达标、或候选为空 → 材料不足。
VerificationOutcome judgeClaim({
  required NewsClaim claim,
  required List<NewsEvidenceCandidate> candidates,
  bool searchConfigured = true,
  double supportThreshold = kNewsSupportOverlapThreshold,
}) {
  if (!searchConfigured) {
    return VerificationOutcome.notVerifiedOnline;
  }
  // 陈述本身是否就是一条否定式（例如「裁员的传闻不属实」）。这一项决定了「来源里的否定」
  // 是**反驳**还是**附和**：对一条否定式陈述，来源的否定是同意的证据。不做这个区分，
  // 报道澄清类事实的条目会被它自己的来源判成「来源冲突」。
  final bool claimNegates = containsNegationOf(claim.text, claim.keywords);
  bool sawSupport = false;
  for (final NewsEvidenceCandidate candidate in candidates) {
    final String text = candidate.combinedText;
    final double overlap = claimOverlap(
      claimKeywords: claim.keywords,
      candidateText: text,
    );
    if (overlap <= 0) {
      // 一个关键词都不沾的来源既不是支持也不是矛盾。
      continue;
    }
    if (containsNegationOf(text, claim.keywords)) {
      // 否定判定**先于**阈值判定：一条明确否认的报道往往只复述极少的关键词（「关于降息的
      // 报道不属实」），用支持阈值去卡它，冲突就永远不会被标出来。反过来，明确否定本身
      // 已经是足够强的信号（见 containsNegationOf 的两个条件）。
      return claimNegates
          ? VerificationOutcome.supported
          : VerificationOutcome.conflict;
    }
    if (overlap >= supportThreshold) {
      sawSupport = true;
    }
  }
  return sawSupport
      ? VerificationOutcome.supported
      : VerificationOutcome.insufficientMaterial;
}

/// 一段文本是否**明确否定**了该陈述。
///
/// 判据要求三个条件同时成立：
///   1) 文本里出现否定标记；
///   2) 该标记**与陈述关键词落在同一个句子里**（按句末标点切分）——否则一段报道里任何
///      无关的「否认」都会被算作对这条陈述的否定；
///   3) 两者在句内的距离不超过 [kNewsNegationWindow]（太长的句子里，远处的否定多半在说
///      别的事）。
///
/// 只看「文本里有否定词」会把「警方否认了此前的传闻，并确认了 X」这类**确认性**报道误判成
/// 矛盾；只看关键词又会把任何重叠都算成矛盾。
bool containsNegationOf(String text, List<String> claimKeywords) {
  final String lower = text.toLowerCase();
  for (final String sentence in _sentences(lower)) {
    for (final String marker in kNewsNegationMarkers) {
      int from = 0;
      while (true) {
        final int index = sentence.indexOf(marker, from);
        if (index < 0) {
          break;
        }
        final int start = index - kNewsNegationWindow < 0
            ? 0
            : index - kNewsNegationWindow;
        final int end =
            index + marker.length + kNewsNegationWindow > sentence.length
            ? sentence.length
            : index + marker.length + kNewsNegationWindow;
        final String window = sentence.substring(start, end);
        for (final String keyword in claimKeywords) {
          if (window.contains(keyword.toLowerCase())) {
            return true;
          }
        }
        from = index + marker.length;
      }
    }
  }
  return false;
}

/// 按句末标点切句（中英标点都算）。
List<String> _sentences(String text) => text
    .split(RegExp(r'[。！？!?;；\n\r]'))
    .where((String sentence) => sentence.trim().isNotEmpty)
    .toList(growable: false);

/// 否定标记周围取多宽的一段来判断「这个否定是关于这条陈述的」。
///
/// 取 12 个字符：太窄会漏掉「…不实，此前报道的降息一事并未发生」这类把否定与关键词分开
/// 的写法；太宽会把同一句里无关的否定算进来，而误判冲突的代价见文件头说明。
const int kNewsNegationWindow = 12;

/// 一次转载聚类的产物：一组「同一稿件」的来源。
final class NewsSourceCluster {
  /// 构造聚类。
  const NewsSourceCluster({required this.clusterId, required this.members});

  /// 聚类标识（规范化 URL 的摘要，或标题摘要）。
  final String clusterId;

  /// 参数（本机文章、抓取材料、检索结果）。
  final List<NewsEvidenceCandidate> members;

  @override
  String toString() => 'NewsSourceCluster($clusterId, ${members.length})';
}

/// 把候选来源按「同一稿件」聚类（URL 规范化 + 标题相似度 > 0.9）。
///
/// 两个判据是**或**关系：
///   * 规范化 URL 相同 → 同一页面（跟踪参数与末尾斜杠不算区别）；
///   * 标题相似度 > 阈值 → 同一稿件被转载到不同站（URL 完全不同）。
///
/// 不用「同域」：同一个站可以发两条不同事实的报道，按域合并会凭空制造一份「独立来源」。
List<NewsSourceCluster> clusterSyndicatedSources(
  List<NewsEvidenceCandidate> candidates, {
  double titleThreshold = kNewsSyndicationTitleThreshold,
}) {
  final List<NewsSourceCluster> clusters = <NewsSourceCluster>[];
  for (final NewsEvidenceCandidate candidate in candidates) {
    final String urlKey = normalizeEvidenceUrl(candidate.url);
    NewsSourceCluster? target;
    for (final NewsSourceCluster cluster in clusters) {
      if (cluster.members.any(
        (NewsEvidenceCandidate member) =>
            normalizeEvidenceUrl(member.url) == urlKey,
      )) {
        target = cluster;
        break;
      }
      if (cluster.members.any(
        (NewsEvidenceCandidate member) =>
            titleSimilarity(member.title, candidate.title) >= titleThreshold,
      )) {
        target = cluster;
        break;
      }
    }
    if (target == null) {
      clusters.add(
        NewsSourceCluster(
          clusterId: clusterIdOf(url: candidate.url, title: candidate.title),
          members: <NewsEvidenceCandidate>[candidate],
        ),
      );
    } else {
      target.members.add(candidate);
    }
  }
  return clusters;
}

/// 聚类的稳定标识（规范化 URL 摘要；无地址时退到标题摘要）。
String clusterIdOf({required String url, required String title}) {
  final String key = normalizeEvidenceUrl(url);
  final String material = key.isEmpty ? _normalizeTitle(title) : key;
  return sha256HexOfString(material).substring(0, 16);
}

/// 证据地址的规范化（只用于**聚类**，不改写原始地址）。
///
/// 去掉跟踪参数、末尾斜杠、fragment 与默认端口，并小写 scheme/host：同一篇稿件被转载时
/// 常带不同的跟踪参数，不归一就会把一份稿子算成两份独立证据。
String normalizeEvidenceUrl(String raw) {
  final String trimmed = raw.trim();
  if (trimmed.isEmpty) {
    return '';
  }
  final Uri? uri = Uri.tryParse(trimmed);
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
    return trimmed.toLowerCase();
  }
  final List<String> kept = <String>[];
  uri.queryParametersAll.forEach((String key, List<String> values) {
    final String lower = key.toLowerCase();
    if (lower.startsWith('utm_') ||
        lower == 'fbclid' ||
        lower == 'gclid' ||
        lower == 'spm' ||
        lower == 'ref' ||
        lower == 'share_token') {
      return;
    }
    for (final String value in values) {
      kept.add('$key=$value');
    }
  });
  kept.sort();
  final String path = uri.path.length > 1 && uri.path.endsWith('/')
      ? uri.path.substring(0, uri.path.length - 1)
      : uri.path;
  return '${uri.scheme.toLowerCase()}://${uri.host.toLowerCase()}$path'
      '${kept.isEmpty ? '' : '?${kept.join('&')}'}';
}

/// 标题相似度（0–1）。
///
/// 两条判据，取较大者：
///   1) **前后缀修饰关系**：去掉标点与空白之后，一条标题是另一条的连续子串，且**长度差
///      不超过 [kNewsSyndicationDecorationMax]** → 1.0。转载的典型形态是「独家：<原标题>」
///      「<原标题>（组图）」这类加几个字的修饰，用「长度差很小」来刻画它，可以避免把
///      「央行宣布降息」并进「央行今日宣布降息二十五个基点」这种**更长也更具体**的另一条
///      标题（那会让真正的第二条来源凭空消失）；
///   2) 否则用**字符二元组的 Dice 系数**。用二元组而不是编辑距离：编辑距离对「加两三个字」
///      过于敏感。
///
/// 另有一道长度下限（[kNewsSyndicationMinTitleLength]）：太短的标题（「降息」「要闻」）
/// 连修饰关系都不可信，低于它只按 URL 聚类。宁可少合并（第二条来源仍在），也不要把两条
/// 不同报道并成一条。
double titleSimilarity(String a, String b) {
  final String left = _normalizeTitle(a);
  final String right = _normalizeTitle(b);
  if (left.length < kNewsSyndicationMinTitleLength ||
      right.length < kNewsSyndicationMinTitleLength) {
    return 0;
  }
  if (left == right) {
    return 1;
  }
  final int lengthDelta = (left.length - right.length).abs();
  if (lengthDelta <= kNewsSyndicationDecorationMax &&
      (left.contains(right) || right.contains(left))) {
    return 1;
  }
  final Set<String> gramsA = _bigrams(left);
  final Set<String> gramsB = _bigrams(right);
  if (gramsA.isEmpty || gramsB.isEmpty) {
    return 0;
  }
  int shared = 0;
  for (final String gram in gramsA) {
    if (gramsB.contains(gram)) {
      shared++;
    }
  }
  return (2 * shared) / (gramsA.length + gramsB.length);
}

/// 参与标题相似度判定的最短标题长度（字符）。
///
/// 短标题（例如「降息」「要闻」「央行降息」）太容易互相包含，纳入相似度判定会制造
/// **假同稿**，从而让真正的第二条来源被判成转载。短标题仍然可以按 URL 聚类——那是唯一
/// 可靠的判据。
const int kNewsSyndicationMinTitleLength = 8;

/// 认定「只是加了前后缀修饰」的最大长度差（字符）。
///
/// 6 个字够容纳「独家：」「（组图）」「- 某某网」这类常见修饰，又不足以容纳一句新增的
/// 具体事实（那已经是另一条标题了）。
const int kNewsSyndicationDecorationMax = 6;

String _normalizeTitle(String raw) => raw
    .toLowerCase()
    .replaceAll(RegExp(r'[\s\u3000]+'), '')
    .replaceAll(RegExp(r'[\p{P}\p{S}]', unicode: true), '');

Set<String> _bigrams(String text) {
  final List<String> runes = text.runes
      .map(String.fromCharCode)
      .toList(growable: false);
  if (runes.length < 2) {
    return <String>{text};
  }
  final Set<String> out = <String>{};
  for (int i = 0; i + 1 < runes.length; i++) {
    out.add('${runes[i]}${runes[i + 1]}');
  }
  return out;
}

/// 「这条候选与条目自己的引用是不是同一稿件」的判定。
///
/// 判据是**聚类归属**而不是两两比较：候选先与自有引用一起聚类，然后看它落在哪个簇里、
/// 簇里有没有自有引用。这与「同一稿件不算两个证据」是同一条规则（架构 4.4），因此两个
/// 判定共用同一份聚类结果，不会出现「聚类说同稿、独立来源判定说不同稿」的分歧。
bool sameClusterAsOwn(
  NewsEvidenceCandidate candidate,
  List<NewsSourceCluster> clusters,
  Set<String> ownClusterIds,
) {
  for (final NewsSourceCluster cluster in clusters) {
    final bool containsCandidate = cluster.members.any(
      (NewsEvidenceCandidate member) =>
          member.url == candidate.url && member.sourceId == candidate.sourceId,
    );
    if (!containsCandidate) {
      continue;
    }
    if (ownClusterIds.contains(cluster.clusterId)) {
      return true;
    }
    for (final NewsEvidenceCandidate member in cluster.members) {
      if (member.sourceId != null &&
          ownClusterIds.contains(
            clusterIdOf(url: member.url, title: member.title),
          )) {
        return true;
      }
    }
  }
  return false;
}

/// 一条引用的完整性检查结果。
final class NewsCitationIssue {
  /// 构造结果。
  const NewsCitationIssue({
    required this.sourceId,
    required this.missingFields,
  });

  /// 材料标识。
  final String sourceId;

  /// 缺哪几个字段（`url` / `time` / `excerpt`）。
  final List<String> missingFields;

  @override
  String toString() =>
      'NewsCitationIssue($sourceId ${missingFields.join(',')})';
}

/// 检查一条引用是否具备架构 4.4 要求的字段（URL / 时间 / 最小摘录）。
///
/// 时间以「材料时间或访问时间任一存在」为准：RSS 材料经常没有发布时间，而我们对它的访问
/// 时刻是确定的——用「没有发布时间」判定引用不完整，会让大量正常引用被退回。
///
/// 获取方式（rss/fetch/search）不在缺失字段里：它是**枚举**而不是可空字段，在类型上不可能
/// 缺失；判定它没有意义，因此这里只检查真正可能缺的东西。
NewsCitationIssue? citationIssueOf(NewsMaterial material) {
  final List<String> missing = <String>[];
  if (material.url.trim().isEmpty) {
    missing.add('url');
  }
  if (material.publishedAt == null && material.accessedAt == null) {
    missing.add('time');
  }
  if (material.excerpt.trim().isEmpty) {
    missing.add('excerpt');
  }
  if (missing.isEmpty) {
    return null;
  }
  return NewsCitationIssue(sourceId: material.sourceId, missingFields: missing);
}

/// 一条条目在核验后的完整结论。
final class NewsItemVerification {
  /// 构造结论。
  const NewsItemVerification({
    required this.itemIndex,
    required this.outcome,
    required this.independentSourceCount,
    required this.candidateClusters,
    this.labels = const <NewsEvidenceLabel>[],
  });

  /// 条目序号（与 NewsDraftItem.index 对应）。
  final int itemIndex;

  /// 判定结果。
  final VerificationOutcome outcome;

  /// 认定的独立来源条数（含条目自己引用的材料，已按转载聚类去重）。
  final int independentSourceCount;

  /// 参与判定的来源聚类数（用户可核对「到底看到了几个不同来源」）。
  final int candidateClusters;

  /// 落库的证据标签。
  final List<NewsEvidenceLabel> labels;

  /// 是否拿到了第二条独立来源（用于界面上的「多源」展示，不是真实性断言）。
  bool get hasIndependentCorroboration =>
      outcome == VerificationOutcome.supported;

  @override
  String toString() =>
      'NewsItemVerification(#$itemIndex ${outcome.name} '
      'sources=$independentSourceCount clusters=$candidateClusters)';
}

/// 对一条条目做完整核验（纯函数：调用方负责把候选来源取回来）。
NewsItemVerification verifyNewsItem({
  required NewsDraftItem item,
  required List<NewsEvidenceCandidate> candidates,
  double supportThreshold = kNewsSupportOverlapThreshold,
  double titleThreshold = kNewsSyndicationTitleThreshold,
  bool searchConfigured = true,
}) {
  final NewsClaim claim = NewsClaim.of(item.text);
  final VerificationOutcome outcome = judgeClaim(
    claim: claim,
    candidates: candidates,
    searchConfigured: searchConfigured,
    supportThreshold: supportThreshold,
  );

  // 独立来源数 = 条目自己引用的材料的聚类数 + 支持性候选的聚类数（都按转载聚类去重）。
  final List<NewsEvidenceCandidate> ownSources = <NewsEvidenceCandidate>[
    for (final String sourceId in item.sourceIds)
      NewsEvidenceCandidate(title: '', text: '', url: '', sourceId: sourceId),
  ];
  final int ownClusters = item.sourceIds.length;
  final List<NewsSourceCluster> supportClusters =
      outcome == VerificationOutcome.supported
      ? clusterSyndicatedSources(
          candidates
              .where(
                (NewsEvidenceCandidate candidate) =>
                    claimOverlap(
                      claimKeywords: claim.keywords,
                      candidateText: candidate.combinedText,
                    ) >=
                    supportThreshold,
              )
              .toList(growable: false),
          titleThreshold: titleThreshold,
        )
      : const <NewsSourceCluster>[];
  final int total = ownClusters + supportClusters.length;
  final NewsEvidenceLabel? label = labelForOutcome(outcome);
  return NewsItemVerification(
    itemIndex: item.index,
    outcome: outcome,
    independentSourceCount: total,
    candidateClusters: ownSources.isEmpty
        ? supportClusters.length
        : ownClusters + supportClusters.length,
    labels: label == null
        ? const <NewsEvidenceLabel>[]
        : <NewsEvidenceLabel>[label],
  );
}
