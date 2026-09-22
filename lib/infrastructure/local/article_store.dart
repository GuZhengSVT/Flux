// 文章导入事务（T009 数据层；业务/网络流程见 T013）。
//
// 本文件只做**数据层**的幂等写入：给定已解析好的文章，按身份规则匹配并合并，
// 保留用户已产生的阅读状态与收藏。它不下载、不解析、不判定正文完整性，
// 也不做调度——那些属于 T013/T016。
//
// 幂等语义（架构 4.1）：
//   - 身份：同 Feed 内按 GUID → 规范化链接 → 来源/标题/时间指纹依次匹配；
//   - 重复导入不新增行，只更新内容字段；
//   - 正文只在**正文哈希变化**时更新（正文哈希只判修订，不判身份）；
//   - readingState 与 favorite 永不被导入覆盖（later 不会被刷成 unread）。
//
// T045 补一条匹配路径：**占位行的升级**。远端状态到达而本机没有正文时，T041 会落一行
// identityBasis = remote 的占位行（没有 GUID/链接/指纹，只有一个跨设备同步键）。这样的行
// 用上面的三条身份规则**找不到**——它没有任何身份证据，因此抓取会为同一篇文章插出第二行，
// 而占位行（连它的阅读状态）留在库里成为一条永远读不出正文的孤行。因此这里在三条身份规则
// 之后再加一条：按**同步键**匹配（本机证据算出的键、以及由它派生的占位键），命中占位行时
// 补上身份与正文，**保留阅读状态与收藏**。
library;

import 'package:drift/drift.dart';

import 'package:flux/core/core.dart';

import 'database.dart';
import 'tables/article_tables.dart';
import 'tables/feed_tables.dart';

// 导入 DTO（ArticleImport / ArticleImportOutcome）自 T012 起定义在
// lib/core/domain/article_import.dart：解析层（features）要产出它们，而 features
// 不得 import infrastructure。这里不再重复声明，避免出现两份形状接近的定义。

/// 文章数据层操作。
extension ArticleStore on AppDatabase {
  /// 幂等批量导入：整个批次在**单个事务**内完成，任一条失败则整批回滚。
  ///
  /// 返回 [Result]，使导入流程无需捕获底层异常：数据库错误统一成为
  /// [StorageError]（架构 2.2、T007 错误体系）。
  Future<Result<ArticleImportOutcome>> upsertArticles(
    List<ArticleImport> imports,
  ) async {
    try {
      final ArticleImportOutcome outcome = await transaction(() async {
        int inserted = 0;
        int updated = 0;
        int bodyUpdated = 0;
        int unchanged = 0;

        // 订阅的跨设备标识：占位行的同步键由「订阅 syncId + 证据」派生，因此按同步键匹配
        // 需要它。每个 feed 只查一次（一批导入通常来自同一个源）。
        final Map<int, String?> feedSyncIds = <int, String?>{};
        Future<String?> feedSyncIdOf(int feedId) async {
          if (feedSyncIds.containsKey(feedId)) {
            return feedSyncIds[feedId];
          }
          final Feed? feed =
              await (select(feeds)
                    ..where((Feeds t) => t.id.equals(feedId))
                    ..limit(1))
                  .getSingleOrNull();
          final String? syncId = feed?.syncId;
          feedSyncIds[feedId] = syncId;
          return syncId;
        }

        for (final ArticleImport incoming in imports) {
          final String? feedSyncId = await feedSyncIdOf(incoming.feedId);
          // 本次抓取按本机证据算出的同步键（可能为 null：证据全缺）。占位行升级后要把它
          // 写成这一行的同步键，否则这一行对外的同步身份仍停在「远端那次给占位键」上，而
          // 下一轮状态同步会用它去匹配——两台设备各自算出的键就不再是同一个了。
          final String? incomingKey = _syncKeyOf(
            incoming: incoming,
            feedSyncId: feedSyncId,
          );
          final Article? existing =
              await _findByIdentity(incoming) ??
              await _findBySyncKey(key: incomingKey, feedSyncId: feedSyncId);

          if (existing == null) {
            await into(articles).insert(_toCompanion(incoming));
            inserted++;
            continue;
          }

          // 身份依据只允许 remote → 真实依据（T041 的 upgradedIdentityBasis）。反向升级
          // 会让一行已经可去重的文章退回「身份未知」，于是同一篇文章会在下一次刷新时被
          // 再插一行。没有新证据时返回 null，保持原样。
          final IdentityBasis? upgraded = upgradedIdentityBasis(
            current: existing.identityBasis,
            guid: incoming.guidPresent ? incoming.guid : null,
            normalizedLink: incoming.normalizedLink,
            fallbackFingerprint: incoming.fallbackFingerprint,
          );

          // 正文替换条件：本次解析**确实带了正文与新哈希**，且哈希与库里不同。
          // 两个刻意的保守选择：
          //   - incoming.bodyHash 为 null 时不动正文，避免“解析失败/只有摘要”
          //     的刷新把已存全文擦成空；
          //   - 哈希相同即视为同一修订，不重写大字段。
          final bool bodyChanged =
              incoming.bodyHash != null &&
              incoming.bodyHash != existing.bodyHash;

          final ArticlesCompanion patch = ArticlesCompanion(
            title: Value<String>(incoming.title),
            author: Value<String?>(incoming.author),
            publishedAt: Value<DateTime?>(incoming.publishedAt),
            fetchedAt: Value<DateTime>(
              incoming.fetchedAt ?? DateTime.now().toUtc(),
            ),
            summary: Value<String?>(incoming.summary),
            // 同步键：占位行升级时把它从「远端派生的占位键」换成「本机证据算出的键」——
            // 这一行的身份已经由本机确认，同步身份就该跟着变（否则下一轮状态同步仍按占位键
            // 去匹配，两台设备各自算出的键不再是同一个）。已有真实键时**不动**：键的漂移会
            // 让对端看到「一条消失、一条新增」，而它携带的阅读状态会丢。
            syncKey:
                existing.identityBasis == IdentityBasis.remote &&
                    incomingKey != null
                ? Value<String?>(incomingKey)
                : const Value<String?>.absent(),
            // 占位行升级：抓取补上身份后，判定依据从 remote 换成真实依据（只单向）。
            // 没有新证据时 upgraded 为 null，写 absent 表示「不改这一列」。
            identityBasis: upgraded == null
                ? const Value<IdentityBasis>.absent()
                : Value<IdentityBasis>(upgraded),
            // 图片地址补齐空缺但不覆盖已有值：与 normalizedLink 同一口径。源后来
            // 撤销了 enclosure 时**不**把卡片图片抹掉——那会让一份已经显示过的封面
            // 在下次刷新后无故消失，而用户没有任何办法找回来（T021 的缓存才是它的
            // 归属地）。
            imageUrl: Value<String?>(existing.imageUrl ?? incoming.imageUrl),
            bodyCompleteness: Value<BodyCompleteness>(
              incoming.bodyCompleteness,
            ),
            // 链接与兜底指纹可能在后续抓取中才拿到，补齐空缺但不覆盖已有值。
            normalizedLink: Value<String?>(
              existing.normalizedLink ?? incoming.normalizedLink,
            ),
            sourceUrl: Value<String?>(existing.sourceUrl ?? incoming.sourceUrl),
            guid: Value<String?>(existing.guid ?? incoming.guid),
            guidPresent: Value<bool>(
              existing.guidPresent || incoming.guidPresent,
            ),
            fallbackFingerprint: Value<String?>(
              existing.fallbackFingerprint ?? incoming.fallbackFingerprint,
            ),
            fingerprintReliability: Value<FingerprintReliability?>(
              existing.fingerprintReliability ??
                  incoming.fingerprintReliability,
            ),
            body: bodyChanged
                ? Value<String?>(incoming.body)
                : const Value.absent(),
            bodyHash: bodyChanged
                ? Value<String?>(incoming.bodyHash)
                : const Value.absent(),
            updatedAt: Value<DateTime>(DateTime.now().toUtc()),
            // readingState / favorite / createdAt / id 有意不出现在补丁里：
            // 导入不得改变用户状态（later 打开后仍为 later 的数据基础）。
          );

          // 真正落库前先判断是否**确有内容变化**；完全相同就不写、也不推进
          // updatedAt，使“同一份 feed 反复导入”在数据上可证明是幂等的。
          if (!_hasContentChange(
            existing,
            incoming,
            bodyChanged: bodyChanged,
          )) {
            unchanged++;
            continue;
          }

          await (update(
            articles,
          )..where((Articles t) => t.id.equals(existing.id))).write(patch);

          if (bodyChanged) {
            bodyUpdated++;
          }
          updated++;
        }

        return ArticleImportOutcome(
          inserted: inserted,
          updated: updated,
          bodyUpdated: bodyUpdated,
          unchanged: unchanged,
        );
      });

      return Ok<ArticleImportOutcome>(outcome);
    } on AppError catch (error, stackTrace) {
      return Err<ArticleImportOutcome>(
        error is StorageError
            ? error
            : StorageError(
                operation: 'upsertArticles',
                detail: error.message,
                cause: error,
                stackTrace: stackTrace,
              ),
      );
    } on Exception catch (error, stackTrace) {
      return Err<ArticleImportOutcome>(
        StorageError(
          operation: 'upsertArticles',
          detail: error.runtimeType.toString(),
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  /// 比较“导入内容”与“已有行”是否产生了需要写入的差异。
  ///
  /// 有意**不**比较：readingState、favorite、createdAt、id（导入无权改动），
  /// 以及 updatedAt（它是写入结果而非内容）。这样重复导入同一份 feed 时
  /// 判定为无变化，不产生多余写入。
  static bool _hasContentChange(
    Article existing,
    ArticleImport incoming, {
    required bool bodyChanged,
  }) {
    if (bodyChanged) {
      return true;
    }

    if (existing.title != incoming.title ||
        existing.author != incoming.author ||
        existing.publishedAt != incoming.publishedAt ||
        existing.summary != incoming.summary ||
        existing.bodyCompleteness != incoming.bodyCompleteness ||
        existing.identityBasis != incoming.identityBasis) {
      return true;
    }

    // 这些字段只在“原本为空”时才会被补上，因此仅当已有值为空而导入有值才算变化。
    if (existing.normalizedLink == null && incoming.normalizedLink != null) {
      return true;
    }
    if (existing.sourceUrl == null && incoming.sourceUrl != null) {
      return true;
    }
    if (existing.guid == null && incoming.guid != null) {
      return true;
    }
    if (!existing.guidPresent && incoming.guidPresent) {
      return true;
    }
    if (existing.fallbackFingerprint == null &&
        incoming.fallbackFingerprint != null) {
      return true;
    }
    if (existing.fingerprintReliability == null &&
        incoming.fingerprintReliability != null) {
      return true;
    }
    if (existing.imageUrl == null && incoming.imageUrl != null) {
      return true;
    }

    return false;
  }

  /// 按架构 4.1 的顺序查找已有文章：GUID → 规范化链接 → 兜底指纹。
  ///
  /// 只使用**本行实际提供**的标识，避免用空值参与匹配而把不相关文章并到一起。
  Future<Article?> _findByIdentity(ArticleImport incoming) async {
    final String? guid = incoming.guidPresent ? incoming.guid : null;

    if (guid != null && guid.isNotEmpty) {
      final Article? byGuid =
          await (select(articles)
                ..where(
                  (Articles t) =>
                      t.feedId.equals(incoming.feedId) & t.guid.equals(guid),
                )
                ..limit(1))
              .getSingleOrNull();
      if (byGuid != null) {
        return byGuid;
      }
    }

    final String? link = incoming.normalizedLink;
    if (link != null && link.isNotEmpty) {
      final Article? byLink =
          await (select(articles)
                ..where(
                  (Articles t) =>
                      t.feedId.equals(incoming.feedId) &
                      t.normalizedLink.equals(link),
                )
                ..limit(1))
              .getSingleOrNull();
      if (byLink != null) {
        return byLink;
      }
    }

    final String? fingerprint = incoming.fallbackFingerprint;
    if (fingerprint != null && fingerprint.isNotEmpty) {
      return (select(articles)
            ..where(
              (Articles t) =>
                  t.feedId.equals(incoming.feedId) &
                  t.fallbackFingerprint.equals(fingerprint),
            )
            ..limit(1))
          .getSingleOrNull();
    }

    return null;
  }

  /// 按**跨设备同步键**查找已有文章（T045 的占位行升级入口）。
  ///
  /// 为什么需要这第四条路径：占位行没有任何身份证据（T041 的 `IdentityBasis.remote` 行
  /// 既没有 GUID 也没有链接与指纹），上面三条规则因此全都找不到它。而它的同步键是**由
  /// 远端用同一份证据算出来的**——键函数是确定性的纯函数，两台设备对同一篇文章算出同一个
  /// 键。所以本机这次抓取只要能算出同一个键，就能把抓取结果**接到那一行上**，而不是为同一
  /// 篇文章再插一行（第二行没有阅读状态，占位行则永远读不出正文）。
  ///
  /// 只匹配 `identityBasis == remote` 的行：键相同的真实行会先被 [_findByIdentity] 命中，
  /// 而这里再匹配一次会让「本机已有一行真实身份的文章」被另一条导入项覆盖。
  Future<Article?> _findBySyncKey({
    required String? key,
    required String? feedSyncId,
  }) async {
    if (key == null || feedSyncId == null || feedSyncId.isEmpty) {
      return null;
    }
    // 两个候选键，顺序有意义：
    //   1) 本机这次算出的键本身——远端设备算出的键就是**同一个**（键函数是确定性的纯
    //      函数），所以对端快照里那条状态的键与它相等；
    //   2) 由它派生的**占位键**——T041 落占位行时存的是 syncPlaceholderKey(syncId,
    //      远端键)，即对本机这次算出的键再做一次派生。缺了这一步，抓取永远匹配不到
    //      占位行（占位行没有任何身份证据，[_findByIdentity] 也找不到它），于是同一篇
    //      文章会被插出第二行，而占位行（连它的阅读状态）成为一条永远读不出正文的孤行。
    for (final String candidate in <String>[
      key,
      syncPlaceholderKey(feedSyncId: feedSyncId, remoteKey: key),
    ]) {
      final Article? row =
          await (select(articles)
                ..where((Articles t) => t.syncKey.equals(candidate))
                ..limit(1))
              .getSingleOrNull();
      if (row == null) {
        continue;
      }
      // 只有**占位行**才允许被这次抓取「接管」：真实身份的行由 [_findByIdentity] 负责，
      // 从这条路命中它会让一次刷新改写一行本机已经确认过身份的文章（它的 GUID/链接可能
      // 与本次解析结果不同，而那种差异应当被当作另一个身份问题处理，不是静默合并）。
      if (row.identityBasis == IdentityBasis.remote) {
        return row;
      }
    }
    return null;
  }

  /// 本次导入项在本机的同步键（由订阅 syncId 与身份证据确定性算出）。
  String? _syncKeyOf({
    required ArticleImport incoming,
    required String? feedSyncId,
  }) {
    if (feedSyncId == null || feedSyncId.isEmpty) {
      return null;
    }
    return syncArticleKeyFor(
      feedSyncId: feedSyncId,
      basis: incoming.identityBasis,
      guid: incoming.guidPresent ? incoming.guid : null,
      normalizedLink: incoming.normalizedLink,
      fallbackFingerprint: incoming.fallbackFingerprint,
      reliability: incoming.fingerprintReliability,
    );
  }

  /// 构造新增行；阅读状态与收藏使用默认值（unread / false）。
  ArticlesCompanion _toCompanion(ArticleImport incoming) {
    return ArticlesCompanion.insert(
      // feedId 在 schema v5 起可空（删除订阅时保留下来的收藏会脱离源）。导入路径
      // 永远写一个真实存在的 id，因此这里包一层 Value 只是匹配生成的签名；刻意不写
      // Value.absent：那会落成一条没有归属的孤儿文章。
      feedId: Value<int?>(incoming.feedId),
      title: incoming.title,
      identityBasis: incoming.identityBasis,
      guid: Value<String?>(incoming.guid),
      guidPresent: Value<bool>(incoming.guidPresent),
      normalizedLink: Value<String?>(incoming.normalizedLink),
      sourceUrl: Value<String?>(incoming.sourceUrl),
      fallbackFingerprint: Value<String?>(incoming.fallbackFingerprint),
      fingerprintReliability: Value<FingerprintReliability?>(
        incoming.fingerprintReliability,
      ),
      author: Value<String?>(incoming.author),
      publishedAt: Value<DateTime?>(incoming.publishedAt),
      fetchedAt: Value<DateTime>(incoming.fetchedAt ?? DateTime.now().toUtc()),
      body: Value<String?>(incoming.body),
      bodyCompleteness: Value<BodyCompleteness>(incoming.bodyCompleteness),
      bodyHash: Value<String?>(incoming.bodyHash),
      summary: Value<String?>(incoming.summary),
      imageUrl: Value<String?>(incoming.imageUrl),
      readingState: const Value<ReadingState>(ReadingState.unread),
    );
  }
}
