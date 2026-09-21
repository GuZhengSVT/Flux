// 新闻来源配置的读写端口（T036；SET-050–055、架构 4.4）。
//
// 端口住在 core（与 [ArticleTranslationStore] 同一做法）：组合 prompt 与选材规则都在 core/
// features，存储实现住 infrastructure，接口必须在中间。
//
// 三条约定：
//   * **列表是整体读写**（[replaceList] / [replaceRequiredSites]）：有序列表的部分更新会产生
//     「顺序空洞」，而那在唯一约束下表现为一次莫名其妙的写入失败；
//   * **prompt 版本只增不改**（[savePromptVersion] 只插入、[deletePromptVersion] 只用于用户
//     主动清理）：每次保存新版本是可回退的前提；
//   * **逐源新闻开关不在这里**：它属于订阅表（FeedCatalogStore.setFeedNewsEnabled），因为它是
//     「这个源」的属性。
library;

import '../result.dart';

import 'news_prompt.dart';

/// 有序字符串列表的类别（与存储层的稳定标识一一对应）。
///
/// 定义在 core 而不是 infrastructure：界面与组合逻辑都要用它，而 features 不得 import
/// infrastructure。存储层的表定义里有一份**同值**的常量，由测试断言两边一致。
abstract final class NewsListCategory {
  /// 联网搜索关键词（SET-052）。
  static const String keywords = 'keywords';

  /// 禁止发送的查询词（SET-053 之一）。
  static const String blockedQueryTerms = 'blockedQueryTerms';

  /// 排除的内容主题（SET-053 之二）。
  static const String excludedTopics = 'excludedTopics';

  /// 全部类别（顺序即界面展示顺序）。
  static const List<String> all = <String>[
    keywords,
    blockedQueryTerms,
    excludedTopics,
  ];

  /// 是否为已知类别（未知类别在读写时被明确拒绝，而不是静默落到某一类）。
  static bool isKnown(String kind) => all.contains(kind);
}

/// 新闻来源配置的读写端口。
abstract interface class NewsSourceConfigStore {
  /// 读必访问网站列表（按用户顺序）。
  Future<Result<List<NewsRequiredSite>>> loadRequiredSites();

  /// 整体替换必访问网站列表（顺序即 [sites] 的顺序）。
  Future<Result<void>> replaceRequiredSites(List<NewsRequiredSite> sites);

  /// 读一个有序字符串列表（类别见 [NewsListCategory]）。
  Future<Result<List<String>>> loadList(String kind);

  /// 整体替换一个有序字符串列表。
  Future<Result<void>> replaceList(String kind, List<String> values);

  /// 读某个语言的 prompt 版本（按版本号倒序）。
  Future<Result<List<NewsPromptVersion>>> loadPromptVersions(String language);

  /// 追加一个新版本（**不覆盖旧版本**）。
  Future<Result<NewsPromptVersion>> savePromptVersion(
    NewsPromptVersion version,
  );

  /// 删除一个版本（用户主动清理）。
  Future<Result<void>> deletePromptVersion({
    required String language,
    required int version,
  });
}
