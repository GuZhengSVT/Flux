// 正文页的单图视觉分析（T033）。
//
// 与 application/visual_router.dart 的分工：
//   - VisualRouter 管「怎么发」（路由、限额、加载、告知闸门、真实调用）；
//   - 本文件管「正文里哪张图、用户看到什么、以及**跳过之后怎么善后**」。
//
// 三件这里才做的事：
//   1) **图片地址解析**：正文文档里的图片是渲染层解析出来的节点，而「这次到底分析哪一张」
//      必须由调用方（页面）明确指定，因此这里只接收 [imageUrl]；图片地址**不进请求**，
//      只用于本机受控加载；
//   2) **界面结局翻译**：把 VisualRouter 的产出翻成四种界面结局（成文 / 跳过 / 待确认 / 失败），
//      页面因此不需要任何 if 判断链；
//   3) **SET-065 开关关闭时的善后**：用户此刻明确点了一次「分析这张图」，把开关留在关闭状态
//      并只说一句「已关闭」是一种死循环（唯一出路是去设置页找到那个开关）。因此本用例把这次
//      动作视为打开开关并如实写回，再重跑一次；写失败不阻断分析。
library;

import 'package:flux/core/core.dart';

import 'package:flux/features/ai/application/tool_ports.dart';
import 'package:flux/features/ai/application/visual_router.dart';
import 'package:flux/features/ai/domain/ai_message.dart';
import 'package:flux/features/ai/domain/vision_consent.dart';

/// 正文单图分析的界面结局。
sealed class ArticleVisionInsight {
  /// 构造结局。
  const ArticleVisionInsight();
}

/// 拿到了描述。
final class ArticleVisionInsightText extends ArticleVisionInsight {
  /// 构造结局。
  const ArticleVisionInsightText({
    required this.text,
    required this.downsampled,
    this.endpoint,
  });

  /// 描述文本。
  final String text;

  /// 是否降采样后送出。
  final bool downsampled;

  /// 实际接收端点。
  final String? endpoint;
}

/// 跳过（**不是失败**）。
final class ArticleVisionInsightSkipped extends ArticleVisionInsight {
  /// 构造结局。
  const ArticleVisionInsightSkipped({required this.reason, this.detail});

  /// 跳过原因。
  final ArticleVisionSkipReason reason;

  /// 附加说明。
  final String? detail;
}

/// 需要用户先确认向该端点发送图片（架构第 8 节的首次发送告知）。
final class ArticleVisionInsightNeedsConsent extends ArticleVisionInsight {
  /// 构造结局。
  const ArticleVisionInsightNeedsConsent({required this.endpoint});

  /// 接收端点。
  final String endpoint;
}

/// 失败（已经决定要发之后发生的）。
final class ArticleVisionInsightFailed extends ArticleVisionInsight {
  /// 构造结局。
  const ArticleVisionInsightFailed({required this.error});

  /// 失败原因。
  final AppError error;
}

/// 跳过原因（界面文案按它取）。
enum ArticleVisionSkipReason {
  /// 没有可用的视觉模型（架构 4.3）。
  noVisionModel,

  /// SET-065 的图像分析开关关闭（且写回失败）。
  disabledBySetting,

  /// 正文里的这张图拿不到（加载/校验失败）。
  imageUnavailable,
}

/// 图像分析面板的状态（T033）。
sealed class VisionPanelState {
  /// 构造状态。
  const VisionPanelState();
}

/// 正在分析。
final class VisionPanelRunning extends VisionPanelState {
  /// 构造状态。
  const VisionPanelRunning({required this.imageRef});

  /// 正在分析的图片引用。
  final String imageRef;
}

/// 分析完成（成功、跳过或失败都由 [insight] 表达）。
final class VisionPanelResult extends VisionPanelState {
  /// 构造状态。
  const VisionPanelResult({required this.imageRef, required this.insight});

  /// 对应的图片引用。
  final String imageRef;

  /// 结局。
  final ArticleVisionInsight insight;
}

/// 正文单图分析用例。
final class ArticleVisionAnalyzer {
  /// 构造用例。
  const ArticleVisionAnalyzer({
    required this.analyzeImage,
    this.settingsWriter,
  });

  /// 单图分析用例（VisualRouter 的界面化包装）。
  final AnalyzeImageUseCase analyzeImage;

  /// 设置写入口（**只**用于开关关闭时的善后；见文件头第 3 条）。为 null 时不做善后。
  final Future<Result<void>> Function(bool enabled)? settingsWriter;

  /// 分析正文里的一张图。
  ///
  /// [confirmation] 非空表示用户刚刚在对话框上确认过（第二次调用）；[cancellation] 是
  /// 取消信号（取消**不改动正文**，也不丢弃已拿到的结论）。
  Future<ArticleVisionInsight> analyze({
    required String imageUrl,
    required String imageRef,
    VisionSendConfirmation? confirmation,
    AiCancellation? cancellation,
  }) async {
    if (imageUrl.trim().isEmpty) {
      return const ArticleVisionInsightSkipped(
        reason: ArticleVisionSkipReason.imageUnavailable,
        detail: '缺少图片地址',
      );
    }
    final VisionAnalysisView view = await analyzeImage(
      taskId: 'article-image-$imageRef',
      imageRef: imageRef,
      url: imageUrl,
      confirmation: confirmation,
      cancellation: cancellation,
    );
    return _translate(
      view,
      imageUrl: imageUrl,
      imageRef: imageRef,
      confirmation: confirmation,
      cancellation: cancellation,
    );
  }

  /// 把链路产出翻译成界面结局。
  Future<ArticleVisionInsight> _translate(
    VisionAnalysisView view, {
    required String imageUrl,
    required String imageRef,
    VisionSendConfirmation? confirmation,
    AiCancellation? cancellation,
  }) async {
    if (view.needsConsent) {
      return ArticleVisionInsightNeedsConsent(endpoint: view.consentEndpoint!);
    }
    if (view.hasDescription) {
      return ArticleVisionInsightText(
        text: view.description!,
        downsampled: view.downsampled,
        endpoint: view.endpoint,
      );
    }
    if (view.error != null) {
      // 图拿不到（Network/Storage）是「这张图分析不了」，与「链路失败」对用户是同一件事：
      // 都给一条可重试的失败说明，而不是把它画成需要改配置的跳过。
      if (view.skipKind == VisionSkipKind.imageUnavailable) {
        return ArticleVisionInsightSkipped(
          reason: ArticleVisionSkipReason.imageUnavailable,
          detail: view.error!.kind,
        );
      }
      return ArticleVisionInsightFailed(error: view.error!);
    }
    if (view.skipKind == VisionSkipKind.disabledBySetting) {
      final Future<Result<void>> Function(bool enabled)? writer =
          settingsWriter;
      if (writer == null) {
        return const ArticleVisionInsightSkipped(
          reason: ArticleVisionSkipReason.disabledBySetting,
        );
      }
      final Result<void> written = await writer(true);
      if (written.isErr) {
        return const ArticleVisionInsightSkipped(
          reason: ArticleVisionSkipReason.disabledBySetting,
          detail: '开关写回失败',
        );
      }
      final VisionAnalysisView retry = await analyzeImage(
        taskId: 'article-image-$imageRef-re',
        imageRef: imageRef,
        url: imageUrl,
        confirmation: confirmation,
        cancellation: cancellation,
      );
      if (retry.needsConsent) {
        return ArticleVisionInsightNeedsConsent(
          endpoint: retry.consentEndpoint!,
        );
      }
      if (retry.hasDescription) {
        return ArticleVisionInsightText(
          text: retry.description!,
          downsampled: retry.downsampled,
          endpoint: retry.endpoint,
        );
      }
      if (retry.error != null) {
        return ArticleVisionInsightFailed(error: retry.error!);
      }
      return const ArticleVisionInsightSkipped(
        reason: ArticleVisionSkipReason.imageUnavailable,
      );
    }
    if (view.skipKind == VisionSkipKind.noVisionModel) {
      return const ArticleVisionInsightSkipped(
        reason: ArticleVisionSkipReason.noVisionModel,
      );
    }
    return const ArticleVisionInsightSkipped(
      reason: ArticleVisionSkipReason.imageUnavailable,
    );
  }
}
