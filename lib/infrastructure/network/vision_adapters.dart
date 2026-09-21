// 视觉链路的端口适配器（T033）。
//
// 三个适配器，各自对应一个已有能力，**不重写任何判据**：
//   1) [CachedVisionImageLoader]：复用 T021 的受控图片加载器（地址守卫 + DNS 解析后复检 +
//      MIME 白名单 + 魔数 + 体积上限 + 解码像素上限），并在超出 SET-065 单图上限时**降采样**；
//   2) [SettingsStoreVisionSettings]：把设置端口接成视觉链路的只读设置端口；
//   3) [DeviceStateVisionConsent]：把本机状态仓储接成发送告知的记录端口（架构第 8 节：
//      确认记录属于本机运行授权状态，不作为普通偏好同步）。
//
// 为什么降采样在这层而不是领域层：缩图要解码 + 重编码，那是平台能力（dart:ui），而领域层
// 必须能在纯 Dart 测试里被逐条断言。领域层只看到「这张图缩过没有」这个事实。
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flux/core/core.dart';
import 'package:flux/features/ai/application/vision_ports.dart';
import 'package:flux/features/ai/application/tool_ports.dart';
import 'package:flux/features/ai/application/visual_router.dart';
import 'package:flux/features/ai/domain/ai_model.dart';
import 'package:flux/features/ai/domain/vision_consent.dart';
import 'package:flux/features/ai/domain/vision_routing.dart';
import 'package:flux/features/articles/application/article_image_ports.dart';
import 'package:flux/features/settings/application/settings_store.dart';

import '../local/device_state_repository.dart';

/// 受控图片加载 + 降采样（T033）。
final class CachedVisionImageLoader implements VisionImageLoader {
  /// 构造适配器。
  const CachedVisionImageLoader({required this.loader});

  /// T021 的受控加载器（含缓存、守卫与全部校验）。
  final ArticleImageLoader loader;

  @override
  Future<Result<VisionLoadedImage>> load({
    required String url,
    required int maxBytes,
  }) async {
    final Result<LoadedImage> loaded = await loader.load(url);
    if (loaded.isErr) {
      return Err<VisionLoadedImage>(loaded.errorOrNull!);
    }
    final LoadedImage image = loaded.unwrap();
    if (image.bytes.length <= maxBytes) {
      return Ok<VisionLoadedImage>(
        VisionLoadedImage(
          bytes: image.bytes,
          mimeType: image.mimeType,
          width: image.width,
          height: image.height,
          downsampled: false,
        ),
      );
    }
    // 超过 SET-065 的单图上限：降采样后发送，并**如实标记**（架构 4.3「降采样仍说明」）。
    return downsampleToByteBudget(
      bytes: image.bytes,
      mimeType: image.mimeType,
      width: image.width,
      height: image.height,
      maxBytes: maxBytes,
    );
  }
}

/// 把一张图缩到不超过 [maxBytes]，并把结果标成「已降采样」。
///
/// 为什么按面积比例逐次缩小而不是一次算到目标：JPEG/PNG 的压缩率与像素数的关系不是线性的
/// （一张纯色图缩一半可能只小 20%），一次到位的估算会让一部分图仍然超限。逐次缩小是
/// 有界循环（[kMaxDownsampleRounds] 轮），且每轮都重新检查实际字节数——判据是**真实结果**
/// 而不是估算。
///
/// 缩不下去时返回 Err：宁可如实说「这张图发不出去」，也不要发出一个超限的请求（服务商一般
/// 会直接拒绝，而那会让用户看到一条与图片无关的错误），更不要静默换成另一张图。
Future<Result<VisionLoadedImage>> downsampleToByteBudget({
  required Uint8List bytes,
  required String mimeType,
  required int width,
  required int height,
  required int maxBytes,
  int rounds = kMaxDownsampleRounds,
}) async {
  if (bytes.isEmpty) {
    return Err<VisionLoadedImage>(
      ValidationError(field: 'vision.image', reason: '图片为空'),
    );
  }
  ui.Image? decoded;
  try {
    decoded = await decodeUiImage(bytes);
  } on Exception catch (error, stackTrace) {
    return Err<VisionLoadedImage>(
      StorageError(
        operation: 'vision.downsample',
        detail: '图片解码失败',
        cause: error,
        stackTrace: stackTrace,
      ),
    );
  }
  final ui.Image source = decoded;
  int targetWidth = source.width;
  int targetHeight = source.height;
  try {
    for (int round = 0; round < rounds; round++) {
      // 每轮按剩余比例缩到 0.7：像素数降到约一半。选 0.7 而不是 0.5 是为了让「只超出 10%」
      // 的图不必被砍掉一半分辨率。
      targetWidth = (targetWidth * 0.7).round();
      targetHeight = (targetHeight * 0.7).round();
      if (targetWidth < 32 || targetHeight < 32) {
        break;
      }
      final Uint8List scaled = await encodeScaledPng(
        source,
        targetWidth,
        targetHeight,
      );
      if (scaled.length <= maxBytes) {
        return Ok<VisionLoadedImage>(
          VisionLoadedImage(
            bytes: scaled,
            // **重编码后是 PNG**：如实报告新 MIME（说成原来的类型会让服务商按错误类型解码）。
            mimeType: 'image/png',
            width: targetWidth,
            height: targetHeight,
            downsampled: true,
          ),
        );
      }
    }
  } finally {
    source.dispose();
  }
  return Err<VisionLoadedImage>(
    ValidationError(
      field: 'vision.image',
      reason: '图片降采样后仍超过单图上限，未发送',
      value: '$mimeType ${width}x$height',
    ),
  );
}

/// 降采样的最大轮数（有界循环；每轮缩小 30%）。
const int kMaxDownsampleRounds = 8;

/// 把字节解码为一张可缩放图。
///
/// 用 [ui.instantiateImageCodec] 而不是 decodeImageFromList：前者可以直接给出目标尺寸，
/// 后者总是按原尺寸解码（一张 8000×6000 的图会先占满内存，正是 T021 的解码像素上限要防的事）。
Future<ui.Image> decodeUiImage(Uint8List bytes) async {
  final ui.Codec codec = await ui.instantiateImageCodec(bytes);
  try {
    final ui.FrameInfo frame = await codec.getNextFrame();
    return frame.image;
  } finally {
    codec.dispose();
  }
}

/// 按目标尺寸重编码为 PNG。
Future<Uint8List> encodeScaledPng(
  ui.Image source,
  int width,
  int height,
) async {
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final ui.Canvas canvas = ui.Canvas(recorder);
  final ui.Paint paint = ui.Paint()..filterQuality = ui.FilterQuality.medium;
  canvas.drawImageRect(
    source,
    ui.Rect.fromLTWH(0, 0, source.width.toDouble(), source.height.toDouble()),
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    paint,
  );
  final ui.Picture picture = recorder.endRecording();
  try {
    final ui.Image scaled = await picture.toImage(width, height);
    try {
      final ByteData? data = await scaled.toByteData(
        format: ui.ImageByteFormat.png,
      );
      if (data == null) {
        throw StateError('PNG 编码返回空数据');
      }
      return data.buffer.asUint8List();
    } finally {
      scaled.dispose();
    }
  } finally {
    picture.dispose();
  }
}

/// 把设置端口接成视觉链路的只读设置读取（SET-034 / SET-065）。
final class SettingsStoreVisionSettings implements VisionSettingsReader {
  /// 绑定一个设置端口。
  const SettingsStoreVisionSettings(this._store);

  final SettingsStore _store;

  @override
  Future<Object?> readDedicatedVisionModel() async {
    final Result<Object?> read = await _store.readSetting(SettingId.set034);
    return read.isOk ? read.valueOrNull : null;
  }

  @override
  Future<Object?> readImageLimits() async {
    final Result<Object?> read = await _store.readSetting(SettingId.set065);
    return read.isOk ? read.valueOrNull : null;
  }
}

/// 把本机状态仓储接成发送告知的记录端口。
///
/// 用 settings 窄表的 `device.` 命名空间（与引导标记同一个做法）：确认记录属于本机运行
/// 授权状态，架构第 8 节明确它不作为普通偏好同步，因此它**不能**是一个 SET 编号。
final class DeviceStateVisionConsent implements VisionConsentStore {
  /// 绑定本机状态仓储。
  const DeviceStateVisionConsent(this._repository);

  final DeviceStateRepository _repository;

  @override
  Future<Result<VisionSendAcknowledgement?>> find(String endpoint) async {
    final Result<bool> read = await _repository.readBool(
      VisionSendAcknowledgement.storageKeyFor(endpoint),
    );
    if (read.isErr) {
      return Err<VisionSendAcknowledgement?>(read.errorOrNull!);
    }
    if (!read.unwrap()) {
      return const Ok<VisionSendAcknowledgement?>(null);
    }
    // 记录的存在性就是授权事实；时刻与别名只用于界面核对，不在这里还原（那条键只有布尔
    // 值可读——这也是本机状态仓储当前的形状；展示「何时同意过」属后续的知情页）。
    return Ok<VisionSendAcknowledgement?>(
      VisionSendAcknowledgement(
        endpoint: endpoint,
        providerAlias: '',
        acknowledgedAtUtc: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      ),
    );
  }

  @override
  Future<Result<void>> save(VisionSendAcknowledgement acknowledgement) =>
      _repository.writeBool(
        VisionSendAcknowledgement.storageKeyFor(acknowledgement.endpoint),
        true,
      );
}

/// 把视觉链路接成执行器的受控分析端口（T033）。
///
/// 为什么需要这一层：VisualRouter 住在 features/ai/application，而工具执行器只认一个
/// 一图一问的窄端口。适配器做三件事，每件都是一次**语义翻译**而不是逻辑重写：
///  1) 单图调用 VisualRouter.analyze（一张图一次请求：一张图的失败不影响其余）；
///  2) 把 VisionAnalysisOutcome 的几种结局（成功 / 无视觉模型 / 待确认 / 图拿不到）
///     翻译成 VisionSkipKind，让执行器的回填文本能明确说清「为什么没有分析」；
///  3) 把「待确认」翻译成一个**不失败**的跳过结果：弹首次发送告知对话框是界面那一侧的
///     事，工具执行器不该在模型对话中间弹一个 UI。
final class VisualRouterToolAnalyzer implements ToolVisionAnalyzer {
  /// 构造适配器。
  const VisualRouterToolAnalyzer(this.router);

  /// 视觉链路。
  final VisualRouter router;

  @override
  Future<Result<VisionAnalysisResult>> analyze({
    required String imageRef,
    required String url,
  }) async {
    final VisionAnalysisOutcome outcome = await router.analyze(
      taskId: 'tool-image-$imageRef',
      images: <VisionImageRequest>[VisionImageRequest(ref: imageRef, url: url)],
    );
    if (outcome.needsConsent) {
      // 首次发送告知：**没有发出任何字节**。如实回填，让模型知道这不是它能重试解决的事。
      return Ok<VisionAnalysisResult>(
        VisionAnalysisResult(
          skippedReason: VisionSkipKind.awaitingConsent,
          endpoint: outcome.awaitingConsentEndpoint,
        ),
      );
    }
    if (outcome.error != null) {
      return Err<VisionAnalysisResult>(outcome.error!);
    }
    if (outcome.skippedNoVisionModel) {
      return const Ok<VisionAnalysisResult>(
        VisionAnalysisResult(skippedReason: VisionSkipKind.noVisionModel),
      );
    }
    if (outcome.analyses.isEmpty) {
      // 开关关闭或全部候选被数量上限挡掉：都是**不失败**的跳过。
      return const Ok<VisionAnalysisResult>(
        VisionAnalysisResult(skippedReason: VisionSkipKind.disabledBySetting),
      );
    }
    final VisionImageAnalysis analysis = outcome.analyses.first;
    if (analysis.ok) {
      return Ok<VisionAnalysisResult>(
        VisionAnalysisResult(
          description: analysis.text,
          downsampled: analysis.downsampled,
          endpoint: switch (outcome.route) {
            VisionRouteDedicated(:final AiModel model) => model.baseUrl,
            VisionRoutePrimary(:final AiModel model) => model.baseUrl,
            VisionRouteSkip() => null,
          },
        ),
      );
    }
    return Ok<VisionAnalysisResult>(
      VisionAnalysisResult(
        skippedReason: VisionSkipKind.imageUnavailable,
        error: analysis.error,
      ),
    );
  }
}
