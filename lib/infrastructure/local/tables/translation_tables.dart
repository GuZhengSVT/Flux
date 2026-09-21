// 分段全文翻译的持久化（T035；架构 4.2「译文与原文按段落关联，原文始终保留」）。
//
// 为什么单独一张表而不是 articles 上的列：
//   1) 「文章 + 目标语言」是一对多的**复合键**。用户可以在中英两种译文之间切换，
//      塞进 articles 就需要再加一组「英文译文」列，而再加一种语言就要一次迁移；
//   2) 译文与源正文的**失效判据不同**：源正文变了译文即过期（source_digest），把两者
//      放在同一行会让「正文还在不在」与「译文对应哪一版正文」互相纠缠；
//   3) 段落是**有序的多值结构**。落成一列 JSON 会让「按段重试」「按段计数」这类操作
//      只能全量读写，而本任务的核心交互恰恰是段落级的（进度 x/y、只重试失败段）。
//
// 本表**不存源正文**（只存每条段的源文本摘要与源文本）：原文只有 articles.body 一份，
// 「原文始终保留」因此是结构性的，而不是靠调用方记得别覆盖。
library;

import 'package:drift/drift.dart';

import 'article_tables.dart';

/// 一篇文章某个目标语言的整份译文。
///
/// 类名用 ArticleTranslationRecords（表名 article_translation_records）而不是
/// ArticleTranslations：drift 按「去掉末尾 s」派生数据类名，那会生成一个与本工程领域类型
/// 同名的 ArticleTranslation，两处同名会让每个使用点都必须加前缀（与 AiModelRecords 同一个
/// 理由）。
///
/// 索引与查询场景：
///   - ux_translations_article_language：按「文章 + 目标语言」取唯一一份译文（切换
///     原文/译文时按它读）；
///   - 段落按译文取回时走 TranslationSegments 上的复合索引（见下）。
@TableIndex(
  name: 'ux_translations_article_language',
  columns: {#articleId, #targetLanguage},
  unique: true,
)
class ArticleTranslationRecords extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// 所属文章。用 CASCADE：文章被彻底删除时，指向它的译文没有任何保留价值
  /// （引用的材料已经不在了），留着会让「译文列表」出现指向不存在文章的孤儿行。
  IntColumn get articleId =>
      integer().references(Articles, #id, onDelete: KeyAction.cascade)();

  /// 目标语言（SET-011 的 translationTarget；zh-Hans / en）。
  TextColumn get targetLanguage => text()();

  /// 翻译时所依据的源正文摘要（SHA-256 十六进制）。
  ///
  /// 正文变化后这一列与新正文的摘要不再相等，界面据此说明「译文对应的是上一版正文」
  /// 而不是把过期译文当成当前译文展示。
  TextColumn get sourceDigest => text()();

  /// 源正文长度（字符数；界面说明用）。
  IntColumn get sourceLength => integer().withDefault(const Constant(0))();

  /// 产出译文的模型标识（别名/模型ID）；未知为 null。
  TextColumn get modelLabel => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

/// 一段译文（译文的子行）。
///
/// 段落是**一行一段**而不是一个 JSON 数组：进度（x/y 段）、只重试失败段、取消后保留
/// 已完成段这三条交互都是段落级的，逐行存储让它们各自是一次单行写入。
///
/// 类名同样带 Records 后缀（表名 translation_segment_records），理由与上一张表一致。
@TableIndex(
  name: 'ux_translation_segments_translation_index',
  columns: {#translationId, #segmentIndex},
  unique: true,
)
class TranslationSegmentRecords extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// 所属译文。CASCADE：译文被替换/删除时它的段落不再有意义。
  IntColumn get translationId => integer().references(
    ArticleTranslationRecords,
    #id,
    onDelete: KeyAction.cascade,
  )();

  /// 段落顺序号（与切分的顺序一致）。
  IntColumn get segmentIndex => integer()();

  /// 块角色稳定标识（heading / paragraph / listItem，见 TranslationBlockKind.name）。
  TextColumn get blockKind => text()();

  /// 层级：标题级别或列表嵌套深度（段落实 0）。
  IntColumn get level => integer().withDefault(const Constant(0))();

  /// 源文本摘要（段落级缓存键）。
  TextColumn get sourceDigest => text()();

  /// 源文本（保留它：即使正文后来变了，这一段仍能显示当时发给模型的原文）。
  TextColumn get sourceText => text()();

  /// 处理状态稳定标识（pending / translated / failed）。
  TextColumn get status => text()();

  /// 译文；未翻译或失败时为 null。
  TextColumn get translatedText => text().nullable()();

  /// 源文本是否被截断（SET-061 的单段预算）。
  BoolColumn get sourceTruncated =>
      boolean().withDefault(const Constant(false))();

  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}
