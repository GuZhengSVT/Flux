// 文章阅读用到的平台端口（T020）：外部浏览器、图片保存、系统分享。
//
// 与 T015 的 file_access.dart 同一条理由：这三件事都要平台能力（url_launcher、
// file_selector、NSSharingServicePicker），而 features 层不得 import infrastructure
// （架构 2.2，测试会拦截）。端口只暴露业务真正需要的动作，不暴露「任意 URL 打开」
// 之外的任何东西——收窄接口可以避免后续顺手拿它做别的事。
//
// 三个端口的失败语义各不相同，因此**不共用一个 Result 形态**：
//   - 打开链接：可能被系统拒绝（没有注册的浏览器）/ 协议不合法 → Result；
//   - 保存图片：可能下载失败、可能用户取消、可能目标路径不可写 → Result；
//   - 系统分享：**不可用是常态**（架构 4.2 明确「系统分享不可用时回退复制」），
//     因此它的能力查询返回 bool 而不是错误。
library;

import 'package:flux/core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 外部浏览器打开端口。
abstract interface class ExternalLinkOpener {
  /// 用系统默认浏览器打开 [url]。
  ///
  /// 实现**必须**自己再校验一次协议（不能假设调用方已经校验过）：这是把地址交给
  /// 操作系统的最后一道关口，一旦把 file: 之类交过去，就不再受本应用控制。
  Future<Result<bool>> openExternal(String url);
}

/// 图片保存端口（下载 + 让用户选保存位置）。
abstract interface class ImageSaveService {
  /// 下载 [url] 并按用户选择的位置保存。
  ///
  /// 返回值：保存成功时为最终路径；用户取消时为 Ok(null)（取消不是错误）。
  Future<Result<String?>> saveImage({
    required String url,
    required String suggestedName,
  });
}

/// 系统分享端口。
abstract interface class SystemShareService {
  /// 该平台是否提供可用的系统分享。
  ///
  /// 不可用时界面回退为「复制」（架构 4.2）。
  Future<bool> isAvailable();

  /// 分享一段纯文本。
  ///
  /// 返回 false 表示用户在分享面板里取消，或分享被系统拒绝——两种情况对界面是同一
  /// 件事（没有分享出去），因此不区分。
  Future<Result<bool>> shareText(String text);
}

/// 外部浏览器端口 Provider。
final Provider<ExternalLinkOpener> externalLinkOpenerProvider =
    Provider<ExternalLinkOpener>(
      (Ref ref) => throw StateError(
        'externalLinkOpenerProvider 未被组合根覆盖：见 lib/app/app_providers.dart',
      ),
    );

/// 图片保存端口 Provider。
final Provider<ImageSaveService> imageSaveServiceProvider =
    Provider<ImageSaveService>(
      (Ref ref) => throw StateError(
        'imageSaveServiceProvider 未被组合根覆盖：见 lib/app/app_providers.dart',
      ),
    );

/// 系统分享端口 Provider。
final Provider<SystemShareService> systemShareServiceProvider =
    Provider<SystemShareService>(
      (Ref ref) => throw StateError(
        'systemShareServiceProvider 未被组合根覆盖：见 lib/app/app_providers.dart',
      ),
    );
