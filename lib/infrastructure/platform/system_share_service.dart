// 系统分享适配器（T020）：macOS 的 NSSharingServicePicker。
//
// 为什么选原生通道而不是 share_plus：
//   - 本任务只要求「可分享一段文本 + 不可用时回退复制」，而 NSSharingServicePicker 正是
//     macOS 上系统分享面板的实现（与 share_plus 内部在 macOS 上用的是同一个 API）；
//   - share_plus 会把 5 个平台实现（含 Android/iOS/Windows/Linux）与它们的构建配置一并
//     拉进来，而本工程当前只有 macOS（D-02 之后才有 Android）。原生通道几十行，且与
//     T010 的 KeychainPlugin 走同一套注册方式，平台边界看得见摸得着；
//   - 架构 2.1 把「文件/分享」明确列为允许的平台桥接范围。
//
// macOS 上的一个实测细节：NSSharingServicePicker 必须挂在**某个视图**上才能弹出，因此
// 通道需要拿到一个 NSView。这里用 NSApplication 的主窗口 contentView——分享面板是模态的
// 用户交互，出现在主窗口上是符合预期的行为。
//
// 不可用时（旧系统、无可用服务、通道未注册）返回 false，由上层回退复制（架构 4.2）。
library;

import 'package:flutter/services.dart';

import 'package:flux/core/core.dart';
import 'package:flux/features/articles/application/article_platform_ports.dart';

/// 分享通道名（必须与 macos/Runner/SharePlugin.swift 一致）。
const String fluxShareChannelName = 'io.github.guzhengsvt.flux/share';

/// 通过原生 NSSharingServicePicker 分享文本。
final class NativeSystemShareService implements SystemShareService {
  /// 构造适配器。
  const NativeSystemShareService();

  /// 通道句柄（懒建，避免在测试环境里构造 MethodChannel 之外的开销）。
  static const MethodChannel _channel = MethodChannel(fluxShareChannelName);

  @override
  Future<bool> isAvailable() async {
    try {
      final bool? available = await _channel.invokeMethod<bool>('isAvailable');
      return available ?? false;
    } on PlatformException {
      // 通道没注册（非 macOS 构建、测试环境）就是「不可用」，这不是错误。
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<Result<bool>> shareText(String text) async {
    if (text.trim().isEmpty) {
      return Err<bool>(
        StorageError(operation: 'shareText', detail: '没有可分享的内容'),
      );
    }
    try {
      final bool? shared = await _channel.invokeMethod<bool>('shareText', text);
      return Ok<bool>(shared ?? false);
    } on PlatformException catch (error, stackTrace) {
      return Err<bool>(
        StorageError(
          operation: 'shareText',
          // 只保留 code：平台异常文本可能带上被分享的内容。
          detail: error.code,
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    } on MissingPluginException catch (error, stackTrace) {
      return Err<bool>(
        StorageError(
          operation: 'shareText',
          detail: 'share channel unavailable',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }
}
