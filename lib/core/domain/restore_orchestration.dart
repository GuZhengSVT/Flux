// 恢复编排的**纯规则**（T048；架构 5.3「恢复默认到新数据目录……正式切换前再次确认」）。
//
// T046 交付的是「恢复到新目录 + 校验通过 + 返回新目录路径」，而**把运行时数据目录指过去**是
// 另一件事：它要跨一次进程重启，且中途失败必须能回退。这个文件定义那次编排的状态机与判定，
// 具体文件操作用例（重命名/删除）由基础设施实现。
//
// 数据目录切换的**原子性从哪来**：两个目录之间的搬移不是一次原子操作，因此这里用「先停旧、
// 再上新、失败就搬回来」的三步加一个**持久化标记**表达。标记写在数据目录的**父目录**（不是
// 数据目录内部）——把标记写在数据目录里会让「数据目录被改名」这一步顺带把标记也搬走，而它
// 恰恰要在搬移过程中一直可见。
//
// 为什么需要标记而不是「重启时看看有没有 -restored- 目录」：那种猜法无法区分「用户还没重启」
// 与「用户已经切换过、只是旧目录还没删」，也无法表达「上次切换失败、需要报告」。标记是那次
// 恢复**意图**的唯一载体。
library;

import 'dart:convert';

/// 恢复编排的阶段。
///
/// 三个阶段就是那次恢复意图的完整生命周期：
///   * [pendingRestart]：已恢复到新目录并校验通过，等重启后切换（**旧目录仍是当前数据**）；
///   * [switched]：切换已完成（新目录已是当前数据），旧目录还留着等用户确认后删除；
///   * [cleaned]：旧目录已删除，这次恢复彻底完成（标记随后被删掉）。
enum RestorePhase { pendingRestart, switched, cleaned }

/// 一个恢复编排标记。
final class RestoreMarker {
  /// 构造标记。
  const RestoreMarker({
    required this.phase,
    required this.restoredDirectory,
    required this.restoredAt,
    this.supersededDirectory,
    this.schemaVersion,
  });

  /// 当前阶段。
  final RestorePhase phase;

  /// 恢复出来的目录（将被切换为当前数据目录）。
  final String restoredDirectory;

  /// 这次恢复发生的时刻（UTC；只作展示与诊断）。
  final DateTime restoredAt;

  /// 被顶替的旧数据目录；切换前为 null，切换后指向那个待删除的目录。
  final String? supersededDirectory;

  /// 备份声明的 schema 版本（展示用）。
  final int? schemaVersion;

  /// 标记的文件名（写在数据目录的**父目录**）。
  static const String fileName = 'restore-pending.json';

  /// 序列化为规范 JSON（字段顺序固定，便于人工阅读与 diff）。
  String encode() =>
      const JsonEncoder.withIndent('  ').convert(<String, Object?>{
        'phase': phase.name,
        'restoredDirectory': restoredDirectory,
        'restoredAt': restoredAt.toUtc().toIso8601String(),
        'supersededDirectory': supersededDirectory,
        'schemaVersion': schemaVersion,
      });

  /// 解析标记 JSON。
  ///
  /// 任何字段缺失/类型不对/阶段名不认识都返回 null（调用方按「没有待编排的恢复」处理），
  /// 而不是用默认值凑一个：一个凑出来的标记会让应用在启动时把数据目录切到一个不存在的位置
  /// （最坏情况是「启动后什么都看不到」）。宁可当作没有恢复任务——用户的数据目录保持原样。
  static RestoreMarker? decode(String text) {
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, Object?>) {
      return null;
    }
    final Object? phaseName = decoded['phase'];
    final Object? restoredDirectory = decoded['restoredDirectory'];
    final Object? restoredAt = decoded['restoredAt'];
    if (phaseName is! String ||
        restoredDirectory is! String ||
        restoredDirectory.isEmpty ||
        restoredAt is! String) {
      return null;
    }
    RestorePhase? phase;
    for (final RestorePhase candidate in RestorePhase.values) {
      if (candidate.name == phaseName) {
        phase = candidate;
        break;
      }
    }
    if (phase == null) {
      return null;
    }
    final DateTime? at = DateTime.tryParse(restoredAt);
    if (at == null) {
      return null;
    }
    final Object? superseded = decoded['supersededDirectory'];
    final Object? schema = decoded['schemaVersion'];
    return RestoreMarker(
      phase: phase,
      restoredDirectory: restoredDirectory,
      restoredAt: at.toUtc(),
      supersededDirectory: superseded is String && superseded.isNotEmpty
          ? superseded
          : null,
      schemaVersion: schema is int ? schema : null,
    );
  }

  /// 复制并覆盖部分字段。
  RestoreMarker copyWith({RestorePhase? phase, String? supersededDirectory}) =>
      RestoreMarker(
        phase: phase ?? this.phase,
        restoredDirectory: restoredDirectory,
        restoredAt: restoredAt,
        supersededDirectory: supersededDirectory ?? this.supersededDirectory,
        schemaVersion: schemaVersion,
      );
}

/// 启动时应该做的那一步。
enum RestoreAction {
  /// 没有待编排的恢复（或标记已失效）：什么都不做。
  nothingToDo,

  /// 把数据目录切到恢复出来的那一份。
  switchToRestored,

  /// 已经切换过，等用户确认后删除旧目录（本阶段只展示状态）。
  awaitCleanupConfirmation,

  /// 丢弃标记并报告失败：恢复出来的目录不可用，**保持当前数据目录不变**。
  dropMarkerAndReport,
}

/// 启动时的编排判定（纯函数）。
///
/// 判定只看四个事实：标记内容、当前数据目录、恢复目录是否存在、恢复目录是否是一个**能打开
/// 的库**。最后一条必须由调用方真的打开一次得出（T046 的 verifyRestoredData 已经在恢复时做过
/// 一次，但两次检查之间用户可能删掉或改动了那个目录——启动时重做一次，代价是一次打开，收益
/// 是「不会在切换之后才发现它坏了」，而那时旧目录已被顶替）。
RestoreAction decideRestoreAction({
  required RestoreMarker? marker,
  required String currentDataDirectory,
  required bool restoredDirectoryExists,
  required bool restoredDatabaseUsable,
}) {
  if (marker == null) {
    return RestoreAction.nothingToDo;
  }
  switch (marker.phase) {
    case RestorePhase.cleaned:
      // 罕见但必须处理：清理完成后标记本应被删掉。残留的 cleaned 标记没有待办事项，
      // 按「无事可做」处理（丢弃它由调用方完成）。
      return RestoreAction.nothingToDo;
    case RestorePhase.switched:
      // 已经切换过：**绝不能**再切一次（那会把当前正在用的目录搬到别处）。
      return RestoreAction.awaitCleanupConfirmation;
    case RestorePhase.pendingRestart:
      if (!restoredDirectoryExists) {
        return RestoreAction.dropMarkerAndReport;
      }
      if (!restoredDatabaseUsable) {
        return RestoreAction.dropMarkerAndReport;
      }
      // 恢复目录就是当前数据目录本身：说明这次恢复的目标与当前数据是同一处（不可能由本工程
      // 产生，但手工摆弄过标记时可能出现）。再「切换」一次等于把一个目录搬到它自己上面，
      // 因此按无事可做处理并丢弃标记。
      if (_samePath(marker.restoredDirectory, currentDataDirectory)) {
        return RestoreAction.nothingToDo;
      }
      return RestoreAction.switchToRestored;
  }
}

/// 一次切换的结论。
enum RestoreSwitchOutcome {
  /// 切换成功（数据目录已指向恢复出来的那一份）。
  switched,

  /// 切换失败但**已回退**：当前数据目录仍是切换前的那一份。
  rolledBack,
}

/// 切换失败与回退的原因（稳定类别名，供界面与诊断展示）。
abstract final class RestoreFailureKind {
  /// 恢复目录不存在。
  static const String restoredDirectoryMissing = 'restoredDirectoryMissing';

  /// 恢复目录不是一个能打开的库。
  static const String restoredDatabaseUnusable = 'restoredDatabaseUnusable';

  /// 停放旧目录失败（切换的第 1 步）。
  static const String parkCurrentFailed = 'parkCurrentFailed';

  /// 启用新目录失败（切换的第 2 步）；此时已回退。
  static const String activateRestoredFailed = 'activateRestoredFailed';

  /// 回退本身也失败（数据目录停在停放位置，需要人工处理）。
  static const String rollbackFailed = 'rollbackFailed';
}

/// 编排状态（界面展示用；不含任何路径以外的信息）。
final class RestoreOrchestrationState {
  /// 构造状态。
  const RestoreOrchestrationState({
    required this.phase,
    this.restoredDirectory,
    this.supersededDirectory,
    this.restoredAt,
    this.failureKind,
  });

  /// 无待编排恢复。
  static const RestoreOrchestrationState idle = RestoreOrchestrationState(
    phase: null,
  );

  /// 当前阶段；null 表示没有待编排的恢复。
  final RestorePhase? phase;

  /// 恢复出来的目录。
  final String? restoredDirectory;

  /// 被顶替的旧目录（切换后才有）。
  final String? supersededDirectory;

  /// 恢复时刻。
  final DateTime? restoredAt;

  /// 最近一次编排失败的原因（稳定类别名）；成功时为 null。
  final String? failureKind;

  /// 是否有待用户确认的旧目录清理。
  bool get needsCleanupConfirmation =>
      phase == RestorePhase.switched && supersededDirectory != null;

  /// 是否有待重启生效的恢复。
  bool get pendingRestart => phase == RestorePhase.pendingRestart;
}

/// 两个路径是否指向同一处（按规范化后的路径比较）。
///
/// 只做**字面**比较（去掉末尾分隔符、统一分隔符），不解析软链接、不碰文件系统：这个判定用在
/// 「要不要把一个目录搬到另一个位置」上，误判为「相同」只会让一次恢复不生效（用户看到的是
/// 「重启后数据没变」，可解释）；而误判为「不同」会让应用把数据目录停放到别处，风险大得多。
bool _samePath(String a, String b) => _normalize(a) == _normalize(b);

String _normalize(String path) {
  String value = path.replaceAll('\\', '/');
  while (value.length > 1 && value.endsWith('/')) {
    value = value.substring(0, value.length - 1);
  }
  return value;
}
