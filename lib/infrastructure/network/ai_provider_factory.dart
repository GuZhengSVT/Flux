// AI 适配器工厂（T026）。
//
// 唯一知道「哪个协议标识对应哪个适配器」的地方（架构 4.3 的三种独立适配器）。
// 放在 infrastructure/network：适配器本身在这里，工厂必须与它们同层。
//
// 两个刻意的行为：
//   1) **协议未实现时返回 Err 而不是抛异常**：T025 期间 Anthropic 已在协议枚举里登记
//      （用户可以提前配置），但适配器属 T027。把一个可预期的配置状态当成崩溃会让
//      「点一下测试」把整页打掉；
//   2) **Base URL 在工厂里再校验一次**：模型记录在保存时已经校验过，但记录可能来自
//      手工改库或未来版本的导入。发请求前再拦一道，代价是三行，收益是「绝不向
//      file:// 或空主机发请求」。
library;

import 'package:http/http.dart' as http;

import 'package:flux/core/core.dart';
import 'package:flux/features/ai/domain/ai_protocol.dart';
import 'package:flux/features/ai/domain/ai_provider.dart';

import 'ai_http.dart';
import 'anthropic_messages_adapter.dart';
import 'chat_completions_adapter.dart';
import 'responses_adapter.dart';

/// 生产工厂。
final class OpenAiProviderFactory implements AiProviderFactory {
  /// 构造工厂。
  ///
  /// [clientFactory] 可注入（测试用它给适配器换 MockClient）；生产不传，适配器每次
  /// 请求自建客户端并在返回前关闭。用工厂函数而不是单个 Client：一个 Client 被多个
  /// 适配器共享时，任一适配器关闭它都会让其它适配器后续请求失败。
  const OpenAiProviderFactory({
    this.clientFactory,
    this.timeouts = const AiStreamTimeouts(),
  });

  /// HTTP 客户端工厂（测试注入）。
  final http.Client Function()? clientFactory;

  /// 时限（SET-036 默认值；由调用方按设置覆盖属 T029 的队列层）。
  final AiStreamTimeouts timeouts;

  @override
  Result<AiProvider> create({
    required String alias,
    required String protocolId,
    required String baseUrl,
    required String modelId,
    required String apiKey,
  }) {
    final AiProtocol? protocol = AiProtocol.fromId(protocolId);
    if (protocol == null) {
      return Err<AiProvider>(
        ModelConfigurationError(
          alias: alias,
          reason: 'unknownProtocol',
          detail: protocolId,
        ),
      );
    }
    if (!protocol.hasAdapter) {
      return Err<AiProvider>(
        ModelConfigurationError(
          alias: alias,
          reason: 'adapterMissing',
          detail: protocol.missingAdapterReason,
        ),
      );
    }
    if (apiKey.isEmpty) {
      return Err<AiProvider>(
        ModelConfigurationError(alias: alias, reason: 'credentialMissing'),
      );
    }
    final Uri? endpoint = Uri.tryParse(baseUrl);
    if (endpoint == null ||
        !endpoint.hasScheme ||
        (endpoint.scheme != 'http' && endpoint.scheme != 'https') ||
        endpoint.host.isEmpty) {
      return Err<AiProvider>(
        ModelConfigurationError(
          alias: alias,
          reason: 'invalidBaseUrl',
          detail: endpoint?.scheme,
        ),
      );
    }

    final http.Client? client = clientFactory?.call();
    return switch (protocol) {
      AiProtocol.openAiChatCompletions => Ok<AiProvider>(
        ChatCompletionsAdapter(
          alias: alias,
          baseUrl: baseUrl,
          modelId: modelId,
          apiKey: apiKey,
          client: client,
          timeouts: timeouts,
        ),
      ),
      AiProtocol.openAiResponses => Ok<AiProvider>(
        ResponsesAdapter(
          alias: alias,
          baseUrl: baseUrl,
          modelId: modelId,
          apiKey: apiKey,
          client: client,
          timeouts: timeouts,
        ),
      ),
      AiProtocol.anthropicMessages => Ok<AiProvider>(
        AnthropicMessagesAdapter(
          alias: alias,
          baseUrl: baseUrl,
          modelId: modelId,
          apiKey: apiKey,
          client: client,
          timeouts: timeouts,
        ),
      ),
    };
  }
}
