// 新闻生成的 prompt 组合与固定协议（T036；架构 4.4「必访网站任务从来源设置组成总 prompt，
// 并由任务执行器逐站落实。即使用户手改总 prompt，原必访任务也不静默消失；提供明确的可视化/
// 高级覆盖模式和差异预览」「搜索查询排除词与内容主题排除词分开」，SET-050–055）。
//
// 这一层是**纯函数**：组合、差异与查询构造都不碰 IO，因此「必访站有没有进 prompt」这类断言
// 可以在没有模型、没有网络、没有数据库的情况下逐条验证。
//
// 三条结构性设计：
//
//   1) **固定输出协议段与用户可改部分在类型上分开**。[NewsPromptTemplate] 只持有
//      「用户可改部分」，协议段由 [kNewsCitationProtocolZh]/[kNewsCitationProtocolEn] 提供，
//      组合时无条件附加。因此「用户把引用格式删掉」在结构上不可能——没有一处 API 接受
//      「连协议一起覆盖」的输入（SET-054「不删除固定输出协议」）；
//   2) **必访站在组合结果里逐站可见**，并有显式的差异检查（[newsPromptDiff]）：高级覆盖模式
//      下若用户写的总 prompt 里缺了某些必访站，界面必须能说出**缺哪几个**，而不是只在文档里
//      承诺「不会静默消失」（架构 4.4）；
//   3) **查询禁词与主题排除是两个函数**：[buildNewsSearchQueries] 只处理「实际发给搜索服务的
//      查询词」，[newsExcludedTopicsSection] 只产出「写进 prompt 的内容偏好」。它们来自两个
//      独立列表，且其中之一被改动不会影响另一个（SET-053）。
library;

/// 生成语言（中/英各一套内置模板，SET-054）。
enum NewsPromptLanguage {
  /// 简体中文。
  chinese(code: 'zh-Hans'),

  /// 英文。
  english(code: 'en');

  const NewsPromptLanguage({required this.code});

  /// 稳定语言码（与 SET-011 的取值一致）。
  final String code;

  /// 由语言码还原；未知码返回 null（调用方回退到界面语言对应的那一份）。
  static NewsPromptLanguage? fromCode(String? code) {
    for (final NewsPromptLanguage value in NewsPromptLanguage.values) {
      if (value.code == code) {
        return value;
      }
    }
    return null;
  }
}

/// 引用协议的固定段（中文）。
///
/// 为什么这一段的每一个字符都不能由用户改：引用格式是**下游校验的输入契约**——T038 的引用
/// 校验会按 [sourceId] 的形状解析并核对「这个 id 是不是真实获取过的材料」。允许用户改写它，
/// 就等于允许把一次校验变成一个恒为真的空操作，而界面上一切正常。
const String kNewsCitationProtocolZh =
    '引用规则（不可更改）：'
    '（1）每一条结论后面用方括号标注它依据的材料引用，形如 [sourceId]；'
    '（2）sourceId 只能使用本次任务中实际获取到的材料标识，不得编造；'
    '（3）一条结论若依据多个材料，写成 [sourceId1][sourceId2]；'
    '（4）没有材料支撑的内容不要写出来。';

/// 引用协议的固定段（英文）。
const String kNewsCitationProtocolEn =
    'Citation rules (not editable): '
    '(1) after each claim, cite the material it is based on in square brackets, as [sourceId]; '
    '(2) sourceId must be one of the materials actually fetched in this task; never invent one; '
    '(3) cite multiple materials as [sourceId1][sourceId2]; '
    '(4) do not write claims that no material supports.';

/// 某一语言的引用协议固定段。
String newsCitationProtocol(NewsPromptLanguage language) => switch (language) {
  NewsPromptLanguage.chinese => kNewsCitationProtocolZh,
  NewsPromptLanguage.english => kNewsCitationProtocolEn,
};

/// 内置的输出规范模板（用户可改部分，SET-054）。
///
/// 这里**不含**引用协议段：协议由组合时无条件附加，因此恢复默认与用户保存走的是同一段
/// 文本，不会出现「恢复默认之后协议消失」这种只在特定路径出现的缺陷。
String builtInOutputSpec(NewsPromptLanguage language) => switch (language) {
  NewsPromptLanguage.chinese =>
    '输出要求：\n'
        '1. 按主题分组，每组给一个简短标题；\n'
        '2. 每条只写事实与它依据的引用，不写评论与推测；\n'
        '3. 同一事件有多家来源时合并为一条，并标出各家引用；\n'
        '4. 材料不足时明确写「材料不足」，不要用常识补齐。',
  NewsPromptLanguage.english =>
    'Output requirements:\n'
        '1. group by topic, each group with a short heading;\n'
        '2. each item states the fact and its citations only, no commentary or speculation;\n'
        '3. merge the same event from several sources into one item and list all citations;\n'
        '4. when material is insufficient, say "insufficient material" instead of filling in from prior knowledge.',
};

/// 内置的总体任务说明（用户可改部分；SET-055 的「自动组合任务+来源+规范」里的「任务」）。
String builtInTaskInstruction(NewsPromptLanguage language) =>
    switch (language) {
      NewsPromptLanguage.chinese => '请根据下面提供的材料，生成今天的新闻摘要。',
      NewsPromptLanguage.english =>
        'Based on the materials below, produce today\'s news summary.',
    };

/// 一个必访问网站（SET-051）。
/// 「新闻选材是否包含这个源」的**生效值**（SET-050）。
///
/// 读订阅表的 newsEnabled（三方：null 表示跟随 enabled），为 null 时跟随 enabled
/// ——「已启用订阅默认开」这条 SET-050 的口径因此在一个地方成立，而不是散在每个查询里各判断一次。
///
/// 用在 core 而不是存储层：界面（逐源开关的三态显示）与 T037 的选材查询都要同一份判断，
/// 写在 SQL 里会让界面无法复用，写在界面里会让查询与界面漂移。
bool newsIncludesFeed({
  required bool? newsEnabled,
  required bool feedEnabled,
}) => newsEnabled ?? feedEnabled;

/// 一个必访问网站（SET-051）。
final class NewsRequiredSite {
  /// 构造站点。
  const NewsRequiredSite({
    required this.name,
    required this.url,
    this.enabled = true,
    this.sortOrder = 0,
    this.id,
  });

  /// 本机自增 id；尚未落库时为 null。
  final int? id;

  /// 显示名（用户可改；进 prompt 时用它标识「这是哪一站」）。
  final String name;

  /// 站点地址。
  final String url;

  /// 是否启用（停用的站点不进 prompt、也不参与逐站执行）。
  final bool enabled;

  /// 排序权重（升序）。
  final int sortOrder;

  /// 复制并覆盖部分字段。
  NewsRequiredSite copyWith({
    String? name,
    String? url,
    bool? enabled,
    int? sortOrder,
    int? id,
  }) => NewsRequiredSite(
    id: id ?? this.id,
    name: name ?? this.name,
    url: url ?? this.url,
    enabled: enabled ?? this.enabled,
    sortOrder: sortOrder ?? this.sortOrder,
  );

  @override
  String toString() =>
      'NewsRequiredSite(#$id $name $url enabled=$enabled order=$sortOrder)';
}

/// 一次组合所需的全部输入（纯数据）。
final class NewsPromptInput {
  /// 构造输入。
  const NewsPromptInput({
    required this.language,
    this.taskInstruction,
    this.outputSpec,
    this.requiredSites = const <NewsRequiredSite>[],
    this.keywords = const <String>[],
    this.blockedQueryTerms = const <String>[],
    this.excludedTopics = const <String>[],
  });

  /// 生成语言。
  final NewsPromptLanguage language;

  /// 用户改过的任务说明；null 表示用内置。
  final String? taskInstruction;

  /// 用户改过的输出规范（**不含协议段**）；null 表示用内置。
  final String? outputSpec;

  /// 必访问网站（只取 enabled 的进 prompt）。
  final List<NewsRequiredSite> requiredSites;

  /// 联网搜索关键词（SET-052）。
  final List<String> keywords;

  /// 禁止发送的查询词（SET-053 的第一个列表）。
  final List<String> blockedQueryTerms;

  /// 排除的内容主题（SET-053 的第二个列表）。
  final List<String> excludedTopics;

  /// 生效的任务说明（用户值优先）。
  String get effectiveTaskInstruction =>
      _orBuiltIn(taskInstruction, builtInTaskInstruction(language));

  /// 生效的输出规范（用户值优先；**始终不含协议段**）。
  String get effectiveOutputSpec =>
      _orBuiltIn(outputSpec, builtInOutputSpec(language));

  /// 参与本次任务的必访站（按 sortOrder，其次按 id 稳定排序）。
  List<NewsRequiredSite> get enabledSites {
    final List<NewsRequiredSite> sites = requiredSites
        .where((NewsRequiredSite site) => site.enabled)
        .toList();
    sites.sort((NewsRequiredSite a, NewsRequiredSite b) {
      final int byOrder = a.sortOrder.compareTo(b.sortOrder);
      if (byOrder != 0) {
        return byOrder;
      }
      return (a.id ?? 0).compareTo(b.id ?? 0);
    });
    return sites;
  }

  static String _orBuiltIn(String? value, String fallback) {
    final String trimmed = value?.trim() ?? '';
    return trimmed.isEmpty ? fallback : trimmed;
  }
}

/// 组合后的 prompt（含分段，便于界面 diff 与测试逐段断言）。
final class ComposedNewsPrompt {
  /// 构造结果。
  const ComposedNewsPrompt({
    required this.text,
    required this.taskSection,
    required this.sourcesSection,
    required this.specSection,
    required this.citationSection,
    required this.requiredSiteLines,
  });

  /// 完整文本（按 任务 → 来源 → 规范 → 协议 的顺序）。
  final String text;

  /// 任务段。
  final String taskSection;

  /// 来源段（必访站逐站一行 + 关键词 + 排除主题）。
  final String sourcesSection;

  /// 输出规范段（用户可改部分）。
  final String specSection;

  /// 引用协议段（固定，不可删）。
  final String citationSection;

  /// 必访站逐站文本行（空列表表示本次没有必访站）。
  final List<String> requiredSiteLines;

  /// 是否包含逐站必访行。
  bool get listsRequiredSites => requiredSiteLines.isNotEmpty;
}

/// 组合一份总 prompt（SET-055 的「自动组合任务+来源+规范」）。
///
/// 顺序固定为 **任务 → 来源 → 规范 → 引用协议**：
///   * 任务在最前，模型先知道要做什么；
///   * 来源在中间，逐站可见（架构 4.4 的「逐站落实」在文本上也成立）；
///   * 规范紧随其后，约束输出形态；
///   * **协议永远在最后且无条件附加**：即使任务/来源/规范都被用户改过，引用格式仍然在，
///     因此「用户改总 prompt 导致协议消失」不可能发生。
ComposedNewsPrompt composeNewsPrompt(NewsPromptInput input) {
  final String task = input.effectiveTaskInstruction;
  final List<NewsRequiredSite> sites = input.enabledSites;
  final List<String> siteLines = <String>[
    for (final NewsRequiredSite site in sites) '- [${site.name}] ${site.url}',
  ];
  final StringBuffer sources = StringBuffer();
  if (siteLines.isEmpty) {
    // 没有必访站时也要明说，而不是留一段空白：留白会让「本来就没有配」与「配了但被过滤掉」
    // 在文本上不可分辨。
    sources.writeln('本次没有配置必访问网站。');
  } else {
    sources.writeln('必访问网站（每一站都要单独获取）：');
    for (final String line in siteLines) {
      sources.writeln(line);
    }
  }
  if (input.keywords.isNotEmpty) {
    sources.writeln('联网搜索关键词：${input.keywords.join('、')}');
  }
  if (input.blockedQueryTerms.isNotEmpty) {
    sources.writeln('禁止作为查询词发送：${input.blockedQueryTerms.join('、')}');
  }
  if (input.excludedTopics.isNotEmpty) {
    // 排除主题的文本只在这里产生：与「禁止发送的查询词」分开（SET-053）。
    sources.writeln(newsExcludedTopicsSection(input.excludedTopics));
  }
  final String spec = input.effectiveOutputSpec;
  final String citation = newsCitationProtocol(input.language);
  final String text = <String>[
    task,
    sources.toString().trimRight(),
    spec,
    citation,
  ].where((String part) => part.trim().isNotEmpty).join('\n\n');
  return ComposedNewsPrompt(
    text: text,
    taskSection: task,
    sourcesSection: sources.toString().trimRight(),
    specSection: spec,
    citationSection: citation,
    requiredSiteLines: siteLines,
  );
}

/// 高级覆盖模式下的差异（架构 4.4 的「差异预览」）。
final class NewsPromptDiff {
  /// 构造差异。
  const NewsPromptDiff({
    required this.missingSites,
    required this.hasCitationProtocol,
  });

  /// 用户的总 prompt 里**没有**提到的必访站（按 sortOrder）。
  final List<NewsRequiredSite> missingSites;

  /// 用户的总 prompt 里是否出现了引用协议的标志（`[sourceId]` 的出现方式）。
  final bool hasCitationProtocol;

  /// 是否有任何需要注意的差异。
  bool get hasWarning => missingSites.isNotEmpty;
}

/// 比较用户写的总 prompt 与「本来应该包含的东西」（高级覆盖模式的差异提示）。
///
/// 判据刻意用**地址或站名出现在文本里**，而不是要求格式完全一致：用户完全可能用自己的措辞
/// 写「先看 A 网、再看 B 站」，那不是错误；但一个**完全没有出现**的站就是被静默删掉了，那
/// 正是架构 4.4 要求显式提示的情形。
NewsPromptDiff newsPromptDiff({
  required String advancedPrompt,
  required List<NewsRequiredSite> requiredSites,
}) {
  final String haystack = advancedPrompt.toLowerCase();
  final List<NewsRequiredSite> missing = <NewsRequiredSite>[];
  for (final NewsRequiredSite site in requiredSites) {
    if (!site.enabled) {
      continue;
    }
    final bool byUrl = haystack.contains(site.url.toLowerCase());
    final bool byName =
        site.name.trim().isNotEmpty &&
        haystack.contains(site.name.trim().toLowerCase());
    if (!byUrl && !byName) {
      missing.add(site);
    }
  }
  return NewsPromptDiff(
    missingSites: missing,
    // 协议标志：方括号包裹的标识出现即认为用户保留了引用要求。
    hasCitationProtocol: RegExp(r'\[[^\]]+\]').hasMatch(advancedPrompt),
  );
}

/// 构造实际发给搜索服务的查询词（SET-052 + SET-053 的第一个列表）。
///
/// 两条与架构 4.4 对应的规则：
///   * **关键词列表是用户明确要搜的**，派生查询（T037 从 RSS 事件派生）与它合并；
///   * **禁止发送的查询词在**这一层**被拒绝**：不是「提示模型不要用」，而是这些词根本不会
///     出现在返回值里。服务商内部行为无法保证受客户端控制，但「实际发送的查询」必须符合本地
///     规则（架构 4.4）。
///
/// 判据用**包含**而不是相等：用户填「股市」是希望任何含「股市」的查询都别发出去，而不是只
/// 挡住恰好叫「股市」的那一个词。
List<String> buildNewsSearchQueries({
  required List<String> keywords,
  List<String> derivedQueries = const <String>[],
  List<String> blockedQueryTerms = const <String>[],
  int maxQueries = 10,
}) {
  final List<String> out = <String>[];
  final Set<String> seen = <String>{};
  for (final String raw in <String>[...keywords, ...derivedQueries]) {
    final String query = raw.trim();
    if (query.isEmpty) {
      continue;
    }
    final String lower = query.toLowerCase();
    final bool blocked = blockedQueryTerms.any((String term) {
      final String t = term.trim().toLowerCase();
      return t.isNotEmpty && lower.contains(t);
    });
    if (blocked) {
      continue;
    }
    if (!seen.add(lower)) {
      continue;
    }
    out.add(query);
    if (out.length >= maxQueries) {
      break;
    }
  }
  return out;
}

/// 排除主题写进 prompt 的那一段（SET-053 的第二个列表）。
///
/// 与 [buildNewsSearchQueries] **分开**：它不影响「发什么查询」，只影响「生成时不要写什么」。
/// 两个列表因此各自独立——改一个不会动另一个，测试也是两条。
String newsExcludedTopicsSection(List<String> excludedTopics) {
  final List<String> topics = <String>[
    for (final String topic in excludedTopics)
      if (topic.trim().isNotEmpty) topic.trim(),
  ];
  if (topics.isEmpty) {
    return '';
  }
  return '排除的内容主题（这些主题不要出现在结果里）：${topics.join('、')}';
}

/// 总 prompt 的模式（SET-055）。
enum NewsPromptMode {
  /// 自动组合（默认）：任务 + 来源 + 规范 + 固定协议。
  composed(code: 'composed'),

  /// 高级覆盖：用户写的总 prompt（**仍需经过差异检查**）。
  advancedOverride(code: 'advancedOverride');

  const NewsPromptMode({required this.code});

  /// 稳定标识（与 SET-055 的取值一致，落库与同步都用它）。
  final String code;

  /// 由稳定标识还原；未知值返回 null（调用方按「配置非法」处理，不猜一个模式）。
  static NewsPromptMode? fromCode(String? code) {
    for (final NewsPromptMode value in NewsPromptMode.values) {
      if (value.code == code) {
        return value;
      }
    }
    return null;
  }
}

/// 总 prompt 的一个版本（SET-055 的「版本/差异/恢复默认」）。
///
/// 每次保存**新增**一个版本而不是覆盖：覆盖会让「上次那版效果更好」无法回退，而 prompt 是
/// 那种「改坏了当天才发现」的配置。版本号单调递增，列表按版本号倒序展示。
final class NewsPromptVersion {
  /// 构造版本。
  const NewsPromptVersion({
    required this.version,
    required this.mode,
    required this.taskInstruction,
    required this.outputSpec,
    required this.advancedPrompt,
    required this.createdAt,
    this.language = NewsPromptLanguage.chinese,
    this.note,
  });

  /// 版本号（从 1 开始，单调递增）。
  final int version;

  /// 保存时的模式。
  final NewsPromptMode mode;

  /// 任务说明（用户可改部分）。
  final String taskInstruction;

  /// 输出规范（用户可改部分，**不含协议段**）。
  final String outputSpec;

  /// 高级覆盖模式下用户写的总 prompt；组合模式下为空串。
  final String advancedPrompt;

  /// 保存时刻（UTC）。
  final DateTime createdAt;

  /// 生成语言（版本与语言绑定：中英两套模板不应互相覆盖）。
  final NewsPromptLanguage language;

  /// 可选的备注（界面显示「这一版改了什么」；空为 null）。
  final String? note;

  @override
  String toString() =>
      'NewsPromptVersion(v$version ${mode.code} ${language.code})';
}

/// 版本列表的下一版号（没有历史时是 1）。
int nextNewsPromptVersion(List<NewsPromptVersion> existing) {
  int max = 0;
  for (final NewsPromptVersion version in existing) {
    if (version.version > max) {
      max = version.version;
    }
  }
  return max + 1;
}

/// 一次组合或覆盖的最终 prompt（**协议永远在**）。
///
/// 这是「用哪段文本去请求」的唯一入口：组合模式走 [composeNewsPrompt]，高级覆盖模式走用户
/// 文本 + 无条件附加的协议段。两种模式都在这里汇合，因此「协议段被删掉」不可能发生。
String resolveNewsPrompt({
  required NewsPromptMode mode,
  required NewsPromptInput input,
  String advancedPrompt = '',
}) {
  final ComposedNewsPrompt composed = composeNewsPrompt(input);
  if (mode != NewsPromptMode.advancedOverride) {
    return composed.text;
  }
  final String override = advancedPrompt.trim();
  if (override.isEmpty) {
    // 高级覆盖但内容是空的：回退到组合结果，而不是发一个只剩协议段的 prompt。
    return composed.text;
  }
  return '$override\n\n${composed.citationSection}';
}
