// AI 流式调用的超时、取消与停滞检测（T026；SET-036 默认值、架构 4.5）。
//
// 三条规则来自架构 4.5，且都是**必须**在这里落实的（放到调用点上就一定会有一处漏掉）：
//   1) **首响应 45 秒**（SET-036 firstResponseSeconds）：从发出请求到收到第一个字节。
//      连接建立但服务商不吐字是最常见的一类挂起；
//   2) **流停滞 30 秒**（SET-036 streamStallSeconds）：两个字节之间的最大间隔。只有
//      首响应超时会漏掉「开头正常、中途卡住」——那种情况下用户会看着半句话无限等；
//   3) **取消**：用户取消后必须立刻停止读取并结束流，而不是等下一个字节到达。
//
// 为什么用「每次字节到达时重置的计时器」而不是一个总时长：总时长会把长输出误杀
// （一个 8k token 的答案可能合理地超过 45 秒），而停滞检测只关心「是否还在流动」。
// 单次硬时限 120 秒（架构 4.5）属于任务层（T029 的队列），不在这里实现——它与
// 「一次流是否还在动」是两个不同的问题。
//
// 取消的优先级高于超时：用户取消是我们能确定的原因，而超时只是「没等到」。
library;

import 'dart:async';

import 'package:flux/core/core.dart';
import 'package:flux/features/ai/domain/ai_message.dart';

/// 一次流式调用的时限配置。
final class AiStreamTimeouts {
  /// 构造时限（默认即 SET-036 的口径）。
  const AiStreamTimeouts({
    this.firstResponse = const Duration(seconds: 45),
    this.streamStall = const Duration(seconds: 30),
  });

  /// 首响应上限（SET-036：默认 45 秒，范围 10–120）。
  final Duration firstResponse;

  /// 流停滞上限（SET-036：默认 30 秒，范围 10–120）。
  final Duration streamStall;
}

/// 给一个字节流套上首响应、停滞与取消。
///
/// 实现要点：
///   - 用 [StreamTransformer] 而不是在适配器里手写 listen 循环，这样两个协议
///     （以及 T027 的 Anthropic）共用**同一份**时限语义，不会出现「Chat Completions
///     有停滞检测、Responses 没有」；
///   - 取消通过订阅的 `cancel()` 实现：取消后底层 HTTP 连接会被 http 包关闭，
///     因此不是「假装不读了」而是真的停止接收；
///   - 定时器在正常结束时**必须**清掉，否则测试里会留下 pending timer（比真实泄漏
///     更难发现的问题：用例之间互相污染）。
Stream<List<int>> guardAiByteStream(
  Stream<List<int>> source, {
  required Uri endpoint,
  required AiStreamTimeouts timeouts,
  required AiCancellation cancellation,
  String limitKindPrefix = 'ai',
}) {
  late StreamController<List<int>> controller;
  StreamSubscription<List<int>>? subscription;
  Timer? timer;
  bool finished = false;

  void finish() {
    if (finished) {
      return;
    }
    finished = true;
    timer?.cancel();
    timer = null;
  }

  void failWith(AppError error) {
    if (finished) {
      return;
    }
    finish();
    // 先取消底层订阅再发错误：否则服务商的字节可能在错误之后继续到达，
    // 消费者会看到一个「已经失败但仍然有数据」的流。
    unawaited(subscription?.cancel() ?? Future<void>.value());
    if (!controller.isClosed) {
      controller.addError(error);
      unawaited(controller.close());
    }
  }

  void arm(Duration duration, String limitKind) {
    timer?.cancel();
    timer = Timer(duration, () {
      failWith(
        DeadlineExceededError(
          limitKind: '$limitKindPrefix$limitKind',
          limit: duration,
        ),
      );
    });
  }

  void onCancel() => failWith(CancelledError(reason: '请求已取消'));

  controller = StreamController<List<int>>(
    onListen: () {
      cancellation.addListener(onCancel);
      // 首响应计时从**订阅时**开始：在此之前还没有发生任何 IO。
      arm(timeouts.firstResponse, 'FirstResponse');
      subscription = source.listen(
        (List<int> chunk) {
          if (finished) {
            return;
          }
          if (chunk.isEmpty) {
            // 空分块不重置停滞计时：它不是「有数据流动」的证据。
            return;
          }
          arm(timeouts.streamStall, 'StreamStall');
          controller.add(chunk);
        },
        onError: (Object error, StackTrace stackTrace) {
          if (finished) {
            return;
          }
          finish();
          controller.addError(error, stackTrace);
          unawaited(controller.close());
        },
        onDone: () {
          if (finished) {
            return;
          }
          finish();
          unawaited(controller.close());
        },
        cancelOnError: false,
      );
    },
    onCancel: () {
      finish();
      cancellation.removeListener(onCancel);
      return subscription?.cancel();
    },
  );
  return controller.stream;
}
