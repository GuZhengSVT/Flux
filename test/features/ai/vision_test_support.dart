// T033 视觉测试替身（端口级，全部不联网、不发真实请求）。
//
// 为什么替身放在**端口**这一层：视觉链路最该被证明的一件事是「哪些情况下一个字节都没发」。
// 用端口替身的**调用计数**能直接断言这一点，而把断言推到 HTTP 层就分不开「拒绝了」与
// 「发了但失败了」。
library;

import 'dart:typed_data';

import 'package:flux/core/core.dart';
import 'package:flux/features/ai/application/vision_ports.dart';
import 'package:flux/features/ai/domain/vision_consent.dart';
import 'package:flux/features/ai/domain/vision_routing.dart';

/// 记录调用次数并按需失败/降采样的图片加载替身。
final class FakeVisionImageLoader implements VisionImageLoader {
  /// 加载次数。
  int loads = 0;

  /// 需要失败的引用（匹配时返回网络错误）。
  String? failFor;

  /// 正常返回的结果。
  VisionLoadedImage result = VisionLoadedImage(
    bytes: Uint8List.fromList(<int>[1, 2, 3, 4]),
    mimeType: 'image/png',
    width: 640,
    height: 480,
    downsampled: false,
  );

  /// 收到的地址（断言「地址只用于本机加载」）。
  final List<String> urls = <String>[];

  @override
  Future<Result<VisionLoadedImage>> load({
    required String url,
    required int maxBytes,
  }) async {
    loads++;
    urls.add(url);
    if (failFor != null && url.contains(failFor!)) {
      return Err<VisionLoadedImage>(
        NetworkError(uri: url, reason: 'fixture failure'),
      );
    }
    return Ok<VisionLoadedImage>(result);
  }
}

/// 可切换的视觉设置替身。
final class FakeVisionSettings implements VisionSettingsReader {
  /// SET-034 的专用视觉模型别名。
  String? dedicatedAlias;

  /// SET-065 的图像限额。
  ImageInputLimits limits = const ImageInputLimits();

  @override
  Future<Object?> readDedicatedVisionModel() async => dedicatedAlias;

  @override
  Future<Object?> readImageLimits() async => <String, Object?>{
    'enabled': limits.enabled,
    'maxImages': limits.maxImages,
    'maxImageMiB': limits.maxImageMiB,
  };
}

/// 内存里的发送告知记录（不落盘；落盘实现见 infrastructure 的适配器）。
final class InMemoryVisionConsent implements VisionConsentStore {
  final Map<String, VisionSendAcknowledgement> _records =
      <String, VisionSendAcknowledgement>{};

  /// 与端口同名的查询（测试里直接调，不必绕 Result）。
  @override
  Future<Result<VisionSendAcknowledgement?>> find(String endpoint) async =>
      Ok<VisionSendAcknowledgement?>(_records[endpoint]);

  @override
  Future<Result<void>> save(VisionSendAcknowledgement acknowledgement) async {
    _records[acknowledgement.endpoint] = acknowledgement;
    return okUnit();
  }

  /// 已记录数。
  int get length => _records.length;
}
