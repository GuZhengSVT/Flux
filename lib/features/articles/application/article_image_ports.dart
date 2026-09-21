// 文章图片加载端口（T021）。
//
// 界面需要的是「给我这张图的字节」这一件事，而不是「一个缓存服务」：
//   - 界面（features）不得 import infrastructure（架构 2.2，测试会拦）；
//   - 把缓存、下载、解码限额的实现细节暴露给界面，会让界面长出「什么时候该清缓存」
//     这类它不该有的判断。
//
// 因此端口只有两个动作：[load]（要一张图，可能来自缓存或网络）与 [saveToFile]
// （保存到用户选定的路径，仍走同一套校验）。缓存统计与清理属 T047 的存储页，不在这里。
//
// [load] 的失败语义是一条明确的产品规则（架构 4.2「失败不阻塞文章」）：返回 Err
// 表示这一张图拿不到，调用方画占位与重试按钮，**其余图片与正文继续渲染**。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flux/core/core.dart';

/// 图片加载端口。
abstract interface class ArticleImageLoader {
  /// 加载一张图（优先缓存）。
  ///
  /// [url] 是正文/卡片里已通过 [isSafeDocUrl] 的地址；实现仍会**再走一遍**地址守卫
  /// （字面量私网 + DNS 解析后复检），因为渲染层只判协议。
  Future<Result<LoadedImage>> load(String url);

  /// 把 [url] 的图片写到 [targetPath]（保存到用户选定的位置）。
  ///
  /// 与 [load] 共用同一条下载与校验管线：保存路径**不得**绕开 MIME/体积限制，
  /// 否则「点保存」就成了一个可以下载任意大小文件的旁路。
  Future<Result<int>> saveToPath({
    required String url,
    required String targetPath,
  });

  /// 应用 SET-080 的媒体缓存上限（MiB）。
  ///
  /// 单独一个动作而不是构造参数：上限来自**异步**的设置读取，而加载器必须在装配时
  /// 就能同步返回。因此装配给出默认值，设置读出来之后再显式套用（与刷新调度的
  /// 「观察到策略后立刻套用」同一模式）。实现应把越界值夹紧到 128–4096。
  Future<void> applyCacheLimitMiB(int limitMiB);
}

/// 图片加载端口 Provider。
///
/// 默认实现抛错：漏接线必须在使用时立刻暴露，而不是退化成一个「所有图都加载失败」的
/// 空实现——后者会被读成「网络问题」，把装配错误伪装成环境问题。
final Provider<ArticleImageLoader> articleImageLoaderProvider =
    Provider<ArticleImageLoader>(
      (Ref ref) => throw StateError(
        'articleImageLoaderProvider 未被组合根覆盖：见 lib/app/app_providers.dart',
      ),
    );
