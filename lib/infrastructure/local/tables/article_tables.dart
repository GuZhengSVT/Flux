// 文章实体（T009，架构 5.1 的 Article / Revision 与 ArticleState）。
//
// 身份规则（架构 4.1）在本表的落地方式：
//   1) 源内 GUID，**仅在该 Feed 范围内**识别 → 唯一索引限定 (feed_id, guid)；
//   2) 无 GUID 时用规范化链接 → 唯一索引限定 (feed_id, normalized_link)；
//   3) 两者都缺失时用来源/标题/时间指纹兜底 → (feed_id, fallback_fingerprint)，
//      并用 [Articles.fingerprintReliability] 标注可靠度，便于同步阶段避免误合并。
//   正文哈希 [Articles.bodyHash] **只判断修订**，不参与新增身份判定。
//
// 阅读状态（架构 4.1、D-10）：readingState 是单一枚举列，数据库层 CHECK 拒绝
// 未列出的取值；favorite 是独立布尔列。两者在同一行上，“已读且稍后再读”这种
// 双状态在结构上不可能表示。
library;

import 'package:drift/drift.dart';

import 'enums.dart';
import 'feed_tables.dart';

/// 文章及其正文修订（T009 核心表）。
///
/// 索引与查询场景（架构 4.1 身份规则 + F-SEARCH/F-STATE 列表需求）：
/// - `ux_articles_feed_guid`：Feed 内按 GUID 识别（导入去重、刷新匹配）；
///   条件唯一，避免无 GUID 的多行 NULL 互相冲突。
/// - `ux_articles_feed_normalized_link`：无 GUID 时按规范化链接识别同一文章。
/// - `ux_articles_feed_fingerprint`：GUID 与链接都缺失时的兜底识别。
/// - `ix_articles_feed_published`：单订阅/分组的按时间列表（源详情页时间序）。
/// - `ix_articles_reading_state`：未读筛选与三态计数（later 有独立入口）。
/// - `ix_articles_favorite`：收藏列表与「保留收藏」删除预览。
/// - `ix_articles_body_hash`：导入时比对正文是否为新修订。
@TableIndex.sql(
  'CREATE UNIQUE INDEX ux_articles_feed_guid ON articles (feed_id, guid) '
  'WHERE guid IS NOT NULL',
)
@TableIndex.sql(
  'CREATE UNIQUE INDEX ux_articles_feed_normalized_link ON articles '
  '(feed_id, normalized_link) WHERE normalized_link IS NOT NULL',
)
@TableIndex.sql(
  'CREATE UNIQUE INDEX ux_articles_feed_fingerprint ON articles '
  '(feed_id, fallback_fingerprint) WHERE fallback_fingerprint IS NOT NULL',
)
@TableIndex(
  name: 'ix_articles_feed_published',
  columns: {#feedId, #publishedAt},
)
@TableIndex(name: 'ix_articles_reading_state', columns: {#readingState})
@TableIndex(name: 'ix_articles_favorite', columns: {#favorite})
@TableIndex(name: 'ix_articles_body_hash', columns: {#bodyHash})
class Articles extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// 所属订阅。删除订阅由用例层显式处理（保留收藏、预览影响范围），
  /// 因此这里**不**用级联删除，避免绕过确认直接清空文章。
  IntColumn get feedId => integer().references(Feeds, #id)();

  /// 源内 GUID。可能是 null（源未提供）或空串（源提供了空值），
  /// 后者由 [guidPresent] 区分。
  TextColumn get guid => text().nullable()();

  /// GUID 存在性标记：区分“源没给 GUID”与“源给了空/重复 GUID”。
  BoolColumn get guidPresent => boolean().withDefault(const Constant(false))();

  /// 规范化链接：用于身份匹配与去重（仅同 Feed 内唯一）。
  TextColumn get normalizedLink => text().nullable()();

  /// 原始链接，**保留全部查询参数**。规范化结果只用于匹配，不覆盖原文，
  /// 以免外开链接时丢失来源要求的参数（架构 4.1）。
  TextColumn get sourceUrl => text().nullable()();

  /// 无 GUID 兜底指纹（来源 + 标题 + 时间）；null 表示未走兜底规则。
  TextColumn get fallbackFingerprint => text().nullable()();

  /// 兜底指纹可靠度；null 表示该行不是靠指纹识别。发布时间缺失时指纹退化为
  /// 来源 + 标题，被标为 unreliable，同步阶段不得据此静默合并。
  TextColumn get fingerprintReliability =>
      textEnum<FingerprintReliability>().nullable()();

  /// 本行实际采用的识别规则，便于导入诊断与冲突排查。
  TextColumn get identityBasis => textEnum<IdentityBasis>()();

  TextColumn get title => text()();
  TextColumn get author => text().nullable()();

  /// 发布时间（UTC）。为 null 表示源未提供，列表按抓取时间排序并注明。
  DateTimeColumn get publishedAt => dateTime().nullable()();

  /// 抓取时间（UTC）。
  DateTimeColumn get fetchedAt => dateTime().withDefault(currentDateAndTime)();

  /// 正文（已清洗的受控文档来源文本）。
  TextColumn get body => text().nullable()();

  /// 正文完整性四态（架构 4.2）。默认 unknown，由导入流程判定。
  ///
  /// 与 [readingState] 同样的理由把取值域固化进 DDL：四态是本体的一部分，
  /// 非法值若被静默存入，后续渲染与同步都会产生难以追查的错误。
  TextColumn get bodyCompleteness =>
      textEnum<BodyCompleteness>().customConstraint(
        'NOT NULL DEFAULT \'unknown\' '
        'CHECK (body_completeness IN '
        "('sourceBody', 'summaryOnly', 'extracted', 'unknown'))",
      )();

  /// 正文哈希：仅用于判断修订（内容变化才更新正文）。
  TextColumn get bodyHash => text().nullable()();

  TextColumn get summary => text().nullable()();

  /// 单一阅读状态枚举，带数据库 CHECK 约束；默认 unread。
  ///
  /// 这里用 customConstraint 手写 CHECK：枚举取值域必须固化在 DDL 里才能被
  /// 数据库拒绝非法值（drift 的 `.check()` 无法对转换器列稳定地内联字面量）。
  ///
  /// customConstraint 的参数是**列约束片段，不含类型名**（类型仍由 drift 按
  /// 列的 SQL 类型写出），它会整体覆盖 drift 的默认约束，因此 NOT NULL 与
  /// DEFAULT 必须在这里一并写出；约束里的列名用 SQL 名（reading_state）。
  TextColumn get readingState => textEnum<ReadingState>().customConstraint(
    "NOT NULL DEFAULT 'unread' "
    "CHECK (reading_state IN ('unread', 'read', 'later'))",
  )();

  /// 收藏：独立于阅读状态，加精/收藏不改变 read/unread/later（架构 4.1）。
  /// drift 会为布尔列自动附加 CHECK (favorite IN (0, 1))。
  BoolColumn get favorite => boolean().withDefault(const Constant(false))();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}
