// 视觉路由与图像输入限制（T033；架构 4.3「视觉用于理解新闻图片和静态网页中的图片。
// 优先指定视觉模型，其次有视觉能力的主模型；均无视觉能力时跳过图像分析并明确标签，
// 文本搜索/抓取/总结仍正常工作」、SET-034、SET-065）。
//
// 为什么路由与图像限制是**纯函数**放在 domain：
//   1) 「专用视觉模型 → 有视觉能力的主模型 → 跳过」这条顺序是架构条文，它的正确性必须
//      能被逐条断言（专用模型被停用怎么办、专用模型没声明视觉能力怎么办），而把它藏在
//      一个要读设置、读模型表、下载图片的用例里，就只能靠构造一整套替身去间接验证；
//   2) 「单图 4 MiB / 最多 6 张」是**数据出境与费用的边界**（SET-065），不是界面细节：
//      超限时是降采样还是丢弃、降采样标记如何传递，都应该在没有 IO 的地方就能测清楚。
//
// 本文件不下载、不编码、不读设置：它只回答「用哪个模型」与「这几张图怎么处理」。
library;

import 'ai_model.dart';
import 'model_capability.dart';

/// 视觉路由的结论。
sealed class VisionRoute {
  /// 构造结论。
  const VisionRoute();
}

/// 使用 SET-034 明确指定的专用视觉模型。
final class VisionRouteDedicated extends VisionRoute {
  /// 构造结论。
  const VisionRouteDedicated({required this.model});

  /// 承担视觉分析的模型。
  final AiModel model;
}

/// 回退到**有视觉能力的主模型**（故障转移排序里的第一个）。
final class VisionRoutePrimary extends VisionRoute {
  /// 构造结论。
  const VisionRoutePrimary({required this.model, this.note});

  /// 承担视觉分析的模型。
  final AiModel model;

  /// 结构性备注（为什么没走专用模型：未设置 / 已停用 / 未声明视觉能力）。
  ///
  /// 分开记而不是只说「回退到主模型」：这三种原因的**下一步动作**不同——未设置要用户
  /// 去配 SET-034，已停用要去启用，未声明能力要去改能力声明。合成一句话会让用户面对一个
  /// 「为什么没用我指定的模型」却无处着手的状态。
  final String? note;
}

/// 跳过图像分析（**不是失败**）。
final class VisionRouteSkip extends VisionRoute {
  /// 构造结论。
  const VisionRouteSkip({required this.reason, this.note});

  /// 跳过原因。
  final VisionSkipReason reason;

  /// 结构性备注。
  final String? note;
}

/// 跳过图像分析的原因（类型化，供界面给出可行动的说明）。
enum VisionSkipReason {
  /// 没有任何启用模型声明了视觉能力（架构 4.3 的「均无视觉能力时跳过」）。
  noVisionModel,

  /// SET-034 指定的别名在本机不存在（模型被删了，或设置是另一台设备同步来的）。
  dedicatedModelMissing,

  /// SET-034 指定的模型没有声明视觉能力（配置自相矛盾，不猜用户的意图）。
  dedicatedModelLacksVision,
}

/// 选择视觉路由（架构 4.3 的优先级）。
///
/// [enabledModels] 必须已是**启用中的模型**，且按故障转移顺序排列（调用方用
/// ModelManager.loadEnabledModels 取）。本函数不排序：排序有两个来源时，「顺序」会变成
/// 一个没人能确定的事实。
///
/// [dedicatedAlias] 是 SET-034 的值（未设置为 null 或空串）。
VisionRoute selectVisionRoute({
  required List<AiModel> enabledModels,
  String? dedicatedAlias,
}) {
  final String? alias = dedicatedAlias?.trim();
  if (alias != null && alias.isNotEmpty) {
    final AiModel? dedicated = _findByAlias(enabledModels, alias);
    if (dedicated == null) {
      // 指定的模型在本机不可用：**继续往下走**而不是终止，因为「优先」不等于「只能」。
      // 但要把原因带到结论里，否则用户会以为专用模型生效了。
      return _fallbackToPrimary(
        enabledModels,
        note: 'SET-034 指定的「$alias」不在启用模型中（可能已删除或未启用）',
        skipReason: VisionSkipReason.dedicatedModelMissing,
      );
    }
    if (!dedicated.capability.vision) {
      // 指定的模型没声明视觉能力：不按名字猜（架构 4.3 明确禁止按模型名推断能力），
      // 否则「用户填了一个纯文本模型」会变成一次注定失败的请求并真实计费。
      return _fallbackToPrimary(
        enabledModels,
        note: 'SET-034 指定的「$alias」未声明视觉能力',
        skipReason: VisionSkipReason.dedicatedModelLacksVision,
      );
    }
    return VisionRouteDedicated(model: dedicated);
  }
  return _fallbackToPrimary(enabledModels, note: null);
}

/// 回退到有视觉能力的主模型；一个都没有时给出「跳过」。
///
/// 注意这里**不**回退到「第一个启用模型」：一个没声明视觉能力的模型收到图片分量时，
/// 协议层通常直接报错（400），而用户看到的会是一条与「图片」无关的错误信息。跳过并明确
/// 标注（架构 4.3）比让链路失败更符合「文本链路继续工作」这条要求。
VisionRoute _fallbackToPrimary(
  List<AiModel> enabledModels, {
  required String? note,
  VisionSkipReason skipReason = VisionSkipReason.noVisionModel,
}) {
  for (final AiModel model in enabledModels) {
    if (model.capability.vision) {
      return VisionRoutePrimary(model: model, note: note);
    }
  }
  return VisionRouteSkip(reason: skipReason, note: note);
}

AiModel? _findByAlias(List<AiModel> models, String alias) {
  for (final AiModel model in models) {
    if (model.alias == alias) {
      return model;
    }
  }
  return null;
}

/// 视觉模型的**主模型**判断（架构 4.3「其次有视觉能力的主模型」）。
///
/// 单列一个函数而不是在路由里内联：界面与诊断也需要回答同一个问题（「我现在配的模型
/// 到底能不能看图」），两处各写一遍会让答案不一致。
bool hasVisionCapableModel(List<AiModel> enabledModels) =>
    enabledModels.any((AiModel model) => model.capability.vision);

/// 视觉所需的能力要求（供故障转移候选筛选复用）。
const CapabilityRequirement visionCapabilityRequirement =
    CapabilityRequirement.vision;

/// 图像输入限制（SET-065：图像分析开关 / 最多图片 6 / 单图上传上限 4 MiB）。
final class ImageInputLimits {
  /// 构造限制。
  const ImageInputLimits({
    this.enabled = true,
    this.maxImages = 6,
    this.maxImageMiB = 4,
  });

  /// 是否允许把图片发给视觉模型（SET-065 的开关）。
  ///
  /// 关闭时**不是**报错，而是把整批图片标成跳过：图片分析是可选能力，
  /// 关闭它不该让一次新闻任务失败（架构 4.3）。
  final bool enabled;

  /// 一次最多发送几张图（SET-065 默认 6）。
  final int maxImages;

  /// 单张图片的 MiB 上限（SET-065 默认 4）。
  final int maxImageMiB;

  /// 单张图片的字节上限（换算后）。
  int get maxImageBytes => maxImageMiB * 1024 * 1024;

  /// 从设置值构造；结构不符时逐项回退注册表默认值。
  ///
  /// 逐项回退而不是整项放弃：一个只有数量上限写坏的复合值，不该让「单图上限」也一起
  /// 失效（那会把一次 4 MiB 的图片变成一次无限制的上传）。
  static ImageInputLimits fromSetting(Object? raw) {
    const ImageInputLimits fallback = ImageInputLimits();
    if (raw is! Map<Object?, Object?>) {
      return fallback;
    }
    final Object? enabled = raw['enabled'];
    final Object? maxImages = raw['maxImages'];
    final Object? maxMiB = raw['maxImageMiB'];
    return ImageInputLimits(
      enabled: enabled is bool ? enabled : fallback.enabled,
      // 至少 1：0 张会让「图像分析开着」变成一个永远什么都不做的功能。
      maxImages: maxImages is int && maxImages > 0
          ? maxImages
          : fallback.maxImages,
      maxImageMiB: maxMiB is int && maxMiB > 0 ? maxMiB : fallback.maxImageMiB,
    );
  }
}

/// 一张候选图片的**已知信息**（尚未下载）。
final class ImageCandidateInfo {
  /// 构造候选。
  const ImageCandidateInfo({required this.ref, this.byteLength, this.mimeType});

  /// 客户端材料引用（模型看到的短标识）。
  final String ref;

  /// 已声明的字节数；null 表示未知（例如正文里的一行 Markdown 图片）。
  final int? byteLength;

  /// 已声明的 MIME；null 表示未知。
  final String? mimeType;
}

/// 一张图片的处理决定。
final class ImageInputDecision {
  /// 构造决定。
  const ImageInputDecision({
    required this.candidate,
    required this.accepted,
    this.downsample = false,
    this.skipDetail,
  });

  /// 对应的候选。
  final ImageCandidateInfo candidate;

  /// 是否纳入本次请求。
  final bool accepted;

  /// 是否需要在发送前降采样（超过 SET-065 的单图上限）。
  ///
  /// **降采样而不是丢弃**：SET-065 与架构 4.3 的口径是「能力不足/超限时要说清楚」，
  /// 而不是静默少给一张图。用户看到「这张图缩过后送出的」比看到「你的图被忽略了」
  /// 有用得多。
  final bool downsample;

  /// 未被纳入的原因（仅 [accepted] 为假时有值）。
  final ImageInputSkip? skipDetail;
}

/// 一张图片被跳过的原因。
enum ImageInputSkip {
  /// SET-065 的图像分析开关关闭。
  disabled,

  /// 超过本次最多图片数（SET-065 的 6）。
  overCountLimit,
}

/// 一次图像输入规划的结果。
final class ImageInputPlan {
  /// 构造结果。
  const ImageInputPlan({
    required this.decisions,
    required this.truncatedByCount,
  });

  /// 全部候选的处理决定（顺序与输入一致）。
  final List<ImageInputDecision> decisions;

  /// 是否有图片因为数量上限被舍弃。
  final bool truncatedByCount;

  /// 纳入本次请求的候选（顺序保持）。
  List<ImageInputDecision> get accepted => decisions
      .where((ImageInputDecision d) => d.accepted)
      .toList(growable: false);

  /// 需要降采样的张数。
  int get downsampleCount =>
      accepted.where((ImageInputDecision d) => d.downsample).length;

  /// 是否一张都没有纳入。
  bool get isEmpty => accepted.isEmpty;
}

/// 按 SET-065 规划一次图像输入（纯函数）。
///
/// 三条规则，顺序固定：
///   1) 开关关闭 → 全部跳过（原因 disabled），**不报错**；
///   2) 取前 [ImageInputLimits.maxImages] 张，其余标 overCountLimit 并置
///      [ImageInputPlan.truncatedByCount]；
///   3) 已知字节数超过单图上限的标 downsample（未知字节数不预先标，由下载后的实际
///      字节长度决定——在不知道大小时标「要降采样」会让一批正常大小的图被无谓重编码）。
ImageInputPlan planImageInputs({
  required List<ImageCandidateInfo> candidates,
  required ImageInputLimits limits,
}) {
  final List<ImageInputDecision> decisions = <ImageInputDecision>[];
  if (!limits.enabled) {
    for (final ImageCandidateInfo candidate in candidates) {
      decisions.add(
        ImageInputDecision(
          candidate: candidate,
          accepted: false,
          skipDetail: ImageInputSkip.disabled,
        ),
      );
    }
    return ImageInputPlan(
      decisions: List<ImageInputDecision>.unmodifiable(decisions),
      truncatedByCount: false,
    );
  }

  int acceptedCount = 0;
  bool truncated = false;
  for (final ImageCandidateInfo candidate in candidates) {
    if (acceptedCount >= limits.maxImages) {
      truncated = true;
      decisions.add(
        ImageInputDecision(
          candidate: candidate,
          accepted: false,
          skipDetail: ImageInputSkip.overCountLimit,
        ),
      );
      continue;
    }
    acceptedCount++;
    final int? bytes = candidate.byteLength;
    decisions.add(
      ImageInputDecision(
        candidate: candidate,
        accepted: true,
        downsample: bytes != null && bytes > limits.maxImageBytes,
      ),
    );
  }
  return ImageInputPlan(
    decisions: List<ImageInputDecision>.unmodifiable(decisions),
    truncatedByCount: truncated,
  );
}
