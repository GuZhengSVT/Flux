// 新闻来源配置与版本化 prompt（T036；SET-050–055、架构 4.4）。
//
// 三张表各自回答一个问题：
//   * news_required_sites：必访问网站列表（SET-051，「增删改排序」）；
//   * news_config_entries：**有序字符串列表**（SET-052 关键词、SET-053 的两个独立列表）。
//     用一张表 + 类别列承载三个列表，而不是三张表：它们的形状完全相同（有序字符串），
//     三张表会让「排序/去重/增删」的逻辑写三遍，而各自的索引也毫无差别；
//   * news_prompt_versions：总 prompt 的版本历史（SET-055「每次保存新版本，可回退」）。
//
// **逐源新闻开关不进这里**：它属于订阅表（feeds.news_enabled，schema v14），因为它是一条
// 「这个源」的属性，而不是一条独立配置；放在独立表里会让「源被删除时它的新闻开关怎么办」
// 变成一个需要额外规则的空问题。
library;

import 'package:drift/drift.dart';

/// 必访问网站（SET-051）。
///
/// 索引与查询场景：ix_news_required_sites_order 按用户排序取列表（界面展示、组合 prompt 与
/// T037 的逐站执行都按同一顺序）。
///
/// 类名带 Records 后缀（表名 news_required_site_records）：drift 按「去掉末尾 s」派生数据类名，
/// NewsRequiredSites 会生成一个与领域类型同名的 NewsRequiredSite，两处同名会让每个使用点都必须加
/// 前缀（与 AiModelRecords / ArticleTranslationRecords 同一个理由）。
@TableIndex(name: 'ix_news_required_sites_order', columns: {#sortOrder})
class NewsRequiredSiteRecords extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// 显示名（用户可改；组合 prompt 时用它标识站点）。
  TextColumn get name => text()();

  /// 站点地址。
  TextColumn get url => text()();

  /// 是否启用（停用的站点不进 prompt，也不参与逐站执行）。
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();

  /// 顺序权重（升序）。
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

/// 有序字符串条目（SET-052/053）。
///
/// 唯一索引 (kind, sort_order)：同一类别里两个条目抢同一个顺序是**结构性**冲突，让数据库
/// 拒绝比让界面显示一个顺序不确定的列表更可靠。
///
/// 类名带 Records 后缀（表名 news_config_entry_records），理由同上。
@TableIndex(
  name: 'ux_news_config_entries_kind_order',
  columns: {#kind, #sortOrder},
  unique: true,
)
class NewsConfigEntryRecords extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// 列表类别（取值见 core 的 NewsListCategory；这里存稳定字符串而不是序号——序号会在
  /// 中间插一项之后整体错位，把关键词列表变成主题排除列表）。
  TextColumn get kind => text()();

  /// 条目文本。
  TextColumn get value => text()();

  /// 顺序权重（升序）。
  IntColumn get sortOrder => integer()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

/// 总 prompt 的一个版本（SET-055）。
///
/// 每次保存**新增一行**而不是更新：prompt 是那种「改坏了当天才发现」的配置，覆盖会让上一版
/// 无法回退。唯一索引 (language, version) 保证同一语言里版本号不重复。
///
/// 类名带 Records 后缀（表名 news_prompt_version_records），理由同上。
@TableIndex(
  name: 'ux_news_prompt_versions_language_version',
  columns: {#language, #version},
  unique: true,
)
class NewsPromptVersionRecords extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// 生成语言（中英两套模板各自版本化，互不覆盖）。
  TextColumn get language => text()();

  /// 版本号（从 1 开始，单调递增）。
  IntColumn get version => integer()();

  /// 模式稳定标识（composed / advancedOverride）。
  TextColumn get mode => text()();

  /// 任务说明（用户可改部分）。
  TextColumn get taskInstruction => text()();

  /// 输出规范（用户可改部分，**不含协议段**——协议由组合时附加，不落库）。
  TextColumn get outputSpec => text()();

  /// 高级覆盖模式下的总 prompt（组合模式下为空串）。
  TextColumn get advancedPrompt => text()();

  /// 可选备注。
  TextColumn get note => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}
