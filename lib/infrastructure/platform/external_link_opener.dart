// 外部浏览器适配器（T020）：把 url_launcher 接到 [ExternalLinkOpener]。
//
// 隔离在这里的理由与 T013 的 HTTP、T015 的文件面板相同：features 层不得 import 平台包
// （架构 2.2，测试会拦截）。
//
// 安全约束：**这一层再校验一次协议**。调用方（详情页）已经校验过，但这是把地址交给
// 操作系统的最后一道关口：一旦把 file: 或 javascript: 交给系统启动器，后续行为就不再
// 受本应用控制（macOS 可能打开本地文件或触发注册了该协议的应用）。重复判定在这里的
// 代价是一次字符串检查，而漏判的代价是让源内容有机会指使系统打开本机文件。
library;

import 'package:url_launcher/url_launcher.dart';

import 'package:flux/core/core.dart';
import 'package:flux/features/articles/application/article_platform_ports.dart';

/// 用系统默认浏览器打开链接。
final class UrlLauncherLinkOpener implements ExternalLinkOpener {
  /// 构造适配器。
  const UrlLauncherLinkOpener();

  @override
  Future<Result<bool>> openExternal(String url) async {
    if (!isSafeDocUrl(url)) {
      // 类型化失败而不是静默忽略：调用方要据此告诉用户「这个地址不会打开」。
      return Err<bool>(
        StorageError(operation: 'openExternal', detail: '地址协议不被允许'),
      );
    }
    try {
      final Uri? uri = Uri.tryParse(url);
      if (uri == null) {
        return Err<bool>(
          StorageError(operation: 'openExternal', detail: '地址无法解析'),
        );
      }
      // 明确用 externalApplication：这是「用用户默认的外部浏览器打开」，而不是把应用
      // 变成一个内嵌浏览器（D-05 禁止 WebView；url_launcher 的 inApp 模式不是它的对手，
      // 但这里连它也不用）。
      final bool launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        return Err<bool>(
          StorageError(operation: 'openExternal', detail: '系统未接受该地址'),
        );
      }
      return const Ok<bool>(true);
    } on Exception catch (error, stackTrace) {
      return Err<bool>(
        StorageError(
          operation: 'openExternal',
          // 只保留异常类型：平台异常文本可能带完整路径。
          detail: error.runtimeType.toString(),
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }
}
