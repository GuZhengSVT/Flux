// 跨设备文章同步键与订阅对齐（T041；架构 5.2）。
//
// 架构原话：「跨设备文章键采用共享 Feed syncId + 类型标记 + GUID（无 GUID 用规范 URL/
// 稳定指纹）的确定性摘要。本机自增 ID 不外传；两台独立导入同一源时先按规范 URL 对齐
// Feed 并保存别名。」
//
// 三处刻意的设计，每一处都对应一类真实会发生的错误：
//
//   1) **键里必须有 Feed syncId**。很多源用同一套模板生成 GUID（甚至直接拿文章标题
//      或时间当 GUID），因此「同一个 GUID」在两个源里**不代表同一篇文章**。少了源标识，
//      两台设备各自订阅了不同源时会开始互相把对方的文章标成已读——而且不会有任何报错。
//
//   2) **类型标记必须进摘要**。若只用 guid 字符串参与哈希，那么一篇「有 GUID = abc」
//      的文章与一篇「规范化链接恰好也是 abc」的占位行会算出同一个键；而这两行携带的
//      是不同可靠度的身份证据（架构 4.1 明确要求保留诊断、不静默合并）。把判定依据
//      本身掺进摘要之后，「不同证据来源得到不同键」是结构性的，不靠调用方记得判断。
//
//   3) **同输入同键、异输入异键**。键是纯函数产物：不含时间、不含随机、不含本机 id，
//      因此两台设备对同一篇文章算出同一个键；这也是「确定性」在这里的唯一含义。
//
// 本文件是纯 Dart、无 I/O、不依赖 Flutter 或 drift，可被纯 Dart 测试逐条钉住。
library;

import '../digest/sha256.dart';

import 'article_identity.dart';

/// 文章同步键的**类型标记**（架构 5.2 原文的「类型标记」）。
///
/// 取值与 [IdentityBasis] 有意不同名（多了 [article]）：这里是**键空间**的标记，
/// 而不是「这一行是怎么被识别的」。将来若同步还传别的实体（例如分组的位置），它们会
/// 加进这个命名空间而不会与文章状态撞键。
abstract final class SyncKeyMarker {
  /// 文章状态。
  static const String article = 'article';

  /// 由源内 GUID 识别的文章。
  static const String guid = 'guid';

  /// 由规范化链接识别的文章。
  static const String link = 'link';

  /// 由来源/标题/时间指纹兜底识别的文章。
  static const String fingerprint = 'fingerprint';

  /// 由远端状态到达、本机还没有正文的占位文章。
  ///
  /// 与上面三个**分属不同键空间**：占位行随时可能被真实抓取「补上身份」而换键，因此
  /// 它对外的同步键必须在补上前保持稳定（否则另一台设备会看到「一条消失、一条新增」，
  /// 而它携带的阅读状态会丢）。
  static const String remoteState = 'remoteState';

  /// 全部标记（供快照格式校验）。
  static const List<String> all = <String>[
    guid,
    link,
    fingerprint,
    remoteState,
  ];
}

/// 同步键的长度（SHA-256 十六进制字符数）。
///
/// 与 fallbackFingerprint 同样的取舍：取 32 个十六进制字符（128 位），在实际文章量下
/// 碰撞概率可忽略，同时让键短到可以直接进快照与日志。
const int syncArticleKeyLength = 32;

/// 计算一篇文章的跨设备同步键。
///
/// 优先顺序与架构 4.1 的身份顺序一致（GUID → 规范化链接 → 指纹）。三个证据都缺失时
/// 返回 null：**没有身份的文章不能参与状态同步**——给它编一个键只会让两台设备上的
/// 无关文章因为同一个空输入而互相覆盖状态。调用方拿到 null 应当跳过这篇文章并记录
/// 诊断（架构 4.1「不可靠兜底身份保留诊断而非误合并」）。
String? syncArticleKey({
  required String feedSyncId,
  String? guid,
  String? normalizedLink,
  String? fallbackFingerprint,
  String? reliabilityNote,
}) {
  final String? trimmedGuid = _nonEmpty(guid);
  if (trimmedGuid != null) {
    return _digest(feedSyncId, SyncKeyMarker.guid, trimmedGuid);
  }
  final String? trimmedLink = _nonEmpty(normalizedLink);
  if (trimmedLink != null) {
    return _digest(feedSyncId, SyncKeyMarker.link, trimmedLink);
  }
  final String? trimmedFingerprint = _nonEmpty(fallbackFingerprint);
  if (trimmedFingerprint != null) {
    // [reliabilityNote] 只进入摘要而**不**参与取舍：不可靠指纹（缺发布时间）仍然要能
    // 算出键（否则那些文章的状态永远同步不了），但它与可靠指纹算出的键不同，因此
    // 「不可靠身份」这件事在键空间里可见，而不是被悄悄当作可靠证据使用。
    return _digest(
      feedSyncId,
      SyncKeyMarker.fingerprint,
      reliabilityNote == null
          ? trimmedFingerprint
          : '$trimmedFingerprint\u0000$reliabilityNote',
    );
  }
  return null;
}

/// 由 [IdentityBasis] 与各证据计算键（调用方的便利封装）。
///
/// 显式接受 basis 而不是「按可用字段猜」：一处调用点写出了不一致的证据组合（例如
/// 声称是 guid 却只给了链接）时，这里按它**声明的**依据算键，让不一致立刻表现为
/// 「键与预期不同」，而不是被静默修正。
String? syncArticleKeyFor({
  required String feedSyncId,
  required IdentityBasis basis,
  String? guid,
  String? normalizedLink,
  String? fallbackFingerprint,
  FingerprintReliability? reliability,
}) {
  switch (basis) {
    case IdentityBasis.guid:
      return syncArticleKey(feedSyncId: feedSyncId, guid: guid);
    case IdentityBasis.normalizedLink:
      return syncArticleKey(
        feedSyncId: feedSyncId,
        normalizedLink: normalizedLink,
      );
    case IdentityBasis.fingerprint:
      return syncArticleKey(
        feedSyncId: feedSyncId,
        fallbackFingerprint: fallbackFingerprint,
        reliabilityNote: reliability?.name,
      );
    case IdentityBasis.remote:
      // 占位行只有本机自增 id 与远端给的键，没有可推导的证据；它的同步键由远端键
      // 原样承接（见 syncPlaceholderKey），因此这里不给一个「猜出来」的键。
      return null;
  }
}

/// 占位行的同步键：由远端键与订阅 syncId 派生。
///
/// 为什么不直接沿用远端键：远端键是**另一台设备**按它的证据算出来的，本机尚未验证
/// 任何证据（没有 GUID、没有链接）。把它当作本机的键就等于让远端单方面决定本机这行
/// 的身份；而掺入本机订阅 syncId 之后，这份「从哪条订阅来的」在本机仍然是可核对的。
String syncPlaceholderKey({
  required String feedSyncId,
  required String remoteKey,
}) => _digest(feedSyncId, SyncKeyMarker.remoteState, remoteKey);

/// 远端状态到达时对本机这一行的处理方式（架构 5.2「保存状态占位，后续抓取匹配；
/// 不把不存在的文章虚构成全文」）。
enum SyncRemoteStateAction {
  /// 本机没有这一行：新建**占位行**（状态落库、正文为空、identityBasis = remote）。
  createPlaceholder,

  /// 本机已有这一行（含正文或是占位）：只应用状态，正文与身份一律不动。
  applyStateOnly,
}

/// 判定远端状态到达时的动作。
///
/// 两个入参而不是「传一整行」：判据只需要「本机有没有这一行」，多传字段会让调用方
/// 以为函数还会读别的列（例如正文），而它**刻意不看正文**——本机有正文时绝不用远端
/// 的空正文覆盖（架构 5.2 首发不同步正文，因此远端的正文一定是空的，照搬会清空本机
/// 已抓取的全文）。
SyncRemoteStateAction planRemoteStateArrival({required bool hasLocalRow}) =>
    hasLocalRow
    ? SyncRemoteStateAction.applyStateOnly
    : SyncRemoteStateAction.createPlaceholder;

/// 占位行被真实抓取补上身份时，新的判定依据应当是什么。
///
/// 抓取拿到证据后**只允许**把 remote 升级为真实依据，绝不反向（真实依据→remote 会
/// 让已经可去重的行退回「身份未知」，于是同一篇文章会在下一次刷新时被当成新文章
/// 再插一行）。返回 null 表示本次抓取没有带来可用证据，保持原样。
IdentityBasis? upgradedIdentityBasis({
  required IdentityBasis current,
  String? guid,
  String? normalizedLink,
  String? fallbackFingerprint,
}) {
  if (current != IdentityBasis.remote) {
    return null;
  }
  if (_nonEmpty(guid) != null) {
    return IdentityBasis.guid;
  }
  if (_nonEmpty(normalizedLink) != null) {
    return IdentityBasis.normalizedLink;
  }
  if (_nonEmpty(fallbackFingerprint) != null) {
    return IdentityBasis.fingerprint;
  }
  return null;
}

// ===========================================================================
// 订阅对齐（架构 5.2「两台独立导入同一源时先按规范 URL 对齐 Feed 并保存别名」）
// ===========================================================================

/// 一条订阅对齐别名（syncId ↔ 本机 feed id）。
final class SyncFeedAlias {
  /// 构造别名。
  const SyncFeedAlias({required this.syncId, required this.localFeedId});

  /// 跨设备稳定标识。
  final String syncId;

  /// 本机自增 id。
  final int localFeedId;
}

/// 对齐一侧的候选项。
final class SyncFeedCandidate {
  /// 构造候选项。
  const SyncFeedCandidate({
    required this.syncId,
    required this.normalizedUrl,
    this.localFeedId,
  });

  /// 跨设备稳定标识。
  final String syncId;

  /// 规范化地址（仅用于匹配）。
  final String normalizedUrl;

  /// 本机 id；远端一侧为 null（远端不知道本机的 id）。
  final int? localFeedId;
}

/// 一次订阅对齐的结果。
final class FeedAlignment {
  /// 构造结果。
  const FeedAlignment({
    required this.remoteSyncId,
    required this.localFeedId,
    required this.matchedByNormalizedUrl,
  });

  /// 远端（或要应用的一侧）的 syncId。
  final String remoteSyncId;

  /// 本机 feed id。
  final int localFeedId;

  /// 是否靠规范化 URL 匹配上的（而不是 syncId 直接相等）。
  ///
  /// 这个标记决定**是否要保存别名**：syncId 相等时两台设备本来就认同一条订阅，别名是
  /// 冗余；靠 URL 匹配上时必须记下别名，否则下一次同步又会走一遍 URL 匹配（而那时源
  /// 可能改了地址，就再也对不上了）。
  final bool matchedByNormalizedUrl;

  /// 是否产生了新的别名。
  bool get createsAlias => matchedByNormalizedUrl;
}

/// 对齐订阅：先按 syncId，再按规范化 URL。
///
/// 三条规则（每一条都对应一类会丢数据的做法）：
///   1) **syncId 优先**：它本来就是为跨设备对齐而生成的（T014），URL 匹配会让源改地址
///      之后整条订阅在另一台设备上变成「新的源」，于是文章状态全部重来；
///   2) **URL 匹配必须唯一**：同一个规范化 URL 在本机出现两次（用户手工重复添加过）
///      时**不对齐**，而不是挑一个——挑错了会把远端状态写进错误的那条订阅，而两条
///      订阅的文章集合并不相同；
///   3) **一条本机订阅只被对齐一次**：远端两条记录同时指向同一条本机订阅时，后面的
///      那条保持未对齐（界面提示需要人工处理），避免两条远端记录的并发状态互相覆盖。
List<FeedAlignment> alignFeeds({
  required List<SyncFeedCandidate> remote,
  required List<SyncFeedCandidate> local,
}) {
  final Map<String, int> bySyncId = <String, int>{};
  for (final SyncFeedCandidate candidate in local) {
    final int? id = candidate.localFeedId;
    if (id != null) {
      bySyncId[candidate.syncId] = id;
    }
  }

  // 规范化 URL → 本机 id；重复 URL 记成 null 表示「不可判定」。
  final Map<String, int?> byUrl = <String, int?>{};
  for (final SyncFeedCandidate candidate in local) {
    final int? id = candidate.localFeedId;
    if (id == null) {
      continue;
    }
    final String key = candidate.normalizedUrl;
    if (byUrl.containsKey(key)) {
      byUrl[key] = null; // 歧义：保留键但置空，后面据此拒绝匹配。
      continue;
    }
    byUrl[key] = id;
  }

  final Set<int> claimed = <int>{};
  final List<FeedAlignment> alignments = <FeedAlignment>[];

  // 第一轮：syncId 直接相等。
  for (final SyncFeedCandidate candidate in remote) {
    final int? id = bySyncId[candidate.syncId];
    if (id != null && !claimed.contains(id)) {
      claimed.add(id);
      alignments.add(
        FeedAlignment(
          remoteSyncId: candidate.syncId,
          localFeedId: id,
          matchedByNormalizedUrl: false,
        ),
      );
    }
  }

  // 第二轮：剩下的按规范化 URL 匹配（要求唯一且未被认领）。
  for (final SyncFeedCandidate candidate in remote) {
    final bool already = alignments.any(
      (FeedAlignment a) => a.remoteSyncId == candidate.syncId,
    );
    if (already) {
      continue;
    }
    final int? id = byUrl[candidate.normalizedUrl];
    if (id == null || claimed.contains(id)) {
      continue;
    }
    claimed.add(id);
    alignments.add(
      FeedAlignment(
        remoteSyncId: candidate.syncId,
        localFeedId: id,
        matchedByNormalizedUrl: true,
      ),
    );
  }

  return List<FeedAlignment>.unmodifiable(alignments);
}

/// 本机 id → 远端 syncId（别名表的正查）。
int? localFeedIdForSyncId({
  required String syncId,
  required Iterable<SyncFeedAlias> aliases,
}) {
  for (final SyncFeedAlias alias in aliases) {
    if (alias.syncId == syncId) {
      return alias.localFeedId;
    }
  }
  return null;
}

/// 远端 syncId → 本机 id（别名表的反查）。
String? syncIdForLocalFeedId({
  required int localFeedId,
  required Iterable<SyncFeedAlias> aliases,
}) {
  for (final SyncFeedAlias alias in aliases) {
    if (alias.localFeedId == localFeedId) {
      return alias.syncId;
    }
  }
  return null;
}

/// 对齐结果里需要新增的别名（已存在的不重复返回）。
List<SyncFeedAlias> aliasesToPersist({
  required List<FeedAlignment> alignments,
  required Iterable<SyncFeedAlias> existing,
}) {
  final List<SyncFeedAlias> additions = <SyncFeedAlias>[];
  for (final FeedAlignment alignment in alignments) {
    if (!alignment.createsAlias) {
      // syncId 本来就相等：两边认同一条订阅，不需要别名行。
      continue;
    }
    final int? known = localFeedIdForSyncId(
      syncId: alignment.remoteSyncId,
      aliases: existing,
    );
    if (known == alignment.localFeedId) {
      continue;
    }
    if (additions.any(
      (SyncFeedAlias a) =>
          a.syncId == alignment.remoteSyncId &&
          a.localFeedId == alignment.localFeedId,
    )) {
      continue;
    }
    additions.add(
      SyncFeedAlias(
        syncId: alignment.remoteSyncId,
        localFeedId: alignment.localFeedId,
      ),
    );
  }
  return List<SyncFeedAlias>.unmodifiable(additions);
}

String _digest(String feedSyncId, String marker, String evidence) =>
    sha256HexOfString('$feedSyncId\u0000$marker\u0000$evidence')
        .substring(0, syncArticleKeyLength);

String? _nonEmpty(String? value) {
  if (value == null) {
    return null;
  }
  final String trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
