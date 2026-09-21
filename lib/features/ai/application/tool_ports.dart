// 受控工具的外部端口（T032）。
//
// 为什么把「抓网页」与「看图」做成端口而不是让执行器直接调用 T024/T021 的实现：
//   - 那两个能力住在 features/articles 与 infrastructure（架构 2.2 的依赖方向：features
//     不得 import infrastructure），而工具执行器住在 features/ai；
//   - 更重要的是**它们各自带一套安全链**（地址守卫 + DNS 解析后复检 + 逐跳校验 +
//     体积/解压上限；图片还有 MIME 白名单 + 魔数 + 解码像素上限）。执行器只消费
//     「已经过完整校验的产物」，不重复实现第二套判据——判据写两份必然漂移，而漂移的
//     后果是「订阅抓取挡住了、工具抓取没挡住」。
//
// 默认实现一律**抛错**（与 ai_ports 的其余端口一致）：漏接线必须立刻暴露，而不是
// 退化成一个静默的空实现，把「已抓取」演得像真的。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flux/core/core.dart';

/// 单材料预算的设置读取端口（窄接口；由组合根把 SettingsStore 接上来）。
///
/// 定义在端口文件而不是执行器文件：执行器要 import 端口（它消费端口），反向会让
/// 「谁依赖谁」出现环。端口文件只声明能力，不知道谁实现。
abstract interface class ToolBudgetSettings {
  /// 读取 SET-061（单材料文本预算）。
  Future<Object?> readSingleMaterialBudget();
}

/// 一次受控网页抓取的结果（已清洗为文本）。
final class FetchedPage {
  /// 构造结果。
  const FetchedPage({
    required this.finalUri,
    required this.title,
    required this.text,
    required this.imageUrls,
    required this.outcome,
  });

  /// 最终地址（跟随重定向之后；已脱敏）。
  final String finalUri;

  /// 标题（可能为空）。
  final String title;

  /// 清洗后的正文文本（**未按 SET-061 截断**；截断由执行器按单材料预算做，
  /// 因为预算是任务级参数，而抓取层不该知道 prompt 预算）。
  final String text;

  /// 正文里的图片地址（**未下载**，只是引用；执行器据此注册材料）。
  final List<String> imageUrls;

  /// 抽取结论标识（ok / empty / noContent）；由适配器从 T024 的枚举映射而来，
  /// 用字符串是为了不让 features/ai 依赖 features/articles 的枚举。
  final String outcome;
}

/// 受控网页抓取端口。
///
/// 实现必须复用 T024 的安全链（地址守卫 → DNS 解析后复检 → 逐跳重定向校验 →
/// 体积/解压上限 → 受控清洗），并以 [Result] 返回类型化失败。
abstract interface class ControlledPageFetcher {
  /// 抓取并清洗 [uri] 指向的网页。
  Future<Result<FetchedPage>> fetch(Uri uri);
}

/// 一张材料的图片元数据（已过 MIME/体积/魔数校验）。
final class InspectedImage {
  /// 构造结果。
  const InspectedImage({
    required this.mimeType,
    required this.width,
    required this.height,
    required this.byteLength,
  });

  /// MIME（由魔数嗅探并与其他声明交叉校验后的类型）。
  final String mimeType;

  /// 宽（像素）。
  final int width;

  /// 高（像素）。
  final int height;

  /// 字节数。
  final int byteLength;
}

/// 受控图片查看端口。
///
/// 只接受**客户端给出的地址**（执行器已用材料集合判定过），实现复用 T021 的
/// MIME/体积/魔数校验与地址守卫。本端口**不做视觉分析**（属 T033）。
abstract interface class ToolImageInspector {
  /// 查看 [url] 指向的图片，返回元数据。
  Future<Result<InspectedImage>> inspect(String url);
}

/// 一次视觉分析的产出（T033：inspectImage 的真正分析）。
final class VisionAnalysisResult {
  /// 构造产出。
  const VisionAnalysisResult({
    this.description,
    this.skippedReason,
    this.error,
    this.downsampled = false,
    this.endpoint,
  });

  /// 分析文本；被跳过或失败时为 null。
  final String? description;

  /// 跳过原因（**不是失败**）：没有视觉模型、图像分析开关关闭、需要用户先确认发送。
  final VisionSkipKind? skippedReason;

  /// 失败原因（已经决定要发之后发生的失败）。
  final AppError? error;

  /// 这张图是否降采样后送出。
  final bool downsampled;

  /// 实际接收端点（界面与回填文本都用它说明「发给了谁」）。
  final String? endpoint;

  /// 是否拿到了可用的分析文本。
  bool get ok => description != null && description!.isNotEmpty;

  /// 是否因为「跳过」而没有分析（与失败区分：跳过不该被画成错误）。
  bool get skipped => skippedReason != null;
}

/// 跳过视觉分析的原因（T033）。
///
/// 与 domain 的 VisionSkipReason 分开：那个回答「为什么没有可用的视觉模型」，这个回答
/// 「这次调用为什么没有产出分析」——后者还包含「开关关闭」与「等待用户确认发送」这两件与
/// 模型能力无关的事。合成一个枚举会让界面必须对同一个取值做两种解释。
enum VisionSkipKind {
  /// 没有可用的视觉模型（架构 4.3 的「跳过图像分析并明确标签」）。
  noVisionModel,

  /// SET-065 的图像分析开关关闭。
  disabledBySetting,

  /// 该端点还没有本机的首次发送告知确认（架构第 8 节）。
  awaitingConsent,

  /// 这张图拿不到（加载/校验失败）。
  imageUnavailable,
}

/// 受控视觉分析端口（T033）。
///
/// 执行器只依赖这个窄接口，不直接持有 VisualRouter：
///   - 路由与限额规则在 features/ai/domain 里是纯函数、在 application 里是组装，
///     tool_executor 只应该关心「给我这张图的分析结果」；
///   - 端口让 T032 的既有用例与 T033 的新用例可以在**同一份执行器代码**上分别验证。
abstract interface class ToolVisionAnalyzer {
  /// 分析 [url] 指向的图片；[imageRef] 是客户端材料引用（回填与诊断用）。
  ///
  /// 实现必须遵守：没有视觉模型时返回 skippedReason 而**不是**抛错；一张图失败不影响
  /// 其它图；需要首次发送告知时返回 awaitingConsent 且**一个字节都不发**。
  Future<Result<VisionAnalysisResult>> analyze({
    required String imageRef,
    required String url,
  });
}

/// 受控网页抓取端口 Provider。
final Provider<ControlledPageFetcher> controlledPageFetcherProvider =
    Provider<ControlledPageFetcher>(
      (Ref ref) => throw StateError(
        'controlledPageFetcherProvider 未被组合根覆盖：见 lib/app/app_providers.dart',
      ),
    );

/// 受控图片查看端口 Provider。
final Provider<ToolImageInspector> toolImageInspectorProvider =
    Provider<ToolImageInspector>(
      (Ref ref) => throw StateError(
        'toolImageInspectorProvider 未被组合根覆盖：见 lib/app/app_providers.dart',
      ),
    );

/// 单材料预算设置端口（SET-061；由组合根接上 SettingsStore）。
final Provider<ToolBudgetSettings?> toolBudgetSettingsProvider =
    Provider<ToolBudgetSettings?>((Ref ref) => null);
