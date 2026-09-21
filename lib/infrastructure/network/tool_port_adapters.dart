// 受控工具端口的适配器（T032）。
//
// 两个适配器把 T024（静态网页抽取）与 T021（受控图片抓取）接到 features/ai 的窄端口上：
// features 不得 import infrastructure（架构 2.2 的守卫会拦），而工具执行器需要
// 「抓一页并清洗」与「看一张图」这两个能力。
//
// 这一层**不重新实现任何判据**：地址守卫、DNS 解析后复检、逐跳重定向校验、体积/解压
// 上限、MIME 白名单、魔数嗅探、解码像素上限全在下方那两层里（T021/T024 的实现）。
// 这里只做两件事：把 HTML 变成「标题 + 正文 + 图片引用」（复用 T024 的纯函数抽取器），
// 以及把结果类型翻译成端口形状。
//
// 为什么抓取与抽取在这里合并：T024 的 StaticPageFetcherPort 只给「网页字节」，而工具
// 需要的是「已清洗的正文」。抽取是**纯函数**（features/articles/domain），因此在这里
// 调用它不会把任何 IO 带进 features —— 依赖方向仍然是 infrastructure → features。
library;

import 'package:flux/core/core.dart';
import 'package:flux/features/ai/application/tool_ports.dart';
import 'package:flux/features/articles/application/article_image_ports.dart';
import 'package:flux/features/articles/application/fetch_original_article.dart';
import 'package:flux/features/articles/domain/static_article_extractor.dart';

/// 把 T024 的抓取端口 + 抽取器接成受控网页抓取。
final class ControlledPageFetcherAdapter implements ControlledPageFetcher {
  /// 构造适配器。
  const ControlledPageFetcherAdapter({
    required this.fetcher,
    this.limits = const StaticExtractionLimits(),
  });

  /// 底层抓取端口（**自带完整安全链**：地址守卫 + DNS 解析后复检 + 逐跳校验 + 体积上限）。
  final StaticPageFetcherPort fetcher;

  /// 抽取上限。
  final StaticExtractionLimits limits;

  @override
  Future<Result<FetchedPage>> fetch(Uri uri) async {
    final Result<StaticPageDocument> page = await fetcher.fetch(uri);
    if (page.isErr) {
      return Err<FetchedPage>(page.errorOrNull!);
    }
    final StaticPageDocument document = page.unwrap();
    final StaticExtraction extraction = extractStaticArticle(
      document.html,
      limits: limits,
    );
    return Ok<FetchedPage>(
      FetchedPage(
        finalUri: document.finalUri,
        title: extraction.title,
        text: extraction.text,
        imageUrls: extraction.imageUrls,
        // 把 T024 的枚举映射成**稳定字符串**：端口用字符串是为了不让 features/ai
        // 依赖 features/articles 的枚举（跨 feature 依赖会让「删掉一个 feature」变成
        // 一件需要跨目录排查的事，见 ai_ports 的同一条说明）。
        outcome: switch (extraction.outcome) {
          StaticExtractionOutcome.ok => 'ok',
          StaticExtractionOutcome.empty => 'empty',
          StaticExtractionOutcome.noContent => 'noContent',
        },
      ),
    );
  }
}

/// 把 T021 的受控图片加载器接成工具的图片查看端口。
///
/// 用 [ArticleImageLoader] 而不是直接 new 一个 HttpMediaFetcher：加载器那条路径已经在
/// 生产里跑（阅读器的图片缓存），因此它带的守卫、MIME/体积/魔数校验与缓存行为是
/// **已经验证过的**那一份。工具复用同一份，比再写一条「只给工具用」的下载路径可靠。
final class ToolImageInspectorAdapter implements ToolImageInspector {
  /// 构造适配器。
  const ToolImageInspectorAdapter(this.loader);

  /// 受控图片加载器。
  final ArticleImageLoader loader;

  @override
  Future<Result<InspectedImage>> inspect(String url) async {
    final Result<LoadedImage> loaded = await loader.load(url);
    if (loaded.isErr) {
      return Err<InspectedImage>(loaded.errorOrNull!);
    }
    final LoadedImage image = loaded.unwrap();
    return Ok<InspectedImage>(
      InspectedImage(
        mimeType: image.mimeType,
        width: image.width,
        height: image.height,
        byteLength: image.bytes.length,
      ),
    );
  }
}
