// Flux 本地数据库（T009）：实体装配、索引、迁移策略与打开封装。
//
// 职责边界（架构 2.2）：本文件只负责**结构与安全打开**，不含网络、业务规则或
// 同步逻辑。查询/事务方法放在同目录的 store/ 下，presentation/application 通过
// 上层接口访问，不直接 import 本文件。
//
// 表结构权威来源：架构说明书 5.1（实体清单）与 4.1（身份与三态规则）。
library;

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

import 'package:flux/core/core.dart';

import 'tables/article_tables.dart';
import 'tables/ai_tables.dart';
// database.g.dart 是本文件的 part，只能看到本文件的 import；枚举类型被生成的
// 伴随类与表访问器引用，因此必须在这里直接可见。T012 起这些枚举由
// package:flux/core/core.dart 的 domain 转出口提供（见 tables/enums.dart 的说明）。
import 'tables/feed_tables.dart';
import 'tables/deletion_tables.dart';
import 'tables/reading_tables.dart';
import 'tables/settings_tables.dart';
import 'tables/news_tables.dart';
import 'tables/summary_tables.dart';
import 'tables/translation_tables.dart';

part 'database.g.dart';

/// 应用数据库。
///
/// schema 版本从 1 开始；每次结构变化都必须：
///   1) 提升 [schemaVersion]；
///   2) 在 [migration] 的 `onUpgrade` 里补上**增量**步骤（不允许只改建表语句就当
///      升级完成——旧设备不会重跑 onCreate）；
///   3) 用 `drift_schemas/` 里导出的历史快照补充迁移测试。
@DriftDatabase(
  tables: <Type>[
    Groups,
    Feeds,
    Articles,
    DeletionEvents,
    ReadingSessions,
    SummaryVersions,
    Citations,
    Settings,
    AiModelRecords,
    AiTasks,
    AiResultCacheRecords,
    SearchServiceRecords,
    ArticleTranslationRecords,
    TranslationSegmentRecords,
    NewsRequiredSiteRecords,
    NewsConfigEntryRecords,
    NewsPromptVersionRecords,
  ],
  // T022 的全文检索索引放在 .drift 文件里：FTS5 是虚拟表，建表语句必须带
  // USING fts5(...) 与 tokenizer 参数，Dart 表 DSL 表达不了（见该文件顶部说明）。
  // include 让这些对象成为 **drift 知道的** schema 的一部分，因此：
  //   - onCreate/createAll 会一并建出（新库不需要额外步骤）；
  //   - 迁移校验会比较它们（不会出现「代码建的索引与快照不一致」这类静默漂移）；
  //   - drift_schemas 快照会记录它们，后续迁移测试能验证。
  include: <String>{'tables/article_search.drift'},
)
class AppDatabase extends _$AppDatabase {
  /// 用外部提供的执行器构造（测试注入内存库、生产注入文件库）。
  AppDatabase(super.executor);

  /// 打开（或创建）[file] 指向的数据库文件。
  ///
  /// 只在此处拼装原生执行器；具体数据目录由应用装配层决定（T011），
  /// 本层不依赖 `path_provider`，以免测试被迫引入平台通道。
  factory AppDatabase.openFile(File file) => AppDatabase(NativeDatabase(file));

  /// 内存数据库：单元测试与预览使用，不落盘。
  factory AppDatabase.memory() => AppDatabase(NativeDatabase.memory());

  /// 保留组“未分类”的稳定标识（架构 4.1）。
  ///
  /// 用固定 syncId 而不是固定自增 id：自增 id 在跨设备/导入导出后不保证一致，
  /// 而“未分类”必须能被稳定识别。
  static const String uncategorizedGroupSyncId = 'group.uncategorized';

  /// 保留组显示名（首次启动种子数据；用户可改名，识别依据是 syncId）。
  static const String uncategorizedGroupName = '未分类';

  @override
  int get schemaVersion => 14;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) async {
      await m.createAll();
      await _seedInitialData();
    },
    onUpgrade: (Migrator m, int from, int to) async {
      // 降级（库比代码新）必须显式失败，绝不用删库重建“修复”。
      // 用户可能用旧版本打开了新版本写过的库；此时原始文件必须保持可回退，
      // 因此这里只报错、不执行任何 DDL（drift 也不会在迁移失败时删除文件）。
      if (from > to) {
        throw StorageError(
          operation: 'openDatabase',
          detail:
              'database schema v$from is newer than supported v$to; '
              'refusing to open (file left untouched, no rebuild)',
        );
      }

      // 增量迁移：按 from 逐步补齐到 to。每一步只做「新增」，不改写已有列的语义，
      // 这样旧数据在升级后保持原样，失败时也容易判断中断在哪一步。
      //
      // 为什么坚持增量而不是“删表重建”：用户的历史文章、阅读状态与收藏都在库里，
      // 重建等于静默丢数据；架构 5.3 明确要求迁移不得消费用户数据。
      if (from < 2) {
        // v1 → v2：新增 settings 表（SET 注册表的持久化）。
        // 不需要回填历史数据：v1 里没有设置表，默认值由注册表在使用时提供。
        //
        // 注意：createTable 只建表，**不会**顺带创建该表的索引（索引是独立的
        // schema 实体）。漏掉 createIndex 时 run-time 查询照常工作，只有结构
        // 校验才会发现差异——T010 的迁移测试正是这样抓到过一次，所以这一步
        // 必须显式写出来。
        await m.createTable(settings);
        await m.createIndex(ixSettingsUpdatedAt);
      }

      if (from < 3) {
        // v2 → v3：订阅表补抓取诊断列（T013 的 lastChecked / 结果类别 / 错误类别）。
        //
        // 三列都可空且**不回填**：历史行没有「上次检查时间」这个事实，用当前时间
        // 填进去等于伪造一次成功的检查记录。界面按 null 显示「尚未检查」——这是
        // 真实状态，而不是缺失。
        //
        // addColumn 只加列，不改写已有列语义，因此旧数据（名称/分组/加精/条件请求
        // 缓存）保持原样。
        await m.addColumn(feeds, feeds.lastCheckedAt);
        await m.addColumn(feeds, feeds.lastRefreshResult);
        await m.addColumn(feeds, feeds.lastRefreshErrorKind);
      }

      if (from < 4) {
        // v3 → v4：订阅表补「启用」列（T014，SET-022 的逐源启用开关）。
        //
        // 只加列并保留默认值 true：**升级前就存在的订阅必须继续刷新**。若默认值
        // 取 false，用户升级后会静默失去所有订阅的自动刷新，而且界面上只是「关」
        // 而已，没有任何线索指向这次迁移——那正是架构 5.3 禁止的「迁移消费用户数据」。
        //
        // 布尔列自带 CHECK (enabled IN (0, 1))：这是 drift 对布尔列的既有处理
        // （与 favorite 一致），不是本任务额外加的约束；addColumn 连带写出。
        await m.addColumn(feeds, feeds.enabled);
      }

      if (from < 5) {
        // v4 → v5：文章表支持「收藏脱离源」（T018）。
        //
        // 两件事，缺一不可：
        //
        //   1) **feed_id 改为可空**。架构 4.1 要求删除订阅时保留的收藏「从源中
        //      脱离，带来源快照进入资料库」，因此这些行的 feed_id 必须能变成 NULL。
        //      sqlite 改不了单列的 NOT NULL，只能用 drift 的 alterTable（它执行
        //      sqlite 官方推荐的 12 步重建流程：建临时表→搬数据→删旧表→改名→
        //      重建索引）。**不用**「先 DROP TABLE 再 CREATE」的做法：那会丢掉全部
        //      历史文章与阅读状态（架构 5.3 禁止迁移消费用户数据）。
        //      搬数据靠 columnTransformer——这里刻意一个都不写：不写的列按同名列
        //      原样复制，因此 id / guid / 正文 / readingState / favorite 全部原值
        //      保留，只有新列取默认值。
        //
        //   2) 新增两列来源快照（feed_title / feed_url）与一张删除事件表。
        //      快照列可空且**不回填**：历史行并没有「源已被删除」这个事实，给它们
        //      填上当前源名等于伪造一份快照，还会让 T047 的清理预览把没脱离源的文章
        //      也算成「已脱离」。
        await m.alterTable(
          TableMigration(
            articles,
            newColumns: <GeneratedColumn<Object>>[
              articles.feedTitle,
              articles.feedUrl,
              // imageUrl 是 v6 才出现的新列，但**必须**在这里一起声明：
              // alterTable 的搬数据语句是按**当前**表定义生成列清单的——它会遍历
              // articles 的全部列并逐列 SELECT。若这里不声明，这一步就会对还不存在
              // 这一列的旧库执行一次带 image_url 的 SELECT，直接把 v4→v5 的升级打崩
              // （实测报 "no such column: image_url"）。声明为 newColumn 之后，它在
              // v5 阶段被跳过（取默认值 null），随后由下面的 v6 步骤补上。
              articles.imageUrl,
              // v8 的五个提取列同理：它们也在**当前**表定义里，因此这次按当前定义生成的
              // 搬数据语句会带上它们。不在这里声明，v4 及更早的库升到 v5 时就会对着还不
              // 存在的 extracted_* 列执行 SELECT，直接把升级打崩（实测报 no such column:
              // extracted_body）。声明为 newColumn 之后它们在 v5 阶段取默认值 null，
              // 随后由 v8 步骤按事实判断是否需要真正加上。
              articles.extractedBody,
              articles.extractedBodyHash,
              articles.extractedAt,
              articles.extractedTitle,
              articles.extractedImageUrls,
              // v12 的 AI 摘要三列同理（T034）：它们也在当前表定义里，v5 阶段取 null，
              // 由 v12 步骤按事实判断是否真的加上。
              articles.aiSummary,
              articles.aiSummaryAt,
              articles.aiSummaryModel,
              // v14 的 feeds.news_enabled 同理（T036）：它也在当前表定义里，v5 阶段取 null，
              // 由 v14 步骤按事实判断是否真的加上。
              feeds.newsEnabled,
            ],
          ),
        );
        await m.createTable(deletionEvents);
        await m.createIndex(ixDeletionEventsSyncId);
        await m.createIndex(ixDeletionEventsDeletedAt);
      }

      if (from < 6) {
        // v5 → v6：文章表补卡片图片地址（T019+ 的三种卡片形态）。
        //
        // 只加一条可空列，**不回填**：历史行并没有「这张图的地址」这个事实。用正文
        // 里可能存在的首图回填需要把全部正文重新解析一遍（那是 T021 媒体任务的
        // 范围），而在这条迁移里做这件事会让一次升级变成一次全库解析。
        //
        // 默认 null 的直接后果是：升级后旧文章的卡片回到「缺图不占位」的形态
        // （架构第 7 节），而**不是**显示一个空图框——缺失与空是两件事。
        //
        // 为什么要先判存在：上面 v4→v5 那一步的 alterTable 是**按当前表定义**重建
        // articles 的（drift 的 12 步重建流程会逐列生成搬数据语句），因此当一次
        // 升级直接从 v4 及更早走到 v6 时，重建出来的表**已经带上** image_url——
        // 再执行一次 ADD COLUMN 会报 duplicate column name（v1 快照升级的用例就是
        // 这么炸的）。对**已经在 v5** 的库则反过来：它的 articles 是按 v5 快照建的，
        // 没有这一列，必须真的加上。
        //
        // 两种情形都要能升上来，所以这里按事实判断，而不是按 from 猜。
        if (!await _columnExists('articles', 'image_url')) {
          await m.addColumn(articles, articles.imageUrl);
        }
      }

      if (from < 7) {
        // v6 → v7：新增全文检索索引（T022；架构 4.2 的 F-SEARCH）。
        //
        // 这一步做三件事，顺序有意义：
        //   1) 建 FTS5 虚拟表（external content 模式，不复制正文）；
        //   2) 建同步触发器（插入/删除/更新文章、订阅改名）；
        //   3) **重建索引**，把已有文章灌进倒排表。
        //
        // 第 3 步不能省：触发器只对**此后**的写入生效，升级前库里已有的文章不会自己
        // 出现在索引里——漏掉它，用户升级后搜自己的历史文章会是零结果，而界面上完全
        // 没有线索指向这次迁移。
        //
        // 为什么用 customStatement 而不是 m.createAll 或 m.createTable：include 里的
        // 对象（虚拟表与触发器）已经进入 drift 的 schema，但 m.createAll 会连带建全部
        // 表与索引（对已存在的表执行 CREATE TABLE IF NOT EXISTS 虽然安全，却把「这一步
        // 只新增检索对象」这件事模糊掉了）。这里逐条创建，来源与顺序都写在眼前。
        // 逐条建出「检索相关的 schema 对象」。之所以不 m.createAll()：那会连带建全部
        // 表与索引（对已存在的对象虽安全，却把「本步只新增检索对象」这件事模糊掉）。
        // 这里显式列出四个对象，来源与顺序都在眼前。
        await m.create(articlesFts);
        await m.create(articlesFtsAi);
        await m.create(articlesFtsAd);
        await m.create(articlesFtsAu);
        // 全量重建索引。用 fts5 内置的 'rebuild' 命令而不是逐行 INSERT：rebuild 直接
        // 从 content 表（articles）重新扫描，速度最快，也不需要在这里重复 COALESCE
        // 的取名字规则——那套规则已经在触发器里写过一遍。
        await customStatement(
          "INSERT INTO articles_fts(articles_fts) VALUES('rebuild')",
        );
      }

      if (from < 8) {
        // v7 → v8：文章表补「本机静态提取正文」（T024 的主动获取原站全文）。
        //
        // 五列全部可空且**不回填**：历史行并没有「提取过正文」这个事实。用现有正文
        // 回填会让界面显示「已提取」，而用户从未点过那个按钮——那正是架构第 8 节禁止的
        // 「用假象代替状态」。
        //
        // 为什么提取正文与源正文**分列**而不是覆盖 body：架构 4.2 要求失败保留原内容，
        // 且用户需要在两份之间对照。覆盖式缓存同时丢掉这两条。
        //
        // 为什么要先判存在：上面 v4→v5 那一步的 alterTable 是**按当前表定义**重建 articles
        // 的，因此当一次升级直接从 v4 及更早走到 v8 时，重建出来的表**已经带上**这五列——
        // 再执行一次 ADD COLUMN 会报 duplicate column name（与 v6 的 image_url 完全同一个
        // 坑，v1 快照升级的用例已经抓到过）。对**已经在 v7** 的库则反过来：它的 articles 是按
        // v7 快照建的，没有这些列，必须真的加上。
        if (!await _columnExists('articles', 'extracted_body')) {
          await m.addColumn(articles, articles.extractedBody);
          await m.addColumn(articles, articles.extractedBodyHash);
          await m.addColumn(articles, articles.extractedAt);
          await m.addColumn(articles, articles.extractedTitle);
          await m.addColumn(articles, articles.extractedImageUrls);
        }
      }

      if (from < 9) {
        // v8 → v9：AI 模型表（T025，架构 5.1 的 AIProvider / Model 实体）。
        //
        // 这一步**没有任何凭据列**：SET-031 是秘密项，只住在 Keychain 里，因此
        // 明文备份（架构 5.3）与 flux.sqlite 都不会携带 API Key。这一点是结构性的，
        // 而不是靠「记得不要把 Key 写进去」。
        //
        // 不回填任何数据：升级前不存在「已经配好的 AI 模型」这个事实，空表是诚实的
        // 默认状态（与 v2→v3 的抓取诊断列同一口径：不用看起来合理的值伪造事实）。
        //
        // 与 v1→v2 同一个坑：createTable 只建表，**不**建索引。索引是独立 schema
        // 实体，漏掉 createIndex 时运行时查询照常工作，只有结构校验才会发现差异
        // （T010 的迁移测试曾这样抓到过一次）。
        await m.createTable(aiModelRecords);
        await m.createIndex(uxAiModelsAlias);
        await m.createIndex(ixAiModelsSort);
      }

      if (from < 10) {
        // v9 → v10：AI 任务的持久记录与结果缓存（T030；架构 5.1 的
        // AITask / Attempt / Result，架构 4.5 的缓存键）。
        //
        // 这一步**不回填任何数据**：升级前不存在「已经跑过的 AI 任务」这个事实，
        // 空表是诚实的默认状态。特别地，不用「把当前时间填进 createdAt」制造
        // 一批看起来跑过的历史任务——那会让任务列表在升级后凭空多出记录。
        //
        // 两张表都是**新增**，不改写任何已有列：
        //   - ai_tasks 记录任务本身（状态九态、deadline、累计消耗、结果与错误类别）；
        //   - ai_result_cache_entries 只存成功产出，键是全部缓存组成项的摘要。
        //
        // 与 v1→v2、v8→v9 同一个坑：createTable 只建表，**不**建索引。索引是独立的
        // schema 实体，漏掉 createIndex 时运行时查询照常工作，只有结构校验才会发现
        // 差异（T010 的迁移测试曾这样抓到过一次），因此这里逐个显式写出。
        await m.createTable(aiTasks);
        await m.createIndex(ixAiTasksCreated);
        await m.createIndex(ixAiTasksStatus);
        await m.createTable(aiResultCacheRecords);
        await m.createIndex(ixAiResultCacheCreated);
      }

      if (from < 11) {
        // v10 → v11：搜索服务记录表（T031，架构 5.1 的 SearchConfig 实体）。
        //
        // 这一步**没有任何凭据列**：SET-039 是秘密项，只住在 Keychain 里，因此
        // 明文备份（架构 5.3）与 flux.sqlite 都不会携带搜索服务的 Key。这一点是
        // 结构性的，而不是靠「记得不要把 Key 写进去」。
        //
        // 不回填任何数据：升级前不存在「已经配好的搜索服务」这个事实，空表是诚实的
        // 默认状态（与 v8→v9 的模型表、v9→v10 的任务表同一口径）。
        //
        // 与 v1→v2、v8→v9、v9→v10 同一个坑：createTable 只建表，**不**建索引。
        // 索引是独立 schema 实体，漏掉 createIndex 时运行时查询照常工作，只有结构
        // 校验才会发现差异（T010 的迁移测试曾这样抓到过一次），因此逐个显式写出。
        await m.createTable(searchServiceRecords);
        await m.createIndex(uxSearchServiceLabel);
        await m.createIndex(ixSearchServiceSort);
      }

      if (from < 12) {
        // v11 → v12：文章表补 AI 摘要三列（T034；架构 4.2「AI 摘要与源摘要独立」）。
        //
        // 三列全部可空且**不回填**：历史行并没有「生成过 AI 摘要」这个事实。用源摘要
        // 回填会让界面显示「AI 摘要」，而用户从未点过那个按钮——那正是架构第 8 节禁止的
        // 「用假象代替状态」。
        //
        // 为什么分列而不是覆盖 summary：源摘要与 AI 摘要**来源不同**（一个是订阅内容，
        // 一个是模型生成），覆盖式存储会让「这句话是谁说的」在数据上不可分辨，也让用户
        // 无法在不信任 AI 摘要时退回源摘要。
        //
        // 为什么要先判存在：上面 v4→v5 那一步的 alterTable 是**按当前表定义**重建 articles
        // 的（drift 的 12 步重建流程会逐列生成搬数据语句），因此当一次升级直接从 v4 及更早
        // 走到 v12 时，重建出来的表**已经带上**这三列——再执行一次 ADD COLUMN 会报
        // duplicate column name（v1 快照升级的用例已经抓到过同一个坑两次）。
        if (!await _columnExists('articles', 'ai_summary')) {
          await m.addColumn(articles, articles.aiSummary);
          await m.addColumn(articles, articles.aiSummaryAt);
          await m.addColumn(articles, articles.aiSummaryModel);
        }
      }

      if (from < 13) {
        // v12 → v13：分段全文翻译的两张表（T035；架构 4.2「译文与原文按段落关联，
        // 原文始终保留」）。
        //
        // **不新增任何 articles 列**：原文只有 articles.body 一份，译文另有归属
        // （article_translations + translation_segments），因此「原文始终保留」在这
        // 一步之后依然是结构性的——没有第二条写入路径会碰源正文。
        //
        // 不回填任何数据：升级前不存在「翻译过这篇文章」这个事实，空表是诚实的默认
        // 状态（与 v8→v9 的模型表、v9→v10 的任务表、v10→v11 的搜索服务表同一口径）。
        //
        // 与 v1→v2、v8→v9、v9→v10、v10→v11 同一个坑：createTable 只建表，**不**建
        // 索引。索引是独立 schema 实体，漏掉 createIndex 时运行时查询照常工作，只有
        // 结构校验才会发现差异，因此逐个显式写出。
        await m.createTable(articleTranslationRecords);
        await m.createIndex(uxTranslationsArticleLanguage);
        await m.createTable(translationSegmentRecords);
        await m.createIndex(uxTranslationSegmentsTranslationIndex);
      }

      if (from < 14) {
        // v13 → v14：新闻来源配置与版本化 prompt（T036；SET-050–055、架构 4.4）。
        //
        // 三张新表 + 订阅表的一个可空列：
        //   * news_required_sites（SET-051 必访问网站）；
        //   * news_config_entries（SET-052 关键词、SET-053 两个独立列表，用 kind 区分）；
        //   * news_prompt_versions（SET-055 的版本历史）；
        //   * feeds.news_enabled（SET-050 的逐源开关，**可空**：null = 跟随 enabled）。
        //
        // 新列**可空且不回填**：升级前不存在「用户为这个源做过新闻选择」这个事实，回填成
        // true 会让「从未选择过」与「显式选了参与」在数据上不可分辨（架构第 8 节禁止用假象
        // 代替状态）。行为上不回填同样安全：SET-050 的口径本就是「已启用订阅默认开」，
        // 而 null 在读取侧（newsIncludesFeed）正是这个含义。
        //
        // 与 v1→v2、v8→v9、v9→v10、v10→v11、v12→v13 同一个坑：createTable 只建表，**不**建
        // 索引；漏掉 createIndex 时运行时查询照常工作，只有结构校验才会发现差异。
        await m.createTable(newsRequiredSiteRecords);
        await m.createIndex(ixNewsRequiredSitesOrder);
        await m.createTable(newsConfigEntryRecords);
        await m.createIndex(uxNewsConfigEntriesKindOrder);
        await m.createTable(newsPromptVersionRecords);
        await m.createIndex(uxNewsPromptVersionsLanguageVersion);
        // 与 v6/v8/v12 同一个坑：v4→v5 的 alterTable 是按**当前**表定义重建 feeds 的，
        // 因此这一列也必须出现在那一步的 newColumns 里（见上方 v5 步骤），这里按事实判断
        // 是否真的需要加上。
        if (!await _columnExists('feeds', 'news_enabled')) {
          await m.addColumn(feeds, feeds.newsEnabled);
        }
      }

      // 未知区间兜底：如果代码要求的 to 超出这里已实现的步骤，必须失败而不是
      // 静默放过——放过会让“代码以为是 vN、库其实是 vM”的错配在运行期才爆发。
      // 必须与 schemaVersion 同步：每加一步迁移就把它改到新版本，否则一次
      // 「代码升到 vN 但忘了写步骤」的改动会被这条兜底挡住（而不是静默放过）。
      const int highestImplemented = 14;
      if (to > highestImplemented) {
        throw StorageError(
          operation: 'openDatabase',
          detail:
              'no migration step implemented for schema v$from -> v$to; '
              'refusing to continue (file left untouched, no rebuild)',
        );
      }
    },
    beforeOpen: (OpeningDetails details) async {
      // 外键约束默认关闭；本工程的引用（文章→订阅、会话/引用→文章）依赖它生效。
      // 放在 beforeOpen 而不是连接字符串里，保证所有打开的连接一致。
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  /// 建库种子数据：保留组“未分类”。
  ///
  /// 与业务无关，只保证“未分类”在任何库里都存在且可识别；删除保护属于用例层
  /// 规则（T014）：`isReserved` 为真时仅允许移动其中订阅，不允许删除本组。
  Future<void> _seedInitialData() async {
    await into(groups).insert(
      GroupsCompanion.insert(
        syncId: uncategorizedGroupSyncId,
        name: uncategorizedGroupName,
        isReserved: const Value<bool>(true),
      ),
      mode: InsertMode.insertOrIgnore,
    );
  }

  /// 表 [table] 上是否已有列 [column]。
  ///
  /// 迁移步骤需要它，而不是靠版本号推断：drift 的 `alterTable` 重建是按**当前**
  /// 表定义生成语句的，因此「同一条迁移链」在不同起点下到达某一步时的实际结构可能
  /// 已经包含了更晚版本才声明的列（见 v6 步骤的说明）。用 PRAGMA 问库，是唯一能
  /// 区分这两种情形的做法。
  Future<bool> _columnExists(String table, String column) async {
    final List<QueryRow> rows = await customSelect('PRAGMA table_info($table)')
        .get();
    return rows.any((QueryRow row) => row.read<String>('name') == column);
  }
}

/// 以 [Result] 包装的打开操作，供上层在不处理底层异常的情况下分支。
///
/// 打开失败（版本过新、文件损坏、迁移中断）都翻译成 [StorageError]；
/// 编程错误（例如断言）仍会抛出，不被吞掉。
Future<Result<AppDatabase>> openAppDatabase(File file) async {
  AppDatabase? db;
  try {
    db = AppDatabase.openFile(file);
    // 触发一次真实查询，让迁移在这里发生，而不是在第一次业务查询时。
    await db.customStatement('PRAGMA user_version');
    return Ok<AppDatabase>(db);
  } on AppError catch (error, stackTrace) {
    await _closeQuietly(db);
    return Err<AppDatabase>(
      StorageError(
        operation: 'openDatabase',
        detail: error.message,
        cause: error,
        stackTrace: stackTrace,
      ),
    );
  } on Exception catch (error, stackTrace) {
    // sqlite3/drift 自身抛出的异常统一收敛为类型化错误。
    // 只保留异常类型与简短说明，不把可能含路径/内容的原始文本整段透出。
    await _closeQuietly(db);
    return Err<AppDatabase>(
      StorageError(
        operation: 'openDatabase',
        detail: error.runtimeType.toString(),
        cause: error,
        stackTrace: stackTrace,
      ),
    );
  }
}

/// 打开失败时释放底层数据库句柄，避免调用方必须自己关一个“没打开成功”的对象。
///
/// 关闭本身失败不再向上抛：真正的失败原因（版本过新/损坏）更重要，不能被清理
/// 时的次生错误覆盖；此处只保证不把异常泄漏成未处理错误。
Future<void> _closeQuietly(AppDatabase? db) async {
  if (db == null) {
    return;
  }
  try {
    await db.close();
  } on Exception {
    // 忽略：见上方说明。
  }
}
