// 视觉链路的端口与设置读取（T033）。
//
// 为什么要端口而不是让 VisualRouter 直接调用 T021 的图片管线：
//   - 图片管线住在 infrastructure（features 不得 import infrastructure，架构 2.2）；
//   - 那条管线自带一整套判据（地址守卫 + DNS 解析后复检 + MIME 白名单 + 魔数 + 体积上限 +
//     解码像素上限），视觉链路只应消费**已经过完整校验的产物**，不重写第二套（与 T032 的
//     tool_ports 同一条理由）。
//
// **降采样也在这里发生**：单图超过 SET-065 上限时要缩，而缩图需要解码/重编码（Flutter 的
// 图片编解码），那是基础设施的能力。领域层只看到「这张图缩过没有」这个事实，因此
// [VisionLoadedImage.downsampled] 是一个可断言的标记，而不是一句注释里的承诺。
library;

import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flux/core/core.dart';

import '../domain/vision_consent.dart';
import '../domain/vision_routing.dart';
import 'ai_ports.dart';
import 'ai_task_providers.dart';
import 'tool_ports.dart';
import 'visual_router.dart';

/// 一张已就绪、可交给视觉模型的图片。
final class VisionLoadedImage {
  /// 构造结果。
  const VisionLoadedImage({
    required this.bytes,
    required this.mimeType,
    required this.width,
    required this.height,
    required this.downsampled,
  });

  /// 字节（已过 MIME/魔数/体积校验；已按上限降采样）。
  final Uint8List bytes;

  /// MIME。
  final String mimeType;

  /// 宽（像素，**发送时的**尺寸）。
  final int width;

  /// 高（像素，**发送时的**尺寸）。
  final int height;

  /// 是否为降采样后的产物。
  final bool downsampled;
}

/// 视觉图片加载端口。
///
/// 实现复用 T021 的受控图片加载器：地址守卫、MIME/魔数校验、体积上下限与解码像素上限
/// 全部走同一份判据。超过 [maxBytes] 时实现必须尝试降采样并把结果标成 downsample；
/// **做不到**时返回 Err（宁可如实说「这张图发不出去」，也不要假装缩过然后发一张超限的图，
/// 或悄悄换一张不是用户选中的图）。
abstract interface class VisionImageLoader {
  /// 加载一张图并按 [maxBytes] 上限降采样（需要时）。
  Future<Result<VisionLoadedImage>> load({
    required String url,
    required int maxBytes,
  });
}

/// 视觉相关的设置读取端口（SET-034 专用视觉模型 / SET-065 图像分析开关与限额）。
///
/// 只给读入口（与 ToolBudgetSettings 同一做法）：给视觉链路写设置的能力会让「一次图像
/// 分析顺手改了用户配置」成为可能，而设置页不会因此刷新。
abstract interface class VisionSettingsReader {
  /// 读取 SET-034（专用视觉模型别名）；未设置为 null。
  Future<Object?> readDedicatedVisionModel();

  /// 读取 SET-065（图像分析开关 / 最多图片 / 单图上限）。
  Future<Object?> readImageLimits();
}

/// 默认实现：未接线时抛错（漏接线必须在使用时立刻暴露）。
final Provider<VisionImageLoader> visionImageLoaderProvider =
    Provider<VisionImageLoader>(
      (Ref ref) => throw StateError(
        'visionImageLoaderProvider 未被组合根覆盖：见 lib/app/app_providers.dart',
      ),
    );

/// 视觉设置读取端口（由组合根接上 SettingsStore）。
final Provider<VisionSettingsReader?> visionSettingsReaderProvider =
    Provider<VisionSettingsReader?>((Ref ref) => null);

/// 视觉发送告知的读写端口（由组合根接上本机状态仓储）。
final Provider<VisionConsentStore?> visionConsentStoreProvider =
    Provider<VisionConsentStore?>((Ref ref) => null);

/// 当前生效的图像输入限制（SET-065）。
///
/// 与 mediaCacheLimitProvider 同一模式：设置读取是异步的，Provider 构造是同步的，因此用
/// 一个 FutureProvider 把「读一次设置」这件事集中在一处；读不到时用注册表默认值（图像分析
/// 开着、6 张、4 MiB）。
final FutureProvider<ImageInputLimits> imageInputLimitsProvider =
    FutureProvider<ImageInputLimits>((Ref ref) async {
      final VisionSettingsReader? reader = ref.watch(
        visionSettingsReaderProvider,
      );
      if (reader == null) {
        return const ImageInputLimits();
      }
      final Object? raw = await reader.readImageLimits();
      return ImageInputLimits.fromSetting(raw);
    });

/// 视觉链路 Provider（T033）。
///
/// 装配点在这里而不是组合根：它依赖的全部是 features 侧的端口（队列、加载器、设置、
/// 告知、诊断），没有一处需要知道 infrastructure 的具体实现——那些由组合根覆盖各自的
/// 端口 Provider 决定（见 app_providers）。
final Provider<VisualRouter> visualRouterProvider = Provider<VisualRouter>(
  (Ref ref) => VisualRouter(
    runner: ref.watch(aiTaskRunnerProvider),
    loader: ref.watch(visionImageLoaderProvider),
    loadEnabledModels: ref.watch(enabledModelsLoaderProvider),
    settings: ref.watch(visionSettingsReaderProvider),
    consent: ref.watch(visionConsentStoreProvider),
    clock: ref.watch(aiTaskClockProvider),
    diagnostics: ref.watch(aiDiagnosticSinkProvider),
    budget: ref.watch(aiTaskBudgetProvider),
  ),
);

/// 工具执行器的视觉分析端口（T033）。
///
/// 默认实现抛错：漏接线必须在使用时立刻暴露。执行器侧对「没有分析器」是**容忍**的
/// （只给元数据），因此这里的默认实现仍保持抛错——真正的「容忍」是执行器不注入分析器
/// 这一事实，而不是让一个坏端口静默返回空分析。
final Provider<ToolVisionAnalyzer> toolVisionAnalyzerProvider =
    Provider<ToolVisionAnalyzer>(
      (Ref ref) => throw StateError(
        'toolVisionAnalyzerProvider 未被组合根覆盖：见 lib/app/app_providers.dart',
      ),
    );
