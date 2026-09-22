// 同步状态的读写端口与占位行语义（T041；架构 5.1 的 SyncState 实体、架构 5.2）。
//
// 端口住在 core（与 FeedCatalogStore / NewsSourceConfigStore 同一做法）：用例住在
// features/sync，而 features 不得 import infrastructure。
//
// 这一层只描述**本机记录的同步状态**：基线版本、待同步变更、墓碑、订阅别名，以及
// 「远端状态到达」的应用。它不做合并决策（T043）、不发网络请求（T042）、不做冲突
// 呈现（T044）。
//
// 四条不变量（由实现与测试共同保证）：
//   1) **确认按修订号**：确认已上传只清「≤ 本次快照修订」的行，绝不清空整表 dirty
//      （架构 5.2「提交结果仅确认已包含的修订，不能……将所有 dirty 标记一并清空」）；
//   2) **墓碑不自动清除**：删除是长期事实（架构 5.2「首发不自动清除」）；
//   3) **占位行不虚构正文**：远端状态到达而本机没有正文时，只落状态与空正文
//      （架构 5.2「不把不存在的文章虚构成全文」）；
//   4) **凭据不经过这里**：端口没有任何接受秘密参数的方法，因此「同步层把秘密写到
//      Keychain 之外的地方」在类型上不可能。
library;

import '../result.dart';

import 'article_identity.dart';
import 'reading_state.dart';
import 'sync_article_key.dart';

/// 本机同步基线（架构 5.1 的 SyncState）。
final class SyncBaseline {
  /// 构造基线。
  const SyncBaseline({
    required this.baseVersion,
    required this.localRevision,
    required this.lastSyncedAt,
    required this.deviceName,
    required this.supportsConditionalWrite,
    required this.capabilityProbedAt,
  });

  /// 共同基线版本（上一次成功同步后的 manifest 版本）；从未同步为 null。
  final String? baseVersion;

  /// 本地修订号（单调递增）。
  final int localRevision;

  /// 上次成功同步时刻（UTC）。
  final DateTime? lastSyncedAt;

  /// 本机设备名（SET-070；标识而非秘密）。
  final String? deviceName;

  /// 服务器是否支持条件写（null = 尚未探测，见 T042 的能力探测）。
  final bool? supportsConditionalWrite;

  /// 上次能力探测时刻（UTC）。
  final DateTime? capabilityProbedAt;

  /// 是否已经探测过条件写能力。
  bool get capabilityProbed => supportsConditionalWrite != null;
}

/// 一条待同步的本地变更。
final class PendingChange {
  /// 构造变更。
  const PendingChange({
    required this.entityKind,
    required this.entityKey,
    required this.fieldName,
    required this.revision,
    required this.changedAt,
  });

  /// 实体类别（见 SyncEntityKind）。
  final String entityKind;

  /// 实体键（跨设备稳定）。
  final String entityKey;

  /// 字段名；空串表示整行变更。
  final String fieldName;

  /// 所属本地修订号。
  final int revision;

  /// 记录时刻（UTC）。
  final DateTime changedAt;
}

/// 一条墓碑。
final class SyncTombstone {
  /// 构造墓碑。
  const SyncTombstone({
    required this.entityKind,
    required this.entityKey,
    required this.deletedAt,
    required this.revision,
    required this.displayName,
  });

  /// 实体类别（见 SyncEntityKind）。
  final String entityKind;

  /// 实体键。
  final String entityKey;

  /// 删除时刻（UTC；仅作展示与诊断，不用于判定先后）。
  final DateTime deletedAt;

  /// 记录时的本地修订号。
  final int revision;

  /// 删除时的显示名快照。
  final String? displayName;
}

/// 远端到达的一篇文章状态（架构 5.1 的 ArticleState）。
final class RemoteArticleState {
  /// 构造状态。
  const RemoteArticleState({
    required this.feedSyncId,
    required this.remoteKey,
    required this.readingState,
    required this.favorite,
    this.deleted = false,
    this.revision = 0,
    this.title,
    this.guid,
    this.normalizedLink,
    this.fallbackFingerprint,
    this.publishedAt,
  });

  /// 所属订阅的跨设备标识（对齐后使用）。
  final String feedSyncId;

  /// 远端算出的文章同步键（本机据此派生占位键）。
  final String remoteKey;

  /// 阅读状态（三态之一）。
  final ReadingState readingState;

  /// 收藏。
  final bool favorite;

  /// 远端认为这篇文章已被删除（墓碑）。
  final bool deleted;

  /// 远端修订号（本机用于「不变则不写」的判定）。
  final int revision;

  /// 标题（仅占位行需要，用于让用户认出「这是哪一篇」）；没有则为 null。
  final String? title;

  /// 远端带上的身份证据（可缺省；占位行不需要）。
  final String? guid;

  /// 规范化链接（同上）。
  final String? normalizedLink;

  /// 兜底指纹（同上）。
  final String? fallbackFingerprint;

  /// 发布时间（UTC；仅用于展示排序）。
  final DateTime? publishedAt;
}

/// 一次远端状态应用的结果。
final class RemoteStateOutcome {
  /// 构造结果。
  const RemoteStateOutcome({
    required this.action,
    required this.localArticleId,
    required this.identityBasis,
  });

  /// 本次做的动作（见 [SyncRemoteStateAction]）。
  final SyncRemoteStateAction action;

  /// 本机文章 id（新建占位行时是新 id）。
  final int localArticleId;

  /// 本机这一行最终的判定依据。
  final IdentityBasis identityBasis;

  /// 是否新建了占位行。
  bool get createdPlaceholder =>
      action == SyncRemoteStateAction.createPlaceholder;
}

/// 同步状态与协议元数据的读写端口。
abstract interface class SyncStore {
  /// 读本机同步基线；库里没有任何行时返回全空基线（而不是失败）。
  Future<Result<SyncBaseline>> readBaseline();

  /// 写设备名（SET-070 的「设备名可改」）。
  Future<Result<void>> writeDeviceName(String deviceName);

  /// 写条件写能力探测结果（T042）。[probedAt] 由调用方给出，便于测试用假时钟。
  Future<Result<void>> writeCapability({
    required bool supportsConditionalWrite,
    required DateTime probedAt,
  });

  /// 推进本地修订号并返回新值（每次记录一批改动前调用一次）。
  Future<Result<int>> bumpRevision();

  /// 记录一批本地变更（同实体同字段只有一条，字段名空串表示整行）。
  Future<Result<void>> recordPendingChanges(List<PendingChange> changes);

  /// 读「≤ [revision]」的待同步变更（同步开始时固定变更集合的依据）。
  Future<Result<List<PendingChange>>> pendingChangesUpTo(int revision);

  /// 确认已上传：只清除「≤ [revision]」的待同步行（架构 5.2 的确认语义）。
  Future<Result<int>> confirmPendingUpTo(int revision);

  /// 记录墓碑（同实体同键幂等：已存在则保留原行）。
  Future<Result<void>> recordTombstone(SyncTombstone tombstone);

  /// 列举墓碑（可按实体类别过滤；null 表示不过滤）。
  Future<Result<List<SyncTombstone>>> listTombstones({String? entityKind});

  /// 该实体键是否已有墓碑（「已删除条目不复活」的判定入口）。
  Future<Result<bool>> hasTombstone({
    required String entityKind,
    required String entityKey,
  });

  /// 写同步成功的结果：基线版本、已确认修订的上界与成功时刻。
  Future<Result<void>> recordSyncSuccess({
    required String baseVersion,
    required int confirmedRevision,
    required DateTime syncedAt,
  });

  /// 写订阅对齐别名（已存在则忽略）。
  Future<Result<void>> saveFeedAlias({
    required String syncId,
    required int localFeedId,
  });

  /// 读全部别名。
  Future<Result<List<SyncFeedAlias>>> loadFeedAliases();

  /// 应用一条远端文章状态（本机没有该文章时落**占位行**）。
  Future<Result<RemoteStateOutcome>> applyRemoteArticleState(
    RemoteArticleState state,
  );
}

/// 一条**本机产生的**删除事实（T045；架构 5.2「删除操作元数据」）。
///
/// 为什么不是直接复用 [SyncDeletion]：那个类型是**快照里的形态**（键、显示名、修订号），
/// 而这里是「要往本机记什么」——它多带一个 [keepFavorites]，并且不带修订号（修订号由
/// 记录动作自己分配，外部给一个数字只会让「谁才是当前修订」有两个来源）。
final class SyncDeletionFact {
  /// 构造删除事实。
  const SyncDeletionFact({
    required this.entityKind,
    required this.entityKey,
    required this.displayName,
    this.keepFavorites,
  });

  /// 实体类别（见 SyncEntityKind；本机目前只有 feed / group 会产生删除）。
  final String entityKind;

  /// 跨设备稳定标识（订阅/分组的 syncId；**绝不用本机自增 id**）。
  final String entityKey;

  /// 删除时的显示名（让别的设备能说明「删的是哪一个」）。
  final String displayName;

  /// 删除时是否选择保留收藏；null 表示该删除不涉及这个选择。
  ///
  /// 这是架构 5.2「删除订阅的保留收藏选择进入同步操作元数据」的落点：别的设备应用这次
  /// 删除**之前**必须能展示它的破坏性影响，因此这个选择随删除事实一起传播，而不是各设备
  /// 按自己的默认值处理（那会让一边说「留下 3 篇收藏」另一边删光）。
  final bool? keepFavorites;
}
