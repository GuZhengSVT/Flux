// 模型引用检查（T025；「设置验证/删除引用不悬空」）。
//
// 为什么删除模型要先查引用：一个模型可能被三处配置指向，而这三处都**不会**
// 因为模型被删而自动更新：
//   - 本机「任务默认模型」标记（模型记录自身的字段）；
//   - SET-034 专用视觉模型（按别名）；
//   - SET-035 故障转移允许列表（按别名）。
// 直接删掉之后，这三处会指向一个不存在的模型：视觉任务要到运行时才发现没有可用
// 模型，故障转移列表会少一个候选却没有任何提示——用户只会看到「总结失败」，找不到原因。
//
// 因此删除是**两段式**：先算出引用并展示给用户，用户确认后带 force 再删。
// 这里只产出「谁引用了它」，不产出界面文案（文案走 l10n，见 presentation）。
library;

/// 引用类型。
enum ModelReferenceKind {
  /// 本机「任务默认模型」。
  defaultForTasks,

  /// SET-034 专用视觉模型。
  visionModel,

  /// SET-035 故障转移允许列表。
  failoverAllowList,
}

/// 一条引用。
final class ModelReference {
  /// 构造引用。
  const ModelReference({required this.kind, this.settingId});

  /// 引用类型。
  final ModelReferenceKind kind;

  /// 对应的设置编号（`SET-034` / `SET-035`）；本表字段的引用为 null。
  final String? settingId;

  /// 供日志与测试使用的稳定描述（不是界面文案）。
  String describe() =>
      settingId == null ? kind.name : '${kind.name}($settingId)';

  @override
  bool operator ==(Object other) =>
      other is ModelReference &&
      other.kind == kind &&
      other.settingId == settingId;

  @override
  int get hashCode => Object.hash(kind, settingId);

  @override
  String toString() => describe();
}

/// 视任务默认与视觉/故障转移配置算出某个别名被哪些地方引用。
///
/// 输入是**已读取的值**而不是「去读设置」的回调：这样这条判断是纯函数，可以被
/// 穷尽覆盖，也不必在单元测试里搭一个设置存储。
///
/// [visionModelAlias] 为 SET-034 的已存值（空串/null 表示未设置）；
/// [failoverAllowList] 为 SET-035 的 allowedModels 列表。
List<ModelReference> referencesToAlias({
  required String alias,
  required bool isDefaultForTasks,
  required String? visionModelAlias,
  required List<String> failoverAllowList,
}) {
  return <ModelReference>[
    if (isDefaultForTasks)
      const ModelReference(kind: ModelReferenceKind.defaultForTasks),
    if (visionModelAlias != null &&
        visionModelAlias.isNotEmpty &&
        visionModelAlias == alias)
      const ModelReference(
        kind: ModelReferenceKind.visionModel,
        settingId: 'SET-034',
      ),
    if (failoverAllowList.contains(alias))
      const ModelReference(
        kind: ModelReferenceKind.failoverAllowList,
        settingId: 'SET-035',
      ),
  ];
}
