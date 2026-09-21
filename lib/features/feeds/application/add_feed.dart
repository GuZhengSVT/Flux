// 「添加订阅」用例（T014；架构 4.1、SET-022）。
//
// 两步式流程，刻意**分开**成两个方法而不是一个 doItAll：
//   1) [AddFeedUseCase.preview]：只抓取 + 解析，产出可核对的预览（标题、文章数、
//      规范化地址），**不写任何数据**；
//   2) [AddFeedUseCase.confirm]：用预览的结果入库，**不再联网**。
//
// 为什么必须分开（这不是为了界面好看）：
//   - 用户需要先看到「这个地址解析出了什么」再决定是否订阅。一个直接写入的实现
//     会把「地址填错了但解析成功」变成「库里多了一条垃圾订阅」；
//   - 若确认时再抓一次，则预览成功后断网会让用户看到自己刚预览过的源「添加失败」，
//     而且源的 ETag 在这两次请求之间可能已经变化，预览与入库的内容不再一致。
//
// 重复添加（同一规范化 URL）**返回已有源并保留其全部状态**：架构 4.1 要求
// 「重复导入按规范地址匹配已有订阅，不重置其状态」，因此这里既不改名、不改分组，
// 也不覆盖加精/刷新间隔/条件请求缓存，更不会把已有文章重置。
library;

import 'package:flux/core/core.dart';

import '../domain/article_identity.dart';
import '../domain/feed_import_builder.dart';
import '../domain/feed_parser.dart';

/// 预览结果：抓取 + 解析的产物，尚未写入任何数据。
class FeedPreview {
  /// 构造「已抓取」的预览（正常路径）。
  ///
  /// 抓取字段（[document] / [parsed] / [format]）在此构造里是必填的，因此
  /// 「一次成功的预览必然带着它的内容」在类型上成立，而不是靠约定。
  const FeedPreview.fetched({
    required this.requestedUrl,
    required this.normalizedUrl,
    required this.finalUrl,
    required this.title,
    required this.entryCount,
    required this.rejectedEntries,
    required this.document,
    required this.parsed,
    required this.format,
    this.siteUrl,
  }) : duplicateOf = null;

  /// 构造「已订阅」的预览（重复添加）。
  ///
  /// 刻意**不带**抓取字段：这条路径上根本没有发生网络请求。用一个构造器加上
  /// 可空字段会让「重复时也有内容」看起来可行，从而诱导调用方去读一份空文档。
  const FeedPreview.duplicate({
    required this.requestedUrl,
    required this.normalizedUrl,
    required this.finalUrl,
    required this.title,
    required this.duplicateOf,
  }) : entryCount = 0,
       rejectedEntries = 0,
       document = null,
       parsed = null,
       format = null,
       siteUrl = null;

  /// 用户输入的地址（原样保留，便于界面回显）。
  final String requestedUrl;

  /// 规范化后的地址（匹配与去重的依据）。
  final String normalizedUrl;

  /// 跟随重定向后的最终地址（诊断用）。
  final String finalUrl;

  /// 预览标题：优先源自带标题，其次站点地址，最后规范化地址。
  ///
  /// 绝不返回空串：界面上的「名称」字段需要一个**可编辑且非空**的初值，
  /// 留空会让用户以为必须自己从零写一个名字。
  final String title;

  /// 解析出的条目数。
  final int entryCount;

  /// 因缺少最小必需字段被跳过的条目数。
  final int rejectedEntries;

  /// 预览阶段那次请求拿到的响应体原文；重复订阅时为 null（没有抓取）。
  ///
  /// 由预览对象持有，而不是让调用方各拿一份：确认步骤要写的就是**这一批**内容，
  /// 把一个字符串在两层之间手工传递，迟早出现「预览 A、确认 B」的错配，而错配的
  /// 后果是订阅了用户没看过的内容。
  final String? document;

  /// 预览阶段解析出的条目集合（与 [document] 同一次抓取的产物）；未抓取时为 null。
  final ParsedFeed? parsed;

  /// 源格式（RSS 2.0/1.0 或 Atom）；重复订阅时为 null（此时没有抓取）。
  final FeedFormat? format;

  /// 站点地址（源声明的主页）。
  final String? siteUrl;

  /// 已存在的订阅（重复添加时非空）。
  ///
  /// 这里保留完整的已有记录，让界面能显示「该地址已订阅（名称）」并让调用方
  /// 决定是跳到已有源还是保持不动——而不是给一个布尔值让每个调用点自己再查一次。
  final FeedRecord? duplicateOf;

  /// 是否为重复订阅。
  bool get isDuplicate => duplicateOf != null;
}

/// 添加订阅的结果。
class AddFeedOutcome {
  /// 构造结果。
  const AddFeedOutcome({
    required this.feed,
    required this.isDuplicate,
    required this.imported,
    this.finalUrl,
  });

  /// 落库后的订阅记录（重复添加时为**已有**记录）。
  final FeedRecord feed;

  /// 是否为重复添加（未新建行、未重置状态）。
  final bool isDuplicate;

  /// 文章导入计数；重复添加时为 null（**不写文章**）。
  ///
  /// 重复添加不导入文章的理由：该源的文章本就在库里，再次导入只会触发「全部
  /// unchanged」的空事务，却会让界面显示「新增 0 篇」；更严重的是若源在两次添加
  /// 之间改了内容，第二次导入会**改写**已有文章，而用户这次动作只是「添加一个
  /// 已经有订阅」。真正的刷新有它自己的入口。
  final ArticleImportOutcome? imported;

  /// 最终地址。
  final String? finalUrl;
}

/// 添加失败在界面上要说明的类别。
///
/// 为什么不直接用 [AppError] 的子类型当界面分支：错误层级里还有一批与「添加订阅」
/// 无关的类别（预算、状态迁移、提供商…），让界面穷尽匹配整个 sealed 层级会逼迫它
/// 为不可能出现的分支写文案。这里把「用户需要看到的不同处理」收敛成四项，
/// 真实类别仍由 [AppError.kind] 携带给诊断日志。
enum AddFeedFailureReason {
  /// 地址不合法（空、非 http(s)、无法解析）。
  invalidUrl,

  /// 网络失败：可稍后重试，且应当提示用户检查网络。
  network,

  /// 内容不是可解析的 RSS/Atom（含被拒绝的 DTD/外部实体）：重试无意义。
  parse,

  /// 本地存储失败：本次改动没保存。
  storage;

  /// 把一个类型化错误归类。
  ///
  /// 对未覆盖的类别取 [network] 这一最中性的说法，而不是硬塞进 [storage]
  /// ——后者会让界面说「没保存」，而实际可能什么都没做。真实类别留给诊断日志。
  static AddFeedFailureReason classify(AppError error) => switch (error) {
    ValidationError() => invalidUrl,
    NetworkError() || DeadlineExceededError() => network,
    ParseError() => parse,
    StorageError() => storage,
    _ => network,
  };
}

/// 添加订阅用例。
class AddFeedUseCase {
  /// 构造用例。
  const AddFeedUseCase({
    required this.fetcher,
    required this.catalog,
    required this.articles,
    this.diagnostics = const NoopDiagnosticSink(),
    this.clock = const SystemClock(),
    this.parserLimits = const FeedParserLimits(),
  });

  /// 取字节能力（复用 T013 的实现：条件请求、超时、限并发、大小上限）。
  final FeedFetcher fetcher;

  /// 订阅/分组读写端口。
  final FeedCatalogStore catalog;

  /// 文章写入端口（复用 T013 的幂等事务写入）。
  final FeedArticleStore articles;

  /// 诊断记录。
  final DiagnosticSink diagnostics;

  /// 时钟（抓取时间）。
  final Clock clock;

  /// 解析限制。
  final FeedParserLimits parserLimits;

  /// 抓取并解析一个地址，产出预览；**不写任何数据**。
  ///
  /// 返回值就地携带 [FeedPreview] 或类型化错误，不做「异常 + 空值」的双通道。
  Future<Result<FeedPreview>> preview(String rawUrl, {DateTime? now}) async {
    final Result<Uri> parsedUrl = parseFeedUrl(rawUrl);
    if (parsedUrl.isErr) {
      return Err<FeedPreview>(parsedUrl.errorOrNull!);
    }
    final Uri url = parsedUrl.unwrap();
    final String normalizedUrl =
        normalizeLink(url.toString()) ?? url.toString();

    // 重复检测放在抓取**之前**：已订阅时不值得再发一次网络请求，而且这样
    // 「同一地址重复添加」在网络不可用时也能给出正确结论（而不是报网络错误）。
    final Result<FeedRecord?> existing = await catalog.findFeedByNormalizedUrl(
      normalizedUrl,
    );
    if (existing.isErr) {
      return Err<FeedPreview>(existing.errorOrNull!);
    }
    final FeedRecord? duplicate = existing.valueOrNull;
    if (duplicate != null) {
      return Ok<FeedPreview>(
        FeedPreview.duplicate(
          requestedUrl: rawUrl.trim(),
          normalizedUrl: normalizedUrl,
          finalUrl: duplicate.normalizedUrl,
          title: duplicate.name,
          duplicateOf: duplicate,
        ),
      );
    }

    final Result<FeedFetchResult> fetched = await fetcher.fetch(url);
    if (fetched.isErr) {
      final AppError error = fetched.errorOrNull!;
      diagnostics.error(
        '添加订阅时抓取失败：${SecretRedaction.sanitizeUrlString(url.toString())}'
        ' — ${error.message}',
        tag: 'feed.add',
      );
      return Err<FeedPreview>(error);
    }
    final FeedFetchResult response = fetched.unwrap();

    // 304 在「首次添加」里不可能是「内容没变」的正常语义：库里没有这个源，
    // 说明请求端带了不该带的缓存校验值。如实报错，而不是给一个空预览。
    final String body = response.body ?? '';
    final Result<ParsedFeed> parsed = parseFeed(
      body,
      source: 'feed.preview',
      limits: parserLimits,
    );
    if (parsed.isErr) {
      final AppError error = parsed.errorOrNull!;
      diagnostics.error(
        '添加订阅时解析失败：${SecretRedaction.sanitizeUrlString(url.toString())}'
        ' — ${error.message}',
        tag: 'feed.add',
      );
      return Err<FeedPreview>(error);
    }
    final ParsedFeed feed = parsed.unwrap();

    return Ok<FeedPreview>(
      FeedPreview.fetched(
        requestedUrl: rawUrl.trim(),
        normalizedUrl: normalizedUrl,
        finalUrl: response.finalUri,
        title: previewTitle(feed: feed, normalizedUrl: normalizedUrl),
        entryCount: feed.entries.length,
        rejectedEntries: feed.rejectedEntries,
        document: body,
        parsed: feed,
        format: feed.format,
        siteUrl: feed.siteUrl,
      ),
    );
  }

  /// 用一次已完成的预览结果把订阅入库；**不再联网**。
  ///
  /// 重复判定在这里**再查一次**：预览与确认之间用户可以另开一个窗口添加同一地址，
  /// 只靠预览时的那次查询做结论会创建出两条同 URL 的订阅（唯一索引会拒绝，但错误
  /// 会以存储错误的形式冒出来，而不是「这就是重复添加」的清晰结论）。
  Future<Result<AddFeedOutcome>> confirm({
    required FeedPreview preview,
    required String name,
    int? groupId,
    DateTime? now,
  }) async {
    if (preview.duplicateOf case final FeedRecord duplicate) {
      return Ok<AddFeedOutcome>(
        AddFeedOutcome(feed: duplicate, isDuplicate: true, imported: null),
      );
    }
    if (!isValidFeedName(name)) {
      return Err<AddFeedOutcome>(
        ValidationError(field: 'feedName', reason: '订阅名称不能为空'),
      );
    }

    final Result<FeedRecord?> existing = await catalog.findFeedByNormalizedUrl(
      preview.normalizedUrl,
    );
    if (existing.isErr) {
      return Err<AddFeedOutcome>(existing.errorOrNull!);
    }
    final FeedRecord? raced = existing.valueOrNull;
    if (raced != null) {
      return Ok<AddFeedOutcome>(
        AddFeedOutcome(feed: raced, isDuplicate: true, imported: null),
      );
    }

    // 内容取自预览对象本身（它带着同一次抓取的文档与解析结果）。未抓取的预览
    // （重复订阅）在上面的 duplicateOf 分支已经返回，因此这里必然有内容。
    final ParsedFeed feed = preview.parsed!;

    final Result<FeedRecord> created = await catalog.createFeed(
      FeedInsert(
        syncId: feedSyncIdFor(preview.normalizedUrl),
        normalizedUrl: preview.normalizedUrl,
        name: name.trim(),
        sourceName: feed.title,
        groupId: groupId,
      ),
    );
    if (created.isErr) {
      return Err<AddFeedOutcome>(created.errorOrNull!);
    }
    final FeedRecord record = created.unwrap();

    // 入库文章。**先建订阅行再写文章**的顺序是有意的：文章表的 feedId 是外键，
    // 反过来会让事务在一个不存在的目标上写入。若这一步失败，订阅行会留下一行
    // 没有文章的空源——这是可被用户看见并修复的状态（手动刷新即可），
    // 比「文章写在孤儿 id 上」要好。
    final FeedImportBatch batch = buildFeedImportBatch(
      feedId: record.id,
      feed: feed,
      feedIdentity: preview.normalizedUrl,
      fetchedAt: (now ?? clock.now()).toUtc(),
    );
    if (batch.imports.isEmpty) {
      return Ok<AddFeedOutcome>(
        AddFeedOutcome(
          feed: record,
          isDuplicate: false,
          imported: const ArticleImportOutcome(
            inserted: 0,
            updated: 0,
            bodyUpdated: 0,
            unchanged: 0,
          ),
          finalUrl: preview.finalUrl,
        ),
      );
    }

    final Result<ArticleImportOutcome> imported = await articles.upsertArticles(
      batch.imports,
    );
    if (imported.isErr) {
      diagnostics.error(
        '添加订阅时写入文章失败：${SecretRedaction.sanitizeUrlString(preview.normalizedUrl)}'
        ' — ${imported.errorOrNull?.message}',
        tag: 'feed.add',
      );
      return Err<AddFeedOutcome>(imported.errorOrNull!);
    }

    diagnostics.info(
      '已添加订阅：${SecretRedaction.sanitizeUrlString(preview.normalizedUrl)}'
      '（新增 ${imported.valueOrNull!.inserted} 篇）',
      tag: 'feed.add',
    );
    return Ok<AddFeedOutcome>(
      AddFeedOutcome(
        feed: record,
        isDuplicate: false,
        imported: imported.valueOrNull,
        finalUrl: preview.finalUrl,
      ),
    );
  }

  /// 预览标题：源自带标题 → 站点主机名 → 规范化地址。
  ///
  /// 三档都取不到时不会发生（规范化地址必然非空），因此返回值非空是结构性保证。
  static String previewTitle({
    required ParsedFeed feed,
    required String normalizedUrl,
  }) {
    final String? title = feed.title?.trim();
    if (title != null && title.isNotEmpty) {
      return title;
    }
    final Uri? parsed = Uri.tryParse(normalizedUrl);
    if (parsed != null && parsed.host.isNotEmpty) {
      return parsed.host;
    }
    return normalizedUrl;
  }

  /// 校验并解析用户输入的订阅地址。
  ///
  /// 只允许 http/https：架构第 8 节的边界校验要求，且不允许「自动发现」式的猜测
  /// （用户在地址栏里填一个网页地址时，我们不替他去猜 feed 路径——那需要抓取整页
  /// 再猜，且猜错会订阅到一个 HTML 页面）。
  static Result<Uri> parseFeedUrl(String rawUrl) {
    final String trimmed = rawUrl.trim();
    if (trimmed.isEmpty) {
      return Err<Uri>(ValidationError(field: 'feedUrl', reason: '订阅地址不能为空'));
    }
    final Uri? uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme) {
      return Err<Uri>(
        ValidationError(field: 'feedUrl', reason: '地址格式不正确（需要完整 URL）'),
      );
    }
    if (!uri.isScheme('http') && !uri.isScheme('https')) {
      return Err<Uri>(
        ValidationError(
          field: 'feedUrl',
          reason: '只支持 http/https 地址（实际 ${uri.scheme}）',
        ),
      );
    }
    if (uri.host.isEmpty) {
      return Err<Uri>(ValidationError(field: 'feedUrl', reason: '地址缺少主机名'));
    }
    return Ok<Uri>(uri);
  }
}
