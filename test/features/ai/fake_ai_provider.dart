// T025 测试替身：可注入的适配器工厂与假 provider。
//
// 为什么工厂要记录 lastRequest：模型管理的「最小生成测试」有几个只能从**请求形状**
// 上验证的事实（输出上限被压到最小预算、消息包含系统指令等）。记录请求比断言
// 「provider 被调用过」能覆盖更多真实行为。
library;

import 'package:flux/core/core.dart';
import 'package:flux/features/ai/domain/ai_message.dart';
import 'package:flux/features/ai/domain/ai_protocol.dart';
import 'package:flux/features/ai/domain/ai_provider.dart';

/// 假工厂：按需产出固定事件流的 provider。
final class FakeAiProviderFactory implements AiProviderFactory {
  /// 被创建过几次（用于断言「被拒绝的请求不产生费用」）。
  int createdCount = 0;

  /// 最后一次收到的请求（用于断言请求形状）。
  AiRequest? lastRequest;

  /// 最后一次收到的 Key（仅用于断言它被**原样**传给适配器，不写入任何日志）。
  String? lastApiKey;

  /// 生成时抛出的类型化错误；为空表示成功。
  AppError? failure;

  /// 生成时抛出的非类型化异常（模拟适配器的 bug）；为空表示不抛。
  Object? untypedFailure;

  /// 成功时产出的增量文本。
  List<String> deltas = <String>['连接', '正常'];

  /// 成功时产出的 usage；为空表示协议未提供。
  AiUsage? usage = const AiUsage(
    inputTokens: 11,
    outputTokens: 5,
    totalTokens: 16,
  );

  /// 成功时产出的结束原因。
  String? finishReason = 'stop';

  /// 额外记录创建参数里的协议标识（用于断言协议被原样传递）。
  String? lastProtocolId;

  @override
  Result<AiProvider> create({
    required String alias,
    required String protocolId,
    required String baseUrl,
    required String modelId,
    required String apiKey,
  }) {
    createdCount++;
    lastProtocolId = protocolId;
    lastApiKey = apiKey;
    return Ok<AiProvider>(_FakeProvider(this));
  }
}

final class _FakeProvider implements AiProvider {
  _FakeProvider(this._factory);

  final FakeAiProviderFactory _factory;

  @override
  Stream<AiEvent> generate(AiRequest request) async* {
    _factory.lastRequest = request;
    if (_factory.untypedFailure != null) {
      throw _factory.untypedFailure!;
    }
    final AppError? failure = _factory.failure;
    if (failure != null) {
      throw failure;
    }
    for (final String delta in _factory.deltas) {
      yield AiDelta(delta);
    }
    final AiUsage? usage = _factory.usage;
    if (usage != null) {
      yield usage;
    }
    yield AiDone(finishReason: _factory.finishReason);
  }
}

/// 一个不会返回任何事件的 provider（用于「空流」边界）。
final class SilentAiProvider implements AiProvider {
  @override
  Stream<AiEvent> generate(AiRequest request) => const Stream<AiEvent>.empty();
}

/// 断言用：协议标识的稳定字符串。
String protocolIdOf(AiProtocol protocol) => protocol.id;
