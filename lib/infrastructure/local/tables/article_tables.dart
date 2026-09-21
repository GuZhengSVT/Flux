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

  /// 所属订阅；**可为空**（schema v5 起）。
  ///
  /// 为什么允许为空：架构 4.1 规定删除订阅时「保留收藏从源中脱离，带来源快照进入
  /// 资料库」。收藏文章必须能在源被删除后继续存在，因此它的 feed_id 会变成 NULL，
  /// 由 [feedTitle] / [feedUrl] 两份快照继续说明「它来自哪里」。
  ///
  /// 仍然**不**用级联删除：删除订阅由用例层显式处理（保留收藏、预览影响范围），
  /// 级联会绕过确认直接清空文章。
  IntColumn get feedId => integer().nullable().references(Feeds, #id)();

  /// 来源快照：删除订阅时冻结的显示名（schema v5）。
  ///
  /// 为什么需要快照而不是「留着 feed_id 在别处查名字」：源那一行在删除后就不存在了，
  /// 而保留下来的收藏文章仍然要显示「来自哪个源」。快照在**删除那一刻**冻结，因此
  /// 之后源被重新添加、改名或再次删除都不会改写这条历史。
  ///
  /// 未脱离源的文章该列为 null（列表仍按 feed_id 现查显示名，改名即时生效）。
  TextColumn get feedTitle => text().nullable()();

  /// 来源快照：删除订阅时冻结的地址（schema v5）。
  ///
  /// 存规范化地址（`Feeds.normalizedUrl`）而不是请求用的原始地址：库里本来就只有
  /// 规范地址这一份——带凭据的原始地址以 credentialRef 引用保存在 Keychain，
  /// 快照不得把它复制进普通列（架构第 8 节）。
  TextColumn get feedUrl => text().nullable()();

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

  /// 卡片图片地址（schema v6）。
  ///
  /// 来源是源内 enclosure 或正文首图，在导入期已通过 isSafeDocUrl 判定，因此这里
  /// 存的一定是 http/https 绝对地址或 null。列表用它画封面（架构第 7 节的三种卡片
  /// 形态），详情页与查看器也从同一列取地址——两处读同一份，不会出现「卡片有图、
  /// 点进去没有」的错位。
  ///
  /// 可空且**不回填**：历史行并没有「这张图的地址」这个事实，用正文里可能存在的
  /// 首图回填需要重新解析全部正文，属 T021 缓存任务的范围。
  TextColumn get imageUrl => text().nullable()();

  /// 本机静态提取得到的正文（schema v8；T024）。
  ///
  /// 为什么与 [body] **分列存储**而不是就地覆盖：架构 4.2 要求主动提取「失败保留原内容」，
  /// 而用户还需要在两份之间**对照**（提取可能截断了正文，或者提取到的其实是另一篇）。
  /// 覆盖式缓存在这两点上都是信息丢失，且不可恢复。
  TextColumn get extractedBody => text().nullable()();

  /// 提取正文的哈希（schema v8）。
  ///
  /// 与 [bodyHash] 同一语义：只判「内容是否变过」。分开存是必需的——两次提取得到同一段
  /// 正文时不该重写大字段，而拿它去和源正文的哈希比较则毫无意义（两者本来就是不同文本）。
  TextColumn get extractedBodyHash => text().nullable()();

  /// 提取时间（schema v8，UTC）。
  ///
  /// 可空：null 表示这篇文章从未提取过。界面据此决定按钮是「获取原站全文」还是「重新获取」。
  DateTimeColumn get extractedAt => dateTime().nullable()();

  /// 提取到的标题（schema v8）。
  ///
  /// 原站标题可能与源内标题不同（源里常有「- 站点名」后缀或旧标题），因此单独一列，
  /// 不覆盖 [title]。
  TextColumn get extractedTitle => text().nullable()();

  /// 提取到的图片地址（schema v8；每行一个，**不下载**）。
  ///
  /// 用换行分隔的文本而不是 JSON：读取方只需要一个列表，而 JSON 会给这一列引入一个
  /// 解析步骤（以及「JSON 坏了怎么办」这个额外分支）。地址本身不含换行符。
  TextColumn get extractedImageUrls => text().nullable()();

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
