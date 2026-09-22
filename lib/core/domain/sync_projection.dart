// 同步投影（T041；架构 5.2「WebDAV 首发范围」、架构 5.1 的 Settings/SyncState 实体）。
//
// 这个文件回答一个问题：**哪些东西会离开本机**。它是纯数据与纯函数，没有 I/O，
// 因此「同步包里有没有凭据」「设备专属设置会不会被带走」这类问题可以在不连网、
// 不连库的情况下逐条断言。
//
// 为什么必须是**一处定义**而不是散在同步实现里各判一次：
//   - 架构 5.2 的两张清单（纳入 / 排除）不是建议，而是数据出境边界。写两处就迟早
//     只改一处，而漏改的那一处会表现为「Key 悄悄进了快照」——没有任何界面提示；
//   - T046 的明文备份有**另一张**排除清单，两者都从 SET 注册表的 C/D/S 分类派生，
//     分类只有一份（lib/core/settings/settings_registry.dart），因此两张清单不会漂移。
//
// 三条边界（逐条对应架构 5.2 的原话）：
//   1) 纳入：共通偏好（C 类）、非敏感模型/搜索配置、prompt/来源规则、订阅/分组、
//      三态阅读与收藏；
//   2) 排除：API Key、WebDAV 密码、带秘密的订阅认证（全部 S 类）、设备路径/字体/
//      背景文件、窗口布局、执行调度开关（D 类）；
//   3) 排除：正文、图片、生成总结、阅读会话统计（首发不自动同步，完整备份用于人工搬迁）。
library;

import '../settings/setting_definition.dart';
import '../settings/settings_registry.dart';
import 'news_config.dart';
import 'url_secrets.dart';

/// 同步实体的**类别标识**。
///
/// 存稳定字符串而不是枚举序号：序号会在枚举中间插一项之后整体错位，把一条订阅的
/// 变更记录静默读成一条文章状态的变更（与 ai_model_records.protocol_id 同一理由）。
abstract final class SyncEntityKind {
  /// 一个共通设置项（键是 SET 编号）。
  static const String setting = 'setting';

  /// 一个订阅（键是订阅表的 syncId）。
  static const String feed = 'feed';

  /// 一个分组（键是分组表的 syncId）。
  static const String group = 'group';

  /// 一篇文章的阅读状态与收藏（键是文章同步键）。
  static const String articleState = 'articleState';

  /// 一个必访问网站（SET-051，T036 产物）。
  static const String newsRequiredSite = 'newsRequiredSite';

  /// 一个有序字符串条目（SET-052/053，T036 产物）。
  static const String newsListEntry = 'newsListEntry';

  /// 一个 prompt 版本（SET-055，T036 产物）。
  static const String newsPromptVersion = 'newsPromptVersion';

  /// 全部类别（顺序即快照里的分区顺序）。
  static const List<String> all = <String>[
    setting,
    feed,
    group,
    articleState,
    newsRequiredSite,
    newsListEntry,
    newsPromptVersion,
  ];
}

/// 同步投影：纳入与排除的**权威清单**。
///
/// 无实例状态（全部是静态清单 + 判定函数），因此不需要构造参数，也无法出现
/// 「两份投影不一致」的情形。字段名用字符串而不是 Dart 反射：字段名会进入快照格式，
/// 必须是可断言、可 diff 的稳定标识（反射拿到的名字会随重命名静默变化）。
final class SyncProjection {
  /// 私有构造：本类是纯规则集合，不实例化。
  const SyncProjection._();

  // -------------------------------------------------------------------------
  // 1) 共通设置（SET C 类）
  // -------------------------------------------------------------------------

  /// 参与同步的设置编号（C 类且可持久化），按注册表顺序（即编号升序）。
  ///
  /// 从注册表**派生**而不是手抄清单：手抄的清单会与文档第 6 节的分类漂移，而漂移的
  /// 后果是「某一项 C 类设置在新设备上永远是默认值」，界面上完全看不出来。
  static List<String> get settingCodes =>
      SettingRegistry.withClassification(SettingClassification.common)
          .where((SettingDefinition definition) => definition.isPersistent)
          .map((SettingDefinition definition) => definition.id.code)
          .toList(growable: false);

  /// 明确排除的设置编号（S 类 + D 类），供同步预览说明「这些不会离开本机」。
  static List<String> get excludedSettingCodes => SettingRegistry.all
      .where(
        (SettingDefinition definition) =>
            definition.isSecret ||
            definition.classification == SettingClassification.device,
      )
      .map((SettingDefinition definition) => definition.id.code)
      .toList(growable: false);

  /// 该编号是否是同步的共通设置。
  static bool includesSetting(String code) {
    final SettingDefinition? definition = SettingRegistry.find(code);
    if (definition == null) {
      // 未注册编号既不纳入也不排除到「已知清单」里：调用方拿到 false 说明它不在
      // 投影内，与「文档里没有这一项」是同一个结论。
      return false;
    }
    return definition.classification == SettingClassification.common &&
        definition.isPersistent;
  }

  // -------------------------------------------------------------------------
  // 2) 订阅与分组
  // -------------------------------------------------------------------------

  /// 参与同步的订阅字段（快照里这一组就是「这台设备看到的订阅」）。
  static const List<String> feedFields = <String>[
    'syncId',
    'normalizedUrl',
    'name',
    'sourceName',
    'groupSyncId',
    'favorite',
    'enabled',
    'newsEnabled',
    'refreshIntervalMinutes',
    'sortOrder',
  ];

  /// 明确排除的订阅字段。
  static const List<String> excludedFeedFields = <String>[
    // 本机自增 id 在另一台设备上必然指向别的行（架构 5.2）。
    'id',
    // 本机安全存储的凭据引用：标识本身不是秘密，但它只在**本机**有意义
    // （另一台设备要各自补填），因此不进快照（架构 5.2「其他设备提示补填」）。
    'credentialRef',
    // 条件请求缓存与抓取诊断：它们是本机的网络状态，跨设备同步会让另一台设备
    // 拿着本机的 ETag 去请求（那台设备的源内容可能还不一样）。
    'httpEtag',
    'httpLastModified',
    'lastCheckedAt',
    'lastRefreshResult',
    'lastRefreshErrorKind',
  ];

  /// 参与同步的分组字段。
  static const List<String> groupFields = <String>[
    'syncId',
    'name',
    'sortOrder',
    'pinned',
    'isReserved',
  ];

  /// 明确排除的分组字段（仅本机自增 id）。
  static const List<String> excludedGroupFields = <String>['id'];

  // -------------------------------------------------------------------------
  // 3) 文章状态（只有状态，没有正文）
  // -------------------------------------------------------------------------

  /// 参与同步的文章字段。
  ///
  /// 注意这里是「文章**状态**」而不是「文章」：正文、摘要、图片、AI 产出全部排除，
  /// 因此这一组字段在快照里对应的是一条 ArticleState 记录，而不是一篇可读文章
  /// （架构 5.1 把 Article / Revision 与 ArticleState 明确分成两个实体）。
  static const List<String> articleStateFields = <String>[
    'syncKey',
    'readingState',
    'favorite',
    'deleted',
    'revision',
  ];

  /// 明确排除的文章字段（首发不自动同步的内容，架构 5.2）。
  static const List<String> excludedArticleFields = <String>[
    'body',
    'bodyHash',
    'extractedBody',
    'extractedBodyHash',
    'summary',
    'aiSummary',
    'imageUrl',
    'extractedImageUrls',
    // 阅读会话统计：架构 5.3 明确「首发不跨设备相加」。
    'readingSeconds',
  ];

  // -------------------------------------------------------------------------
  // 4) 新闻来源规则（T036 产物）
  // -------------------------------------------------------------------------

  /// 参与同步的新闻规则类别。
  ///
  /// 三个有序列表直接引用 [NewsListCategory] 的常量而不是再写一遍字符串：这是
  /// 「T036 的产物被纳入同步」这句话的可执行形式，写第二份字面量就会在某个类别改名
  /// 之后变成「投影里有一个不存在的类别」。
  static const List<String> newsRuleKinds = <String>[
    'requiredSites',
    NewsListCategory.keywords,
    NewsListCategory.blockedQueryTerms,
    NewsListCategory.excludedTopics,
    'promptVersions',
  ];

  /// 参与同步的 prompt 语言（中英两套模板各自版本化，都要同步）。
  static const List<String> newsPromptLanguages = <String>['zh-Hans', 'en'];

  /// 该类别是否是同步的新闻规则。
  static bool includesNewsRuleKind(String kind) => newsRuleKinds.contains(kind);

  /// 该字段是否随订阅同步。
  static bool syncsFeedField(String field) => feedFields.contains(field);

  /// 该字段是否随分组同步。
  static bool syncsGroupField(String field) => groupFields.contains(field);

  /// 该字段是否随文章状态同步。
  static bool syncsArticleStateField(String field) =>
      articleStateFields.contains(field);
}

// ===========================================================================
// 私密订阅地址：可同步地址与秘密的拆分（架构 5.2、SET-027）
// ===========================================================================

/// 订阅凭据引用的类别（Keychain account 前缀）。
///
/// 与 credential_store.dart 里列举的 `feed-auth` 同一口径：凭据的定位键是
/// 「类别 + 订阅 syncId」，因此同一条订阅在每台设备上都能找到**自己**那份秘密，
/// 而两台的秘密可以不同（用户可能给同一源申请了两个 token）。
const String feedAuthCredentialCategory = 'feed-auth';

/// 一条订阅地址进入同步包之前的结果。
final class SyncFeedUrlPlan {
  /// 构造结果。
  const SyncFeedUrlPlan({
    required this.syncableUrl,
    required this.credentialRef,
    required this.strippedParams,
  });

  /// 可以放进快照的地址（已去掉明确的秘密参数与 userinfo）。
  final String syncableUrl;

  /// 秘密在本机的凭据引用（Keychain 的 account 字符串）。
  ///
  /// 注意它是**引用**而不是值：值只写进 Keychain，快照里连引用都不带（引用在另一台
  /// 设备上没有意义，两台设备的 Keychain 是各自的）。
  final String credentialRef;

  /// 被剥离的参数名（只留名字，不含值；界面据此提示「有 N 个参数需要补填」）。
  final List<String> strippedParams;

  /// 其他设备是否需要补填凭据。
  ///
  /// 判据是「确实剥离了秘密」，而不是「地址看起来像需要认证」：后者会把一个公开源
  /// 说成需要凭据，用户按提示去填一个根本不存在的 token。
  bool get needsCredentialPrompt => strippedParams.isNotEmpty;
}

/// 把一条订阅地址拆成「可同步地址 + 本机凭据引用」（复用 T015 的 [stripUrlSecrets]）。
///
/// 为什么复用而不是在同步层再写一遍参数判定：秘密参数名的清单必须只有一处
/// （见 url_secrets.dart 的说明），否则迟早出现「导出时遮了、同步时没遮」。
SyncFeedUrlPlan planSyncFeedUrl({
  required String rawUrl,
  required String feedSyncId,
}) {
  final UrlSecretStripResult stripped = stripUrlSecrets(rawUrl);
  final String escapedSyncId = feedSyncId.replaceAll(':', '%3A');
  return SyncFeedUrlPlan(
    syncableUrl: stripped.url,
    credentialRef: '$feedAuthCredentialCategory:$escapedSyncId',
    strippedParams: stripped.removed,
  );
}
