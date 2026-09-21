// 类型化错误与脱敏测试（T007）。
//
// 关键验收：每个错误子类都能构造，且 message 在输入含 token/API Key 时
// 不包含秘密值（架构第 8 节、SET-082）。

import 'package:flutter_test/flutter_test.dart';

import 'package:flux/core/core.dart';

/// 测试用**假**凭据：形如真实 Key 的固定字符串，但只是本文件内的常量，
/// 不指向任何真实账号或服务。保留常见前缀是为了让脱敏规则能被真实触发。
const String _fakeKey = 'sk-abcdef1234567890abcdef1234567890';
const String _fakeToken = 'ghp_abcdefghijklmnopqrstuvwx1234';

void main() {
  group('错误子类构造', () {
    test('NetworkError 携带脱敏 URL、状态码与重试语义', () {
      final NetworkError error = NetworkError(
        uri: 'https://example.com/feed.xml?page=2',
        statusCode: 503,
        reason: 'service unavailable',
      );
      expect(error.kind, 'network');
      expect(error.statusCode, 503);
      expect(error.isRetryable, isTrue);
      expect(error.isServerSideFailure, isTrue);
      expect(error.message, contains('503'));
      expect(error.message, contains('feed.xml'));
      expect(error.message, contains('service unavailable'));
    });

    test('NetworkError 区分客户端错误与可重试错误', () {
      final NetworkError notFound = NetworkError(
        uri: 'https://example.com',
        statusCode: 404,
      );
      expect(notFound.isServerSideFailure, isFalse);

      final NetworkError rateLimited = NetworkError(
        uri: 'https://example.com',
        statusCode: 429,
      );
      expect(rateLimited.isServerSideFailure, isTrue);

      final NetworkError offline = NetworkError(uri: 'https://example.com');
      expect(offline.statusCode, isNull);
      expect(offline.isServerSideFailure, isTrue, reason: '连接失败应可重试');
    });

    test('StorageError 默认不可重试，并可标记目标缺失', () {
      final StorageError error = StorageError(
        operation: 'openDatabase',
        detail: 'unable to open database file',
      );
      expect(error.kind, 'storage');
      expect(error.isRetryable, isFalse);
      expect(error.isMissing, isFalse);
      expect(error.message, contains('openDatabase'));

      final StorageError missing = StorageError(
        operation: 'readFile',
        isMissing: true,
      );
      expect(missing.isMissing, isTrue);
    });

    test('ParseError 记录来源、位置与结构性原因', () {
      final ParseError error = ParseError(
        source: 'feed:12',
        detail: 'unexpected end of entity',
        offset: 41,
      );
      expect(error.kind, 'parse');
      expect(error.source, 'feed:12');
      expect(error.offset, 41);
      expect(error.isRetryable, isFalse);
      expect(error.message, contains('feed:12'));
      expect(error.message, contains('41'));
    });

    test('CancelledError 明确表达“取消不等于失败”', () {
      final CancelledError error = CancelledError(reason: '用户返回上一页');
      expect(error.kind, 'cancelled');
      expect(error.isRetryable, isFalse);
      expect(error.message, contains('取消'));
      expect(error.message, contains('用户返回上一页'));
    });

    test('BudgetExhaustedError 记录类别、已用与上限，并算出剩余', () {
      final BudgetExhaustedError error = BudgetExhaustedError(
        limitKind: 'tokens',
        limit: 100000,
        consumed: 100000,
      );
      expect(error.kind, 'budgetExhausted');
      expect(error.limit, 100000);
      expect(error.consumed, 100000);
      expect(error.remaining, 0);
      expect(error.message, contains('100000'));

      final BudgetExhaustedError partial = BudgetExhaustedError(
        limitKind: 'totalMinutes',
        limit: 10,
        consumed: 7,
      );
      expect(partial.remaining, 3);
    });

    test('DeadlineExceededError 用毫秒表达时限，避免精度误读', () {
      final DeadlineExceededError error = DeadlineExceededError(
        limitKind: 'firstResponse',
        limit: const Duration(seconds: 45),
        elapsed: const Duration(seconds: 46),
      );
      expect(error.kind, 'deadlineExceeded');
      expect(error.limit, const Duration(seconds: 45));
      expect(error.message, contains('45000ms'));
      expect(error.message, contains('46000ms'));
    });

    test('ProviderError 记录 provider/kind/状态码', () {
      final ProviderError error = ProviderError(
        provider: 'openai-main',
        kind: 'unauthorized',
        statusCode: 401,
        detail: 'invalid api key',
      );
      expect(error.kind, 'unauthorized');
      expect(error.provider, 'openai-main');
      expect(error.statusCode, 401);
      expect(error.message, contains('openai-main'));
      expect(error.message, contains('unauthorized'));
      expect(error.isRetryable, isFalse, reason: '认证失败不应自动重试');
    });

    test('ValidationError 记录字段、原因与被拒值', () {
      final ValidationError error = ValidationError(
        field: 'SET-059',
        reason: '超出 1–60 分钟范围',
        value: '90',
      );
      expect(error.kind, 'validation');
      expect(error.field, 'SET-059');
      expect(error.value, '90');
      expect(error.message, contains('SET-059'));
    });

    test('StateTransitionError 记录失败原因与两端状态', () {
      final StateTransitionError error = StateTransitionError(
        failure: StateTransitionFailure.illegalTransition,
        from: TaskStatus.queued,
        to: TaskStatus.succeeded,
        taskId: 'task-9',
      );
      expect(error.kind, 'stateTransition');
      expect(error.failure, StateTransitionFailure.illegalTransition);
      expect(error.message, contains('queued'));
      expect(error.message, contains('succeeded'));
      expect(error.message, contains('task-9'));
    });
  });

  group('message 脱敏', () {
    test('NetworkError 的 URL token 参数被遮盖', () {
      final NetworkError error = NetworkError(
        uri: 'https://api.example.com/feed?token=$_fakeToken&page=2',
        statusCode: 403,
      );
      expect(error.message, isNot(contains(_fakeToken)));
      expect(error.message, isNot(contains('ghp_')));
      expect(error.message, contains('***'));
      // 非秘密参数保留，便于定位问题。
      expect(error.message, contains('page=2'));
    });

    test('NetworkError 的 userinfo 凭据被遮盖', () {
      final NetworkError error = NetworkError(
        uri: 'https://user:$_fakeKey@example.com/private.xml',
      );
      expect(error.message, isNot(contains(_fakeKey)));
      expect(error.message, contains('example.com'));
    });

    test('StorageError 的 detail 中秘密串被遮盖', () {
      final StorageError error = StorageError(
        operation: 'writeSecret',
        detail: 'failed while writing api_key=$_fakeKey',
      );
      expect(error.message, isNot(contains(_fakeKey)));
      expect(error.message, contains('api_key=***'));
    });

    test('ParseError 的 detail 中 Authorization 头被整体遮盖', () {
      // 只吃第一个词会把 Bearer 后的 token 留在消息里，因此按整行值遮盖。
      final ParseError error = ParseError(
        source: 'ai.result',
        detail: 'request header Authorization: Bearer $_fakeKey rejected',
      );
      expect(error.message, isNot(contains(_fakeKey)));
      expect(error.message, contains('Authorization: ***'));
    });

    test('ProviderError 的 detail 中 sk- 前缀凭据被遮盖', () {
      final ProviderError error = ProviderError(
        provider: 'deepseek',
        kind: 'unauthorized',
        detail: 'api key $_fakeKey is invalid',
      );
      expect(error.message, isNot(contains(_fakeKey)));
      expect(error.message, contains('***'));
    });

    test('cause 携带原始异常对象，但不进入默认字符串输出', () {
      final Object raw = Exception('raw failure referencing $_fakeKey');
      final NetworkError error = NetworkError(
        uri: 'https://example.com',
        cause: raw,
      );
      expect(error.cause, same(raw));
      // 默认输出不展开 cause，避免把底层对象里的凭据带进日志。
      expect(error.toString(), isNot(contains(_fakeKey)));
      expect(error.toString(), contains('NetworkError'));
    });

    test('toLogString 携带分类、可重试标记与脱敏消息', () {
      final ValidationError error = ValidationError(
        field: 'readingState',
        reason: '非法枚举值',
      );
      final String log = error.toLogString();
      expect(log, contains('ValidationError'));
      expect(log, contains('kind=validation'));
      expect(log, contains('retryable=false'));
    });

    test('空/无 detail 的构造不会产生多余的连接符', () {
      final StorageError error = StorageError(operation: 'vacuum');
      expect(error.message, '存储操作失败：vacuum');

      final ParseError parse = ParseError(source: 'opml', detail: '');
      expect(parse.message, '解析失败：opml — ');
    });
  });

  group('exhaustive switch 可用', () {
    test('sealed 层级可被穷尽匹配，无需 default 分支', () {
      final List<AppError> errors = <AppError>[
        NetworkError(uri: 'https://example.com'),
        StorageError(operation: 'open'),
        ParseError(source: 'feed', detail: 'bad xml'),
        CancelledError(),
        BudgetExhaustedError(limitKind: 'tokens', limit: 1, consumed: 1),
        DeadlineExceededError(
          limitKind: 'taskTotal',
          limit: const Duration(minutes: 10),
        ),
        ProviderError(provider: 'p', kind: 'unavailable'),
        ValidationError(field: 'f', reason: 'r'),
        StateTransitionError(
          failure: StateTransitionFailure.illegalTransition,
          from: TaskStatus.queued,
          to: TaskStatus.failed,
          taskId: 't',
        ),
      ];

      final List<String> kinds = errors.map((AppError error) {
        return switch (error) {
          NetworkError() => 'network',
          StorageError() => 'storage',
          ParseError() => 'parse',
          CancelledError() => 'cancelled',
          BudgetExhaustedError() => 'budget',
          DeadlineExceededError() => 'deadline',
          ProviderError() => 'provider',
          ValidationError() => 'validation',
          StateTransitionError() => 'transition',
        };
      }).toList();

      expect(kinds, <String>[
        'network',
        'storage',
        'parse',
        'cancelled',
        'budget',
        'deadline',
        'provider',
        'validation',
        'transition',
      ]);
    });

    test('所有错误都实现 Exception，可参与现有 try/catch 体系', () {
      final AppError error = CancelledError();
      expect(error, isA<Exception>());
    });
  });
}
