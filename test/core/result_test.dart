// Result<T> 与 Clock 测试（T007）。
//
// 文件内出现的 `sk-...` 字样是**假**凭据常量，仅用于验证 toString 不泄漏秘密。

import 'package:flutter_test/flutter_test.dart';

import 'package:flux/core/core.dart';

void main() {
  group('Result<T>', () {
    test('Ok 暴露值且错误为空', () {
      const Result<int> result = Ok<int>(42);
      expect(result.isOk, isTrue);
      expect(result.isErr, isFalse);
      expect(result.valueOrNull, 42);
      expect(result.errorOrNull, isNull);
      expect(result.getOrElse(0), 42);
    });

    test('Err 暴露类型化错误且无值', () {
      final Result<int> result = Err<int>(CancelledError());
      expect(result.isErr, isTrue);
      expect(result.valueOrNull, isNull);
      expect(result.errorOrNull, isA<CancelledError>());
      expect(result.getOrElse(7), 7);
    });

    test('map 只作用于成功分支', () {
      expect(const Ok<int>(2).map((int v) => v * 3).unwrap(), 6);
      final Result<String> failed = Err<int>(StorageError(operation: 'read'))
          .map((int v) => '$v');
      expect(failed.isErr, isTrue);
      expect(failed.errorOrNull, isA<StorageError>());
    });

    test('flatMap 串接多个可能失败的步骤', () {
      Result<int> halve(int value) => value.isEven
          ? Ok<int>(value ~/ 2)
          : Err<int>(ValidationError(field: 'value', reason: '必须为偶数'));

      expect(const Ok<int>(8).flatMap(halve).unwrap(), 4);
      final Result<int> failed = const Ok<int>(7).flatMap(halve);
      expect(failed.isErr, isTrue);
      expect(failed.errorOrNull, isA<ValidationError>());

      // 已经是错误时，后续步骤不再执行。
      var invoked = false;
      final Result<int> shortCircuit = Err<int>(CancelledError())
          .flatMap((int v) {
            invoked = true;
            return Ok<int>(v);
          });
      expect(invoked, isFalse);
      expect(shortCircuit.isErr, isTrue);
    });

    test('recover 在失败时提供替换结果', () {
      final Result<int> recovered = Err<int>(
        CancelledError(),
      ).recover((AppError error) => Ok<int>(error is CancelledError ? 0 : -1));
      expect(recovered.unwrap(), 0);

      final Result<int> untouched = const Ok<int>(5)
          .recover((AppError error) => const Ok<int>(-1));
      expect(untouched.unwrap(), 5);
    });

    test('unwrap 成功返回值、失败抛出所携带的 AppError', () {
      expect(const Ok<String>('ok').unwrap(), 'ok');
      expect(
        () => Err<String>(CancelledError()).unwrap(),
        throwsA(isA<CancelledError>()),
      );
    });

    test('静态工厂 ok/err 与构造器等价', () {
      expect(Result.ok<int>(1), isA<Ok<int>>());
      expect(Result.err<int>(CancelledError()), isA<Err<int>>());
    });

    test('Unit 用于“无成功值”的场景', () {
      final Result<void> done = okUnit();
      expect(done.isOk, isTrue);

      final Result<void> failed = errUnit(StorageError(operation: 'delete'));
      expect(failed.isErr, isTrue);
      expect(failed.errorOrNull, isA<StorageError>());
    });

    test('toString 不泄漏秘密', () {
      // 假凭据（非真实 Key），仅用于断言 toString 会脱敏。
      const String key = 'sk-abcdef1234567890abcdef1234567890';
      final Result<int> failed = Err<int>(
        NetworkError(uri: 'https://example.com/?token=$key'),
      );
      expect(failed.toString(), isNot(contains(key)));
    });
  });

  group('Clock', () {
    test('FakeClock 从指定起点开始且可推进', () {
      final FakeClock clock = FakeClock(start: DateTime.utc(2026, 5, 1, 8));
      expect(clock.now(), DateTime.utc(2026, 5, 1, 8));
      expect(clock.monotonic(), Duration.zero);

      clock.advance(const Duration(minutes: 10));
      expect(clock.now(), DateTime.utc(2026, 5, 1, 8, 10));
      expect(clock.monotonic(), const Duration(minutes: 10));
    });

    test('FakeClock 忽略负向推进，避免时光倒流', () {
      final FakeClock clock = FakeClock();
      final DateTime before = clock.now();
      clock.advance(const Duration(minutes: -5));
      expect(clock.now(), before);
      expect(clock.monotonic(), Duration.zero);
    });

    test('FakeClock.set 可模拟设备时钟被改动', () {
      final FakeClock clock = FakeClock(start: DateTime.utc(2026, 5, 1));
      clock.set(DateTime.utc(2026, 5, 1, 2));
      expect(clock.now(), DateTime.utc(2026, 5, 1, 2));
      expect(clock.monotonic(), const Duration(hours: 2));
    });

    test('FakeClock 返回 UTC，与“时间按 UTC 存储”一致', () {
      final FakeClock clock = FakeClock(start: DateTime(2026, 5, 1, 8));
      expect(clock.now().isUtc, isTrue);
    });

    test('SystemClock 返回 UTC 且单调时间不倒退', () {
      const SystemClock clock = SystemClock();
      expect(clock.now().isUtc, isTrue);
      final Duration first = clock.monotonic();
      final Duration second = clock.monotonic();
      expect(second >= first, isTrue, reason: '单调时间不得倒退');
    });

    test('两种实现共享同一 Clock 接口，可互换注入', () {
      final List<Clock> clocks = <Clock>[const SystemClock(), FakeClock()];
      for (final Clock clock in clocks) {
        expect(clock.now(), isA<DateTime>());
        expect(clock.monotonic(), isA<Duration>());
      }
    });
  });
}
