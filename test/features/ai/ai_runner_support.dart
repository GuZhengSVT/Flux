// T029 测试替身：按脚本产出「成功 / 失败 / 挂起」的适配器，以及可控的等待调度。
//
// 为什么不用 T025 的 FakeAiProviderFactory：它只能表达「每次调用都一样」，而五次规则的
// 验收核心恰恰是**逐次不同**（前四次失败、第五次才切模型；第 3 次时 deadline 已到）。
// 脚本化替身把「第几次调用发生什么」写在测试里，断言就能直接对应到规则条文，而不是靠
// 一串共享可变状态拼出来。
library;

import 'dart:async';

import 'package:flux/core/core.dart';
import 'package:flux/features/ai/application/ai_task_budget.dart';
import 'package:flux/features/ai/domain/ai_credential_store.dart';
import 'package:flux/features/ai/domain/ai_message.dart';
import 'package:flux/features/ai/domain/ai_model.dart';
import 'package:flux/features/ai/domain/ai_protocol.dart';
import 'package:flux/features/ai/domain/ai_provider.dart';
import 'package:flux/features/ai/domain/tool_call.dart';

/// 一次调用的剧本。
sealed class AiAttemptScript {
  /// 构造剧本。
  const AiAttemptScript();

  /// 调用开始时的回调（测试用它做「第 2 次尝试中取消」这类时点动作）。
  void Function()? get onStart;

  /// 本次调用「耗时」：调用进行中推进注入的假时钟。
  ///
  /// 时间必须在**调用进行中**流逝，否则「第 3 次尝试时总时限已到」无法构造：
  /// 只在调用之间推进，队列层看不到任何调用耗时。
  Duration get advanceClockBy;
}

/// 成功：产出若干增量 + usage + 结束原因。
final class ScriptSuccess extends AiAttemptScript {
  /// 构造成功剧本。
  const ScriptSuccess({
    this.deltas = const <String>['好', '的'],
    this.usage = const AiUsage(
      inputTokens: 20,
      outputTokens: 2,
      totalTokens: 22,
    ),
    this.finishReason = 'stop',
    this.onStart,
    this.advanceClockBy = Duration.zero,
    this.toolCalls = const <ToolCall>[],
  });

  /// 增量文本。
  final List<String> deltas;

  /// usage；null 表示协议未提供（此时预算按字符估算）。
  final AiUsage? usage;

  /// 结束原因（回答 length 表示输出被截断）。
  final String? finishReason;

  /// 本轮请求的工具调用（T032 的工具循环用它构造「模型请求了工具」这一轮）。
  final List<ToolCall> toolCalls;

  @override
  final void Function()? onStart;

  @override
  final Duration advanceClockBy;
}

/// 失败：抛出类型化错误；可带已经收到的部分文本（模拟流中断）。
final class ScriptFailure extends AiAttemptScript {
  /// 构造失败剧本。
  const ScriptFailure({
    required this.error,
    this.partialText = '',
    this.finishReason,
    this.usage,
    this.onStart,
    this.advanceClockBy = Duration.zero,
  });

  /// 抛出的错误。
  final AppError error;

  /// 失败前已经产出的文本（流中断时的半句话）。
  final String partialText;

  /// 结束原因。
  final String? finishReason;

  /// 失败前已经收到的 usage（服务商先发用量、随后断流的真实形态）。
  final AiUsage? usage;

  @override
  final void Function()? onStart;

  @override
  final Duration advanceClockBy;
}

/// 挂起：一个字节都不发，直到被取消。
///
/// 用于验证「单次硬时限真的会打断一次卡住的调用」：卡住的流不会有任何事件，只靠
/// 事件驱动的检查永远等不到，必须由队列层的真实计时器打断。
final class ScriptHang extends AiAttemptScript {
  /// 构造挂起剧本。
  const ScriptHang({this.onStart});

  @override
  final void Function()? onStart;

  @override
  Duration get advanceClockBy => Duration.zero;
}

/// 一个脚本化工厂：按模型别名给出一串剧本，逐个消费。
final class ScriptedAiFactory implements AiProviderFactory {
  /// 构造工厂；[scriptClock] 用于在调用期间推进假时钟。
  ScriptedAiFactory(this.scriptsByAlias, {this.scriptClock});

  /// 别名 → 该模型的剧本队列（按调用顺序消费；用尽后重复最后一条）。
  ///
  /// 重复最后一条是有意的：默认「该模型一直不响应」不需要把剧本写五遍，写一遍就能
  /// 表达「反复超时」。
  final Map<String, List<AiAttemptScript>> scriptsByAlias;

  /// 调用期间推进的时钟。
  FakeClock? scriptClock;

  /// 已发起的调用次数（按别名）。
  final Map<String, int> issuedByAlias = <String, int>{};

  /// 调用顺序（别名列表）。
  final List<String> callOrder = <String>[];

  /// 收到的请求（用于断言请求形状，例如保守输出上限）。
  final List<AiRequest> requests = <AiRequest>[];

  /// 同时在途的调用数与峰值（验证并发上限）。
  int _inFlight = 0;

  /// 曾经同时在途的最大调用数。
  int peakInFlight = 0;

  /// 全部调用次数。
  int get totalIssued =>
      issuedByAlias.values.fold(0, (int sum, int value) => sum + value);

  @override
  Result<AiProvider> create({
    required String alias,
    required String protocolId,
    required String baseUrl,
    required String modelId,
    required String apiKey,
  }) => Ok<AiProvider>(_ScriptedProvider(this, alias));

  AiAttemptScript _nextScript(String alias) {
    final List<AiAttemptScript> scripts =
        scriptsByAlias[alias] ?? const <AiAttemptScript>[];
    final int issued = issuedByAlias[alias] ?? 0;
    issuedByAlias[alias] = issued + 1;
    callOrder.add(alias);
    if (scripts.isEmpty) {
      return ScriptFailure(error: CancelledError(reason: '无剧本'));
    }
    return issued < scripts.length ? scripts[issued] : scripts.last;
  }

  void _enter() {
    _inFlight++;
    if (_inFlight > peakInFlight) {
      peakInFlight = _inFlight;
    }
  }

  void _leave() => _inFlight--;
}

final class _ScriptedProvider implements AiProvider {
  _ScriptedProvider(this._factory, this._alias);

  final ScriptedAiFactory _factory;
  final String _alias;

  @override
  Stream<AiEvent> generate(AiRequest request) async* {
    final AiAttemptScript script = _factory._nextScript(_alias);
    _factory.requests.add(request);
    _factory._enter();
    script.onStart?.call();
    try {
      switch (script) {
        case ScriptHang():
          // 挂起：等到被取消才结束。适配器契约是「取消后停止读取并结束流」，
          // 因此这里抛 CancelledError，而不是安静地把流关掉。
          final Completer<void> cancelled = Completer<void>();
          void onCancel() {
            if (!cancelled.isCompleted) {
              cancelled.complete();
            }
          }

          request.cancellation.addListener(onCancel);
          try {
            await cancelled.future;
          } finally {
            request.cancellation.removeListener(onCancel);
          }
          throw CancelledError(reason: request.cancellation.reason);
        case ScriptSuccess(
          :final List<String> deltas,
          :final AiUsage? usage,
          :final String? finishReason,
          :final List<ToolCall> toolCalls,
        ):
          if (request.cancellation.isCancelled) {
            throw CancelledError(reason: request.cancellation.reason);
          }
          for (final String delta in deltas) {
            yield AiDelta(delta);
          }
          if (usage != null) {
            yield usage;
          }
          if (toolCalls.isNotEmpty) {
            yield AiToolCalls(toolCalls);
          }
          yield AiDone(finishReason: finishReason);
        case ScriptFailure(
          :final AppError error,
          :final String partialText,
          :final AiUsage? usage,
        ):
          if (partialText.isNotEmpty) {
            yield AiDelta(partialText);
          }
          if (usage != null) {
            yield usage;
          }
          throw error;
      }
    } finally {
      final Duration advance = script.advanceClockBy;
      if (advance > Duration.zero) {
        _factory.scriptClock?.advance(advance);
      }
      _factory._leave();
    }
  }
}

/// 立即返回并把时间「推进」的等待调度。
///
/// 真实等待会把超时用例变成慢用例，而这里要验证的是「等待是否发生、等了多久、
/// 是否计入总时限」——三者都能在假时钟上精确断言。
final class AdvancingDelayScheduler implements AiDelayScheduler {
  /// 绑定假时钟（每次等待都会推进它）。
  AdvancingDelayScheduler(this.clock);

  /// 假时钟。
  final FakeClock clock;

  /// 发生过的等待（按顺序）。
  final List<Duration> waits = <Duration>[];

  @override
  Future<void> delay(Duration duration) async {
    waits.add(duration);
    clock.advance(duration);
  }
}

/// 一个可切换的离线端口。
final class ScriptedNetworkConditions implements NetworkConditionPort {
  /// 构造端口。
  ScriptedNetworkConditions({this.offline = false, this.metered = false});

  /// 是否回答「当前无网络」。
  bool offline;

  /// 是否回答「计费网络」。
  bool metered;

  @override
  Future<bool> isMetered() async => metered;

  @override
  Future<bool> isOffline() async => offline;
}

/// 构造一个按顺序的启用模型列表（sortOrder 即列表位置）。
List<AiModel> scriptedModels(List<String> aliases) => <AiModel>[
  for (int index = 0; index < aliases.length; index++)
    AiModel(
      id: index + 1,
      alias: aliases[index],
      protocol: AiProtocol.openAiChatCompletions,
      baseUrl: 'https://${aliases[index]}.example.com',
      modelId: '${aliases[index]}-model',
      sortOrder: index,
    ),
];

/// 一个总是给出 Key 的凭据端口（Key 值不参与任何断言，也不进日志）。
final class AlwaysCredentialStore implements AiCredentialStore {
  /// 构造端口。
  const AlwaysCredentialStore();

  @override
  Future<Result<String>> read(String alias) async =>
      const Ok<String>('test-key');

  @override
  Future<Result<void>> write(String alias, String apiKey) async => okUnit();

  @override
  Future<Result<void>> delete(String alias) async => okUnit();

  @override
  Future<Result<bool>> exists(String alias) async => const Ok<bool>(true);

  @override
  Future<bool> isAvailable() async => true;
}

/// 一个永远没有 Key 的凭据端口（验证「缺凭据是配置错误，不消耗五次额度」）。
final class MissingCredentialStore implements AiCredentialStore {
  /// 构造端口。
  const MissingCredentialStore();

  @override
  Future<Result<String>> read(String alias) async => Err<String>(
    StorageError(operation: 'read', detail: 'missing', isMissing: true),
  );

  @override
  Future<Result<void>> write(String alias, String apiKey) async => okUnit();

  @override
  Future<Result<void>> delete(String alias) async => okUnit();

  @override
  Future<Result<bool>> exists(String alias) async => const Ok<bool>(false);

  @override
  Future<bool> isAvailable() async => true;
}

/// 记录全部诊断消息的 sink（断言「不记 prompt / 不记 Key」）。
final class RecordingSink implements DiagnosticSink {
  /// 全部消息。
  final List<String> messages = <String>[];

  @override
  void record(DiagnosticSeverity severity, String message, {String? tag}) =>
      messages.add(message);

  @override
  void error(String message, {String? tag}) => messages.add(message);

  @override
  void warning(String message, {String? tag}) => messages.add(message);

  @override
  void info(String message, {String? tag}) => messages.add(message);
}

/// 一个把每次迁移都记下来的观察者（T030 会用它落库）。
final class SnapshotRecorder {
  /// 收到的快照。
  final List<TaskSnapshot> snapshots = <TaskSnapshot>[];

  /// 状态序列（便于断言「经过 running 再到终态」）。
  List<TaskStatus> get statuses =>
      snapshots.map((TaskSnapshot s) => s.status).toList(growable: false);

  /// 回调入口。
  void call(TaskSnapshot snapshot) => snapshots.add(snapshot);
}
