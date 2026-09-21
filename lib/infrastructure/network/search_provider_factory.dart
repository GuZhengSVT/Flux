// 搜索适配器工厂（T031）。
//
// 唯一知道「哪个协议标识对应哪个适配器」的地方（架构 4.3 的三个独立适配器）。
// 放在 infrastructure/network：适配器本身在这里，工厂必须与它们同层。
//
// 两个刻意的行为（与 OpenAiProviderFactory 同一口径）：
//   1) **配置问题返回 Err 而不是抛异常**：Base URL 为空（SearXNG 没填实例地址）
//      是可预期的用户配置状态，把它当成崩溃会让「点一下测试」把整页打掉；
//   2) **Base URL 在工厂里再校验一次**：记录在保存时已经校验过，但记录可能来自
//      手工改库或未来版本的导入。发请求前再拦一道，代价是三行，收益是「绝不向
//      file:// 或空主机发请求」。
//
// 工厂**不**校验凭据是否已配置：那是 ModelManager/SearchManager（用例层）的职责，
// 因为「没有 Key」需要变成一条界面提示，而工厂只回答「能不能造出适配器」。
library;

import 'package:http/http.dart' as http;

import 'package:flux/core/core.dart';
import 'package:flux/features/ai/domain/search_protocol.dart';
import 'package:flux/features/ai/domain/search_provider.dart';

import 'brave_search_adapter.dart';
import 'searxng_search_adapter.dart';
import 'tavily_search_adapter.dart';

/// 生产工厂。
final class HttpSearchProviderFactory implements SearchProviderFactory {
  /// 构造工厂。
  ///
  /// [clientFactory] 可注入（测试用它给适配器换 MockClient）；生产不传，适配器每次
  /// 请求自建客户端并在返回前关闭（用工厂函数而不是单个 Client：一个 Client 被多个
  /// 适配器共享时，任一适配器关闭它都会让其它适配器后续请求失败）。
  const HttpSearchProviderFactory({this.clientFactory});

  /// HTTP 客户端工厂（测试注入）。
  final http.Client Function()? clientFactory;

  @override
  Result<SearchProvider> create({
    required SearchProtocol protocol,
    required String baseUrl,
    required String apiKey,
    Duration timeout = const Duration(seconds: 20),
    int maxResults = 10,
    bool allowPrivateEndpoint = false,
  }) {
    final Uri? parsed = Uri.tryParse(baseUrl.trim());
    if (parsed == null ||
        !parsed.hasScheme ||
        (parsed.scheme != 'http' && parsed.scheme != 'https') ||
        parsed.host.isEmpty) {
      return Err<SearchProvider>(
        ValidationError(
          field: 'SET-038.baseUrl',
          reason: '端点必须是 http/https 的完整地址',
          value: parsed?.scheme,
        ),
      );
    }
    final http.Client? client = clientFactory?.call();
    return switch (protocol) {
      SearchProtocol.tavily => Ok<SearchProvider>(
        TavilySearchAdapter(
          baseUrl: baseUrl,
          apiKey: apiKey,
          maxResults: maxResults,
          timeout: timeout,
          client: client,
        ),
      ),
      SearchProtocol.brave => Ok<SearchProvider>(
        BraveSearchAdapter(
          baseUrl: baseUrl,
          apiKey: apiKey,
          maxResults: maxResults,
          timeout: timeout,
          client: client,
        ),
      ),
      SearchProtocol.searxng => Ok<SearchProvider>(
        SearxngSearchAdapter(
          baseUrl: baseUrl,
          apiKey: apiKey,
          allowPrivateEndpoint: allowPrivateEndpoint,
          maxResults: maxResults,
          timeout: timeout,
          client: client,
        ),
      ),
    };
  }
}
